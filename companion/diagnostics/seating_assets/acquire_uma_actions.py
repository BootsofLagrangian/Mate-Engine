#!/usr/bin/env python3
"""Export/canonicalize a fixed local UMA interaction subset; never install assets.

The existing exporter refuses nonempty output and records input/output hashes.
The direct-Unity quaternion bake supersedes FBX Euler interpolation. Original
prop-size curves remain in the intermediate GLB outside the humanoid output.
"""
import argparse,json,subprocess,sys
from pathlib import Path
COMPANION=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(COMPANION/'diagnostics/authored_idle'))
import export_uma_subset
CLIPS=[f'sitdown{i:02}{v}_{p}' for i in range(1,8) for v in (['','_01'] if i==6 else ['']) for p in ['s','loop','e']]
CLIPS += [f'table_{h}_{v}_loop' for h in ['l','s'] for v in ['laptop01','study01','study02']]
CLIPS += [f'chair01_{h}_drink01_loop' for h in ['l','s']]
CLIPS += [f'{v}_{p}' for v in ['book01','drink01','phonelook01','diarylook01','table_l_eat01'] for p in ['s','loop','e']]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--export',action='store_true',help='First export into an empty source output directory');p.add_argument('--source-root',type=Path,default=COMPANION/'assets/research/seating-candidates/uma-actions');p.add_argument('--output',type=Path,default=COMPANION/'assets/research/seating-candidates/uma-canonical');a=p.parse_args()
 if a.export:
  export_uma_subset.SELECTED=[f'3d/motion/event/body/type00/anm_eve_type00_{v}' for v in CLIPS]
  saved=sys.argv;sys.argv=[saved[0],'--output',str(a.source_root)]
  try:export_uma_subset.main()
  finally:sys.argv=saved
  manifest_path=a.source_root/'manifest.json';manifest=json.loads(manifest_path.read_text())
  manifest['selection']='24 sitting phases and 23 ordinary object-interaction phases'
  manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
 a.output.mkdir(parents=True,exist_ok=True);files=sorted((a.source_root/'yaml').glob('*.anim'))
 expected={'anm_eve_type00_'+v for v in CLIPS}
 if {f.stem.lower() for f in files}!=expected:raise ValueError('Exported clip set does not match fixed selection')
 for f in files:
  clip=f.stem.removeprefix('anm_eve_type00_');alias='uma_'+clip.lower()
  subprocess.run([sys.executable,str(COMPANION/'diagnostics/walking_assets/bake_unity_walk.py'),'--source-root',str(a.source_root),'--research-root',str(a.output),'--clip',clip,'--alias',alias,'--intermediate',alias+'_fbx'],check=True)
 subprocess.run([sys.executable,str(Path(__file__).with_name('inspect_trajectory.py')),str(a.output),str(a.output.parent/'uma-trajectory.json')],check=True)
if __name__=='__main__':main()
