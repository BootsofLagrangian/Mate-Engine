# Independent leg/pelvis/foot rig audit

2026-09-06. Read-only inspection of the three original VRMs plus their actual Godot runtime imports. No avatar, skin, runtime, or motion assets changed; no additional tools needed. `probe.gd` and `measurements.json` preserve the measurements.

**No rig rewrite is justified by this audit.** The moving-turn problem primarily concerns contact trajectories, joint velocity, and ownership transitions. One concrete sole-calibration omission affects Eishin and should be corrected in the runtime pipeline.

| Imported rig | Thigh / shin m | Rest knee forward offset m | Foot-weighted sole vertices |
|---|---|---|---:|
| Cheval | 0.35116 / 0.40020 | +0.01466 | 3963 |
| Rice | 0.31824 / 0.36268 | +0.01329 | 990 |
| Eishin | 0.35116 / 0.40020 | approximately zero | 0; fallback used |

Left/right lengths agree within float precision. All three imported skeleton global bases/scales are identity, hip rest bases are identity, and inspected local bone scales are one. All toe vectors extend toward skeleton +Z. Eishin's straight rest knees are not reversed knees: lowering the pelvis 4 cm and solving to the original ankle target produces the intended +Z bend, just as on the other rigs. All six ankle residuals are below 0.0000001 m in this static solve. This validates the basic axes and two-bone geometry, not continuous steering quality.

## Foot and knee frames

All three feet have nonidentity global rest bases: columns `(-X, +Z, +Y)`. Using identity as the desired ankle basis would rotate these feet incorrectly. The current gait's `landing_yaw * rest_foot_basis`, its inverse-yaw transport of planted foot bases, and LegIK's restoration of the requested/rest basis preserve the actual ankle frame. The measured ~0.04-degree rest-basis angle after solving is float quaternion precision, not evidence of visible tilt.

The fixed LegIK pole `Vector3.BACK` is +Z in Godot skeleton space and agrees with the measured anatomical forward direction. Rotating the avatar root carries that pole into world space. Therefore root-yaw steering does not require guessing a new bone axis per character. Large divergence between pelvis/body heading and a planted or leading foot can still cause uncomfortable knee/ankle twist: that is a motion/contact constraint issue. This audit does not establish acceptable twist or velocity at the proposed 72-degree departure boundary. Do not replace the pole with instantaneous screen travel direction without considering planted-leg continuity.

## Eishin calibration omission

Eishin's humanoid feet map to `Ankle_L/R` and toes to `Toe_L/R`. The low shoe vertices are weighted to descendant `Ankle_offset_L/R` and `Toe_offset_L/R` instead. Original source hierarchy confirms:

- `Ankle_offset_L -> Ankle_L -> Knee_L -> Thigh_L -> Hip` (same on right).
- `Toe_offset_L -> Toe_L -> Ankle_offset_L -> Ankle_L` (same on right).

Imported low-vertex weight totals likewise use these four helper names. `_calibrate_soles()` currently includes only exact mapped foot/toe IDs when determining skin binds; Eishin therefore gets zero weighted candidates and falls back to the minimum of the entire mesh. Its recorded floor is -0.002624 m, versus near zero for Cheval/Rice. That numeric difference alone does not prove a visible floor error, but the whole-mesh fallback lacks the intended shoe-only scope and can select unrelated low geometry.

Recommended correction: treat skin joints descending from the humanoid foot/toe joints as foot-owned for sole calibration. Preserve the avatar's helper hierarchy and skinning. This is a pipeline fix, not a reason to rewrite the model or remap all humanoid feet to the skin helpers.

## Retargeting and world-contact scope

The separate UMA bake composes animated helper ancestors before collapsing mapped joints. The runtime consumes normalized rotations and the explicit hips translation path; it intentionally does not reproduce every helper translation. Hip height normalization is valid for the inspected baked root-hips inputs and these target rigs, not arbitrary VRMA hierarchy/scale conventions.

Current gait contacts are cached in skeleton coordinates and transported by inverse avatar yaw around the stable pivot. For the measured identity imported skeleton transforms, this is consistent with preserving world contacts through root yaw; it remains dependent on matching the host's actual yaw pivot and desktop displacement compensation. These assumptions belong in the final per-frame contact probe. Static rest measurements cannot approve abrupt reset removal, continuous knee velocity, actual skinned-shoe contact across a turn, or naturalness.

Reproduce from repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/leg_rig/probe.gd
```

Source assets were read only. Runtime gait is being revised concurrently; these findings are a rig/axis audit, not acceptance of a frozen movement implementation.
