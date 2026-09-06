# Independent off-axis outline and shared scene follow-up

Verdict: **APPROVED for the off-axis outline correction, main integration and shared World3D lifecycle**, with the raster/compositor limits below. This supplements the earlier spatial review; it is not a claim that every rendered pixel is identical.

The MToon screen-outline branch previously treated off-axis crop projections as symmetric and used the current crop dimensions to determine width. The new opt-in uniform uses the canonical viewport height. Its direction is the derivative of perspective division, `(d.xy*w - p.xy*d.w)`, converted to actual pixel units before normalization. The omitted division by positive `w²` cancels in normalization. Width then converts back through the current viewport dimensions, so a crop retains the same global outline extent as the reference camera. The shader still preserves original view-space Z, retaining the earlier inner-mouth outline fix.

Uniform zero retains the prior guarded orthographic branch. Main sets the value after projection selection to canonical WINDOW_SIZE.y in perspective and zero in orthographic. The helper walks active ShaderMaterial resources and their next passes, avoids duplicate resources and sets only shaders declaring the uniform. A reverse dry-run of the committed installation patch against the installed shader succeeded; the patch and runtime shader agree.

Shared prop windows receive the root World3D and matching antialiasing settings. Duplicate lights/environment are disabled, hidden native prop models become invisible in that shared scene, and orthographic restoration recreates their private world/environment. The previous World3D resource is retained until detachment completes. These changes preserve the existing metric crop geometry and prevent duplicate standalone geometry during contact replacement.

Independent reruns after this delta: perspective/crop 454 checks, actual main three-rig projection 54 checks, actual chair projection plus shared-world visibility/restoration 20 checks; all passed. These are headless geometry/lifecycle tests, not native Windows rendering.

The owner-rendered lit Cheval plus overlapping chairs records **23 mismatches in 166,717 opaque reference samples**. The original strict pixel-equality report still correctly contains a failure. Independently analyzing those exact PNGs reproduced 7 and 16 mismatches in the two crops; all lie on a 3×3 color or alpha transition, with **zero interior mismatches**. Exact coordinates/errors are retained in `lit-render-independent-analysis.json`. This supports a corrected geometric outline with residual boundary rasterization/AA differences; it does not turn the strict report into a pass. The separate imported-chair opaque test remains 150,822 samples with zero mismatches.

Partially transparent edges may blend repeatedly where native windows overlap. Shared scene depth and matching opaque pixels do not establish correct final desktop alpha composition or frontmost-mesh mouse picking. Windows D3D12 visual/compositor acceptance remains the parent’s separate checkpoint. This reviewer made no Windows launch. Facial-expression quality, sitting choreography, floor changes and physical simulation are outside this approval.

Exact reviewed shader, patch, integration and test hashes are retained in `mtoon-source-identity.json`.
