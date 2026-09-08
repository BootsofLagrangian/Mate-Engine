"""Manifest/download checks with small declared VRMA containers (no real animation/GPU)."""
import hashlib
import json
import struct
import pytest
from conftest import collect
from engine.motion_assets import MotionAssets


def fake_vrma():
    document = {'asset': {'version': '2.0'}, 'animations': [{'name': 'test'}],
                'extensions': {'VRMC_vrm_animation': {'specVersion': '1.0'}}}
    payload = json.dumps(document).encode()
    payload += b' ' * (-len(payload) % 4)
    return struct.pack('<4sIIII', b'glTF', 2, 20 + len(payload), len(payload), 0x4E4F534A) + payload


def install(root, **overrides):
    data = fake_vrma()
    path = root / 'assets/motions/walk.vrma'
    path.parent.mkdir(exist_ok=True)
    path.write_bytes(data)
    entry = {'name': 'walk', 'path': 'assets/motions/walk.vrma', 'duration': 1.25,
             'sha256': hashlib.sha256(data).hexdigest(), 'loop': True, 'description': 'Walk naturally'}
    entry.update(overrides)
    (root / 'motion-assets.json').write_text(json.dumps({'version': 1, 'motions': [entry]}))
    return entry, data, path


def test_catalog_download_and_hash_metadata(client, companion_root):
    assert client.get('/motion-assets').json() == {'motions': []}
    entry, data, _ = install(companion_root)
    catalog = client.get('/motion-assets').json()['motions']
    assert catalog == [{'name': 'walk', 'kind': 'vrma', 'duration': 1.25, 'sha256': entry['sha256'],
                        'asset_url': '/motion-assets/walk', 'loop': True, 'description': 'Walk naturally',
                        'locomotion': False, 'locomotion_priority': 0, 'locomotion_preserve_hips': False}]
    response = client.get(catalog[0]['asset_url'])
    assert response.status_code == 200 and response.content == data
    assert response.headers['content-type'] == 'model/gltf-binary'
    assert response.headers['etag'] == '"' + hashlib.sha256(response.content).hexdigest() + '"'
    assert 'path' not in catalog[0]
    assert client.get('/motion-assets/unlisted').status_code == 404
    assert client.get('/motion-assets/..%2F..%2Fconfig.json').status_code == 404


@pytest.mark.parametrize('path', ['../../secret.vrma', '/tmp/secret.vrma', 'assets/motions/../../secret.vrma',
                                 'assets/reference.wav', 'assets/motions/clip.txt', 'C:\\secret.vrma',
                                 'assets/motions/..\\secret.vrma'])
def test_manifest_paths_cannot_escape_motion_directory(client, companion_root, path):
    install(companion_root, path=path)
    assert client.get('/motion-assets').json()['motions'] == []
    assert client.get('/motion-assets/walk').status_code == 404


def test_symlink_escape_missing_file_and_replaced_file_are_not_served(client, companion_root, tmp_path):
    entry, data, path = install(companion_root)
    assert client.get('/motion-assets/walk').status_code == 200  # warm validation cache
    path.unlink()
    assert client.get('/motion-assets').json()['motions'] == []
    assert client.get('/motion-assets/walk').status_code == 404
    outside = tmp_path / 'outside.vrma'
    outside.write_bytes(data)
    path.symlink_to(outside)
    assert client.get('/motion-assets/walk').status_code == 404
    path.unlink()
    path.write_bytes(data)
    assert client.get('/motion-assets/walk').status_code == 200
    path.write_bytes(data[:-1] + b'\n')  # same size, changed checksum; cached validation must expire
    assert client.get('/motion-assets/walk').status_code == 404


@pytest.mark.parametrize('overrides', [{'sha256': 'f' * 64}, {'sha256': 'not-a-hash'}, {'duration': -1},
                                       {'duration': float('nan')}, {'loop': 'yes'}, {'ambient': 'yes'}, {'name': '../secret'}])
def test_invalid_metadata_is_not_advertised(client, companion_root, overrides):
    install(companion_root, **overrides)
    assert client.get('/motion-assets').json()['motions'] == []


def test_ambient_capability_survives_catalogue_validation(client, companion_root):
    install(companion_root, ambient=True)
    assert client.get('/motion-assets').json()['motions'][0]['ambient'] is True


@pytest.mark.parametrize('contact_mode', ['', 'foot'])
def test_contact_mode_survives_catalog_validation(client, companion_root, contact_mode):
    install(companion_root, contact_mode=contact_mode)
    assert client.get('/motion-assets').json()['motions'][0]['contact_mode'] == contact_mode


@pytest.mark.parametrize('contact_mode', ['hand', 'Foot', True, None, 0, [], {}])
def test_invalid_contact_mode_is_not_advertised(client, companion_root, contact_mode):
    install(companion_root, contact_mode=contact_mode)
    assert client.get('/motion-assets').json()['motions'] == []


def test_non_animation_binary_and_broken_manifest_are_ignored(client, companion_root):
    entry, _, path = install(companion_root)
    data = b'private arbitrary file'
    path.write_bytes(data)
    entry['sha256'] = hashlib.sha256(data).hexdigest()
    (companion_root / 'motion-assets.json').write_text(json.dumps({'version': 1, 'motions': [entry]}))
    assert client.get('/motion-assets/walk').status_code == 404
    (companion_root / 'motion-assets.json').write_text('{')
    assert client.get('/motion-assets').json() == {'motions': []}


def test_installed_vrma_names_join_llm_allow_list(client, companion_root):
    install(companion_root, name='authored_wave', loop=False, description='One friendly hand wave')
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'turn_id': 'motions', 'character': 'alpha', 'text': '歩いて', 'voice': False})
        collect(ws, lambda e: e['type'] == 'done' and e.get('turn_id') == 'motions')
        request = next(iter(client.app.state.connections)).turn.req
        assert 'authored_wave' in request.gestures and 'wave' in request.gestures
        assert 'walk' not in request.gestures
        assert request.motion_descriptions['authored_wave'] == 'One friendly hand wave'
    # Procedural /motions keeps its existing shape; binary clips have their own catalog.
    assert all(m['name'] != 'authored_wave' for m in client.get('/motions').json()['motions'])


def test_replacement_during_download_does_not_serve_wrong_etag(client, companion_root, monkeypatch):
    _, data, path = install(companion_root)
    assets = client.app.state.motion_assets
    resolve = assets.resolve
    def replaced(name):
        validated = resolve(name)
        path.write_bytes(data[:-1] + b'\n')
        return validated
    monkeypatch.setattr(assets, 'resolve', replaced)
    assert client.get('/motion-assets/walk').status_code == 404


@pytest.mark.parametrize('locomotion,priority', [(True, 0), (True, 50), (True, 100), (False, 10)])
def test_locomotion_capability_catalog_round_trip(client, companion_root, locomotion, priority):
    install(companion_root, locomotion=locomotion, locomotion_priority=priority, locomotion_preserve_hips=locomotion)
    entry = client.get('/motion-assets').json()['motions'][0]
    assert entry['locomotion'] is locomotion and entry['locomotion_priority'] == priority
    assert entry['locomotion_preserve_hips'] is locomotion
    assert client.get(entry['asset_url']).status_code == 200


@pytest.mark.parametrize('overrides', [
    {field: value} for field in ['locomotion', 'locomotion_preserve_hips'] for value in [1, 0, 'true', None, [], {}]
] + [{'locomotion_priority': value} for value in [-1, 101, True, False, 1.5, 10.0, '50', None, [], {}]])
def test_invalid_locomotion_metadata_not_advertised_or_served(client, companion_root, overrides):
    install(companion_root, **overrides)
    assert client.get('/motion-assets').json()['motions'] == []
    assert client.get('/motion-assets/walk').status_code == 404


def test_seated_transition_and_authored_gait_metadata(companion_root):
    style = {'version': 1, 'cycle_stride_leg_lengths': 1.8,
             'contacts': {'left': [0.05, 0.45], 'right': [0.55, 0.95]},
             'hip_translation_limit_leg_lengths': 0.2}
    install(companion_root, locomotion=True, locomotion_style=style, seated_transition='enter')
    entry = MotionAssets(companion_root).catalog()['motions'][0]
    assert entry['locomotion_style'] == style
    assert entry['seated_transition'] == 'enter'


@pytest.mark.parametrize('overrides', [
    {'seated_transition': 'sit'}, {'seated_transition': 1},
    {'locomotion_style': []},
    {'locomotion': True, 'locomotion_style': {'version': 1}},
    {'locomotion': True, 'locomotion_style': {'version': 1, 'cycle_stride_leg_lengths': 1.8,
      'contacts': {'left': [[0.0, 0.5], [0.4, 0.7]], 'right': [0.5, 0.9]}}},
])
def test_invalid_seat_and_gait_metadata_is_not_published(companion_root, overrides):
    install(companion_root, **overrides)
    assert MotionAssets(companion_root).catalog()['motions'] == []


def test_context_phases_remain_catalogued_but_not_standalone_gestures(companion_root):
    from engine.motion_assets import available_motions
    class EmptyBank:
        def bank(self): return {'motions': []}
    assets = MotionAssets(companion_root)
    for overrides in [
        {'seated_transition': 'enter'},
        {'seated_transition': 'exit'},
        {'locomotion': True},
        {'locomotion': True, 'locomotion_style': {'version': 1, 'cycle_stride_leg_lengths': 1.8,
          'contacts': {'left': [0.05, 0.45], 'right': [0.55, 0.95]}}},
    ]:
        install(companion_root, name='context_action', **overrides)
        assert len(assets.catalog()['motions']) == 1
        assert assets.resolve('context_action') is not None
        assert available_motions(EmptyBank(), assets) == []
    install(companion_root, name='everyday_wave', loop=False)
    assert [x['name'] for x in available_motions(EmptyBank(), assets)] == ['everyday_wave']


def test_internal_seated_idle_is_not_a_standalone_gesture(companion_root):
    from engine.motion_assets import available_motions
    class EmptyBank:
        def bank(self): return {'motions': []}
    install(companion_root, name='sit_idle')
    assets = MotionAssets(companion_root)
    assert assets.catalog()['motions'][0]['name'] == 'sit_idle'
    assert assets.resolve('sit_idle') is not None
    assert available_motions(EmptyBank(), assets) == []


@pytest.mark.parametrize('name', ['walk', 'walk_formal', 'sit_enter', 'sit_exit', 'sit_idle', 'floor_rest_enter', 'floor_rest_idle', 'floor_rest_exit'])
def test_reserved_context_names_cannot_leak_from_old_catalog_or_bank(companion_root, name):
    from engine.motion_assets import available_motions
    install(companion_root, name=name)
    assets = MotionAssets(companion_root)
    class Bank:
        def bank(self):
            return {'motions': [{'name': name}, {'name': 'everyday_custom', 'description': 'Small upper-body wave'}]}
    assert assets.read(name) is not None
    assert [entry['name'] for entry in available_motions(Bank(), assets)] == ['everyday_custom']


def test_finite_everyday_metadata_is_preserved_for_dialogue(companion_root):
    from engine.motion_assets import available_motions
    install(companion_root, name='authored_wave', loop=False, ambient=False, contact_mode='foot',
            description='One friendly hand wave')
    class Bank:
        def bank(self): return {'motions': []}
    assets = MotionAssets(companion_root)
    assert available_motions(Bank(), assets) == assets.catalog()['motions']


@pytest.mark.parametrize('metadata', [{'locomotion': True}, {'seated_transition': 'enter'}, {'seated_transition': 'exit'}])
def test_bank_shadow_cannot_strip_installed_context_ownership(companion_root, metadata):
    from engine.motion_assets import available_motions
    install(companion_root, name='portable_context', **metadata)
    class Bank:
        def bank(self): return {'motions': [{'name': 'portable_context'}, {'name': 'wave'}]}
    assets = MotionAssets(companion_root)
    assert assets.read('portable_context') is not None
    assert available_motions(Bank(), assets) == [{'name': 'wave'}]
