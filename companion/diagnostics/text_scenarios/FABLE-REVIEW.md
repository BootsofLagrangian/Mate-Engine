# Independent Fable medium review

Model: `claude-fable-5-1`, effort `medium`. Full prompt, command and JSONL preserved in `companion/logs/collaboration/fable-backend-harness-review*`. Read-only review; no native/GPU run.

**Verdict: APPROVED**, with one packaging condition that must land in the same commit.

**Scope reviewed (read-only).** `engine/server.py` sender and intent lifecycle, `engine/INSTRUCTIONS.md` inclusion through `profiles.py`, `intent.py` appearance examples and movement-restriction wording, `providers/omni.py` active-variant reminder, both new test files, `run_text_scenario.py` plus `native/tools/run_text_scenario.gd` and its parent probe, the text-scenario README and JSON examples, and the failing Windows report. Native cross-reads: `main.gd` avatar variant request path, `living_behavior.gd` event handling, `behavior_director.gd` and `desktop_objects_host.gd` dedup.

**Tests I ran.** Full backend suite with the omni venv, no network, no models: 227 passed. The affected subset alone: 75 passed. I did not run Godot or Windows, and I did not re-parse the GDScript on Linux. The harness runtime claims below rest on reading the code and the user's prior Linux parse.

**Condition (must fix before commit).** `engine/INSTRUCTIONS.md` is untracked, and `engine/profiles.py:15` reads it at import time. A checkout without it fails at engine startup, not at first turn. Add it with the other new untracked files (both test files, `run_text_scenario.py`, `native/tools/run_text_scenario.gd`, `diagnostics/text_scenarios/`, `engine/tests/test_text_scenario_validation.py`).

**Lifecycle findings, confirmed sound.**
- Replay is scoped exactly as described at `engine/server.py:288-294`. It only fires on a successful done for the current turn, only when that turn already issued an intent to this character, and it copies the issued dict rather than the model's done intent.
- Guards persist. An action whose world context went stale is stripped at line 295 and never enters the issued map, so nothing stale can be replayed. Cancel is filtered at line 286 via the turn outcome. Reset and character select both call `_clear_world`, which empties the issued map, so the done falls through to the strip branch. Supersession changes the current turn id, so the old done is dropped. The parametrized lifecycle test covers all four cases.
- Native dedup holds for every replayed kind. Appearance uses `_avatar_variant_seen` in `main.gd:1003`, furniture uses `_command_seen`, and the director checks `_history` and the active id. All return `duplicate`, which `living_behavior.gd:213` explicitly excludes from a rejected feedback send, so the replay produces no second terminal outcome.
- The failing report is explained by the code. The revision bump at 6675 ms came from the native republishing world context after the costume load, which invalidated the done at 9125 ms. The default-return step had raw `intent:{}` with an exact turn match, so it is model omission. The grounded default-return example and the omni grounding line address that, not the parser.

**Harness findings, no false-pass path found.**
- Every failure class is recorded separately and gates the per-step check at `run_text_scenario.gd:122`. An intent that appears only in done, not in action, fails the step rather than passing. Feedback acceptance is keyed on the exact intent id.
- All native fields the harness reads exist: `base_url`, `audio.queue`, `director._active`, `objects._pending_command`, `_avatar_variant_command`, `avatar_variant_outcomes`, `_vrma_pending`, `_selection_announced`, `loading_label`. Provider `status()` exposes `last` with `turn_id` and `raw`, so the exact-turn raw capture works.
- Overlap is disclosed as an interval bound with a separate active-sample count, and zero overlap is not a failure. That matches the README.

**Non-blocking notes.**
- After a reset, feedback for a still-running native command is answered with the generic error at `server.py:404` because the issued map was cleared. Harmless, but it surfaces as a status message on the native side.
- The Python validator allows 8 steps of 90 s, which exceeds the 600 s native watchdog plus setup. That produces a recorded watchdog failure, not a false pass.
- The GDScript validator is looser than the Python one for `expect_intent` and `expected_outcomes`. Only matters if someone launches the script without the Python wrapper.
