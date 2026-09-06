#!/usr/bin/env python3
"""Join verified UMA entry/loop/exit phases and optionally install local aliases."""
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
from convert_candidates import base,pack,COMPANION


def read_track(data,binary,index):
    a=data['accessors'][index];v=data['bufferViews'][a['bufferView']]
    width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
    return [struct.unpack_from('<'+'f'*width,binary,v.get('byteOffset',0)+a.get('byteOffset',0)+i*v.get('byteStride',width*4)) for i in range(a['count'])]


def join(paths):
    sources=[base.read_glb(path.read_bytes()) for path in paths]
    out=copy.deepcopy(sources[0][0]);out['accessors']=[];out['bufferViews']=[]
    out['animations']=[{'name':paths[0].stem+'_complete_action','channels':[],'samplers':[]}]
    packed=bytearray();combined={};offset=0;seams=[]
    for data,binary in sources:
        if data['nodes'] != sources[0][0]['nodes']:
            raise ValueError('Action phase rest skeletons differ')
        duration=0
        for c in data['animations'][0]['channels']:
            s=data['animations'][0]['samplers'][c['sampler']]
            times=read_track(data,binary,s['input']);values=read_track(data,binary,s['output'])
            duration=max(duration,times[-1][0]);key=(c['target']['node'],c['target']['path'])
            track=combined.setdefault(key,{'times':[],'values':[]})
            if track['values'] and key[1]=='rotation':
                dot=abs(sum(x*y for x,y in zip(track['values'][-1],values[0])))
                seams.append(math.degrees(2*math.acos(min(1,dot))))
            for t,value in zip(times,values):
                global_time=t[0]+offset
                if track['times'] and global_time <= track['times'][-1]+1e-6:
                    continue
                track['times'].append(global_time);track['values'].append(value)
        offset+=duration
    def accessor(rows,width):
        blob=struct.pack('<'+'f'*(len(rows)*width),*(v for row in rows for v in row))
        out['bufferViews'].append({'buffer':0,'byteOffset':len(packed),'byteLength':len(blob)});packed.extend(blob)
        out['accessors'].append({'bufferView':len(out['bufferViews'])-1,'componentType':5126,'count':len(rows),'type':{1:'SCALAR',3:'VEC3',4:'VEC4'}[width]})
        return len(out['accessors'])-1
    for (node,prop),track in combined.items():
        time=accessor([(t,) for t in track['times']],1);values=accessor(track['values'],4 if prop=='rotation' else 3)
        anim=out['animations'][0];anim['channels'].append({'target':{'node':node,'path':prop},'sampler':len(anim['samplers'])})
        anim['samplers'].append({'input':time,'output':values,'interpolation':'LINEAR'})
    return pack(out,bytes(packed)),{'duration':offset,'max_phase_rotation_seam_deg':max(seams,default=0),'phases':[p.name for p in paths]}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--install',action='store_true');args=p.parse_args()
    folder=COMPANION/'assets/research/uma/candidates';entries=[]
    for character in ['cheval','rice','eishin']:
        alias=f'uma_{character}_idle_action'
        paths=[folder/f'uma_{character}_idle_{part}.vrma' if part!='loop' else folder/f'uma_{character}_idle.vrma' for part in ['enter','loop','exit']]
        blob,report=join(paths);(folder/f'{alias}.vrma').write_bytes(blob)
        (folder/f'{alias}.action.json').write_text(json.dumps(report,indent=2)+'\n');print(alias,report)
    if args.install:
        names=['uma_home_idle','uma_cheval_idle','uma_rice_idle','uma_eishin_idle']+[f'uma_{c}_idle_action' for c in ['cheval','rice','eishin']]
        for name in names:
            source=folder/f'{name}.vrma';target=COMPANION/f'assets/motions/{name}.vrma';shutil.copyfile(source,target)
            report=json.loads(source.with_suffix('.action.json' if name.endswith('_action') else '.bake.json').read_text())
            entries.append({'name':name,'path':f'assets/motions/{name}.vrma','kind':'vrma','duration':round(report['duration'],6),
                            'loop':not name.endswith('_action'),'ambient':name=='uma_home_idle',
                            'contact_mode':'foot',
                            'description':'Authored quiet standing base with contact IK' if name=='uma_home_idle' else 'Authored character posture action or style',
                            'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source':'local UMA extraction',
                            'source_manifest':'assets/research/uma/export-work/natural-subset/manifest.json','license':'local-user-assets-not-redistributable'})
        path=COMPANION/'motion-assets.json';manifest=json.loads(path.read_text())
        manifest['motions']=[e for e in manifest['motions'] if e['name'] not in names]+entries
        path.write_text(json.dumps(manifest,indent=2)+'\n')
