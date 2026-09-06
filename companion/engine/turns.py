"""Per-connection turn management: supersession, cancellation, event tagging.

Each connection owns at most one active turn. A new chat/audio turn cancels the
previous one. Every outbound event is tagged with turn_id and character so the
client can discard stale ones. Job acknowledgement/result turns use the
turn_id prefix 'job:' and never pre-empt a foreground user turn.
"""
import json
import logging
import threading
import time
from . import COMPANION_ROOT
from .providers.base import TurnRequest

log = logging.getLogger('engine.turns')
FORWARDED = {'start', 'text', 'phrase', 'tts_start', 'audio', 'tts_end', 'action', 'done', 'error', 'voice_error'}


def is_job_turn(turn_id):
    return isinstance(turn_id, str) and turn_id.startswith('job:')


class Turn:
    def __init__(self, req, provider, emit, root=COMPANION_ROOT):
        self.req = req
        req.defer_history = True
        self._lock = threading.RLock()
        self.ready = threading.Event()
        self.provider = provider
        self.emit = emit  # thread-safe callback(event dict)
        self.root = root
        self.cancelled = threading.Event()
        self.finished = threading.Event()
        self.thread = None
        self.outcome = None  # 'done' | 'error' | 'cancelled'
        self.result = None

    @property
    def turn_id(self):
        return self.req.turn_id

    @property
    def character(self):
        return self.req.character

    @property
    def foreground(self):
        return not is_job_turn(self.req.turn_id)

    def tag(self, event):
        event['turn_id'] = self.req.turn_id
        event['character'] = self.req.character
        return event

    def start(self):
        self.thread = threading.Thread(target=self._run, daemon=True, name=f'turn-{self.req.turn_id}')
        self.thread.start()

    def cancel(self, reason='client'):
        with self._lock:
            if self.finished.is_set() or self.cancelled.is_set():
                return False
            self.cancelled.set()
            self.outcome = 'cancelled'
            self.emit(self.tag({'type': 'cancelled', 'reason': reason}))
            return True

    def _forward(self, event):
        # Cancellation and event publication/history commit have a single order.
        with self._lock:
            if self.cancelled.is_set():
                return
            kind = event.get('type')
            if kind == 'done':
                event['ok'] = bool(event.get('text')) and self.outcome != 'error'
                self.outcome = 'done' if event['ok'] else 'error'
                self.result = event
                if event['ok'] and self.req.pending_history:
                    history, user, result = self.req.pending_history
                    history.append(self.req.session, self.character, user, result)
                self.finished.set()
            elif kind == 'error':
                self.outcome = 'error'
            self.emit(self.tag(event))
            if kind == 'audio' or (kind == 'text' and not self.req.voice):
                self.ready.set()

    def _run(self):
        from stream_pipeline import conversation_stream
        try:
            self._forward({'type': 'state', 'state': 'thinking'})
            spoke = False
            for line in conversation_stream(self.provider, self.req, self.root, self.cancelled):
                if self.cancelled.is_set():
                    break
                event = json.loads(line)
                kind = event.get('type')
                if kind not in FORWARDED:
                    continue  # ping and internal markers stay server-side
                if kind == 'audio' and not spoke:
                    spoke = True
                    self._forward({'type': 'state', 'state': 'speaking'})
                self._forward(event)
        except Exception as exc:  # never let a worker die silently
            log.exception('turn %s failed', self.req.turn_id)
            self.outcome = 'error'
            if not self.cancelled.is_set():
                self.emit(self.tag({'type': 'error', 'message': str(exc)}))
        finally:
            self.finished.set()
            if not self.cancelled.is_set():
                self.emit(self.tag({'type': 'state', 'state': 'idle'}))


def make_request(*, turn_id, character, profile, session, voice=True, text='', audio=None, audio_seconds=0.0):
    reference = profile.reference()
    ref_path, ref_text = (str(reference[0]), reference[1]) if reference else (None, None)
    return TurnRequest(turn_id=turn_id, character=character, profile=profile, session=session, voice=voice and reference is not None,
                       text=text, audio=audio, audio_seconds=audio_seconds, ref_audio_path=ref_path, reference_text=ref_text,
                       save_audio=False)
