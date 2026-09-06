# Authored seating and ordinary interaction acquisition

59 canonical VRMA research candidates are present locally: 47 UMA clips, 3
Quaternius UAL1 sitting phases, and 9 Quaternius UAL2 interactions. All map 52
humanoid bones and retain authored translation, including pelvis trajectories.
`acquired-clips.json` records exact paths, durations and hashes. Acquisition is
not runtime acceptance. The motion owner is testing the selected chair sequence
on all three VRM rigs before installing its aliases.

## Selected chair sequence

`assets/research/seating-candidates/uma-canonical/uma_sitdown01_{s,loop,e}.vrma`
contains actual authored sit-down (1.3667 s), seated idle (2 s), and stand-up
(1.0333 s). The pelvis moves from (0.004, 0.882, -0.022) m to
(0.001, 0.538, -0.336) m; knees bend from approximately 30 to 95 degrees.
Source midpoint and endpoints are independently decoded by `inspect_trajectory.py`.
A preliminary actual Cheval render by the motion owner shows hands reaching back
toward the seat. Quaternius instead settles hands on the thighs. This is a
selection preference, not yet proof that every rig/contact configuration passes.

Across all 52 canonical bones, enter→idle and idle→exit endpoints agree within
0.000004 degrees and 0.000000001 m. Exit returns to the enter standing pose within
0.000033 degrees / 0.000000008 m. The idle loop seam has zero measured rotation
change. See `uma01-endpoints.json`. A short runtime blend is still needed when
entering from a different standing/ambient animation.

The canonical CC0 fallback is in `assets/research/seating-candidates/`:
`quaternius_sit_down.vrma` (1.3 s), `quaternius_seated_idle.vrma` (1.6667 s),
`quaternius_stand_up.vrma` (1.0333 s). Its pelvis lowers 0.336 m and moves backward
0.245 m, with an authored preparatory right-foot step. Endpoints match the paired
idle/up source. It is also a finite sequence, not a static seated pose translated
by runtime code.

## Other acquired UMA actions

| Source family | Clips | Durations / numerical screening |
| --- | ---: | --- |
| sitdown01 | S/loop/E | Chair-height primary sequence above |
| sitdown06, sitdown06_01 | 6 | Same .538 m hip endpoint, feet tucked; knees about 117 degrees |
| sitdown02 | 3 | Floor level, hip .061 m; unsuitable as chair source |
| sitdown03 | 3 | Deep squat/kneel candidate, hip .326 m and knees 154 degrees |
| sitdown04 | 3 | Asymmetric low pose, hip .400 m, knees 116/139 degrees |
| sitdown05 | 3 | Low folded-leg candidate, hip .345 m, knees 150 degrees |
| sitdown07 | 3 | Floor level, hip .090 m, knees 143/145 degrees |
| book01 | S/loop/E | 2.933 / 6.600 / 3.000 s |
| diarylook01 | S/loop/E | 4.033 / 2.000 / 3.700 s |
| drink01 | S/loop/E | 1.367 / 2.033 / 1.200 s |
| phonelook01 | S/loop/E | 1.533 / 2.033 / 1.367 s |
| chair01 L/S drink01 | 2 loops | 3.333 / 3.367 s |
| table L/S laptop01 | 2 loops | 8.333 / 8.367 s |
| table L/S study01/02 | 4 loops | 11.333–11.367 s |
| table L eat01 | S/loop/E | 3.967 / 2.033 / .367 s |

Low-pose labels above are inferences from FK, not a substitute for visual
classification. Laptop/study/drink assets are canonical candidates; prop fit and
contact have not been validated. Source L/S suffix meanings are not assumed.

## Public interactions ready for later selection

Nine newly baked CC0 UAL2 clips are in
`assets/research/seating-candidates/public-actions/`: chest opening (1.367 s),
consume (1.333 s), folded arms (2.5 s), rail call/lean (2.5 s each), phone
(2.933 s), rise from lying (1.533 s), yes/no (2.5 s each). They preserve full
source translations and helper hierarchy effects, rather than discarding
translations during conversion. These are authored actions, not generated poses.
No runtime aliases were added for them during acquisition.

Creator sources: [UAL1](https://quaternius.com/packs/universalanimationlibrary.html),
[UAL2](https://quaternius.com/packs/universalanimationlibrary2.html).
The downloaded archives include creator CC0 licenses, copied beside candidates.
UAL2 archive SHA256 is
`4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`.

## Local provenance and conversion

Original read-only asset root:
`/mnt/f/ULTIMA/UMA-Extractor/UmaMusumeToolbox/uma_asset`.
Sources are `3d/motion/event/body/type00/anm_eve_type00_<clip>` plus Cheval's
`3d/chara/body/bdy1089_00/pfb_bdy1089_00` Avatar/rest skeleton. Generic animation
is retargetable; using this rig does not make an action Cheval-specific.
The extracted research manifest records all 48 input hashes and the 47 FBX/YAML
pairs in `assets/research/seating-candidates/uma-actions/manifest.json`.
Local UMA files remain ignored and non-redistributable; they are not CC0.

1. AssetStudio exports skeleton/clip FBX and decompressed Unity AnimationClip YAML.
2. Godot imports FBX into a temporary GLB.
3. `walking_assets/bake_unity_walk.py` replaces imported rotations with original
   normalized Unity Hermite quaternion samples using the verified mirror-X basis
   and exact Avatar CRC-path mapping. This avoids prior FBX Euler wrap corruption.
4. Full animated helper ancestry is collapsed into the 52 mapped humanoid bones
   at 60 Hz. UMA source units use the previously verified 100 factor.
5. All source-authored humanoid translations are retained. FBX translation sampling
   is retained; direct Unity quaternion replacement applies to rotations only.

Five clips initially failed the strict animated-scale check. Inspection found
only `Hand_Attach_L/R` prop-size/visibility curves, outside every mapped humanoid
bone's ancestor chain. The baker now explicitly excludes only such scale channels
from the humanoid output and records the node names; the original intermediate
GLB preserves those curves for future prop playback. A scale track affecting any
humanoid ancestor still fails closed. No humanoid scale was silently dropped.

Reproduce the fixed local subset into empty output directories:

```sh
python3 companion/diagnostics/seating_assets/acquire_uma_actions.py --export \
  --source-root /absolute/new-export --output /absolute/new-canonical
python3 companion/diagnostics/seating_assets/bake_public_actions.py \
  companion/assets/research/walking-candidates/ual2-standard.zip --version 2
```

The replay exporter uses its recorded default FBX Euler filtering setting; direct
Unity quaternion replacement is the final rotation authority. Existing exports
can be reconverted without `--export`. Raw source bundles are never modified.

## Chair pull-out / richer mocap search limits

Bounded filename screening of 17,598 generic UMA body assets and 1,188 event prop
entries found no literal chair-pull, push-chair or chair-movement prop clip. This
is not proof such an action is absent under opaque numbered names. Book01 and
other object actions do have paired `_prop` animation bundles; using their
source attachment transforms is the next appropriate prop integration step.
Home numbered body/prop sets also exist but were not visually classified here.

[Adobe Research HUMOTO](https://github.com/adobe-research/humoto) exposes actual
chair lifting/putting-down and seated laptop/drink mocap examples. Its bundled
Adobe Research License v1.1 restricts use to academic research/teaching; these
were not imported into application assets. Full-dataset access also requires
contact, and no message/request was sent. Public download availability is not a
permissive app license.

[CMU's official motion index](https://mocap.cs.cmu.edu/search.php) includes seated
stand-up/everyday trials, while [HDM05 scene 4-1](https://resources.mpi-inf.mpg.de/HDM05/04-01/index.html)
contains approach/sit/stand/turn sequences. Follow-up primary download/terms
requests timed out, so no claims of acquired or validated clips from those
sources are made. A chair pull-out sequence is still an acquisition gap;
none was fabricated and labeled authored.
