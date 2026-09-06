"""Motion bank: built-in shared clips plus validated user-saved custom clips.

The bank shape is Assets/StreamingAssets/cheval-motions.json: additive local Euler
degrees on normalized VRM humanoid bones; every track starts and ends at zero so
the character returns to idle.
"""
import json
import math
import re
import threading
from pathlib import Path
from . import config

MOTION_ID = re.compile(r'^[a-z0-9][a-z0-9_-]{0,31}$')
VRM_BONES = {
    'hips', 'spine', 'chest', 'upperChest', 'neck', 'head', 'jaw', 'leftEye', 'rightEye',
    'leftShoulder', 'leftUpperArm', 'leftLowerArm', 'leftHand', 'rightShoulder', 'rightUpperArm', 'rightLowerArm', 'rightHand',
    'leftUpperLeg', 'leftLowerLeg', 'leftFoot', 'leftToes', 'rightUpperLeg', 'rightLowerLeg', 'rightFoot', 'rightToes',
} | {f'{side}{finger}{part}' for side in ('left', 'right') for finger in ('Thumb', 'Index', 'Middle', 'Ring', 'Little')
     for part in ('Proximal', 'Intermediate', 'Distal', 'Metacarpal')}
MAX_DEGREES = 90.0
MAX_DEG_PER_SECOND = 720.0
MIN_DURATION, MAX_DURATION = 0.2, 20.0
MAX_TRACKS, MAX_KEYS = 32, 256


class MotionError(ValueError):
    pass


def _number(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise MotionError(f'{name} must be a finite number')
    if not low <= value <= high:
        raise MotionError(f'{name} must be within [{low}, {high}]')
    return float(value)


def validate_motion(motion_id, body):
    """Return a normalized motion dict or raise MotionError with the actual problem."""
    if not MOTION_ID.fullmatch(motion_id or ''):
        raise MotionError('Motion id must match ^[a-z0-9][a-z0-9_-]{0,31}$')
    if not isinstance(body, dict):
        raise MotionError('Motion must be a JSON object')
    name = body.get('name', motion_id)
    if name != motion_id:
        raise MotionError('Motion name must equal the URL id')
    duration = _number(body.get('duration'), 'duration', MIN_DURATION, MAX_DURATION)
    tracks = body.get('tracks')
    if not isinstance(tracks, list) or not tracks:
        raise MotionError('tracks must be a non-empty list')
    if len(tracks) > MAX_TRACKS:
        raise MotionError(f'At most {MAX_TRACKS} tracks')
    seen = set()
    out_tracks = []
    for track in tracks:
        if not isinstance(track, dict):
            raise MotionError('Each track must be an object')
        bone = track.get('bone')
        if bone not in VRM_BONES:
            raise MotionError(f'Unknown VRM bone: {bone!r}')
        if bone in seen:
            raise MotionError(f'Duplicate track for bone {bone}')
        seen.add(bone)
        keys = track.get('keys')
        if not isinstance(keys, list) or len(keys) < 2:
            raise MotionError(f'Track {bone} needs at least two keys')
        if len(keys) > MAX_KEYS:
            raise MotionError(f'Track {bone} has more than {MAX_KEYS} keys')
        out_keys = []
        previous = None
        for key in keys:
            if not isinstance(key, dict):
                raise MotionError(f'Track {bone}: keys must be objects')
            t = _number(key.get('time'), f'{bone} key time', 0, duration)
            if previous is not None and t <= previous['time']:
                raise MotionError(f'Track {bone}: key times must strictly increase')
            angles = {axis: _number(key.get(axis, 0), f'{bone} {axis}', -MAX_DEGREES, MAX_DEGREES) for axis in 'xyz'}
            if previous is not None:
                dt = t - previous['time']
                speed = max(abs(angles[a] - previous[a]) for a in 'xyz') / dt
                if speed > MAX_DEG_PER_SECOND:
                    raise MotionError(f'Track {bone}: angular speed {speed:.0f} deg/s exceeds {MAX_DEG_PER_SECOND:.0f}')
            current = {'time': t, **angles}
            out_keys.append(current)
            previous = current
        if out_keys[0]['time'] != 0 or out_keys[-1]['time'] != duration:
            raise MotionError(f'Track {bone}: keys must start at 0 and end at duration')
        for edge in (out_keys[0], out_keys[-1]):
            if any(edge[a] != 0 for a in 'xyz'):
                raise MotionError(f'Track {bone}: first and last keys must be zero (return to idle)')
        out_tracks.append({'bone': bone, 'keys': out_keys})
    motion = {'name': motion_id, 'duration': duration, 'tracks': out_tracks, 'custom': True}
    if isinstance(body.get('description'), str):
        motion['description'] = body['description'][:200]
    return motion


class MotionBank:
    def __init__(self, bank_path=None, custom_dir=None):
        self.bank_path = Path(bank_path) if bank_path else config.motion_bank_path()
        self.custom_dir = Path(custom_dir) if custom_dir else config.user_data_dir() / 'motions'
        self._lock = threading.Lock()

    def builtin(self):
        data = json.loads(self.bank_path.read_text(encoding='utf-8'))
        if not isinstance(data, dict) or not isinstance(data.get('motions'), list):
            raise MotionError('Built-in motion bank is malformed')
        return data

    def builtin_names(self):
        return [m['name'] for m in self.builtin()['motions']]

    def customs(self):
        motions = []
        if not self.custom_dir.is_dir():
            return motions
        for path in sorted(self.custom_dir.glob('*.json')):
            try:
                motion = validate_motion(path.stem, json.loads(path.read_text(encoding='utf-8')))
            except (OSError, ValueError):
                continue  # a corrupt saved file must not take the whole bank down
            motions.append(motion)
        return motions

    def bank(self):
        data = self.builtin()
        builtin_names = {m['name'] for m in data['motions']}
        data['motions'] = data['motions'] + [m for m in self.customs() if m['name'] not in builtin_names]
        return data

    def names(self):
        return [m['name'] for m in self.bank()['motions']]

    def save(self, motion_id, body):
        motion = validate_motion(motion_id, body)
        if motion_id in self.builtin_names():
            raise MotionError(f'{motion_id} is a built-in motion and cannot be overwritten')
        with self._lock:
            self.custom_dir.mkdir(parents=True, exist_ok=True)
            target = self.custom_dir / f'{motion_id}.json'
            tmp = target.with_suffix('.json.tmp')
            tmp.write_text(json.dumps(motion, ensure_ascii=False, indent=2), encoding='utf-8')
            tmp.replace(target)
        return motion

    def delete(self, motion_id):
        if not MOTION_ID.fullmatch(motion_id or ''):
            raise MotionError('Invalid motion id')
        with self._lock:
            target = self.custom_dir / f'{motion_id}.json'
            if not target.is_file():
                return False
            target.unlink()
            return True
