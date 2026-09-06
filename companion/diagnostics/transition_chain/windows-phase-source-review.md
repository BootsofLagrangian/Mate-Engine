# Windows overlap analysis

Observed Windows run; recorded source hashes unchanged, loaded-build provenance still required.

Input: `/home/hard2251/workspace/mate-engine/Mate-Engine/companion/logs/windows-chain-phase-source`. 28 checks, 0 failures; renderer `NVIDIA GeForce RTX 4090`.

Fixed thresholds: actual trailing-100-ms window speed >20 px/s and adjacent-sample absolute yaw rate >10°/s, contiguous duration ≥0.25 s and heading change ≥5°. Loading and explicitly stationary pair: phases excluded; all other phases included regardless of outcome.

| Phase | Sustained overlap | Intervals (ms) | Duration / heading / displacement | Raw quantized count |
| --- | --- | --- | --- | --- |
| idle_to_right | True | 6316–7202 | 0.886 s / 42.169° / 57 px | 22 |
| moving_reversal | True | 10736–11636 | 0.900 s / 42.866° / 57 px | 21 |
| left_to_right | True | 18778–19649 | 0.871 s / 41.594° / 54 px | 21 |
| stop_and_settle | True | 28160–28894 | 0.734 s / 34.447° / 49 px | 20 |

Stationary action-pair phases (outside the travel denominator): `pair:wave->nod, pair:nod->wave, pair:wave->wave`. Their action checks remain included in the reported check total.

Capture/CSV metadata matches: 324/325; image files present 325; save errors 0.
Reported stop drift: 0.0 px. Independently computed stop CSV check: `{"start_ms": 29161, "samples": 68, "unique_window_positions": [[926.0, 672.0]], "maximum_drift_px": 0.0}`.
Changed source hashes: `none recorded`; source snapshot pair present: True.

Contiguous means consecutive observed samples, not continuous independent measurement between samples. Raw frame counts are quantization-sensitive and are not acceptance criteria. Own-viewport captures cannot independently establish OS placement. This analyzer checks metadata alignment, not image content. Source disk hashes do not prove which code was loaded or whether hot reload occurred; final build attribution requires separate provenance. See JSON for exact formulas, intervals, sample gaps and input hashes.
