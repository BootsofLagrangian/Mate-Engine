"""Background Codex jobs: one subprocess per job, JSONL events streamed to the owner.

`codex exec --json` is spawned with an argv list (no shell), a fixed working
root (MATE_JOB_ROOT) and the configured sandbox (read-only unless
MATE_JOB_SANDBOX=workspace-write). The prompt travels over stdin so it can never
be parsed as an option. Completion is reported only after the real exit status.
"""
import json
import os
import shlex
import signal
from collections import deque
import subprocess
import threading
import time

STATUSES = ('starting', 'running', 'completed', 'failed', 'cancelled')
MAX_DETAIL = 4000


def build_argv(settings, model=None):
    # MATE_CODEX_BIN may carry an interpreter prefix (tests use "python fake_codex.py"); still no shell.
    argv = shlex.split(settings['codex']) + ['exec', '--json', '--skip-git-repo-check', '--color', 'never',
                                            '-C', settings['root'], '-s', settings['sandbox']]
    model = model or settings.get('model')
    if model:
        argv += ['-m', model]
    argv.append('-')  # prompt from stdin
    return argv


def summarize_item(item):
    """Map one codex item to (message, detail) for the job panel; None to skip."""
    if not isinstance(item, dict):
        return None
    kind = item.get('type')
    if kind == 'agent_message':
        text = (item.get('text') or '').strip()
        return (text[:200], text) if text else None
    if kind == 'command_execution':
        command = item.get('command') or ''
        status = item.get('status') or ''
        code = item.get('exit_code')
        message = f'$ {command}'[:200]
        if status == 'completed' or code is not None:
            message = f'exit {code}: {command}'[:200]
        return message, (item.get('aggregated_output') or '')[:MAX_DETAIL]
    if kind == 'file_change':
        changes = item.get('changes') or []
        paths = [c.get('path') for c in changes if isinstance(c, dict)]
        return ('edited ' + ', '.join(p for p in paths if p))[:200], json.dumps(changes)[:MAX_DETAIL]
    if kind == 'mcp_tool_call':
        return f"tool {item.get('server')}/{item.get('tool')} {item.get('status') or ''}"[:200], None
    if kind == 'web_search':
        return f"search: {item.get('query') or ''}"[:200], None
    if kind == 'reasoning':
        return None
    if kind == 'error':
        return ('error: ' + str(item.get('message') or ''))[:200], None
    return None


class Job:
    def __init__(self, job_id, prompt, character, settings, emit, on_finish=None):
        self.job_id = job_id
        self.prompt = prompt
        self.character = character
        self.settings = settings
        self.emit = emit  # thread-safe callback(event dict)
        self.on_finish = on_finish  # callback(job) after final status
        self.process = None
        self.status = None
        self.final_message = ''
        self.error = None
        self.exit_code = None
        self.cancel_requested = threading.Event()
        self.started_at = None
        self.thread = None
        self._lock = threading.Lock()

    def event(self, status, message='', detail=None):
        payload = {'type': 'job', 'job_id': self.job_id, 'character': self.character, 'status': status, 'message': message,
                   'workspace': self.settings.get('root'), 'sandbox': self.settings.get('sandbox')}
        if detail:
            payload['detail'] = str(detail)[:MAX_DETAIL]
        return payload

    def start(self):
        self.thread = threading.Thread(target=self._run, daemon=True, name=f'job-{self.job_id}')
        self.status = 'starting'
        self.thread.start()

    def cancel(self):
        self.cancel_requested.set()
        with self._lock:
            proc = self.process
        if proc and proc.poll() is None:
            self._terminate(proc)
            killer = threading.Timer(1.0, self._terminate, args=(proc, True))
            killer.daemon = True
            killer.start()

    @staticmethod
    def _terminate(proc, force=False):
        try:
            if os.name == 'posix':
                os.killpg(proc.pid, signal.SIGKILL if force else signal.SIGTERM)
            elif proc.poll() is None:
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            pass

    def _finish(self, status, message, detail=None):
        with self._lock:
            if self.status in ('completed', 'failed', 'cancelled'):
                return
            self.status = status
        self.emit(self.event(status, message, detail))
        if self.on_finish:
            try:
                self.on_finish(self)
            except RuntimeError:
                pass  # owner's event loop is gone

    def _run(self):
        self.started_at = time.monotonic()
        self.status = 'starting'
        self.emit(self.event('starting', f"codex exec in {self.settings['root']} ({self.settings['sandbox']})"))
        if not self.settings.get('available'):
            self._finish('failed', '; '.join(self.settings.get('problems') or ['jobs unavailable']))
            return
        argv = build_argv(self.settings)
        env = {k: v for k, v in os.environ.items() if not k.startswith('MATE_')}
        try:
            with self._lock:
                if self.cancel_requested.is_set():
                    self.process = None
                else:
                    self.process = subprocess.Popen(argv, cwd=self.settings['root'], env=env, stdin=subprocess.PIPE,
                                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                                    encoding='utf-8', errors='replace', bufsize=1,
                                                    start_new_session=(os.name == 'posix'))
            if self.process is None:
                self._finish('cancelled', 'cancelled before start')
                return
        except OSError as exc:
            self._finish('failed', f'cannot start codex: {exc}')
            return
        proc = self.process
        try:
            proc.stdin.write(self.prompt)
            proc.stdin.close()
        except (OSError, ValueError) as exc:
            self.error = f'cannot send prompt: {exc}'
        stderr_lines = deque(maxlen=32)
        stderr_thread = threading.Thread(target=lambda: stderr_lines.extend(line[-MAX_DETAIL:] for line in proc.stderr), daemon=True)
        stderr_thread.start()
        watchdog = threading.Timer(self.settings.get('timeout_seconds') or 1800, self._timeout)
        watchdog.daemon = True
        watchdog.start()
        self.status = 'running'
        turn_failed = None
        turn_completed = False
        try:
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    self.emit(self.event('running', line[:200]))
                    continue
                if not isinstance(event, dict):
                    continue
                kind = event.get('type')
                if kind == 'item.completed' or kind == 'item.started':
                    summary = summarize_item(event.get('item'))
                    item = event.get('item') or {}
                    if item.get('type') == 'agent_message' and kind == 'item.completed':
                        self.final_message = (item.get('text') or '').strip() or self.final_message
                    if summary and (kind == 'item.completed' or item.get('type') == 'command_execution'):
                        self.emit(self.event('running', summary[0], summary[1]))
                elif kind == 'turn.completed':
                    turn_completed = True
                elif kind == 'turn.failed':
                    turn_failed = (event.get('error') or {}).get('message') or 'turn failed'
                elif kind == 'error':
                    turn_failed = event.get('message') or 'error'
                elif kind == 'turn.started':
                    self.emit(self.event('running', 'agent turn started'))
        except Exception as exc:
            turn_failed = f'invalid job output: {exc}'
            self._terminate(proc, True)
        finally:
            self.exit_code = proc.wait()
            watchdog.cancel()
            stderr_thread.join(timeout=5)
        stderr_text = ''.join(stderr_lines)[-MAX_DETAIL:]
        if self.cancel_requested.is_set():
            self._finish('cancelled', self.timeout_message or 'cancelled', stderr_text or None)
        elif self.exit_code == 0 and turn_completed and not turn_failed and not self.error:
            self._finish('completed', self.final_message[:200] or 'completed', self.final_message or None)
        else:
            reason = turn_failed or self.error or ('codex exited without turn.completed' if self.exit_code == 0 else f'codex exited with status {self.exit_code}')
            self._finish('failed', reason[:200], stderr_text or None)

    timeout_message = None

    def _timeout(self):
        self.timeout_message = 'timed out'
        self.cancel()

    def wait(self, timeout=None):
        if self.thread:
            self.thread.join(timeout)
        return self.status
