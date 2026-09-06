# Upper-body overlay independent review

**APPROVED for bounded channel ownership, finite lifecycle and continuous handoff mechanism.** This does not establish universally natural motion or a wrist-speed limit. Runtime source hashes are in [summary.json](summary.json).

The independent [probe](../../native/tools/probe_upper_body_review.gd) runs actual MotionPlayer final poses for three rigs at 30/60 Hz, with a continuous UMA walking base. Thirty cells cover six controls and 24 finite-wave, replacement, explicit-stop and contact-lock scenarios. All checks pass: hips and both feet remain exactly equal to the matching no-overlay control; requests finish and release; replacement samples both live actions for at least one-third second. World quaternion measurements include the skeleton's global transform. These runs manually supply deterministic locomotion displacement; they do not test main event routing, real OS movement or automatic spring processing.

Source inspection confirms root/leg exclusion for bank and authored sources, filtering before arm IK, final contact/gait solver ownership, preview/custom exclusion, and clearing on reset and model replacement. Nonfinite intensity/speed are rejected. Contact locking retires existing arm/torso contributions over a quintic half-second fade, permanently for that request; unlocking cannot resurrect them. New locked requests exclude those channels. An independent rerun of `probe_upper_body_contacts.gd` also passes all nine rig/scenario combinations covering authored upper-body over walking, seated wave and locked wave, plus retirement/reset checks. This is not a complete furniture-contact acquisition test.

At the first explicit stop/lock frame, Cheval's world hand step is 3.49° at 30 Hz and 1.77° at 60 Hz, close to the continuing-wave control's 3.34° and 1.75°. The largest hand rotation speed occurs later during the return to the walking pose: roughly 524–533°/s in the Cheval replacement/stop/lock cases and up to 569°/s across finite-wave cells. The corresponding Cheval 60 Hz mid-fade velocity change is about 9–10°/s between adjacent frames. This is a fast, sustained arm return, not evidence of a one-frame lock cut; visual quality remains a separate judgment. No numeric acceptance threshold was added after observing these peaks.

Full boundary records and all three attempts remain in ignored local logs, indexed by [trace_files.json](trace_files.json) and the global trace index. The first two runs already used the final lock-fade source hashes; they are repeated current-source observations, **not before-fix evidence**. The final run additionally records peak-frame locations and probe hash. The compact summary selects hand frames immediately around the event and the maximum hand-speed frame; complete unfiltered bone boundary records remain available in the indexed raw result.

Reproduce from the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_upper_body_review.gd -- --output /tmp/upper-body-review.json
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_upper_body_contacts.gd
```
