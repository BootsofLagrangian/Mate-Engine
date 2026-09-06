#!/usr/bin/env python3
"""Collapse animated helper bones into mapped humanoid joints at 60 Hz.

Input is Godot's baked LINEAR GLB export, not sparse Unity Hermite curves.
Explicit --metres-per-unit corrects exported units. Outputs a research VRMA.
"""
import argparse
import bisect
import json
import math
from pathlib import Path
import struct
from convert_candidates import base, pack


def mul(a,b):
    x,y,z,w=a; X,Y,Z,W=b
    return (w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z)
def inv(q):
    return (-q[0],-q[1],-q[2],q[3])
def rotate(q,v):
    return mul(mul(q,(*v,0)),inv(q))[:3]
def normalize(q):
    norm=math.sqrt(sum(x*x for x in q))
    return tuple(x/norm for x in q)
def slerp(a,b,u):
    dot=sum(x*y for x,y in zip(a,b))
    if dot<0:
        b=tuple(-x for x in b);dot=-dot
    if dot>.9995:
        return normalize(tuple(x+(y-x)*u for x,y in zip(a,b)))
    angle=math.acos(max(-1,min(1,dot)))
    return tuple((x*math.sin((1-u)*angle)+y*math.sin(u*angle))/math.sin(angle) for x,y in zip(a,b))


def bake(data,binary,mapping,metres_per_unit=1):
    nodes=data['nodes'];parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
    indices={n.get('name'):i for i,n in enumerate(nodes)}
    mapped=[indices[name] for name in mapping]
    if any('matrix' in n or any(abs(float(s)-1)>1e-5 for s in n.get('scale',[1,1,1])) for n in nodes):
        raise ValueError('Non-unit rest scale/matrix requires explicit decomposition')
    animation=data['animations'][0];tracks={};duration=0
    def read(index):
        a=data['accessors'][index];view=data['bufferViews'][a['bufferView']]
        width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        offset=view.get('byteOffset',0)+a.get('byteOffset',0)
        return [struct.unpack_from('<'+'f'*width,binary,offset+i*view.get('byteStride',width*4)) for i in range(a['count'])]
    for c in animation['channels']:
        sampler=animation['samplers'][c['sampler']]
        if sampler.get('interpolation','LINEAR') not in ('LINEAR','STEP'):
            raise ValueError('Input must be baked LINEAR or STEP')
        times=[t[0] for t in read(sampler['input'])];values=read(sampler['output'])
        if c['target']['path']=='scale':
            if any(abs(v-1)>1e-4 for row in values for v in row):
                raise ValueError('Animated scale must not be silently discarded')
            continue
        tracks[(c['target']['node'],c['target']['path'])]=(times,values,sampler.get('interpolation','LINEAR'))
        duration=max(duration,times[-1])
    def sample(track,t,rotation):
        times,values,mode=track;i=bisect.bisect_right(times,t)
        if i==0:return values[0]
        if i==len(times):return values[-1]
        u=0 if mode=='STEP' else (t-times[i-1])/(times[i]-times[i-1])
        return slerp(values[i-1],values[i],u) if rotation else tuple(a+(b-a)*u for a,b in zip(values[i-1],values[i]))
    def world(t=None):
        result={}
        def visit(i):
            if i in result:return result[i]
            node=nodes[i];q=tuple(node.get('rotation',[0,0,0,1]));v=tuple(node.get('translation',[0,0,0]))
            if t is not None:
                if (i,'rotation') in tracks:q=sample(tracks[i,'rotation'],t,True)
                if (i,'translation') in tracks:v=sample(tracks[i,'translation'],t,False)
            if i in parents:
                pq,pv=visit(parents[i]);q=mul(pq,q);v=tuple(a+b for a,b in zip(pv,rotate(pq,v)))
            result[i]=(normalize(q),v);return result[i]
        for i in mapped:visit(i)
        return result
    collapsed_parents={}
    for i in mapped:
        ancestor=parents.get(i)
        while ancestor is not None and ancestor not in mapped:ancestor=parents.get(ancestor)
        collapsed_parents[i]=ancestor
    def local(world_pose,i):
        q,v=world_pose[i];parent=collapsed_parents[i]
        if parent is not None:
            pq,pv=world_pose[parent];q=mul(inv(pq),q);v=rotate(inv(pq),tuple(a-b for a,b in zip(v,pv)))
        return normalize(q),tuple(x*metres_per_unit for x in v)
    rest=world();out_nodes=[];lookup={old:new for new,old in enumerate(mapped)}
    for i in mapped:
        q,v=local(rest,i);out_nodes.append({'name':nodes[i]['name'],'rotation':q,'translation':v})
    for child,parent in collapsed_parents.items():
        if parent is not None:out_nodes[lookup[parent]].setdefault('children',[]).append(lookup[child])
    out={'asset':{'version':'2.0','generator':'Mate helper-bone world-pose bake'},'nodes':out_nodes,
         'scenes':[{'nodes':[lookup[i] for i in mapped if collapsed_parents[i] is None]}],'scene':0,
         'extensionsUsed':['VRMC_vrm_animation'],'extensionsRequired':['VRMC_vrm_animation'],
         'extensions':{'VRMC_vrm_animation':{'specVersion':'1.0','humanoid':{'humanBones':{mapping[nodes[i]['name']]:{'node':lookup[i]} for i in mapped}}}},
         'accessors':[],'bufferViews':[],'animations':[{'name':animation.get('name','motion'),'channels':[],'samplers':[]}]}
    packed=bytearray()
    def accessor(rows,width):
        blob=struct.pack('<'+'f'*(len(rows)*width),*(x for row in rows for x in row))
        out['bufferViews'].append({'buffer':0,'byteOffset':len(packed),'byteLength':len(blob)});packed.extend(blob)
        out['accessors'].append({'bufferView':len(out['bufferViews'])-1,'componentType':5126,'count':len(rows),'type':{1:'SCALAR',3:'VEC3',4:'VEC4'}[width]})
        return len(out['accessors'])-1
    times=[min(f/60,duration) for f in range(math.ceil(duration*60)+1)]
    poses=[world(t) for t in times];time_id=accessor([(t,) for t in times],1)
    for i in mapped:
        samples=[local(pose,i) for pose in poses]
        for prop,col,width in [('rotation',0,4),('translation',1,3)]:
            values=accessor([value[col] for value in samples],width);anim=out['animations'][0]
            anim['channels'].append({'target':{'node':lookup[i],'path':prop},'sampler':len(anim['samplers'])})
            anim['samplers'].append({'input':time_id,'output':values,'interpolation':'LINEAR'})
    return pack(out,bytes(packed)),{'duration':duration,'samples':len(times),'mapped_bones':len(mapped),'source_tracks':len(tracks),'metres_per_unit':metres_per_unit}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('glb',type=Path);p.add_argument('mapping',type=Path);p.add_argument('output',type=Path);p.add_argument('--metres-per-unit',type=float,default=1)
    args=p.parse_args();data,binary=base.read_glb(args.glb.read_bytes())
    blob,report=bake(data,binary,json.loads(args.mapping.read_text()),args.metres_per_unit)
    args.output.write_bytes(blob);args.output.with_suffix('.bake.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
