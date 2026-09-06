# Continuous motion handoffs

The sequence follow-up inspects actual main-scene idle → turn → walk → stop →
reverse transitions, including the final pose after OS-window movement. Isolated
clip playback did not reveal the following ownership/timing defects.

- Gait used a second, static leg-pose fade after the shared inertial transition.
  Removing it gives the common transition sole ownership of leg release.
- A low-speed cutoff released feet before the host ended the walking clip.
  Fresh supported samples now retain contact through deceleration, and stride
  stops adapting when traveled motion stops. Distance-driven phase is retained.
- Gait pelvis clearance erased outgoing lateral/depth translation. Clearance now
  adds to the current blended pelvis offset; its post-movement correction applies
  only the additional clearance, without accumulating the previous correction.
- Velocity was recorded before post-window movement IK. Both preliminary and final
  recordings now compare against the same previous **final** frame; the final
  recording replaces the preliminary estimate. Pending transition snapshots also
  follow the final posed frame.
- A transition initiated inside the pose pass began at u=0 and froze one frame.
  It now advances by that frame's elapsed time when its source is the previous
  rendered pose. External between-frame requests retain their normal timestamp.
- The final turn pose was discarded during the host's readiness-to-walk gap.
  Turn completion now creates a shared pose/velocity transition immediately.
- Ambient contact acquisition now carries foot orientation as well as position,
  so flat-sole IK cannot erase residual turn yaw instantaneously.

Development actual-main comparisons on Cheval at 60 FPS showed the pre-arrival
shoe spike fall from 189/268 degrees/sec to approximately zero, and the exact
turn-completion edge fall from 148 degrees/sec to 0.07. The knee continued from
34.24 to 32.97 degrees/sec instead of stopping for one frame. These are specific
diagnosed boundaries, not universal maximum-speed claims. The independent final
matrix includes all three rigs and both 30/60 FPS.

Nonurgent navigation reversal braking belongs to the autonomy layer; urgent stops
remain immediate. Do not force artificial leg motion against a stationary planted
foot to conceal an instantaneous OS-window stop.

Standing `idle_talking` now has the generic `contact_mode:"foot"` catalog
capability, maintained by `setup_motions.py`. Its stationary speech path receives
the same hip/contact treatment as other configured standing clips; seated contact
continues to own the lower body. This avoids relying on a later idle recovery to
correct the previously observed raw standing-speech foot displacement.

Owned regression commands (repository root):

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native -s tools/probe_gait_velocity_release.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native -s tools/probe_gait_transitions.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native -s tools/probe_authored_ambient.gd
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native -s tools/probe_desktop_gait.gd
```

The velocity-release probe reports diagnostics, while the other probes contain
explicit failure gates. Existing contact, model-switch, inertial-head and legacy
motion-asset regressions also pass. Production viewport/Windows sequence capture
and the independent combined-chain matrix remain separate acceptance evidence.
