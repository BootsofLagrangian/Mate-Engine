# Idle and locomotion asset research — 2026-09-06

## Recommendation

Use the eight installed clips plus restrained procedural layers for the immediate natural-idle improvement. A new asset pack is not necessary to fix repetitive head motion, pose ownership, gaze transitions or abrupt walk blending. Do not make `idle_talking` the continuous ambient default. Keep `idle_natural` as the candidate body base, keep head/gaze under a single owner, and let explicit conversation gestures temporarily replace or mask the corresponding body tracks.

The existing Standard archive has no dedicated standing look-around, turn-in-place or walk start/stop animation. If authored transitions become the next priority, Overte has the most specifically relevant public source files found in this bounded search. They require FBX conversion and a new humanoid mapping; do not treat them as drop-in VRMA or assume visual acceptance from filenames.

No installed motion asset, setup_motions.py, manifest, runtime source or Windows process was changed. Only this report, local numerical evidence and its inspection script were added.

## Installed/archive inspection

Inspected all 43 animation names in `/tmp/mate-ual-standard.zip`, member `Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb`; source SHA-256 `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997` matches the installed manifest. Its License.txt declares CC0 1.0. The creator also publishes the library as CC0 with Godot/Unity/Unreal retargeting exports. [Official Quaternius source](https://quaternius.com/packs/universalanimationlibrary.html).

Measured source **local joint quaternion maximum pairwise excursion**, not global head motion, perceptual naturalness, or rendered rig quality. Angular speeds are adjacent sample geodesic differences / source time interval. Small numerical values have float precision limits. `source-metrics.json` contains the complete eight-candidate result; `inspect_source.py` reproduces it from the original archive when run from repository parent workspace.

| Source / installed name | Duration | Local head excursion / max speed | Arm excursion | Assessment |
| --- | ---: | ---: | ---: | --- |
| Idle_Loop / idle_natural | 2.50 s | 4.40° / 10.81°/s | L 5.94°, R 4.27° | Suitable quiet body base; repeated every 2.5 s will still be recognizable if all layers phase-lock |
| Idle_Talking_Loop / idle_talking | 2.93 s | 9.03° / 65.75°/s | L 33.88°, R 16.20° | Active speech motion; not a quiet ambient loop |
| Sitting_Idle_Loop / sit_idle | 1.67 s | 3.91° / 7.69°/s | L 3.39°, R 2.92° | Existing modest seated base; avoid restarting it on dialogue events |
| Walk_Loop / walk | 1.33 s | 6.69° / 22.24°/s | ~32.80° both | Ordinary visible arm swing |
| Walk_Formal_Loop / walk_formal | 1.33 s | 3.05° / 11.01°/s | L 2.65°, R 3.12° | Quieter upper-body option already installed; low arm swing may read as formal/stiff, so keep character selection |
| Sitting_Talking_Loop / not installed | 2.93 s | 9.03° / 65.75°/s | L 30.49°, R 17.92° | Adds authored seated speech, but not subtle idle variety |
| Sitting_Enter / not installed | 1.30 s | 9.89° / 46.52°/s | L 22.37°, R 32.75° | Real additional transition value if seat pivot/contact is coordinated |
| Sitting_Exit / not installed | 1.03 s | 9.38° / 48.91°/s | L 32.04°, R 65.14° | Same; do not treat as loop |

Idle_Loop has a small endpoint mismatch: head 0.390°, neck 0.163°, pelvis 0.105°. Do not reset procedural phases or snap to identity on each wrap; a small seam blend is justified. Talking and seated idle source endpoints match at measured precision. Parent rotations contribute to world-space head movement, so masking only the head is not sufficient if neck/chest also compete with gaze.

Other Standard idles are torch, pistol, sword, spell, crouch, swim and driving poses. Their semantics/posture do not justify substituting them for relaxed companion idle. Dance/interaction/pickup are already purposeful actions, not ambient variety. The converter intentionally drops translations; a convincing authored weight shift or sit transition cannot be inferred to survive rotation-only conversion unchanged.

## Official-source search

### Quaternius Universal Animation Library 2

The creator offers a free Standard ZIP and lists CC0, humanoid retarget compatibility and both root-motion/in-place versions. Current page notes June 2026 left-foot phase synchronization fixes. It is a compatible next place to inspect, but the public listing does not establish which specific quiet-idle/turn clips are in the free Standard subset; I did not download it or inspect its binary. Do not claim all 130+ advertised clips are free or installed. [Creator's pack page](https://quaternius.itch.io/universal-animation-library-2), [free Standard download listing](https://quaternius.itch.io/universal-animation-library-2/purchase).

### Overte — specific high-value candidates

Verified exact files in the official repository at revision `b92036e6cb081666dc46af33c7fe881440e9ba50`:

- `idle_once_lookaround.fbx`, `idle_once_lookleftright.fbx`
- `idle_once_shiftheelpivot.fbx`, `idle_once_headtilt.fbx`, `idle_once_slownod.fbx`
- `idle_to_walk.fbx`, `settle_to_idle_small.fbx`, `settle_to_idle.fbx`
- `turn_left.fbx`, `turn_right.fbx`
- `idle.fbx`, `idle02.fbx`, `idle03.fbx`, `idle04.fbx`
- seated equivalents include `sitting_idle_once_shiftweight.fbx` and `sitting_idle_once_lookaround.fbx`.

All under `interface/resources/avatar/animations/`. Official docs explicitly identify start/settle and turn-in-place roles; they also describe ordered layering and IK after animation. [Official animation directory](https://github.com/overte-org/overte/tree/b92036e6cb081666dc46af33c7fe881440e9ba50/interface/resources/avatar/animations), [official animation documentation](https://docs.overte.org/en/latest/create/avatars/custom-animations.html).

License evidence: repository LICENSE declares Apache-2.0; its Debian copyright record applies Apache-2.0 to `Files: *`. I found no per-animation exception file in this directory. Preserve upstream copyright/license and conversion notices if adopting; review binary metadata and any additional notices during import. This is source/license screening, not a legal clearance or visual/retarget test. [Repository license](https://github.com/overte-org/overte/blob/b92036e6cb081666dc46af33c7fe881440e9ba50/LICENSE), [copyright inventory](https://github.com/overte-org/overte/blob/b92036e6cb081666dc46af33c7fe881440e9ba50/debian/copyright).

These are FBX assets, not Quaternius GLB. Existing setup_motions.py cannot consume them unchanged. Prioritize just `idle_once_lookaround`, `idle_once_shiftheelpivot`, `idle_to_walk`, `settle_to_idle_small`, and left/right turns if root chooses this follow-up. Retarget and inspect three rigs before adding a new pack to the manifest.

### Official VRoid seven-motion VRMA pack

The official list is Show full body, Greeting, Peace sign, Shoot, Spin, Model pose and Squat. It has immediate VRMA compatibility but does not fill subtle idle/walk-transition gaps, so no acquisition is recommended for this goal. The announcement requires checking BOOTH terms; the BOOTH product page was unavailable to this web tool, so I do not assign it a license or infer redistribution permission. [Official VRoid announcement](https://vroid.com/en/news/6HozzBIV0KkcKf9dc1fZGW).

## Director/motion integration guidance (design proposals, not measured acceptance)

Use long quiet dwell periods and occasional low-amplitude changes rather than continuously stacking several idle oscillators. Sample a gaze target only at an intent transition, ease toward it, hold, then return; never choose a new target each frame. Keep head/neck gaze contribution independent from the ambient body clip, with one explicit additive order. Silence should not trigger the high-speed talking loop.

Retain walk phase through changes of movement speed. Approach a stop with speed and clip weight fading together, and settle around a contact-friendly gait phase; turning yaw smoothly while both feet are planted still looks like skating, so a bounded foot/leg weight-transfer layer is needed if turn assets are deferred. No procedural change should move the camera or OS contact anchor to imitate body motion. Keep a deliberate priority: drag/contact recovery, explicit user gesture, speech, locomotion, ambient body. Restore quiet body motion without resetting gaze/clip phases after interruption.

Suggested first implementation: existing idle_natural as masked body base, rare procedural look targets and mild weight shifts, continuous locomotion phase and eased start/stop; preserve procedural-only fallback when assets are missing. Existing assets suffice for that bounded improvement. New authored clips become valuable specifically for foot-aware turning, gait start/settle, and seated enter/exit—not as a substitute for correct scheduling.
