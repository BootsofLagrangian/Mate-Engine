# Additional public VRMA motion assets — 2026-09-06

Eleven CC0 VRMA files are acquired under `companion/assets/research/vrma-public-20260906/` (Git ignored). All eleven load successfully using the current native `VrmaClip` and Godot 4.5.2. This is file/curve compatibility evidence, not rendered acceptance on the three avatars. No runtime, manifest, original avatar, or motion-bank changes were made.

## Sources and provenance

[Sachi VRMA 1, sashii](https://booth.pm/ja/items/6412084) explicitly publishes the collection as CC0. Its author distinguishes Blender-authored animations from TDPT capture converted through BVH to VRMA and edited in Blender. Four files acquired: idle-01, speaking-01, airplane-02, airplane-05.

[Motion pack, rerofumi](https://booth.pm/ja/items/5527394) explicitly offers CC0 VRMA and Unity humanoid clips, allowing modification and redistribution without required attribution. Seven acquired mirror files represent pose, apology, exercise step, phone, drinking, encouragement, and startled reaction. The author also lists a greeting/meeting clip; that eighth clip was not present in the inspected mirror and was not acquired.

The BOOTH download links redirected to login. No login or access-control bypass was attempted. Bytes came from the public CC0 redistribution in [VoxAvatar](https://github.com/SanHsien/voxavatar/blob/2a06be82d1b912c59a3e6d692105af88b162e71a/ASSET_LICENSES.md), revision `2a06be82d1b912c59a3e6d692105af88b162e71a`. Each downloaded SHA256 matches its pinned manifest. Author license statements were independently checked; attribution of these particular mirrored bytes to each author relies on the mirror provenance, not an author-direct byte comparison. `acquisition.json` preserves exact URLs, hashes, sizes, generators, mappings, and license records. Models from that repository were not downloaded.

## Measured suitability

| File | Duration s | Loaded rotations | Practical use / limitation |
|---|---:|---:|---|
| idle-01 | 7.967 | 4 | Nearly static supported bones; source expression/translation channels are ignored. Not a richer full-body idle. |
| speaking-01 | 1.967 | 4 | Very small arm layer; head static in supported rotations. Potential restrained speech overlay after visual review. |
| review-phone | 10.367 | 51 | Gentle contextual phone interaction; provide a prop or deliberately reinterpret the hands. |
| reaction-startle | 11.400 | 51 | Explicit reaction one-shot, not ambient idle. |
| success-cheer | 21.500 | 51 | Expressive encouragement one-shot; energetic arms. |
| drink-water | 23.667 | 51 | Bottle interaction; needs prop/hand attachment. |
| failed-apology | 7.300 | 51 | Prostration; pinned root translation makes grounded playback unsuitable without adaptation. |
| pose-motion | 19.967 | 51 | Deliberate pose sequence; large motion, not quiet idle. |
| exercise-step | 2.267 | 51 | Requires step/foot-height adaptation; current rotation-only playback loses elevation. |
| airplane-02 | 7.458 | 52 | Large whole-body motion; retain for preview, not automatic ambient selection. |
| airplane-05 | 43.708 | 52 | Long whole-body motion; retain for preview, not automatic ambient selection. |

Rerofumi files omit `specVersion` but retain the dictionary humanoid schema and float LINEAR rotation accessors that the current loader supports. This loader success does not establish full modern VRMA-spec conformance. All root translation, expression, and gaze channels remain outside this loader.

The phone clip has head keyframe peak 11.56 degrees/s and endpoint seam 0.41 degrees; drinking has 90.78 degrees/s and 3.90 degrees. Cheer right-upper-arm peak is 668.26 degrees/s. These are source-local, adjacent-key quaternion estimates, not world-head measurements or perceptual judgements; small angles have float precision limits. `loader-results.json` contains all measurements. One-shots need blending and interruption handling; seamless looping is not established by a small endpoint angle alone.

## Existing assets and Uma reference scope

`Assets/MATE ENGINE - Animations/` already has 35 PET_IDLE, 26 PET_SITTING, 17 PET_DANCING, 9 PET_MISC, 7 PET_LOCOMOTION, and further face, pose, intro, sleep, and miscellaneous groups. These Unity AnimationClip files use humanoid muscle curves and root/foot channels. Correct conversion needs Unity humanoid sampling/export; treating muscle scalars as bone Euler rotations would be incorrect. The repository `LICENSE.md` asset clause identifies Shiny copyright, noncommercial/personal/educational use with attribution, and prohibits separate redistribution. These are not CC0 assets.

The official [Uma fan-work guidelines](https://umamusume.jp/derivativework_guidelines/) are not an explicit license to redistribute raw game animations. Official [PakaTube](https://pakatube.umamusume.jp/) is a visual reference source for character-specific timing and gestures. This bounded public search did not establish a redistributable official Uma motion pack. The newly supplied local UMA-Extractor archive is being inventoried by a separate agent and is not duplicated here.

## Integration recommendation

Keep the previously researched Quaternius/Overte motions for baseline idle, look-around, weight shift and locomotion transitions. These new files add contextual interactions and expressive reactions. First preview phone, restrained speaking, startle and encouragement on all three avatars; supply props and root/foot support where required. Do not automatically schedule every acquired clip or treat file-loading success as visual acceptance. Motion integration remains owned by the runtime agent.

Reproduce file-loader check from repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/vrma_public/inspect_loader.gd
```
