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
        if not isinstance(entry, dict) or set(entry) - {'id', 'verbs', 'sockets', 'appearances', 'bounds', 'perception', 'version', 'spatial'} or not {'id', 'verbs', 'sockets', 'appearances', 'bounds'} <= set(entry):
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
