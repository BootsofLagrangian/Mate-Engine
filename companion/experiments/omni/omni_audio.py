"""Audio-only input adapter for the existing phrase -> character-TTS pipeline.

No ASR transcript is used as model input. Loads Thinker only: no Talker or
Token2Wav weights are instantiated. Kept separate from the running text backend.
"""
import json,queue,threading,sys,time,re
from pathlib import Path
import numpy as np,soundfile as sf,torch,librosa
from transformers import (Qwen2_5OmniConfig,Qwen2_5OmniThinkerForConditionalGeneration,
                          Qwen2_5OmniProcessor,StoppingCriteria,StoppingCriteriaList)
from transformers.generation.streamers import BaseStreamer
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from persona import SYSTEM
from stream_pipeline import partial_text

class CancelGeneration(StoppingCriteria):
    def __init__(self,*events):self.events=events
    def __call__(self,*args,**kwargs):return any(e.is_set() for e in self.events)

class Tokens(BaseStreamer):
    def __init__(self):self.queue=queue.Queue();self.prompt=True
    def put(self,value):
        if self.prompt:self.prompt=False;return
        self.queue.put(value.detach().cpu().reshape(-1).tolist())
    def end(self):self.queue.put(None)

class OmniAudio:
    def __init__(self):
        torch.set_num_threads(8)
        path=ROOT/'models/qwen2.5-omni-3b-thinker';start=time.perf_counter()
        config=Qwen2_5OmniConfig.from_pretrained(path)
        self.processor=Qwen2_5OmniProcessor.from_pretrained(path)
        self.model=Qwen2_5OmniThinkerForConditionalGeneration.from_pretrained(
            path,config=config.thinker_config,torch_dtype=torch.bfloat16,
            device_map={'':'cuda'},attn_implementation='sdpa').eval()
        assert not hasattr(self.model,'talker') and not hasattr(self.model,'token2wav')
        self.load_seconds=time.perf_counter()-start
        self.path=None;self.last={};self.lock=threading.Lock();self.poisoned=False
    def stream_reply(self,_text,_session,cancelled=None):
        with self.lock:
            if self.poisoned:raise RuntimeError('Previous GPU generation did not stop; restart process')
            cancel=cancelled if cancelled is not None else threading.Event();stop=threading.Event()
            start=time.perf_counter();audio,rate=sf.read(self.path,dtype='float32')
            if audio.ndim>1:audio=audio.mean(axis=1)
            if rate!=16000:audio=librosa.resample(audio,orig_sr=rate,target_sr=16000)
            if len(audio)==0 or len(audio)>30*16000 or not np.isfinite(audio).all():
                raise ValueError('Audio must be finite and between 0 and 30 seconds')
            messages=[{'role':'system','content':[{'type':'text','text':SYSTEM}]},
                      {'role':'user','content':[{'type':'audio','audio':str(self.path)},
                       {'type':'text','text':'これは人間のトレーナーの発言です。音声の内容に、シュヴァルとして日本語で答えてください。返事は指定されたJSONだけ。'}]}]
            prompt=self.processor.apply_chat_template(messages,add_generation_prompt=True,tokenize=False)
            # Preserve at least one STFT window of zero padding after the signal.
            # Valid frames matched the default 300-second padded frontend exactly.
            padded=((len(audio)+400+159)//160)*160
            inputs=self.processor(text=prompt,audio=[audio],sampling_rate=16000,return_tensors='pt',padding=True,audio_kwargs={'max_length':padded})
            inputs=inputs.to('cuda')
            for k,v in inputs.items():
                if torch.is_floating_point(v):inputs[k]=v.to(torch.bfloat16)
            self.last={'preprocess_ms':round((time.perf_counter()-start)*1000,1),'input_tokens':inputs['input_ids'].shape[-1],
                       'audio_feature_shape':list(inputs['input_features'].shape),'raw':'','generated_tokens':0}
            streamer=Tokens();errors=[]
            def generate():
                try:
                    with torch.inference_mode():self.model.generate(**inputs,max_new_tokens=220,do_sample=False,
                       streamer=streamer,stopping_criteria=StoppingCriteriaList([CancelGeneration(cancel,stop)]))
                except BaseException as exc:errors.append(exc)
                finally:streamer.end()
            worker=threading.Thread(target=generate,daemon=True);worker.start();ids=[];previous='';raw='';result=None
            try:
                while True:
                    chunk=streamer.queue.get(timeout=90)
                    if chunk is None:break
                    if not ids:yield 'token',None
                    ids+=chunk;raw=self.processor.tokenizer.decode(ids,skip_special_tokens=True)
                    text=partial_text(raw)
                    # A byte-level token may end inside a UTF-8 character.
                    if '\ufffd' in text:text=text[:text.index('\ufffd')]
                    if re.search('[A-Za-z가-힣ᄀ-ᇿ㄰-㆏ꥠ-꥿ힰ-퟿]',text):
                        raise ValueError('Non-Japanese script in spoken output; suppressed before TTS')
                    if text!=previous:
                        if not text.startswith(previous):raise ValueError('Non-monotonic decoded text')
                        previous=text;yield 'text',text
                    candidate=raw.lstrip()
                    if candidate.startswith('```json'):candidate=candidate[7:].lstrip()
                    elif candidate.startswith('```'):candidate=candidate[3:].lstrip()
                    if candidate.startswith('{'):
                        try:
                            obj,end=json.JSONDecoder().raw_decode(candidate)
                            if isinstance(obj,dict) and all(k in obj for k in ('text','emotion','gesture')):
                                result=obj;break
                        except json.JSONDecodeError:pass
            finally:
                stop.set();worker.join(timeout=90)
                self.poisoned=worker.is_alive()
                self.last.update(raw=raw,generated_tokens=len(ids))
            if worker.is_alive():raise RuntimeError('Omni generation did not stop')
            if errors:raise errors[0]
            if result is None:raise ValueError('Omni did not emit complete dialogue JSON: '+raw[:250])
            if not isinstance(result['text'],str) or not result['text'].strip():raise ValueError('Empty dialogue')
            if result['emotion'] not in ('neutral','happy','sad','relaxed','surprised'):result['emotion']='neutral'
            if result['gesture'] not in ('idle','nod','shake_head','shy','wave','think','bow','stretch'):result['gesture']='idle'
            yield 'result',result
