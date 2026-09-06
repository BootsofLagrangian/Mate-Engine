#!/usr/bin/env python3
"""Decode canonical VRMA source FK for seating selection, without runtime IK."""
import argparse,bisect,hashlib,json,math,struct,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'authored_idle'))
from bake_humanoid import mul,rotate,slerp
from convert_candidates import base

def inspect(path):
 data,binary=base.read_glb(path.read_bytes());nodes=data['nodes'];parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
 bones={k:v['node'] for k,v in data['extensions']['VRMC_vrm_animation']['humanoid']['humanBones'].items()}
 def read(index):
  a=data['accessors'][index];v=data['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];offset=v.get('byteOffset',0)+a.get('byteOffset',0)
  return [struct.unpack_from('<'+'f'*w,binary,offset+i*v.get('byteStride',w*4)) for i in range(a['count'])]
 tracks={};duration=0
 for channel in data['animations'][0]['channels']:
  s=data['animations'][0]['samplers'][channel['sampler']];times=[v[0] for v in read(s['input'])];values=read(s['output']);tracks[channel['target']['node'],channel['target']['path']]=(times,values);duration=max(duration,times[-1])
 def world(t):
  result={}
  def visit(i):
   if i in result:return result[i]
   n=nodes[i];pose={'rotation':n.get('rotation',[0,0,0,1]),'translation':n.get('translation',[0,0,0])}
   for prop in pose:
    if (i,prop) not in tracks:continue
    times,values=tracks[i,prop];j=bisect.bisect_right(times,t)
    if j==0:v=values[0]
    elif j==len(times):v=values[-1]
    else:
     u=(t-times[j-1])/(times[j]-times[j-1]);v=slerp(values[j-1],values[j],u) if prop=='rotation' else tuple(a+(b-a)*u for a,b in zip(values[j-1],values[j]))
    pose[prop]=v
   q,p=pose['rotation'],pose['translation']
   if i in parents:
    pq,pp=visit(parents[i]);p=tuple(a+b for a,b in zip(pp,rotate(pq,p)));q=mul(pq,q)
   result[i]=(q,p);return result[i]
  return {name:visit(i)[1] for name,i in bones.items()}
 def knee(p,side):
  a,b,c=[p[side+x] for x in ['UpperLeg','LowerLeg','Foot']];u=[x-y for x,y in zip(a,b)];v=[x-y for x,y in zip(c,b)];dot=sum(x*y for x,y in zip(u,v))/math.sqrt(sum(x*x for x in u)*sum(x*x for x in v));return 180-math.degrees(math.acos(max(-1,min(1,dot))))
 frames=[]
 for t in [0,duration/2,duration]:
  p=world(t);frames.append({'time':t,**{k:p[k] for k in ['hips','leftFoot','rightFoot']},**{s+'_knee_bend_deg':knee(p,s) for s in ['left','right']}})
 return {'name':path.stem,'duration':duration,'mapped_bones':len(bones),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'frames':frames}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('output',type=Path);a=p.parse_args();rows=[inspect(f) for f in sorted(a.directory.glob('*.vrma'))];a.output.write_text(json.dumps(rows,indent=2)+'\n')
 for r in rows:
  if 'sitdown' in r['name']:print(r['name'],round(r['duration'],2),'hips',[[round(v,3) for v in f['hips']] for f in r['frames']],'knees',[[round(f[s+'_knee_bend_deg']) for s in ['left','right']] for f in r['frames']])
