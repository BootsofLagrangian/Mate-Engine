# Walking source comparison — 2026-09-06

This acquisition record distinguishes source conversion from runtime acceptance.
Research outputs are local under `assets/research/walking-candidates/`; original
UMA bundles on `F:` were not changed. The direct-quaternion neutral candidate was
selected after the motion agent's three-rig rendered/contact comparison and an
independent posture screen, then installed as `uma_walk`. Its SHA-256 is
`8f0b44c9fbee138f9923185a6dc373e0a11349c7d20c523163c941ebfe329573`.
The catalogue marks it as locomotion, priority 50, with bounded authored hips
preservation; the backend's real `MotionAssets.catalog()` validates the installed
file and publishes all three fields. Native Windows host verification is separate.

## Actual candidates

| Candidate | Duration | Source and intended comparison |
| --- | ---: | --- |
| `uma_homewalk_direct.vrma` | 1.300 s | Original Unity quaternion curves, avoiding FBX Euler interpolation entirely |
| `uma_homewalk_filtered.vrma` | 1.300 s | Generic UMA home walk, re-exported with FBX Euler continuity filtering |
| `uma_homewalk_up_filtered.vrma` | 1.300 s | Original `homewalk01_U_loop`; do not infer the meaning of U from its name |
| `uma_homewalk_down_filtered.vrma` | 1.300 s | Original `homewalk01_D_loop`; same semantic caution |
| `uma_walk_enter.vrma` | 2.033 s | Original `walkin01`; unfiltered research conversion, not a continuous walk |
| `uma_walk_exit.vrma` | 3.433 s | Original `walkout01`; unfiltered research conversion, not a continuous walk |
| `walk_fwd.vrma` | 0.967 s | Official Overte ordinary forward walk |
| `walk_short_fwd.vrma` | 1.333 s | Official Overte short forward steps, relevant to slow desktop travel |

The UMA FBXs originate from the preserved
`assets/research/uma/export-work/natural-subset/manifest.json`. All five initial
outputs used the existing `convert_overte_fbx.gd` importer followed by
`bake_humanoid.py`, the verified UMA bone map, and `metres_per_unit=100`. That
bake preserves translation and collapses animated helper bones into 52 mapped
humanoid joints. `uma-manifest.json` records source/output hashes; the original
unfiltered outputs remain available for comparison.

## A conversion defect discovered by actual rendering

The first neutral walk rendered with an arm rotating above the head during the
middle of a cycle. This was not a deliberately shy walking style or a first-frame
bind pose. The largest adjacent upper-arm quaternion steps at 60 Hz were:

| Source | Unfiltered left / right | Euler-filtered left / right |
| --- | ---: | ---: |
| Neutral home walk | 29.10° / 39.87° | 1.54° / 1.49° |
| U variant | 1.55° / 1.51° | 1.55° / 1.51° |
| D variant | 30.78° / 30.23° | 0.70° / 0.67° |

The previous AssetStudio reflection helper explicitly set `eulerFilter=false`.
A local copy changed that single export option to `true` and re-exported only the
three walk clips and their skeleton. The resulting files, executed helper,
compiler log and export log are retained under `euler-filtered/`. This repairs an
interior Euler wrap introduced during quaternion-to-FBX conversion. The filtered
result still has at most 2.776° left-arm / 1.604° right-arm difference from the
original neutral clip, so it is not described as an exact reconstruction.
Original decompressed Unity quaternion
curves provide an independent reference through `sample_unity_curves.py` and the
Avatar hash-to-path map in `rig.json`. See `arm-continuity.json`, reproduced by
`python3 companion/diagnostics/walking_assets/inspect_arm_continuity.py`.

The additional `bake_unity_walk.py` candidate replaces every existing GLB rotation
channel with the original Unity quaternion curve sampled at 60 Hz, using the
verified mirror-X basis. It restores three constant source curves omitted by the
FBX path. Its 61 rotation paths all resolve through the original Avatar map; two
additional source hashes absent from that Avatar are explicitly recorded and
excluded. No existing GLB rotation channel may remain unverified. The rest rig
and translation channels are unchanged from the filtered intermediate before
the existing helper-bone collapse. This neutral candidate matches both original
arm quaternion curves within 0.00000382° at those sampling times. The same direct
quaternion replacement applied to the original unfiltered FBX intermediate gives
a **bit-identical final VRMA**, so the final conversion does not depend on the
temporary Euler-filtered export. Run `bake_unity_walk.py` after the documented
local UMA subset export; it creates its FBX-to-GLB intermediate when absent.
The code and
candidate do not assert exact reproduction of unmeasured joints between samples
or of the game's complete animation stack.

The step measurements alone establish neither perceptual naturalness nor gait
contact correctness. All finalists must be rendered on the three VRMs with the
actual gait/contact layer. In particular, a smooth upper body does not prove that
source stride length, phase, hip offsets or landing behavior match desktop travel.

## Official external sources actually inspected

Overte `walk_fwd.fbx` and `walk_short_fwd.fbx` were downloaded from the official
repository at revision `b92036e6cb081666dc46af33c7fe881440e9ba50`, converted with
the existing Overte mapping and calibration-frame handling, and accompanied by
the upstream license. `overte-manifest.json` preserves exact source URLs and
hashes. The official animation documentation associates ordinary and short forward
walking with different travel speeds and specifies gait phase for blending.
[Official animation documentation](https://docs.overte.org/en/latest/create/avatars/custom-animations.html),
[pinned animation directory](https://github.com/overte-org/overte/tree/b92036e6cb081666dc46af33c7fe881440e9ba50/interface/resources/avatar/animations).

The Quaternius Universal Animation Library 2 **free Standard archive was actually
downloaded** through its public free-download flow. Both in-place and root-motion
GLBs contain 43 clips. Their only walk clips are `Walk_Carry_Loop` and
`Zombie_Walk_Fwd_Loop`; the advertised broader library does not establish that
ordinary eight-direction locomotion is in the free subset. Neither is an ordinary
relaxed-walk replacement, so no new default was selected from this archive.
The archive, CC0 license, README and full clip inventory with hashes are preserved
locally. [Creator's library page](https://quaternius.com/packs/universalanimationlibrary2.html),
[free Standard download listing](https://quaternius.itch.io/universal-animation-library-2/purchase).

Mixamo's official site offers motion-captured animations and a logged-in download
workflow. No Mixamo asset was downloaded or assigned a redistribution license in
this work. [Official Mixamo site](https://www.mixamo.com/).

UMA sources and derived clips remain local user-provided material; this record
does not grant redistribution rights. Overte license evidence is Apache-2.0 at
the pinned repository, retained with the research files. UAL2 is explicitly CC0.
