# Clothing shape takes priority over eliminating proxy overlap

Extra hand/forearm spring contacts are **off by default**. Ordinary `VrmAvatar` loading preserves the imported/authored spring groups and does not append new hand proxies. The diagnostic API `configure(avatar, true)` explicitly enables an experimental response; there is no default all-chain hard push. Actual garment cloth remains an isolated optional experiment.

The initial contact review checked lifecycle, length conservation and endpoint clearance but did not establish clothing quality. A deeper user-requested review found two measurement issues and a real stability concern:

1. The first fixed-step comparison disabled Godot's SkeletonModifier without restoring nonhumanoid local bone poses between ticks. This fed the preceding secondary pose back into the spring's authored pose. Those reports remain historical and their appearance/stability interpretation is withdrawn.
2. With every bone's prephysics pose restored before each tick, Rice's authored walk had a maximum spring-tail step of 26.9 mm with original springs and 115.6 mm with unrestricted extra contacts. Clearing every endpoint was therefore an inadequate acceptance criterion. `hard-contacts-corrected.json` retains this failed candidate.
3. Translated paired-avatar trials were confounded by the importer’s initial-tail center convention, whether placement happened before or after loading. Even identical physics on both twins reproduced the large first-frame difference. Those maxima are not attributed to garment settings. Final quality comparisons use the same physics origin, and the later history rebase independently fixes the translated startup state.

Independent review confirms the corrected manual reset/update matches actual modifier callbacks on Rice/Eishin walk/sit: 1,438 actual callbacks, matching tail positions and global bone transforms exactly. Godot can issue more than one modifier callback between this probe's process-frame waits, so resetting once per actual callback matters.

The remaining opt-in experiment progressively yields when a proxy requests a large angular correction: full response through 2°, smoothly decreasing to zero at 10°. The existing spring integrator supplies authored stiffness and drag. This is an intentionally limited shallow-contact approximation. It permits deep overlap instead of turning a garment panel inside out, and it has **not** been approved as a default collision system. A complete garment simulation needs proper cloth topology, bending/stretch constraints, pins, and body collision shapes.

The normal mini characters continue to use their authored hair/skirt spring groups, which are independent of these optional hand proxies. Their clothing and hair use existing weighted bones and retain normal skeletal rendering. No proxy skirt is substituted for the costume.

Follow-up acceptance compares continuous paired renders and sparse spring-influenced skinned triangles, including silhouette displacement, edge-length changes, bone-length preservation, motion versus forced-pose-reset velocities, and settling. A cross-condition triangle normal turning more than 90° is reported as a changed orientation, not automatically a mesh inversion. Numerical bounds alone do not certify that a costume looks natural.

## Startup correction and retained shape evidence

`VrmAvatar.rebase_secondary_physics()` now seeds each spring's current and previous tail from the current posed bone using the same forward-center and fixed-length convention as the runtime integrator. This gives zero artificial initial velocity after retargeting. It preserves every spring resource, state, collider, terminal joint and length. Model loading calls it after the initial pose; the desktop calls it again after final initial placement. Explicit coordinate-frame handoffs may call it; continuous walking/turning must retain inertia.

Independent tests cover all five rigs, scales 0.6/1/1.4, yaw/translation, head poses, idempotence and occupied floor constraints: **1,080 checks, zero failures**. The translated-twin negative control that previously produced 0.9–1.6 m startup differences now agrees within 0.000002 m over 60 ticks. This fixes a real startup deformation, not merely a test tolerance.

The final `quality_revision/shape-rebased.json` uses the same physics origin for both conditions and sequential captures. It samples every 17th spring-influenced triangle at 30 times per six-second cell. Mini baselines have no newly authored spring simulation; mini results use the normal default authored springs with extra hand contacts off. Original-character cells explicitly study the optional shallow-contact experiment; they do **not** represent an enabled production feature.

| Mini rest case | Maximum sampled surface displacement | 95th percentile relative edge-length change |
| --- | ---: | ---: |
| Mambo | 9.6 mm | 0.73% |
| Hachimi | 17.6 mm | 0.59% |

The earlier uncorrected startup maxima were 240 mm and 710 mm respectively. The before/after Hachimi first-frame PNGs show the hair no longer pulled inward. Paired MP4s retain rest, authored walking and sitting sequences; left is baseline and right has authored springs. Each clip shows three seconds of the source pose/motion followed by an intentionally abrupt relaxed-pose reset for settling stress. Render samples are 5 Hz; tail-motion measurements cover every 60 Hz simulation tick. The forced reset's velocity is reported separately from normal motion.

For these six mini cells, spring segment-length error stays below 0.00000023 m, no sampled triangle normal reverses relative to baseline, and tail steps in the final settling second stay below 0.000003 m. Rest surface shape remains close to the original; hair moves more during walking, as expected. The sampled skin mesh is **not inextensible cloth**: across the complete walk-plus-forced-reset/settling cells, local edge-length changes reach 19–38% at the worst sampled edges even though the 95th percentile stays below 1.8%. These surface summaries include the intentional source-pose reset; they are not isolated steady-walking strain measurements. Sparse sampling and a front camera do not prove all triangles or viewpoints are free of clipping. The retained renders support bounded acceptance of these authored spring settings, not a claim of complete garment physics.

The original-character shallow-contact experiments still include sizeable local surface changes during walking, so they remain disabled. No zero-overlap score overrides this shape policy.
