"""Run direct audio -> Omni Thinker -> provided character SoVITS, with audit logs."""
import json,time,sys,hashlib,threading
from pathlib import Path
from types import SimpleNamespace
import torch,httpx,soundfile as sf
from omni_audio import OmniAudio,ROOT
from stream_pipeline import conversation_stream
OUT=ROOT/'logs/omni';OUT.mkdir(parents=True,exist_ok=True)

def main():
    manifest=json.loads((ROOT/'logs/omni-inputs/manifest.json').read_text())
    # Recognition is a separate input-quality control, never passed to Omni.
    for row in manifest:
        with open(row['path'],'rb') as f:
            t=time.perf_counter();r=httpx.post('http://127.0.0.1:8765/stt',files={'audio':('input.wav',f,'audio/wav')},timeout=90)
        r.raise_for_status();row['whisper_input_control']=r.json();row['whisper_seconds']=time.perf_counter()-t
    (OUT/'input-controls.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    torch.cuda.reset_peak_memory_stats();model=OmniAudio()
    report={'model':'Qwen/Qwen2.5-Omni-3B Thinker only','dtype':'bfloat16','attention':'sdpa',
            'load_seconds':model.load_seconds,'talker_present':hasattr(model.model,'talker'),
            'token2wav_present':hasattr(model.model,'token2wav'),
            'parameter_devices':sorted(set(str(p.device) for p in model.model.parameters())),
            'parameter_count':sum(p.numel() for p in model.model.parameters()),
            'source_revision':'f75b40e3da2003cdd6e1829b1f420ca70797c34e',
            'tts_weights':{},'runs':[]}
    for name in ['uma-AIO-GPT-v2-e100.ckpt','uma-AIO-SoViTS-v2_e20_s8300.pth']:
        report['tts_weights'][name]=hashlib.sha256((ROOT/'models'/name).read_bytes()).hexdigest()
    # First run is explicitly cold; repeat one input after all cases for warm timing.
    cases=manifest+[manifest[0]]
    for i,case in enumerate(cases):
        model.path=Path(case['path']);torch.cuda.reset_peak_memory_stats()
        req=SimpleNamespace(text='audio-only',session=f'omni-probe-{i}',voice=True)
        events=[];audio_packets=0;first_audio=None;pcm_bytes=0;start=time.perf_counter()
        for line in conversation_stream(model,req,ROOT):
            event=json.loads(line)
            if event['type']=='audio':
                import base64
                audio_packets+=1;pcm_bytes+=len(base64.b64decode(event['pcm']))
                if first_audio is None:first_audio=(time.perf_counter()-start)*1000
            elif event['type']!='ping':events.append(event)
        result={'input':case,'repeat':i>=len(manifest),'events':events,'first_pcm_arrival_ms':first_audio,
                'audio_packets':audio_packets,'audio_seconds':pcm_bytes/64000,
                'omni':model.last,'omni_process_allocated_gib':torch.cuda.memory_allocated()/1024**3,
                'omni_process_peak_allocated_gib':torch.cuda.max_memory_allocated()/1024**3,
                'omni_process_peak_reserved_gib':torch.cuda.max_memory_reserved()/1024**3}
        report['runs'].append(result)
        (OUT/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        if model.poisoned:raise SystemExit('Fatal generation timeout; restart probe process')
        print(json.dumps({'id':case['id'],'first_pcm_ms':first_audio,'peak_gib':result['omni_process_peak_allocated_gib'],'final':events[-1]},ensure_ascii=False),flush=True)
    # Dedicated output speech intelligibility probe; does not affect model inputs.
    for row in report['runs']:
        done=next((e for e in row['events'] if e['type']=='done'),{})
        url=done.get('audio_url')
        if url:
            path=ROOT/'output'/Path(url).name
            with path.open('rb') as f:r=httpx.post('http://127.0.0.1:8765/stt',files={'audio':('output.wav',f,'audio/wav')},timeout=90)
            row['output_asr_check']=r.json()
    (OUT/'results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
