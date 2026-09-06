# Validation record — 2026-09-06

The newer local-behavior and stepped-turn milestone is recorded in
[Windows stepped-motion acceptance](diagnostics/liveliness/windows-stepped-baseline/README.md):
40 continuous Windows checks, 12 normal-processing voice-to-movement checks and
17 window-top/floor checks pass on the identified exported executable. The
[three-rig turn matrix](diagnostics/liveliness/README.md) passes 240 checks;
the native selftest passes 504, host lifecycle 34, heading callbacks 7 and fake
protocol 59. Backend intent changes pass 111 tests, with real-model limitations
retained in [intent validation](diagnostics/behavior/INTENT-VALIDATION.md).

These records cover deterministic idle scheduling, user markers, occasional model
intents, distance-driven gait, stepped turning and interruption ownership. They
precede the subsequent search/integration of additional authored Uma motion assets.
The remaining sections preserve the **earlier native baseline** and its original
artifact identities; their executable hash is not the newer stepped-motion build.

This is a development acceptance record, not a general reliability benchmark.
The earlier browser/Unity-adapter record is preserved in [VALIDATION-LEGACY.md](VALIDATION-LEGACY.md).
Both the Windows editor host and the exported Windows executable passed the voice
and world checks below. Export acceptance uses the final embedded-PCK executable,
with diagnostic scripts supplied externally; the runtime project and Windows geometry
helper are loaded from the package.

## Verified components

| Check | Evidence and scope |
| --- | --- |
| Native voice and input | 30 actual Windows checks pass: three voices, driver microphone frames, waveform-input reply, PCM draining, cancellation and lip envelope; no dropped PCM frames and one uninterrupted playback interval per full test reply |
| Native desktop interaction | 17 actual Windows checks pass with a dedicated visible test window and actual workarea floor: foot contact, scale preserving height, 248 px lateral movement, about 82° facing, panel pause, seat contact, seated talking closed-support release and floor walking |
| Generic backend | 86 tests pass: profiles, isolated history, cancellation, streaming errors, work jobs, motion storage/catalog, browser-Origin rejection |
| Real GPU conversation | RTX 4090, Qwen2.5-Omni 3B Thinker on CUDA BF16, dedicated original Uma GPT-SoVITS v2 on CUDA FP16; no Omni speech decoder |
| Current exploratory prompt variant | 16/16 valid completed dialogue JSON; raw Korean tea-request fixture on topic for all three profiles |
| First received PCM | Nine voiced requests: median 871 ms, range 502–1645 ms; excludes recording, model startup and physical speaker onset |
| Real Codex work | Selected Eishin, acknowledgement PCM at 984.5 ms, job-start marker at 1002 ms, verified exact smoke-file content at 15.25 s, result PCM at 15.60 s |
| VRMA conversion | Eight CC0 Quaternius Standard clips; independent comparison found all 416 mapped channels, 21,632 quaternion samples and timestamps byte-identical to source |
| VRMA/IK | All 24 clip/character combinations tested; three rigs pass contact, scale, seated-gesture and hand-reach regressions |
| Actual-rig floor projection | 135 checks pass over all three rigs, three scales and three yaws; measured mesh sole and orthographic bounds agree, floor support persists and workarea safety is retained |
| Desktop movement modules | 3,636 free-roam and 769 surface checks; moving/closed windows, monitor changes, resize and stale targets included |
| Windows geometry source | Actual dedicated test window moved/minimized; persistent snapshots, owner exclusion and child cleanup pass; normalized workareas exactly match Windows Godot DisplayServer |
| Mouth rendering | All three characters rendered on actual Windows RTX 4090, including idle and phoneme weights; screen-outline depth fix removes Cheval's protruding inner-mouth triangles while preserving outlines |
| Idle head movement | Actual Windows 20-second rendered Cheval idle: 1,201 samples, 200 screenshots, approximately 60 fps; separate fixed-step baseline/fix ablation is in diagnostics/head_motion |

The Codex test used emulated playback acknowledgements over WebSocket; its timing
does not establish physical speaker onset. The Korean audio fixture is synthetic
input from `facebook/mms-tts-kor`, seed 42, asking for warm tea instead of coffee.
The fixture enters the Thinker as waveform, with no transcript or ASR in that path.
Character output always uses the supplied dedicated Uma voice weights and the
selected official reference sample. No replacement output voice was trained.

## Known limits

The current 3B model still fails indirect conversation recall: all three exam-event
recall checks failed in the final exploratory variant. A fresh-session question
also elicited an invented date/place from the character profile. Two direct
bicycle-color recall checks and one relocation recall succeeded. These mixed
results do **not** establish reliable memory or consistent character nuance.

Prompt variants were selected after observing results; all attempts were retained
locally. Structured-output success is distinct from semantic accuracy. The code
isolates and passes actual session history; a model can still fail to use it.

Microphone utterances are submitted after PTT release or VAD endpoint. Response
text and TTS PCM stream incrementally; continuous partial-audio understanding and
acoustic echo cancellation are not implemented. A stalled TTS read can retain the
serialization lock until its ten-second read timeout.

Desktop surfaces currently mean horizontal visible window-top segments, authored
lines and the monitor work-area floor. There is no general jumping/path planner,
wall-climbing, screen-content recognition or full foot/cloth physics. Explicit
hand-target leaning is an API; automatic wall attachment remains future work.
Magnifier/laptop props are planned in DESKTOP-WORLD.md, not delivered props.

## Reproducible evidence

Tracked probes and component records are in `diagnostics/`, `native/tools/` and
`engine/tests/`. Raw audio, character assets, rendered images and complete GPU
event logs stay local under ignored `assets/` and `logs/`.

Independent reviews approved backend/supervisor/build source, desktop geometry
modules, converter and motion contact implementation after fixes. Root separately
reviewed and reran the five Origin regression tests because the backend reviewer
authored that fix. Root independently reviewed the host corrections, reran 25 actual-handler checks,
and verified 30 voice/input and 17 world checks on Windows. Fable's full suite passed
407 checks and its isolated fake-provider protocol probe passed 59. The final Windows package separately passes the same 30 voice/input and 17 world
checks; these are not inferred from headless or editor results.

The first desktop fixture was occluded by another window: attachment correctly did not
select it. A subsequent owned topmost fixture made the tested edge visible and passed.
The native world source continues to account for occlusion. Small probe-only compile
errors were corrected before acceptance; they did not change runtime functionality.


## Windows package acceptance

The final `native/build/MateCompanion.exe` is 96,784,544 bytes, SHA-256
`fc8233c069ed590b86c964736b5dc2cbe48ff873c1068ad5018a3a85f898da9a`.
Its manifest records pinned Godot/plugin revisions and patch hashes. Assets and
models remain installed beside the backend, rather than bundled for redistribution.

Final local records: `logs/windows-live/report.json` (30/0) and
`logs/windows-world/report.json` (17/0). Three complete voiced replies each have
one native playback interval, zero dropped frames and a drained generator/queue.
This measures the native playback lifecycle, not a physical acoustic gap recording.

An earlier packaged probe failed the microphone-frame assertion: it read the
buffer after a fixed 0.8 seconds while synchronous avatar import could delay main
thread capture processing. A focused integrated diagnostic observed first processed
frames at 1.31 seconds, without focus loss or cancellation; isolated packaged and
editor input also passed. The corrected test waits at most five seconds for actual
frames and retains the assertion. The final full package run captured 0.117 seconds
of frames after 184 ms and canceled without saving or transmitting that recording.
The original failed report is retained in `logs/windows-live-packaged-v1/`.

All three avatars also pass measured sole calibration and stable floor projection.
Windows floor and window-top renders were inspected. Imported gait can lift the feet
above the stable support line; this is not a per-frame physical foot-lock solver.

The ordinary `Launch-Mate.ps1` path also completed successfully against the warm
GPU supervisor. The launched Windows process responded, had a nonzero native window
handle, and established one backend WebSocket connection. The app and owned GPU
services were left running for use.
