#!/usr/bin/env python3
"""Compare original Unity arm quaternion curves with both FBX export attempts.

Reads local research assets; it does not install a motion or change the source.
The FBX/GLB basis is the verified AssetStudio mirror-X conversion: quaternion
(x, -y, -z, w). Quaternion sign has no effect on the geodesic error.
"""
import bisect
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

COMPANION = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(COMPANION / 'diagnostics/authored_idle'))
from bake_humanoid import slerp
from convert_candidates import base
from sample_unity_curves import bake, read_clip


def angle(a, b):
    norm = math.sqrt(sum(x*x for x in a) * sum(x*x for x in b))
    return math.degrees(2*math.acos(min(1, abs(sum(x*y for x, y in zip(a, b))) / norm)))


def accessor(data, binary, index, width):
    item = data['accessors'][index]
    view = data['bufferViews'][item['bufferView']]
    offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', width*4)
    return [struct.unpack_from('<'+'f'*width, binary, offset+i*stride)
            for i in range(item['count'])]


def sample(times, values, t):
    i = bisect.bisect_right(times, t)
    if i == 0:
        return values[0]
    if i == len(times):
        return values[-1]
    return slerp(values[i-1], values[i], (t-times[i-1])/(times[i]-times[i-1]))


def main():
    source = COMPANION / 'assets/research/uma/export-work/natural-subset'
    candidates = COMPANION / 'assets/research/walking-candidates'
    paths = json.loads((source / 'fbx/rig.json').read_text())['avatars'][0]['paths']
    rows = []
    for suffix, alias in [('homewalk01_loop', 'uma_homewalk'),
                          ('homewalk01_U_loop', 'uma_homewalk_up'),
                          ('homewalk01_D_loop', 'uma_homewalk_down')]:
        yaml_path = source / 'yaml' / f'anm_eve_type00_{suffix}.anim'
        unity = bake(read_clip(yaml_path))
        variants = ['', '_filtered']
        if suffix == 'homewalk01_loop':
            variants.append('_direct')
        for variant in variants:
            glb = candidates / 'intermediate' / (alias + variant + '.glb')
            data, binary = base.read_glb(glb.read_bytes())
            for bone in ('Arm_L', 'Arm_R'):
                track = next(t for t in unity['tracks'] if t['property'] == 'rotation'
                             and paths.get(t['source_path'].removeprefix('path_'), '').endswith('/'+bone))
                reference = [(q[0], -q[1], -q[2], q[3]) for q in track['values']]
                node = next(i for i, n in enumerate(data['nodes']) if n.get('name') == bone)
                animation = data['animations'][0]
                channel = next(c for c in animation['channels']
                               if c['target'] == {'node': node, 'path': 'rotation'})
                sampler = animation['samplers'][channel['sampler']]
                times = [t[0] for t in accessor(data, binary, sampler['input'], 1)]
                values = accessor(data, binary, sampler['output'], 4)
                actual = [sample(times, values, t) for t in unity['times']]
                rows.append({'clip': suffix, 'bone': bone, 'euler_filter': variant != '',
                             'rotation_source': 'Unity Hermite' if variant == '_direct' else 'FBX Euler',
                             'samples': len(actual),
                             'unity_max_step_deg': max(angle(a, b) for a, b in zip(reference, reference[1:])),
                             'export_max_step_deg': max(angle(a, b) for a, b in zip(actual, actual[1:])),
                             'max_reference_error_deg': max(angle(a, b) for a, b in zip(reference, actual)),
                             'source_yaml_sha256': hashlib.sha256(yaml_path.read_bytes()).hexdigest(),
                             'intermediate_glb_sha256': hashlib.sha256(glb.read_bytes()).hexdigest()})
    output = Path(__file__).with_name('arm-continuity.json')
    output.write_text(json.dumps(rows, indent=2)+'\n')
    for row in rows:
        print(row['clip'], row['bone'], row['euler_filter'], row['rotation_source'],
              round(row['export_max_step_deg'], 3), round(row['max_reference_error_deg'], 3))


if __name__ == '__main__':
    main()
