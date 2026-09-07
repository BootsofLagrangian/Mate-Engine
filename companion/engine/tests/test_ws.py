"""WebSocket contract tests with the stub provider and a fake TTS client (no GPU, no real services)."""
import time
from conftest import collect, wav_base64, FakeTts


def done_for(turn_id):
    return lambda e: e.get('turn_id') == turn_id and e['type'] == 'done'


def test_http_catalog_and_avatar(client):
    health = client.get('/health').json()
    assert health['ok'] and health['provider']['provider'] == 'stub' and health['default_character'] == 'alpha'
    catalog = client.get('/characters').json()
    ids = [c['id'] for c in catalog['characters']]
    assert ids == ['alpha', 'beta', 'gamma'] and catalog['default'] == 'alpha'
    alpha = catalog['characters'][0]
    assert alpha['avatar_url'] == '/characters/alpha/avatar' and alpha['motion_style'] == {'amplitude': 0.8, 'tempo': 0.9, 'idle_interval': 12}
    assert alpha['voice_available'] and not catalog['characters'][2]['voice_available']
    r = client.get('/characters/alpha/avatar')
    assert r.status_code == 200 and r.headers['content-type'] == 'model/gltf-binary' and r.content.startswith(b'glTF')
    assert client.get('/characters/gamma/avatar').status_code == 404
    assert client.get('/characters/../avatar').status_code in (404, 422)
    assert client.get('/characters/nope/avatar').status_code == 404


def test_hello_and_text_turn_events_are_tagged(client):
    with client.websocket_connect('/ws') as ws:
        hello = ws.receive_json()
        assert hello['type'] == 'hello' and hello['protocol'] == 1 and hello['character'] == 'alpha'
        assert hello['capabilities']['audio_input'] and hello['capabilities']['jobs']
        assert [c['id'] for c in hello['characters']] == ['alpha', 'beta', 'gamma']
        ws.send_json({'type': 'chat', 'text': 'こんにちは', 'character': 'beta', 'turn_id': 't1', 'voice': True})
        events = collect(ws, done_for('t1'))
    kinds = [e['type'] for e in events]
    assert kinds[0] == 'state' and kinds[1] == 'start'
    assert all(e['turn_id'] == 't1' and e['character'] == 'beta' for e in events)
    for kind in ('text', 'phrase', 'tts_start', 'audio', 'tts_end', 'action', 'done'):
        assert kind in kinds, kind
    text_events = [e for e in events if e['type'] == 'text']
    assert 'delta' in text_events[0] and text_events[-1]['text'].startswith('ベータです。')
    audio = next(e for e in events if e['type'] == 'audio')
    assert audio['sample_rate'] == 32000 and audio['sequence'] == 0 and audio['phrase'] == 0 and audio['pcm']
    assert kinds.index('audio') < kinds.index('done')
    done = events[-1]
    assert done['ok'] and done['gesture'] == 'nod' and done['emotion'] == 'happy' and 'timings' in done and done['voice_error'] is None
    # Voice reference comes from the selected profile, not a global default.
    assert FakeTts.payloads[0]['ref_audio_path'].endswith('assets/beta-reference.wav')
    assert FakeTts.payloads[0]['prompt_text'] == 'テスト用の参照音声です。'
    assert client.app.state.stub.calls[-1]['character'] == 'beta'


def test_new_turn_supersedes_and_stale_cancel_is_ignored(client):
    client.app.state.stub.delay = 0.03
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': '一つ目の長めの発言です', 'turn_id': 'old', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'text' and e['turn_id'] == 'old')
        ws.send_json({'type': 'chat', 'text': '二つ目', 'turn_id': 'new', 'character': 'alpha'})
        ws.send_json({'type': 'cancel', 'turn_id': 'old'})  # stale: must not touch 'new'
        ws.send_json({'type': 'cancel', 'turn_id': 'never-existed'})
        events = collect(ws, done_for('new'))
    cancelled = [e for e in events if e['type'] == 'cancelled']
    assert cancelled and cancelled[0]['turn_id'] == 'old' and cancelled[0]['reason'] == 'superseded'
    assert not any(e['type'] == 'done' and e['turn_id'] == 'old' for e in events)
    old_after_cancel = [e for e in events[events.index(cancelled[0]) + 1:] if e['turn_id'] == 'old']
    assert old_after_cancel == [], 'no events may leak from a cancelled turn'
    assert events[-1]['turn_id'] == 'new' and events[-1]['ok']


def test_client_cancel_stops_turn_without_done(client):
    client.app.state.stub.delay = 0.05
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'ゆっくり', 'turn_id': 't', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'text')
        ws.send_json({'type': 'cancel', 'turn_id': 't'})
        events = collect(ws, lambda e: e['type'] == 'cancelled')
        assert events[-1]['turn_id'] == 't' and events[-1]['reason'] == 'client'
        ws.send_json({'type': 'ping'})
        tail = collect(ws, lambda e: e['type'] == 'pong')
    assert not any(e['type'] == 'done' for e in tail)


def test_audio_turn_feeds_waveform_not_transcript(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'audio', 'wav': wav_base64(seconds=1.5, rate=48000), 'character': 'alpha', 'turn_id': 'a1'})
        events = collect(ws, done_for('a1'))
        call = client.app.state.stub.calls[-1]
        assert call['modality'] == 'audio' and events[-1]['text'].startswith('アルファです。1.5秒')
        ws.send_json({'type': 'audio', 'wav': 'bm90IGEgd2F2', 'character': 'alpha', 'turn_id': 'a2'})
        err = collect(ws, lambda e: e['type'] == 'error')[-1]
        assert err['turn_id'] == 'a2' and 'Unreadable WAV' in err['message']
        ws.send_json({'type': 'audio', 'wav': wav_base64(seconds=31), 'character': 'alpha', 'turn_id': 'a3'})
        assert '30 seconds' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']


def test_history_is_per_session_and_character(client):
    stub = client.app.state.stub
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        for i, (turn, character) in enumerate((('h1', 'alpha'), ('h2', 'alpha'), ('h3', 'beta'), ('h4', 'alpha'))):
            ws.send_json({'type': 'chat', 'text': f'発言{i}', 'turn_id': turn, 'character': character})
            collect(ws, done_for(turn))
    assert [c['history_len'] for c in stub.calls[-4:]] == [0, 1, 0, 2]
    with client.websocket_connect('/ws') as ws:  # a new connection is a new session
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': '新しい接続', 'turn_id': 'n1', 'character': 'alpha'})
        collect(ws, done_for('n1'))
    assert stub.calls[-1]['history_len'] == 0
    with client.websocket_connect('/ws') as ws:  # explicit session ids persist across connections
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'x', 'turn_id': 's1', 'character': 'alpha', 'session': 'shared'})
        collect(ws, done_for('s1'))
        ws.send_json({'type': 'chat', 'text': 'y', 'turn_id': 's2', 'character': 'alpha', 'session': 'shared'})
        collect(ws, done_for('s2'))
        ws.send_json({'type': 'reset', 'session': 'shared', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'reset')
        ws.send_json({'type': 'chat', 'text': 'z', 'turn_id': 's3', 'character': 'alpha', 'session': 'shared'})
        collect(ws, done_for('s3'))
    assert [c['history_len'] for c in stub.calls[-3:]] == [0, 1, 0]


def test_validation_errors_and_voice_error_semantics(client):
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'x', 'turn_id': 'u', 'character': 'nobody'})
        assert 'unknown character' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        ws.send_json({'type': 'chat', 'text': '   ', 'turn_id': 'v', 'character': 'alpha'})
        assert 'text' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        ws.send_json({'type': 'chat', 'text': 'x', 'character': 'alpha'})
        assert 'turn_id' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        ws.send_json({'type': 'chat', 'text': 'x', 'turn_id': 'job:x:ack', 'character': 'alpha'})
        assert 'turn_id' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        ws.send_json({'type': 'bogus'})
        assert 'unknown message type' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        ws.send_text('not json')
        assert 'invalid JSON' in collect(ws, lambda e: e['type'] == 'error')[-1]['message']
        # TTS failure keeps the dialogue: text/done still arrive, voice_error reports the cause.
        FakeTts.fail = True
        ws.send_json({'type': 'chat', 'text': 'こんにちは', 'turn_id': 'w', 'character': 'alpha'})
        events = collect(ws, done_for('w'))
        assert any(e['type'] == 'voice_error' and 'fake TTS offline' in e['message'] for e in events)
        assert events[-1]['ok'] and events[-1]['text'] and not any(e['type'] == 'audio' for e in events)
        FakeTts.fail = False
        # Character without a voice reference: no TTS call, no voice_error, dialogue still delivered.
        before = len(FakeTts.payloads)
        ws.send_json({'type': 'chat', 'text': 'こんにちは', 'turn_id': 'g', 'character': 'gamma'})
        events = collect(ws, done_for('g'))
        assert len(FakeTts.payloads) == before and events[-1]['ok'] and not any(e['type'] in ('audio', 'voice_error') for e in events)


def test_provider_failure_is_an_error_event(client, monkeypatch):
    def broken(req, cancelled):
        yield 'token', None
        raise RuntimeError('model exploded')
    monkeypatch.setattr(client.app.state.stub, 'stream_turn', broken)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'text': 'x', 'turn_id': 'e', 'character': 'alpha'})
        events = collect(ws, done_for('e'))
    assert any(e['type'] == 'error' and 'model exploded' in e['message'] for e in events)
    assert events[-1]['ok'] is False and 'text' not in events[-1]


def test_disconnect_cancels_running_turn(client):
    stub = client.app.state.stub
    stub.delay = 0.05
    with client.websocket_connect('/ws') as ws:
        session = ws.receive_json()['session']
        ws.send_json({'type': 'chat', 'text': '切断テストの長い発言', 'turn_id': 'd', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'text')
        turn = next(iter(client.app.state.connections)).turn
    assert turn.finished.wait(5) and turn.cancelled.is_set() and turn.outcome == 'cancelled'
    assert stub.calls[-1]['turn_id'] == 'd'
    # The provider stopped before finishing the reply: nothing is remembered for a cancelled turn.
    assert client.app.state.history.get(session, 'alpha') == []
