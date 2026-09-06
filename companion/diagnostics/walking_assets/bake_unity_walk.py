#!/usr/bin/env python3
"""Preserve original Unity quaternion curves instead of interpolating FBX Euler.

Uses the verified FBX-derived rest skeleton and existing translations. Every
rotation channel is replaced from its original decompressed Unity Hermite curve,
resolved through the source Avatar's exact hash-to-path map. No guessed bones,
runtime changes, source mutation or installed-catalog mutation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

COMPANION = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(COMPANION / 'diagnostics/authored_idle'))
from bake_humanoid import bake as bake_humanoid
from convert_candidates import base, pack
from sample_unity_curves import bake as sample_unity, read_clip


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clip', default='homewalk01_loop')
    parser.add_argument('--intermediate', default='uma_homewalk')
    parser.add_argument('--alias', default='uma_homewalk_direct')
    parser.add_argument('--source-root', type=Path,
                        default=COMPANION / 'assets/research/uma/export-work/natural-subset')
    parser.add_argument('--research-root', type=Path,
                        default=COMPANION / 'assets/research/walking-candidates')
    args = parser.parse_args()
    research = args.research_root.resolve()
    source = args.source_root.resolve()
    yaml_path = source / 'yaml' / f'anm_eve_type00_{args.clip}.anim'
    rig_path = source / 'fbx/rig.json'
    paths = json.loads(rig_path.read_text())['avatars'][0]['paths']
    unity = sample_unity(read_clip(yaml_path))
    original = research / 'intermediate' / (args.intermediate + '.glb')
    if not original.exists():
        original.parent.mkdir(parents=True, exist_ok=True)
        fbx = source / 'fbx' / f'anm_eve_type00_{args.clip}.fbx'
        subprocess.run([str(COMPANION / 'tools/Godot_v4.5.2-stable_linux.x86_64'),
                        '--headless', '--path', str(COMPANION / 'native'),
                        '-s', 'tools/convert_overte_fbx.gd', '--', str(fbx), str(original)], check=True)
    data, binary = base.read_glb(original.read_bytes())
    packed = bytearray(binary)
    names = {}
    for i, node in enumerate(data['nodes']):
        name = node.get('name')
        if name in names:
            raise ValueError('Ambiguous source node: '+name)
        names[name] = i

    def accessor(rows, width):
        raw = struct.pack('<'+'f'*(len(rows)*width), *(v for row in rows for v in row))
        data['bufferViews'].append({'buffer': 0, 'byteOffset': len(packed), 'byteLength': len(raw)})
        packed.extend(raw)
        data['accessors'].append({'bufferView': len(data['bufferViews'])-1,
                                  'componentType': 5126, 'count': len(rows),
                                  'type': {1: 'SCALAR', 4: 'VEC4'}[width]})
        return len(data['accessors'])-1

    time_id = accessor([(t,) for t in unity['times']], 1)
    animation = data['animations'][0]
    replaced = []
    absent_from_rig = []
    for track in unity['tracks']:
        if track['property'] != 'rotation':
            continue
        path = paths.get(track['source_path'].removeprefix('path_'))
        if path is None:
            absent_from_rig.append(track['source_path'])
            continue
        node = names[path.rsplit('/', 1)[-1]]
        channels = [c for c in animation['channels']
                    if c['target'] == {'node': node, 'path': 'rotation'}]
        if len(channels) > 1:
            raise ValueError('Ambiguous rotation channels for '+path)
        if not channels:
            # FBX may omit constant source curves. Reintroduce the verified
            # original rather than relying on an importer-selected rest value.
            channels = [{'target': {'node': node, 'path': 'rotation'}}]
            animation['channels'].append(channels[0])
        # AssetStudio's verified Unity->FBX basis mirrors X. Quaternion signs
        # remain arbitrary, and the existing bake samples shortest-path SLERP.
        values = [(q[0], -q[1], -q[2], q[3]) for q in track['values']]
        channels[0]['sampler'] = len(animation['samplers'])
        animation['samplers'].append({'input': time_id, 'output': accessor(values, 4),
                                      'interpolation': 'LINEAR'})
        replaced.append(path)
    if len(replaced) != sum(c['target']['path'] == 'rotation' for c in animation['channels']):
        raise ValueError('Unverified rotation channels remain')
    intermediate = research / 'intermediate' / (args.alias+'.glb')
    intermediate.write_bytes(pack(data, bytes(packed)))
    mapping = json.loads((COMPANION / 'diagnostics/authored_idle/uma-bone-map.json').read_text())
    # Prop visibility/size tracks can animate Hand_Attach nodes. They cannot
    # affect humanoid FK when outside every mapped bone's ancestor chain.
    # Preserve these in the intermediate GLB and explicitly report exclusion
    # from the humanoid-only output; never drop scale on a humanoid ancestor.
    parents = {child: i for i, n in enumerate(data['nodes']) for child in n.get('children', [])}
    relevant = set()
    for name in mapping:
        node = names[name]
        while node is not None and node not in relevant:
            relevant.add(node)
            node = parents.get(node)
    excluded_prop_scale = [c for c in animation['channels']
                           if c['target']['path'] == 'scale' and c['target']['node'] not in relevant]
    animation['channels'] = [c for c in animation['channels'] if c not in excluded_prop_scale]
    blob, report = bake_humanoid(data, bytes(packed), mapping, 100)
    output = research / (args.alias+'.vrma')
    output.write_bytes(blob)
    report.update({'rotation_sampling': 'Original Unity unweighted Hermite quaternion curves, normalized at 60 Hz; verified mirror-X basis',
                   'translation_sampling': 'Existing FBX-derived translation channels, unchanged',
                   'replaced_rotation_tracks': len(replaced), 'source_paths': replaced,
                   'unmapped_source_curves_absent_from_avatar': absent_from_rig,
                   'excluded_nonhumanoid_scale_nodes': [data['nodes'][c['target']['node']]['name'] for c in excluded_prop_scale],
                   'prop_scale_preserved_in': str(intermediate.relative_to(research)),
                   'source_yaml_sha256': hashlib.sha256(yaml_path.read_bytes()).hexdigest(),
                   'source_rig_sha256': hashlib.sha256(rig_path.read_bytes()).hexdigest(),
                   'input_glb_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
                   'output_sha256': hashlib.sha256(blob).hexdigest(),
                   'installed': False, 'license': 'local-user-assets-not-redistributable'})
    output.with_suffix('.bake.json').write_text(json.dumps(report, indent=2)+'\n')
    print(output, report['duration'], len(replaced), report['output_sha256'])


if __name__ == '__main__':
    main()
