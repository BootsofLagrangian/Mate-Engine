# Independent upper-body actions over locomotion

`MotionPlayer.play_upper_body_gesture(name, intensity=1, speed=1, repeat=1,
channels=["head", "arms", "torso"])` samples an existing bank action or loaded
VRMA on its own finite timeline. It leaves `current_gesture()`, distance-driven
walking phase, hips translation and leg ownership untouched. VRMA rotations are
retargeted; their root translation and lower-body tracks are excluded. Bank arm
actions retain their existing hand IK and wrist articulation. Half-second
quintic acquisition/release weights avoid inserting a rest-pose frame.

`stop_upper_body_gesture()` fades the layer out. `is_upper_body_active()` and
`upper_body.diagnostics.active` expose ownership independently from full-body
motion. Up to two live descriptors permit a bounded outgoing/incoming handoff;
a third request during that handoff is rejected. Full manual/custom previews
remain exclusive. Reset and model replacement discard old descriptors.

`set_upper_body_contact_lock(true)` reserves arms and torso for a workstation or
other hand-contact solver. Head-only requests remain available. The host should
set this lock before attaching hands and clear it after release. Existing arm/torso channels retire through a half-second fade and cannot
resume when unlocked; the host hand solver retains final contact priority.
This is not a physical collision simulation.

`view_yaw_radians` rotates screen-relative heading and horizontal gait vectors
into the world. Explicit `set_contact_heading()` remains world-relative;
`face_front()` faces the camera yaw. This mapping covers grounded horizontal
walking; it does not promise planted feet during arbitrary vertical flight.

## Reproduction

From the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_upper_body_overlay.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_upper_body_contacts.gd
DISPLAY=:0 WALK_CANDIDATE="$PWD/companion/assets/motions/uma_walk.vrma" WALK_HIPS=1 MOTION_RENDER_DIR=/tmp/upper-body-render companion/tools/Godot_v4.5.2-stable_linux.x86_64 --path companion/native --script res://tools/render_upper_body_overlay.gd -- upper_wave
```

Initial local validation: all three real VRMs, 30/60 FPS and camera yaw 0/0.8
radians, matched runs with and without a walking wave. Hips and feet positions
were identical; maximum wrist displacement from the baseline was 0.52–0.58 m.
Claimed stance drift including supplied desktop displacement was below 0.08 px.
Separate authored UMA upper-body-over-walk, seated wave and locked-arm tests
passed on all three rigs: leg rotations unchanged and locked arms unchanged.
These tests do not replace packaged host/camera acceptance. Own Cheval viewport
sequence was rendered and inspected; source snapshots and numerical logs are
under ignored `companion/logs/diagnostic-traces/upper_body_overlay`.
