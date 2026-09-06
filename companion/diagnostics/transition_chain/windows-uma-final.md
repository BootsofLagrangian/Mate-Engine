# Final packaged Windows standing chain

**28/28 checks passed; 4/4 travel phases meet the fixed meaningful-overlap criterion; 3/3 UI action pairs advance and finish.** Renderer: NVIDIA GeForce RTX 4090.

Recorded package: `MateCompanion.exe`, SHA-256 `e15e395292144d0cde9eae00f246ff5adf99f46bd701e1363b41d7f228fc61ff`, 99,642,712 bytes, Godot 4.5.2-stable. `build.json` records stable source during export. This is packaged-runtime evidence: mutable workspace source snapshots are not the runtime identity. The external probe and downloaded character/motion assets are separate inputs; character assets were not bundled. Package identity is taken from the preserved build record, not inferred by hashing today's executable.

The initial probe requested Cheval in local settings but did not verify the post-hello session and loaded model identity. This run is therefore not assigned to a specific character. A later probe revision explicitly selects and records the actual VRM and its hash.

Travel criterion, unchanged: actual trailing-100-ms OS-window speed >20 px/s, yaw rate >10°/s, contiguous sampled interval ≥.25 s and heading change ≥5°. Loading and three explicitly stationary `pair:` phases are excluded prospectively from the travel denominator.

| Phase | Interval ms | Duration | Heading | OS displacement |
| --- | --- | --- | --- | --- |
| idle_to_right | 5690–6576 | 0.886s | 42.67° | 57px |
| moving_reversal | 10040–10918 | 0.878s | 43.27° | 53px |
| left_to_right | 18090–18909 | 0.819s | 38.00° | 51px |
| stop_and_settle | 27370–28264 | 0.894s | 42.37° | 55px |

The last interval is travel **before** user stop. After stop at 28,509 ms, all 134 sampled positions remain (1564,672): independently computed and reported drift both 0 px. Maximum gaps inside qualifying intervals are 61–72 ms; continuity is sampled evidence, not an independent continuous measurement.

The actual panel-button pairs wave→nod, nod→wave and wave→wave retain preview ownership, promote the incoming timeline, and finish naturally. Incoming progress reaches 2.9928/3 s, 3.9922/4 s and 4.0000/4 s respectively before release. Both live timeline clocks strictly increase during each recorded overlap. These records demonstrate temporal overlap, not a claim of photorealistic pose quality.

All 322 owned-viewport images exist with no save errors; 321 match CSV timestamp/state/yaw/window metadata exactly. The sole unmatched capture is the initial loading frame at 623 ms. Captures do not independently verify OS placement or compositor z-order. Raw data: `logs/windows-uma-chain-corridor/{report.json,frames.csv,build.json}`; detailed formulas, input hashes and numeric evidence are in the adjacent JSON.

The earlier `logs/windows-uma-chain` attempt remains 20/28 passing, with failed reversal/travel/stop-precondition checks. Its pause cause is unproven. This successful corridor run must not be presented as a controlled diagnosis or retroactive pass of that attempt.

Separate source review found the dialogue gesture guard still recognized only legacy walk names. A catalog-declared locomotion clip can therefore bypass navigation through a dialogue gesture. The smallest correction is to include declared locomotion capability in that existing guard, retain legacy/sit exclusions, and test a generic newly declared name. No runtime or probe changes were made for this analysis.

Follow-up: root corrected that dialogue guard after the packaged run. The actual-handler regression passes 17 total host checks (including five new dialogue cases); see `diagnostics/locomotion/HOST-REVIEW.md`. This later source change is not part of the immutable package identity above.
