#!/usr/bin/env python3
"""Offline candidates only: preserve translation tracks; never edit installed manifest.

General gesture playback pins translations. The explicit ambient layer now reads
normalized hips offsets; seat transitions still require contact-aware evaluation.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import zipfile

COMPANION = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('setup_motions', COMPANION / 'setup_motions.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


def pack(data, binary):
    data['buffers'] = [{'byteLength': len(binary)}]
    js = json.dumps(data, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    binary += b'\0' * (-len(binary) % 4)
    return (struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(binary))
            + struct.pack('<II', len(js), 0x4E4F534A) + js
            + struct.pack('<II', len(binary), 0x004E4942) + binary)


def convert(data, binary, animation):
    rotation_blob, duration = base.convert(data, binary, animation)
    out, packed = base.read_glb(rotation_blob)
    packed = bytearray(packed)
    tracks = []
    for channel in animation['channels']:
        if channel['target']['path'] != 'translation':
            continue
        sampler = animation['samplers'][channel['sampler']]
        ids, raw = [], []
        for source_id in (sampler['input'], sampler['output']):
            a = data['accessors'][source_id]
            width = {'SCALAR': 1, 'VEC3': 3}[a['type']]
            assert a['componentType'] == 5126 and 'sparse' not in a
            view = data['bufferViews'][a['bufferView']]
            offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
            stride = view.get('byteStride', width * 4)
            blob = b''.join(binary[offset+i*stride:offset+i*stride+width*4] for i in range(a['count']))
            view_id = len(out['bufferViews'])
            out['bufferViews'].append({'buffer': 0, 'byteOffset': len(packed), 'byteLength': len(blob)})
            packed.extend(blob)
            new = {k: copy.deepcopy(v) for k, v in a.items() if k not in ('bufferView', 'byteOffset')}
            new['bufferView'] = view_id
            ids.append(len(out['accessors']))
            out['accessors'].append(new)
            raw.append(struct.unpack('<'+'f'*(len(blob)//4), blob))
        target_animation = out['animations'][0]
        target_animation['channels'].append({'target': copy.deepcopy(channel['target']), 'sampler': len(target_animation['samplers'])})
        target_animation['samplers'].append({'input': ids[0], 'output': ids[1], 'interpolation': sampler.get('interpolation', 'LINEAR')})
        node = data['nodes'][channel['target']['node']]
        vectors = list(zip(*[iter(raw[1])]*3))
        tracks.append({'node': node.get('name'), 'samples': len(vectors),
                       'first': vectors[0], 'last': vectors[-1],
                       'range_source_units': [max(v[c] for v in vectors)-min(v[c] for v in vectors) for c in range(3)]})
    return pack(out, bytes(packed)), duration, tracks


def trim_export_bind_frame(data, binary):
    """Overte export has a bind calibration at t=0; retain motion from 1/30s.

    This is an explicit source-specific boundary correction, not smoothing or
    retiming the authored interior. Preserve original intermediate for audit.
    """
    def angle(a,b):
        dot = abs(sum(x*y for x,y in zip(a,b)))
        norm = math.sqrt(sum(x*x for x in a)*sum(x*x for x in b))
        return math.degrees(2*math.acos(min(1,dot/norm)))
    rest_errors, jumps = [], []
    animation = data['animations'][0]
    for channel in animation['channels']:
        if channel['target']['path'] != 'rotation':
            continue
        sampler = animation['samplers'][channel['sampler']]
        a = data['accessors'][sampler['output']]
        view = data['bufferViews'][a['bufferView']]
        offset = view.get('byteOffset',0)+a.get('byteOffset',0)
        first = struct.unpack_from('<ffff',binary,offset)
        second = struct.unpack_from('<ffff',binary,offset+view.get('byteStride',16))
        rest_errors.append(angle(first,data['nodes'][channel['target']['node']].get('rotation',[0,0,0,1])))
        jumps.append(angle(first,second))
    # idle_to_walk has a continuous first frame (~0.13deg), so preserve it.
    if max(rest_errors,default=1) > .001 or max(jumps,default=0) < 20:
        return binary
    packed = bytearray(binary)
    cache = {}
    for animation in data['animations']:
        for sampler in animation['samplers']:
            pair = (sampler['input'], sampler['output'])
            if pair in cache:
                sampler['input'], sampler['output'] = cache[pair]
                continue
            arrays = []
            for index in pair:
                a = data['accessors'][index]
                width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
                view = data['bufferViews'][a['bufferView']]
                offset = view.get('byteOffset', 0)+a.get('byteOffset', 0)
                stride = view.get('byteStride', width*4)
                arrays.append([struct.unpack_from('<'+'f'*width,binary,offset+i*stride) for i in range(a['count'])])
            keep = [i for i,t in enumerate(arrays[0]) if t[0] >= 1/30-1e-6]
            if not keep:
                raise ValueError('No samples beyond calibration frame')
            ids = []
            for column,index in enumerate(pair):
                a = data['accessors'][index]
                values = [(max(0, arrays[0][i][0]-1/30),) if column == 0 else arrays[1][i] for i in keep]
                flat = [v for row in values for v in row]
                blob = struct.pack('<'+'f'*len(flat),*flat)
                new = {k: copy.deepcopy(v) for k,v in a.items() if k not in ('bufferView','byteOffset','min','max')}
                new.update(count=len(keep),bufferView=len(data['bufferViews']))
                data['bufferViews'].append({'buffer':0,'byteOffset':len(packed),'byteLength':len(blob)})
                packed.extend(blob)
                ids.append(len(data['accessors']))
                data['accessors'].append(new)
            cache[pair] = ids
            sampler['input'],sampler['output'] = ids
    return bytes(packed)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ual-zip', type=Path, default=Path('/tmp/mate-ual-standard.zip'))
    p.add_argument('--output', type=Path, default=Path(__file__).parent / 'candidates')
    p.add_argument('--overte-glb', type=Path, help='Godot-exported Overte FBX intermediate')
    p.add_argument('--source-glb', type=Path, help='Generic FBX-derived GLB; requires --bone-map')
    p.add_argument('--bone-map', type=Path, help='JSON object mapping exact source names to VRM humanoid names')
    p.add_argument('--animation', help='Exact animation name, otherwise require a single animation')
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.source_glb:
        if not args.bone_map:
            p.error('--source-glb requires an explicit verified --bone-map')
        mapping = json.loads(args.bone_map.read_text())
        if len(mapping.values()) != len(set(mapping.values())):
            p.error('Each normalized humanoid bone must have one source owner')
        base.bone_names = lambda: mapping
        source = args.source_glb.read_bytes()
        data, binary = base.read_glb(source)
        source_names = [n.get('name') for n in data['nodes']]
        for name in mapping:
            if source_names.count(name) != 1:
                p.error(f'Mapped source bone must occur exactly once: {name}')
        animations = data.get('animations', [])
        selected = [a for a in animations if a.get('name') == args.animation] if args.animation else animations
        if len(selected) != 1:
            p.error('Select one exact animation with --animation')
        blob, duration, translations = convert(data, binary, selected[0])
        stem = args.source_glb.stem
        (args.output / (stem+'.vrma')).write_bytes(blob)
        (args.output / (stem+'.json')).write_text(json.dumps({'prototype_only': True, 'duration': duration,
            'source_glb_sha256': hashlib.sha256(source).hexdigest(), 'bone_map': mapping,
            'translations': translations, 'source_animation': selected[0].get('name')}, indent=2)+'\n')
        print(stem, duration, len(blob))
        return
    if args.overte_glb:
        source = args.overte_glb.read_bytes()
        mapping = {'Hips': 'hips', 'Spine': 'spine', 'Spine1': 'chest', 'Spine2': 'upperChest', 'Neck': 'neck', 'Head': 'head'}
        for side in ('Left', 'Right'):
            for original, normalized in [('Shoulder','Shoulder'), ('Arm','UpperArm'), ('ForeArm','LowerArm'), ('Hand','Hand'), ('UpLeg','UpperLeg'), ('Leg','LowerLeg'), ('Foot','Foot'), ('ToeBase','Toes')]:
                mapping[side+original] = side.lower()+normalized
            for finger in ('Thumb', 'Index', 'Middle', 'Ring', 'Pinky'):
                parts = ['Metacarpal', 'Proximal', 'Distal'] if finger == 'Thumb' else ['Proximal', 'Intermediate', 'Distal']
                for i, part in enumerate(parts, 1):
                    mapping[f'{side}Hand{finger}{i}'] = side.lower()+('Little' if finger == 'Pinky' else finger)+part
        base.bone_names = lambda: mapping
        data, binary = base.read_glb(source)
        binary = trim_export_bind_frame(data, binary)
        blob, duration, translations = convert(data, binary, data['animations'][0])
        stem = args.overte_glb.stem
        (args.output / (stem+'.vrma')).write_bytes(blob)
        (args.output / (stem+'.json')).write_text(json.dumps({'prototype_only': True, 'duration': duration, 'source_glb_sha256': hashlib.sha256(source).hexdigest(), 'translations': translations}, indent=2)+'\n')
        print(stem, duration, len(blob))
        return
    with zipfile.ZipFile(args.ual_zip) as archive:
        source = archive.read(next(n for n in archive.namelist() if n.endswith('/Unreal-Godot/UAL1_Standard.glb')))
        (args.output / 'LICENSE.txt').write_bytes(archive.read(next(n for n in archive.namelist() if n.endswith('/License.txt'))))
    data, binary = base.read_glb(source)
    entries = []
    for name in ('Sitting_Enter', 'Sitting_Exit', 'Sitting_Talking_Loop'):
        animation = next(a for a in data['animations'] if a['name'] == name)
        blob, duration, translations = convert(data, binary, animation)
        (args.output / (name.lower()+'.vrma')).write_bytes(blob)
        entries.append({'name': name, 'duration': duration, 'sha256': hashlib.sha256(blob).hexdigest(), 'translations': translations})
    report = {'prototype_only': True, 'source_sha256': hashlib.sha256(source).hexdigest(),
              'runtime_limitation': 'Current player ignores preserved translations; not an accepted seated transition.', 'clips': entries}
    (args.output / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
