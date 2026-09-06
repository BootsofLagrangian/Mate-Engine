"""Installed VRMA assets listed by the companion-owned motion-assets.json manifest.

Only manifest-listed, contained, checksum-matching binary VRM animations are
published. File stat identities cache validation; replacement invalidates it.
"""
import hashlib
import json
import math
import re
import struct
import threading
from pathlib import Path, PurePosixPath
from . import COMPANION_ROOT
from .motions import MOTION_ID

SHA256 = re.compile(r'^[0-9a-fA-F]{64}$')


class MotionAssets:
    def __init__(self, root=COMPANION_ROOT):
        self.root = Path(root).resolve()
        self.manifest = self.root / 'motion-assets.json'
        self._cache = {}
        self._lock = threading.Lock()

    def _path(self, relative):
        if not isinstance(relative, str) or '\\' in relative or ':' in relative:
            return None
        parts = PurePosixPath(relative).parts
        if len(parts) < 3 or parts[:2] != ('assets', 'motions') or '..' in parts:
            return None
        try:
            path = (self.root / relative).resolve()
        except (OSError, RuntimeError):
            return None
        try:
            path.relative_to(self.root / 'assets' / 'motions')
        except ValueError:
            return None
        return path if path.suffix.lower() == '.vrma' else None

    def _validated(self, path, expected):
        try:
            stat = path.stat()
            if not path.is_file():
                return False
            identity = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
            key = (path, expected)
            with self._lock:
                cached = self._cache.get(key)
                if cached and cached[0] == identity:
                    return cached[1]
            with path.open('rb') as stream:
                header = stream.read(20)
                if len(header) != 20:
                    return False
                magic, version, size, json_size, chunk_type = struct.unpack('<4sIIII', header)
                if magic != b'glTF' or version != 2 or size != stat.st_size or chunk_type != 0x4E4F534A:
                    return False
                if json_size > min(size - 20, 8 * 1024 * 1024):
                    return False
                document = json.loads(stream.read(json_size))
                if not isinstance(document, dict) or not isinstance(document.get('animations'), list) or not document['animations']:
                    return False
                extensions = document.get('extensions', {})
                if not isinstance(extensions, dict) or not isinstance(extensions.get('VRMC_vrm_animation'), dict):
                    return False
                stream.seek(0)
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            valid = digest == expected
            # Avoid caching a validation if an install changed the file mid-read.
            after = path.stat()
            if identity != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                return False
            with self._lock:
                if len(self._cache) >= 256:
                    self._cache.clear()
                self._cache[key] = (identity, valid)
            return valid
        except (OSError, ValueError, struct.error):
            return False

    def entries(self):
        try:
            manifest = json.loads(self.manifest.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            return []
        if not isinstance(manifest, dict) or manifest.get('version') != 1 or not isinstance(manifest.get('motions'), list):
            return []
        entries, seen = [], set()
        for item in manifest['motions']:
            if not isinstance(item, dict):
                continue
            name, duration, sha = item.get('name'), item.get('duration'), item.get('sha256')
            if not isinstance(name, str) or not MOTION_ID.fullmatch(name) or name in seen:
                continue
            if isinstance(duration, bool) or not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
                continue
            if not isinstance(sha, str) or not SHA256.fullmatch(sha):
                continue
            if 'loop' in item and not isinstance(item['loop'], bool):
                continue
            path = self._path(item.get('path'))
            if path is None or not self._validated(path, sha.lower()):
                continue
            entry = {'name': name, 'kind': 'vrma', 'duration': float(duration), 'asset_url': f'/motion-assets/{name}', 'sha256': sha.lower()}
            if 'loop' in item:
                entry['loop'] = item['loop']
            if isinstance(item.get('description'), str):
                entry['description'] = item['description'][:500]
            entries.append((entry, path))
            seen.add(name)
        return entries

    def catalog(self):
        return {'motions': [entry for entry, _ in self.entries()]}

    def resolve(self, name):
        if not isinstance(name, str) or not MOTION_ID.fullmatch(name):
            return None
        return next((pair for pair in self.entries() if pair[0]['name'] == name), None)


    def read(self, name):
        resolved = self.resolve(name)
        if resolved is None:
            return None
        entry, path = resolved
        try:
            data = path.read_bytes()
        except OSError:
            return None
        # An installer may replace the file between validation and HTTP delivery.
        # Return a verified byte snapshot, so the advertised ETag describes this body.
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            return None
        return entry, data


def available_motions(bank, assets):
    """Native VRMA and local procedural gestures share a name namespace; bank wins duplicates."""
    motions = bank.bank()['motions']
    names = {motion['name'] for motion in motions}
    return motions + [entry for entry, _ in assets.entries() if entry['name'] not in names]
