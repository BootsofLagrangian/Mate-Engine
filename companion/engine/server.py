"""FastAPI application: catalog/avatar/motion HTTP endpoints and the /ws conversation socket."""
import asyncio
import base64
import time
import json
import logging
import re
import threading
import uuid
from pathlib import Path
import httpx
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse, Response
from . import COMPANION_ROOT, PROTOCOL_VERSION, config
from .audio import AudioError, decode_wav_base64
from .history import HistoryStore
from .jobs import Job
from .motions import MotionBank, MotionError
from .motion_assets import MotionAssets, available_motions
from .profiles import load_profiles, valid_id
from .providers import create_provider, ScriptedProvider
from .turns import Turn, make_request, is_job_turn
from .fly_brain_service import FullBrainService, BrainUnavailable
from .furniture import validate_catalog
from .intent import validate_interests, validate_furniture_types, validate_locomotion_catalog, WORLD_TTL_SECONDS

log = logging.getLogger('engine.server')
ID_RE = re.compile(r'^[A-Za-z0-9:_.-]{1,128}$')
SESSION_RE = re.compile(r'^[A-Za-z0-9_-]{1,64}$')
MAX_TEXT = 2000
MAX_PROMPT = 8000


def create_app(provider=None, history=None, profiles_dir=None, root=COMPANION_ROOT, motion_bank=None, job_settings=None):
    app = FastAPI(title='Mate companion engine', version='1.0')
    state = app.state
    state.root = Path(root)
    state.history = history or HistoryStore(config.history_turns(), config.history_sessions())
    state.provider_name = provider.name if provider else config.provider_name()
    state.provider = provider or create_provider(state.provider_name, state.history)
    state.profiles_dir = profiles_dir
    state.motions = motion_bank or MotionBank()
    state.motion_assets = MotionAssets(state.root)
    state.job_settings = job_settings  # None -> read env per request (tests pass explicit settings)
    state.connections = set()
    state.fly_brain = FullBrainService(state.root)

    def profiles():
        problems = []
        loaded = load_profiles(state.profiles_dir, state.root, problems=problems)
        for problem in problems:
            log.warning('skipping profile %s', problem)
        return loaded

    def jobs_config():
        return dict(state.job_settings) if state.job_settings is not None else config.job_settings()

    def default_character(loaded):
        wanted = config.default_character()
        if wanted in loaded:
            return wanted
        return next(iter(loaded), None)

    @app.on_event('startup')
    def maybe_warmup():
        if config.env('MATE_ENGINE_WARMUP', '0') == '1':
            threading.Thread(target=_warm, args=(state.provider,), daemon=True, name='provider-warmup').start()

    # ----- HTTP ---------------------------------------------------------------
    @app.get('/health')
    def health():
        try:
            tts = httpx.get(config.tts_url() + '/docs', timeout=1.5).status_code == 200
        except httpx.HTTPError:
            tts = False
        loaded = profiles()
        jobs = jobs_config()
        return {'ok': True, 'protocol': PROTOCOL_VERSION, 'provider': state.provider.status(), 'tts_ready': tts,
                'tts_url': config.tts_url(), 'characters': sorted(loaded), 'default_character': default_character(loaded),
                'jobs': {'available': jobs['available'], 'workspace': jobs['root'], 'sandbox': jobs['sandbox'], 'problems': jobs['problems']},
                'connections': len(state.connections)}

    @app.get('/autonomy/brain')
    def brain_status():
        return state.fly_brain.status()

    @app.post('/autonomy/brain/load')
    def brain_load():
        return state.fly_brain.warmup()

    @app.post('/autonomy/brain/step')
    async def brain_step(body: dict):
        try:
            return await asyncio.to_thread(state.fly_brain.step, body)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except BrainUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc

    @app.get('/characters')
    def characters():
        loaded = profiles()
        return {'characters': [p.catalog_entry() for p in loaded.values()], 'default': default_character(loaded)}

    @app.get('/characters/{character_id}')
    def character(character_id: str):
        loaded = profiles()
        if not valid_id(character_id) or character_id not in loaded:
            raise HTTPException(404, 'Unknown character')
        profile = loaded[character_id]
        return {**profile.catalog_entry(), 'job_lines': {k: profile.job_line(k) for k in ('ack', 'done', 'failed')}}

    @app.get('/characters/{character_id}/avatar')
    def avatar(character_id: str, variant: str | None = None):
        loaded = profiles()
        if not valid_id(character_id) or character_id not in loaded:
            raise HTTPException(404, 'Unknown character')
        path = loaded[character_id].vrm_path(variant)
        if not path or not path.is_file():
            raise HTTPException(404, 'Avatar file is not installed for this character')
        return FileResponse(path, media_type='model/gltf-binary', filename=f'{character_id}.vrm')

    @app.get('/motion-assets')
    def motion_assets():
        return state.motion_assets.catalog()

    @app.get('/motion-assets/{motion_id}')
    def motion_asset(motion_id: str):
        resolved = state.motion_assets.read(motion_id)
        if resolved is None:
            raise HTTPException(404, 'Motion asset is not installed or failed validation')
        entry, data = resolved
        return Response(data, media_type='model/gltf-binary',
                        headers={'ETag': '"' + entry['sha256'] + '"',
                                 'Content-Disposition': f'attachment; filename="{motion_id}.vrma"'})

    @app.get('/motions')
    def motions():
        try:
            return state.motions.bank()
        except (OSError, ValueError) as exc:
            raise HTTPException(500, f'Motion bank unavailable: {exc}') from exc

    @app.put('/motions/{motion_id}')
    async def put_motion(motion_id: str, body: dict):
        try:
            motion = state.motions.save(motion_id, body)
        except MotionError as exc:
            raise HTTPException(422, str(exc)) from exc
        return {'ok': True, 'motion': motion}

    @app.delete('/motions/{motion_id}')
    def delete_motion(motion_id: str):
        try:
            removed = state.motions.delete(motion_id)
        except MotionError as exc:
            raise HTTPException(422, str(exc)) from exc
        if not removed:
            raise HTTPException(404, 'No custom motion with that id')
        return {'ok': True}

    # ----- WebSocket ------------------------------------------------------------
    @app.websocket('/ws')
    async def ws(websocket: WebSocket):
        # This endpoint is native-client only. Loopback binding alone does not
        # stop a web page from opening a socket and invoking local Codex jobs.
        if 'origin' in websocket.headers:
            await websocket.close(code=1008, reason='Browser origins are not allowed')
            return
        await websocket.accept()
        loaded = profiles()
        connection = Connection(app, websocket, loaded, default_character(loaded), jobs_config())
        state.connections.add(connection)
        try:
            await connection.run()
        finally:
            state.connections.discard(connection)

    return app


def _warm(provider):
    try:
        provider.load()
        log.warning('provider %s loaded', provider.name)
    except Exception:
        log.exception('provider warmup failed; first turn will retry')


class Connection:
    def __init__(self, app, websocket, profiles, character, jobs):
        self.app = app
        self.state = app.state
        self.websocket = websocket
        self.profiles = profiles
        self.session = uuid.uuid4().hex[:16]
        self.character = character
        self.jobs = jobs
        self.loop = asyncio.get_running_loop()
        self.outbound = asyncio.Queue(maxsize=256)
        self.playing = None
        self.playback_until = 0.0
        self.tasks = set()
        self.pending_callbacks = threading.BoundedSemaphore(256)
        self.overloaded = threading.Event()
        self.turn = None
        self.job = None
        self.closed = False
        self.world_interests = ()
        self.furniture_types = ()
        self.furniture_catalog = ()
        self.locomotion_catalog = ()
        self.appearance_supported = False
        self.active_variant_id = "default"
        self.issued_intents = {}
        self.execution_feedback = []
        self.world_revision = 0
        self.world_updated = None

    # thread-safe: called from turn/job worker threads
    def emit(self, event):
        if self.closed or self.overloaded.is_set():
            return
        if event.get('turn_id'):
            event = {**event, '_turn_event': True}
        if not self.pending_callbacks.acquire(blocking=False):
            self.overloaded.set()
            self.loop.call_soon_threadsafe(self._slow_client)
            return
        def enqueue():
            self.pending_callbacks.release()
            if self.closed:
                return
            if self.outbound.full():
                self._slow_client()
            else:
                self.outbound.put_nowait(event)
        try:
            self.loop.call_soon_threadsafe(enqueue)
        except RuntimeError:
            self.pending_callbacks.release()

    def _slow_client(self):
        if not self.closed:
            self.closed = True
            if self.turn:
                self.turn.cancel('slow_client')
            self._task(self.websocket.close(code=1013, reason='client too slow'))

    async def send(self, event):
        if not self.closed:
            await self.outbound.put(event)

    def _task(self, coroutine):
        task = asyncio.create_task(coroutine)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return task

    def hello(self):
        return {'type': 'hello', 'protocol': PROTOCOL_VERSION, 'session': self.session,
                'characters': [p.catalog_entry() for p in self.profiles.values()], 'character': self.character,
                'capabilities': {'audio_input': True, 'jobs': bool(self.jobs['available']), 'text_input': True,
                                 'job_workspace': self.jobs['root'], 'job_sandbox': self.jobs['sandbox'],
                                 'provider': self.state.provider.name, 'world_context': True}}

    async def run(self):
        await self.send(self.hello())
        sender = asyncio.create_task(self._sender())
        try:
            while True:
                try:
                    raw = await self.websocket.receive_text()
                except WebSocketDisconnect:
                    break
                try:
                    message = json.loads(raw)
                except ValueError:
                    await self.send({'type': 'error', 'message': 'invalid JSON'})
                    continue
                if not isinstance(message, dict):
                    await self.send({'type': 'error', 'message': 'message must be an object'})
                    continue
                await self.handle(message)
        finally:
            self.closed = True
            if self.turn:
                self.turn.cancel('disconnect')
            if self.job:
                self.job.cancel()
            for task in self.tasks:
                task.cancel()
            sender.cancel()
            try:
                await asyncio.wait_for(sender, timeout=2)
            except (asyncio.TimeoutError, asyncio.CancelledError, Exception):
                sender.cancel()

    async def _sender(self):
        while True:
            event = await self.outbound.get()
            if event is None:
                return
            if event.pop('_turn_event', False) and event.get('type') != 'cancelled':
                if not self.turn or event['turn_id'] != self.turn.turn_id or self.turn.outcome == 'cancelled':
                    continue
                issued = self.issued_intents.get(event['turn_id'] + ':intent')
                if event.get('type') == 'done' and event.get('ok') and issued and issued['character'] == self.character:
                    # Historical metadata for the action already delivered to this
                    # native connection. Its execution may itself change the world
                    # revision before TTS finishes. Never grant a new stale action.
                    event['intent'] = dict(issued['intent'])
                    event['intent_replay'] = True
                elif 'intent' in event and not self.turn.req.world_context_valid():
                    event.pop('intent', None)
            if event.get('type') in ('action', 'done') and 'intent' in event:
                intent_id = event['turn_id'] + ':intent'
                if intent_id not in self.issued_intents:
                    self.issued_intents[intent_id] = {'character': self.character, 'at': time.monotonic(), 'intent': event['intent']}
                    if len(self.issued_intents) > 16:
                        self.issued_intents.pop(next(iter(self.issued_intents)))
            if event.get('type') == 'audio':
                seconds = len(base64.b64decode(event['pcm'])) / (2 * event.get('sample_rate', 32000))
                self.playback_until = max(time.monotonic(), self.playback_until) + seconds
            try:
                await self.websocket.send_text(json.dumps(event, ensure_ascii=False))
            except Exception:  # socket gone; the receive loop notices the disconnect
                return

    async def handle(self, message):
        kind = message.get('type')
        handler = {'chat': self.on_chat, 'audio': self.on_audio, 'cancel': self.on_cancel, 'job': self.on_job,
                   'cancel_job': self.on_cancel_job, 'playback': self.on_playback, 'select_character': self.on_select_character, 'reset': self.on_reset, 'ping': self.on_ping, 'world_context': self.on_world_context, 'intent_result': self.on_intent_result}.get(kind)
        if handler is None:
            await self.send({'type': 'error', 'message': f'unknown message type: {kind!r}'})
            return
        await handler(message)

    # ----- validation helpers -------------------------------------------------
    def _turn_error(self, turn_id, character, message):
        return {'type': 'error', 'message': message, 'turn_id': turn_id, 'character': character}

    def _profile(self, message):
        character = message.get('character') or self.character
        if not valid_id(character) or character not in self.profiles:
            self.profiles = load_profiles(self.state.profiles_dir, self.state.root)  # profile may have been added
        if not valid_id(character) or character not in self.profiles:
            return None, character
        return self.profiles[character], character

    def _session_for(self, message):
        session = message.get('session')
        if session is None:
            return self.session
        if not isinstance(session, str) or not SESSION_RE.fullmatch(session):
            return None
        return self.session + ':' + session

    @staticmethod
    def _valid_id(value):
        return isinstance(value, str) and bool(ID_RE.fullmatch(value))

    # ----- turns --------------------------------------------------------------
    def _clear_world(self):
        self.world_interests = ()
        self.furniture_types = ()
        self.furniture_catalog = ()
        self.locomotion_catalog = ()
        self.appearance_supported = False
        self.active_variant_id = "default"
        self.issued_intents = {}
        self.execution_feedback = []
        self.world_updated = None
        self.world_revision += 1

    def _select(self, character):
        if character != self.character:
            self._clear_world()
        self.character = character

    async def on_world_context(self, message):
        if message.get('character_id') != self.character:
            await self.send({'type': 'error', 'message': 'world_context character_id must match selected character'})
            return
        try:
            if type(message.get('furniture_schema_version', 1)) is not int or message.get('furniture_schema_version', 1) != 1:
                raise ValueError('unsupported furniture schema version')
            furniture_types = validate_furniture_types(message.get('furniture_types', []))
            furniture_catalog = validate_catalog(message.get('furniture_catalog', []))
            locomotion_catalog = validate_locomotion_catalog(message.get('locomotion_catalog', []))
            appearance_supported = message.get('appearance_supported', False)
            if type(appearance_supported) is not bool:
                raise ValueError('appearance_supported must be boolean')
            active_variant_id = message.get('active_variant_id', 'default')
            available_variants = {v['id'] for v in self.profiles[self.character].avatar_variant_catalog() if v['avatar_available']}
            if not isinstance(active_variant_id, str) or (appearance_supported and active_variant_id not in available_variants) or (not appearance_supported and active_variant_id != 'default'):
                raise ValueError('active_variant_id must identify an installed variant with native appearance support')
            interests = validate_interests(message.get('interests'), {e['id'] for e in furniture_catalog} or set(furniture_types))
        except ValueError as exc:
            await self.send({'type': 'error', 'message': str(exc)})
            return
        if interests != self.world_interests or furniture_types != self.furniture_types or furniture_catalog != self.furniture_catalog or locomotion_catalog != self.locomotion_catalog or appearance_supported != self.appearance_supported or active_variant_id != self.active_variant_id or self.world_updated is None or time.monotonic() - self.world_updated > WORLD_TTL_SECONDS:
            self.world_revision += 1
        self.world_interests = interests
        self.furniture_types = furniture_types
        self.furniture_catalog = furniture_catalog
        self.locomotion_catalog = locomotion_catalog
        self.appearance_supported = appearance_supported
        self.active_variant_id = active_variant_id
        self.world_updated = time.monotonic()
        await self.send({'type': 'world_context', 'character_id': self.character,
                         'revision': self.world_revision, 'accepted': len(interests), 'furniture_types': list(furniture_types),
                         'furniture_catalog': [{'id': entry['id'], 'verbs': list(entry['verbs'])} for entry in furniture_catalog]})

    async def on_intent_result(self, message):
        intent_id, outcome = message.get('intent_id'), message.get('outcome')
        issued = self.issued_intents.get(intent_id) if isinstance(intent_id, str) else None
        reason = message.get('reason', '')
        if (set(message) - {'type', 'character_id', 'intent_id', 'outcome', 'reason'}
                or message.get('character_id') != self.character or issued is None
                or issued['character'] != self.character or time.monotonic() - issued['at'] > 120
                or outcome not in ('completed', 'arrived', 'rejected', 'failed', 'cancelled', 'expired', 'interrupted')
                or not isinstance(reason, str) or len(reason) > 64 or any(c not in 'abcdefghijklmnopqrstuvwxyz_' for c in reason)):
            await self.send({'type': 'error', 'message': 'invalid or unissued intent result'})
            return
        if not issued.get('reported'):
            issued['reported'] = True
            self.execution_feedback.append({'intent_id': intent_id, 'intent': issued['intent'], 'outcome': outcome, 'reason': reason})
            self.execution_feedback = self.execution_feedback[-8:]
        await self.send({'type': 'intent_result', 'intent_id': intent_id, 'accepted': True})

    def foreground_active(self):
        return self.turn is not None and self.turn.foreground and not self.turn.finished.is_set() and not self.turn.cancelled.is_set()

    def _start_turn(self, req, provider):
        if self.turn and not self.turn.finished.is_set():
            self.turn.cancel('superseded')
        self.playing = None
        self.playback_until = 0.0
        motions = available_motions(self.state.motions, self.state.motion_assets)
        req.gestures = tuple(m['name'] for m in motions)
        req.execution_feedback = tuple(self.execution_feedback)
        req.motion_descriptions = {m['name']: m['description'] for m in motions if m.get('description')}
        revision = self.world_revision
        req.world_context_valid = lambda: (not self.closed and self.character == req.character
            and self.world_revision == revision and self.world_updated is not None
            and time.monotonic() - self.world_updated <= WORLD_TTL_SECONDS)
        if req.world_context_valid() and not is_job_turn(req.turn_id):
            req.world_interests = self.world_interests
            req.furniture_types = self.furniture_types
            req.furniture_catalog = self.furniture_catalog
            req.locomotion_catalog = self.locomotion_catalog
            if self.appearance_supported:
                req.active_variant_id = self.active_variant_id
                req.appearance_variants = tuple({key: entry[key] for key in ('id', 'label', 'description', 'mood_tags')}
                    for entry in req.profile.avatar_variant_catalog() if entry['avatar_available'])
        else:
            req.world_context_valid = lambda: False
        self.turn = Turn(req, provider, self.emit, self.state.root)
        self.turn.start()
        return self.turn

    async def on_chat(self, message):
        turn_id = message.get('turn_id')
        profile, character = self._profile(message)
        if not self._valid_id(turn_id) or is_job_turn(turn_id):
            await self.send(self._turn_error(turn_id if isinstance(turn_id, str) else None, character, 'chat requires a valid turn_id'))
            return
        if profile is None:
            await self.send(self._turn_error(turn_id, character, f'unknown character: {character!r}'))
            return
        text = message.get('text')
        if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT:
            await self.send(self._turn_error(turn_id, character, 'text must be 1-2000 non-blank characters'))
            return
        session = self._session_for(message)
        if session is None:
            await self.send(self._turn_error(turn_id, character, 'invalid session id'))
            return
        self._select(character)
        req = make_request(turn_id=turn_id, character=character, profile=profile, session=session,
                           voice=bool(message.get('voice', True)), text=text.strip())
        self._start_turn(req, self.state.provider)

    async def on_audio(self, message):
        turn_id = message.get('turn_id')
        profile, character = self._profile(message)
        if not self._valid_id(turn_id) or is_job_turn(turn_id):
            await self.send(self._turn_error(turn_id if isinstance(turn_id, str) else None, character, 'audio requires a valid turn_id'))
            return
        if profile is None:
            await self.send(self._turn_error(turn_id, character, f'unknown character: {character!r}'))
            return
        session = self._session_for(message)
        if session is None:
            await self.send(self._turn_error(turn_id, character, 'invalid session id'))
            return
        try:
            audio, seconds = await asyncio.to_thread(decode_wav_base64, message.get('wav'))
        except AudioError as exc:
            await self.send(self._turn_error(turn_id, character, str(exc)))
            return
        self._select(character)
        req = make_request(turn_id=turn_id, character=character, profile=profile, session=session,
                           voice=bool(message.get('voice', True)), audio=audio, audio_seconds=seconds)
        self._start_turn(req, self.state.provider)

    async def on_cancel(self, message):
        turn_id = message.get('turn_id')
        if self.turn and self.turn.turn_id == turn_id:
            self.turn.cancel('client')
        # Stale or unknown turn ids are ignored: the referenced turn already ended.

    async def on_playback(self, message):
        if self.turn and message.get('turn_id') == self.turn.turn_id:
            self.playing = self.turn.turn_id if message.get('playing') is True else None
            if message.get('playing') is False:
                self.playback_until = 0.0

    async def on_select_character(self, message):
        profile, character = self._profile(message)
        if profile is None:
            await self.send({'type': 'error', 'message': 'unknown character'})
            return
        if self.turn:
            self.turn.cancel('character_changed')
        self._clear_world()
        self._select(character)
        self.playing = None
        self.playback_until = 0.0
        await self.send({'type': 'character_selected', 'character': character})

    def playback_active(self):
        return self.playing is not None or time.monotonic() < self.playback_until

    async def on_reset(self, message):
        self._clear_world()
        session = self._session_for(message) or self.session
        character = message.get('character')
        if self.turn and self.turn.req.session == session and (not character or self.turn.character == character):
            self.turn.cancel('reset')
        self.state.history.reset(session, character if valid_id(character or '') else None)
        await self.send({'type': 'reset', 'ok': True, 'session': session, 'character': character})

    async def on_ping(self, message):
        await self.send({'type': 'pong'})

    # ----- jobs ---------------------------------------------------------------
    def _job_event(self, job_id, character, status, message):
        return {'type': 'job', 'job_id': job_id, 'character': character, 'status': status, 'message': message,
                'workspace': self.jobs['root'], 'sandbox': self.jobs['sandbox']}

    async def on_job(self, message):
        job_id = message.get('job_id')
        profile, character = self._profile(message)
        if not self._valid_id(job_id):
            await self.send(self._job_event(job_id if isinstance(job_id, str) else None, character, 'failed', 'job requires a valid job_id'))
            return
        prompt = message.get('prompt')
        if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > MAX_PROMPT:
            await self.send(self._job_event(job_id, character, 'failed', 'prompt must be 1-8000 non-blank characters'))
            return
        if profile is None:
            await self.send(self._job_event(job_id, character, 'failed', f'unknown character: {character!r}'))
            return
        if not self.jobs['available']:
            await self.send(self._job_event(job_id, character, 'failed', '; '.join(self.jobs['problems'])))
            return
        if self.job and self.job.status not in ('completed', 'failed', 'cancelled'):
            await self.send(self._job_event(job_id, character, 'failed', f'another job is still running: {self.job.job_id}'))
            return
        self.job = Job(job_id, prompt.strip(), character, self.jobs, self.emit,
                       on_finish=lambda job: self.loop.call_soon_threadsafe(self._job_finished, job))
        self.job.status = 'starting'
        ack = self._speak_job_line(profile, character, job_id, 'ack')
        self._task(self._launch_job(self.job, ack))

    async def _launch_job(self, job, ack):
        deadline = time.monotonic() + 4
        while ack and not ack.ready.is_set() and not ack.finished.is_set() and not ack.cancelled.is_set():
            if job.cancel_requested.is_set() or time.monotonic() >= deadline:
                break
            await asyncio.sleep(.02)
        if ack and not ack.ready.is_set() and not ack.cancelled.is_set():
            await self.send(self._turn_error(ack.turn_id, ack.character, 'Acknowledgement audio unavailable; starting job'))
            ack.cancel('ack_unavailable')
        if not self.closed:
            job.start()

    async def on_cancel_job(self, message):
        job_id = message.get('job_id')
        if self.job and self.job.job_id == job_id:
            self.job.cancel()

    def _job_finished(self, job):
        if self.closed or job is not self.job:
            return
        kind = {'completed': 'done', 'failed': 'failed'}.get(job.status)
        if kind:
            self._task(self._job_result(job, kind))

    async def _job_result(self, job, kind):
        if self.foreground_active() or (self.turn and self.turn.foreground and self.playback_active()):
            return
        # A fast job must not supersede its still-speaking acknowledgement.
        deadline = time.monotonic() + 30
        while self.turn and (not self.turn.finished.is_set() or self.playback_active()):
            if self.foreground_active() or self.turn.foreground or time.monotonic() > deadline:
                return
            await asyncio.sleep(.05)
        if not self.closed and job is self.job:
            self._speak_job_line(self.profiles.get(job.character), job.character, job.job_id, kind)

    def _speak_job_line(self, profile, character, job_id, kind):
        """Short spoken line only when the user is not mid-conversation and the character is still selected."""
        if profile is None or character != self.character or self.foreground_active() or self.playback_active():
            return
        line = profile.job_line(kind)
        if not line:
            return
        suffix = 'ack' if kind == 'ack' else 'result'
        req = make_request(turn_id=f'job:{job_id}:{suffix}', character=character, profile=profile, session=self.session, text=line)
        gesture = {'ack': 'nod', 'done': 'bow', 'failed': 'shake_head'}[kind]
        emotion = {'ack': 'neutral', 'done': 'happy', 'failed': 'sad'}[kind]
        return self._start_turn(req, ScriptedProvider(line, emotion=emotion, gesture=gesture))


app = create_app()
