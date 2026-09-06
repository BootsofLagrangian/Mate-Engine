import io
import pytest
import numpy as np
import soundfile as sf
from fastapi.testclient import TestClient
import app

client=TestClient(app.app)
def test_reply_allowlist():
    assert app.parse_reply('{"text":"こんにちは。","gesture":"rm -rf /","emotion":"bogus"}') == {'text':'こんにちは。','gesture':'idle','emotion':'neutral'}
@pytest.mark.parametrize('raw',['not JSON','{"text":null}','{"text":""}','[]','{"gesture":"wave"}'])
def test_malformed_output_is_not_spoken(raw):
    with pytest.raises(ValueError):app.parse_reply(raw)
def test_chat_voice_failure_keeps_dialogue(monkeypatch):
    monkeypatch.setattr(app.brain,'reply',lambda *_:{'text':'こんにちは。','gesture':'wave','emotion':'happy'})
    def fail(_):raise RuntimeError('offline')
    monkeypatch.setattr(app,'synthesize',fail)
    r=client.post('/chat',json={'text':'안녕','session':'test'})
    assert r.status_code==200 and r.json()['text']=='こんにちは。'
    assert r.json()['audio_url'] is None and r.json()['voice_error']=='offline'
def test_bad_inputs():
    assert client.post('/chat',json={'text':' '}).status_code==422
    assert client.post('/chat',json={'text':'x','session':'../../secret'}).status_code==422
    assert client.post('/stt',files={'audio':('bad.wav',b'invalid')}).status_code==422
    data=io.BytesIO();sf.write(data,np.zeros(16000*31),16000,format='WAV')
    assert client.post('/stt',files={'audio':('long.wav',data.getvalue())}).status_code==413
def test_reset_isolates_sessions():
    app.brain.history={'a':[{'content':'a'}],'b':[{'content':'b'}]}
    assert client.post('/sessions/a/reset').json()['ok']
    assert 'a' not in app.brain.history and 'b' in app.brain.history

def test_motion_library_matches_llm_actions():
    import json
    library=json.loads((app.ROOT.parent/'Assets/StreamingAssets/cheval-motions.json').read_text())
    assert {m['name'] for m in library['motions']} == app.GESTURES
    for motion in library['motions']:
        for track in motion['tracks']:
            assert track['keys'][0]['time']==0
            assert track['keys'][-1]['time']==motion['duration']
            for key in (track['keys'][0],track['keys'][-1]):
                assert [key['x'],key['y'],key['z']]==[0,0,0]

def test_explicit_motion_requests_and_negation():
    assert app.explicit_motion('같이 기지개 켜자.') == 'stretch'
    assert app.explicit_motion('손 흔들어 줘') == 'wave'
    assert app.explicit_motion('손 흔들지 말고 기지개 하지 마') is None
    assert app.explicit_motion('오늘 하루가 힘들었어') is None
