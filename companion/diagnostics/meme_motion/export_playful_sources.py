#!/usr/bin/env python3
"""Reuse the verified local UMA exporter for a bounded playful-walk inventory.

Only selected source bundles are read. The destination must be new/empty; the
source tree and installed motion catalog are not changed.
"""
import importlib.util
import json
from pathlib import Path
import sys

COMPANION = Path(__file__).resolve().parents[2]
SELECTED = (
    [f'homewalk{i:02}_loop' for i in range(2, 6)]
    + [f'walk{i:02}_loop' for i in range(2, 9)]
    + [f'walkunique{i:02}_loop' for i in (1, 2, 4, 5, 6, 7, 8, 9, 10, 11)]
    + ['skip01_loop', 'walkclap01_loop', 'walkclap02_loop', 'takewalk01_loop', 'takewalk02_loop']
)


def main():
    source = COMPANION / 'diagnostics/authored_idle/export_uma_subset.py'
    spec = importlib.util.spec_from_file_location('uma_subset', source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.SELECTED = [f'3d/motion/event/body/type00/anm_eve_type00_{name}' for name in SELECTED]
    output = COMPANION / 'assets/research/playful-walk/uma-source'
    if len(sys.argv) == 1:
        sys.argv += ['--output', str(output)]
    else:
        if '--output' not in sys.argv:
            raise ValueError('Specify --output for an alternate empty acquisition directory')
        output = Path(sys.argv[sys.argv.index('--output') + 1]).resolve()
    module.main()
    manifest_path = output / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['selection'] = '26 generic authored walk variants selected prospectively by filenames for playful broad-stride screening'
    manifest['selection_script'] = str(Path(__file__).relative_to(COMPANION))
    manifest['selected_clip_suffixes'] = SELECTED
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
