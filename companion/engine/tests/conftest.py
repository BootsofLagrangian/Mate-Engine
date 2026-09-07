"""Shared fixtures. Everything here is a FAKE or STUB: no GPU model, no real TTS, no real codex.

- `stub` provider (engine.providers.stub) replaces Qwen2.5-Omni.
- FakeTts replaces the GPT-SoVITS HTTP client inside stream_pipeline.
- fake_codex.py replaces the codex CLI and speaks the real `codex exec --json` event shapes.
"""
import json
import sys
import threading
from pathlib import Path
import numpy as np
import pytest
import soundfile as sf

ENGINE_DIR = Path(__file__).resolve().parents[1]
COMPANION_ROOT = ENGINE_DIR.parent
for p in (str(COMPANION_ROOT),):
    if p not in sys.path:
        sys.path.insert(0, p)

import stream_pipeline  # noqa: E402
from engine.history import HistoryStore  # noqa: E402
from engine.motions import MotionBank  # noqa: E402
from engine.providers.stub import StubProvider  # noqa: E402
from engine.server import create_app  # noqa: E402

FAKE_CODEX = ENGINE_DIR / 'tests' / 'fake_codex.py'


def profile_json(character_id, name, **extra):
    data = {
        'id': character_id, 'name': name,
        'canonical_facts': [f'{name}は架空のテスト用キャラクター。'],
        'roleplay_guidance': ['短く丁寧に話す。'],
        'examples': [{'user': 'こんにちは', 'text': 'こんにちは。', 'emotion': 'happy', 'gesture': 'wave'}],
        'assets': {'vrm': f'assets/{character_id}.vrm', 'reference_audio': f'assets/{character_id}-reference.wav', 'reference_text': 'テスト用の参照音声です。'},
        'motion_style': {'amplitude': 0.8, 'tempo': 0.9, 'idle_interval': 12},
        'job_ack': 'はい、始めますね。', 'job_done': '終わりました。', 'job_failed': 'うまくいきませんでした。',
    }
    data.update(extra)
    return data


def write_wav(path, seconds=1.0, rate=16000):
    t = np.arange(int(seconds * rate)) / rate
    sf.write(str(path), (0.1 * np.sin(2 * np.pi * 220 * t)).astype('float32'), rate)


@pytest.fixture
def companion_root(tmp_path):
    root = tmp_path / 'companion'
    (root / 'characters').mkdir(parents=True)
    (root / 'assets').mkdir()
    (root / 'output').mkdir()
    for cid, name in (('alpha', 'アルファ'), ('beta', 'ベータ')):
        (root / 'characters' / f'{cid}.json').write_text(json.dumps(profile_json(cid, name), ensure_ascii=False), encoding='utf-8')
        write_wav(root / 'assets' / f'{cid}-reference.wav')
        (root / 'assets' / f'{cid}.vrm').write_bytes(b'glTF' + bytes(12))
    # 'gamma' has no reference audio -> turns run without voice
    (root / 'characters' / 'gamma.json').write_text(json.dumps(profile_json('gamma', 'ガンマ', assets={}), ensure_ascii=False), encoding='utf-8')
    return root


class FakeTtsResponse:
    def __init__(self, fail):
        self.fail = fail

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def raise_for_status(self):
        if self.fail:
            raise RuntimeError('fake TTS offline')

    def iter_bytes(self, **_):
        for _ in range(3):
            yield b'\x01\x00' * 640


class FakeTts:
    """Stands in for httpx.Client inside stream_pipeline. Records every payload it receives."""
    payloads = []
    fail = False

    def __init__(self, **_):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def stream(self, method, url, json=None, **_):
        FakeTts.payloads.append(json)
        return FakeTtsResponse(FakeTts.fail)


@pytest.fixture
def fake_tts(monkeypatch):
    FakeTts.payloads = []
    FakeTts.fail = False
    monkeypatch.setattr(stream_pipeline.httpx, 'Client', FakeTts)
    return FakeTts


@pytest.fixture
def job_settings(tmp_path):
    root = tmp_path / 'jobroot'
    root.mkdir()
    return {'root': str(root), 'sandbox': 'read-only', 'codex': f'{sys.executable} {FAKE_CODEX}', 'model': None,
            'timeout_seconds': 20, 'available': True, 'problems': []}


@pytest.fixture
def engine(companion_root, fake_tts, job_settings, tmp_path):
    history = HistoryStore(max_turns=3, max_sessions=4)
    provider = StubProvider(history, delay=0.005)
    bank = MotionBank(bank_path=COMPANION_ROOT.parent / 'Assets/StreamingAssets/cheval-motions.json', custom_dir=tmp_path / 'user-data/motions')
    app = create_app(provider=provider, history=history, profiles_dir=companion_root / 'characters', root=companion_root,
                     motion_bank=bank, job_settings=job_settings)
    app.state.stub = provider
    return app


@pytest.fixture
def client(engine, monkeypatch):
    from fastapi.testclient import TestClient
    monkeypatch.setenv('MATE_DEFAULT_CHARACTER', 'alpha')
    with TestClient(engine) as tc:
        yield tc


def wav_base64(seconds=1.0, rate=16000):
    import base64
    import io
    buf = io.BytesIO()
    t = np.arange(int(seconds * rate)) / rate
    sf.write(buf, (0.1 * np.sin(2 * np.pi * 330 * t)).astype('float32'), rate, format='WAV')
    return base64.b64encode(buf.getvalue()).decode()


def collect(ws, until, timeout=10.0, keep=None):
    """Receive events until `until(event)` is true. Fails loudly instead of hanging forever."""
    events = []
    result = {}

    def pump():
        try:
            while True:
                event = ws.receive_json()
                events.append(event)
                if until(event):
                    return
        except Exception as exc:  # surfaced by the assertion below
            result['error'] = exc

    worker = threading.Thread(target=pump, daemon=True)
    worker.start()
    worker.join(timeout)
    assert not worker.is_alive(), f'timed out waiting; got {[e.get("type") for e in events]}'
    assert 'error' not in result, result['error']
    return events
