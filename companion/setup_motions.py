#!/usr/bin/env python3
"""Convert the freely downloaded Quaternius Standard GLB into local VRMA clips.

Obtain the free Standard ZIP at https://quaternius.itch.io/universal-animation-library
and pass --ual-zip. Source is CC0; the conversion retains rest transforms and exact
rotation samples. Translation is intentionally pinned by the desktop player.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parent
CLIPS = {
    'idle_natural': ('Idle_Loop', True, 'Relaxed standing idle'),
    'idle_talking': ('Idle_Talking_Loop', True, 'Small conversational body gestures'),
    'walk': ('Walk_Loop', True, 'Walking, root stays on the desktop anchor'),
    'walk_formal': ('Walk_Formal_Loop', True, 'Measured walking'),
    'dance': ('Dance_Loop', False, 'Celebratory dance'),
    'interact': ('Interact', False, 'Reach to interact with a nearby object'),
    'pick_up': ('PickUp_Table', False, 'Pick up an object at table height'),
    'sit_idle': ('Sitting_Idle_Loop', True, 'Seated idle; requires a chosen sitting location'),
}


def bone_names():
    mapping = {'pelvis': 'hips', 'spine_01': 'spine', 'spine_02': 'chest', 'spine_03': 'upperChest',
               'neck_01': 'neck', 'Head': 'head'}
    for short, side in [('l', 'left'), ('r', 'right')]:
        for source, target in [('clavicle', 'Shoulder'), ('upperarm', 'UpperArm'), ('lowerarm', 'LowerArm'),
                               ('hand', 'Hand'), ('thigh', 'UpperLeg'), ('calf', 'LowerLeg'), ('foot', 'Foot'), ('ball', 'Toes')]:
            mapping[f'{source}_{short}'] = side + target
        for source, target in [('thumb', 'Thumb'), ('index', 'Index'), ('middle', 'Middle'), ('ring', 'Ring'), ('pinky', 'Little')]:
            parts = ['Metacarpal', 'Proximal', 'Distal'] if source == 'thumb' else ['Proximal', 'Intermediate', 'Distal']
            for i, part in enumerate(parts, 1):
                mapping[f'{source}_{i:02}_{short}'] = side + target + part
    return mapping


def read_glb(blob):
    magic, version, total = struct.unpack_from('<III', blob)
    if magic != 0x46546C67 or version != 2 or total != len(blob):
        raise ValueError('Expected complete GLB v2')
    chunks = {}; offset = 12
    while offset < len(blob):
        length, kind = struct.unpack_from('<II', blob, offset)
        chunks[kind] = blob[offset + 8:offset + 8 + length]
        offset += 8 + length
    return json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]


def convert(data, binary, animation):
    names = bone_names()
    bones = {names[node['name']]: {'node': i} for i, node in enumerate(data['nodes']) if node.get('name') in names}
    for required in ['hips', 'head', 'leftUpperArm', 'rightUpperArm', 'leftFoot', 'rightFoot']:
        if required not in bones:
            raise ValueError('Source humanoid mapping missing ' + required)
    nodes = copy.deepcopy(data['nodes'])
    for node in nodes:
        for field in ['mesh', 'skin', 'camera', 'weights']:
            node.pop(field, None)
        if 'matrix' in node:
            raise ValueError('Matrix nodes need decomposition before VRMA conversion')
    out = {'asset': {'version': '2.0', 'generator': 'Mate companion Quaternius Standard to VRMA'},
           'nodes': nodes, 'scenes': data['scenes'], 'scene': data.get('scene', 0),
           'extensionsUsed': ['VRMC_vrm_animation'], 'extensionsRequired': ['VRMC_vrm_animation'],
           'extensions': {'VRMC_vrm_animation': {'specVersion': '1.0', 'humanoid': {'humanBones': bones}}},
           'accessors': [], 'bufferViews': [], 'animations': []}
    packed = bytearray(); accessor_ids = {}; duration = 0
    def accessor(index):
        nonlocal duration
        if index in accessor_ids:
            return accessor_ids[index]
        a = data['accessors'][index]
        if a['componentType'] != 5126 or 'sparse' in a:
            raise ValueError('Expected dense float animation accessor')
        widths = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}
        width = widths[a['type']] * 4
        view = data['bufferViews'][a['bufferView']]
        stride = view.get('byteStride', width)
        offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        if offset + (a['count'] - 1) * stride + width > len(binary):
            raise ValueError('Truncated source accessor')
        blob = b''.join(binary[offset+i*stride:offset+i*stride+width] for i in range(a['count']))
        start = len(packed); packed.extend(blob)
        v = len(out['bufferViews']); out['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': len(blob)})
        new = {k: copy.deepcopy(v) for k, v in a.items() if k not in ('bufferView', 'byteOffset')}
        new['bufferView'] = v
        result = len(out['accessors']); out['accessors'].append(new); accessor_ids[index] = result
        if a['type'] == 'SCALAR':
            duration = max(duration, max(struct.unpack('<' + 'f'*a['count'], blob)))
        return result
    anim = {'name': animation['name'], 'channels': [], 'samplers': []}
    target_nodes = {v['node'] for v in bones.values()}
    for channel in animation['channels']:
        if channel['target']['path'] != 'rotation' or channel['target']['node'] not in target_nodes:
            continue
        sampler = animation['samplers'][channel['sampler']]
        if sampler.get('interpolation', 'LINEAR') not in ('LINEAR', 'STEP'):
            raise ValueError('Unsupported interpolation')
        s = {'input': accessor(sampler['input']), 'output': accessor(sampler['output']),
             'interpolation': sampler.get('interpolation', 'LINEAR')}
        anim['channels'].append({'target': channel['target'], 'sampler': len(anim['samplers'])}); anim['samplers'].append(s)
    out['animations'].append(anim)
    out['buffers'] = [{'byteLength': len(packed)}]
    js = json.dumps(out, separators=(',', ':')).encode(); js += b' ' * (-len(js) % 4)
    packed.extend(b'\0' * (-len(packed) % 4))
    encoded = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(packed))
    encoded += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(packed), 0x004E4942) + packed
    return encoded, duration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ual-zip', type=Path, required=True)
    args = parser.parse_args()
    target = ROOT / 'assets/motions'; target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.ual_zip) as z:
        source_name = next(n for n in z.namelist() if n.endswith('/Unreal-Godot/UAL1_Standard.glb'))
        source = z.read(source_name)
        license_name = next(n for n in z.namelist() if n.endswith('/License.txt'))
        (target / 'Quaternius-LICENSE.txt').write_bytes(z.read(license_name))
    data, binary = read_glb(source)
    animations = {a['name']: a for a in data['animations']}
    entries = []
    for name, (original, loop, description) in CLIPS.items():
        blob, duration = convert(data, binary, animations[original])
        relative = f'assets/motions/{name}.vrma'
        (ROOT / relative).write_bytes(blob)
        entries.append({'name': name, 'path': relative, 'kind': 'vrma', 'duration': round(duration, 5), 'loop': loop,
                        'description': description, 'sha256': hashlib.sha256(blob).hexdigest(), 'source_clip': original,
                        'source': 'https://quaternius.itch.io/universal-animation-library', 'license': 'CC0-1.0'})
        print(name, round(duration, 2), len(blob))
    manifest = {'version': 1, 'source_sha256': hashlib.sha256(source).hexdigest(), 'motions': entries}
    (ROOT / 'motion-assets.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
