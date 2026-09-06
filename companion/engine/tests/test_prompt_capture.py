import hashlib
import json
from types import SimpleNamespace
import pytest
from engine.prompt_capture import capture_fixture, capability_summary


def request(**changes):
    return SimpleNamespace(**dict({'audio':None,'text':'fixture request','character':'alpha','turn_id':'fixture','session':'fresh',
            'furniture_catalog':({'id':'workstation','verbs':['use']},),'furniture_types':(),
            'world_interests':(),'locomotion_catalog':(),'appearance_variants':()},**changes))


def arm(root, **changes):
    marker=root/'user-data/diagnostics/prompt-capture-request.json'
    marker.parent.mkdir(parents=True,exist_ok=True)
    marker.write_text(json.dumps(dict({'capture_id':'a'*32,'character_id':'alpha',
        'text_sha256':hashlib.sha256(b'fixture request').hexdigest(),'expires_unix':1100},**changes)))
    return marker


def test_exact_fresh_fixture_capture_is_opt_in_and_one_shot(tmp_path):
    req=request();messages=[{'role':'user','content':'fixture request'}];prompt='EXACT TOKENIZER TEMPLATE'
    assert not capture_fixture(req,messages,prompt,has_history=False,root=tmp_path,now=1000)
    marker=arm(tmp_path)
    assert capture_fixture(req,messages,prompt,has_history=False,root=tmp_path,now=1000)
    payload=json.loads((marker.parent/'prompt-captures'/('a'*32+'.json')).read_text())
    assert payload['messages']==messages and payload['rendered_prompt']==prompt
    assert payload['capabilities']['furniture_catalog']==[{'id':'workstation','verbs':['use']}]
    assert not marker.exists()
    arm(tmp_path)
    assert not capture_fixture(req,messages,'CHANGED',has_history=False,root=tmp_path,now=1000)
    assert json.loads((marker.parent/'prompt-captures'/('a'*32+'.json')).read_text())['rendered_prompt']==prompt


@pytest.mark.parametrize('change,history', [({'text':'unrelated private request'},False),({'character':'beta'},False),({'audio':[0.]},False),({},True)])
def test_private_nonfixture_audio_or_history_never_captured(tmp_path,change,history):
    marker=arm(tmp_path)
    assert not capture_fixture(request(**change),[], 'PRIVATE',has_history=history,root=tmp_path,now=1000)
    assert not (marker.parent/'prompt-captures').exists()


@pytest.mark.parametrize('change',[{'expires_unix':999},{'expires_unix':2000},{'expires_unix':True},{'capture_id':'../outside'}])
def test_capture_marker_scope_bounded(tmp_path,change):
    arm(tmp_path,**change)
    assert not capture_fixture(request(),[],'prompt',has_history=False,root=tmp_path,now=1000)


def test_rich_catalog_ack_is_not_confused_with_empty_legacy_types(client):
    from test_furniture_intents import CATALOG
    from conftest import collect
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type':'world_context','character_id':'alpha','interests':[],'furniture_catalog':CATALOG})
        ack=collect(ws,lambda e:e['type']=='world_context')[-1]
        assert ack['furniture_types']==[]
        assert ack['furniture_catalog']==[{'id':r['id'],'verbs':sorted(r['verbs'])} for r in CATALOG]
