#!/usr/bin/env python3
"""Explicit real-asset packaging audit; outputs stay local/ignored, never uploaded.

Run after the character and motion owners freeze their assets. This is loader
validation; it neither starts a GPU service nor opens a native pet window.
"""
import argparse
import json
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from engine.character_package import export_package, import_package, inspect_package, sha
from engine.motion_assets import MotionAssets
from engine.profiles import load_profiles, build_system_prompt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--install-root', type=Path, required=True)
    args = parser.parse_args()
    root, installed_root = args.root.resolve(), args.install_root.resolve()
    if installed_root.exists():
        raise ValueError('Use a fresh isolated installation directory for an unambiguous audit')
    characters = ['cheval-grand', 'rice-shower', 'eishin-flash', 'mambo', 'hachimi']
    profiles = load_profiles(root / 'characters', root, strict=True)
    source_catalog = {e['name']: e for e in MotionAssets(root).catalog()['motions']}
    source_manifest_hash = sha(root / 'motion-assets.json')
    source_profile_hashes = {name: sha(root / 'characters' / (name + '.json')) for name in characters}
    output = root / 'output'
    full_archive = output / 'cheval-grand-with-tts.matecharacter'
    export_package('cheval-grand', full_archive, root, include_tts_weights=True)
    import_package(full_archive, installed_root)
    records = []
    for name in characters:
        archive = output / (name + '.matecharacter')
        inspected = export_package(name, archive, root)
        installed = import_package(archive, installed_root, replace=name == 'cheval-grand')
        profile = load_profiles(installed_root / 'characters', installed_root, strict=True)[name]
        source = profiles[name]
        catalog = {e['name']: e for e in MotionAssets(installed_root).catalog()['motions']}
        requested = inspected['motions']
        assert all(catalog[mid] == source_catalog[mid] for mid in requested), 'Motion semantics changed during import'
        assert sha(profile.vrm_path()) == sha(source.vrm_path()), 'Default avatar changed'
        assert sha(profile.reference()[0]) == sha(source.reference()[0]), 'Voice reference changed'
        assert profile.catalog_entry()['abilities'] == inspected['abilities'], 'LM ability changed'
        assert all(sha(profile.vrm_path(v['id'])) == sha(source.vrm_path(v['id'])) for v in profile.avatar_variants), 'Variant avatar changed'
        with wave.open(str(profile.reference()[0])) as audio:
            seconds = audio.getnframes() / audio.getframerate()
        records.append({
            'id': name, 'source_profile_sha256': source_profile_hashes[name],
            'source_stable_during_export': source_profile_hashes[name] == sha(root / 'characters' / (name + '.json')),
            'archive_path': archive.relative_to(root).as_posix(), 'archive_sha256': sha(archive), 'archive_bytes': archive.stat().st_size,
            'inventory': inspected, 'installed': installed, 'loader_catalog': profile.catalog_entry(),
            'avatar_sha256': sha(profile.vrm_path()), 'reference_audio_sha256': sha(profile.reference()[0]), 'reference_seconds': seconds,
            'profile_motion_ids': [profile.ambient_loop, *profile.idle_actions, *profile.data.get('package', {}).get('motion_ids', [])],
            'variant_assets': [{'id': v['id'], 'sha256': sha(profile.vrm_path(v['id'])), 'bytes': profile.vrm_path(v['id']).stat().st_size} for v in profile.avatar_variants],
            'voice_style_in_system_prompt': all(line in build_system_prompt(profile) for line in profile.data.get('package', {}).get('voice_patterns', [])),
            'motion_metadata_exact_match': True,
            'appearance_ability_exact_match': True,
        })
    assert all(r['source_stable_during_export'] for r in records), 'Profile changed during audit'
    assert source_manifest_hash == sha(root / 'motion-assets.json'), 'Motion metadata changed during audit'
    evidence = root / 'diagnostics/character_package'
    samples = {'records': records, 'installed_motion_catalog': MotionAssets(installed_root).catalog(),
               'source_motion_manifest_sha256': source_manifest_hash,
               'scope': 'Private local asset archives; exact isolated engine loaders and shared TTS model hashes. No native/GPU session launched.'}
    (evidence / 'sample-packages.json').write_text(json.dumps(samples, ensure_ascii=False, indent=2) + '\n')
    cheval = load_profiles(installed_root / 'characters', installed_root, strict=True)['cheval-grand']
    full = inspect_package(full_archive, installed_root)
    assert not full['missing_or_mismatched_tts_weights']
    roundtrip = {'character_id': cheval.id, 'avatar_available': cheval.catalog_entry()['avatar_available'],
                 'voice_available': cheval.catalog_entry()['voice_available'], 'avatar_sha256': sha(cheval.vrm_path()),
                 'reference_sha256': sha(cheval.reference()[0]), 'motion_catalog': MotionAssets(installed_root).catalog(),
                 'persona_prompt_characters': len(build_system_prompt(cheval)), 'tts_weights_and_assets_package': full,
                 'small_package': inspect_package(output / 'cheval-grand.matecharacter'),
                 'reimport_same_package': import_package(output / 'cheval-grand.matecharacter', installed_root, replace=True),
                 'scope': samples['scope']}
    (evidence / 'roundtrip.json').write_text(json.dumps(roundtrip, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'install_root': str(installed_root), 'packages': [{'id': r['id'], 'bytes': r['archive_bytes'], 'sha256': r['archive_sha256'],
                       'motions': r['inventory']['motions'], 'variants': [v['id'] for v in r['variant_assets']]} for r in records]}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
