# Independent authored foot-contact review

Verdict: **APPROVED for the measured Cheval/Rice/Eishin seating path**. Mambo miniature exact-contact acceptance remains unresolved. Final runtime identities match `source-hashes.json`; this review does not approve every seat height, character or Windows timing result.

Two defects were found and corrected during independent review:

1. A nonnegative floor-safety term discarded every requested downward correction, preserving existing floating feet. The signed bound now allows safe downward motion.
2. Applying floor priority after a vector-length clamp could exceed the advertised 20%-of-leg-length correction budget. Vertical correction now consumes that budget first, and X/Z use the remaining Euclidean budget. An independently captured oversized diagonal request decreased from 0.212218 m to 0.150271773 m against a 0.150271761 m cap; the residual difference is floating-point rounding. `limited` remains true rather than claiming exact contact.

Independent helper checks use three actual rigs. A deliberately floated foot lowers by approximately 20 mm without penetrating the selected plane, and its foot orientation is preserved. Zero ownership leaves the pose unchanged. An intentionally lifted source pose remains unpinned. Reset clears the captured references. Results are in `review-helper.json`; all checks pass. This deliberate lift is an isolated helper condition, not a claim that every authored clip has been validated.

A fixed-reference Cheval phase query was replayed forward, backward and after a fresh transition-bounds query. Its maximum foot-position difference is exactly zero. Source FK caches are local to a call and read-only; phase queries do not update captured source/live references or take ownership. The bounds sampler restores the actual skeleton, spring and floor state. Results and the earlier failing oversized request are retained in `review-order-bounds*.json`.

Runtime contact uses up to 26 selected support vertices plus two heel/toe markers per side; repeated evaluations can skin these markers more than once per frame. Full foot-vertex arrays are retained for diagnostic measurement and are not iterated in the runtime contact loop. This support selection is validated on the measured motions; it is not a mathematical enclosure of arbitrary shoe deformation.

The implementer's final full-shoe matrix retains 24 normal and 24 scaled/oblique stages, including authored entry, hold, exit and handoff. Both shoes are measured against the initial physical floor. All normal-character cases pass: at most 0.081 mm finite-phase penetration, 0.186 mm hold penetration, 0.724 mm planned-contact residual and 0.340 mm handoff displacement, with no clipped corrections. Source-compatible and fixed 0.48 m rig-local seat heights and source X/Z travel ×1.20 are covered. The largest recorded MotionPlayer processing sample is 1.922 ms; this excludes the full Windows renderer, probe capture cost and preparation/frame-boundary timing.

Mambo's four retained stages fail the strict no-limited-correction gate: 76 limited samples and up to 2.868 mm planned-contact residual. They are not silently discarded or called exact-contact passes. Hachimi was not in the initial matrix; a subsequent separately identified four-stage Hachimi result passes and is reviewed in `PREPARATION-HACHIMI-REVIEW.md`. The rig-proportional floor-height admission fixes the previous miniature rejection, but does not itself establish miniature contact quality.

The retained Cheval contact sheet shows the actual entry/hold/exit arrangement; static frames cannot establish continuous naturalness. Root's packaged Windows tests remain necessary for frame gaps, actual scene placement, seat depth and overall motion quality. No Windows process was launched or stopped by this review.
