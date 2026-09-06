# Focused authored-motion handoff audit

This follow-up reuses the existing inertial pose transition. No replacement
animation or new noise layer was generated.

Changes:

- A new full-body gesture takes ownership of the outgoing upper-body overlay
  through the common pose/velocity snapshot. The independent overlay no longer
  survives over the new action or applies a second competing return fade.
- Ordinary VRMA ownership uses quintic acquisition/release, with zero first and
  second derivative at the endpoints.
- The local arm angular-velocity carry ceiling is 720 rather than 360 degrees/s.
  The selected authored wave has about 474 degrees/s hand-world orientation
  speed; the previous local ceiling truncated its interruption. Head/body carry
  ceilings remain unchanged. This is not a global motion speed limit.
- Seated acquisition carries outgoing rotations and hip velocity with the same
  decaying-velocity/quintic construction. Bounds-cache keys also include those
  velocities. Seated idle starts at its own entry-relative phase, rather than a
  phase derived from total application uptime.
- World-scene locomotion wrappers pass real X/Z displacement to the existing
  gait owner and retain concurrent heading/step ownership. This adds no new
  procedural gait or path planner.

## Evidence and scope

`probe_motion_seams.gd` runs three real VRMs at 30/60 FPS over four selected
edges: live authored wave→bow, live wave→idle, walking+wave overlay→bank bow,
and natural finite wave completion. All 24 targeted regression cases pass.
The first two switches occur at 0.8 seconds while the source is still moving.
The first exploratory trace switched those cases at 2 seconds, after the short
wave had already ended; it is retained but is not evidence for live clip
replacement. The later `single-owner` and `carry720` traces use the actual live
0.8-second boundary.

At 60 Hz on Cheval, source hand-world speed immediately before live replacement
is 473.85 degrees/s. The old arm carry ceiling yielded 349.4 on the first new
frame; the final handoff yields 458.1. Natural finite completion's last nonzero
frame decreased from 24.78 to 2.97 degrees/s. The walking overlay handoff begins
at 127.40→127.43 degrees/s and no longer leaves the overlay timeline active.

Fast composed hand orientation returns remain: the recorded clip→idle return
peaks at about 640 degrees/s, and walking-overlay→gesture at about 707. These
are world hand orientations, including ancestor rotations, not isolated wrist
joint speeds. The targeted regression thresholds detect the former boundary
truncation and finite-release issue; they do not establish universal human
naturalness, joint-speed limits, or full motion-capture quality.

Additional checks pass: six real X/Z curved-path cases (three rigs×30/60),
claimed foot drift at most 0.284 mm; twelve authored seated entry/exit cases;
seated bounds/lifecycle checks; upper-body contact regressions; and the existing
bank release probe. The scene and foot results concern the numerical native
motion path, not Windows window compositing or obstacle choreography.

Local Cheval viewport sequences for clip replacement and walking-overlay
replacement were rendered; sampled temporal frames were inspected and complete
frame sequences/GIFs retained. Packaged real-time Windows presentation, cloth
quality, and subjective naturalness across every installed asset remain separate
acceptance work. No Windows process was launched or stopped by this task.

## Replay

```sh
SEAM_REPORT=/tmp/motion-seams.json companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_motion_seams.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_scene_locomotion_motion.gd
SEAT_UMA=1 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_seated_transition.gd
DISPLAY=:0 MOTION_RENDER_DIR=/tmp/seam-render companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script res://tools/render_motion_seams.gd -- walk_upper
```

Exact source identities and raw trace hashes are recorded in `validation.json`.
Earlier exploratory/failed attempts are preserved under ignored
`companion/logs/diagnostic-traces/motion_seams`.

## Independent review correction: acquisition bounds

The reviewer measured outgoing-wave acquisition geometry outside the original
13-sample envelope: Rice 6.695 mm and Eishin 3.650 mm. The corrected cache adds
120 Hz acquisition samples, increased when outgoing velocity exceeds three
degrees per sample, and grows the advertised envelope outward by 1 mm. The
original failed results are preserved. The exact 60 Hz acquisition comparison
now reports zero overflow for all three rigs; twelve seated cases and lifecycle
regressions also pass. This is a sampled containment result, not a mathematical
bound for every possible source or outgoing pose. Bounds preparation is cached
but now takes roughly one second in the measured headless cases; no CPU mesh
measurement runs each frame. Current identity is in dense-bounds-validation.json.

## Bounds preparation performance follow-up

The dense exact-skin fix above stalled the calling thread for 0.55–1.24 seconds.
It is retained as a correctness reference, not the final performance candidate.
`TransitionBoundsMeasure` now caches immutable mesh inputs and unions transformed
per-bind influence boxes. Normalized nonnegative skin weights form convex
combinations, so this encloses the skinned contributions. Unweighted vertices
use their mesh transform. To avoid false floor penetration from conservative
boxes, the minimum Y is refined by exact skinning only vertices whose influence
bounds can beat the current minimum. Cached vertical slices reduce that set.
The other five faces remain conservative. No actual geometry is clipped.

The current grid retains 13 full-clip samples and adds acquisition samples at
30 Hz or enough to limit carried rotation to 12 degrees per sample. Against
actual full-mesh measurements, all three rigs at 60/90/144 Hz acquisition and
all three full transitions at 60 Hz have zero observed overflow. This is the
explicit coverage for the reduced grid, not a universal continuous-time proof.
The exact minimum-Y refinement matches the old per-pose full measurement in
the tested cases. Side bounds can be 4–10 cm broader; production fit is separate.

Immutable input indexing is prewarmed when seated assets register; callers
registering before the model exists can call `prepare_seated_geometry_inputs`
after model load. This captures no future outgoing pose or velocity. Actual
start still computes a fresh complete bound synchronously: 35.5–45.3 ms across
the final 12 cases. This is substantially below the earlier second-long stall,
but **does not meet a strict 20–30 ms frame budget**. Cold input indexing has an
additional one-time cost and must not be mistaken for a free operation.
The cache retains at most three models and weak mesh references; changing model
identity replaces inputs. As with the old measurement, this describes base-mesh
skinning, not arbitrary morph-target changes or simulated renderer geometry.

Current identities/timings are in `optimized-bounds-validation.json`; all failed
and intermediate timing/geometry attempts are retained in the diagnostic logs.
