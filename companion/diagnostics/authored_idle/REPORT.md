# Historical Overte motion conversion prototype

This records the initial fallback screening before UMA assets were installed.
Current UMA runtime/acceptance is documented in `VALIDATION.md`; statements
below about no runtime changes or rotation-only playback describe this earlier
prototype, not the current authored ambient layer.

Historical first-pass Overte prototype: no installed manifest or runtime changed at that stage. Candidates were research outputs pending
asset selection and contact-aware playback. Source Overte FBX provenance is in
`../../assets/motion-research/overte/download-manifest.json`; Quaternius source
archive/hash/license matches the existing installed CC0 pack.

`native/tools/convert_overte_fbx.gd` imports FBX through Godot FBXDocument and
exports a GLB intermediate. `convert_candidates.py --overte-glb FILE` maps the
Overte humanoid bones and emits VRMA with rotation AND translation tracks intact.
At that stage the runtime consumed only rotations. Intermediates remain
available for source inspection; no root-translation support is claimed.

Eight Overte candidates and Quaternius Sitting_Enter/Exit were evaluated on all
three actual VRMs at 121 positions each: all transforms finite, zero probe errors.
Actual Linux viewport captures were rendered for five positions per clip/rig.
The inspected `overte-idle-candidates.jpg` shows Cheval lookaround, headtilt and
slownod after calibration correction. These are plausible authored upper-body
action candidates; they have not passed continuous production playback review.

Seven Overte exports have a bind-pose calibration sample at zero followed by a
65–73 degree one-frame arm jump. Every candidate was measured separately in
`calibration-frame-report.json`. The converter removes that single 1/30-second
prefix only when every rotation matches rest within 0.001 degrees AND a first
step exceeds 20 degrees. `idle_to_walk` has a continuous 0.13-degree first step
and is preserved. This correction fixes a visibly reproduced initial T-pose,
without smoothing the authored interior.

Full-body rotation-only playback moves the live foot anchor by centimetres for
the Overte candidates and approximately half a metre for the sitting transitions.
Finite transforms therefore do not establish contact suitability. Lookaround,
headtilt and slownod should first be evaluated with an upper-body mask and exclusive
authored head/gaze ownership. Heel pivot, turn, start/settle and sit transitions
require preserved translations and explicit support handling before adoption.

## UMA integration follow-up

Local UMA exports now provide true rest transforms plus authored animation.
`bake_humanoid.py` folds animated helper parents into 52 mapped joints at 60 Hz,
with explicit ×100 unit correction for the AssetStudio FBX/Godot path. Canonical
Unity rig JSON verifies metres. All mapped translations are preserved in the
converted files; runtime consumes hips translation only, retaining target bone
lengths elsewhere. Retargeted world positions are consequently not an exact
reconstruction of every source joint, and final leg IK intentionally changes legs.

The runtime now has a separate authored ambient layer: continuous base phase,
finite entry/loop/exit actions, exclusive authored head ownership with an explicit
attention crossfade, normalized hip translation, and final two-foot contact IK.
Foreground gestures, navigation, non-standing contact, disabled idle and host
suspension suppress this layer. It never signals a dialogue gesture.

`uma_home_idle` is the quiet base. Character-specific variants are sustained
expressive poses; the installed finite `_idle_action` aliases combine their actual
entry, loop and exit clips. Largest measured join mismatch is 0.110 degrees.
Only the quiet generic base is tagged `ambient:true` in the local catalog.
`uma-ambient-rigs.jpg` compares all four poses on all three rigs; source binaries
and derived images remain local, while conversion tools and metadata are reusable.

Overte remains a fallback, not an installed selection. Walking/turning sources
have not replaced the independently validated contact-aware gait/turn runtime.
