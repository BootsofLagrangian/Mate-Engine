# Pose-bounds and contact-heading review

APPROVED for the bounded standing and heading scope. The actual shared-prop attachment lifecycle remains owned and tested by the host integration task.

All three rigs at 60 Hz and scale 1.0 pass 99 assertions. Each complete decompressed frame CSV is byte-for-byte identical to its corresponding cell in the preceding UMA walk matrix; `standing-comparison.json` records both paths and the matching SHA-256. This checks that the new calibrated seated geometry does not change standing gait, gaze, heading, foot contacts or window movement in this sequence.

The four additional checks per rig verify that calibration preserves the current posed skeleton, stable foot anchor, standing hit rectangle and navigation rectangle; the seated selector chooses finite shorter vertical bounds; and stand-up clears that selector and restores standing geometry. No seated frame is rendered by this selector check. It is intentionally not evidence of a real chair attachment or a physical sit-to-stand transition.

Source review confirms that standing bounds retain their previous branch while `_sit_active` is false. The calibrated seat anchor is separate from the stable foot anchor. Stand-up clears `_sit_active` before switching back to foot presentation; model replacement invokes stand-up and resets the motion before reframing the new model. Calibration and clip-instance caching were independently reviewed by the geometry owner/reviewer.

The existing real-rig contact-heading probe was independently rerun: nine rig/angle cases pass, including 215° wrapping, return to zero, 35° and rejection of infinity. Maximum heading speed is about 70.001°/s and acceleration 100.027°/s²; observed held-foot displacement remains below 0.065 mm. The setter rejects nonfinite headings and nonstanding/preview/custom contexts before changing state, wraps finite targets, and uses the existing continuous heading controller instead of writing avatar rotation directly. This is kinematic contact evidence, not friction or full-body physics.

The Windows chain probe's new character selection/identity assertion was also reviewed: it selects the requested/default character after hello, waits for matching session and loaded VRM identity, and records model path/hash. This closes the previous ambiguity about which rig a Windows trace exercised.
