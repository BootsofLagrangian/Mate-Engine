# Automatic continuous cape acceptance

**Do not enable candidate 1.2 as the production default.** The corrected automatic MotionPlayer comparison confirms a closer-hanging cape in some poses, but substantially larger movement during startup, model replacement and standing up. The candidate's largest stand-up tip step is **71.2 mm in one engine frame**, versus a baseline maximum of 26.1 mm. The existing imported settings remain unchanged; this does not establish that the baseline cape is fully natural or collision-free.

The earlier manual/coroutine fixture is [quarantined as scheduling-confounded history](CAPE-CONTINUOUS-HISTORICAL.md). Its 83 mm result is not the basis of this automatic-scheduling verdict.

## Validated scheduling and inputs

`native/tools/probe_cape_continuous_automatic.gd` uses actual automatic MotionPlayer nodes at priority -10. A priority -20 driver issues source events; a priority -5 driver applies the diagnostic host's movement/seat root and records source equality. The render callback only reads/captures. No manual MotionPlayer `_process` is called. Passive SkeletonModifier observers before/after the imported spring modifier record the engine-supplied delta without changing bones.

Across 1,320 engine frames per avatar, there is **exactly one spring callback per frame**. For each avatar, 1,319 callbacks receive engine delta 1/60 second. The sole zero-time callback is at model-replacement source frame 720; it is separately recorded and is not the frame containing the stand-up excursion. The addon still consumes its node delta during that zero-time replacement callback, a separately documented engine-integration issue. There are no doubled spring passes in this automatic comparison.

Both avatars use isolated 3D worlds, identical transforms/cameras and synchronous viewports. Prephysics humanoid local transforms and avatar world transforms match exactly throughout. Source/dependency hashes match between start and finish. Model-generation guards exclude stale callbacks. Candidate arrays and scales survive until the pre-reload and final post-seat snapshots; nonselected spring configuration remains unchanged. The actual heading reaches 1.9198 radians (approximately 110°).

## Sequence and scope

The 22-second source sequence contains authored Cheval idle, UMA walk acceleration, a curved path while turning, deceleration to idle, an interrupted overhead stretch, idle, same-asset model replacement at a translated/scaled placement, authored sit-enter, seated hold, sit-exit and idle. Autonomous idle selection and gaze are disabled; explicit authored idle is retained, with identical scripted events/seeds.

The seated part uses the actual SeatedTransition layer and 0.45 m floor clearance. A diagnostic host applies the layer's source root delta. **No chair/backrest mesh or collision is included**, so this is not full Windows carrier acceptance. The candidate changes only matching cape-chain stiffness/gravity arrays; the original mesh, weights, drag, radii and collider groups are retained. It does not reproduce the recovered source's angular limits, panel connections or extra collider types.

The run records 2,640 total actual spring callbacks and 660 paired render/mesh samples. The mesh sampler selects 114 vertices / 38 Mantle-influenced triangles at the existing every-seventeenth-triangle stride. Sampling occurs inside actual modifier callbacks. The complete paired video is 30 Hz. The renderer is **Linux/WSL Godot 4.5.2, OpenGL Compatibility → Mesa D3D12 → NVIDIA RTX4090**, as reported by `process.log`; this is not a Windows or Vulkan test, nor a production performance benchmark.

## Results

| Phase | Baseline maximum tip step per engine frame | Candidate maximum tip step per engine frame |
| --- | ---: | ---: |
| Initial load | 20.2 mm | 36.0 mm |
| Model replacement | 17.4 mm | 33.3 mm |
| Sit enter | 34.7 mm | 47.7 mm |
| Sit exit | 26.1 mm | **71.2 mm** |

The candidate maximum occurs at source frame 1147 on `Sp_Sh_Mantle0_L_04`, inside the positive-time stand-up motion. It is neither an event boundary nor a replacement refresh. Nearby original captures `frame-0570.png`, `-0573.png`, `-0574.png` and `-0577.png` show the changing cape shape during the rise. The rendered candidate remains closer to the body during parts of walking/overhead motion, but that benefit does not justify this larger stand-up excursion as the default.

During exit, maximum sampled edge-length difference between candidate and simultaneously simulated baseline reaches 59.0%, with minimum area ratio 0.356. These are **cross-condition shape differences**, not strain measured against an undeformed cloth rest mesh, and do not alone prove torn or inverted fabric. No sampled normals oppose the baseline normals; that is not a global inversion/collision guarantee. Internal spring segment length error remains below 0.29 micrometres. Bone-length conservation therefore does not establish garment naturalness.

The baseline's outward spread during torso/shoulder movement and the backrest intersections visible in the separate Windows carrier captures remain unresolved. Larger gravity does not supply missing body/furniture collision or panel constraints. No further parameter sweep or production tuning was made after this comparison.

## Evidence and next boundary

Tracked `cape_continuous_automatic/` contains compact source/configuration records, phase metrics, independent review, hashes, log and twelve selected original PNGs. The full callback/observer/mesh report and paired MP4 are in ignored `assets/research/cape-continuous-automatic/`, identified by SHA256 in the tracked report. `summarize_cape_continuous.py` reproduces phase metrics and distinguishes callbacks from engine frames.

Further work should establish correct zero-time refresh handling, then evaluate a generic constrained garment profile incorporating recovered angular limits, connected panels and correctly transformed collision shapes. Startup relaxation and ordinary action transitions require continuous validation. A full cloth claim additionally requires a suitable simulation mesh, attachments, stretch/bending constraints and render-mesh transfer; the earlier SoftBody proxy is not that costume implementation.
