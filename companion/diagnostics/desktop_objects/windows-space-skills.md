# Windows live space-skill and seated-camera integration probe

**Current acceptance limit:** the retained 48/0 Windows run validates command execution, terminal contact geometry and camera/settings behavior. It does **not** establish a natural sit-down transition. The user subsequently rejected the current transition and requested authored motion acquisition/choreography (including chair handling and actually lowering into the seat). That presentation work remains unresolved; static endpoint approval must not be reported as acceptance of sitting/standing motion quality.

Probe: `native/tools/probe_windows_space_skills.gd`. Root owns and runs the actual Windows process; author only parsed the script locally with Godot 4.5.2. It refuses non-Windows execution. Required argument: `--output <directory>` after Godot's `--` separator. Use the production main scene and existing live backend configuration; no stub, synthetic model event or direct skill is substituted for the model request.

Example engine invocation (root supplies the installed executable/project or equivalent main pack):

```text
Godot.exe --path <native-project> --script res://tools/probe_windows_space_skills.gd -- --output <new-report-directory>
```

Total watchdog: **120 seconds**, including readiness waits. Normal cached readiness is expected to leave time for the dialogue, approach, 10-second computer use and chair/view checks. If the backend is too slow or ordinary hover/busy policy prevents progress, the run records a failure instead of changing that policy. Existing settings are snapshotted and restored on success, checked failure and watchdog cleanup. An externally killed process cannot execute cleanup.

Fixture: explicit Cheval Grand after backend hello (session and actual VRM cache filename/hash checked), default 0.6 pet size, neutral view, empty furniture, VAD off, explicit behavior enabled and normal default autonomy/surface mode. Existing backend, microphone device, voice preferences, cursor and application windows are not changed. The owned pet window is placed on the usable monitor floor away from the current cursor half; normal hover, foreground, motion and contact gates stay active.

The first phase submits the exact Korean chat:

> 컴퓨터를 꺼내서 써 봐. 먼저 짧게 대답해 줘.

Assertions cover:

- Declared non-stub provider, actual model response success, Japanese kana in reply text, received PCM bytes, native playback signal and measured audio envelope. This establishes actual PCM playback associated with Japanese reply text; it is not independent transcription of generated audio.
- The real `action` and `done` events carry the same validated `furniture/computer/use` intent. A wrong/missing model intent fails the run.
- Exactly one computer appears, enters shared-world `using`, and both final rendered wrists satisfy strict reach acceptance, <2cm world residual and <3px projected residual. Calibrated seat/socket residual must be <1px. Spoken acknowledgement precedes use.
- Exactly one terminal `completed` outcome occurs for `<turn>:intent`, with no duplicate dispatch from action/done, and the interaction releases.
- The **real backend** returns `intent_result` with the matching intent ID and `accepted=true`. This verifies server acknowledgment of native execution feedback. It does not claim a second model turn consumed that feedback; no second model call is made.

The independent direct-host phase uses `living.request_intent` with source `user` and `probe:*` IDs that deliberately do not end in `:intent`:

1. Place one chair, then target that same instance with yaw 45°, scale 0.8 and appearance `cool`. Check canonical stored values and actual material-instance tint application.
2. Sit on that existing chair through the validated skill; require real `arrived` and shared seat contact. The expected total is two furniture objects; the final hard check is ≤3.
3. Open the actual independent settings window. Require visible, nonembedded, separate viewport and no overlap with the rendered seated pet.
4. Change the real UI sliders to pitch 45° and yaw 45°. Check actual `Camera3D` basis, orbit position and size against the expected view, not merely saved settings. Require retained occupied support identity and <1px seat/socket residual. Capture the owned shared root viewport and settings viewport.
5. Reset through the panel API; require actual camera transform/size and all four setting defaults restored, with contact preserved. Close settings without removing the seated pet, then clean up owned furniture and restore settings.

Evidence is incrementally retained in `report.json`: full non-PCM backend events, PCM byte counts, native playback events, command/interaction outcomes, 250ms policy/contact contexts, skill arguments/results, rig identity, actual camera transforms, per-hand residuals, seat residuals and own-viewport capture provenance. Images include `lm-computer-using.png`, `chair-view45-shared.png`, `separate-settings-view45.png`, and failure captures where reachable. No desktop screenshot, external-window content, cursor injection, keyboard injection or microphone capture is performed.

Local validation: Godot 4.5.2 `--headless --path native --script res://tools/probe_windows_space_skills.gd --check-only` passes. Independent reviewer initially found that saved view values alone could produce a false positive and that window visibility was not asserted. Both findings were fixed by checking actual camera basis/position/size before/after/reset and requiring visible native settings. Actual Windows results remain root-owned and must be attached separately.

Final independent `astra_face` review: **APPROVED** after rereading the corrected actual-camera and visible-window assertions. This is probe/source approval, not an assertion that the Windows integration run passed.

## Retained packaged Windows run — 2026-09-06

Root executed `logs/windows-space-skills-d3d12-nudge/`. This review read its strict JSON report, build/probe identities, process log and all three owned-viewport captures; it did not launch another Windows process.

- **48 passed, 0 failed**, elapsed **45.541s**.
- Runtime: Godot **4.5.2-stable**, D3D12 12_0 / Forward+, NVIDIA GeForce RTX 4090.
- Executable: `MateCompanion.exe`, **99,712,944 bytes**, SHA256 `7821c11b2236636efb3f14f4dbe3f882bc4bd543e2bd1fb12e9b280417288a3e`.
- Probe SHA256: `38280eb30e9bc3c4529c13aa9f17803e6137872e0441a27844b410e835233d43`.
- Report SHA256: `2836492a43e1e3e02cac25d9ceca4a54ad5c18eb68079e7b6046c5ca60d8c56d`.
- Build manifest records `source_stable_during_build=true`; its complete source-before and source-after SHA256 maps are equal. Main source SHA256 `900f8a774b3a1a07cbe7ee1de0b423582ef155b2c01f2fddc4b4827218f584ba`; object-host SHA256 `577322e55fa71aa83e80c9dc778874fc8dce94a4225e38d20992b976cf84a8fa`.
- Actual Cheval VRM SHA256: `61e40e14eec93f9bd8124b2a9d3a71aba0e580ee9b2ef4a55dbb6e4ce5d8ef8a`. This replay covers Cheval only; it is not a three-character motion test.
- Separate retained local selftest `logs/native-selftest-space-skills-nudge.log`: **591 passed, 0 failed**. This is additional software coverage, not visual transition evidence.

Measured run outcomes:

| Measurement | Retained value |
|---|---|
| Japanese reply text | `はい、トレーナーさん。` |
| Actual received PCM / playback | 114,560 bytes; playback observed; first playback at 5.921s |
| Model intent | `furniture`, `computer`, `use`, placement `near` |
| Computer left wrist | reachable; 0px projected error; 9.5414e-8m world error |
| Computer right wrist | reachable; 0px projected error; 6.6640e-8m world error |
| Computer seat/socket | 0.781105px |
| Model execution | `t1-5813:intent` completed once at 34.480s |
| Server feedback | matching `intent_result`, `accepted=true`, at 34.527s |
| Direct chair settings | `obj_2`, yaw 45°, scale 0.8, appearance `cool` |
| Chair seat error before view | 0.298383px |
| Chair seat error at pitch45/yaw45 | 0.000244px |
| Chair seat error after reset | 0.000122px |
| Final created object count | 2; settings restored |

The actual camera changes from identity basis at position `(-0.537937,1.027519,4.605996)` to basis columns `X=(.707107,0,-.707107)`, `Y=(-.5,.707107,-.5)`, `Z=(.5,.707107,.5)` at `(1.40886,3.983497,2.169617)`, then returns to the original basis and position. Orthographic size remains `2.2968075275`. This is evidence of an actual camera change, beyond saved slider values. The occupied support remains `object:obj_2:seat`.

### Visual review and its boundary

**APPROVED for the narrow static endpoint presentation in this run.** Reviewer Astra inspected:

- `lm-computer-using.png` (shared root depth, 24.552s): the avatar visibly sits facing the monitor, the arms extend to the keyboard, the monitor remains substantially visible, and desk/chair/avatar depth ordering reads coherently. Numerical wrist and seat evidence supports the contact claim at that sampled frame.
- `chair-view45-shared.png` (shared root depth, 45.379s): the higher camera view clearly exposes the seated pose and chair; the visible character, chair and feet remain inside the owned image. Reported camera basis and retained seat identity support the requested 45° view behavior.
- `separate-settings-view45.png` (native window ID 4, 45.401s): Korean settings UI renders in its own window. **The image shows the conversation tab, not the view sliders.** Slider values and camera response are established by the report's actual UI events/camera checks, not by visible controls in this particular capture.

This approval concerns the endpoint images and sampled measurements. It does not approve how the character reaches the chair, pulls it out, turns, lowers the body into the seat or stands up. No temporal sequence was reviewed in this pass. The user's subsequent rejection of the sitting transition remains an unresolved acceptance issue; authored motion inventory/acquisition and choreography are being handled by the motion/interaction owners. The current solver-based contact checks must not be presented as a substitute for that motion work.

### Earlier failures remain retained

The successful replay does not erase these earlier runs:

| Directory | Build SHA256 | Result and limitation |
|---|---|---|
| `windows-space-skills-d3d12-first` | `3f0002806c2c2f08fe7b12563d8b14a2293c11283435443ffb43c5c5b513ed71` | 12/13 checks passed; actual Japanese reply returned **without a furniture intent**, so the strict probe failed the model-intent assertion and stopped. No furniture command was fabricated to continue. |
| `windows-space-skills-d3d12-refresh` | `e49a9180bb5af9b7ca3be92f5d973a26f9d84fda455ab8b2aa14e45aeba5a80f` | 44/48 checks passed. Model computer use and completion passed, but chair view change cancelled with `view_does_not_fit`; the four contact/support/reset/close-preservation assertions failed. Original raw report also contains nonstandard literal `inf` in inactive contact metrics. It is preserved unchanged. |
| `windows-space-skills-d3d12-nudge` | `7821c11b2236636efb3f14f4dbe3f882bc4bd543e2bd1fb12e9b280417288a3e` | 48/48 checks passed after the owner corrected view fitting and the probe replaced inactive `inf` with finite failure sentinel `1e9`. Natural sitting transition is still outside this pass and remains rejected by the user. |

Earlier raw JSON with `inf` was inspected using temporary in-memory normalization only; no retained file was rewritten. The final report parses with a strict JSON decoder. All three directories and their own build/probe identities remain the provenance for the sequence of outcomes, rather than treating them as repeated runs of one unchanged executable.
