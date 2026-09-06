import threading
import time

import pytest

from conftest import collect
from engine.intent import validate_interests
from engine.profiles import Profile, normalize_result
from engine.providers.omni import OmniProvider


TARGET = {'id': 'surface:left@1', 'label': '窓の左側', 'kind': 'surface'}
INTENT = {'kind': 'move_to', 'target_id': TARGET['id'], 'duration_s': 6}


def context(ws, interests=None, character='alpha'):
    ws.send_json({'type': 'world_context', 'character_id': character, 'interests': [TARGET] if interests is None else interests})
    return collect(ws, lambda e: e['type'] in ('world_context', 'error'))[-1]


def chat(ws, turn='test', character='alpha'):
    ws.send_json({'type': 'chat', 'text': 'そこを見て', 'turn_id': turn, 'character': character, 'voice': False})
    return collect(ws, lambda e: e['type'] == 'done' and e['turn_id'] == turn)


def provider(client, monkeypatch, intent=INTENT, entered=None, release=None, seen=None):
    def stream(req, cancelled):
        if seen is not None:
            seen.append(req)
        yield 'text', '見てみますね。'
        if entered:
            entered.set()
            assert release.wait(3)
        yield 'result', {'text': '見てみますね。', 'emotion': 'neutral', 'gesture': 'nod', 'intent': intent}
    monkeypatch.setattr(client.app.state.stub, 'stream_turn', stream)


def test_named_context_prompt_and_streamed_final_intent(client, monkeypatch):
    seen = []
    provider(client, monkeypatch, seen=seen)
    with client.websocket_connect('/ws') as ws:
        assert ws.receive_json()['capabilities']['world_context']
        ack = context(ws)
        assert ack['accepted'] == 1
        assert context(ws)['revision'] == ack['revision']  # heartbeat
        events = chat(ws)
        actions = [e for e in events if e['type'] in ('action', 'done')]
        assert len(actions) == 2 and all(e['intent'] == INTENT for e in actions)
        assert events.index(next(e for e in events if e['type'] == 'text')) < events.index(actions[0])
        omni = OmniProvider(client.app.state.history)
        messages, _ = omni.build_messages(seen[0])
        system = messages[0]['content'][0]['text']
        assert TARGET['id'] in system and TARGET['label'] in system
        assert 'untrusted names' in system and 'never proof of action' in system


@pytest.mark.parametrize('intent', [None, [], {'kind': 'teleport'}, {'kind': 'inspect'},
    {'kind': 'move_to', 'target_id': 'unknown'}, {**INTENT, 'x': 100},
    {**INTENT, 'duration_s': float('nan')}, {**INTENT, 'duration_s': 31}, {**INTENT, 'duration_s': True}])
def test_normalizer_rejects_malformed_or_unknown_intent(intent):
    assert 'intent' not in normalize_result({'text': 'はい。', 'intent': intent}, interests=[TARGET])


def test_rest_and_known_target_normalize():
    assert normalize_result({'text': 'はい。', 'intent': {'kind': 'rest'}})['intent'] == {'kind': 'rest'}
    assert normalize_result({'text': 'はい。', 'intent': INTENT}, interests=[TARGET])['intent'] == INTENT


@pytest.mark.parametrize('items', [[TARGET] * 17, [TARGET, TARGET], [{**TARGET, 'x': 5}],
    [{**TARGET, 'label': 'x' * 81}], [{**TARGET, 'label': 'x\ny'}], [{**TARGET, 'id': 'x' * 97}],
    [{**TARGET, 'kind': 'shell'}], None])
def test_context_metadata_bounds(items):
    with pytest.raises(ValueError):
        validate_interests(items)


def test_conflicting_character_reset_and_reconnect(client, monkeypatch):
    provider(client, monkeypatch)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        assert context(ws, character='beta')['type'] == 'error'
        assert all('intent' not in e for e in chat(ws))
        context(ws)
        ws.send_json({'type': 'reset'})
        collect(ws, lambda e: e['type'] == 'reset')
        assert all('intent' not in e for e in chat(ws, 'reset'))
        context(ws)
        assert all('intent' not in e for e in chat(ws, 'switch', 'beta'))
        assert context(ws, character='alpha')['type'] == 'error'
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        assert all('intent' not in e for e in chat(ws, 'fresh'))


def test_empty_context_and_explicit_reselection_disable_targeted_intent(client, monkeypatch):
    provider(client, monkeypatch)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        context(ws, [])
        assert all('intent' not in e for e in chat(ws, 'empty'))
        context(ws)
        ws.send_json({'type': 'select_character', 'character': 'alpha'})
        collect(ws, lambda e: e['type'] == 'character_selected')
        assert all('intent' not in e for e in chat(ws, 'reselected'))


def test_invalid_context_update_rejected_and_live_context_preserved(client, monkeypatch):
    provider(client, monkeypatch)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ack = context(ws)
        assert context(ws, [{**TARGET, 'x': 123}])['type'] == 'error'
        assert context(ws)['revision'] == ack['revision']
        assert chat(ws)[-1]['intent'] == INTENT


@pytest.mark.parametrize('change', ['replace', 'expire'])
def test_inflight_intent_rejected_after_context_change(client, monkeypatch, change):
    entered, release = threading.Event(), threading.Event()
    provider(client, monkeypatch, entered=entered, release=release)
    try:
        with client.websocket_connect('/ws') as ws:
            ws.receive_json()
            context(ws)
            ws.send_json({'type': 'chat', 'text': 'そこ', 'turn_id': 'stale', 'voice': False})
            assert entered.wait(2)
            if change == 'replace':
                context(ws, [])
            else:
                conn = next(iter(client.app.state.connections))
                conn.world_updated = time.monotonic() - 46
            release.set()
            events = collect(ws, lambda e: e['type'] == 'done')
            assert all('intent' not in e for e in events)
    finally:
        release.set()


def test_behavior_style_catalog_bounds_and_legacy_fallback(client, tmp_path):
    catalog = client.get('/characters').json()['characters']
    assert catalog[0]['behavior_style']['idle_interval_s'] == 12
    profile = Profile({'id': 'test', 'name': 'Test', 'motion_style': {'idle_interval': 18},
                       'behavior_style': {'curiosity': 9, 'gaze_hold_s': -1, 'response_delay_s': float('nan')}}, tmp_path / 'test.json')
    assert profile.behavior_style == {'idle_interval_s': 18.0, 'gaze_hold_s': .3, 'response_delay_s': .25,
                                      'curiosity': 1.0, 'posture_strength': .5}
