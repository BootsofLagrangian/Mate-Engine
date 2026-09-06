# Final shared-floor package review

**29/29 chain checks passed; 4/4 travel phases meet the unchanged meaningful-overlap criterion; 3/3 UI pairs advance, promote and finish naturally.**

Package SHA-256: `80303c7e703a5dbd526d343a2ac1ddd64af4b05ea8cbedd44094eb7c6bda170f`. Recorded character selection and actual cached model both identify **Cheval Grand**; model SHA-256 `61e40e14eec93f9bd8124b2a9d3a71aba0e580ee9b2ef4a55dbb6e4ce5d8ef8a`. Renderer: NVIDIA GeForce RTX 4090. Build record reports stable export sources. The runtime is embedded in the package; external probe and downloaded assets remain separate inputs, so absent live workspace source snapshots do not downgrade this to an editor run.

Criterion: actual trailing-100-ms OS-window speed >20 px/s and absolute yaw rate >10°/s, lasting ≥.25 s with heading change ≥5°. Loading and explicitly stationary `pair:` phases excluded; all four travel phases included.

| Phase | Interval ms | Duration | Heading | OS displacement |
| --- | --- | --- | --- | --- |
| idle_to_right | 5445–6297 | 0.852s | 41.16° | 55px |
| moving_reversal | 9929–10686 | 0.757s | 34.87° | 50px |
| left_to_right | 17872–18673 | 0.801s | 39.39° | 51px |
| stop_and_settle | 27190–27993 | 0.803s | 37.74° | 51px |

The stop-phase overlap precedes stop. After stop at 28,276 ms, all 133 samples remain at (1561,672): independently computed and reported drift are both **0 px**. Maximum gaps within qualifying intervals are 73–81 ms; continuity is sampled, not independently continuous measurement.

Wave→nod, nod→wave and wave→wave each have strictly advancing incoming/outgoing clocks during overlap, preserved preview ownership, promotion and natural completion. Incoming progress reaches 2.999718/3 s, 3.999740/4 s and 3.999700/4 s. These measurements establish temporal behavior, not anatomical or aesthetic pose quality.

All 314 own-viewport captures exist and saved successfully. 313 match CSV state/yaw/window metadata exactly; the sole unmatched frame is initial loading at 684 ms. Captures do not independently establish native OS placement or compositor z-order. Raw records: `logs/windows-chain-shared-floor-final`; formulas, counts and hashes are retained in adjacent JSON.

**World-surface retry: 18/18 checks passed on the same package**, in `logs/windows-world-shared-floor-ready`. Its preceding 15/17 run remains preserved: the fixed two-second post-scale delay requested travel while support was still settling. The revised external probe waits up to eight seconds for scale tolerance, attachment to the fixture and actual movement readiness, then retains the travel assertions. This is a probe synchronization correction; it does not change the packaged runtime.
