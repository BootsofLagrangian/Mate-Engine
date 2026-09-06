# Deterministic behavior diagnostics

Run from the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/behavior/test_director.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/autonomy/test_autonomy.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/autonomy/test_surfaces.gd
```

2026-09-06 results: director 9,746 checks, autonomy 3,636, surfaces 769; zero failures.
The 16-minute simulated idle run at 10Hz produced 7,589 rest, 809 curious, and
1,202 sleepy samples. Identical context streams produced identical outputs; repeated
attention targets obeyed their cooldown. This distribution uses the default style,
two persistent surface interests, and can_move=false, so it measures quiet/dwell
scheduling, not real desktop travel or gait quality. The director contains no model,
network, screenshot, or desktop-content reading calls.

Other cases cover user/LLM deduplication, target removal, expiry while movement is
blocked, character switch, user arbitration over a full local queue, foreground
preemption within a tick, preview suppression, explicit non-movement inspect,
pre-travel anticipation, already-at-point success, cancellation, and rejection of
points on a different surface height. Original autonomy tests retain frame-rate,
speed/acceleration, monitor and surface safety coverage. The explicit movement
state test now expects anticipation before walking; simulation handles anticipation
deadline crossings using only the remaining frame time.

These are deterministic headless tests. Real projected geometry, OS movement,
and visible gait are covered separately by the root-owned liveliness/Windows probes.

Departure refinement adds five checks: the first speed sample has gentle acceleration,
speed builds after half a second, and cancellation/restart resets the easing interval.
Autonomy 3,636 and surface 769 checks still pass. Numerical easing alone is not evidence
that the rendered walk looks natural; actual-rig turn/first-step visual review is pending
with the root/motion owners.

Turn readiness adds five checks for a held3s anticipation, no catch-up translation,
subsequent eased travel, bounded heading timeout, and immediate speech interruption.

Actual host callback ordering (no rendered rig):

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/behavior/test_host_heading.gd
```

7 checks, zero failures. Uses real main._wire callbacks and actual MotionPlayer heading
methods over a lightweight avatar double. Covers a new target while already anticipating,
legacy roaming without LivingBehavior, readiness withholding, panel pause/front ordering,
drag cancellation, and timeout cancellation. The new-target case caught an actual bug:
state_changed alone did not update heading for a replacement target; root changed heading
ownership to target_chosen. This validates control ordering, not physical foot planting or
rendered turning quality, which still require the actual-rig acceptance artifacts.

Authored-idle host integration:

```sh
XDG_DATA_HOME=/tmp/mate-idle-review-data companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/behavior/test_host_idle.gd
```

21 checks, zero failures. Actual LivingBehavior, main idle-selection handler, MotionPlayer
ambient APIs, and ControlPanel selector methods run with lightweight host/avatar doubles.
Checks cover profile loop application and same-ID refresh, finite action scheduling and
cooldown, auto-only actions, behavior-disabled foreground suspension and stale attention
clearing, UI candidate filtering and saved choices, and explicit breathing-only selection.
This probe writes only isolated test settings under the supplied XDG_DATA_HOME. It does
not validate rendered body/foot motion. Godot reports the existing ObjectDB exit warning
in the shared host fixture; no script errors occur.

Navigation execution budget regression adds11checks (total9,719): a command dispatched
at28.1s of a30s freshness TTL can complete25s later; duplicated started acknowledgments
do not renew its45s execution deadline; accepted navigation cannot requeue itself;
missing completion expires with cancel_move; target expiry and never-dispatched queue
expiry remain authoritative. This addresses the observed Windows cold-reply case that
expired shortly before arrival. Windows replay remains the root's separate validation.

Supersession handoff adds13checks (total9,732): safe supported replacement removes
only redundant settle, stops OS motion immediately and retains anticipation/readiness.
Ordinary cancel, different height, outside surface, pointer/voice block and no active
navigation retain settle. Director emits a current replacement point but drops it after
a newer rest request or command expiry. Original autonomy3636/surfaces769 still pass.

Smooth nonurgent supersession refinement: previous instant-stop expectation is now
explicitly replaced by bounded deceleration. Added tests check preserved initial velocity,
acceleration/safe-position bounds, replacement gating until rest, urgent stop/voice/
pointer/drag during braking, unsafe stopping-distance fallback, and pending replacement
expiry cancellation. Total9,744checks pass; original autonomy3636 and surfaces769 pass.
This is trajectory-policy evidence; real Windows chain footage remains root-owned.

Character switch explicitly clears handoff queue tracking; the first new-character tick
cannot emit an old replacement_invalidated cancellation (two focused regression checks).
Current limitation: another queued move issued during the short braking interval invalidates
the prior replacement and takes the immediate-stop fallback. Smooth braking is guaranteed
for a single validated same-support replacement; rapid retargeting would require a new
native geometry validation and is deliberately not generalized here.
