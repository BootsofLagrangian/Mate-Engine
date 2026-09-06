#!/usr/bin/env python3
"""Fetch local test-character assets; models/voice/avatars are excluded from Git."""
import hashlib
import json
from pathlib import Path
import subprocess
import requests

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import gdown
    for item in json.loads((ROOT / 'character-assets.json').read_text()):
        profile = json.loads((ROOT / 'characters' / (item['id'] + '.json')).read_text())
        assets = profile['assets']
        vrm = ROOT / assets['vrm']
        vrm.parent.mkdir(parents=True, exist_ok=True)
        if not vrm.is_file() or sha(vrm) != item['vrm']['sha256']:
            partial = vrm.with_suffix('.vrm.part')
            gdown.download(id=item['vrm']['drive_id'], output=str(partial), use_cookies=False)
            if sha(partial) != item['vrm']['sha256'] or partial.read_bytes()[:4] != b'glTF':
                raise ValueError('Unexpected Drive avatar content: ' + item['id'])
            partial.replace(vrm)
        ref = item['reference']
        mp3 = ROOT / ref['mp3']
        if not mp3.is_file() or sha(mp3) != ref['sha256']:
            response = requests.get(ref['url'], timeout=60)
            response.raise_for_status()
            if hashlib.sha256(response.content).hexdigest() != ref['sha256']:
                raise ValueError('Unexpected voice reference content: ' + item['id'])
            mp3.write_bytes(response.content)
        wav = ROOT / assets['reference_audio']
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(mp3), '-ac', '1', '-ar', '32000',
                        '-af', f"apad=whole_dur={ref['minimum_seconds']}", '-c:a', 'pcm_s16le', str(wav)], check=True)
        print(item['id'] + ': VRM and official voice reference ready')


if __name__ == '__main__':
    main()
