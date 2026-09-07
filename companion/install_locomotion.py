#!/usr/bin/env python3
"""Install a local VRMA with a measured calibration profile; no asset downloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from engine.motion_assets import MotionAssets, valid_locomotion_style


def install(root, source, profile, name, make_default=False):
    root, source = Path(root).resolve(), Path(source).resolve()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,63}', name):
        raise ValueError('Use a lowercase motion name')
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    style = profile['locomotion_style']
    duration = profile['duration_s']
    if digest != profile['source_sha256'] or not style or not valid_locomotion_style(style):
        raise ValueError('Source checksum or measured gait profile mismatch')
    if not isinstance(duration, (int, float)) or not 0.1 <= duration <= 30:
        raise ValueError('Invalid source duration')
    catalogue = MotionAssets(root)
    if not catalogue._validated(source, digest):
        raise ValueError('Source is not a valid VRM animation')
    manifest_path = root / 'motion-assets.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {'version': 1, 'motions': []}
    if manifest.get('version') != 1 or not isinstance(manifest.get('motions'), list):
        raise ValueError('Unsupported installed manifest')
    others = [entry for entry in manifest['motions'] if entry['name'] != name]
    installed = [entry for entry, _ in catalogue.entries() if entry['name'] != name]
    priority = max([entry.get('locomotion_priority', 0) for entry in installed if entry.get('locomotion')] + [0]) + 1 if make_default else 0
    if priority > 100: raise ValueError('Existing priorities leave no default priority available')
    relative = f'assets/motions/{name}.vrma'
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    # Checksum-addressed validation plus atomic manifest publication; no source mutation.
    if source != target: shutil.copyfile(source, target)
    entry = {'name': name, 'path': relative, 'kind': 'vrma', 'duration': duration,
             'sha256': digest, 'loop': True, 'ambient': False, 'locomotion': True,
             'locomotion_priority': priority, 'locomotion_preserve_hips': True,
             'locomotion_style': style, 'source_clip': profile.get('name', ''),
             'source': 'local calibrated authored source', 'license': profile.get('license', 'local-user-assets-not-redistributable'),
             'description': 'Authored walking with calibrated stride and stance contacts'}
    manifest['motions'] = others + [entry]
    fd, temp = tempfile.mkstemp(prefix='.motion-assets-', suffix='.json', dir=root)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(manifest, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temp, manifest_path)
    finally:
        Path(temp).unlink(missing_ok=True)
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--make-default', action='store_true')
    args = parser.parse_args()
    print(json.dumps(install(args.root, args.source, json.loads(args.profile.read_text()), args.name, args.make_default), indent=2))


if __name__ == '__main__':
    main()
