#!/usr/bin/env python3
"""Rebuild the curated everyday selections from explicitly acquired local sources."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'diagnostics/authored_idle'))
from assemble_uma_actions import join
from convert_candidates import base,pack
SOURCES=[('authored_think','think01','Think with hand near chin'),('authored_bow','bow01','Small polite standing bow'),('authored_breathe','breath01','One deliberate breath and relax'),('authored_read','book01','Reading pantomime; no book is attached'),('authored_drink','drink01','Drink pantomime; no cup is attached'),('authored_phone','phonelook01','Check-phone pantomime; no phone is attached')]
def main():
 target=ROOT/'assets/research/everyday-candidates/assembled';target.mkdir(parents=True,exist_ok=True)
 selection=Path(__file__).with_name('selection.json');old=json.loads(selection.read_text());motions=[m for m in old['motions'] if m['entry']['name'] in ['sit_enter','sit_idle','sit_exit']]
 def add(alias,source,description,report,loop=False,contact='foot'):
  blob=source.read_bytes();entry={'name':alias,'path':f'assets/motions/{alias}.vrma','kind':'vrma','duration':report['duration'],'loop':loop,'ambient':False,'contact_mode':contact,'description':description,'sha256':hashlib.sha256(blob).hexdigest(),'source':'local UMA extraction','source_manifest':report['source_manifest'],'conversion_manifest':str(source.with_suffix('.curation.json').relative_to(ROOT)),'license':'local-user-assets-not-redistributable'}
  source.with_suffix('.curation.json').write_text(json.dumps(report,indent=2)+'\n');motions.append({'source_path':str(source.relative_to(ROOT)),'entry':entry})
 for alias,family,description in SOURCES:
  group='everyday-candidates' if family in ['think01','bow01','breath01'] else 'seating-candidates';folder=ROOT/'assets/research'/group/('canonical' if group=='everyday-candidates' else 'uma-canonical');paths=[folder/f'uma_{family}_{phase}.vrma' for phase in ['s','loop','e']]
  if family=='phonelook01': paths=paths[1:2]
  blob,report=join(paths);source=target/(alias+'.vrma');source.write_bytes(blob);report.update({'source_sha256':[hashlib.sha256(p.read_bytes()).hexdigest() for p in paths],'source_manifest':f'assets/research/{group}/'+('export' if group=='everyday-candidates' else 'uma-actions')+'/manifest.json','transformation':'One authored phone-check hold, native entry/exit blend; full source exit withheld for 25-degree wrist release step' if family=='phonelook01' else 'Concatenate original authored entry, one loop and exit; no pose synthesis'})
  add(alias,source,description,report)
 for alias,family,description in [('authored_wave','byebye01','One friendly hand wave'),('authored_stretch','stretch01','Shoulder and arm stretch'),('authored_overhead_stretch','stretch02','Open arms overhead and relax')]:
  source=ROOT/f'assets/research/everyday-candidates/canonical/uma_{family}.vrma';r=json.loads(source.with_suffix('.bake.json').read_text());r['source_manifest']='assets/research/everyday-candidates/export/manifest.json';r['source_clip']=family;add(alias,source,description,r)
 source=ROOT/'assets/research/seating-candidates/uma-canonical/uma_table_l_laptop01_loop.vrma';d,b=base.read_glb(source.read_bytes());bones=d['extensions']['VRMC_vrm_animation']['humanoid']['humanBones'];keep={v['node'] for name,v in bones.items() if name!='hips' and not any(s in name for s in ['Leg','Foot','Toes'])};anim=d['animations'][0];anim['channels']=[c for c in anim['channels'] if c['target']['node'] in keep and c['target']['path']=='rotation'];out=target/'authored_type.vrma';out.write_bytes(pack(d,b));r=json.loads(source.with_suffix('.bake.json').read_text());r.update({'source_manifest':'assets/research/seating-candidates/uma-actions/manifest.json','source_clip':'table_L_laptop01_loop','transformation':'Retain authored upper-body rotation channels only; remove hips/legs and translation. No keyboard/laptop object attached.','animated_bones':len(keep),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest()});add('authored_type',out,'Typing pantomime, upper body only; no laptop is attached',r,True,'')
 selection.write_text(json.dumps({'version':1,'motions':motions},indent=2)+'\n');print('Prepared',len(motions),'curated entries including3seated phases')
if __name__=='__main__':main()
