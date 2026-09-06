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
                        'asset_url': '/motion-assets/walk', 'loop': True, 'description': 'Walk naturally'}]
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
                                       {'duration': float('nan')}, {'loop': 'yes'}, {'name': '../secret'}])
def test_invalid_metadata_is_not_advertised(client, companion_root, overrides):
    install(companion_root, **overrides)
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
    install(companion_root)
    with client.websocket_connect('/ws') as ws:
        ws.receive_json()
        ws.send_json({'type': 'chat', 'turn_id': 'motions', 'character': 'alpha', 'text': '歩いて', 'voice': False})
        collect(ws, lambda e: e['type'] == 'done' and e.get('turn_id') == 'motions')
        request = next(iter(client.app.state.connections)).turn.req
        assert 'walk' in request.gestures and 'wave' in request.gestures
        assert request.motion_descriptions['walk'] == 'Walk naturally'
    # Procedural /motions keeps its existing shape; binary clips have their own catalog.
    assert all(m['name'] != 'walk' for m in client.get('/motions').json()['motions'])


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
