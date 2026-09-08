"""Declarative native furniture capabilities; no executable code or geometry."""
import math
import re

IDENTIFIER = re.compile(r'^[a-z][a-z0-9_]{0,39}$')
VERBS = ('place', 'sit', 'use', 'inspect', 'hide', 'remove', 'configure', 'appearance')


def identifiers(value, limit):
    if not isinstance(value, list) or len(value) > limit or any(not isinstance(v, str) or not IDENTIFIER.fullmatch(v) for v in value) or len(set(value)) != len(value):
        raise ValueError('capability identifiers must be distinct bounded names')
    return sorted(value)


def validate_catalog(value):
    if not isinstance(value, list) or len(value) > 8:
        raise ValueError('furniture_catalog must contain at most eight installed capabilities')
    result, seen = [], set()
    for entry in value:
        if not isinstance(entry, dict) or set(entry) - {'id', 'verbs', 'sockets', 'appearances', 'bounds', 'perception', 'version', 'spatial', 'interaction_anchors', 'manipulation', 'anchor_contract'} or not {'id', 'verbs', 'sockets', 'appearances', 'bounds'} <= set(entry):
            raise ValueError('furniture capability requires id, verbs, sockets, appearances, bounds')
        if type(entry.get('version', 1)) is not int or entry.get('version', 1) != 1:
            raise ValueError('unsupported furniture descriptor version')
        name = entry['id']
        if not isinstance(name, str) or not IDENTIFIER.fullmatch(name) or name in seen:
            raise ValueError('invalid or duplicate furniture capability id')
        verbs = identifiers(entry['verbs'], 8)
        if not verbs or any(v not in VERBS for v in verbs):
            raise ValueError('unsupported furniture verb')
        bounds = entry['bounds']
        if not isinstance(bounds, dict) or set(bounds) != {'scale', 'yaw_deg'}:
            raise ValueError('bounds require scale and yaw_deg')
        clean_bounds = {}
        for key, lower, upper in (('scale', .5, 1.8), ('yaw_deg', -180, 180)):
            pair = bounds[key]
            if not isinstance(pair, list) or len(pair) != 2 or any(isinstance(v, bool) or not isinstance(v, (int,float)) or not math.isfinite(v) for v in pair) or not lower <= pair[0] <= pair[1] <= upper:
                raise ValueError('invalid furniture parameter bounds')
            clean_bounds[key] = [float(v) for v in pair]
        perception = entry.get('perception', {'mode':'geometry_only','available':True,'reachable':'unknown','reason':''})
        if (not isinstance(perception, dict) or set(perception) - {'mode','available','reachable','reason'} or not {'mode','available','reason'} <= set(perception)
                or perception['mode'] != 'geometry_only' or not isinstance(perception['available'], bool)
                or perception.get('reachable', 'unknown') not in ('unknown','yes','no') or not isinstance(perception['reason'], str)
                or len(perception['reason']) > 64 or any(c not in 'abcdefghijklmnopqrstuvwxyz_' for c in perception['reason'])):
            raise ValueError('invalid geometry-only perception state')
        result.append({'id': name, 'version': 1, 'perception': {**perception, 'reachable': perception.get('reachable', 'unknown')}, 'verbs': verbs, 'sockets': identifiers(entry['sockets'], 16),
                       'appearances': identifiers(entry['appearances'], 16), 'bounds': clean_bounds})
        if 'spatial' in entry:
            result[-1]['spatial'] = validate_spatial(entry['spatial'])
        if 'interaction_anchors' in entry:
            result[-1]['interaction_anchors'] = validate_anchors(entry['interaction_anchors'], result[-1]['sockets'], verbs)
        if 'manipulation' in entry:
            result[-1]['manipulation'] = validate_manipulation(entry['manipulation'], result[-1].get('interaction_anchors', {}))
        if 'anchor_contract' in entry:
            result[-1]['anchor_contract'] = validate_anchor_contract(entry['anchor_contract'])
        seen.add(name)
    return tuple(sorted(result, key=lambda e:e['id']))


def legacy_catalog(types):
    return tuple({'id': name, 'verbs': ['place','inspect','hide','remove', 'use' if name == 'computer' else 'sit'],
                  'sockets': [], 'appearances': [], 'bounds': {'scale':[.5,1.8], 'yaw_deg':[-180,180]}} for name in types)


def validate_spatial(value):
    if not isinstance(value, dict) or set(value) != {'frame','bounds'} or value['frame'] != 'desktop_scene_v1':
        raise ValueError('unsupported furniture spatial frame')
    bounds = value['bounds']
    if not isinstance(bounds, dict) or set(bounds) != {'x','y','z'}:
        raise ValueError('spatial bounds require x, y, z')
    clean = {}
    for axis in ('x','y','z'):
        pair = bounds[axis]
        if not isinstance(pair,list) or len(pair)!=2 or any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in pair) or not -20 <= pair[0] <= pair[1] <= 20:
            raise ValueError('spatial bounds exceed native storage limits')
        clean[axis] = [float(v) for v in pair]
    return {'frame':'desktop_scene_v1','bounds':clean}


def _unit_vector(value):
    if (not isinstance(value, list) or len(value) != 3
            or any(type(v) not in (int, float) or not math.isfinite(v) or abs(v) > 1 for v in value)
            or not math.isclose(sum(v*v for v in value), 1., abs_tol=1e-5)):
        raise ValueError('anchor orientation requires a finite unit vector')
    return [float(v) for v in value]


def validate_anchors(value, sockets, verbs):
    if not isinstance(value, dict) or len(value) > 16:
        raise ValueError('at most sixteen named interaction anchors')
    identifiers(list(value), 16)
    result = {}
    required = {'socket', 'frame', 'role', 'verbs', 'facing', 'up', 'execution'}
    roles = ('pelvis', 'gaze', 'standing', 'hand_left', 'hand_right', 'work')
    for name, entry in value.items():
        if not isinstance(entry, dict) or set(entry) != required:
            raise ValueError('unsupported interaction anchor fields')
        if entry['socket'] not in sockets or entry['frame'] not in ('object', 'seat') or entry['role'] not in roles:
            raise ValueError('invalid anchor socket, frame or role')
        actions = identifiers(entry['verbs'], 8)
        if any(v not in verbs for v in actions) or entry['execution'] not in ('existing', 'reference_only'):
            raise ValueError('anchor cannot introduce unadvertised executable verbs')
        facing, up = _unit_vector(entry['facing']), _unit_vector(entry['up'])
        if abs(sum(a*b for a, b in zip(facing, up))) > 1e-5:
            raise ValueError('anchor facing and up must be perpendicular')
        result[name] = {**entry, 'verbs': actions, 'facing': facing, 'up': up}
    return result


def validate_manipulation(value, anchors):
    if value == {}:
        return {}
    required = {'version', 'component', 'actor_anchor', 'hand_anchors', 'translation', 'rotation', 'actions', 'admission'}
    if not isinstance(value, dict) or set(value) != required or type(value['version']) not in (int, float) or value['version'] != 1 or value['component'] != 'seat':
        raise ValueError('unsupported manipulation contract')
    actor = value['actor_anchor']
    hands = identifiers(value['hand_anchors'], 2)
    if (not isinstance(actor, str) or actor not in anchors or anchors[actor]['role'] != 'standing'
            or len(hands) != 2 or any(h not in anchors for h in hands)
            or {anchors[h]['role'] for h in hands} != {'hand_left', 'hand_right'}):
        raise ValueError('manipulation requires standing and two distinct hand anchors')
    constraints = {}
    for key, parameter, axis, lower, upper in (
            ('translation', 'pullout_local_m', [0, 0, 1], 0, 1.2),
            ('rotation', 'yaw_delta_deg', [0, 1, 0], -180, 180)):
        constraint = value[key]
        if (not isinstance(constraint, dict) or set(constraint) != {'frame', 'axis', 'parameter', 'limits'}
                or constraint['frame'] != 'object' or constraint['parameter'] != parameter
                or _unit_vector(constraint['axis']) != axis):
            raise ValueError('unsupported manipulation constraint frame or axis')
        pair = constraint['limits']
        if (not isinstance(pair, list) or len(pair) != 2
                or any(type(v) not in (int, float) or not math.isfinite(v) for v in pair)
                or not lower <= pair[0] <= pair[1] <= upper):
            raise ValueError('manipulation limits exceed native component bounds')
        constraints[key] = {**constraint, 'axis': [float(v) for v in axis], 'limits': [float(v) for v in pair]}
    actions = value['actions']
    if not isinstance(actions, dict) or set(actions) != {'push', 'pull'}:
        raise ValueError('unsupported manipulation action mapping')
    for name, sign in (('push', -1), ('pull', 1)):
        action = actions[name]
        if (not isinstance(action, dict) or set(action) != {'parameter', 'sign'}
                or action['parameter'] != 'pullout_local_m' or type(action['sign']) not in (int, float)
                or action['sign'] != sign):
            raise ValueError('invalid manipulation direction mapping')
    admission = value['admission']
    if not isinstance(admission, str) or len(admission) > 200 or any(ord(c) < 32 or ord(c) > 126 for c in admission):
        raise ValueError('invalid manipulation admission description')
    return {**value, **constraints, 'version': 1, 'hand_anchors': hands,
            'actions': {name: dict(action) for name, action in actions.items()}}


def validate_anchor_contract(value):
    expected = {'version': 1, 'position_units': 'metres', 'facing': 'unit_vector',
                'approach': 'reference_only; authored clip and collision admission determine final entry',
                'reference_only': 'not an executable verb'}
    if not isinstance(value, dict) or type(value.get('version')) is not int or value != expected:
        raise ValueError('unsupported anchor contract')
    return dict(expected)
