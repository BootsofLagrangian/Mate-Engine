# Actual-main liveliness acceptance

The probe instantiates the real main script and inherits its `_ready` and signal wiring. It supplies local VRM/VRMA assets and authored character profiles, disables backend/microphone activity and settings persistence, and records the final pose after the real motion/main/autonomy update order. No solver is called directly by the test.

Final measurements use each character's authored behavior style, scale 0.6, 30/60 Hz and a consistent 90-second idle observation followed by directed travel, explicit failure cases and three context preemptions. Headless cells use the rounded simulated desktop origin and are not Windows rendering evidence. The coordinator runs actual Windows separately.

`results/` contains final authored-profile reports, per-frame `frames.csv.gz` traces and logs. `default-style-results/` contains six earlier passing fallback-style controls. `development-results/` preserves earlier failures and measurements, including two important integration defects that the runtime owners fixed:

- Yaw changed instantaneous safety bounds at a platform edge and interrupted a valid reversing journey. The main host now supplies a conservative turning envelope through `_navigation_rect()`.
- Gaze pursuit was bounded in normalized coordinates but its angular output hit a hard yaw limit before the pursuit reached its target. The motion owner now clamps the desired target to the reachable angular envelope before calculating pursuit/braking; ambient posture changes are also acceleration limited.

The probe itself was independently reviewed. World head quaternions now include the avatar transform; local/skeleton metrics remain separately available. First-frame preemption is asserted immediately. Reviewer recommendations also added explicit p95 foot-drift gating, turning exclusions, wall-clock deltas for real Windows runs and asset/probe hashes. The exact engineering criteria and every development adjustment are recorded in `ACCEPTANCE.md`.

## What the foot metric means

For each fully blended stance epoch, the probe records `desktop origin + camera.project(live world ankle)`. This includes the final skeleton pose, avatar scale/yaw, camera and committed desktop displacement. It also records a sole reference formed by transforming the measured rest-sole offset through the live foot bone. Neither the IK target/residual nor the stable presentation anchor substitutes for the observed point.

The result measures desktop contact stability, not friction, exact skinned sole deformation, foot roll, collision dynamics or human naturalness. The all-frame head peaks include deliberate full-body turns and walk animation, so they must not be described as quiet head jitter. Additional scales are tested by the motion owner's separate `probe_desktop_gait.gd` matrix; the main-scene matrix uses default scale 0.6.

## Reproduce headless

From `companion`:

```sh
./tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path native --script res://tools/probe_liveliness.gd -- --test-root "$PWD" --output /tmp/liveliness-cheval-60 --model cheval-grand --fps 60 --scale 0.6
```

Repeat with the other model IDs and `--fps 30`. Source and asset hashes, effective profile style, measured frame-delta distribution and exact check outcomes are in each report. The probe rejects a visible display unless `--realtime` is explicitly supplied.

## Actual Windows package

The coordinator owns this run. Exported packages intentionally omit tool scripts, so supply the script externally. Keep the application's normal Forward+ renderer:

```powershell
& '<package>\MateCompanion.exe' --script '<companion>\native\tools\probe_liveliness.gd' -- --realtime --test-root '<companion>' --output '<owned log directory>' --model cheval-grand --fps 60 --scale 0.6
```

`<companion>` may be an absolute UNC path. The run lasts roughly 150 seconds, creates/moves only its own companion window and uses actual monitor workareas. `--test-root` resolves external assets, motion bank and profiles; it is required for packaged execution. Motion/main/autonomy and derivative calculations use measured wall time between updates, while `--fps` sets the requested timer pacing. Actual frame-delta p50/p95 are reported.

The probe does not move or falsify the cursor. Real pointer interaction during quiet/travel is recorded and sets `controlled_run_valid=false`; assess that interference before treating failed motion checks as a runtime defect. Original settings are restored in memory and the probe does not save its placement or temporary test preferences.

## Final headless results

All six authored-profile cells passed, 34 checks each (204 checks total). Runtime and probe SHA256 identities match across the six cells.

| Model / Hz | Quiet seconds / 90 | Peak quiet head °/s | Peak glance acceleration °/s² | Peak stance drift px | Look lead s |
| --- | ---: | ---: | ---: | ---: | ---: |
| cheval-grand-30fps | 55.87 | 3.95 | 63.82 | 0.0589 | 1.000 |
| cheval-grand-60fps | 56.15 | 4.06 | 64.21 | 0.0617 | 1.017 |
| eishin-flash-30fps | 55.73 | 4.24 | 62.18 | 0.0552 | 1.033 |
| eishin-flash-60fps | 55.97 | 4.23 | 63.72 | 0.0550 | 1.050 |
| rice-shower-30fps | 55.77 | 4.23 | 65.10 | 0.0501 | 1.000 |
| rice-shower-60fps | 56.03 | 4.32 | 65.44 | 0.0600 | 1.017 |

Every speaking/dragging/panel case stopped with zero velocity and zero committed displacement on its first post-context frame, held position, avoided instant obsolete travel on release, and resumed eligible behavior. Known user/LLM requests, explicit unknown/unreachable outcomes and zero-displacement gait-phase freezing passed. Stance p95 drift remained below 0.03 px. These are simulated-desktop integration results, not actual Windows rendering or biological validation.

Optional Windows visual evidence: append `--capture-fps 8 --capture-seconds 90`. Captures only the owned root viewport after rendering, with timestamped PNGs in `frames/` and `captures.json` metadata. Capture/write cost is included in the next measured frame delta; capture defaults off and is always off headless. This optional hook was added after the six baseline runs, so their source hashes identify the earlier probe.


## Final stepping-turn results

The lifecycle-fixed runtime passed six authored-profile cells at 30/60 Hz,40 checks each (240 total). `turn-results/` preserves compressed full traces, logs and reports; `turn-summary.json` aggregates them. Every recorded runtime/probe hash matches across the six cases and matches the final source at test completion. The earlier baseline and intermediate lifecycle-unfixed matrix remain separate.

| Model / Hz | Turn support max drift px | Support coverage | Peak heading °/s | Peak heading acceleration °/s² | Interrupted skeleton-head acceleration °/s² |
| --- | ---: | ---: | ---: | ---: | ---: |
| cheval-grand-30fps | 0.00012 | 92.5% | 70.00 | 100.01 | 908.3 |
| cheval-grand-60fps | 0.00017 | 92.4% | 70.00 | 100.05 | 914.8 |
| eishin-flash-30fps | 0.02710 | 92.5% | 70.00 | 100.01 | 888.9 |
| eishin-flash-60fps | 0.02612 | 92.4% | 70.00 | 100.05 | 946.6 |
| rice-shower-30fps | 0.00012 | 92.5% | 70.00 | 100.01 | 934.9 |
| rice-shower-60fps | 0.00479 | 92.4% | 70.00 | 100.05 | 974.3 |

All cells measured24 fully weighted turn-support epochs. Initial turn blending accounts for 1.0 second of explicitly unsupported time aggregated across turns; this is not covered by the tiny fully weighted drift values. Actual departure heading error stayed below 0.004 degrees. Foot swing arcs include approximately 0.048–0.055 m of actual world-Z excursion at scale 0.6. These demonstrate a supported geometric stepping mechanism, not complete foot physics or whole-desktop depth navigation.

The interrupted-pose implementation now carries outgoing local joint velocity into a quintic transition instead of freezing a static pose snapshot. The remaining global/skeleton vector acceleration peaks above are deliberately retained; no post-observation absolute acceleration gate was invented. Quiet-head and purposeful-glance gates remain unchanged. Visual naturalness and absence of visible pops still require the coordinator's Windows sequence. Use `--capture-seconds 180` to include the explicit mid-turn interruption and later walking preemptions; this version runs approximately 164 seconds.
