# Independent motion/contact review, 2026-09-06

Verdict: **APPROVED after two fixes** for `motion_player.gd`, `vrm_avatar.gd`, `arm_ik.gd`, and `vrma_clip.gd` in the reviewed local state. Reviewer: astra_head_jitter; implementer: astra_motion.

Two reproduced blockers were corrected:

1. Lean initially reported `contact_reachable=true` before transition blending, while the final hand was 0.313 m from its target on the first frame and 0.109 m away at frame 15. The final code combines solver feasibility with the actual post-transition world hand error below 0.015 m. Independent rerun reports false at those frames and true at frame 29 with approximately 3e-8 m error.
2. A full-body `idle_talking` VRMA overrode the seated lower body while `current_contact_pose()` still returned `sit`. Cheval's knee dropped from 0.859 m to 0.560 m with hips at 0.904 m. The seated contact now masks hips/legs/feet/toes out of the imported overlay. Independent rerun keeps the knee at 0.859 m during talking. Bank wave and imported talking retain the seated lower-body pose.

The expanded `native/tools/probe_contacts.gd` passes independently for Cheval, Rice and Eishin. It checks stable rest foot anchors, 82-degree lateral facing, hanging-leg geometry, seated wave, every-frame seated talking, scaled seat anchors and no premature lean-contact flag. The separate `review_contact_motion.gd` and `contact_review_fixed.log` preserve the reproduction and corrected outputs. Source inspection confirms smooth finite gesture entry/exit blends, rotation transitions at supersession, speed/acceleration-limited lateral facing, arm reach clamping, quiet analytic head motion and combined procedural mouth weight at most 0.6.

Imported-loop endpoint differences were inspected for eight supplied clips: at most 1.20 degrees for `walk_formal`, 0.39 degrees for `idle_natural`, and at most 0.07 degrees for the others. These are endpoint checks, not a blanket continuous-velocity guarantee for all clips or a validation of arbitrary imported VRMA. Cheval sit/lean and Rice side-walk renders were viewed and support plausible contact presentation.

Limits: foot/seat anchors are stable presentation references based on the rest skeleton. This does not establish physical foot locking, friction, collision response, anatomically exact seating, or hair/ear spring stability. Root owns actual Windows desktop integration and final visual acceptance. Earlier head-noise measurements remain scoped to their recorded deterministic scenarios; they were not needlessly repeated for these contact fixes.
