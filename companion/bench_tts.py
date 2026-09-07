"""GPU API benchmark: same seed/text, warm repetitions; audio files for auditing."""
import httpx,json,time,pathlib,os
r=pathlib.Path(__file__).resolve().parent;cfg=json.loads((r/'config.json').read_text());out=[]
tag=os.getenv('MATE_BENCH_TAG','sdpa')
with httpx.Client(timeout=90) as c:
 for mode in [True,False,True,False]:
  for text in ['トレーナーさん、お疲れ様です。','僕も、ここにいますから。']:
   p=dict(text=text,text_lang='all_ja',ref_audio_path=str(r/'assets/reference.wav'),prompt_lang='all_ja',prompt_text=cfg['reference_text'],text_split_method='cut0',batch_size=1,media_type='raw',streaming_mode=True,seed=42,parallel_infer=mode,split_bucket=False,fragment_interval=.03)
   t=time.perf_counter();a=c.post('http://127.0.0.1:9880/tts',json=p);a.raise_for_status();wall=time.perf_counter()-t;duration=len(a.content)/64000;row=dict(parallel=mode,text=text,seconds=wall,audio_seconds=duration,rtf=wall/duration);out.append(row);print(row,flush=True)
   (r/f'logs/tts-{tag}-{len(out)}.pcm').write_bytes(a.content)
(r/f'logs/tts-{tag}-bench.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
