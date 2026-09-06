#!/usr/bin/env python3
"""Audit selected source channels and separate finger steps from larger joints."""
import json,math,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'diagnostics/authored_idle'))
from assemble_uma_actions import read_track
from convert_candidates import base

def angle(u,v):
 return math.degrees(2*math.acos(min(1,abs(sum(x*y for x,y in zip(u,v)))/math.sqrt(sum(x*x for x in u)*sum(x*x for x in v)))))
def main():
 rows=[]
 for item in json.loads(Path(__file__).with_name('selection.json').read_text())['motions']:
  p=ROOT/item['source_path'];d,b=base.read_glb(p.read_bytes());anim=d['animations'][0];bones={v['node']:n for n,v in d['extensions']['VRMC_vrm_animation']['humanoid']['humanBones'].items()};steps=[];seams=[];finite=True;rotation_count=0
  for c in anim['channels']:
   s=anim['samplers'][c['sampler']];values=read_track(d,b,s['output']);finite &= all(math.isfinite(x) for row in values for x in row)
   if c['target']['path']=='rotation':
    name=bones[c['target']['node']];rotation_count+=1;times=read_track(d,b,s['input']);gap=[angle(u,v) for u,v in zip(values,values[1:])];i=gap.index(max(gap));steps.append({'bone':name,'step_deg':gap[i],'time':times[i][0]});seams.append(angle(values[0],values[-1]))
  body=[v for v in steps if not any(s in v['bone'] for s in ['Thumb','Index','Middle','Ring','Little'])]
  rows.append({'name':item['entry']['name'],'duration':item['entry']['duration'],'mapped_bones':len(bones),'animated_rotation_bones':rotation_count,'finite':finite,'max_step':max(steps,key=lambda v:v['step_deg']),'max_nonfinger_step':max(body,key=lambda v:v['step_deg']),'endpoint_rotation_gap_deg':max(seams),'loop':item['entry']['loop']})
 out=Path(__file__).with_name('source-statistics.json');out.write_text(json.dumps(rows,indent=2)+'\n');print(out)
if __name__=='__main__':main()
