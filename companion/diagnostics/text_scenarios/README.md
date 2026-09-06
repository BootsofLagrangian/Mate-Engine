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

Measured Windows runs are summarized in
[windows-appearance-results.json](windows-appearance-results.json): Mambo and
Hachimi each completed wet → default through two actual Korean text requests,
Japanese PCM playback, exactly one native completion per turn, matching action/done
intent, and acknowledged feedback (four turns, no failed assertions). First native
playback was 1.018–2.516 seconds after text submission. These runs used executable
`26d9fb9…` and the appearance-lifecycle prompt checkpoint; they are not a broad
reliability benchmark. The subsequent Cheval computer request omitted intent and
is preserved separately in [computer-grounding-change.json](computer-grounding-change.json).
That record distinguishes the later prompt repair from the earlier measured runs.

For an ordinary-conversation negative control, run
`computer-conversation.json`. Its `expect_no_intent:true` assertion fails if either
`action` or `done` contains an intent. It cannot be combined with `expect_intent`,
and neither assertion is forwarded to the model: only the step's text is submitted.
This checks that a stronger skill prompt does not turn discussion into an unsolicited
furniture action. Python and headless native assertion tests cover both event paths.

Assertion-only native regression (Linux headless, no native window or GPU model):

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless \
  --path companion/native --script ../diagnostics/text_scenarios/test_assertions.gd
```

To verify capability delivery and the exact model prompt, add `--capture-prompt`.
The launcher arms one local marker for the first step's exact text SHA256 and
selected character, expiring after 15 minutes. The backend captures only a fresh
text-only session with no prior history, once, to local user-data; the launcher
copies it to `assembled-prompt.json`. It contains the actual messages and exact
`apply_chat_template` string plus generation prefix used for inference, not a
reconstruction. Capturing never changes token inputs or generation settings. The
marker is removed on capture or launcher cleanup, and existing captures are never
overwritten. No HTTP endpoint exposes the prompt. Do not arm this against private
conversation: it is deliberately limited to the explicit first-step fixture.

The trial also records a pre-publication native furniture catalogue. Backend
`world_context` acknowledgments now echo accepted rich-catalog IDs/verbs separately
from legacy `furniture_types`; an empty legacy list does not imply an empty rich
catalogue. Exact-turn provider diagnostics contain the capability IDs/verbs actually
forwarded on the request. Use these layers before attributing an omitted skill to
model behavior rather than missing capability delivery.
