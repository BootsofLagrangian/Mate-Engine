# Independent one-time ground admission review

Verdict: **APPROVED** for `ProjectedAvatarGeometry.nearest_safe_ground` and the `main.normalize_scene_ground_placement` candidate wrapper. Production admission/idle policy and trajectory execution are outside this review.

For fixed world Y, each homogeneous screen edge and the near-plane constraint is linear in the X/Z correction. Taking the maximum residual over the cached swept hull gives a convex feasible polygon for each monitor. The nearest point is either the unchanged origin, an orthogonal projection onto a feasible edge, or a feasible pairwise intersection. The implementation enumerates these candidates and selects the smallest Euclidean correction across monitor solutions, subject to its 0.25 m budget. An already safe point is returned exactly unchanged. The wrapper supplies the canonical camera, actual scale, desktop origin and native workareas without committing movement.

The result requires the entire swept footprint to fit within one workarea; it does not solve a silhouette straddling adjacent monitors merely because their union covers it. Geometry is the existing cached rest hull swept over headings, not arbitrary animated limbs or clothing. Final projected bounds still pass exact workarea enclosure. The 0.001 pixel inward numeric reserve supplements the existing 0.01 pixel hull reserve rather than relaxing the enclosure gate.

The independent reviewer reran the actual three-rig perspective diagnostic: **18 cells passed**, with **181 tested headings per cell**, unchanged world Y, idempotence and smaller-budget rejection. Output is retained as `actual-rig-ground-normalization.json` and its log. This rerun preceded input guards; the valid-input algorithm was unchanged by them.

A separate reviewer-authored closed-form test passed **24 checks**. At 200 px/m, two disjoint monitor admissible regions have distinct known correction distances; the helper chooses the exact nearer region regardless of enumeration order. It also covers negative desktop origins, exact safe-point identity, a too-small correction budget, empty monitor sets, non-finite foot/scale, null or detached camera, non-finite desktop origin, and malformed/empty workareas.

Review identified missing early guards that let invalid camera inputs reach projection dereferences. The owner added structured invalid-camera, invalid-origin and invalid-workarea rejection; the final 24-check run covers these paths. This was API robustness, not a demonstrated normal-main runtime failure.

No Windows process was launched. These geometric tests do not establish natural turning, authored animation quality, actual policy invocation or successful production idle roaming. Exact reviewed source/test hashes and independent logs are adjacent.
