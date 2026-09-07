"""Regression tests for lifecycle races; only fake TTS/Codex, no GPU or live services."""
import threading
import time
from conftest import collect, FakeTtsResponse
from engine.jobs import Job
from engine.providers.omni import OmniProvider


def done(turn):
    return lambda e: e['type'] == 'done' and e.get('turn_id') == turn


def test_cancel_after_model_result_does_not_commit_history(client, monkeypatch):
    release = threading.Event()
    entered = threading.Event()

    def blocked_audio(self, **kwargs):
        entered.set()
        assert release.wait(3)
        yield b'\x01\x00' * 640

    monkeypatch.setattr(FakeTtsResponse, 'iter_bytes', blocked_audio)
    try:
        with client.websocket_connect('/ws') as ws:
            session = ws.receive_json()['session']
            ws.send_json({'type': 'chat', 'text': 'はい', 'turn_id': 'cancel-late', 'character': 'alpha'})
            collect(ws, lambda e: e['type'] == 'action')
            assert entered.wait(1)
            connection = next(iter(client.app.state.connections))
            assert connection.turn.req.pending_history is not None
            assert client.app.state.history.get(session, 'alpha') == []
            ws.send_json({'type': 'cancel', 'turn_id': 'cancel-late'})
            collect(ws, lambda e: e['type'] == 'cancelled')
            release.set()
            assert connection.turn.finished.wait(2)
            assert client.app.state.history.get(session, 'alpha') == []
    finally:
        release.set()


def test_failed_partial_reply_stops_queued_audio(client, monkeypatch):
    entered = threading.Event()
    release = threading.Event()

    def blocked_audio(self, **kwargs):
        entered.set()
        assert release.wait(3)
        yield b'\x01\x00' * 640

    def broken(req, cancelled):
        yield 'text', 'はい。次の文章です。'
        assert entered.wait(2)
        raise ValueError('malformed final JSON')

    monkeypatch.setattr(FakeTtsResponse, 'iter_bytes', blocked_audio)
    monkeypatch.setattr(client.app.state.stub, 'stream_turn', broken)
    try:
        with client.websocket_connect('/ws') as ws:
            ws.receive_json()
            ws.send_json({'type': 'chat', 'text': 'はい', 'turn_id': 'broken', 'character': 'alpha'})
            events = collect(ws, lambda e: e['type'] == 'error')
            release.set()
            events += collect(ws, done('broken'))
            assert not any(e['type'] == 'audio' for e in events)
            assert not events[-1]['ok']
    finally:
        release.set()


def test_named_sessions_cannot_read_another_connection(client):
    for expected in (0, 0):
        with client.websocket_connect('/ws') as ws:
            ws.receive_json()
            ws.send_json({'type': 'chat', 'text': '記憶', 'session': 'guessable', 'turn_id': 'same', 'character': 'alpha', 'voice': False})
            collect(ws, done('same'))
            assert client.app.state.stub.calls[-1]['history_len'] == expected


def test_new_custom_gesture_reaches_omni_prompt(client):
    motion = {'name': 'salute_custom', 'description': '右手で敬礼する', 'duration': 1.0, 'tracks': [
        {'bone': 'head', 'keys': [{'time': 0}, {'time': .5, 'x': 10}, {'time': 1}]}]}
    assert client.put('/motions/salute_custom', json=motion).status_code == 200
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': '敬礼して', 'turn_id': 'custom', 'character': 'alpha', 'voice': False})
        collect(ws, done('custom'))
        req = next(iter(client.app.state.connections)).turn.req
        provider = OmniProvider(client.app.state.history, device='cpu')
        messages, _ = provider.build_messages(req)
        assert 'salute_custom' in messages[0]['content'][0]['text']
        assert '右手で敬礼する' in messages[0]['content'][0]['text']


def test_job_waits_for_first_ack_pcm(client, monkeypatch):
    release = threading.Event()
    entered = threading.Event()

    def blocked_audio(self, **kwargs):
        entered.set()
        assert release.wait(3)
        yield b'\x01\x00' * 640

    monkeypatch.setattr(FakeTtsResponse, 'iter_bytes', blocked_audio)
    try:
        with client.websocket_connect('/ws') as ws:
            ws.receive_json()
            ws.send_json({'type': 'job', 'prompt': 'quick', 'job_id': 'ordered', 'character': 'alpha'})
            collect(ws, lambda e: e['type'] == 'tts_start')
            assert entered.wait(1)
            job = next(iter(client.app.state.connections)).job
            assert job.process is None and job.thread is None
            release.set()
            events = collect(ws, lambda e: e['type'] == 'job' and e['status'] == 'completed')
            assert next(i for i, e in enumerate(events) if e['type'] == 'audio') < next(i for i, e in enumerate(events) if e['type'] == 'job')
    finally:
        release.set()


def test_job_does_not_speak_over_finished_foreground_playback(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'はい', 'turn_id': 'playing', 'character': 'alpha'})
        collect(ws, done('playing'))
        ws.send_json({'type': 'playback', 'turn_id': 'playing', 'playing': True})
        ws.send_json({'type': 'job', 'prompt': 'quick', 'job_id': 'quiet', 'character': 'alpha'})
        events = collect(ws, lambda e: e['type'] == 'job' and e['status'] == 'completed')
        ws.send_json({'type': 'ping'})
        events += collect(ws, lambda e: e['type'] == 'pong')
        assert not any(str(e.get('turn_id', '')).startswith('job:') for e in events)
        ws.send_json({'type': 'select_character', 'character': 'beta'})
        collect(ws, lambda e: e['type'] == 'character_selected')
        connection = next(iter(client.app.state.connections))
        assert connection.character == 'beta' and not connection.playback_active()


def test_cancel_job_before_launch_emits_terminal_status(job_settings):
    events = []
    job = Job('early', 'quick', 'alpha', job_settings, events.append)
    job.cancel()
    job.start()
    assert job.wait(3) == 'cancelled'
    assert events[-1]['status'] == 'cancelled' and job.process is None


def test_job_cancel_kills_sigterm_ignoring_child(tmp_path, job_settings):
    import os
    import sys
    import pytest
    if os.name != 'posix':
        pytest.skip('POSIX process-group regression; Windows requires actual validation')
    script = tmp_path / 'ignore.py'
    script.write_text('import signal,time,json\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nprint(json.dumps({"type":"turn.started"}),flush=True)\ntime.sleep(60)\n')
    events = []
    ready = threading.Event()
    def emit(event):
        events.append(event)
        if event['status'] == 'running':
            ready.set()
    job = Job('stubborn', 'quick', 'alpha', {**job_settings, 'codex': f'{sys.executable} {script}'}, emit)
    job.start()
    assert ready.wait(3)
    job.cancel()
    assert job.wait(4) == 'cancelled'
    assert job.process.poll() is not None


def test_exit_zero_without_completed_event_is_not_success(tmp_path, job_settings):
    import sys
    script = tmp_path / 'empty.py'
    script.write_text('pass\n')
    events = []
    job = Job('empty', 'quick', 'alpha', {**job_settings, 'codex': f'{sys.executable} {script}'}, events.append)
    job.start()
    assert job.wait(3) == 'failed'
    assert 'without turn.completed' in events[-1]['message']


def test_job_deadline_terminates_real_fake_process(job_settings):
    events = []
    job = Job('timeout', 'be SLOW', 'alpha', {**job_settings, 'timeout_seconds': .1}, events.append)
    job.start()
    assert job.wait(3) == 'cancelled'
    assert events[-1]['message'] == 'timed out'
