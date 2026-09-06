#!/usr/bin/env python3
"""Export and canonicalize the13 additional local generic gestures, without install."""
import argparse,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'diagnostics/authored_idle'))
import export_uma_subset as exporter
CLIPS=[f'{a}_{p}' for a in ['think01','bow01','breath01'] for p in ['s','loop','e']]+['stretch01','stretch02','byebye01','byebye02']
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,default=ROOT/'assets/research/everyday-candidates');a=parser.parse_args();source=a.output/'export';canonical=a.output/'canonical'
 exporter.SELECTED=[f'3d/motion/event/body/type00/anm_eve_type00_{v}' for v in CLIPS];sys.argv=[sys.argv[0],'--output',str(source)];exporter.main();manifest_path=source/'manifest.json';manifest=json.loads(manifest_path.read_text());manifest['selection']='13 authored think/bow/breath/stretch/wave source phases';manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
 for file in sorted((source/'yaml').glob('*.anim')):
  clip=file.stem.removeprefix('anm_eve_type00_');alias='uma_'+clip.lower()
  subprocess.run([sys.executable,str(ROOT/'diagnostics/walking_assets/bake_unity_walk.py'),'--source-root',str(source),'--research-root',str(canonical),'--clip',clip,'--alias',alias,'--intermediate',alias+'_fbx'],check=True)
if __name__=='__main__':main()
