# Independent external capture review

Verdict: **APPROVED**. Final source hashes are in `review-capture-identity.json`. Scope: external authored-seating and scene-navigation probes plus their diagnostic foot-marker helper.

Each probe connects one `frame_post_draw` observer. The observer records telemetry independently of the coroutine that waits for conditions. Removing image writes from that wait therefore does not skip motion samples. The existing 50 ms temporal gap and continuity gates remain unchanged; actual main/render-thread stalls still increase recorded frame intervals. Captures use an approximately 8 Hz cadence plus phase edges and are explicitly distinct from the per-render telemetry.

Each worker owns a newly read Image and a unique destination. It writes only its private result fields. The main thread joins completed tasks before copying results into shared sample rows, checksums and capture records. At most three image jobs are pending; a full queue records a skipped capture and fails the final capture gate. It does not discard telemetry. Readback stays on the main thread and its cost remains measured. CSV writes are buffered. All jobs drain before sequence analysis and final serialization/exit.

One review finding was corrected: image-save checks previously ran only within completed sequence analysis, so an optional abort-tail capture error could escape the aggregate failure result. Both probes now have a global post-drain check requiring every scheduled record to have a successful save and a 64-character SHA256, in addition to the no-queue-skip gate.

Independent checks:

- Both final probes pass Godot `--check-only`.
- `review_capture_worker.gd` runs two concurrent jobs: one valid PNG and one deliberately invalid path. Four checks pass, confirming completion drain, valid checksum, preserved save-error status/empty checksum, and rejection by the global result predicate. The expected filesystem error is retained in `review-capture-worker.log`; machine-readable results are in `.json`.
- The real foot-marker test passes on three rigs at three source phases with zero difference from the engine's applied normalized rotations and FK. The helper caches four actual, weighted base-mesh vertices and skins their full influences per frame. Its source-local path does not mutate the live pose. These markers are sparse heel/toe diagnostics, not an assertion that every sole vertex contacts the floor.

Recognizing `scene_approaching` alongside `approaching` admits the actual spatial approach state without removing the other orientation/entry/exit requirements. Failed older runs remain retained. The Linux synthetic writer test is a lifecycle exercise, not proof of Windows readback speed or application naturalness. No Windows process was launched or stopped by this review.

## Three-slot burst follow-up

The two-slot candidate encountered one cadence capture followed by two stage-edge captures before the first PNG finished. Increasing the finite capacity to three is approved for this observed burst. The 125 ms cadence, every-render telemetry, 50 ms gates, explicit queue-full failure and global save/checksum checks remain unchanged. New per-row pending depth and aggregate peak depth retain evidence of capacity use. Three raw 1920×1760 RGBA images occupy about 38.7 MiB; this excludes encoding buffers and other process memory. The concurrent valid/invalid save regression was rerun successfully. Earlier two-slot source identities are preserved in `review-capture-identity-two-slots.json`. This approval does not address the separately observed heel/chair-height mismatch.
