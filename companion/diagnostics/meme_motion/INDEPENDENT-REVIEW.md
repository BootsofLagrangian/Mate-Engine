# Independent motion review

**APPROVED for the stated asset ownership, finite lifecycle and existing-rig validation scope.** This is not approval of a universal head-jitter bound, a faithful meme-video reproduction, or the pending new-avatar/Windows visuals.

**Latest disposition: APPROVED within scope after the neutral torso/head revision described below.** Initial measurements remain explicitly first-candidate evidence.

Inspected the three authored definitions, builder, production catalog entries and validation probe. The builder samples the pinned local UMA resting pose, adds quintic upper-body curves, and correctly reverses VrmaClip's normalized-rest conversion when writing quaternion tracks. The resulting assets own no hips, legs, translation, eyes, jaw or expression channels. They retain the source hierarchy/rest transforms and are explicitly derived from local assets. Catalog entries are finite, non-ambient defaults with foot contact metadata. The builder preserves integer catalog fields; all 16 preexisting catalog entries remain deep-equal to HEAD.

An independent rerun with [additional head measurements](independent_head_probe.gd) reproduced **366 checks, zero failures** on Cheval, Rice and Eishin. Eighteen walking-overlay comparisons preserve the baseline hips and feet exactly; ambient-contact, completion, reset and channel-lock assertions pass. [Independent results and hashes](independent-validation.json) retain the full compact measurements. The added instrumentation uses final world orientation, including the skeleton transform, rather than a local head key alone.

That 366-check report and the following derivative table describe the **first candidate**, not the current neutral-base binaries.

| Action | Maximum head speed | Maximum head vector acceleration |
|---|---:|---:|
| mambo_sway | 117.8°/s | 1052.9°/s² |
| hachimi_peek | 118.2°/s | 810.9°/s² |
| playful_shrug | 86.7°/s | 726.7°/s² |

These observations include acquisition, active animation and release over the continuous walking base at 30/60 Hz; they exclude the base clip's initial startup. Sway's acceleration peak occurs 0.30 seconds after overlay acquisition. Ancestor rotations and ownership blending contribute, so the asset's maximum 1.030° baked local step does **not** establish a gentle global head transition. These peaks do not meet earlier quiet/glance bounds; those bounds were not specified for these new playful actions. No post-observation derivative acceptance threshold was introduced. The current README's narrower numerical claims are supported.

The independent probe is a measurement amendment to the author's existing harness, not a second independently implemented simulator. No packaged Windows run or visual acceptance was performed here. New Mambo/Hachimi rigs still require their own validation; old rigs cannot establish their retargeting quality.

## Matched walking control follow-up

[Cheval comparison](first-candidate-baseline.json) records the otherwise identical no-overlay control at 30/60 Hz. Its head peaks are 75.1/76.7°/s and 355.6/681.6°/s², so absolute overlay derivative peaks cannot all be attributed to the new curves. At 60 Hz, the maximum matched head-orientation differences are 24.67° sway, 31.14° peek and 17.28° shrug. At those peaks the world-rest-relative YXZ Euler x/y/z components are respectively −8.86/22.26/5.22°, 1.26/30.48/−6.02°, and −15.27/4.72/−1.50°. The matched control remains near neutral (values retained in the report).

Selected torso/head tracks inherit the sampled source pose while omitted ancestors retain the walking pose. This can break the source pose's ancestor cancellation and add a larger bias than the new curve suggests. The owner is testing neutral torso/head bases while retaining relaxed source arms. This is a bounded asset revision, not a claim that all measured base-walk acceleration is a new asset defect.

## Neutral torso/head revision

The builder now starts torso/head tracks at identity while retaining the relaxed UMA shoulder/arm base. The independent [Cheval 30/60 Hz rerun](neutral-head-comparison.json) passes 132 checks. At 60 Hz the matched maximum head difference falls from 24.67° to 7.97° for sway, 31.14° to 20.80° for peek, and 17.28° to 10.05° for shrug. Speeds become 77.20/105.83/76.93°/s and accelerations 872.19/747.64/689.08°/s² respectively; the same control is 76.74°/s and 681.62°/s². This supports the intended reduction in inherited pose bias, not a strict global derivative guarantee.

The owner additionally reports 367 checks on the three existing rigs and 250 on the new Mambo/Hachimi rigs, with unchanged input hashes during those runs. Those broader revised-candidate runs were not independently rerun here. Approval remains bounded to asset structure, mask/lifecycle correctness and the measured Cheval improvement; Windows appearance and the owner-run new-rig evidence retain their separate provenance.
