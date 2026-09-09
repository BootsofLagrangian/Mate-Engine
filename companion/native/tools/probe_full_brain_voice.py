#!/usr/bin/env python3
"""Opt-in real local LLM/TTS delivery while full-connectome GPU work runs."""
import argparse
import asyncio
import base64
import json
from pathlib import Path
import time
import httpx
import websockets

async def run(output):
    events=[];brain=[];start=time.perf_counter();finished=asyncio.Event()
    async with httpx.AsyncClient(timeout=15) as client:
        status=(await client.post('http://127.0.0.1:8876/autonomy/brain/load',json={})).json()
        deadline=time.monotonic()+45
        while not status.get('loaded') and time.monotonic()<deadline:
            await asyncio.sleep(.2);status=(await client.get('http://127.0.0.1:8876/autonomy/brain')).json()
        if not status.get('loaded'):raise RuntimeError(status)
        async def stimulate():
            for sequence in range(1,41):
                if finished.is_set():break
                at=time.perf_counter()
                r=await client.post('http://127.0.0.1:8876/autonomy/brain/step',json={'session_id':'voice-probe','generation':int(start),'sequence':sequence,'left':.8 if sequence%2 else .2,'right':.2 if sequence%2 else .8})
                data=r.json();brain.append({'start_s':at-start,'end_s':time.perf_counter()-start,'status':r.status_code,'data':data})
                await asyncio.sleep(.5) # intentional stress cadence, faster than production 5s decisions
        async with websockets.connect('ws://127.0.0.1:8876/ws',max_size=16*1024*1024) as ws:
            await ws.recv();worker=asyncio.create_task(stimulate());start=time.perf_counter()
            await ws.send(json.dumps({'type':'chat','turn_id':'full-brain-voice','character':'cheval-grand','text':'안녕, 지금 기분이 어때? 한 문장으로 말해줘.','voice':True},ensure_ascii=False))
            try:
                async with asyncio.timeout(60):
                    async for message in ws:
                        event=json.loads(message);event['at_s']=time.perf_counter()-start
                        if 'pcm' in event:event['pcm_bytes']=len(base64.b64decode(event.pop('pcm')))
                        events.append(event)
                        if event.get('type')=='done':break
            finally:finished.set();await worker
    report={'scope':'Actual local model and dedicated trained voice PCM delivery, with concurrent full-brain GPU calls at 0.5s stress cadence. No native playback or controlled latency comparison claim.','events':events,'brain':brain,
            'audio_bytes':sum(e.get('pcm_bytes',0) for e in events),'first_audio_s':next((e['at_s'] for e in events if e.get('pcm_bytes',0)>0),None),
            'successful_brain_steps':sum(b['status']==200 for b in brain),'errors':[e for e in events if e.get('type')=='error']}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2,ensure_ascii=False));print({k:report[k] for k in ['audio_bytes','first_audio_s','successful_brain_steps','errors']})
    assert report['audio_bytes']>0 and report['successful_brain_steps']>0 and not report['errors']
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);args=p.parse_args();asyncio.run(run(args.output))
