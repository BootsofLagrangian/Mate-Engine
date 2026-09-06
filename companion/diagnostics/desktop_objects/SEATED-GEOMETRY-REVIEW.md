# Independent seated geometry review

2026-09-06. **REVISE one cache-failure guard; calibration method otherwise approved for the three measured rigs.** Reviewed `seated_geometry_calibrator.gd`, avatar API/cache clearing, main cache/projection consumers, focused probe and all three `/tmp/seated-calibration-render-v2` side views. No runtime edits.

The calibrator composes actual imported skin-bind transforms with canonical posed bones, retains all mesh vertices for posed bounds, and selects a bounded rear pelvis/proximal-thigh region for the seat anchor. It excludes lower-leg descendants and uses a skin-weight threshold plus spatial filtering. The anchor is the minimum selected height with an 8 mm band defining horizontal location. This is a reproducible geometric contact heuristic, not a semantic skin/body segmentation or proof of collision-free seating.

Independent focused run: `SEATED_FAILURES=0`. All three rigs select skinned patches, not fallback: Cheval 594 patch/54 band vertices, Rice 103/10, Eishin 248/22. Rest-bind residual maxima are below 0.0000002 m. Every saved bone TRS is restored, repeated calibration agrees, and the checked scale/yaw transforms preserve the avatar-local anchor. Helper bones begin at rest; `_posed_bones` ownership is saved/restored. Model clearing clears geometry; main compares the current clip instance before reusing it.

**Required fix:** main `_ensure_seated_geometry()` adds `clip_instance` to a possibly empty calibration result before checking `is_empty()`. Empty failure therefore becomes a nonempty dictionary and `geometry.anchor` errors. Require valid anchor and bounds before adding the cache identity, and fail cleanly without publishing an incomplete cache.

The side renders place the cyan plane plausibly at the rear pelvis/thigh underside. Garments/tails extend below that plane; that alone is not an anatomical contact failure. This confirms a plausible calibrated anchor, not the earlier oversized furniture alignment or actual prop collision. The shared-scene host and premium cushion geometry must be checked separately.

Bounds are from the canonical sampled pose, including rest secondary bones, not an envelope of every later spring/gesture/blendshape displacement. Avatar-local storage followed by current global transform is correct for uniform scale/yaw. The pose test checks scale/yaw consumption but does not itself call calibration under every changed transform. Cache identity is clip-object identity; mutating an existing clip object in place would need explicit invalidation if that path is introduced.

## Cache guard revision

**APPROVED as revised for calibration/cache scope.** Re-read the main helper: anchor `Vector3` and bounds `AABB` are validated before attaching clip identity; bad calibration clears avatar geometry and returns false. Cached results are likewise shape-validated before publishing the sit pivot. This closes the required guard finding. Shared-scene object alignment remains outside this approval.
