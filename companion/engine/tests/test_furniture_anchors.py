"""Data-contract and websocket regression; no rendered manipulation quality claim."""
import copy
import json
from pathlib import Path

import pytest

from engine.furniture import validate_catalog, validate_anchor_contract
from test_intents import collect, provider, chat


def native_catalog():
    definitions = json.loads((Path(__file__).parents[2] / 'native/assets/desktop_objects/premium/objects.json').read_text())
    contract = {'version': 1, 'position_units': 'metres', 'facing': 'unit_vector',
                'approach': 'reference_only; authored clip and collision admission determine final entry',
                'reference_only': 'not an executable verb'}
    return [{'id': name, 'version': 1, 'verbs': ['place', 'configure', 'appearance', 'hide', 'remove', 'inspect', 'use' if name == 'computer' else 'sit'],
             'sockets': sorted({a['socket'] for a in item['interaction_anchors'].values()}),
             'appearances': ['default', 'warm', 'cool', 'porcelain', 'flat'],
             'bounds': {'scale': [.5, 1.8], 'yaw_deg': [-180, 180]},
             'spatial': {'frame': 'desktop_scene_v1', 'bounds': {axis: [-20, 20] for axis in 'xyz'}},
             'perception': {'mode': 'geometry_only', 'available': True, 'reason': 'native_geometry', 'reachable': 'unknown'},
             'interaction_anchors': item['interaction_anchors'], 'manipulation': item.get('manipulation', {}), 'anchor_contract': contract}
            for name, item in definitions.items()]


def test_installed_anchor_metadata_roundtrip_and_legacy_compatibility():
    catalog = native_catalog()
    clean = validate_catalog(catalog)
    assert validate_catalog(json.loads(json.dumps(clean))) == clean
    # Godot parses embedded JSON numbers as floats before serializing its catalogue.
    godot_numbers = copy.deepcopy(catalog)
    next(e for e in godot_numbers if e['id'] == 'computer')['manipulation']['version'] = 1.0
    assert validate_catalog(godot_numbers) == clean
    assert next(e for e in clean if e['id'] == 'computer')['manipulation']['hand_anchors'] == ['grip_left', 'grip_right']
    for e in catalog:
        for field in ('interaction_anchors', 'manipulation', 'anchor_contract'):
            e.pop(field)
    assert all('interaction_anchors' not in e for e in validate_catalog(catalog))
    assert all('push' not in e['verbs'] and 'pull' not in e['verbs'] for e in clean)


@pytest.mark.parametrize('field,value', [
    ('facing', [0, float('nan'), 1]), ('facing', [0, 0, 0]), ('facing', [True, 0, 0]),
    ('facing', [0, 0, 2]), ('up', [0, 0, 1]), ('up', None), ('frame', 'screen_pixels'),
    ('socket', 'missing'), ('role', 'execute_script'), ('verbs', ['pull']), ('execution', 'code'),
])
def test_invalid_anchor_rejected(field, value):
    catalog = native_catalog()
    catalog[0]['interaction_anchors']['grip_left'][field] = value
    with pytest.raises(ValueError): validate_catalog(catalog)


@pytest.mark.parametrize('path,value', [
    (('translation', 'limits'), [-1, 1.2]), (('translation', 'limits'), [0, 1.201]),
    (('translation', 'limits'), [0, True]), (('translation', 'limits'), [0, float('inf')]),
    (('translation', 'axis'), [1, 0, 0]), (('rotation', 'limits'), [-181, 180]),
    (('rotation', 'frame'), 'camera'), (('rotation', 'parameter'), 'script'),
    (('hand_anchors',), ['grip_left', 'grip_left']), (('hand_anchors',), ['seat', 'inspect']),
    (('actor_anchor',), 'seat'), (('version',), True), (('admission',), 'x'*201),
    (('actions', 'pull', 'sign'), True), (('actions', 'pull', 'parameter'), 'execute'),
])
def test_invalid_manipulation_rejected(path, value):
    catalog = native_catalog()
    obj = next(e for e in catalog if e['id'] == 'computer')['manipulation']
    for key in path[:-1]: obj = obj[key]
    obj[path[-1]] = value
    with pytest.raises(ValueError): validate_catalog(catalog)


def test_anchor_count_name_and_contract_rejected():
    for invalid in ({'version': True}, {'version': 2}, None):
        with pytest.raises(ValueError): validate_anchor_contract(invalid)
    for name in ('../escape', 'a'*41):
        catalog = native_catalog()
        catalog[0]['interaction_anchors'][name] = copy.deepcopy(catalog[0]['interaction_anchors']['seat'])
        with pytest.raises(ValueError): validate_catalog(catalog)
    catalog = native_catalog()
    catalog[0]['interaction_anchors'] = {f'a{i}': copy.deepcopy(catalog[0]['interaction_anchors']['seat']) for i in range(17)}
    with pytest.raises(ValueError): validate_catalog(catalog)


def test_anchor_catalog_world_context_keeps_tools_available(client, monkeypatch):
    seen = []
    provider(client, monkeypatch, {'kind': 'furniture', 'object_type': 'computer', 'verb': 'place'}, seen=seen)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        message = {'type': 'world_context', 'character_id': 'alpha', 'interests': [], 'furniture_catalog': native_catalog()}
        ws.send_json(message)
        ack = collect(ws, lambda e: e['type'] == 'world_context')[-1]
        assert any(e['id'] == 'computer' for e in ack['furniture_catalog'])
        events = chat(ws)
        assert any(e.get('intent', {}).get('object_type') == 'computer' for e in events)
        computer = next(e for e in seen[0].furniture_catalog if e['id'] == 'computer')
        assert computer['interaction_anchors']['grip_left']['frame'] == 'seat'
        assert computer['manipulation']['actor_anchor'] == 'manipulate_approach'
        from engine.intent import furniture_prompt
        assert 'grip_left' not in furniture_prompt((), seen[0].furniture_catalog)
        assert 'grip_left' in computer['interaction_anchors']


def test_prompt_projection_keeps_semantic_choices_without_native_actuation():
    from engine.intent import furniture_prompt, furniture_prompt_catalog, grounded_furniture_example
    catalog = validate_catalog(native_catalog())
    original = copy.deepcopy(catalog)
    projected = furniture_prompt_catalog(catalog)
    for full, compact in zip(catalog, projected):
        assert set(compact) == {'id', 'verbs', 'appearances', 'bounds', 'perception', 'spatial'}
        for key in compact:
            assert compact[key] == full[key]
    prompt = furniture_prompt((), catalog)
    assert grounded_furniture_example(catalog) in prompt
    assert 'desktop_scene_v1' in prompt
    assert 'Never claim creation, contact or completion succeeded before host feedback' in prompt
    assert 'grip_left' not in prompt and 'manipulation' not in prompt and 'pullout_local_m' not in prompt
    assert '"object_type": "computer"' in prompt and '"verb": "use"' in prompt
    assert catalog == original
    old_json = json.dumps(list(catalog))
    compact_json = json.dumps(projected, ensure_ascii=False, separators=(',', ':'))
    assert len(compact_json) < len(old_json) * .3
