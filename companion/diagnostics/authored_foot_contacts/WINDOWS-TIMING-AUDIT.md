# Independent timing audit of contact-grounded Windows run

Input: `logs/windows-scene-navigation-contact-grounded`. This is a read-only audit of the failed run, not approval of its temporal acceptance. Input hashes and all intervals over 50 ms are retained in `windows-contact-timing-audit.json`.

The two reported finite-phase gap failures are:

| Phase | Wall interval | Render frames | Source clip time increment | Previous sample cost |
|---|---|---|---|---|
| Entering | 23072→23129 ms, **57 ms** | 1204→1205 | 16.667 ms in `sit_enter` | 7.786 ms, including 7.399 ms readback |
| Exiting | 24119→24171 ms, **52 ms** | 1263→1264 | 16.668 ms in `sit_exit` | 0.594 ms, no image readback |

Both are within a continuous authored phase, with the same clip and contact owner on either side. They are not failed ownership transitions or missing probe rows from recording being disabled. The next exiting sample includes 7.218 ms readback, but that readback occurs after its timestamp and therefore cannot account for the preceding 52 ms interval. Concurrent worker/renderer/runtime cost is not sufficiently instrumented to attribute causality.

Larger, separate boundary intervals also exist: facing→entering is **256 ms** (21996→22252, one rendered-frame step), and seated→exiting is **78 ms** (23938→24016, one frame). The current phase-filtered `max_gap` gates exclude these cross-stage intervals. They must not be described as covered by the 57/52 ms finite-phase maxima.

The 1273 ms and 4446 ms gaps cross fixture sequences while recording is paused; 32 and 178 engine frames respectively pass in those intervals. They are not single-render stalls and should not be used as such.

One diagnostic provenance issue was sent to the motion owner: at the first entering row, `transition.time` is zero, but the helper's standalone contact diagnostics still show the last bounds-sampling endpoint with full ownership. Live pose and captured contact references are restored; that stale diagnostic row is not proof of an applied endpoint contact. Restore or clear helper diagnostics after bounds preparation before using the field as live telemetry.

No source, runtime or probe was edited for this audit. The original failures remain valid. No Windows process was launched or stopped.
