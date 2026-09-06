# Walking posture diagnosis

The previous default imported walk caused a downward head posture independently of pointer or destination gaze. A static source-only ablation across three real rigs and 120 uniform phases per clip measures rest-relative humanoid forward elevation, with positive pitch downward. No procedural pose, gaze, IK, camera pitch or window motion participates.

- `walk`: head 13.40–17.05° down (mean14.82°); upper chest16.45–20.07° down.
- `walk_formal`: head12.877° down throughout; upper chest11.79–15.89° down.
- Removing head and neck tracks worsens the walk head to16.45–20.07° down. The source neck compensates for part of the ancestor lean.
- Removing torso tracks instead gives head4.90–2.17° upward. The torso chain is therefore the dominant source of downlook.
- Formal upper-arm pitch excursion is only about4.3–4.6°, versus17–18° in the ordinary walk. This is a measured contributor to its constrained upper-body movement, not a complete perceptual explanation of stiffness.
- Both GLB files contain52 rotation channels and no translation channels. Enabling an existing hips translation track cannot restore a missing authored bounce.

A separate host issue was also found: the director retained the destination support point as attention, and LivingBehavior converted its floor-level Y relative to the head into downward gaze. However, full-weight imported VRMA head/neck rotations overwrite procedural gaze in that original steady walk. Correcting only that host target cannot remove the source posture. It can affect anticipation and other periods where imported head ownership is incomplete.

A locomotion-only final head/neck pitch correction is a bounded fallback; deleting their source tracks is counterproductive. The subsequent integration selected the directly baked UMA walk and corrected travel attention; see the final sections below. This opening diagnosis describes the original baseline, not an unresolved current host issue.

Reproduce with `companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script res://tools/probe_walking_posture.gd -- --output /tmp/walking-posture`. The compact JSON summary records source/probe hashes and links the complete compressed phase samples in ignored logs.

## First replacement candidate screen — not approved for installation

The initial baked `uma_homewalk` source has a nearly level head (-2.83° upward to2.40° downward, mean0.34°), but source-only arm measurements expose a conversion/curve defect: upper-arm segment elevation reaches76.7°/78.2° above horizontal, with adjacent local quaternion steps18.92°/25.91° per 1/120 cycle. `uma_homewalk_down` similarly raises arms above73°. This occurs without gait or IK. The up variant's arms remain below horizontal (-75.8° to-63.8°) with about 1° maximum adjacent step, but its head points3–10.8° upward. The neutral head result alone therefore does not justify installing that clip.

`candidate-v1-summary.json` records this failed source screen. All three exact tested VRMA binaries and full phase samples were preserved under ignored logs, with matching SHA-256 hashes, before conversion changes. The source conversion is being investigated independently.

## Selected direct-quaternion source and integrated result

A later candidate baked directly from the original Unity quaternion curves was selected as production `uma_walk`; it is distinct from both the failed unfiltered candidate and the intermediate Euler-filtered candidate. Its exact SHA-256 is `8f0b44c9fbee138f9923185a6dc373e0a11349c7d20c523163c941ebfe329573`. Independent source-only sampling across all three rigs gives head pitch -0.875–2.085°, relaxed arms below horizontal and maximum adjacent upper-arm quaternion steps about 1° per 1/120 cycle. See `direct-unity-source/summary.json` and the indexed complete samples.

The actual main 12-cell matrix in `../transition_chain/uma-walk-final/` then passes 348 checks, with established walk head pitch -1.020–2.228°, centered authored hip motion, observed claimed foot drift ≤0.314 mm, and all prior concurrent-turn and gesture-pair checks passing. Established-walk statistics explicitly exclude the first0.5 seconds of each clip; all acquisition frames remain in the raw evidence. The host now levels vertical navigation attention while leaving stationary inspection height-sensitive. No synthetic head-correction layer was installed: the source selection fixes the steady authored posture.
