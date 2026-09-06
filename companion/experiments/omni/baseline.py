"""Same synthetic audio -> existing STT/text-Qwen/character-TTS baseline."""
import json,time
from pathlib import Path
import httpx
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'logs/omni';OUT.mkdir(exist_ok=True)
manifest=json.loads((ROOT/'logs/omni-inputs/manifest.json').read_text());results=[]
with httpx.Client(timeout=120) as c:
 for case in manifest:
  start=time.perf_counter()
  with open(case['path'],'rb') as f:r=c.post('http://127.0.0.1:8765/stt',files={'audio':('input.wav',f,'audio/wav')})
  r.raise_for_status();stt=r.json();stt_ms=(time.perf_counter()-start)*1000;events=[];first=None
  with c.stream('POST','http://127.0.0.1:8765/chat/stream',json={'text':stt['text'],'session':'omni-baseline-'+case['id'],'voice':True}) as r:
   r.raise_for_status()
   for line in r.iter_lines():
    e=json.loads(line)
    if e['type']=='audio':
     if first is None:first=(time.perf_counter()-start)*1000
    elif e['type']!='ping':events.append(e)
  row={'input':case,'stt':stt,'stt_ms':stt_ms,'first_pcm_from_upload_ms':first,'events':events};results.append(row)
  print(json.dumps({'id':case['id'],'stt':stt,'first_pcm_ms':first,'done':events[-1]},ensure_ascii=False),flush=True)
  (OUT/'baseline.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
