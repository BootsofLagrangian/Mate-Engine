#!/usr/bin/env python3
"""Bake locally downloaded creator UAL1/2 humanoid interaction clips (CC0)."""
import argparse,copy,hashlib,json,sys,zipfile
from pathlib import Path
COMPANION=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(COMPANION/'diagnostics/authored_idle'))
from bake_humanoid import bake
from convert_candidates import base
CLIPS={1:{'Sitting_Enter':'sit_down','Sitting_Exit':'stand_up','Sitting_Idle_Loop':'seated_idle'},2:{'Chest_Open':'chest_open','Consume':'consume','Idle_FoldArms_Loop':'fold_arms','Idle_Rail_Call':'rail_call','Idle_Rail_Loop':'rail_lean','Idle_TalkingPhone_Loop':'phone','LayToIdle':'rise_from_lying','Yes':'yes','Idle_No_Loop':'no'}}
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('archive',type=Path);p.add_argument('--version',type=int,choices=[1,2],required=True);p.add_argument('--output',type=Path,default=COMPANION/'assets/research/seating-candidates/public-actions');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(a.archive) as z:
  member=next(n for n in z.namelist() if n.endswith(f'/UAL{a.version}_Standard.glb'));raw=z.read(member);d,b=base.read_glb(raw)
  licenses=[n for n in z.namelist() if 'license' in n.lower() and not n.endswith('/')]
  for n in licenses:(a.output/f'UAL{a.version}-{Path(n).name}').write_bytes(z.read(n))
 mapping={n:h for n,h in base.bone_names().items() if n in {v.get('name') for v in d['nodes']}}
 rows=[]
 for clip,alias in CLIPS[a.version].items():
  animation=next(v for v in d['animations'] if v['name']==clip);data=copy.deepcopy(d);data['animations']=[animation];blob,r=bake(data,b,mapping,1);out=a.output/f'quaternius_{alias}.vrma';out.write_bytes(blob)
  r.update({'source_clip':clip,'source_glb_member':member,'source_glb_sha256':hashlib.sha256(raw).hexdigest(),'archive_sha256':hashlib.sha256(a.archive.read_bytes()).hexdigest(),'sha256':hashlib.sha256(blob).hexdigest(),'source':f'https://quaternius.com/packs/universalanimationlibrary{a.version if a.version>1 else ""}.html','license':'CC0-1.0','installed':False});out.with_suffix('.json').write_text(json.dumps(r,indent=2)+'\n');rows.append(r);print(out.name,r['duration'])
 (a.output/f'UAL{a.version}-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
if __name__=='__main__':main()
