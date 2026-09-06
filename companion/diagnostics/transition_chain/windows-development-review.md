# Independent Windows development evidence review

**The recorded run demonstrates meaningful concurrent window travel and yaw in all four travel phases.** It is development evidence, not final immutable-build acceptance: `desktop_autonomy.gd` changed between the source snapshots. No runtime code was changed for this analysis.

Input: local [report.json](../../logs/windows-chain-concurrent-development/report.json), [frames.csv](../../logs/windows-chain-concurrent-development/frames.csv), captures and source-before/after snapshots. The [small numeric result](windows-development-review.json) records input hashes, formulas and exact source hash differences. All four non-loading phases were included; none were selected out.

## Agreed thresholds and result

Actual travel speed uses Euclidean displacement of the recorded native window position over the trailing 100 ms, divided by 0.1 s. The earlier position is linearly interpolated between timestamped integer positions. Reported controller `velocity_x` is not used. Absolute yaw rate is the adjacent-sample difference of unwrapped yaw, converted from radians to degrees and divided by actual timestamp delta.

Both speed **>20 px/s** and yaw rate **>10°/s** must hold at consecutive samples for **at least 0.25 s**, with **at least 5°** net heading change. Duration is last minus first qualifying timestamp; the first 100 ms of each phase is excluded to avoid cross-phase history. These criteria match the pre-agreed meaningful overlap thresholds.

| Travel phase | Qualifying interval, run ms | Duration | Heading change | Actual displacement |
| --- | --- | --- | --- | --- |
| Idle → right | 6516–7384 | 0.868 s | 41.335° | 55 px |
| Moving reversal | 10969–11759 | 0.790 s | 39.522° | 50 px |
| Left → right | 18975–19821 | 0.846 s | 38.834° | 52 px |
| Trip before stop | 28328–29120 | 0.792 s | 38.185° | 52 px |

Each phase has one qualifying contiguous run. Maximum gaps between observed samples within these runs are 70, 74, 78 and 74 ms respectively. “Continuous” here means contiguous qualifying observations at the captured cadence, not independently observed motion between every sample.

Raw adjacent-frame moving-and-turning counts are **20, 15, 15, 15**; the trailing-window counts are **17, 15, 15, 15**. Integer window positions and variable frame intervals make these counts quantization-sensitive. They are reported separately and are not the acceptance criterion or a substitute for elapsed duration.

## Functional and renderer alignment evidence

The run reports **19 checks passed, zero failures**, renderer **NVIDIA GeForce RTX 4090**, and **0 px** window drift after user stop. The CSV independently retains the single position `(925,672)` from the stop/settle transition at 29398 ms onward. The overlap interval for that phase occurs before stop, not after it.

There are **1,214 CSV samples** and **182 saved viewport captures**, all present with zero save errors. **181/182** capture records exactly match CSV timestamp, phase, state, window position and yaw. The unmatched initial loading capture at 1343 ms precedes avatar availability; the capture code conditionally emits CSV rows only once a model exists.

The inspected probe samples after `RenderingServer.frame_post_draw`, writes CSV, and saves the same viewport without an intervening await. Visual inspection of captures `00023`, `00030` and `00052` shows the character changing from a partial rightward heading to a right profile, then facing left during the reversal, consistent with their recorded yaw. This supports alignment of rendered pose and metadata. Own-viewport PNGs do not independently show the window's position on the full desktop; placement evidence comes from the native window position samples. No external compositor timestamp or full-desktop recording was captured. Readback/save overhead is included in this development run.

## Source attribution limit

Of the 27 recorded script hashes, only `desktop_autonomy.gd` differs: before `8ab58a127d541570150bc73d25fb05babb903cb64d130a825d408c048c0cb675`, after `3f3f4a03178aeaae6b43c7104bd2f56ba3d6b27d06049745f69c65ea8d579ad1`. A disk edit does not itself prove the running script reloaded; these snapshots cannot establish exactly which version was loaded at each point. The probe script itself is not among those 27 hashes. Preserve this result as observed development behavior, and use a frozen-source run for final release attribution.
