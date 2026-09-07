import json
import threading
import pytest
from conftest import collect
from engine.intent import grounded_appearance_examples
from engine.profiles import build_system_prompt


@pytest.mark.parametrize('change', ['world_changed', 'support_withdrawn', 'reset', 'cancel'])
def test_done_replays_only_delivered_action_and_reset_cancel_revoke(client, monkeypatch, change):
    import stream_pipeline
    release = threading.Event()
    intent = {'kind':'change_appearance','variant_id':'default'}
    def pipeline(*args):
        yield json.dumps({'type':'action','intent':intent,'gesture':'idle'})
        assert release.wait(3)
        yield json.dumps({'type':'done','text':'変えますね。','intent':intent,'gesture':'idle'})
    monkeypatch.setattr(stream_pipeline,'conversation_stream',pipeline)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        context={'type':'world_context','character_id':'alpha','interests':[],'appearance_supported':True}
        ws.send_json(context);collect(ws,lambda e:e['type']=='world_context')
        ws.send_json({'type':'chat','text':'着替えて','turn_id':'issued','character':'alpha','voice':False})
        action=collect(ws,lambda e:e['type']=='action')[-1]
        assert action['intent']==intent
        if change in ('reset','cancel'):
            ws.send_json({'type':change,'turn_id':'issued'})
            collect(ws,lambda e:e['type'] in ('reset','cancelled'))
            release.set()
            # A subsequent ping is a barrier after native cancellation handling.
            ws.send_json({'type':'ping'})
            events=collect(ws,lambda e:e['type']=='pong')
            assert not any(e['type']=='done' and e.get('intent') for e in events)
        else:
            message={**context,'interests':[{'id':'floor:left','label':'Left','kind':'floor'}]} if change=='world_changed' else {**context,'appearance_supported':False}
            ws.send_json(message);collect(ws,lambda e:e['type']=='world_context')
            release.set()
            done=collect(ws,lambda e:e['type']=='done')[-1]
            assert done['intent']==action['intent'] and done['intent_replay'] is True
            ws.send_json({'type':'intent_result','character_id':'alpha','intent_id':'issued:intent','outcome':'completed','reason':'avatar_loaded'})
            assert collect(ws,lambda e:e['type']=='intent_result')[-1]['accepted']


def test_grounded_appearance_examples_only_available_ids():
    rows=[{'id':'formal','label':'Formal'}]
    text=grounded_appearance_examples(rows)
    assert 'formal' in text and '"variant_id": "default"' not in text and 'wet' not in text
    assert grounded_appearance_examples([]).endswith('[]')


def test_shared_instructions_are_character_agnostic(client):
    from engine.profiles import load_profiles
    profiles=load_profiles(client.app.state.profiles_dir,client.app.state.root)
    text=build_system_prompt(profiles['alpha'])
    assert 'Mate Engine interaction contract' in text
    assert 'empty intent object' in text and 'Returning to an' in text
