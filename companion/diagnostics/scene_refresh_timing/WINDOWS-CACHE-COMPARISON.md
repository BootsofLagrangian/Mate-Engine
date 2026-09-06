# Actual Windows cache comparison

The new strict run `logs/windows-full-computer-restore-cache` passes 74/74 checks, including one completed computer terminal and the committed five-second ground hold. `windows-cache-comparison.json` contains compact extracted evidence and SHA-256 identities of both original sample/report pairs. No production source changed for this analysis.

| Phase | Prior maximum interior gap | New maximum interior gap |
|---|---:|---:|
| Chair entry | 45 ms | 30 ms |
| Chair exit | 52 ms | 30 ms |
| Computer entry | 84 ms | 26 ms |
| Computer exit | 77 ms | 31 ms |

The unchanged limit is 50 ms. Entry phases contain 79 samples and exit phases 60 samples in the new run. These are within-phase measurements, not an end-to-end frame-time guarantee.

Timestamp-selected computer projection requests during entry cost 44, 47 and 51 microseconds; the two exit requests cost 45 and 76 microseconds. Full-fit count stays at three throughout both phases while cache-hit counts advance. The retained last full-fit cost is 69.772 ms, timestamped at 32196.168 ms of the probe, well before entry at 44718 ms. It is not a recurring cost in these phases. Chair cached requests cost 27–29 microseconds; its prior full fit cost 26.204 ms. Absolute monotonic profile timestamps were converted using report.started_ticks_msec, so publication lag does not assign stale full-fit cost to the wrong frame.

This directly supports the intended mechanism: the half-second projection requests continue, but unchanged geometry avoids repeating the expensive full fit. The old run has no corresponding cost counters, so exact causal attribution of each old gap is not possible. Multiple reviewed changes differ between runs; this is not an isolated randomized performance comparison.

Scene interests remain suppressed with unchanged rebuild counts throughout contact. Full Living refresh costs peak at 57/30 microseconds for chair entry/exit and 41/60 microseconds for computer entry/exit. During contact, object interest observations request these cheap refreshes nearly every frame; they are not all half-second samples. These data do not support the initial scene-routing hypothesis as the dominant observed pause mechanism.

Preparation remains a separate cost: the new computer entry reports 50.829 ms Motion preparation and 51.147 ms total host preparation. That boundary work is outside the interior phase gap comparison. No universal 20 Hz guarantee, garment collision certification or visual-naturalness conclusion is inferred from these timing results.
