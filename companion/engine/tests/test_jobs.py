"""Codex job tests run engine/tests/fake_codex.py (a FAKE CLI emitting real codex --json shapes)."""
import json
import os
import time
from engine.jobs import build_argv, summarize_item
from conftest import collect


def job_final(job_id):
    return lambda e: e['type'] == 'job' and e['job_id'] == job_id and e['status'] in ('completed', 'failed', 'cancelled')


def test_build_argv_is_scoped_and_shell_free(job_settings):
    argv = build_argv(job_settings)
    assert argv[-1] == '-' and '-C' in argv and argv[argv.index('-C') + 1] == job_settings['root']
    assert argv[argv.index('-s') + 1] == 'read-only' and '--json' in argv and '-m' not in argv
    argv = build_argv({**job_settings, 'sandbox': 'workspace-write', 'model': 'gpt-x'})
    assert argv[argv.index('-s') + 1] == 'workspace-write' and argv[argv.index('-m') + 1] == 'gpt-x'


def test_summarize_item_shapes():
    assert summarize_item({'type': 'agent_message', 'text': 'hi'}) == ('hi', 'hi')
    assert summarize_item({'type': 'reasoning', 'text': 'secret'}) is None
    msg, detail = summarize_item({'type': 'command_execution', 'command': 'ls', 'exit_code': 0, 'aggregated_output': 'a'})
    assert msg == 'exit 0: ls' and detail == 'a'


def test_job_completes_with_real_exit_status_and_speaks_ack_and_result(client, tmp_path, monkeypatch):
    argv_file = tmp_path / 'argv.json'
    monkeypatch.setenv('FAKE_CODEX_ARGV', str(argv_file))
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'job', 'prompt': 'list files', 'character': 'alpha', 'job_id': 'j1'})
        events = collect(ws, job_final('j1'))
        # the spoken result line follows the completion event
        events += collect(ws, lambda e: e.get('turn_id') == 'job:j1:result' and e['type'] == 'done')
    jobs = [e for e in events if e['type'] == 'job']
    assert [j['status'] for j in jobs][:2] == ['starting', 'running']
    assert jobs[-1]['status'] == 'completed' and jobs[-1]['message'].startswith('Listed the directory')
    assert all(j['workspace'] == client.app.state.job_settings['root'] and j['sandbox'] == 'read-only' for j in jobs)
    running = [j for j in jobs if j['status'] == 'running']
    assert any(j['message'] == 'exit 0: ls' and j['detail'] == 'a.txt\n' for j in running)
    assert not any('hidden' in j['message'] for j in jobs), 'reasoning items are not surfaced'
    ack = [e for e in events if e.get('turn_id') == 'job:j1:ack']
    assert any(e['type'] == 'done' and e['text'] == 'はい、始めますね。' for e in ack)
    result = [e for e in events if e.get('turn_id') == 'job:j1:result']
    assert any(e['type'] == 'done' and e['text'] == '終わりました。' and e['gesture'] == 'bow' for e in result)
    argv = json.loads(argv_file.read_text())
    assert argv[argv.index('-C') + 1] == client.app.state.job_settings['root'] and argv[-1] == '-'


def test_job_failure_reports_actual_error(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'job', 'prompt': 'please FAIL', 'character': 'alpha', 'job_id': 'j2'})
        events = collect(ws, job_final('j2'))
        events += collect(ws, lambda e: e.get('turn_id') == 'job:j2:result' and e['type'] == 'done')
    final = [e for e in events if e['type'] == 'job'][-1]
    assert final['status'] == 'failed' and final['message'] == 'fake model refused'
    assert any(e.get('turn_id') == 'job:j2:result' and e['type'] == 'done' and e['text'] == 'うまくいきませんでした。' for e in events)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'job', 'prompt': 'please CRASH', 'character': 'alpha', 'job_id': 'j3'})
        final = collect(ws, job_final('j3'))[-1]
    assert final['status'] == 'failed' and 'status 3' in final['message']


def test_cancel_job_terminates_process_and_disconnect_cancels(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'job', 'prompt': 'be SLOW', 'character': 'alpha', 'job_id': 'j4'})
        collect(ws, lambda e: e['type'] == 'job' and e['status'] == 'running' and 'sleep' in e['message'])
        ws.send_json({'type': 'job', 'prompt': 'second', 'character': 'alpha', 'job_id': 'j5'})
        rejected = collect(ws, lambda e: e['type'] == 'job' and e['job_id'] == 'j5')[-1]
        assert rejected['status'] == 'failed' and 'still running' in rejected['message']
        ws.send_json({'type': 'cancel_job', 'job_id': 'wrong'})
        ws.send_json({'type': 'cancel_job', 'job_id': 'j4'})
        final = collect(ws, job_final('j4'))[-1]
        assert final['status'] == 'cancelled'
        ws.send_json({'type': 'ping'})
        tail = collect(ws, lambda e: e['type'] == 'pong')
        assert not any(str(e.get('turn_id', '')).endswith(':result') for e in tail), 'no result speech for cancelled jobs'
        ws.send_json({'type': 'job', 'prompt': 'be SLOW again', 'character': 'alpha', 'job_id': 'j6'})
        collect(ws, lambda e: e['type'] == 'job' and e['status'] == 'running' and 'sleep' in e['message'])
        job = next(iter(client.app.state.connections)).job
    # Disconnect cancels the owned job and the subprocess actually exits.
    assert job.wait(5) == 'cancelled' and job.process.poll() is not None
    time.sleep(0.2)
    assert client.app.state.connections == set()


def test_job_speech_never_interrupts_foreground_chat(client):
    stub = client.app.state.stub
    stub.delay = 0.04
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'これは前景の会話です', 'turn_id': 'fg', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'text')
        ws.send_json({'type': 'job', 'prompt': 'quick', 'character': 'alpha', 'job_id': 'j7'})
        seen = set()

        def both(e):
            if e['type'] == 'done' and e.get('turn_id') == 'fg':
                seen.add('fg')
            if job_final('j7')(e):
                seen.add('job')
            return seen == {'fg', 'job'}
        events = collect(ws, both)
        ws.send_json({'type': 'ping'})
        events += collect(ws, lambda e: e['type'] == 'pong')
    assert not any(str(e.get('turn_id', '')).startswith('job:') for e in events), 'no ack/result speech while the user is talking'
    assert any(e['type'] == 'job' and e['status'] == 'completed' for e in events)


def test_job_speech_skipped_when_character_changed(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'job', 'prompt': 'be SLOW', 'character': 'alpha', 'job_id': 'j8'})
        collect(ws, lambda e: e.get('turn_id') == 'job:j8:ack' and e['type'] == 'done')
        ws.send_json({'type': 'chat', 'text': '切り替え', 'turn_id': 'sw', 'character': 'beta'})
        collect(ws, lambda e: e['type'] == 'done' and e['turn_id'] == 'sw')
        ws.send_json({'type': 'cancel_job', 'job_id': 'j8'})
        events = collect(ws, job_final('j8'))
        ws.send_json({'type': 'ping'})
        events += collect(ws, lambda e: e['type'] == 'pong')
    assert not any(e.get('turn_id') == 'job:j8:result' for e in events)


def test_jobs_unavailable_without_configured_root(client):
    client.app.state.job_settings = {'root': None, 'sandbox': 'read-only', 'codex': 'codex', 'model': None,
                                     'timeout_seconds': 1, 'available': False, 'problems': ['MATE_JOB_ROOT is not configured']}
    assert client.get('/health').json()['jobs'] == {'available': False, 'workspace': None, 'sandbox': 'read-only', 'problems': ['MATE_JOB_ROOT is not configured']}
    with client.websocket_connect('/ws') as ws:
        hello = ws.receive_json()
        assert hello['capabilities']['jobs'] is False
        ws.send_json({'type': 'job', 'prompt': 'x', 'character': 'alpha', 'job_id': 'j9'})
        final = collect(ws, job_final('j9'))[-1]
    assert final['status'] == 'failed' and 'MATE_JOB_ROOT' in final['message']


def test_env_job_settings_validation(monkeypatch, tmp_path):
    from engine import config
    monkeypatch.delenv('MATE_JOB_ROOT', raising=False)
    assert not config.job_settings()['available']
    monkeypatch.setenv('MATE_JOB_ROOT', str(tmp_path))
    monkeypatch.setenv('MATE_JOB_SANDBOX', 'danger-full-access')
    settings = config.job_settings()
    assert not settings['available'] and 'MATE_JOB_SANDBOX' in settings['problems'][0]
    monkeypatch.setenv('MATE_JOB_SANDBOX', 'workspace-write')
    assert config.job_settings()['available'] and config.job_settings()['root'] == str(tmp_path.resolve())


def test_job_character_does_not_implicitly_change_selection(client):
    with client.websocket_connect('/ws') as ws:
        hello = ws.receive_json()
        assert hello['character'] == 'alpha'
        ws.send_json({'type': 'job', 'prompt': 'quick', 'character': 'beta', 'job_id': 'unselected'})
        events = collect(ws, job_final('unselected'))
        ws.send_json({'type': 'ping'})
        events += collect(ws, lambda e: e['type'] == 'pong')
        assert any(e['type'] == 'job' and e.get('status') == 'completed' for e in events)
        assert not any(str(e.get('turn_id', '')).startswith('job:') for e in events)
        assert next(iter(client.app.state.connections)).character == 'alpha'
        ws.send_json({'type': 'select_character', 'character': 'beta'})
        collect(ws, lambda e: e['type'] == 'character_selected')
        ws.send_json({'type': 'job', 'prompt': 'quick', 'character': 'beta', 'job_id': 'selected'})
        events = collect(ws, lambda e: e['type'] == 'done' and e.get('turn_id') == 'job:selected:result')
        assert any(e['type'] == 'done' and e.get('turn_id') == 'job:selected:ack' for e in events)
        assert any(e['type'] == 'job' and e.get('status') == 'completed' for e in events)
        assert next(i for i, e in enumerate(events) if e['type'] == 'audio') < next(i for i, e in enumerate(events) if e['type'] == 'job')
