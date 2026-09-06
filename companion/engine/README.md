# Companion engine (`companion/engine/`)

Generic FastAPI + WebSocket backend for the native desktop pet. Implements the
shared contract in `companion/logs/collaboration/contract.md`: character
catalog, VRM avatars, motion bank with validated custom clips, streaming
text/audio conversation turns with hard cancellation, and background Codex jobs.

The current 3B Thinker has a known grounding limit: isolated history is supplied correctly,
but indirect recall can fail and absent-history questions can invent user facts from character
profiles. In the v4 GPU probe, direct Korean/Japanese color recall worked, while all three
indirect event-recall questions failed and a fresh-session date/place was fabricated.
`done.ok` means a valid completed reply, not verified factual accuracy. See
`companion/logs/collaboration/astra-gpu-followup.md` for the complete exploratory record.

## Run

```bash
cd Mate-Engine/companion
../../.venv-omni/bin/python -m engine            # 127.0.0.1:8876, provider=omni (lazy GPU load on first turn)
MATE_ENGINE_WARMUP=1 ../../.venv-omni/bin/python -m engine   # load the Thinker at startup instead
MATE_ENGINE_PROVIDER=stub ../../.venv-omni/bin/python -m engine --port 8877   # TEST ONLY: canned replies, no model
```

Requirements: `experiments/omni/requirements-lock.txt` plus `engine/requirements.txt`
(uvicorn, websockets, pytest; the Starlette WebSocket test client also needs `httpx2`).
The GPT-SoVITS service must be running at `MATE_TTS_URL` (default `http://127.0.0.1:9880`)
for voice; without it every turn still delivers text and reports `voice_error`.

| Variable | Default | Meaning |
|---|---|---|
| `MATE_ENGINE_PROVIDER` | `omni` | `omni` (Qwen2.5-Omni-3B Thinker, text + waveform input) or `stub` (tests only) |
| `MATE_ENGINE_WARMUP` | `0` | `1` loads the provider at startup |
| `MATE_TTS_URL` | `http://127.0.0.1:9880` | GPT-SoVITS v2 API (unchanged Uma weights, per-profile reference) |
| `MATE_DEFAULT_CHARACTER` | `cheval-grand` | Character announced in `hello` when present |
| `MATE_CHARACTERS_DIR` | `companion/characters` | Profile directory |
| `MATE_MOTION_BANK` | `Assets/StreamingAssets/cheval-motions.json` | Built-in motion bank |
| `MATE_USER_DATA` | `companion/user-data` | Custom motions are saved under `<user-data>/motions/{id}.json` (git-ignored) |
| `MATE_HISTORY_TURNS` / `MATE_HISTORY_SESSIONS` | `6` / `32` | Bounded memory per (session, character); LRU over sessions |
| `MATE_JOB_ROOT` | unset | Required for jobs: the only directory Codex may work in |
| `MATE_JOB_SANDBOX` | `read-only` | `workspace-write` only when set explicitly; anything else disables jobs |
| `MATE_CODEX_BIN` | `codex` | Codex CLI (may include an interpreter prefix; never a shell) |
| `MATE_JOB_MODEL` | unset | Optional `-m` for codex |
| `MATE_JOB_TIMEOUT` | `1800` | Seconds before a job is terminated and reported `cancelled` (message `timed out`) |

## HTTP

- `GET /health` – provider status, TTS reachability, characters, job configuration.
- `GET /characters` – `{characters:[{id,name,avatar_url,avatar_available,voice_available,motion_style,source,examples}],default}`.
- `GET /characters/{id}` – catalog entry plus the profile's job lines.
- `GET /characters/{id}/avatar` – VRM binary (`model/gltf-binary`), 404 when the asset is not installed.
- `GET /motion-assets` – `{motions:[{name,kind:"vrma",duration,asset_url,sha256,loop?,description?}]}`
  for installed, validated entries in `companion/motion-assets.json` (version 1). Only relative
  `assets/motions/*.vrma` paths contained within that directory are accepted. Missing files,
  unsafe paths, malformed GLB/VRMA containers and SHA-256 mismatches are omitted.
- `GET /motion-assets/{id}` – installed VRMA binary (`model/gltf-binary`), checksum ETag;
  404 when absent or invalid. The URL accepts manifest names, never caller-supplied file paths.
  Installed VRMA names/descriptions join the model gesture choices on the next turn.
  Procedural motion names take precedence on collisions. This does not map greetings to dance;
  the existing wave/nod/idle gestures remain available.
- `GET /motions` – built-in bank plus saved custom clips (`custom: true`).
- `PUT /motions/{id}` – validate and persist a custom clip in bank format; 422 with the concrete reason
  (unknown VRM bone, non-monotonic keys, ends not at zero, |angle| > 90°, > 720°/s, built-in name, bad id).
- `DELETE /motions/{id}` – remove a custom clip.

## WebSocket `/ws`

Server → client on connect: `{type:hello, protocol:1, session, characters:[...], character, capabilities:{audio_input, jobs, text_input, job_workspace, job_sandbox, provider}}`.

Client → server:

| Message | Notes |
|---|---|
| `{type:chat, text, character, turn_id, voice?, session?}` | New turn; cancels the previous turn on this connection (`cancelled`, reason `superseded`). |
| `{type:audio, wav:<base64 WAV>, character, turn_id, voice?, session?}` | Same as chat, waveform input (≤ 30 s, ≤ 16 MB, any rate; resampled to 16 kHz). No ASR. |
| `{type:cancel, turn_id}` | Cancels only the matching active turn; stale ids are ignored. |
| `{type:job, prompt, character, job_id}` | One owned job per connection. |
| `{type:cancel_job, job_id}` | Terminates the owned job (status `cancelled`). |
| `{type:reset, session?, character?}` | Optional extension: clears bounded history. |
| `{type:select_character, character}` | Cancels generation and updates the selection even without a chat. Responds `character_selected`. |
| `{type:playback, turn_id, playing}` | Reports actual PCM playback start/drain. Jobs do not speak over playback. |
| `{type:ping}` | Optional extension: replies `pong`. |

Every turn event carries `turn_id` and `character`: `state(thinking|speaking|idle)`, `start`, `text(text,delta)`,
`phrase(index,text)`, `tts_start`, `audio(pcm base64 s16le mono 32000, sequence, phrase)`, `tts_end`,
`action(gesture,emotion[,intensity,speed,repeat])`, `done(text,gesture,emotion,timings,ok,voice_error)`,
`error(message)`, `voice_error(message)`, `cancelled(reason: superseded|client|disconnect)`.
`done.ok=false` (no `text`) follows an `error`; queued speech is discarded. The client must flush audio on `error`; speech already played before a later generation failure cannot be retracted. A cancelled turn
emits nothing after `cancelled`.

Turn `action` and `done` metadata already includes the selected profile's motion style:
`intensity = clamp((provider intensity or 1) * amplitude, 0, 1.5)` and
`speed = clamp((provider speed or 1) * tempo, 0.5, 2)` (defaults apply only when omitted or invalid).
This also applies to scripted job acknowledgements/results. Clients use these final values
without another profile multiplier. Provider history and explicit motion previews are unchanged.
`motion_style.idle_interval` remains profile metadata; it does not currently control idle scheduling.

Validation failures (unknown character, blank text, bad `turn_id`, unreadable WAV, > 30 s) are `error`
events tagged with the offending `turn_id`.

Job events: `{type:job, job_id, character, status:starting|running|completed|failed|cancelled, message, detail?, workspace, sandbox}`.
`running` messages summarise Codex items (`exit 0: ls`, agent text, edited files); reasoning is never surfaced.
`completed` is only sent after exit status 0 and a `turn.completed` event; otherwise `failed` with the real reason.
The short profile lines `job_ack` / `job_done` / `job_failed` are spoken as separate turns
`job:{job_id}:ack` / `job:{job_id}:result` only when no foreground turn is active and the job's character is
still the selected one. A user turn always supersedes those. Jobs start after the first acknowledgement PCM (or text without voice), with a four-second fallback deadline and visible error. Result speech waits for acknowledgement playback to drain.

Client-supplied session names are scoped to this connection; another connection cannot access that history. History commits at successful generation-and-TTS completion, not during partial model output. Outbound queues are bounded; a slow client closes with code 1013 and must reconnect.

Custom motions are included in each new Omni request's gesture allow-list. A missing voice reference never borrows another character's reference: the legacy reference.wav/config.json fallback applies only to asset-less cheval-grand.

## Providers

`engine/providers/base.py` defines the interface used by `stream_pipeline.conversation_stream`:
`stream_turn(req, cancelled)` yielding `('token',None)`, `('text', growing_text)`, `('result', {...})`.

- `omni.py` – Qwen2.5-Omni-3B Thinker only (generalised from `experiments/omni/omni_audio.py`). Text turns
  and audio turns share one prompt builder (`profiles.build_system_prompt`, in-context examples from the
  profile). History is per (session, character); the newest `history_audio_turns` audio turns are re-fed as
  waveforms, older audio turns become a placeholder, text turns are kept verbatim. One generation at a time
  (lock), cancellation through a stopping criterion, `poisoned` flag if a generation refuses to stop.
- `stub.py` – deterministic canned replies for tests.

## Tests

```bash
cd Mate-Engine/companion
../../.venv-omni/bin/python -m pytest engine/tests -q
```

All tests use fakes: the `stub` provider, a fake GPT-SoVITS client patched into `stream_pipeline`, and
`engine/tests/fake_codex.py` (emits the `codex exec --json` shapes observed with codex-cli 0.153.4).
`test_omni_prompt.py` loads only the real Omni processor on CPU (skipped without the local checkpoint).
