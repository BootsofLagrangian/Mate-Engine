import pytest
from engine.furniture import validate_catalog
from engine.intent import normalize_intent, validate_locomotion_catalog
from test_furniture_intents import CATALOG, PROP
from test_intents import provider, chat, collect, TARGET

SPATIAL={'frame':'desktop_scene_v1','bounds':{'x':[-20,20],'y':[-20,20],'z':[-20,20]}}
GAITS=[{'id':'playful_stride','description':'A broad playful stride'}]


def test_spatial_position_only_in_advertised_native_frame():
    registry=validate_catalog([{**CATALOG[0],'spatial':SPATIAL}])
    intent={'kind':'furniture','object_type':'reading_lamp','verb':'configure','target_id':PROP['id'],'position_m':{'x':-20,'y':0,'z':20}}
    assert normalize_intent(intent,[PROP],furniture_catalog=registry)==intent
    assert normalize_intent(intent,[PROP],furniture_catalog=validate_catalog(CATALOG)) is None
    for change in [{'position_m':{'x':0,'y':True,'z':0}},{'position_m':{'x':0,'y':0,'z':float('nan')}},{'position_m':{'x':0,'y':0,'z':20.1}},{'position_m':[0,0,0]},{'placement':'left'},{'verb':'inspect'}]:
        assert normalize_intent({**intent,**change},[PROP],furniture_catalog=registry) is None
    moved={**intent,'verb':'place'}
    assert 'placement' not in normalize_intent(moved,[PROP],furniture_catalog=registry)


@pytest.mark.parametrize('spatial',[{'frame':'camera_local','bounds':SPATIAL['bounds']},{**SPATIAL,'bounds':{'x':[-21,20],'y':[-20,20],'z':[-20,20]}},{**SPATIAL,'bounds':{'x':[True,20],'y':[-20,20],'z':[-20,20]}},None])
def test_invalid_spatial_descriptors_rejected(spatial):
    with pytest.raises(ValueError):validate_catalog([{**CATALOG[0],'spatial':spatial}])


def test_locomotion_is_separate_from_gesture_and_only_for_trip():
    intent={'kind':'move_to','target_id':TARGET['id'],'locomotion_id':'playful_stride'}
    catalog=validate_locomotion_catalog(GAITS)
    assert normalize_intent(intent,[TARGET],locomotion_catalog=catalog)==intent
    for change in [{'kind':'rest'},{'kind':'inspect'},{'locomotion_id':'wave'},{'target_id':'missing'}]:
        assert normalize_intent({**intent,**change},[TARGET],locomotion_catalog=catalog) is None
    assert normalize_intent(intent,[TARGET]) is None
    assert normalize_intent({'kind':'move_to','target_id':TARGET['id']},[TARGET])=={'kind':'move_to','target_id':TARGET['id']}


@pytest.mark.parametrize('value',[[{'id':'x'}]*33,[{'id':'x'},{'id':'x'}],[{'id':'../walk'}],[{'id':'x','description':'x'*241}],[{'id':'x','loop':True}],None])
def test_invalid_loaded_gait_catalog(value):
    with pytest.raises(ValueError):validate_locomotion_catalog(value)


def test_locomotion_request_forwarding_parity_and_revocation(client,monkeypatch):
    from engine.providers.omni import OmniProvider
    intent={'kind':'move_to','target_id':TARGET['id'],'locomotion_id':'playful_stride'}
    seen=[];provider(client,monkeypatch,intent,seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        message={'type':'world_context','character_id':'alpha','interests':[TARGET],'locomotion_catalog':GAITS}
        ws.send_json(message);ack=collect(ws,lambda e:e['type']=='world_context')[-1]
        ws.send_json(message);assert collect(ws,lambda e:e['type']=='world_context')[-1]['revision']==ack['revision']
        events=chat(ws)
        assert all(e['intent']==intent for e in events if e['type'] in ('action','done'))
        system=OmniProvider(client.app.state.history).build_messages(seen[0])[0][0]['content'][0]['text']
        assert 'playful_stride' in system and 'finite trip' in system
        ws.send_json({**message,'locomotion_catalog':[]});collect(ws,lambda e:e['type']=='world_context')
        assert all('intent' not in e for e in chat(ws,'revoked'))


def test_spatial_position_request_forwarding_and_prompt(client,monkeypatch):
    from engine.providers.omni import OmniProvider
    intent={'kind':'furniture','object_type':'reading_lamp','verb':'configure','target_id':PROP['id'],'position_m':{'x':1,'y':0,'z':-2}}
    seen=[];provider(client,monkeypatch,intent,seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        message={'type':'world_context','character_id':'alpha','interests':[PROP],'furniture_catalog':[{**CATALOG[0],'spatial':SPATIAL}]}
        ws.send_json(message);collect(ws,lambda e:e['type']=='world_context')
        assert len([e for e in chat(ws) if e.get('intent')==intent])==2
        system=OmniProvider(client.app.state.history).build_messages(seen[0])[0][0]['content'][0]['text']
        assert 'desktop_scene_v1' in system and 'NOT camera-local' in system
        ws.send_json({**message,'furniture_catalog':CATALOG});collect(ws,lambda e:e['type']=='world_context')
        assert all('intent' not in e for e in chat(ws,'no-spatial'))
