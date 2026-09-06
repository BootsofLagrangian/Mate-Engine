"""Incremental Qwen JSON -> short pronounceable clauses -> GPT-SoVITS raw PCM.

v2 synthesizes a complete input fragment, not an isolated phoneme stream. Text is
therefore committed at phrase/morpheme boundaries. 20 ms PCM packets are transport
frames and must not be confused with the acoustic model's inference granularity.
"""
import base64, io, json, os, queue, re, threading, time, uuid, wave
import httpx
from fastapi.responses import StreamingResponse
TTS_LOCK=threading.Lock()

class CancelStreamingResponse(StreamingResponse):
    def __init__(self,*args,cancel,**kwargs):
        self.cancel=cancel
        super().__init__(*args,**kwargs)
    async def __call__(self,scope,receive,send):
        try:await super().__call__(scope,receive,send)
        finally:self.cancel.set()

def cleanup_audio(root):
    for old in (root/'output').glob('*.wav'):
        try:
            if old.stat().st_mtime<time.time()-86400:old.unlink(missing_ok=True)
        except FileNotFoundError:pass



def partial_text(raw):
    match=re.search(r'"text"\s*:\s*"',raw)
    if not match:return ''
    tail=raw[match.end():]
    # Find a real closing quote; escaped quotes are part of speech.
    escaped=False
    for i,c in enumerate(tail):
        if c=='"' and not escaped:
            try:return json.loads('"'+tail[:i]+'"')
            except ValueError:return ''
        if c=='\\':escaped=not escaped
        else:escaped=False
    # Incomplete JSON escape sequences are withheld until the next token.
    for trim in range(min(12,len(tail))+1):
        candidate=tail if trim==0 else tail[:-trim]
        try:
            text=json.loads('"'+candidate+'"')
            # Withhold a lone high surrogate rather than publishing invalid UTF-8.
            if text and 0xD800<=ord(text[-1])<=0xDBFF:text=text[:-1]
            return text
        except ValueError:continue
    return ''


class PhraseChunker:
    def __init__(self):self.pending=''
    def push(self,delta,final=False):
        self.pending+=delta;chunks=[]
        while self.pending:
            cut=0
            for m in re.finditer(r'[。！？!?\n]|[、，,；;：:]|…{2,}',self.pending):
                # Full endings can commit a short acknowledgement; commas need
                # enough pronunciation context to avoid unstable isolated syllables.
                minimum=2 if m.group()[0] in '。！？!?\n' else 8
                if m.end()>=minimum:
                    cut=m.end();break
            if not cut and len(self.pending)>=24:
                # Never cut arbitrary token/character positions inside a word.
                import pyopenjtalk
                offset=0
                for word in pyopenjtalk.run_frontend(self.pending):
                    offset+=len(word['string'])
                    if 12<=offset<=28 and word.get('pos') in ('助詞','助動詞'):
                        cut=offset;break
            if not cut:
                if final:cut=len(self.pending)
                else:break
            phrase=self.pending[:cut].strip();self.pending=self.pending[cut:]
            if re.search(r'\w',phrase):chunks.append(phrase)
        return chunks


def conversation_stream(brain,req,root,cancelled=None):
    start=time.perf_counter();cancelled=cancelled if cancelled is not None else threading.Event()
    events=queue.Queue(maxsize=128);phrases=queue.Queue()
    metrics={};result={};audio_parts=[];errors=[];llm_failed=threading.Event()
    def ms():return round((time.perf_counter()-start)*1000,1)
    def emit(kind,**data):
        event={'type':kind,'elapsed_ms':ms(),**data}
        while not cancelled.is_set():
            try:events.put(event,timeout=.1);return
            except queue.Full:pass
    def llm_worker():
        chunker=PhraseChunker();previous='';count=0
        try:
            # Engine providers receive the whole request (text or audio); legacy brains take text.
            if hasattr(brain,'stream_turn'):stream=brain.stream_turn(req,cancelled)
            else:stream=brain.stream_reply(req.text.strip(),req.session,cancelled)
            for kind,value in stream:
                if cancelled.is_set():break
                if kind=='token':metrics.setdefault('first_token_ms',ms())
                elif kind=='text':
                    metrics.setdefault('first_text_ms',ms())
                    if not value.startswith(previous):raise ValueError('Non-monotonic LLM text stream')
                    delta=value[len(previous):];previous=value
                    emit('text',text=value,delta=delta)
                    for phrase in chunker.push(delta):
                        phrases.put((count,phrase));emit('phrase',index=count,text=phrase);count+=1
                elif kind=='result':
                    result.update(value);metrics['llm_done_ms']=ms()
                    for phrase in chunker.push('',final=True):
                        phrases.put((count,phrase));emit('phrase',index=count,text=phrase);count+=1
                    emit('action',**{k:value[k] for k in ('gesture','emotion','intensity','speed','repeat') if k in value})
        except Exception as exc:
            llm_failed.set();result.clear()
            errors.append(str(exc));emit('error',message=str(exc))
        finally:
            phrases.put(None);emit('_llm_finished')
    def audio_worker():
        try:
            # Per-profile voice reference when the request carries one; legacy single-character default otherwise.
            ref_audio=getattr(req,'ref_audio_path',None) or str(root/'assets/reference.wav')
            prompt_text=getattr(req,'reference_text',None)
            with httpx.Client(timeout=httpx.Timeout(60, connect=3, read=10, pool=3)) as client:
                sequence=0
                while not cancelled.is_set():
                    try:item=phrases.get(timeout=.1)
                    except queue.Empty:continue
                    if item is None:break
                    index,text=item
                    if not req.voice or llm_failed.is_set():continue
                    if prompt_text is None:prompt_text=json.loads((root/'config.json').read_text())['reference_text']
                    payload={'text':text,'text_lang':'all_ja','ref_audio_path':str(ref_audio),'prompt_lang':'all_ja','prompt_text':prompt_text,'text_split_method':'cut0','batch_size':1,'media_type':'raw','streaming_mode':True,'fragment_interval':.03,'seed':42,'parallel_infer':False,'split_bucket':False}
                    with TTS_LOCK:
                        if cancelled.is_set() or llm_failed.is_set():break
                        emit('tts_start',index=index,text=text)
                        with client.stream('POST',os.getenv('MATE_TTS_URL','http://127.0.0.1:9880')+'/tts',json=payload) as response:
                            response.raise_for_status()
                            pending=b'';received=0
                            for block in response.iter_bytes(chunk_size=1280):
                                if cancelled.is_set() or llm_failed.is_set():return
                                pending+=block
                                n=len(pending)//2*2
                                if not n:continue
                                pcm=pending[:n];pending=pending[n:];received+=len(pcm)
                                metrics.setdefault('first_audio_ms',ms())
                                if getattr(req,'save_audio',True):audio_parts.append(pcm)
                                emit('audio',pcm=base64.b64encode(pcm).decode(),sample_rate=32000,sequence=sequence,phrase=index)
                                sequence+=1
                            if pending:raise ValueError('Odd-length PCM frame')
                            if received<640:raise ValueError('TTS produced no usable PCM')
                    emit('tts_end',index=index)
        except Exception as exc:
            errors.append('TTS: '+str(exc));emit('voice_error',message=str(exc))
        finally:emit('_audio_finished')
    workers=[threading.Thread(target=llm_worker,daemon=True),threading.Thread(target=audio_worker,daemon=True)]
    for worker in workers:worker.start()
    finished=set()
    try:
        yield json.dumps({'type':'start','elapsed_ms':0})+'\n'
        while len(finished)<2 and not cancelled.is_set():
            try:event=events.get(timeout=.25)
            except queue.Empty:
                yield json.dumps({'type':'ping','elapsed_ms':ms()})+'\n'
                continue
            if event['type'].startswith('_'):
                finished.add(event['type']);continue
            if llm_failed.is_set() and event['type'] in ('audio','tts_start','tts_end','action','phrase'):continue
            yield json.dumps(event,ensure_ascii=False)+'\n'
        if cancelled.is_set():return
        audio_url=None
        if audio_parts and getattr(req,'save_audio',True):
            name=uuid.uuid4().hex+'.wav';out=root/'output'/name
            with wave.open(str(out),'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(32000);wav.writeframes(b''.join(audio_parts))
            audio_url='/audio/'+name
            cleanup_audio(root)
        metrics['total_ms']=ms()
        yield json.dumps({'type':'done',**result,'audio_url':audio_url,'voice_error':'; '.join(errors) or None,'timings':metrics,'elapsed_ms':ms()},ensure_ascii=False)+'\n'
    finally:
        cancelled.set()
        # Threads observe cancellation at token/audio boundaries; never block the
        # HTTP disconnect waiting for a CUDA kernel or a model lock.
