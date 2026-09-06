#!/usr/bin/env python3
"""Sample decompressed AssetStudio Unity curves, retaining original Unity axes.

No guessed hash mapping. Output paths remain exact until a verified rig map is
provided. Supports unweighted Hermite/constant curves; refuses weighted curves.
"""
import argparse
import bisect
import json
import math
from pathlib import Path
import yaml


def read_clip(path):
    text = '\n'.join(line for line in path.read_text().splitlines() if not line.startswith(('%','---')))
    return yaml.safe_load(text)['AnimationClip']


def number(value):
    if str(value) in ('∞','Infinity','inf'):
        return math.inf
    if str(value) in ('-∞','-Infinity','-inf'):
        return -math.inf
    return float(value)


def sample(keys,time,components):
    if any(k.get('weightedMode',0) != 0 for k in keys):
        raise ValueError('Weighted curves need weighted Bezier evaluation')
    index = bisect.bisect_right([k['time'] for k in keys],time)
    if index == 0 or index == len(keys):
        key = keys[0] if index == 0 else keys[-1]
        return [float(key['value'][c]) for c in components]
    left,right = keys[index-1:index+1]
    duration = right['time']-left['time']
    u = (time-left['time'])/duration
    values = []
    for c in components:
        a,b = float(left['value'][c]),float(right['value'][c])
        out_slope,in_slope = number(left['outSlope'][c]),number(right['inSlope'][c])
        if not math.isfinite(out_slope) or not math.isfinite(in_slope):
            values.append(a)
        else:
            values.append((2*u**3-3*u*u+1)*a+(u**3-2*u*u+u)*duration*out_slope
                          +(-2*u**3+3*u*u)*b+(u**3-u*u)*duration*in_slope)
    return values


def bake(clip,rate=60):
    duration = float(clip['m_AnimationClipSettings']['m_StopTime'])
    frames = math.ceil(duration*rate)
    times = [min(i/rate,duration) for i in range(frames+1)]
    tracks = []
    for field,path,components in [('m_RotationCurves','rotation','xyzw'),('m_PositionCurves','translation','xyz'),('m_ScaleCurves','scale','xyz')]:
        for curve in clip[field]:
            keys = curve['curve']['m_Curve']
            values = [sample(keys,t,components) for t in times]
            if path == 'rotation':
                for value in values:
                    norm = math.sqrt(sum(v*v for v in value))
                    if norm < 1e-8:
                        raise ValueError('Degenerate quaternion')
                    value[:] = [v/norm for v in value]
            tracks.append({'source_path':curve['path'],'property':path,'values':values})
    return {'name':clip['m_Name'],'duration':duration,'sample_rate':rate,'coordinate_system':'Unity original, conversion required','times':times,'tracks':tracks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('anim',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    result = bake(read_clip(args.anim))
    args.output.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print(result['name'],result['duration'],len(result['tracks']),len(result['times']))
