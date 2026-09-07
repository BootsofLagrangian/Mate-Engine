import pytest
from engine.intent import normalize_intent, validate_furniture_types
from engine.providers.omni import OmniProvider
from test_intents import provider, chat, collect

PROP = {'id':'prop:obj_1','label':'Existing desk','kind':'prop'}
INTENT = {'kind':'furniture','object_type':'computer','verb':'use','placement':'near'}

def context(ws, types=None, interests=None):
    ws.send_json({'type':'world_context','character_id':'alpha','interests':interests or [],'furniture_types':['computer'] if types is None else types})
    return collect(ws, lambda e:e['type'] in ('world_context','error'))[-1]


def test_empty_world_can_ensure_furniture_and_stream_intent(client, monkeypatch):
    seen=[]
    provider(client,monkeypatch,INTENT,seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ack=context(ws)
        assert ack['furniture_types']==['computer']
        assert context(ws)['revision']==ack['revision']
        events=chat(ws)
        actions=[e for e in events if e['type'] in ('action','done')]
        assert len(actions)==2 and all(e['intent']==INTENT for e in actions)
        assert next(i for i,e in enumerate(events) if e['type']=='text') < events.index(actions[0])
        messages,_=OmniProvider(client.app.state.history).build_messages(seen[0])
        system=messages[0]['content'][0]['text']
        assert 'user need not create it first' in system and 'object_type' in system
        context(ws,[])
        assert all('intent' not in e for e in chat(ws,'revoked'))


@pytest.mark.parametrize('change', [{'object_type':'oven'},{'verb':'sit'},{'placement':'absolute'}, {'scale':True},{'scale':float('nan')},{'scale':.49},{'scale':1.81},{'target_id':'invented'}, {'x':10},{'verb':'remove'}])
def test_malformed_or_unavailable_furniture_rejected(change):
    assert normalize_intent({**INTENT,**change},[PROP],['computer']) is None


@pytest.mark.parametrize('types', [['computer','computer'],['chair','sofa','computer','oven'],['oven'],None,[{}]])
def test_invalid_capabilities(types):
    with pytest.raises(ValueError): validate_furniture_types(types)


def test_known_prop_actions_and_scale_bounds():
    for verb in ['place','use','inspect','hide','remove']:
        for scale in [.5,1.8]:
            intent={**INTENT,'verb':verb,'target_id':PROP['id']}
            if verb not in ('hide','remove'): intent['scale']=scale
            assert normalize_intent(intent,[PROP],['computer'])==intent
    assert normalize_intent({**INTENT,'target_id':PROP['id']},[{**PROP,'kind':'point'}],['computer']) is None
    assert normalize_intent(INTENT,[],[]) is None


def test_context_reset_and_character_scope(client,monkeypatch):
    provider(client,monkeypatch,INTENT)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json(); context(ws)
        ws.send_json({'type':'reset'})
        collect(ws,lambda e:e['type']=='reset')
        assert all('intent' not in e for e in chat(ws,'reset-furniture'))
        context(ws)
        assert all('intent' not in e for e in chat(ws,'other-character','beta'))


def test_capability_change_invalidates_inflight_furniture(client,monkeypatch):
    import threading
    entered,release=threading.Event(),threading.Event()
    provider(client,monkeypatch,INTENT,entered=entered,release=release)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json(); context(ws)
        ws.send_json({'type':'chat','text':'Use a computer','turn_id':'inflight','character':'alpha','voice':False})
        assert entered.wait(2)
        context(ws,[])
        release.set()
        events=collect(ws,lambda e:e['type']=='done')
        assert all('intent' not in e for e in events)


CATALOG = [{'id':'reading_lamp','verbs':['place','configure','appearance','inspect'],
            'sockets':['light'],'appearances':['warm','cool'],
            'bounds':{'scale':[.7,1.2],'yaw_deg':[-90,90]}}]


def test_generic_declared_skill_not_builtin_and_bounded_configuration():
    from engine.furniture import validate_catalog
    registry=validate_catalog(CATALOG)
    intent={'kind':'furniture','object_type':'reading_lamp','verb':'configure','target_id':PROP['id'],'scale':1.1,'yaw_deg':45,'appearance':'warm'}
    assert normalize_intent(intent,[PROP],furniture_catalog=registry)==intent
    for change in [{'scale':1.3},{'yaw_deg':91},{'appearance':'shader_code'},{'placement':'left'},{'target_id':'unknown'}]:
        assert normalize_intent({**intent,**change},[PROP],furniture_catalog=registry) is None
    assert normalize_intent({'kind':'furniture','object_type':'reading_lamp','verb':'place'},furniture_catalog=registry)['placement']=='near'


@pytest.mark.parametrize('change',[{'verbs':['shell']},{'appearances':['x']*17},{'sockets':['x']*17},{'bounds':{'scale':[.4,1.2],'yaw_deg':[-90,90]}},{'id':'../../lamp'}])
def test_invalid_skill_descriptor(change):
    from engine.furniture import validate_catalog
    with pytest.raises(ValueError): validate_catalog([{**CATALOG[0],**change}])


def test_native_feedback_is_issued_scoped_deduplicated_and_prompted(client,monkeypatch):
    seen=[]
    provider(client,monkeypatch,INTENT,seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json();context(ws);chat(ws,'furniture')
        feedback={'type':'intent_result','character_id':'alpha','intent_id':'furniture:intent','outcome':'completed'}
        ws.send_json({**feedback,'intent_id':'invented:intent'})
        assert collect(ws,lambda e:e['type']=='error')[-1]['type']=='error'
        for _ in range(2):
            ws.send_json(feedback)
            assert collect(ws,lambda e:e['type']=='intent_result')[-1]['accepted']
        chat(ws,'followup')
        assert len(seen[-1].execution_feedback)==1
        messages,_=OmniProvider(client.app.state.history).build_messages(seen[-1])
        assert 'Native execution reports' in messages[0]['content'][0]['text']
        ws.send_json({'type':'reset'});collect(ws,lambda e:e['type']=='reset')
        ws.send_json(feedback)
        assert collect(ws,lambda e:e['type']=='error')[-1]['type']=='error'


def test_perception_unavailable_and_unknown_version_are_rejected(client):
    from engine.furniture import validate_catalog
    entry={**CATALOG[0],'perception':{'mode':'geometry_only','available':False,'reachable':'unknown','reason':'missing_asset'}}
    assert normalize_intent({'kind':'furniture','object_type':'reading_lamp','verb':'place'}, furniture_catalog=validate_catalog([entry])) is None
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type':'world_context','character_id':'alpha','interests':[],'furniture_schema_version':2,'furniture_catalog':CATALOG})
        assert collect(ws,lambda e:e['type']=='error')[-1]['type']=='error'


def test_registry_configuration_end_to_end_and_unavailable_revocation(client,monkeypatch):
    configured={'kind':'furniture','object_type':'reading_lamp','verb':'configure','target_id':PROP['id'],'yaw_deg':30,'appearance':'warm'}
    seen=[]
    provider(client,monkeypatch,configured,seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        message={'type':'world_context','character_id':'alpha','interests':[{**PROP,'object_type':'reading_lamp'}],'furniture_schema_version':1,'furniture_catalog':CATALOG}
        ws.send_json(message);collect(ws,lambda e:e['type']=='world_context')
        events=chat(ws,'configure')
        assert all(e['intent']==configured for e in events if e['type'] in ('action','done'))
        system=OmniProvider(client.app.state.history).build_messages(seen[0])[0][0]['content'][0]['text']
        assert 'reading_lamp' in system and 'warm' in system and 'yaw_deg' in system
        ws.send_json({**message,'furniture_catalog':[],'interests':[]});collect(ws,lambda e:e['type']=='world_context')
        assert all('intent' not in e for e in chat(ws,'registry-removed'))


def test_live_prompt_never_invents_example_targets_or_skill_types():
    import json
    from engine.intent import intent_prompt, grounded_target_examples
    from engine.furniture import validate_catalog
    registry=validate_catalog(CATALOG)
    empty=intent_prompt([],furniture_catalog=registry)
    assert 'sample:bench' not in empty and 'prop:sample' not in empty and '"target_id"' not in empty
    assert '"object_type": "reading_lamp"' in empty
    assert '"object_type": "computer"' not in empty
    live=intent_prompt([PROP],furniture_catalog=registry)
    assert 'sample:bench' not in live and 'prop:sample' not in live
    examples=json.loads(grounded_target_examples([PROP]).split(': ',1)[1])
    assert all(e['intent']['target_id']==PROP['id'] for e in examples)
    # Existing props are untyped: never guess compatibility to fabricate configure examples.
    assert '"verb": "configure"' not in live


def test_typed_prop_context_and_grounded_configuration_example():
    import json
    from engine.intent import validate_interests, grounded_configuration_example
    from engine.furniture import validate_catalog
    typed={**PROP,'object_type':'reading_lamp'}
    targets=validate_interests([typed],['reading_lamp'])
    registry=validate_catalog(CATALOG)
    example=json.loads(grounded_configuration_example(targets,registry).split(': ',1)[1])
    assert example['intent']['target_id']==PROP['id']
    assert example['intent']['object_type']=='reading_lamp'
    assert normalize_intent(example['intent'],targets,furniture_catalog=registry)==example['intent']
    assert grounded_configuration_example([PROP],registry)==''
    for invalid in [{**typed,'kind':'point'},{**typed,'object_type':'unknown'}]:
        with pytest.raises(ValueError):validate_interests([invalid],['reading_lamp'])
    assert normalize_intent({**INTENT,'target_id':PROP['id']},targets,['computer']) is None
