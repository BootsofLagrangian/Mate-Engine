#!/usr/bin/env python3
"""Reproduce local UMA runtime aliases from the verified 32-FBX extraction."""
import argparse
from pathlib import Path
import subprocess
import sys
from convert_candidates import COMPANION,base
from bake_humanoid import bake
import json


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=COMPANION/'assets/research/uma/export-work/natural-subset/fbx')
    parser.add_argument('--godot',type=Path,default=COMPANION/'tools/Godot_v4.5.2-stable_linux.x86_64')
    parser.add_argument('--install',action='store_true')
    args=parser.parse_args()
    output=COMPANION/'assets/research/uma/candidates';intermediate=output/'intermediate';intermediate.mkdir(parents=True,exist_ok=True)
    mapping=json.loads((Path(__file__).parent/'uma-bone-map.json').read_text())
    selected={'uma_home_idle':'anm_eve_type00_homestand01_loop'}
    for character,code in [('cheval','1089'),('rice','1030'),('eishin','1037')]:
        for part,source_suffix in [('', 'loop'),('_enter','S'),('_exit','E')]:
            selected[f'uma_{character}_idle{part}']=f'anm_eve_chr{code}_00_idle01_{source_suffix}'
    for alias,source in selected.items():
        glb=intermediate/(alias+'.glb')
        subprocess.run([str(args.godot),'--headless','--path',str(COMPANION/'native'),'-s','tools/convert_overte_fbx.gd','--',str(args.source/(source+'.fbx')),str(glb)],check=True)
        data,binary=base.read_glb(glb.read_bytes());blob,report=bake(data,binary,mapping,100)
        target=output/(alias+'.vrma');target.write_bytes(blob)
        report['source_fbx']=source+'.fbx'
        target.with_suffix('.bake.json').write_text(json.dumps(report,indent=2)+'\n')
    command=[sys.executable,str(Path(__file__).parent/'assemble_uma_actions.py')]
    if args.install:command.append('--install')
    subprocess.run(command,check=True)


if __name__=='__main__':
    main()
