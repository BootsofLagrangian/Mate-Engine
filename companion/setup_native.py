#!/usr/bin/env python3
"""Install pinned Godot editor/templates/VRM plugins, or export the Windows host.

No character data is bundled into the exported executable.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
NATIVE = ROOT / 'native'
TOOLS = ROOT / 'tools'
VERSION = '4.5.2-stable'
PLUGINS = [
    ('V-Sekai/godot-vrm', 'e15199f980064028bfa4fbee5e70dddb82dd55c3', 'addons/vrm', 'vrm'),
    ('V-Sekai/Godot-MToon-Shader', '7aaabd21eb7ac9734c82053bad69f16fce6c33ea', '', 'Godot-MToon-Shader')]


def fetch(url, path):
    if path.is_file():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(path.suffix + '.part')
    with urllib.request.urlopen(url, timeout=180) as response, partial.open('wb') as out:
        shutil.copyfileobj(response, out)
    partial.replace(path)


def setup():
    cache = TOOLS / 'downloads'
    base = f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}/'
    name = f'Godot_v{VERSION}_linux.x86_64'
    fetch(base + name + '.zip', cache / (name + '.zip'))
    with zipfile.ZipFile(cache / (name + '.zip')) as z:
        (TOOLS / name).write_bytes(z.read(name))
    (TOOLS / name).chmod(0o755)
    archive = cache / 'templates.tpz'
    fetch(base + f'Godot_v{VERSION}_export_templates.tpz', archive)
    templates = TOOLS / 'export_templates/4.5.2.stable'
    templates.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for template in ('windows_release_x86_64.exe', 'windows_debug_x86_64.exe'):
            (templates / template).write_bytes(z.read('templates/' + template))
    for repo, revision, source, name in PLUGINS:
        archive = cache / (name + '-' + revision + '.zip')
        fetch(f'https://github.com/{repo}/archive/{revision}.zip', archive)
        destination = NATIVE / 'addons' / name
        destination.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            prefix = z.namelist()[0] + (source + '/' if source else '')
            for member in z.namelist():
                if not member.startswith(prefix) or member.endswith('/'):
                    continue
                relative = Path(member[len(prefix):])
                if relative.is_absolute() or '..' in relative.parts:
                    raise ValueError('Unsafe archive member')
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(member))
    for patch in ('godot-vrm-bone-rename.patch', 'mtoon-screen-outline-depth.patch'):
        subprocess.run(['patch', '-p1', '--forward', '-i', str(ROOT / 'patches' / patch)], cwd=NATIVE, check=True)
    print('Pinned Godot and VRM plugins installed, including collision-safe bone renaming.')


def build():
    godot = TOOLS / f'Godot_v{VERSION}_linux.x86_64'
    template = TOOLS / 'export_templates/4.5.2.stable/windows_release_x86_64.exe'
    if not godot.is_file() or not template.is_file():
        raise SystemExit('Run setup_native.py first.')
    preset_path = NATIVE / 'export_presets.cfg'
    original = preset_path.read_text()
    def source_snapshot():
        sources = list((NATIVE / 'scripts').glob('*.gd')) + [NATIVE / 'main.tscn', NATIVE / 'project.godot']
        # Record installed plugin code as well as the patch recipes: exports use
        # these actual bytes, including the off-axis MToon outline correction.
        sources += [p for p in (NATIVE / 'addons').rglob('*')
                    if p.is_file() and p.suffix in {'.gd', '.gdshader', '.gdshaderinc'}]
        return {str(p.relative_to(NATIVE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)}
    sources_before = source_snapshot()
    temporary = original.replace('custom_template/release=""', 'custom_template/release=' + json.dumps(str(template)))
    # Restore the portable tracked preset even if export fails.
    preset_path.write_text(temporary)
    try:
        checked_godot([str(godot), '--headless', '--path', str(NATIVE), '--editor', '--import'], 'native-import.log')
        out = NATIVE / 'build/MateCompanion.exe'
        out.parent.mkdir(exist_ok=True)
        checked_godot([str(godot), '--headless', '--path', str(NATIVE), '--export-release', 'Windows Desktop', str(out)], 'native-export.log')
        out.chmod(0o755)  # Also permits direct Windows interop launch from WSL.
        licenses = out.parent / 'licenses'
        licenses.mkdir(exist_ok=True)
        fetch('https://raw.githubusercontent.com/godotengine/godot/4.5.2-stable/LICENSE.txt', licenses / 'Godot.txt')
        fetch('https://raw.githubusercontent.com/godotengine/godot/4.5.2-stable/COPYRIGHT.txt', licenses / 'Godot-third-party.txt')
        for _, _, _, name in PLUGINS:
            shutil.copy2(NATIVE / 'addons' / name / 'LICENSE', licenses / (name + '.txt'))
        shutil.copy2(ROOT.parent / 'LICENSE.md', licenses / 'Mate-Engine.md')
        shutil.copy2(NATIVE / 'assets/desktop_objects/License.txt', licenses / 'Kenney-Furniture.txt')
        premium_provenance = NATIVE / 'assets/desktop_objects/premium/PROVENANCE.md'
        if premium_provenance.is_file():
            shutil.copy2(premium_provenance, licenses / 'Mate-Furniture-Provenance.md')
        for name in ('Launch-Mate.ps1', 'Launch-Mate.cmd'):
            shutil.copy2(ROOT / 'windows' / name, out.parent / name)
        launcher_readme = ROOT / 'windows/README.md'
        if launcher_readme.is_file():
            shutil.copy2(launcher_readme, out.parent / 'README.md')
        # Local launcher metadata stays in the ignored build directory.
        (out.parent / 'runtime-location.json').write_text(json.dumps({
            'distro': os.getenv('WSL_DISTRO_NAME', 'Ubuntu-24.04'), 'backend_root': str(ROOT)}, indent=2))
        sources_after = source_snapshot()
        manifest = {'godot': VERSION, 'plugins': [{'repo': r, 'revision': v} for r, v, _, _ in PLUGINS],
                    'source_before_sha256': sources_before, 'source_after_sha256': sources_after,
                    'source_stable_during_build': sources_before == sources_after,
                    'executable': out.name, 'bytes': out.stat().st_size, 'sha256': hashlib.sha256(out.read_bytes()).hexdigest(),
                    'character_assets_bundled': False,
                    'desktop_objects': {str(p.relative_to(NATIVE / 'assets/desktop_objects')): hashlib.sha256(p.read_bytes()).hexdigest()
                                        for p in sorted((NATIVE / 'assets/desktop_objects').rglob('*'))
                                        if p.is_file() and p.suffix in {'.glb', '.txt', '.json', '.md'}},
                    'patches': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sorted((ROOT / 'patches').glob('*.patch'))}}
        (out.parent / 'build-manifest.json').write_text(json.dumps(manifest, indent=2))
        print(str(out))
    finally:
        preset_path.write_text(original)


def checked_godot(argv, log_name):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=600)
    log = ROOT / 'logs' / log_name
    log.parent.mkdir(exist_ok=True)
    log.write_text(result.stdout)
    # Godot can return success after an individual GDScript failed to import.
    if result.returncode or any(line.startswith(('SCRIPT ERROR:', 'ERROR:'))
                               for line in result.stdout.splitlines()):
        raise RuntimeError(f'Godot import/export failed; inspect {log}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='Export using the installed tools')
    args = parser.parse_args()
    build() if args.build else setup()
