# Historical continuous cape fixture — scheduling-confounded

**This manual/coroutine fixture is scheduling-confounded relative to ordinary automatic MotionPlayer. Its measurements must not be used as a production acceptance or rejection verdict. Candidate 1.2 remains unapproved pending the corrected automatic comparison.** It hangs closer to the body in some inspected poses, but the continuous test reveals substantially larger startup/reload movement and a rapid cape-tip movement during the middle of standing up. The existing imported settings remain unchanged. This result does not establish that the baseline cape is fully natural or collision-free.

## Controlled sequence and evidence

`native/tools/probe_cape_continuous.gd` runs two isolated 3D worlds with identical avatar transforms and cameras, rendered synchronously into adjacent viewports. The left avatar uses the current imported springs; the right explicitly opts into the previously documented source-relative candidate with effective root stiffness 2.5 and gravity 1.2. The mesh, weights, imported drag, radii and collider groups are retained.

The 22-second source sequence uses the actual MotionPlayer: authored Cheval idle, UMA walk with acceleration, a curved world path and approximately 110° heading change, deceleration to idle, an interrupted overhead stretch, return to idle, a same-asset model replacement with translated/scaled placement, and authored sit-enter / seated hold / sit-exit / idle. The seated portion uses the real SeatedTransition layer, a diagnostic host applying its source root delta and 0.45 m floor clearance. There is **no chair/backrest geometry or collision in this probe**, and it does not replay the full Windows carrier host.

Automatic ambient action selection and gaze are disabled; the explicit authored idle remains active. Both players receive identical scripted events and a fixed seed. Their prephysics humanoid local transforms and whole-avatar world transforms match exactly throughout. The actual yaw reaches 1.9198 radians, so the turn is observed rather than inferred from a phase label. Model generation guards prevent old callbacks from pairing with the replacement model. Candidate parameter snapshots before reload and after seated exit confirm that the modified arrays persist; nonselected chain configuration is preserved.

The final run contains 1,320 source steps, 660 synchronous rendered/mesh samples and 2,640 actual modifier callbacks **per avatar**. The source and dependency hashes match between start and finish. The sampler selects only Mantle-influenced triangles: 114 vertices / 38 triangles, every seventeenth eligible source triangle. All geometry is sampled inside actual modifier callbacks. The video preserves the 30 Hz paired capture sequence.

This probe observes two modifier callbacks within each engine frame, each consuming a node delta of 1/60 second. Independent scheduling research is investigating zero-time skeleton refresh passes versus time-advancing passes; the two-pass observation must not be generalized to every production scheduling arrangement or used to silently retune the engine. The report retains source frame, engine frame, callback count, delta and both tail states. It does not equate one callback with one displayed frame.

## Observed limits

| Phase | Baseline maximum net tip movement per engine frame | Candidate maximum net tip movement per engine frame |
| --- | ---: | ---: |
| Initial load | 22.4 mm | 71.9 mm |
| Model replacement | 21.8 mm | 66.0 mm |
| Sit exit | 28.8 mm | **83.1 mm** |

The candidate's largest sit-exit displacement occurs at source frame 1144, inside the authored motion, on `Sp_Sh_Mantle0_L_04`. It is not the frame that starts the action or replaces the model. Per-callback maxima are smaller because the displayed frame includes two spring passes: 43.3 mm candidate versus 25.3 mm baseline during exit. The result is therefore preserved both per callback and per engine frame.

The continuous renders show a closer-hanging candidate during parts of walking and overhead motion, followed by faster cape movement during stand-up. The maximum sampled edge-length difference between the simultaneously simulated candidate and baseline reaches 49.2% during exit, with minimum triangle-area ratio 0.408. These are **cross-condition shape differences**, not measured strain relative to an undeformed cloth rest mesh, and they do not alone prove torn or inverted cloth. No sampled normals opposed the baseline normals; that is also not proof of global collision freedom or absence of every triangle fold. Internal spring segment length error remains below 0.35 micrometres, demonstrating that bone-length conservation alone is insufficient for garment appearance acceptance.

The supplied baseline still spreads outward when the torso/shoulders move during entering and exiting. The Windows carrier screenshots additionally show backrest intersection. Neither problem is solved by this candidate, and no backrest-collision claim is made here. Greater global gravity is not an acceptable way to hide the missing panel/body/furniture constraints.

## Retained artifacts and next boundary

`assets/research/cape-continuous/comparison.mp4` is the full paired sequence in ignored research output. Its adjacent raw `report.json` preserves actual callback tails/origins and sparse mesh comparisons. The tracked `cape_continuous/report.json` keeps compact source equality, generations, parameter endpoints and raw artifact hashes. `summary.json` derives phase-specific metrics. Selected original PNGs include startup, walking, turn, overhead and dense stand-up samples. `identities.json` and `process.log` identify the source and RTX4090 D3D12 run.

An earlier exploratory run omitted `prepare_scene_locomotion`, so its curved position path did not produce an actual heading turn. Its raw report is retained in ignored `assets/research/cape-continuous/first-run-no-turn-report.json`, with the small source `cape_continuous/first-run-no-turn.gd.txt`, and its turning coverage is withdrawn. The final run fixes this and records actual yaw. It also adds seated transitions and parameter persistence checks.

No production tuning is warranted from this historical fixture. Its double-integrated results cannot establish the candidate's behavior under normal scheduling. Further work should first establish correct time advancement for secondary physics, then evaluate a generic constrained garment profile incorporating the recovered angular limits and panel links, with properly transformed body/furniture colliders. Startup relaxation and action transitions must be checked continuously. A full cloth claim additionally requires a suitable garment simulation mesh, attachments, stretch/bending constraints and render-mesh transfer; the existing separate cloth proxy is not that implementation.
