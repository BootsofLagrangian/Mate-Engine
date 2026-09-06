# Explicit seated floor contact

`MotionPlayer.set_seated_floor(clearance_m)` configures a furniture seat-to-floor
distance in unscaled avatar metres. The host supplies the actual asset socket
height adjusted by object/avatar scale, before requesting canonical seated
geometry. `clear_seated_floor()` removes the configuration; standing/cancel/model
replacement also clear it. Ordinary window-top seating has no floor constraint.

`SeatedFloorConstraint` adds a plane collider through the imported VRM Verlet
collider interface. Only secondary chains whose geometric reach intersects the
floor participate (the tested rigs use 1, 3, and 1 chains). The source rig uses
7 cm virtual terminal segments; visible tail/ribbon geometry can extend farther.
The adapter measures terminal mesh extent and radial width once, temporarily
extends those virtual collision segments, and restores them on release. Real
skeleton bone lengths and scales are unchanged. Equal-length joints in a spring
chain conservatively share the largest matching terminal padding; no vertex or
material is hidden to make the bounds fit.

Two-bone leg IK places soles on the same floor, gently extending shins forward
for a low seat while leaving the pelvis attached. The common transition controls
acquisition. Source sitting torso/arms remain authored. Canonical calibration
uses the same geometric constraints and restores exact bone and Verlet state.

Godot restores pre-modifier bone poses after drawing. The avatar therefore
captures secondary helper transforms inside `modification_processed`; ordinary
post-draw pose queries do not represent the rendered spring pose. Initial
geometry is refreshed once after 30 secondary samples. No full mesh skinning
runs every frame: CPU skinning is limited to explicit calibration and probes.

## Verification

- `probe_seated_floor.gd`: actual viewport and final modifier CPU-skinned mesh,
  four later samples per rig, physical floor derived from the **returned** seat
  anchor. All three rigs pass sofa 0.428 m at scale 0.6 and chair 0.48 m at scale
  1.0. Mesh minima meet the solver plane within floating-point error; the returned
  seat anchor leaves roughly 0.2–3.7 mm physical clearance in these samples.
- `probe_seated_floor_lifecycle.gd`: all three rigs preserve exact pre-activation
  Verlet history and array membership during calibration; release restores
  virtual lengths and removes colliders; model replacement clears caches.
- `probe_seated_geometry.gd`: full bone TRS restoration, deterministic canonical
  measurement, and anchor transforms at multiple scales/yaws.

```sh
DISPLAY=:0 SEAT_TEST_SCALE=0.6 SEAT_TEST_HEIGHT=0.428 MOTION_RENDER_DIR=/tmp/seat-sofa \
  companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script tools/probe_seated_floor.gd
DISPLAY=:0 SEAT_TEST_SCALE=1 SEAT_TEST_HEIGHT=0.48 MOTION_RENDER_DIR=/tmp/seat-chair \
  companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script tools/probe_seated_floor.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script tools/probe_seated_floor_lifecycle.gd
```

This is an explicit plane constraint for shared furniture seating, not general
cloth collision with furniture backs, legs, or arbitrary scene geometry.
