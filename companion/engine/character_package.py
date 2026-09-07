"""Version 1 .matecharacter interchange. Data only; never executes package content."""
import argparse
import copy
import hashlib
import json
import os
import math
import struct
import wave
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tempfile
import zipfile
from . import COMPANION_ROOT, config
from .profiles import Profile, valid_id
from .motions import MotionBank, validate_motion
from .motion_assets import MotionAssets, valid_locomotion_style

FORMAT = 'mate.character'
VERSION = 1
MAX_FILES = 512
MAX_FILE = 2 * 1024**3
MAX_TOTAL = 8 * 1024**3
MAX_JSON = 2 * 1024**2
MAX_RATIO = 1000
WEIGHTS = {
    'models/uma-AIO-GPT-v2-e100.ckpt': '847f88e3d8bea9dc37fc686a02499e7402d9af6cceb6e6eda6bdbb3b16582716',
    'models/uma-AIO-SoViTS-v2_e20_s8300.pth': '417d80e4fedb5bd4d9f45d985dc889d4fa738a8644177dea310f894e3c973a06',
}


class PackageError(ValueError):
    pass


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n').encode('utf-8')


def safe_name(name):
    if not isinstance(name, str) or not name or len(name) > 240 or '\\' in name or ':' in name or '\x00' in name:
        raise PackageError('Unsafe archive path')
    parts = PurePosixPath(name).parts
    if name.startswith('/') or any(p in ('', '.', '..') or p.endswith((' ', '.')) for p in name.split('/')):
        raise PackageError(f'Unsafe archive path: {name}')
    if any(re.fullmatch(r'(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?', p) for p in parts):
        raise PackageError('Reserved Windows filename')
    return name


def inside(root, relative):
    safe_name(relative)
    root = Path(root).resolve()
    current = root
    for part in PurePosixPath(relative).parts:
        current = current / part
        if current.is_symlink():
            raise PackageError('Symlink asset path is forbidden')
    current.resolve().relative_to(root)
    return current


def read_json(data):
    if len(data) > MAX_JSON:
        raise PackageError('JSON document too large')
    def unique(pairs):
        obj = {}
        for key, value in pairs:
            if key in obj:
                raise PackageError('Duplicate JSON key')
            obj[key] = value
        return obj
    return json.loads(data, object_pairs_hook=unique, parse_constant=lambda x: (_ for _ in ()).throw(PackageError('Non-finite JSON')))


def validate_avatar(path, animation=False):
    """Validate GLB framing and self-contained VRM data before registering it."""
    size = path.stat().st_size
    with path.open('rb') as stream:
        header = stream.read(12)
        if len(header) != 12 or struct.unpack('<4sII', header) != (b'glTF', 2, size):
            raise PackageError('Invalid VRM GLB header')
        document, index = None, 0
        while stream.tell() < size:
            chunk = stream.read(8)
            if len(chunk) != 8:
                raise PackageError('Truncated VRM chunk header')
            length, kind = struct.unpack('<II', chunk)
            if length % 4 or stream.tell() + length > size:
                raise PackageError('Invalid VRM chunk boundary')
            if index == 0:
                if kind != 0x4E4F534A or length > 8 * 1024 * 1024:
                    raise PackageError('Invalid VRM JSON chunk')
                document = json.loads(stream.read(length))
            else:
                if kind != 0x004E4942 or index != 1:
                    raise PackageError('Unexpected VRM GLB chunk')
                stream.seek(length, 1)
            index += 1
    if not isinstance(document, dict) or not isinstance(document.get('asset'), dict) or document['asset'].get('version') != '2.0':
        raise PackageError('Missing VRM glTF document')
    extensions = document.get('extensions', {})
    required = ('VRMC_vrm_animation',) if animation else ('VRM', 'VRMC_vrm')
    if not isinstance(extensions, dict) or not any(isinstance(extensions.get(key), dict) for key in required):
        raise PackageError('Missing VRM extension')
    for kind in ('buffers', 'images'):
        entries = document.get(kind, [])
        if not isinstance(entries, list):
            raise PackageError('Invalid VRM resources')
        for item in entries:
            if not isinstance(item, dict):
                raise PackageError('Invalid VRM resource')
            uri = item.get('uri')
            if uri is not None and (not isinstance(uri, str) or not uri.startswith('data:')):
                raise PackageError('External VRM resources are forbidden in a portable package')


def requirements(root):
    return {
        'engine': {'id': 'mate-companion', 'character_package_version': VERSION},
        'dialogue': {'id': 'qwen2.5-omni-thinker-or-compatible-provider', 'external': True, 'audio_input': True, 'speech_output': False},
        'tts': {'id': 'gpt-sovits-v2-uma-aio', 'external': True, 'reference_language': 'ja', 'text_language': 'ja',
                'source': 'https://huggingface.co/UmaDiffusion/uma-voice-gpt-sovits-v2',
                'weights': [{'path': p, 'sha256': digest} for p, digest in WEIGHTS.items()],
                'other_dependencies': ['GPT-SoVITS v2 runtime', 'chinese-hubert-base', 'chinese-roberta-wwm-ext-large']},
    }


def check_layout(root):
    if root == COMPANION_ROOT.resolve():
        defaults = ((config.characters_dir(), root / 'characters', 'MATE_CHARACTERS_DIR'),
                    (config.user_data_dir(), root / 'user-data', 'MATE_USER_DATA'),
                    (config.motion_bank_path(), root.parent / 'Assets/StreamingAssets/cheval-motions.json', 'MATE_MOTION_BANK'))
        for actual, expected, setting in defaults:
            if actual.resolve() != expected.resolve():
                raise PackageError(f'Package CLI requires default companion layout; unset {setting} or import into an explicit isolated --root')


def export_package(character_id, output, root=COMPANION_ROOT, include_tts_weights=False):
    root, output = Path(root).resolve(), Path(output)
    check_layout(root)
    if not valid_id(character_id):
        raise PackageError('Invalid character id')
    source = inside(root, f'characters/{character_id}.json')
    profile = Profile(read_json(source.read_bytes()), source, root)
    data = copy.deepcopy(profile.data)
    data.pop('package_install', None)
    assets = {}
    sources = {}
    provenance = []
    def add(path, dest, role, metadata=None):
        path = Path(path)
        path.relative_to(root)
        inside(root, path.relative_to(root).as_posix())
        if not path.is_file():
            raise PackageError(f'Missing required asset: {path.name}')
        sources[dest] = path
        provenance.append({'path': dest, 'role': role, 'source': metadata or profile.data.get('source', ''),
                           'license': 'Unverified; private local use. Verify redistribution permission before sharing.'})
        return dest
    vrm = profile.vrm_path()
    if not vrm or not vrm.is_file():
        raise PackageError('Required VRM is missing')
    assets['vrm'] = add(vrm, 'payload/avatar.vrm', 'avatar')
    for variant in data.get('avatar_variants', []):
        source_variant = profile.vrm_path(variant['id'])
        if source_variant is None:
            raise PackageError('Missing avatar variant: ' + variant['id'])
        variant['vrm'] = add(source_variant, f'payload/variants/{variant["id"]}.vrm', 'avatar-variant')
    reference = profile.reference()
    if reference is None:
        raise PackageError('Required voice reference or transcript is missing')
    assets['reference_audio'] = add(reference[0], 'payload/reference.wav', 'voice-reference')
    assets['reference_text'] = reference[1]
    data['assets'] = assets
    motion_index = MotionAssets(root)
    available = {entry['name']: (entry, path) for entry, path in motion_index.entries()}
    source_manifest = read_json((root / 'motion-assets.json').read_bytes()) if (root / 'motion-assets.json').exists() else {'motions': []}
    provenance_by_name = {entry['name']: entry for entry in source_manifest.get('motions', [])}
    names = list(dict.fromkeys([profile.ambient_loop, *profile.idle_actions, 'uma_walk']))
    if 'uma_walk' not in available:
        names.remove('uma_walk')
    # Optional declarative package metadata can name additional reusable motions.
    meta = data.get('package', {})
    if not isinstance(meta, dict):
        raise PackageError('profile.package must be an object')
    extra_motions = meta.get('motion_ids', [])
    if not isinstance(extra_motions, list) or any(not isinstance(n, str) for n in extra_motions):
        raise PackageError('package.motion_ids must be a list of motion IDs')
    names += extra_motions
    builtin_path = root.parent / 'Assets/StreamingAssets/cheval-motions.json'
    bank = MotionBank(builtin_path, root / 'user-data/motions', root=root)
    procedural = {m['name']: m for m in (bank.bank()['motions'] if builtin_path.exists() else bank.customs())}
    motions, customs = [], []
    for name in dict.fromkeys(n for n in names if n):
        if name in available:
            entry, path = available[name]
            entry = {k: v for k, v in entry.items() if k != 'asset_url'}
            entry['path'] = add(path, f'payload/motions/{name}.vrma', 'motion', provenance_by_name.get(name, {}))
            motions.append(entry)
        elif name in procedural:
            customs.append(validate_motion(name, procedural[name]))
        else:
            raise PackageError(f'Required motion is not installed: {name}')
    blobs = {'profile.json': json_bytes(data), 'motions.json': json_bytes({'version': 1, 'motions': motions, 'procedural': customs})}
    if include_tts_weights:
        for path, digest in WEIGHTS.items():
            local = inside(root, path)
            if not local.is_file() or sha(local) != digest:
                raise PackageError(f'Installed TTS weight differs from supported runtime: {path}')
            add(local, 'runtime/' + Path(path).name, 'runtime-weight', 'UmaDiffusion/uma-voice-gpt-sovits-v2')
    inventory = []
    for path, body in blobs.items():
        inventory.append({'path': path, 'bytes': len(body), 'sha256': hashlib.sha256(body).hexdigest()})
    for path, local in sources.items():
        inventory.append({'path': path, 'bytes': local.stat().st_size, 'sha256': sha(local)})
    manifest = {'format': FORMAT, 'version': VERSION, 'character_id': profile.id, 'profile': 'profile.json', 'motions': 'motions.json',
                'files': inventory, 'requirements': requirements(root), 'provenance': provenance,
                'abilities': [profile.appearance_ability(False)] if profile.appearance_ability(False) else [],
                'redistribution': 'private-use-unverified', 'extensions': meta}
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.mate-export-', dir=output.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
            archive.writestr('manifest.json', json_bytes(manifest))
            for path, body in blobs.items():
                archive.writestr(path, body)
            for path, local in sources.items():
                archive.write(local, path)
        inspect_package(temporary)
        os.replace(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return inspect_package(output, root)


def validated_archive(archive):
    infos = archive.infolist()
    if len(infos) > MAX_FILES:
        raise PackageError('Too many archive entries')
    names, total = set(), 0
    for info in infos:
        name = safe_name(info.filename)
        if name.casefold() in names or info.is_dir():
            raise PackageError('Duplicate/case-colliding path or directory entry')
        names.add(name.casefold())
        mode = info.external_attr >> 16
        if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG)) or info.flag_bits & 1:
            raise PackageError('Symlink, special or encrypted ZIP entry')
        if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise PackageError('Unsupported ZIP compression')
        total += info.file_size
        if info.file_size > MAX_FILE or total > MAX_TOTAL or info.file_size / max(1, info.compress_size) > MAX_RATIO:
            raise PackageError('Archive exceeds decompression budget')
    if 'manifest.json' not in archive.namelist() or archive.getinfo('manifest.json').file_size > MAX_JSON:
        raise PackageError('Missing or oversized manifest')
    manifest = read_json(archive.read('manifest.json'))
    if not isinstance(manifest, dict) or manifest.get('format') != FORMAT or type(manifest.get('version')) is not int or manifest['version'] != VERSION:
        raise PackageError('Unsupported package format/version')
    if not valid_id(manifest.get('character_id')) or manifest.get('profile') != 'profile.json' or manifest.get('motions') != 'motions.json':
        raise PackageError('Invalid manifest identity or entry point')
    files = manifest.get('files')
    if not isinstance(files, list) or not files:
        raise PackageError('Missing file inventory')
    listed = set()
    for entry in files:
        if not isinstance(entry, dict):
            raise PackageError('Invalid file inventory')
        name = safe_name(entry.get('path'))
        if name in listed or name == 'manifest.json':
            raise PackageError('Duplicate inventory entry')
        listed.add(name)
        if name not in archive.namelist() or type(entry.get('bytes')) is not int or entry['bytes'] != archive.getinfo(name).file_size:
            raise PackageError(f'Missing asset or wrong size: {name}')
        with archive.open(name) as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != entry.get('sha256'):
            raise PackageError(f'Checksum mismatch: {name}')
    if listed != set(archive.namelist()) - {'manifest.json'} or not {'profile.json', 'motions.json'} <= listed:
        raise PackageError('Unlisted or missing package files')
    if any(archive.getinfo(n).file_size > MAX_JSON for n in ('profile.json', 'motions.json')):
        raise PackageError('Oversized profile/motion JSON')
    profile = read_json(archive.read('profile.json'))
    validated_profile = Profile(profile, Path(manifest['character_id'] + '.json'))
    ability = validated_profile.appearance_ability(False)
    derived_abilities = [ability] if ability else []
    # Older v1 archives omit this derived descriptor; never trust a supplied independent allowlist.
    if 'abilities' in manifest and manifest['abilities'] != derived_abilities:
        raise PackageError('Appearance ability differs from validated profile variants')
    if manifest.get('extensions') != profile.get('package', {}) or not isinstance(manifest.get('redistribution'), str):
        raise PackageError('Missing or inconsistent package metadata')
    provenance = manifest.get('provenance')
    if not isinstance(provenance, list) or any(not isinstance(p, dict) or not {'path', 'role', 'source', 'license'} <= p.keys() for p in provenance):
        raise PackageError('Missing asset provenance')
    if profile['id'] != manifest['character_id'] or 'package_install' in profile:
        raise PackageError('Profile identity/installation metadata mismatch')
    assets = profile.get('assets', {})
    if set(assets) != {'vrm', 'reference_audio', 'reference_text'} or not isinstance(assets['reference_text'], str) or not assets['reference_text'].strip():
        raise PackageError('Missing/unsupported avatar or voice asset declaration')
    if assets['vrm'] != 'payload/avatar.vrm' or assets['reference_audio'] != 'payload/reference.wav':
        raise PackageError('Invalid avatar/reference package path')
    expected = {'profile.json', 'motions.json', assets['vrm'], assets['reference_audio']}
    for variant in profile.get('avatar_variants', []):
        if variant['vrm'] != f'payload/variants/{variant["id"]}.vrm':
            raise PackageError('Invalid avatar variant package path')
        expected.add(variant['vrm'])
    motions = read_json(archive.read('motions.json'))
    if not isinstance(motions, dict) or type(motions.get('version')) is not int or motions.get('version') != 1 or not isinstance(motions.get('motions'), list) or not isinstance(motions.get('procedural'), list):
        raise PackageError('Invalid motion manifest')
    from .motions import MOTION_ID
    seen = set()
    for entry in motions['motions']:
        name = entry.get('name') if isinstance(entry, dict) else None
        if not isinstance(name, str) or not MOTION_ID.fullmatch(name) or name in seen or entry.get('path') != f'payload/motions/{name}.vrma':
            raise PackageError('Invalid or duplicate motion')
        duration = entry.get('duration')
        if type(duration) not in (float, int) or not math.isfinite(duration) or duration <= 0:
            raise PackageError('Invalid motion duration')
        for flag in ('loop', 'ambient', 'locomotion', 'locomotion_preserve_hips'):
            if flag in entry and not isinstance(entry[flag], bool):
                raise PackageError('Invalid motion capability')
        if type(entry.get('locomotion_priority', 0)) is not int or not 0 <= entry.get('locomotion_priority', 0) <= 100:
            raise PackageError('Invalid motion priority')
        if entry.get('contact_mode', '') not in ('', 'foot'):
            raise PackageError('Invalid motion contact mode')
        style = entry.get('locomotion_style', {})
        if not valid_locomotion_style(style) or (style and not entry.get('locomotion', False)):
            raise PackageError('Invalid locomotion style')
        if entry.get('seated_transition', '') not in ('', 'enter', 'exit'):
            raise PackageError('Invalid seated transition')
        seen.add(name)
        expected.add(entry['path'])
        inventory = next((f for f in files if f['path'] == entry['path']), {})
        if entry.get('sha256') != inventory.get('sha256'):
            raise PackageError('Motion/inventory hash mismatch')
    for motion in motions['procedural']:
        name = motion.get('name') if isinstance(motion, dict) else None
        validate_motion(name, motion)
        if name in seen:
            raise PackageError('Duplicate procedural motion')
        seen.add(name)
    extras = profile.get('package', {}).get('motion_ids', [])
    if not isinstance(extras, list) or any(not isinstance(n, str) for n in extras):
        raise PackageError('Invalid package motion references')
    for name in [profile.get('ambient_loop'), *profile.get('idle_actions', []), *extras]:
        if name and name not in seen:
            raise PackageError('Profile refers to missing motion')
    req = manifest.get('requirements', {})
    if req != requirements(None):
        raise PackageError('Unsupported runtime requirements; arbitrary model activation is forbidden')
    for path, digest in WEIGHTS.items():
        candidate = 'runtime/' + Path(path).name
        if candidate in listed:
            if next(f['sha256'] for f in files if f['path'] == candidate) != digest:
                raise PackageError('Untrusted runtime weight')
            expected.add(candidate)
    if expected != listed:
        raise PackageError('Unsupported or missing asset; executable/plugin payloads are forbidden')
    return manifest, profile, motions


def inspect_package(path, root=None):
    with zipfile.ZipFile(path) as archive:
        manifest, profile, motions = validated_archive(archive)
    validated_profile = Profile(profile, Path(profile['id'] + '.json'))
    ability = validated_profile.appearance_ability(False)
    missing = []
    if root is not None:
        for relative, digest in WEIGHTS.items():
            local = inside(root, relative)
            if not local.is_file() or sha(local) != digest:
                missing.append(relative)
    return {'format': FORMAT, 'version': VERSION, 'character_id': profile['id'], 'name': profile['name'],
            'sha256': sha(path), 'bytes': Path(path).stat().st_size, 'files': len(manifest['files']),
            'motions': [m['name'] for m in motions['motions'] + motions['procedural']],
            'avatar_variants': [{'id': v['id'], 'label': v['label'], 'path': v['vrm'], 'sha256': next(f['sha256'] for f in manifest['files'] if f['path'] == v['vrm'])} for v in profile.get('avatar_variants', [])],
            'abilities': [ability] if ability else [],
            'media_validation': 'performed on import; inspection verifies inventory and declarations',
            'requirements': manifest['requirements'], 'runtime_checked': root is not None,
            'missing_or_mismatched_tts_weights': missing, 'runtime_health_checked': False,
            'redistribution': manifest.get('redistribution'), 'provenance': manifest.get('provenance', []),
            'profile_fields': sorted(profile), 'extensions': manifest.get('extensions', {})}


def import_package(path, root=COMPANION_ROOT, replace=False, allow_missing_runtime=False):
    root = Path(root).resolve()
    check_layout(root)
    root.mkdir(parents=True, exist_ok=True)
    # Lock serializes import writers. Profile registration is the sole activation point.
    lock = root / '.matecharacter-import.lock'
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    try:
        with zipfile.ZipFile(path) as archive:
            manifest, profile, motions = validated_archive(archive)
            target = inside(root, f"characters/{profile['id']}.json")
            if target.exists() and not replace:
                raise PackageError('Character already exists; use --replace explicitly')
            package_hash = sha(path)
            prefix = f'assets/character-packages/{profile["id"]}/{package_hash}'
            install = inside(root, prefix)
            # Stage on the destination filesystem; never extract directly to live paths.
            with tempfile.TemporaryDirectory(prefix='.matecharacter-stage-', dir=root) as tmp:
                stage = Path(tmp)
                for entry in manifest['files']:
                    dest = stage / safe_name(entry['path'])
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(entry['path']) as source, dest.open('wb') as sink:
                        shutil.copyfileobj(source, sink, 1024 * 1024)
                validate_avatar(stage / profile['assets']['vrm'])
                for variant in profile.get('avatar_variants', []):
                    validate_avatar(stage / variant['vrm'])
                try:
                    with wave.open(str(stage / profile['assets']['reference_audio']), 'rb') as audio:
                        frames, rate = audio.getnframes(), audio.getframerate()
                        if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or not 8000 <= rate <= 96000 or not rate * 3 <= frames <= rate * 10:
                            raise PackageError('Voice reference needs mono PCM16 WAV, 3–10 seconds, 8–96 kHz')
                        if len(audio.readframes(frames)) != frames * 2:
                            raise PackageError('Truncated voice reference PCM frames')
                except (wave.Error, EOFError) as exc:
                    raise PackageError('Invalid voice reference WAV') from exc
                for motion in motions['motions']:
                    validate_avatar(stage / motion['path'], animation=True)
                    if not MotionAssets(stage)._validated(stage / motion['path'], motion['sha256']):
                        raise PackageError('Invalid VRMA payload')
                required_missing = []
                for relative, digest in WEIGHTS.items():
                    local = inside(root, relative)
                    if local.exists() and (not local.is_file() or sha(local) != digest):
                        raise PackageError(f'Existing shared model differs: {relative}')
                    bundled = stage / 'runtime' / Path(relative).name
                    if not local.exists() and not bundled.exists():
                        required_missing.append(relative)
                if required_missing and not allow_missing_runtime:
                    raise PackageError('Missing external TTS weights: ' + ', '.join(required_missing) + '; install runtime or use --allow-missing-runtime')
                existing_vrma = {entry['name']: entry for entry, _ in MotionAssets(root).entries()}
                builtin = root.parent / 'Assets/StreamingAssets/cheval-motions.json'
                bank = MotionBank(builtin, root / 'user-data/motions', root=root)
                existing_procedural = {m['name']: m for m in (bank.bank()['motions'] if builtin.exists() else bank.customs())}
                for entry in motions['motions']:
                    other = existing_vrma.get(entry['name'])
                    if entry['name'] in existing_procedural or (other and any(other.get(k) != entry.get(k) for k in ('sha256', 'duration', 'loop', 'ambient', 'contact_mode', 'locomotion', 'locomotion_priority', 'locomotion_preserve_hips', 'locomotion_style', 'seated_transition'))):
                        raise PackageError('Conflicting installed motion: ' + entry['name'])
                for entry in motions['procedural']:
                    other = existing_procedural.get(entry['name'])
                    if entry['name'] in existing_vrma or (other and validate_motion(entry['name'], other) != validate_motion(entry['name'], entry)):
                        raise PackageError('Conflicting installed procedural motion: ' + entry['name'])
                # Motion paths remain within the engine allowlisted assets/motions namespace.
                for entry in motions['motions']:
                    old = entry['path']
                    new = f'assets/motions/character-packages/{package_hash}/{Path(old).name}'
                    dest = inside(root, new)
                    if dest.exists() and sha(dest) != entry['sha256']:
                        raise PackageError('Existing immutable motion asset is corrupt')
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    if not dest.exists():
                        os.replace(stage / old, dest)
                    else:
                        (stage / old).unlink()
                    entry['path'] = new
                for key in ('vrm', 'reference_audio'):
                    profile['assets'][key] = prefix + '/' + profile['assets'][key]
                for variant in profile.get('avatar_variants', []):
                    variant['vrm'] = prefix + '/' + variant['vrm']
                profile['package_install'] = {'format': FORMAT, 'version': VERSION, 'archive_sha256': package_hash,
                    'motions': prefix + '/motions.json', 'requirements': manifest['requirements']}
                (stage / 'motions.json').write_bytes(json_bytes(motions))
                (stage / 'manifest.json').write_bytes(json_bytes(manifest))
                # Only pinned, already-supported shared model bytes can be installed.
                for relative in WEIGHTS:
                    bundled = stage / 'runtime' / Path(relative).name
                    local = inside(root, relative)
                    if bundled.exists() and not local.exists():
                        local.parent.mkdir(parents=True, exist_ok=True)
                        os.replace(bundled, local)
                    elif bundled.exists():
                        bundled.unlink()
                install.parent.mkdir(parents=True, exist_ok=True)
                if install.exists():
                    for staged in stage.rglob('*'):
                        if staged.is_file():
                            existing = inside(root, prefix + '/' + staged.relative_to(stage).as_posix())
                            if not existing.is_file() or sha(existing) != sha(staged):
                                raise PackageError('Existing immutable package asset is corrupt')
                else:
                    os.replace(stage, install)
                target.parent.mkdir(parents=True, exist_ok=True)
                fd, temporary = tempfile.mkstemp(prefix='.mate-profile-', dir=target.parent)
                try:
                    with os.fdopen(fd, 'wb') as stream:
                        stream.write(json_bytes(profile))
                        stream.flush()
                        os.fsync(stream.fileno())
                    os.replace(temporary, target)
                finally:
                    Path(temporary).unlink(missing_ok=True)
        return {'character_id': profile['id'], 'profile': str(target), 'archive_sha256': package_hash,
                'registered': True, 'missing_tts_weights': required_missing, 'restart_backend_required': True}
    finally:
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=COMPANION_ROOT)
    sub = parser.add_subparsers(dest='command', required=True)
    export = sub.add_parser('export')
    export.add_argument('character_id')
    export.add_argument('output', type=Path)
    export.add_argument('--include-tts-weights', action='store_true')
    inspect = sub.add_parser('inspect')
    inspect.add_argument('package', type=Path)
    load = sub.add_parser('import')
    load.add_argument('package', type=Path)
    load.add_argument('--replace', action='store_true')
    load.add_argument('--allow-missing-runtime', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'export':
            result = export_package(args.character_id, args.output, args.root, args.include_tts_weights)
        elif args.command == 'inspect':
            result = inspect_package(args.package, args.root)
        else:
            result = import_package(args.package, args.root, args.replace, args.allow_missing_runtime)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as exc:
        parser.exit(2, json.dumps({'error': str(exc)}, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
