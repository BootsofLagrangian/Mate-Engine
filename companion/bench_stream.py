"""Record actual arrival times; excludes audio packet contents from the report."""
import json,time
from pathlib import Path
import httpx
ROOT=Path(__file__).resolve().parent
results=[]
with httpx.Client(timeout=90) as client:
    for _ in range(30):
        try:
            if client.get('http://127.0.0.1:8765/health').json()['tts_ready']:break
        except httpx.HTTPError:pass
        time.sleep(.5)
    for prompt in ['안녕 슈발, 오늘 같이 쉬자.','오늘 피곤하니까 같이 기지개 켜자.','오늘 연습이 잘 안 돼서 슬퍼.']:
        start=time.perf_counter();events=[];frames=0;pcm_bytes=0
        with client.stream('POST','http://127.0.0.1:8765/chat/stream',json={'text':prompt,'session':'stream-bench','voice':True}) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line:continue
                event=json.loads(line)
                if event['type']=='audio':
                    frames+=1;pcm_bytes+=len(event['pcm'])*3//4
                    if frames>1:continue
                    event={k:v for k,v in event.items() if k!='pcm'}
                if event['type']=='ping':continue
                events.append({'arrival_ms':round((time.perf_counter()-start)*1000,1),**event})
        report={'input':prompt,'frames':frames,'approx_pcm_bytes':pcm_bytes,'events':events}
        results.append(report)
        print(json.dumps({'input':prompt,'first_audio':next((e for e in events if e['type']=='audio'),None),'done':events[-1]},ensure_ascii=False),flush=True)
(ROOT/'logs/stream-benchmark.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
