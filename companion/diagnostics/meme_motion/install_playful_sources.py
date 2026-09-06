#!/usr/bin/env python3
"""Install two selected local UMA locomotion sources with measured contact metadata.

The complete authored quaternions and hips translations are copied unchanged.
Both remain priority zero, so they require explicit selection for a supported
move and cannot replace the normal default UMA walk through catalog ordering.
"""
import hashlib
import json
from pathlib import Path
import shutil

COMPANION = Path(__file__).resolve().parents[2]
SELECTED = {
    'playful_strut': {
        'source_alias': 'uma_homewalk03_loop',
        'description': 'Authored broad-stride parade walk with large arm swings; choose for a finite supported move.',
        'locomotion_style': {'version': 1, 'cycle_stride_leg_lengths': 1.539550751,
                             'contacts': {'left': [.31, .59], 'right': [.81, .09]},
                             'contact_blend_phase': .04, 'preserve_source_hip_height': True,
                             'hip_translation_limit_leg_lengths': .15},
    },
    'mambo_goofy_walk': {
        'source_alias': 'uma_walkunique09_loop',
        'description': 'Authored goofy high-knee strut with deliberate head and hip rocking; two gait cycles per full source loop.',
        'locomotion_style': {'version': 1, 'cycle_stride_leg_lengths': 4.165960726,
                             'contacts': {'left': [[.37, .52], [.88, .01]],
                                          'right': [[.06, .30], [.645, .835]]},
                             'contact_blend_phase': .025, 'preserve_source_hip_height': True,
                             'hip_translation_limit_leg_lengths': .25},
    },
}


def main():
    candidates = COMPANION / 'assets/research/playful-walk/candidates'
    manifest_path = COMPANION / 'motion-assets.json'
    manifest = json.loads(manifest_path.read_text())
    before = {entry['name']: entry for entry in manifest['motions'] if entry['name'] not in SELECTED}
    installed = []
    for name, selected in SELECTED.items():
        alias = selected['source_alias']
        source = candidates / (alias + '.vrma')
        proof = json.loads((candidates / (alias + '.bake.json')).read_text())
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != proof['output_sha256']:
            raise ValueError('Source bake checksum mismatch: ' + alias)
        relative = f'assets/motions/{name}.vrma'
        target = COMPANION / relative
        shutil.copy2(source, target)
        entry = {'name': name, 'path': relative, 'kind': 'vrma',
                 'duration': proof['duration'], 'loop': True, 'ambient': False,
                 'locomotion': True, 'locomotion_priority': 0, 'locomotion_preserve_hips': True,
                 'locomotion_style': selected['locomotion_style'],
                 'description': selected['description'], 'sha256': digest,
                 'source_clip': 'anm_eve_type00_' + alias.removeprefix('uma_'),
                 'source': 'local UMA extraction',
                 'source_manifest': 'assets/research/playful-walk/uma-source/manifest.json',
                 'conversion_manifest': str((candidates / (alias + '.bake.json')).relative_to(COMPANION)),
                 'license': 'local-user-assets-not-redistributable'}
        manifest['motions'] = [item for item in manifest['motions'] if item['name'] != name] + [entry]
        installed.append(entry)
    after = {entry['name']: entry for entry in manifest['motions'] if entry['name'] not in SELECTED}
    assert before == after
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    report = {'selection': 'Two full authored sources selected from 26 filename-screened candidates and visual/FK review',
              'bytes_preserved_from_source_bake': True, 'existing_entries_preserved': len(before),
              'locomotion_default_overridden': False, 'motions': installed}
    (COMPANION / 'diagnostics/meme_motion/playful-installed.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Installed optional authored locomotion:', ', '.join(SELECTED))


if __name__ == '__main__':
    main()
