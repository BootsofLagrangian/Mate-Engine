# Independent baseline measurement and marker review

2026-09-06, reviewer astra_face. Read-only review of runtime/probe sources; no Windows launch or input performed by reviewer.

## Liveliness baseline: APPROVED

The earlier REVISE findings are resolved. Head/torso orientation now includes skeleton.global_transform and thus avatar world yaw; skeleton-space head orientation/derivatives are additionally retained. Foot and sole-reference measurements include avatar scale/yaw, actual skeleton pose, camera projection and rounded committed simulated origin. They do not substitute the solver target or solver residual. Fully weighted stance is gated by runtime diagnostics; yaw changes split epochs. Maximum and p95 stance drift criteria are both encoded.

Each preemption checks velocity and committed displacement immediately after the first context frame, then checks the hold and release. Realtime mode uses measured wall intervals for runtime updates and derivative measurements, with frame timing reported. Headless mode uses fixed intervals and mirrors rounded simulated origin into the host window coordinate reference. Authored character data is installed before the first director tick and effective style is checked. Probe, relevant runtime and asset identities are recorded.

Checked six authored-profile reports under results/: 34 checks each, 204/0 total, shared source identities consistent. Peak stationary head speed is 4.323 degrees/s; purposeful glance acceleration is at most 65.436 degrees/s²; stance peak drift is 0.0617 px and p95 below 0.03 px. The README correctly limits these to simulated desktop, scale 0.6, three rigs and 30/60 Hz. Revised quiet-interval and purposeful-glance criteria are disclosed rather than represented as untouched prospective thresholds. Full all-frame peaks and earlier development failures remain available.

This approval covers that baseline measurement and claim scope, not new stepping-turn, direction-reversal or Z-axis quality requirements. New runtime revisions need their own identified evidence; the historical six-cell result must not be relabeled as testing later code.

## Marker polygon and Windows runner: APPROVED

`InterestPoints.pin_polygon()` now traverses the open circular arc continuously and closes through the tip, avoiding the prior self-crossing triangulation. Drawing and mouse passthrough share the same polygon.

Runner checks the window at the grab point against owner PID and complete rectangle before input. Raw Win32 coordinates add the virtual-screen origin once to Godot-normalized coordinates. The PowerShell input sequence releases the left button and restores the prior cursor in finally. The observed packaged report contains 36 successful checks and exact tip displacement [160,-90]; its process-identity record verifies Windows PID 3092 against launcher PID 16192 using executable and unique probe/output command identity.

One bounded correction was requested: under WSL, numerical equality of Linux Popen.pid and Windows OwnerPid must never bypass the executable/command identity check. Initialize ownership as `not IS_WSL and owner_pid == proc.pid`, then use the existing query path for WSL. The actual recorded run used unequal IDs and passed the full identity path, so its measurement is not invalidated by this edge-case finding. The coordinator applied `owned = not IS_WSL and owner_pid == proc.pid`; independent source reread confirms WSL always enters the existing executable/command identity verification path. Runner approval is now APPROVED. No rerun is required for this condition change: the recorded unequal-ID run already exercised the same full verification path.

## Existing asset research

No additional asset search is needed for this review. The previously researched official Overte files specifically fill the authored transition gap: idle_to_walk.fbx, settle_to_idle_small.fbx, turn_left.fbx and turn_right.fbx, with idle_once_shiftheelpivot.fbx for occasional weight transfer. Exact source revision, Apache-2.0 evidence and FBX-retarget limitations are in ../idle_assets/REPORT.md. Existing Quaternius Standard lacks dedicated standing turn/start-stop clips. Asset availability alone does not establish foot-aware turn quality; motion-owner implementation and actual rendered reversal evidence remain required.

## Stepping-turn probe additions: APPROVED

Independent rereview of the lifecycle-fixed six-cell `turn-results/` matrix and current probe: 40 checks per cell, 240/0. Relevant runtime and probe hashes match current source at review. Heading derivatives use actual signed avatar-yaw differences and measured dt; moving heading error is measured separately from requested target/readiness. Turn-support epochs use final projected live ankle and sole-reference points with full avatar transform and desktop origin, with no walking-yaw exclusion. Fully weighted stance follows runtime flags; initial blend support exclusions and measured coverage remain explicit. The dedicated preemption begins only after an active turn has nonzero heading speed and checks first-frame desktop departure suppression.

Optional captures are disabled headless/by default, read only the owned root viewport after frame_post_draw, record filenames/timestamps/save status, and include rendering/PNG overhead in the next measured runtime dt. This does not capture unrelated desktop pixels or alter the pointer.

Approval is for the stated geometric measurement scope. Tiny stance drift is projected desktop drift, not a 3D friction/foot-lock guarantee; raw world-foot Z is recorded separately. The roughly 889–974 degrees/s² interrupted skeleton-head peaks remain disclosed, not hidden by the successful turn checks. Visual continuity still requires the coordinator's actual Windows sequence. No new post-observation acceleration limit is inferred here.

Minor report correction requested: README's world-Z swing range should end at approximately 0.055 m, because Cheval30 records 0.0549785 m in turn-summary.json (currently printed approximately 0.048–0.053 m). This rounding correction does not affect any check verdict.
