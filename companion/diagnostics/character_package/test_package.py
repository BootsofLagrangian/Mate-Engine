"""Real importer/exporter tests with tiny valid GLB/VRMA and PCM fixtures; no GPU."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import wave
import zipfile
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from engine.character_package import export_package, import_package, inspect_package, PackageError, json_bytes
from engine.profiles import load_profiles, build_system_prompt
from engine.motion_assets import MotionAssets
from engine.motions import MotionBank


def glb(document):
    body = json.dumps(document).encode()
    body += b' ' * ((-len(body)) % 4)
    return struct.pack('<4sIIII', b'glTF', 2, 20 + len(body), len(body), 0x4E4F534A) + body


@pytest.fixture
def source(tmp_path):
    root = tmp_path / 'source'
    (root / 'characters').mkdir(parents=True)
    (root / 'assets/motions').mkdir(parents=True)
    (root / 'assets/test.vrm').write_bytes(glb({'asset': {'version': '2.0'}, 'extensions': {'VRMC_vrm': {}}}))
    with wave.open(str(root / 'assets/test.wav'), 'wb') as stream:
        stream.setparams((1, 2, 32000, 0, 'NONE', 'not compressed'))
        # Non-zero bytes avoid unrealistic >1000x compression attack protection.
        stream.writeframes(bytes(range(256)) * 750)
    clip = glb({'asset': {'version': '2.0'}, 'animations': [{}], 'extensions': {'VRMC_vrm_animation': {}}})
    (root / 'assets/motions/uma_walk.vrma').write_bytes(clip)
    (root / 'motion-assets.json').write_bytes(json_bytes({'version': 1, 'motions': [{'name': 'uma_walk', 'path': 'assets/motions/uma_walk.vrma', 'duration': 1.3, 'sha256': hashlib.sha256(clip).hexdigest(), 'locomotion': True, 'locomotion_priority': 50}]}))
    profile = {'id': 'test', 'name': 'テスト', 'canonical_facts': ['A test'], 'roleplay_guidance': ['静かに話す'],
        'examples': [{'user': 'Hi', 'text': 'こんにちは。'}], 'assets': {'vrm': 'assets/test.vrm', 'reference_audio': 'assets/test.wav', 'reference_text': 'こんにちは。'},
        'ambient_loop': 'uma_walk', 'motion_style': {'amplitude': .8}, 'behavior_style': {'curiosity': .7},
        'package': {'speaking_patterns': ['Short replies'], 'voice_patterns': ['Soft delivery'], 'motion_ids': ['uma_walk']}}
    (root / 'characters/test.json').write_bytes(json_bytes(profile))
    return root


@pytest.fixture
def package(source, tmp_path):
    path = tmp_path / 'test.matecharacter'
    export_package('test', path, source)
    return path


def rewrite(path, transform):
    with zipfile.ZipFile(path) as stream:
        files = {i.filename: stream.read(i.filename) for i in stream.infolist()}
    transform(files)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as stream:
        for name, content in files.items():
            stream.writestr(name, content)


def modify_payload(files, name, callback):
    value = json.loads(files[name])
    callback(value)
    files[name] = json_bytes(value)
    manifest = json.loads(files['manifest.json'])
    record = next(f for f in manifest['files'] if f['path'] == name)
    record.update(bytes=len(files[name]), sha256=hashlib.sha256(files[name]).hexdigest())
    files['manifest.json'] = json_bytes(manifest)


def test_roundtrip_engine_consumes_all_assets(package, source, tmp_path):
    dest = tmp_path / 'dest'
    report = import_package(package, dest, allow_missing_runtime=True)
    assert report['registered'] and len(report['missing_tts_weights']) == 2
    profile = load_profiles(dest / 'characters', dest, strict=True)['test']
    assert profile.vrm_path().read_bytes() == (source / 'assets/test.vrm').read_bytes()
    assert profile.reference()[0].read_bytes() == (source / 'assets/test.wav').read_bytes()
    assert profile.data['package']['speaking_patterns'] == ['Short replies']
    assert 'Short replies' in build_system_prompt(profile)
    motions = MotionAssets(dest).catalog()['motions']
    assert [(m['name'], m['locomotion']) for m in motions] == [('uma_walk', True)]
    assert str(source) not in json.dumps(profile.data)
    other = tmp_path / 'export-again.matecharacter'
    export_package('test', other, dest)
    assert inspect_package(other)['motions'] == ['uma_walk']


def test_existing_requires_explicit_replace(package, tmp_path):
    dest = tmp_path / 'dest'
    import_package(package, dest, allow_missing_runtime=True)
    profile = dest / 'characters/test.json'
    before = profile.read_bytes()
    with pytest.raises(PackageError, match='already exists'):
        import_package(package, dest, allow_missing_runtime=True)
    assert profile.read_bytes() == before
    assert import_package(package, dest, replace=True, allow_missing_runtime=True)['registered']


def test_missing_runtime_not_silently_ready(package, tmp_path):
    dest = tmp_path / 'dest'
    with pytest.raises(PackageError, match='Missing external TTS'):
        import_package(package, dest)
    assert not (dest / 'characters/test.json').exists()
    assert not (dest / '.matecharacter-import.lock').exists()


@pytest.mark.parametrize('name', ['../escape', '/absolute', 'C:/evil', 'foo\\bar', 'a/../b', 'CON.txt', 'dir/trailing.', 'a//b', 'a/./b'])
def test_archive_path_rejection(package, name):
    rewrite(package, lambda files: files.update({name: b'bad'}))
    with pytest.raises(PackageError):
        inspect_package(package)


def test_symlink_rejection(package):
    with zipfile.ZipFile(package, 'a') as archive:
        entry = zipfile.ZipInfo('symlink')
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        archive.writestr(entry, '../outside')
    with pytest.raises(PackageError, match='Symlink'):
        inspect_package(package)


def test_case_collision_rejection(package):
    with zipfile.ZipFile(package, 'a') as archive:
        archive.writestr('PROFILE.json', '{}')
    with pytest.raises(PackageError, match='case-colliding'):
        inspect_package(package)


def test_hash_tamper_rejection(package, tmp_path):
    rewrite(package, lambda files: files.update({'payload/avatar.vrm': files['payload/avatar.vrm'][:-1] + b'x'}))
    with pytest.raises(PackageError, match='Checksum'):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)
    assert not (tmp_path / 'dest/characters/test.json').exists()


def test_missing_required_asset(package):
    rewrite(package, lambda files: files.pop('payload/reference.wav'))
    with pytest.raises(PackageError, match='Missing asset'):
        inspect_package(package)


def test_version_rejection(package):
    def update(files):
        manifest = json.loads(files['manifest.json']); manifest['version'] = 999
        files['manifest.json'] = json_bytes(manifest)
    rewrite(package, update)
    with pytest.raises(PackageError, match='format/version'):
        inspect_package(package)


def test_expansion_budget(package):
    with zipfile.ZipFile(package, 'a', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('bomb', b'\0' * (2 * 1024 * 1024))
    with pytest.raises(PackageError, match='decompression budget'):
        inspect_package(package)


def test_missing_motion_reference(package):
    rewrite(package, lambda files: modify_payload(files, 'profile.json', lambda p: p.update(ambient_loop='missing')))
    with pytest.raises(PackageError, match='missing motion'):
        inspect_package(package)


def test_model_override_rejected(package):
    def update(files):
        manifest = json.loads(files['manifest.json'])
        manifest['requirements']['tts']['weights'][0]['sha256'] = '0' * 64
        files['manifest.json'] = json_bytes(manifest)
    rewrite(package, update)
    with pytest.raises(PackageError, match='arbitrary model activation'):
        inspect_package(package)


def test_existing_symlink_parent_rejected(package, tmp_path):
    dest = tmp_path / 'dest'; dest.mkdir()
    outside = tmp_path / 'outside'; outside.mkdir()
    (dest / 'assets').symlink_to(outside, target_is_directory=True)
    with pytest.raises(PackageError, match='Symlink'):
        import_package(package, dest, allow_missing_runtime=True)
    assert not list(outside.iterdir())


def test_package_procedural_motion_loaded(source, tmp_path):
    bank = source.parent / 'Assets/StreamingAssets/cheval-motions.json'
    bank.parent.mkdir(parents=True)
    motion = {'name': 'wiggle', 'duration': 1, 'tracks': [{'bone': 'head', 'keys': [{'time': 0}, {'time': .5, 'z': 10}, {'time': 1}]}]}
    bank.write_bytes(json_bytes({'motions': [motion]}))
    profile = json.loads((source / 'characters/test.json').read_text())
    profile['package']['motion_ids'].append('wiggle')
    (source / 'characters/test.json').write_bytes(json_bytes(profile))
    package = tmp_path / 'custom.matecharacter'
    export_package('test', package, source)
    dest = tmp_path / 'dest'
    import_package(package, dest, allow_missing_runtime=True)
    loaded = MotionBank(bank, dest / 'user-data/motions', root=dest).customs()
    assert loaded[0]['name'] == 'wiggle'


def test_no_histories_secrets_or_extra_files_exported(source, tmp_path):
    (source / 'user-data').mkdir(); (source / 'user-data/history.json').write_text('private conversation')
    (source / '.env').write_text('TOKEN=private')
    package = tmp_path / 'safe.matecharacter'
    export_package('test', package, source)
    with zipfile.ZipFile(package) as archive:
        assert not any('history' in n or 'env' in n or 'user-data' in n for n in archive.namelist())


def test_corrupt_immutable_install_rejected(package, tmp_path):
    dest = tmp_path / 'dest'
    import_package(package, dest, allow_missing_runtime=True)
    profile = load_profiles(dest / 'characters', dest)['test']
    profile.vrm_path().write_bytes(b'corrupted')
    with pytest.raises(PackageError, match='immutable package asset is corrupt'):
        import_package(package, dest, replace=True, allow_missing_runtime=True)


def test_conflicting_motion_rejected(package, source, tmp_path):
    dest = tmp_path / 'dest'; (dest / 'assets/motions').mkdir(parents=True)
    clip = glb({'asset': {'version': '2.0'}, 'animations': [{'name': 'different'}], 'extensions': {'VRMC_vrm_animation': {}}})
    (dest / 'assets/motions/uma_walk.vrma').write_bytes(clip)
    (dest / 'motion-assets.json').write_bytes(json_bytes({'version': 1, 'motions': [{'name': 'uma_walk', 'path': 'assets/motions/uma_walk.vrma', 'duration': 2, 'sha256': hashlib.sha256(clip).hexdigest()}]}))
    with pytest.raises(PackageError, match='Conflicting installed motion'):
        import_package(package, dest, allow_missing_runtime=True)
    assert not (dest / 'characters/test.json').exists()


def test_procedural_reexport_without_builtin_bank(source, tmp_path):
    bank = source.parent / 'Assets/StreamingAssets/cheval-motions.json'
    bank.parent.mkdir(parents=True)
    motion = {'name': 'wiggle', 'duration': 1, 'tracks': [{'bone': 'head', 'keys': [{'time': 0}, {'time': .5, 'z': 10}, {'time': 1}]}]}
    bank.write_bytes(json_bytes({'motions': [motion]}))
    profile = json.loads((source / 'characters/test.json').read_text())
    profile['package']['motion_ids'].append('wiggle')
    (source / 'characters/test.json').write_bytes(json_bytes(profile))
    archive = tmp_path / 'one.matecharacter'
    export_package('test', archive, source)
    dest = tmp_path / 'isolated/companion'
    import_package(archive, dest, allow_missing_runtime=True)
    other = tmp_path / 'two.matecharacter'
    export_package('test', other, dest)
    assert 'wiggle' in inspect_package(other)['motions']


def replace_binary(files, name, body):
    files[name] = body
    manifest = json.loads(files['manifest.json'])
    entry = next(f for f in manifest['files'] if f['path'] == name)
    entry.update(bytes=len(body), sha256=hashlib.sha256(body).hexdigest())
    files['manifest.json'] = json_bytes(manifest)


@pytest.mark.parametrize('avatar', [struct.pack('<4sII', b'glTF', 2, 12), glb({'asset': {'version': '2.0'}}), glb({'asset': {'version': '2.0'}, 'extensions': {'VRM': {}}, 'images': [{'uri': 'file:///etc/passwd'}]})])
def test_invalid_or_external_avatar_rejected(package, tmp_path, avatar):
    rewrite(package, lambda files: replace_binary(files, 'payload/avatar.vrm', avatar))
    with pytest.raises(PackageError):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)
    assert not (tmp_path / 'dest/characters/test.json').exists()


def test_truncated_pcm_rejected(package, tmp_path):
    rewrite(package, lambda files: replace_binary(files, 'payload/reference.wav', files['payload/reference.wav'][:44]))
    with pytest.raises(PackageError, match='Truncated'):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)


def test_custom_runtime_layout_is_explicit(monkeypatch):
    from engine.character_package import check_layout, COMPANION_ROOT
    monkeypatch.setenv('MATE_CHARACTERS_DIR', '/tmp/another-character-directory')
    with pytest.raises(PackageError, match='MATE_CHARACTERS_DIR'):
        check_layout(COMPANION_ROOT.resolve())


def test_external_vrma_resource_rejected(package, tmp_path):
    def update(files):
        body = glb({'asset': {'version': '2.0'}, 'animations': [{}], 'extensions': {'VRMC_vrm_animation': {}}, 'buffers': [{'uri': '../../outside.bin'}]})
        replace_binary(files, 'payload/motions/uma_walk.vrma', body)
        modify_payload(files, 'motions.json', lambda m: m['motions'][0].update(sha256=hashlib.sha256(body).hexdigest()))
    rewrite(package, update)
    with pytest.raises(PackageError, match='External VRM'):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)


def test_reference_matches_tts_ten_second_limit(package, tmp_path):
    import io
    content = io.BytesIO()
    with wave.open(content, 'wb') as stream:
        stream.setparams((1, 2, 32000, 0, 'NONE', 'not compressed'))
        stream.writeframes(bytes(range(256)) * 2750)  # 11 seconds, outside actual GPT-SoVITS contract.
    rewrite(package, lambda files: replace_binary(files, 'payload/reference.wav', content.getvalue()))
    with pytest.raises(PackageError, match='3–10 seconds'):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)


def test_avatar_variant_export_import_preserves_identity_and_assets(source, tmp_path):
    from engine.profiles import Profile
    profile_path = source / 'characters/test.json'
    profile = json.loads(profile_path.read_text())
    alternate = glb({'asset': {'version': '2.0'}, 'extensions': {'VRMC_vrm': {}}, 'extras': {'costume': 'wet'}})
    (source / 'assets/test-wet.vrm').write_bytes(alternate)
    profile['avatar_variants'] = [{'id': 'wet', 'label': '비 맞은 모습', 'vrm': 'assets/test-wet.vrm', 'description': 'Optional costume', 'mood_tags': ['playful']}]
    profile_path.write_bytes(json_bytes(profile))
    archive = tmp_path / 'variants.matecharacter'
    report = export_package('test', archive, source)
    assert report['avatar_variants'][0]['sha256'] == hashlib.sha256(alternate).hexdigest()
    dest = tmp_path / 'dest'
    import_package(archive, dest, allow_missing_runtime=True)
    actual = load_profiles(dest / 'characters', dest, strict=True)['test']
    assert actual.id == profile['id'] and actual.data['roleplay_guidance'] == profile['roleplay_guidance']
    assert actual.vrm_path('wet').read_bytes() == alternate
    assert actual.vrm_path('default').read_bytes() != alternate
    assert actual.reference()[1] == profile['assets']['reference_text']
    assert actual.vrm_path('absent') is None
    entries = actual.catalog_entry()['avatar_variants']
    assert [v['id'] for v in entries] == ['default', 'wet']
    assert entries[1]['avatar_url'] == '/characters/test/avatar?variant=wet'
    assert entries[1]['avatar_available'] and entries[1]['mood_tags'] == ['playful']
    exported_again = tmp_path / 'variants-again.matecharacter'
    assert export_package('test', exported_again, dest)['avatar_variants'][0]['sha256'] == report['avatar_variants'][0]['sha256']


@pytest.mark.parametrize('variant', [
    {'id': 'default', 'label': 'Bad', 'vrm': 'assets/alt.vrm'},
    {'id': 'wet', 'label': 'Bad', 'vrm': '../alt.vrm'},
    {'id': 'wet', 'label': 'Bad', 'vrm': 'C:\\alt.vrm'},
    {'id': 'wet', 'label': 'Bad', 'vrm': 'assets/alt.vrm', 'voice': {'engine': 'other'}},
    {'id': 'wet', 'label': 'Bad', 'vrm': 'assets/alt.vrm', 'motion_overrides': {}},
    {'id': 'wet', 'label': '', 'vrm': 'assets/alt.vrm'},
])
def test_avatar_variant_bad_contract_rejected(source, tmp_path, variant):
    p = source / 'characters/test.json'; data = json.loads(p.read_text())
    data['avatar_variants'] = [variant]; p.write_bytes(json_bytes(data))
    with pytest.raises(ValueError):
        export_package('test', tmp_path / 'invalid.matecharacter', source)


def test_missing_avatar_variant_is_not_silently_omitted(source, tmp_path):
    p = source / 'characters/test.json'; data = json.loads(p.read_text())
    data['avatar_variants'] = [{'id': 'wet', 'label': 'Wet', 'vrm': 'assets/missing.vrm'}]; p.write_bytes(json_bytes(data))
    with pytest.raises(PackageError, match='Missing required asset'):
        export_package('test', tmp_path / 'invalid.matecharacter', source)


def add_variant_fixture(source):
    p = source / 'characters/test.json'; data = json.loads(p.read_text())
    (source / 'assets/alt.vrm').write_bytes(glb({'asset': {'version': '2.0'}, 'extensions': {'VRM': {}}}))
    data['avatar_variants'] = [{'id': 'wet', 'label': 'Wet', 'vrm': 'assets/alt.vrm', 'mood_tags': ['playful']}]
    p.write_bytes(json_bytes(data))


def test_appearance_ability_is_derived_portable_and_engine_visible(source, tmp_path):
    add_variant_fixture(source)
    archive = tmp_path / 'ability.matecharacter'
    report = export_package('test', archive, source)
    ability = report['abilities'][0]
    assert ability['id'] == 'change_appearance'
    assert ability['intent_schema']['properties']['variant_id']['enum'] == ['default', 'wet']
    assert ability['intent_schema']['properties']['kind'] == {'const': 'change_appearance'}
    assert ability['variants'][1]['mood_tags'] == ['playful']
    with zipfile.ZipFile(archive) as stream:
        assert json.loads(stream.read('manifest.json'))['abilities'] == [ability]
    dest = tmp_path / 'dest'
    import_package(archive, dest, allow_missing_runtime=True)
    profile = load_profiles(dest / 'characters', dest, strict=True)['test']
    assert profile.catalog_entry()['abilities'] == [ability]
    profile.vrm_path('wet').unlink()
    assert profile.appearance_ability()['intent_schema']['properties']['variant_id']['enum'] == ['default']


def test_appearance_ability_tamper_rejected(source, tmp_path):
    add_variant_fixture(source)
    archive = tmp_path / 'ability.matecharacter'; export_package('test', archive, source)
    def tamper(files):
        manifest = json.loads(files['manifest.json'])
        manifest['abilities'][0]['intent_schema']['properties']['variant_id']['enum'].append('arbitrary-file')
        files['manifest.json'] = json_bytes(manifest)
    rewrite(archive, tamper)
    with pytest.raises(PackageError, match='Appearance ability differs'):
        import_package(archive, tmp_path / 'dest', allow_missing_runtime=True)


def test_older_v1_missing_ability_descriptor_is_derived(source, tmp_path):
    add_variant_fixture(source)
    archive = tmp_path / 'older.matecharacter'; export_package('test', archive, source)
    def remove(files):
        manifest = json.loads(files['manifest.json']); manifest.pop('abilities')
        files['manifest.json'] = json_bytes(manifest)
    rewrite(archive, remove)
    assert inspect_package(archive)['abilities'][0]['intent_schema']['properties']['variant_id']['enum'] == ['default', 'wet']
    assert import_package(archive, tmp_path / 'dest', allow_missing_runtime=True)['registered']


def add_locomotion_style(source, stride=4.1):
    style = {'version': 1, 'cycle_stride_leg_lengths': stride,
             'contacts': {'left': [[.37, .52], [.88, .01]], 'right': [[.06, .3], [.645, .835]]},
             'contact_blend_phase': .025, 'preserve_source_hip_height': True, 'hip_translation_limit_leg_lengths': .25}
    path = source / 'motion-assets.json'; data = json.loads(path.read_text())
    data['motions'][0]['locomotion_style'] = style
    data['motions'][0]['seated_transition'] = 'enter'
    path.write_bytes(json_bytes(data))
    return style


def test_locomotion_multi_contact_style_and_seating_metadata_roundtrip(source, tmp_path):
    style = add_locomotion_style(source)
    archive = tmp_path / 'gait.matecharacter'; export_package('test', archive, source)
    dest = tmp_path / 'dest'; import_package(archive, dest, allow_missing_runtime=True)
    entry = MotionAssets(dest).catalog()['motions'][0]
    assert entry['locomotion_style'] == style
    assert entry['seated_transition'] == 'enter'
    second = tmp_path / 'gait-again.matecharacter'; export_package('test', second, dest)
    with zipfile.ZipFile(second) as stream:
        assert json.loads(stream.read('motions.json'))['motions'][0]['locomotion_style'] == style


def test_rehashed_invalid_locomotion_style_rejected(package, tmp_path):
    rewrite(package, lambda files: modify_payload(files, 'motions.json', lambda m: m['motions'][0].update(locomotion_style={'version': 1})))
    with pytest.raises(PackageError, match='Invalid locomotion style'):
        import_package(package, tmp_path / 'dest', allow_missing_runtime=True)


def test_same_binary_different_gait_metadata_cannot_shadow(source, tmp_path):
    add_locomotion_style(source)
    first = tmp_path / 'gait.matecharacter'; export_package('test', first, source)
    dest = tmp_path / 'dest'; import_package(first, dest, allow_missing_runtime=True)
    add_locomotion_style(source, stride=3.9)
    second = tmp_path / 'gait-new.matecharacter'; export_package('test', second, source)
    with pytest.raises(PackageError, match='Conflicting installed motion'):
        import_package(second, dest, replace=True, allow_missing_runtime=True)
