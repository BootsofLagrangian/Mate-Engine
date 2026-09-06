# External motion-chain prerequisite review

Verdict: **APPROVED**, narrow probe-only change. Reviewed SHA256: `f6e1213cec57c570cac9d01cee388b4bba35a0120be78437fd7ba90ac67961af` for `native/tools/probe_windows_motion_chain.gd`.

The retained failed run `logs/windows-motion-view45-current/report.json` shows state `walk` at 33139 ms while the gesture is `idle` and the owned walk ID is empty. At 33155 ms, the injected action is a standalone `wave`, and the host pauses. This supports a prerequisite race: the state notification preceded actual clip ownership. It is not evidence that a correctly dispatched upper-body overlay stops an owned walking loop.

The new `moving_owned_walk()` requires state `walk`, absolute X velocity above 20 px/s, a nonempty owned walk ID, and a matching current gesture. Dispatch waits at most 12 seconds for this condition. The stop case waits at most three seconds for the same prerequisite after the unchanged observation intervals.

The actual acceptance gates remain: upper-body activity and retained walk ownership after 0.5 seconds, more than 10 pixels of actual OS-window X travel, continuing walk state, and exactly zero native-window drift after user stop. Capture, outcomes and gesture-pair checks are unchanged. The bounded wait acquires the stated scenario; it does not relax the measured movement or stop tolerances. A timeout still records failure.

Independent Godot `--check-only` succeeds. The previous failed run is preserved. This approval authorizes interpreting the new probe correctly; only the subsequent Windows run can establish that the runtime passes it. No Windows process was launched or stopped during this review.
