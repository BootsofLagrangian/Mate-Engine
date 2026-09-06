"""TEST-ONLY provider (MATE_ENGINE_PROVIDER=stub). Deterministic, no model, no GPU.

It streams a canned Japanese reply in pieces so cancellation, chunking and
history plumbing can be exercised without loading Qwen2.5-Omni.
"""
import time
from .base import Provider
from ..profiles import build_system_prompt, normalize_result


class StubProvider(Provider):
    name = 'stub'

    def __init__(self, history, delay=0.02):
        import threading
        self.history = history
        self.lock = threading.Lock()
        self.loaded = True
        self.delay = delay
        self.calls = []  # inspected by tests

    def load(self):
        self.loaded = True

    def status(self):
        return {'provider': self.name, 'loaded': True, 'test_only': True}

    def stream_turn(self, req, cancelled):
        with self.lock:
            prior = self.history.get(req.session, req.character)
            self.calls.append({'turn_id': req.turn_id, 'character': req.character, 'modality': req.modality,
                               'history_len': len(prior), 'system': build_system_prompt(req.profile)})
            if req.modality == 'audio':
                spoken = f'{req.profile.name}です。{req.audio_seconds:.1f}秒の音声を聞きました。'
            else:
                spoken = f'{req.profile.name}です。「{req.text[:20]}」ですね、はい。'
            if prior:
                spoken += f'これで{len(prior) + 1}回目の会話です。'
            yield 'token', None
            partial = ''
            for ch in spoken:
                if cancelled.is_set():
                    return
                partial += ch
                yield 'text', partial
                if self.delay:
                    time.sleep(self.delay)
            result = normalize_result({'text': spoken, 'emotion': 'happy', 'gesture': 'nod'})
            self.remember(req, result)
            yield 'result', result
