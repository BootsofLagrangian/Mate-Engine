# Liveliness acceptance design

Prospective engineering checks drafted 2026-09-06 before the new main-scene integration was measured. These tolerances target a quiet desktop companion, not a validated model of human behavior. Runtime owners: motion (gait and ambient pose), autonomy (travel director), root (LivingBehavior and main integration). Probe owner: astra_head_jitter; no runtime edits.

The probe must instantiate the actual main script and preserve its wiring. It may suppress network access, microphone activation, settings persistence and visible-window creation; supply deterministic desktop geometry, a simulation clock and context flags; and manually advance real runtime nodes in their frame order. It must not call the leg solver directly or substitute its own behavior policy. A Windows run must use actual committed Window.position as the desktop origin; a headless run labels its rounded simulated origin explicitly.

## Quiet idle and variation

Observe 90 seconds at 30 and 60 Hz with a fixed seed and no user input. Record behavior/ambient state, gaze cue, local and global head quaternion, torso quaternion, window origin, gesture and context ownership every frame. Use quaternion rotation-vector differences, avoiding acos(dot) precision loss for tiny steps.

A quiet interval lasts at least 2 seconds, with desktop displacement below 0.5 pixel/frame, head speed below 5 degrees/second and torso speed below 3 degrees/second. Require at least three such intervals and at least 20% quiet time. Require at least two distinct intended look/posture states across the observation, rather than constant noise or an uninterrupted imported loop. Report how many actual head-direction excursions exceed 3 degrees; merely setting a cue is not evidence that the rendered pose changed.

For stationary quiet/ambient frames, report peak and p95 head speed/acceleration. Candidate tolerances: peak below 12 degrees/second and 150 degrees/second², excluding a separately reported 0.6-second window after an explicit gaze-target change. Report all-frame peaks as well, including those transitions, so exclusions cannot hide spikes. Deliberate gestures and travel turns are separately classified. If the implementation intentionally supplies fewer behavior states in 90 seconds, preserve the failed coverage result rather than quietly extending the observation until it passes.

## Desktop displacement, gait phase and planted feet

Drive a reachable lateral journey long enough to travel at least 200 desktop pixels. Record actual committed desktop displacement, current gait phase/stride and both final live feet after every main/motion/autonomy update. Phase must not advance while actual horizontal displacement is zero; report the residual between observed phase change and displacement/stride.

For each contiguous fully blended stance epoch, compute the final desktop point:

`Window.position + Camera3D.unproject_position(live world-space foot point)`.

Use the real skeleton pose and avatar transform. Report ankle points and a separately labeled sole reference derived from the rest sole offset transformed through the live foot bone; do not substitute the stable presentation anchor or the IK requested target. The sole reference is not an exact skinned-vertex measurement.

Candidate limits: maximum cumulative desktop drift within a stance epoch <=4 pixels; p95 <=2 pixels. Report stance duration/coverage and every excluded frame. Exclusions are entry blending (<0.999 weight), swing, and active facing changes (>0.5 degree/frame); require enough measured coverage to avoid a vacuous pass (at least four stance epochs and 50% of settled walking frames with a measured stance). Report support-plane vertical error separately. Include stop, restart, reverse direction, 30/60 Hz, and user scales 0.35/0.6/1.0 where the journey fits. Leg/solver residuals are secondary diagnostics, never the acceptance result.

Foot roll, friction, dynamic collision, cloth/hair response and biologically exact contact are outside this check.

## Anticipation and ownership

For a known reachable interest, trace request receipt, anticipate state, visible head direction and first committed desktop movement. The target cue and a visible head turn of at least 1.5 degrees should precede first travel by at least 0.15 second. Report movement during anticipation; cue timestamps alone cannot satisfy the visible-head criterion.

Interrupt travel separately with speaking, dragging and open-panel contexts through the main host path. Travel must stop within one frame. It must remain stopped throughout the hold. On release, it must respect the configured settle/anticipation delay and eventually resume an eligible behavior rather than remain stuck or instantly continue an obsolete walk clip. Do not simulate audio by transmitting real audio or messages; set the existing voice-active state and emit its normal signal when required.

## Unified intent path and failures

User-origin and LLM-origin requests for the same action must enter the same public intent handler and produce the same normalized intent/status shape, with origin retained only as provenance. Test known reachable, unknown action/interest and unreachable target requests. Unknown/unreachable outcomes must be explicit and must not silently claim movement or execute a different gesture. No live LLM/network call is needed to test the dispatch contract.

## Evidence and limits

Retain the exact scenario configuration, source hashes, deterministic seed, per-frame CSV and result JSON. Each planned cell is pass, fail, invalid or not run. Do not pool simulated and actual Windows measurements as if they were the same execution path. Root owns actual Windows final acceptance; this probe owner does not launch Windows or GPU workloads.


## Development-run dispositions

The first 90-second integrated observation produced meaningful quiet periods but the draft count of three periods was sensitive to how much of the same observation contained a legitimate journey. The coordinator explicitly directed keeping the original 90-second records and judging the quiet coverage rather than adding artificial interruptions to manufacture three periods. The implemented check now requires at least two intervals of two seconds and at least 20% quiet time; actual interval lengths and the original three-interval result remain in development artifacts. This is an explicitly revised engineering criterion, not a prospective biological claim.

An early metric incorrectly included walk-stop frames in the stationary-head summary. It now follows the original scope restriction: rest/curious/sleepy state, no gesture, no desktop displacement, and the separately logged 0.6-second attention-transition window. All-frame head peaks remain reported. A 175 degrees/second² sample at 0.633 seconds after a deliberate look still exceeds the 150 tolerance; it is reported as settling of an intentional glance, not silently excluded or relabeled as quiet noise.

The first integration run also exposed a real target interruption when yaw expanded the avatar bounds at a platform edge. The host now supplies its conservative `_navigation_rect()` envelope. The probe uses that same callback rather than the earlier instantaneous `pet_rect`, preserving the production navigation policy.

The coordinator then explicitly approved separating active purposeful pursuit from settled quiet: a nonzero measured `MotionPlayer._gaze_velocity` above 0.01 normalized units/second classifies a director look or its neutral return as an active glance. Settled stationary head limits remain 12 degrees/second and 150 degrees/second²; active glance limits are 30 degrees/second and 150 degrees/second². The 30 limit accommodates the chosen pursuit speed of 0.6 normalized units/second mapped through 36 degrees plus modest idle pose. The old fixed 0.6-second transition flag is retained in the CSV for audit, but no longer pretends every look finishes in 0.6 seconds. Original failures and all-frame peaks are preserved.

Independent review corrected two measurement gaps: head/torso world quaternions now include `skeleton.global_transform` (avatar yaw and scale frame), while skeleton-space head quaternions and derivatives are recorded separately; preemption now explicitly checks velocity and displacement immediately after the first post-context frame before measuring the longer hold. Stance epochs split at excluded turning frames and the p95 <=2 pixel condition is enforced.

Headless simulation mirrors the rounded simulated desktop origin into the test Window's cached position, so the real host's gaze/pointer coordinate conversion sees the same origin used by the foot metric. This is not an actual OS move. The `--realtime` mode uses actual owned Window.position and measured wall-clock intervals for motion, main, autonomy and derivative calculations; the nominal FPS only paces its timer. Actual pointer interaction is observed, not faked, and marks a supposedly controlled Windows quiet/travel run invalid if it interferes.

Final default-scale matrix: all three local character profiles are loaded into the real session catalogue with the matching character ID before the first LivingBehavior tick. The effective director style is checked against that profile and recorded. Earlier six default-style control runs remain separately labeled. Additional manual scales belong to the motion owner's separate gait scale matrix; the six main-scene cells use scale 0.6 consistently.


## Separate stepping-turn matrix (prospective)

The earlier `results/` matrix is preserved as the pre-stepper baseline. The forthcoming `turn-results/` matrix records explicit actual avatar heading, target/error/readiness, true world foot Z, turn phase and stance/swing flags. It additionally interrupts an actively rotating turn with speaking context. Turn-support epochs include world avatar transforms and desktop origin and do not use the walking metric's yaw exclusion.

Gates: heading speed <=90.1 degrees/s and acceleration <=180.5 degrees/s² (small numeric tolerances around the proposed 90/180 limits); actual moving heading error <=15 degrees; at least 4 measured turn support epochs, each with ankle and sole-reference drift <=4 px. Initial 0.18-second support blending remains explicitly unsupported in duration/coverage reporting. A passing fully weighted support metric does not claim support during this excluded initial blend. Interrupted skeleton-head acceleration remains separately exposed while the runtime owner resolves pose-velocity continuity; these turn checks alone do not approve that unresolved dimension.

Optional actual-Windows captures default off and capture only the probe window. Rendering/readback/PNG write overhead is included in subsequent real wall-clock dt, so captured runs may have a different measured frame-rate distribution from uncaptured runs.
