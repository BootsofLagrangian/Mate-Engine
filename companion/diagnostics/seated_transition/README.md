# Authored sitting and standing

The previous furniture flow selected `sit_idle`, waited 0.8 seconds, then lowered
that already folded pose to the seat. The new motion owner exposes a finite
source timeline so the host can move toward the seat while the original hip,
knee, torso and arm motion plays.

Selected source: locally extracted UMA `sitdown01` S/loop/E. Source-specific
provenance and exact endpoint checks are in `diagnostics/seating_assets` and the
reproducible installed selection in `diagnostics/everyday_assets`. Quaternius
CC0 sitting enter/exit was also converted and rendered as a comparison. UMA01
includes a backward hand reach and matched seated/exit endpoints; no generated
bend animation replaces the source.

## Host contract

1. Load clips and call `register_seated_transition("enter"|"exit", alias)`.
   Catalog metadata `seated_transition` performs this registration generically.
2. `seated_transition_requirements(kind)` returns clip, duration and original
   source hip displacement in unscaled avatar-local metres. Stage the standing
   approach in front of the chair; do not erase the source's backward movement
   by positioning a chair directly under the standing hips.
3. Call `start_seated_transition(kind, root_delta_local)` with the actual
   standing-to-seat (or reverse) endpoint displacement in avatar-local metres.
4. Every frame, read `seated_transition_state()` and apply the corresponding
   world endpoint displacement times `root_progress` as presentation offset.
   Root progress comes from the original sampled pelvis-height curve. The
   motion layer applies the remaining local pelvis path and all joint rotations.
5. `finished` means the exact source endpoint is being held. Commit the host
   support/root alignment atomically, then call `finish_seated_transition()`.
   Entry commits canonical seated idle; exit commits standing with the common
   short pose transition. Urgent cancellation uses `cancel_seated_transition()`.

`transition_bounds` is a cached, full sampled transition envelope expressed
relative to the CURRENT presentation root: the helper merges 13 skinned poses
in the initial root frame and subtracts current root displacement when queried.
Project directly with the current avatar transform; do not subtract twice.
Whole-mesh sampling occurs during preparation, never every frame. Initial
preparation measured about 0.19–0.42 seconds across the three rigs; up to four
matching configurations (including the outgoing joint pose) are cached. Helpers, bones and spring history are
restored after sampling. This sampled envelope still needs actual rendered
host validation, especially secondary motion and arbitrary camera viewpoints.

A configured physical floor follows the changing root coordinate frame.
Source swing legs are retained; only below-floor penetration is corrected.
The existing spring integrator handles tail/ribbon floor collisions. This is
not a new procedural sit solver or a chair-pulling animation.

## Local verification

```sh
SEAT_UMA=1 companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_authored_seated_transition.gd
DISPLAY=:0 WALK_CHARACTER=cheval-grand MOTION_RENDER_DIR=/tmp/authored-seat-transition-side-cheval-grand companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script res://tools/render_authored_seated_transition.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_motion_capability_metadata.gd
```

Initial local UMA verification: all three real VRMs at 30/60 FPS, entry and
exit, zero failures. Entry knee excursion 86–93 degrees, exit about 74 degrees;
ankle-based sole floor error below 0.000001 m. This establishes actual
articulation rather than a frozen seated pose. Runtime source sequences were
rendered and inspected on all three rigs. The earlier Quaternius candidate
probe retained four small floor failures before exact-plane/full penetration
correction; that failed run remains alongside the final UMA run.

These checks do not claim body-to-chair collision, a general physical seat
solver, or packaged Windows choreography acceptance. That host acceptance is
separate from the motion-layer evidence.
