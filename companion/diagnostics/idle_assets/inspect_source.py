import sys,zipfile,json,hashlib
import numpy as np
sys.path.insert(0,'Mate-Engine/companion');import setup_motions as s
with zipfile.ZipFile('/tmp/mate-ual-standard.zip') as z:
 blob=z.read(next(n for n in z.namelist() if n.endswith('/Unreal-Godot/UAL1_Standard.glb')))
j,b=s.read_glb(blob)
def arr(i):
 a=j['accessors'][i];v=j['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',w*4)
 return np.array([np.frombuffer(b,dtype='<f4',count=w,offset=start+k*stride) for k in range(a['count'])])
def angle(a,b):return np.degrees(2*np.arccos(np.clip(np.abs(np.sum(a*b,axis=-1)),0,1)))
rows=[]
for anim in j['animations']:
 if anim['name'] not in ['Idle_Loop','Idle_Talking_Loop','Walk_Loop','Walk_Formal_Loop','Sitting_Idle_Loop','Sitting_Talking_Loop','Sitting_Enter','Sitting_Exit']:continue
 row={'clip':anim['name'],'bones':{}}
 for c in anim['channels']:
  n=j['nodes'][c['target']['node']].get('name'); sam=anim['samplers'][c['sampler']];t=arr(sam['input']).ravel(); q=arr(sam['output']);row['duration']=float(t[-1])
  if c['target']['path']!='rotation' or n not in ['pelvis','spine_01','spine_03','neck_01','Head','upperarm_l','upperarm_r']:continue
  q=q/np.linalg.norm(q,axis=1,keepdims=True); pair=angle(q[:,None,:],q[None,:,:]); speed=angle(q[1:],q[:-1])/np.diff(t)
  row['bones'][n]={'range_deg':round(float(pair.max()),2),'seam_deg':round(float(angle(q[0],q[-1])),3),'max_speed_deg_s':round(float(speed.max()),2)}
 rows.append(row)
print(json.dumps({'source_sha256':hashlib.sha256(blob).hexdigest(),'metrics_scope':'local rotation quaternion pairwise maximum excursion; not world head trajectory or perceptual naturalness','clips':rows},indent=2))
