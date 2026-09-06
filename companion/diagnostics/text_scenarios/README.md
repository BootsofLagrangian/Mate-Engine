# Real native text scenarios

The shared [engine instructions](../../engine/INSTRUCTIONS.md) are loaded into the
actual system prompt for every character. Profile data supplies identity and style;
current native capabilities supply callable IDs. The LM emits speech and a bounded
intent; native owns execution, deduplication, safety checks and terminal feedback.

Run one native app at a time, with the owned local backend already ready:

```sh
python3 companion/run_text_scenario.py \
  --native-exe companion/native/build/MateCompanion.exe \
  --character mambo \
  --scenario companion/diagnostics/text_scenarios/appearance-roundtrip.json \
  --output companion/logs/text-scenario-mambo-01
```

Use an installed character ID; the harness has no character branches. The appearance
scenario requires that character's installed `wet` and `default` variants. The
computer scenario uses the native furniture registry. Unsupported requests fail
honestly. `expect_intent` is only a report assertion: it is never sent to the model
or native dispatcher. To use a Windows Godot editor instead of a package, supply
its executable and `--project`. `--dry-run` validates and prints the command.

The launcher works from Windows or WSL with Windows interop and `wslpath`. It starts
an owned real native session, sends each text through the same `_send_chat` path as
the UI, preserves actual runtime target discovery and hover policies, and restores
Settings on normal exit. It disables microphone VAD for these text-only trials.
It does not move the cursor, inject calls, clear/create furniture fixtures or force
an initial costume. Prepare the desired initial state through the normal UI and
record it; the report captures actual initial model identity. A user interruption
is a recorded outcome, not a reason to silently retry.

Each new output directory preserves `launch.json` (executable, external script,
parent script and scenario hashes), `process.log`, and incremental `report.json`.
Reports distinguish text, PCM receipt, actual native playback intervals, delivered
action, observed native-active state, terminal outcome and backend acknowledgment.
They retain model raw output only if `/health` still identifies that exact turn;
otherwise raw output is explicitly unavailable. No PCM bytes or microphone capture
are saved. Optional PNGs contain owned viewport textures only.

`delivered_action_to_terminal_playback_overlap_ms` is an interval measurement, not
proof of continuous physical movement. The separate simultaneous-active sample
count observes actual native command/director state during playback. A fast costume
reload may finish before speech starts; zero overlap is measured, not a failure.
Native failure, missing intent, metadata mismatch, playback failure, feedback failure
and timeout are reported separately. Linux headless compilation establishes syntax
only; actual Windows execution is required for playback/rendering claims.
