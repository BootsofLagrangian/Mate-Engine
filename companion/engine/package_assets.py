"""Read declarative motion manifests registered by installed character bundles."""
import json
from pathlib import Path, PurePosixPath
from . import config, COMPANION_ROOT


def package_manifests(root=COMPANION_ROOT):
    root = Path(root).resolve()
    directory = config.characters_dir() if root == COMPANION_ROOT.resolve() else root / 'characters'
    seen = set()
    for profile in sorted(directory.glob('*.json')):
        try:
            data = json.loads(profile.read_text(encoding='utf-8'))
            relative = data.get('package_install', {}).get('motions')
            if not isinstance(relative, str) or '\\' in relative or ':' in relative:
                continue
            parts = PurePosixPath(relative).parts
            if parts[:2] != ('assets', 'character-packages') or '..' in parts or not relative.endswith('/motions.json'):
                continue
            path = (root / relative).resolve()
            path.relative_to(root / 'assets' / 'character-packages')
            if path in seen or path.stat().st_size > 2 * 1024 * 1024:
                continue
            manifest = json.loads(path.read_text(encoding='utf-8'))
            if (isinstance(manifest, dict) and manifest.get('version') == 1
                    and isinstance(manifest.get('motions', []), list)
                    and isinstance(manifest.get('procedural', []), list)):
                seen.add(path)
                yield manifest
        except (OSError, ValueError, TypeError, AttributeError):
            continue
