# Independent motion-seam review

Verdict: **APPROVED for the final motion/helper scope**. Separate reviewer context. This review covers MotionPlayer, SeatedTransition and TransitionBoundsMeasure; the concurrent desktop scene host and actual Windows furniture fit remain separate acceptance work. Final hashes are in `review-final-identity.json` and match `optimized-bounds-validation.json`.

## Continuity and ownership

`review_vectors.gd` independently measures angular-velocity vectors, including their directions, around the first rendered handoff frame. It uses actual Cheval and installed clips at 60/120/240 Hz over live wave→bow, live wave→idle, walking upper-body wave→bow, and live wave→seated acquisition. All 12 cases pass. At 60 Hz, direction cosine is at least 0.99847; relative vector error is 3.49% for clip replacement/release, 2.69% for walking-overlay replacement and 9.45% for seated acquisition. At 240 Hz these errors fall below 2.09%, consistent with continuous outgoing velocity followed by intentional deceleration. This is discrete refinement evidence, not a formal continuity proof or a universal motion-quality threshold.

The probe also confirms that full-body takeover retires the upper layer and that cancelling seated acquisition clears its active state and cached outgoing velocities, restores foot ownership, and leaves finite poses. Source inspection confirms quintic ownership endpoints, entry-relative seated idle sampling, unchanged head/body carry caps, and bounded outgoing local arm carry. A preview clears the overlay before its first composed pose through UpperBodyOverlay.apply; stopping the base loop alone can intentionally leave an independent upper layer active.

The implementer's 24 targeted cases, six curved-path cases and 12 seated cases remain correctly scoped. They do not measure every replacement or guarantee natural arm speeds. Fast composed hand returns remain disclosed. Four retained viewport frames were inspected around two ordinary handoffs; static samples do not establish full-sequence subjective naturalness.

## Corrected bounds and final optimization

The initial 13-sample envelope underestimated actual live-wave→UMA-seat acquisition by 6.695 mm on Rice and 3.650 mm on Eishin. The dense exact-skin correction passed nine independent acquisition cases, but increased synchronous uncached preparation to approximately 0.55–1.24 seconds. Both stages remain in `review-bounds-before.*` and `review-bounds-dense-reference.*`.

The final candidate replaces repeated full vertex skinning with cached immutable per-bind influence boxes. For the existing nonnegative, normalized linear blend skinning, each vertex is a convex combination of transformed contributions, so their enclosing AABB is conservative. Unweighted vertices use the mesh transform. Current bone and mesh transforms and visibility are read at measurement time; the cache keeps weak mesh references and at most three model entries. This relies on immutable source mesh/bind data for a model identity, as used by the current loader.

Minimum Y is refined exactly at each sampled pose. Slices are ordered by a lower bound on their transformed contributions. If a vertex can beat the best measured minimum, at least one of its contributions must have a lower bound below that minimum; that candidate evaluates the complete skinned vertex. Duplicate vertex flags only avoid repeated exact evaluation. The refinement preserves conservative X/Z/upward bounds without inventing a lower floor. This is per-pose exactness; the finite time-sampling envelope remains a numerical, selected-motion validation.

Independent final checks:

- `review_bounds.gd`: nine acquisition cases, three rigs × 60/90/144 Hz, all with zero measured geometry overflow. The 90/144 Hz frames are not merely a subset of the earlier dense sampling grid. Results: `review-bounds-optimized.json` and `.log`.
- `review_measure.gd`: 15 actual authored poses across three rigs, compared with the original full-vertex measurement. Each avatar is rotated/scaled and includes an additional unweighted mesh. All cases have zero containment overflow and exactly zero minimum-Y difference. Hiding every mesh returns an empty measurement. Results: `review-measure.json` and `.log`.

Local 3D containment implies projected containment under a valid camera projection with geometry in front of the camera, at any positive avatar scale. This geometric implication does not replace the packaged camera/compositor or furniture-placement test. The bounds concern the same base mesh vertices as the old measurement; they are not a blanket bound for arbitrary blendshape or later runtime topology changes.

## Performance and remaining acceptance

The final reported preparation is **35.5–45.3 ms after immutable input prewarming**, across 12 selected cases. Registration invokes the prewarm path. This is a substantial reduction from the dense reference, but it is not a ≤30 ms guarantee, and preparation still synchronously consumes a measurable frame budget. First-time indexing/loading has separate cost. Root will measure actual Windows frame gaps.

Conservative X/Z and upward expansion can make some previously marginal scene placements reject safely; actual furniture fit remains required. No safety threshold was weakened to obtain this approval. No Windows process was launched or stopped by this reviewer. Obstacle choreography, garment physics and broad subjective naturalness remain outside this review.
