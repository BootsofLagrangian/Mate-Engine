#!/usr/bin/env python3
"""Inspect an exported motion rig before choosing a humanoid map.

Keeps extraction separate from adoption: reports source transforms, hierarchy,
animation channels and duration without changing any runtime asset.
"""
import argparse
import json
from pathlib import Path
import struct

from convert_candidates import base


def inspect(path):
    data, binary = base.read_glb(path.read_bytes())
    parents = {child: i for i,node in enumerate(data['nodes']) for child in node.get('children', [])}
    nodes = [{'index': i, 'parent': parents.get(i), 'name': node.get('name'),
              'translation': node.get('translation', [0,0,0]),
              'rotation': node.get('rotation', [0,0,0,1]),
              'scale': node.get('scale', [1,1,1]), 'matrix': node.get('matrix')}
             for i,node in enumerate(data['nodes'])]
    animations = []
    for animation in data.get('animations', []):
        channels = []
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            accessor = data['accessors'][sampler['input']]
            view = data['bufferViews'][accessor['bufferView']]
            offset = view.get('byteOffset',0)+accessor.get('byteOffset',0)
            times = [struct.unpack_from('<f',binary,offset+i*view.get('byteStride',4))[0] for i in range(accessor['count'])]
            channels.append({'bone': data['nodes'][channel['target']['node']].get('name'),
                             'path': channel['target']['path'], 'samples': len(times),
                             'start': min(times), 'end': max(times),
                             'interpolation': sampler.get('interpolation','LINEAR')})
        animations.append({'name': animation.get('name'), 'channels': channels})
    return {'source': str(path), 'nodes': nodes, 'animations': animations}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('glb', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = json.dumps(inspect(args.glb),indent=2)+'\n'
    if args.output:
        args.output.write_text(report)
    else:
        print(report,end='')
