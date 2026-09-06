# Independent authored-idle runtime review

**APPROVED for the tested runtime integration scope.** Three real VRM rigs at 30 and 60 Hz passed 132 assertions with zero failures. Six additional stage-summary records are diagnostics, not assertions. This is a fresh authored-layer review; the earlier 240-check turn baseline does not validate these changes.

The dedicated probe uses real `MotionPlayer`, `AmbientMotion`, `VrmAvatar`, `VrmaClip`, leg IK and TurnStepper. It loads generic `uma_home_idle` for each character and that character's real rare-action alias, then tests action completion, speech interruption/resumption, gaze ownership in both directions, heading and return, idle disabling, direct model replacement and explicit reset. It records true scaled world-space ankle and sole-reference points. It does not instantiate the whole main scene or move an OS window.

## Fixed findings

- Rare actions were accepted while idle was disabled, then immediately discarded. The API now rejects unavailable ownership states and missing base loops.
- Reset/model replacement retained head-mask state. Both now clear it; changing loop selection preserves the current explicit attention request.
- Boolean head ownership caused a 3.82-degree first-frame jump when gaze returned to authored idle. Continuous complementary blending removed the pose jump; bounded ownership pursuit also removed the subsequent linear-weight velocity discontinuity. Intermediate gaze failures are preserved.
- Starting a turn discarded the authored pelvis translation, moving the hips about 14–15 mm in one frame. TurnStepper now preserves the blended offset while applying its additional reach correction; observed maximum hip steps fell to about 1 mm.
- Resuming idle after a talking clip immediately pinned the feet, moving them 124.9 mm in one frame. Contact targets now acquire from the actual outgoing feet over the 1.2-second blend. The first step fell to 0.0716 mm; maximum acquisition steps were 2.62 mm at 60 Hz and 5.23 mm at 30 Hz.

## Final measurements and limits

Generic home head speed peaked at 5.34 degrees/s and acceleration at 102.84 degrees/s². Deliberate gaze handoffs peaked at 19.16 degrees/s and 127.97 degrees/s², meeting the existing quiet 12/150 and purposeful-gaze 30/150 criteria without changing the source animation assets.

At contact weight >=0.999, actual ankle and sole-reference error remained below 0.072 mm. Per rig, 60 Hz runs measured 2,080 acquired frames and explicitly recorded 140 acquisition frames in the selected standing stages; 30 Hz runs measured 1,040 and 70 respectively. The sole reference uses a measured rest-sole offset transformed through the live foot bone, not exact skinned shoe vertices or collision/friction physics.

The earlier fixed one-second exclusion ended before the new explicit 1.2-second contact acquisition and produced three recorded contact failures (up to 7.9 mm residual). The final criterion uses actual contact weight, with acquisition coverage and every raw frame retained. It does not claim that feet are planted at their final rest contacts during acquisition.

All stage peaks remain in the reports. Authored rare actions and imported talking clips have substantially higher head acceleration than quiet home idle. Direct model replacement intentionally bypasses the host's normal `reset_all()` path and records a roughly 145 degrees/s new-model startup transient; it verifies stale action/contact/head-mask cleanup, not orientation continuity between different rigs. Normal main loading explicitly resets motion before replacing the model. Windows visual naturalness, source-action expressiveness and visible shoe deformation require the coordinator's separate rendered review.

## Artifacts and reproduction

`summary.json` aggregates the final cells. `final-30fps/` and `final-60fps/` contain compact reports and `trace_files.json` indexes for complete CSV traces and logs in ignored local storage. `development/` preserves each failed or intermediate run, including the diagnostic pose/foot discontinuities that were not represented by the initial boolean assertions. Before/after runtime hashes match across both final runs and the source at completion, including `turn_stepper.gd`, `leg_ik.gd` and `desktop_gait.gd`; candidate assets and the probe are also hashed.

From the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_idle_review.gd -- --fps 60 --output /tmp/authored-idle-review
```

Repeat with `--fps 30`. The probe creates no visible window and makes no backend requests.


## Raw trace storage

Complete raw CSV/JSONL attempts are now stored under ignored `companion/logs/diagnostic-traces/`, so bulk debug traces are not added to Git. Each result directory has `trace_files.json` with the exact repository-relative local path, byte count and SHA256. `diagnostics/TRACE_STORAGE.json` indexes this relocation. No failed attempt was discarded. Earlier artifact descriptions refer to capture-time filenames; use these indexes to find the preserved files. Reports, checks and selected boundary evidence remain in diagnostics.
