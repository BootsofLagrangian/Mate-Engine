# Independent seated floor constraint review

2026-09-06 — **REVISE/pending lifecycle clarification and focused evidence.** Initial read-only review of floor constraint, avatar cache/modifier callback, canonical measurement and motion activation/clear paths. No runtime edits or Windows execution.

No real skeleton bone length or scale is changed by the constraint. Leg correction uses the existing IK solver; secondary correction projects within the existing spring collision interface. Added/extended terminal lengths belong to Verlet simulation state. Full mesh scans occur during configuration/canonical measurement and diagnostic snapshots, not ordinary per-frame floor solving. Runtime helper-pose capture iterates bones only.

The floor collider transforms the skeleton-space plane into the spring center frame and preserves simulated segment length during projection. Padding includes terminal skin radius. If the plane is unreachable from a segment origin, clamping cannot guarantee penetration-free mesh; the actual measured floor check remains necessary. Radius lookup in collision currently matches joints by approximate length within a spring state; equal-length joints can receive conservative padding from another terminal. This is not a direct joint-identity guarantee.

Lifecycle clarification required: `solve_secondary_pose()` claims no Verlet history mutation but calls `_ensure_terminal_joints()`, which can append virtual joints and extend/reset live joint tails during canonical measurement. Cleanup removes registered colliders/virtual joints and restores original simulated lengths, but does not restore the original pre-calibration tail histories; it sets previous tail to current tail for extended joints. That may be a deliberate zero-velocity handoff rather than a bug, but it must be described and tested accurately.

Current floor probe checks three rigs at 0.428 m clearance, a limited set of actual post-modifier full-mesh minima, and inactive/cleared clearance after stopping. It does not yet prove original collider/joint counts and lengths are restored, reload leaves no owner references, or calibration preserves history. Requested these bounded checks from motion owner.

The late secondary-cache refresh after 30 samples replaces the cached geometry. Confirm the canonical seat anchor stays stable across that refresh and clip identity remains correctly invalidated/reassociated, so a seated support pivot is not changed by a bounds update. Existing no-full-skin-per-frame property should be retained. Final default-scale Windows floor/contact acceptance remains separate.

## Floor lifecycle revision

**APPROVED for the corrected source/lifecycle scope.** Re-read temporary spring snapshots and restoration around canonical solving: original joint-array membership, lengths, current tails and previous tails are restored. Runtime release removes virtual joints/colliders and returns extended virtual lengths while scaling current velocity about the current origin, rather than jumping back to stale pre-seat history. Floor clear/height change also clears secondary helper cache, sample count, canonical rotations and pending refresh, preventing floor-curled geometry from contaminating subsequent unconstrained seating.

Independently ran the latest lifecycle probe: all three rigs, zero failures. No real bone scaling or per-frame full-skinning was introduced. The equal-length conservative-padding limitation is now documented. The 30-sample geometry refresh remains explicitly bounded rather than continuous bounds chasing; final host/pivot stability and actual physical seating are still the packaged Windows acceptance scope.
