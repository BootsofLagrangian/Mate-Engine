"""Local Cheval Grand conversation service. No microphone capture until requested."""
from __future__ import annotations
import io, json, logging, os, re, threading, time, uuid
from pathlib import Path
import httpx
import numpy as np
import soundfile as sf
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / 'output'
OUTPUT.mkdir(exist_ok=True)
EMOTIONS = {'neutral', 'happy', 'sad', 'relaxed', 'surprised'}
GESTURES = {'idle', 'nod', 'shake_head', 'shy', 'wave', 'think', 'bow', 'stretch'}
from persona import SYSTEM, EXAMPLES, PROFILE
from stream_pipeline import conversation_stream, TTS_LOCK, partial_text, CancelStreamingResponse, cleanup_audio


class ChatRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    session: str = Field(default='default', pattern=r'^[a-zA-Z0-9_-]{1,64}$')
    voice: bool = True

class Brain:
    def __init__(self):
        self.model = self.tokenizer = self.whisper = None
        self.lock = threading.Lock()
        self.stt_lock = threading.Lock()
        self.history = {}
        self.model_id = os.getenv('MATE_LLM_MODEL', 'Qwen/Qwen2.5-1.5B-Instruct')
        self.device = os.getenv('MATE_DEVICE', 'cpu')

    def load(self):
        if self.model is not None:
            return
        from llama_cpp import Llama, llama_supports_gpu_offload
        if self.device == 'cuda' and not llama_supports_gpu_offload():
            raise RuntimeError('llama.cpp was built without CUDA; run companion/install.sh')
        self.model = Llama(model_path=os.getenv('MATE_GGUF', str(ROOT/'models/qwen2.5-1.5b-instruct-q4_k_m.gguf')), n_ctx=8192, n_threads=int(os.getenv('MATE_THREADS','8')), n_gpu_layers=int(os.getenv('MATE_GPU_LAYERS','0')), chat_format='chatml', flash_attn=self.device=='cuda', verbose=False)

    def stream_reply(self, text, session, cancelled=None):
        with self.lock:
            self.load()
            if cancelled is not None and cancelled.is_set(): return
            history = self.history.get(session, [])
            user_content='【人間のトレーナーから、あなた（シュヴァルグラン）への発言】\n'+text+'\n【シュヴァルとして日本語で返事】'
            requested=explicit_motion(text)
            motion_meaning={'stretch':'体を伸ばすストレッチを一緒にする','wave':'相手に手を振る','nod':'うなずく','shake_head':'首を横に振る','bow':'お辞儀をする'}
            if requested:user_content+='\n動作要求の意味: '+motion_meaning[requested]+'。この動作に合う返事をする。'
            messages = [{'role':'system','content':SYSTEM}] + history + [{'role':'user','content':user_content}]
            while history and len(self.model.tokenize(json.dumps(messages,ensure_ascii=False).encode())) > 6500:
                history=history[2:]
                messages=[{'role':'system','content':SYSTEM}] + history + [{'role':'user','content':user_content}]
            schema={'type':'object','properties':{'text':{'type':'string','minLength':1,'maxLength':100,'pattern':'^[　-ヿ㐀-䶿一-鿿！-｠ 0-9!?…—]{1,100}$'},'emotion':{'type':'string','enum':sorted(EMOTIONS)},'gesture':{'type':'string','enum':sorted(GESTURES)}},'required':['text','emotion','gesture'],'additionalProperties':False}
            stream=self.model.create_chat_completion(messages=messages,max_tokens=384,temperature=.45,top_p=.85,repeat_penalty=1.06,stream=True,response_format={'type':'json_object','schema':schema})
            raw=''; previous=''; first=True
            try:
                for item in stream:
                    if cancelled is not None and cancelled.is_set():return
                    token=item['choices'][0].get('delta',{}).get('content','')
                    if token and first:
                        yield 'token', None
                        first=False
                    raw+=token
                    spoken=partial_text(raw)
                    if spoken!=previous:
                        yield 'text',spoken
                        previous=spoken
                    # Some small-model completions repeat JSON after the first
                    # object. Finish as soon as the one requested object closes.
                    try:
                        obj,end=json.JSONDecoder().raw_decode(raw.lstrip())
                        if isinstance(obj,dict) and all(k in obj for k in ('text','emotion','gesture')):
                            raw=raw.lstrip()[:end]
                            break
                    except ValueError:pass
            finally:
                stream.close()
            parsed=parse_reply(raw)
            requested=explicit_motion(text)
            if requested:parsed['gesture']=requested
            if session not in self.history and len(self.history)>=32:self.history.pop(next(iter(self.history)))
            self.history[session]=(history+[{'role':'user','content':user_content},{'role':'assistant','content':json.dumps(parsed,ensure_ascii=False)}])[-12:]
            yield 'result',parsed

    def reply(self,text,session):
        result=None
        for kind,value in self.stream_reply(text,session):
            if kind=='result':result=value
        if result is None:raise ValueError('LLM produced no response')
        return result

    def transcribe(self, data):
        with self.stt_lock:
            from faster_whisper import WhisperModel
            if self.whisper is None:
                self.whisper = WhisperModel(os.getenv('MATE_STT_MODEL','small'), device=os.getenv('MATE_STT_DEVICE','cpu'), compute_type='float16' if os.getenv('MATE_STT_DEVICE','cpu')=='cuda' else 'int8', cpu_threads=4)
            segments, info = self.whisper.transcribe(io.BytesIO(data), beam_size=3, vad_filter=True)
            return {'text': ''.join(s.text for s in segments).strip(), 'language':info.language}

def explicit_motion(text):
    """Honor unambiguous direct motion requests; spontaneous actions stay model-led."""
    if re.search(r"하지\s*마|하지\s*말|하지\s*않|しない|やめ|don't|do not", text, re.I):
        return None
    for pattern, motion in [
        (r'기지개|伸びを|ストレッチ', 'stretch'),
        (r'손.{0,6}흔들|手を振', 'wave'),
        (r'끄덕|うなず|頷', 'nod'),
        (r'고개.{0,5}저어|首を横に', 'shake_head'),
        (r'허리.{0,5}숙|お辞儀', 'bow'),
    ]:
        if re.search(pattern, text):
            return motion
    return None


def parse_reply(raw):
    raw = re.sub(r'<think>.*?</think>', '', raw, flags=re.S).strip()
    match = re.search(r'\{.*\}', raw, re.S)
    try:
        obj = json.loads(match.group() if match else raw)
        text = obj['text']
        if not isinstance(text, str) or not text.strip():
            raise ValueError('Missing spoken text')
    except (ValueError, KeyError, TypeError):
        # Never speak malformed tool/JSON output as dialogue.
        raise ValueError('LLM returned invalid dialogue; please retry')
    return {'text':text.strip()[:500], 'emotion':obj.get('emotion') if obj.get('emotion') in EMOTIONS else 'neutral', 'gesture':obj.get('gesture') if obj.get('gesture') in GESTURES else 'idle'}

brain = Brain()
app = FastAPI(title='Cheval Grand Companion')

def synthesize(text):
    config = json.loads((ROOT/'config.json').read_text())
    payload = {'text':text, 'text_lang':'all_ja', 'ref_audio_path':str(ROOT/'assets/reference.wav'), 'prompt_lang':'all_ja', 'prompt_text':config['reference_text'], 'text_split_method':'cut5', 'batch_size':1, 'media_type':'wav', 'streaming_mode':False, 'seed':42, 'parallel_infer':False}
    with TTS_LOCK:
        response = httpx.post(os.getenv('MATE_TTS_URL','http://127.0.0.1:9880')+'/tts', json=payload, timeout=180)
    response.raise_for_status()
    data, rate = sf.read(io.BytesIO(response.content))
    if len(data) < rate//10 or not np.isfinite(data).all():
        raise ValueError('TTS returned invalid audio')
    name = uuid.uuid4().hex+'.wav'
    (OUTPUT/name).write_bytes(response.content)
    cleanup_audio(ROOT)
    return '/audio/'+name

@app.on_event('startup')
def start_warmup():
    if os.getenv('MATE_WARMUP','0')!='1':return
    def warm():
        try:
            brain.reply('こんにちは。','startup-warmup')
            brain.history.pop('startup-warmup',None)
            for _ in range(120):
                try:
                    if httpx.get(os.getenv('MATE_TTS_URL','http://127.0.0.1:9880')+'/docs',timeout=2).is_success:break
                except httpx.HTTPError:pass
                time.sleep(.5)
            synthesize('トレーナーさん。')
            app.state.warmed=True
            logging.warning('Companion model/reference warmup complete')
        except Exception:
            logging.exception('Warmup failed; interactive requests may retry')
    app.state.warmed=False
    threading.Thread(target=warm,daemon=True).start()

@app.get('/health')
def health():
    try:
        r = httpx.get(os.getenv('MATE_TTS_URL','http://127.0.0.1:9880')+'/docs', timeout=2)
        tts = r.status_code == 200
    except httpx.HTTPError:
        tts = False
    return {'warmed':getattr(app.state,'warmed',False),'llm':brain.model_id, 'llm_loaded':brain.model is not None, 'device':brain.device, 'llm_gpu_layers':int(os.getenv('MATE_GPU_LAYERS','0')), 'tts_device':os.getenv('MATE_TTS_DEVICE','cpu'), 'stt_device':os.getenv('MATE_STT_DEVICE','cpu'), 'tts_ready':tts, 'stt_loaded':brain.whisper is not None, 'vrm_ready':(ROOT/'assets/cheval-grand.vrm').is_file()}

@app.post('/chat')
def chat(req: ChatRequest):
    if not req.text.strip():
        raise HTTPException(422, 'Empty message')
    start = time.monotonic()
    try:
        result = brain.reply(req.text.strip(), req.session)
    except Exception as exc:
        logging.exception('LLM failed')
        raise HTTPException(503, str(exc)) from exc
    result.update(audio_url=None, voice_error=None)
    if req.voice:
        try:
            result['audio_url'] = synthesize(result['text'])
        except Exception as exc:
            logging.exception('TTS failed')
            result['voice_error'] = str(exc)
    result['elapsed_seconds'] = round(time.monotonic()-start, 2)
    return result

@app.post('/chat/stream')
def chat_stream(req: ChatRequest):
    if not req.text.strip():raise HTTPException(422,'Empty message')
    cancel=threading.Event()
    return CancelStreamingResponse(conversation_stream(brain,req,ROOT,cancel),cancel=cancel,media_type='application/x-ndjson',headers={'Cache-Control':'no-cache','X-Accel-Buffering':'no'})

@app.get('/character')
def character():
    return {'id':PROFILE['id'],'name':PROFILE['name'],'source':PROFILE['source'],'examples':len(PROFILE['examples'])}

@app.post('/stt')
def stt(audio: UploadFile = File(...)):
    data = audio.file.read(16*1024*1024+1)
    if len(data)>16*1024*1024:
        raise HTTPException(413, 'Audio is limited to 16 MB')
    try:
        decoded, rate = sf.read(io.BytesIO(data))
        if len(decoded)/rate>30:
            raise HTTPException(413, 'Recording is limited to 30 seconds')
        return brain.transcribe(data)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(422, str(exc)) from exc

@app.post('/sessions/{session}/reset')
def reset(session: str):
    with brain.lock:
        brain.history.pop(session, None)
    return {'ok':True}

@app.get('/motions')
def motions():
    return FileResponse(ROOT.parent/'Assets/StreamingAssets/cheval-motions.json', media_type='application/json')

@app.get('/avatar')
def avatar():
    return FileResponse(ROOT/'assets/cheval-grand.vrm', media_type='model/gltf-binary')

app.mount('/audio', StaticFiles(directory=OUTPUT), name='audio')
if (ROOT/'web/dist').exists():
    app.mount('/', StaticFiles(directory=ROOT/'web/dist', html=True), name='web')
