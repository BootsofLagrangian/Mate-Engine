import json
import pytest
from engine.motions import MotionError, validate_motion


def custom(duration=2.0, keys=None, bone='head'):
    keys = keys or [{'time': 0, 'x': 0, 'y': 0, 'z': 0}, {'time': 1, 'x': 12, 'y': 0, 'z': 0}, {'time': duration, 'x': 0, 'y': 0, 'z': 0}]
    return {'name': 'tilt', 'duration': duration, 'tracks': [{'bone': bone, 'keys': keys}]}


def test_validate_motion_accepts_bank_shape():
    motion = validate_motion('tilt', custom())
    assert motion['custom'] and motion['tracks'][0]['keys'][1] == {'time': 1.0, 'x': 12.0, 'y': 0.0, 'z': 0.0}


@pytest.mark.parametrize('mutate,expected', [
    (lambda m: m.update(name='other'), 'name must equal'),
    (lambda m: m.update(duration=0), 'duration'),
    (lambda m: m['tracks'][0].update(bone='tail'), 'Unknown VRM bone'),
    (lambda m: m['tracks'][0]['keys'].__setitem__(1, {'time': 0, 'x': 1, 'y': 0, 'z': 0}), 'strictly increase'),
    (lambda m: m['tracks'][0]['keys'].__setitem__(2, {'time': 2, 'x': 5, 'y': 0, 'z': 0}), 'return to idle'),
    (lambda m: m['tracks'][0]['keys'].__setitem__(1, {'time': 0.01, 'x': 80, 'y': 0, 'z': 0}), 'angular speed'),
    (lambda m: m['tracks'][0]['keys'].__setitem__(1, {'time': 1, 'x': float('nan'), 'y': 0, 'z': 0}), 'finite'),
    (lambda m: m['tracks'][0]['keys'].__setitem__(1, {'time': 1, 'x': 170, 'y': 0, 'z': 0}), 'within'),
    (lambda m: m.update(tracks=[]), 'non-empty'),
    (lambda m: m.update(tracks=m['tracks'] * 2), 'Duplicate'),
])
def test_validate_motion_rejects(mutate, expected):
    body = custom()
    mutate(body)
    with pytest.raises(MotionError, match=expected):
        validate_motion('tilt', body)


def test_invalid_ids():
    with pytest.raises(MotionError):
        validate_motion('../x', custom())
    with pytest.raises(MotionError):
        validate_motion('', custom())


def test_motion_endpoints_persist_custom_entries(client, tmp_path):
    builtin = client.get('/motions').json()
    names = [m['name'] for m in builtin['motions']]
    assert names[:2] == ['idle', 'nod'] and builtin['version'] == 1
    r = client.put('/motions/tilt', json=custom())
    assert r.status_code == 200 and r.json()['motion']['name'] == 'tilt'
    saved = json.loads((tmp_path / 'user-data/motions/tilt.json').read_text())
    assert saved['custom'] is True
    merged = client.get('/motions').json()
    assert [m['name'] for m in merged['motions']] == names + ['tilt']
    assert client.put('/motions/nod', json=custom() | {'name': 'nod'}).status_code == 422
    assert client.put('/motions/tilt', json=custom() | {'duration': 999}).status_code == 422
    assert client.put('/motions/Bad', json=custom()).status_code == 422
    assert client.delete('/motions/tilt').status_code == 200
    assert client.delete('/motions/tilt').status_code == 404
    assert [m['name'] for m in client.get('/motions').json()['motions']] == names
