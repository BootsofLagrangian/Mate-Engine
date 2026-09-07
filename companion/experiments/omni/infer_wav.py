"""Usage: .venv-omni/bin/python infer_wav.py recorded-korean.wav"""
import argparse,json
from pathlib import Path
from types import SimpleNamespace
from omni_audio import OmniAudio,ROOT
from stream_pipeline import conversation_stream
p=argparse.ArgumentParser();p.add_argument('audio',type=Path);args=p.parse_args()
model=OmniAudio();model.path=args.audio.resolve()
for line in conversation_stream(model,SimpleNamespace(text='audio-only',session='omni-wav',voice=True),ROOT):
 e=json.loads(line)
 if e['type'] not in ('audio','ping'):print(json.dumps(e,ensure_ascii=False),flush=True)
 if e['type']=='done' and e.get('audio_url'):print('WAV:',ROOT/'output'/Path(e['audio_url']).name,flush=True)
