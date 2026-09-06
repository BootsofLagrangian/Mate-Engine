# Orthographic canvas-padding outline review

APPROVED for source/math scope. Independently reviewed the new `_OutlineLegacyReferenceViewportSize` shader uniform, its helper parameter/validation, and the main reference-size call. The helper retains zero as the default outside the explicitly configured root avatar and clears invalid reference sizes. The perspective derivative branch and preserved mouth-depth correction remain unchanged.

At fixed pixels per metre, multiplying projected normal XY by current viewport/reference viewport reconstructs the original reference projection before normalization. Multiplying final NDC extrusion by reference height/current height preserves its pixel displacement. An independent 4,000-case calculation over four viewport sizes and random 2D normal directions reproduced the old 680×760 reference displacement with maximum error 1.28e-13 pixels (common width factors omitted on both sides).

This result assumes the symmetric orthographic camera used by main. It does not establish arbitrary off-axis orthographic-frustum support, Windows compositing, or visual equivalence by itself. The implementation owner's actual render comparison remains separate evidence. The earlier shader-resource replacement control remains inconclusive as recorded in ORTHOGRAPHIC-CONTROL-NOTE.md.
