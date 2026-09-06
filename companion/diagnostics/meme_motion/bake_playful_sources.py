#!/usr/bin/env python3
"""Bake the acquired 26-clip UMA screening set without installing candidates."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys

COMPANION = Path(__file__).resolve().parents[2]


def main():
    research = COMPANION / 'assets/research/playful-walk'
    source = research / 'uma-source'
    output = research / 'candidates'
    output.mkdir(exist_ok=True)
    paths = sorted((source / 'yaml').glob('*.anim'))
    def bake(path):
        suffix = path.stem.removeprefix('anm_eve_type00_')
        alias = 'uma_' + suffix
        command = [sys.executable, str(COMPANION / 'diagnostics/walking_assets/bake_unity_walk.py'),
                   '--source-root', str(source), '--research-root', str(output),
                   '--clip', suffix, '--intermediate', alias + '_fbx', '--alias', alias]
        result = subprocess.run(command, capture_output=True, cwd=COMPANION)
        (output / (alias + '.log')).write_bytes(result.stdout + result.stderr)
        file = output / (alias + '.vrma')
        return {'clip': suffix, 'alias': alias, 'exit_code': result.returncode,
                'vrma_sha256': hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else None}
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(bake, paths))
    (research / 'screening-bakes.json').write_text(json.dumps(results, indent=2) + '\n')
    failed = [entry for entry in results if entry['exit_code']]
    print(f'Baked {len(results)-len(failed)}/{len(results)} candidates; failures={failed}')
    return bool(failed)


if __name__ == '__main__':
    raise SystemExit(main())
