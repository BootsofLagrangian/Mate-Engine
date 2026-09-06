#!/usr/bin/env python3
"""Export a fixed, local-only UMA motion subset through installed AssetStudio.

Run from WSL. Does not modify source bundles/config, install motions, or contact
services. Reads 32 selected motion bundles plus one rig, copies them into its
output tree, compiles the reflection bridge, and exports skeleton+clip FBXs and
Unity YAML curves. Source hashes and all conversion settings are recorded.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

COMPANION = Path(__file__).resolve().parents[2]
RIG = '3d/chara/body/bdy1089_00/pfb_bdy1089_00'
GENERIC = [
    'homestand01_s', 'homestand01_loop', 'homestand01_e', 'homestand01_pose',
    'homestand01_turn50_l', 'homestand01_turn50_r',
    'homestand01_turn135_l', 'homestand01_turn135_r',
    'homewalk01_loop', 'homewalk01_u_loop', 'homewalk01_d_loop',
    'walkin01', 'walkout01', 'chair01_l_look01_s',
    'chair01_l_look01_loop', 'chair01_l_look01_e', 'chair01_l_look01_pose',
]
SELECTED = [f'3d/motion/event/body/type00/anm_eve_type00_{name}' for name in GENERIC]
SELECTED += [f'3d/motion/event/body/chara/chr{cid}_00/anm_eve_chr{cid}_00_idle01_{part}'
             for cid in ('1089', '1030', '1037') for part in ('s', 'loop', 'e', 'sl', 'pose')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def win(path):
    return subprocess.check_output(['wslpath', '-w', str(path.resolve())], text=True).strip()


def run(command, log, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=240)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'Export command exited {result.returncode}; inspect {log}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asset-root', type=Path, default=Path('/mnt/f/ULTIMA/UMA-Extractor/UmaMusumeToolbox/uma_asset'))
    parser.add_argument('--studio-dir', type=Path, default=Path('/mnt/f/ULTIMA/UMA-Extractor/AssetStudio'))
    parser.add_argument('--dotnet', type=Path, default=COMPANION / 'tools/dotnet-win8/dotnet.exe')
    parser.add_argument('--output', type=Path, default=COMPANION / 'assets/research/uma/export-work/natural-subset')
    args = parser.parse_args()
    root, out = args.asset_root.resolve(), args.output.resolve()
    if out == root or root in out.parents:
        raise ValueError('Output must be outside the source asset tree')
    if out.exists() and any(out.iterdir()):
        raise ValueError('Choose an empty output directory; prior attempts are never overwritten')
    for relative in [RIG] + SELECTED:
        if not (root / relative).is_file():
            raise FileNotFoundError(root / relative)
    for name in ('input', 'helper', 'fbx', 'yaml'):
        (out / name).mkdir(parents=True, exist_ok=True)
    manifest = {'version': 1, 'source_root': str(root), 'source_files': [], 'outputs': [],
                'selection': '17 generic transitions/idle/walk/chair clips + 5 idle phases for each of 1089/1030/1037',
                'local_use_only': True, 'rig': RIG, 'clip_count': len(SELECTED),
                'settings': {'collectAnimations': False, 'exportAllNodes': True, 'exportSkins': False,
                             'exportMaterials': False, 'eulerFilter': False, 'scaleFactor': 1,
                             'fbxVersion': 3, 'fbxFormat': 0,
                             'rig_json_basis': 'original Unity local TRS',
                             'fbx_basis': 'AssetStudio mirrors translation X and quaternion Y/Z'}}
    manifest_path = out / 'manifest.json'
    try:
        for relative in [RIG] + SELECTED:
            source = root / relative
            destination = out / 'input' / source.name
            if destination.exists():
                raise ValueError('Duplicate source basename in fixed subset')
            digest = sha(source)
            shutil.copy2(source, destination)
            assert sha(destination) == digest
            manifest['source_files'].append({'path': relative, 'sha256': digest, 'bytes': source.stat().st_size})
        helper = out / 'helper'
        source_cs = Path(__file__).with_name('AssetStudioSubset.cs')
        shutil.copy2(source_cs, helper / source_cs.name)
        native = args.studio_dir / 'x64/AssetStudio.FBXNative.dll'
        native_target = args.dotnet.parent / 'x64/AssetStudio.FBXNative.dll'
        native_target.parent.mkdir(exist_ok=True)
        if not native_target.exists():
            shutil.copy2(native, native_target)
        if sha(native_target) != sha(native):
            raise ValueError('Existing dotnet FBX native dependency differs; refusing replacement')
        manifest['tools'] = {str(p): sha(p) for p in [args.dotnet, native, source_cs, args.studio_dir / 'AssetStudio.dll', args.studio_dir / 'AssetStudio.Utility.dll', args.studio_dir / 'AssetStudio.CLI.dll']}
        executable = helper / 'Export.exe'
        run(['/mnt/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe', '/nologo',
             '/out:' + win(executable), win(helper / source_cs.name)], helper / 'compile.log', helper)
        executable.with_suffix('.runtimeconfig.json').write_text(json.dumps({'runtimeOptions': {
            'tfm': 'net8.0', 'framework': {'name': 'Microsoft.NETCore.App', 'version': '8.0.30'}}}))
        run([str(args.dotnet), win(executable), win(out / 'input'), win(out / 'fbx'), win(args.studio_dir)],
            out / 'fbx-export.log', helper)
        # CLI handles bundles separately, sufficient for native Unity curve YAML.
        # --types has a custom parser; name filtering avoids its ambiguous syntax.
        run([str(args.dotnet), win(args.studio_dir / 'AssetStudio.CLI.dll'), win(out / 'input'),
             win(out / 'yaml'), '--game', 'Normal', '--names', '^anm_', '--group_assets', 'None', '--export_type', 'Convert'],
            out / 'yaml-export.log', helper)
        fbx_files, yaml_files = sorted((out / 'fbx').glob('*.fbx')), sorted((out / 'yaml').glob('*.anim'))
        if len(fbx_files) != len(SELECTED) or len(yaml_files) != len(SELECTED):
            raise ValueError(f'Expected {len(SELECTED)} FBX and YAML clips, got {len(fbx_files)}, {len(yaml_files)}')
        for file in fbx_files + yaml_files + [out / 'fbx/rig.json']:
            source_names = {Path(item['path']).name.casefold(): item['path'] for item in manifest['source_files']}
            source_path = RIG if file.name == 'rig.json' else source_names[file.stem.casefold()]
            manifest['outputs'].append({'path': str(file.relative_to(out)), 'sha256': sha(file),
                                        'bytes': file.stat().st_size, 'source_path': source_path})
        for item in manifest['source_files']:
            if sha(root / item['path']) != item['sha256']:
                raise ValueError('Source changed during extraction: ' + item['path'])
        manifest['complete'] = True
    finally:
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Exported {len(SELECTED)} FBX + YAML clips and rest rig; {manifest_path}')


if __name__ == '__main__':
    main()
