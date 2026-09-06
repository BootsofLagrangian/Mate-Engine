# Independent Windows motion-chain probe review

2026-09-06. **REVISE before acceptance use.** Reviewed `native/tools/probe_windows_motion_chain.gd`; no Windows process launched and no runtime edits made.

The probe uses the normal production scene, public user-intent entry point, real desktop coordinates, and its own viewport. It does not manually step motion or synthesize desktop input. The target points correctly combine the window's global desktop origin with the local projected foot anchor. Normal cleanup cancels its behavior, disconnects the websocket, stops the owned geometry helper, disables autonomy, closes CSV, and restores settings. Readiness failure reaches that cleanup.

Required corrections sent to the coordinator:

1. Assert the character is still walking with meaningful velocity immediately before the replacement and stop commands. The fixed two-second/1.5-second waits can outlive a trip; observing walking before those waits does not establish a walking interruption at command time.
2. The check labelled one explicit superseded outcome uses `any()`. Filter outcomes for the first request ID and require exactly one row with `superseded`.
3. Snapshot telemetry after `frame_post_draw`, before both CSV and conditional PNG save. Currently CSV/ms/state are read before rendering while image/yaw/window are read afterward. `process_frame` is emitted before node processing, so the stored metadata can describe a preceding state. This is material when reviewing the turn/walk boundary. Preserve measured capture timing and describe its overhead.
4. Verify projected desktop foot position at arrival against the requested target. An `arrived` outcome alone verifies the director's report, not that the native window reached the point.

Optional precision: rename readiness from complete motion catalog to required walk/home clips and completed fetches; pending-zero does not imply every catalog asset loaded. Check output-file creation before writing, and preserve separate run directories. A missing runtime dependency can otherwise throw rather than reach normal cleanup.

This behavioral probe does not establish numerical naturalness, knee/foot velocity continuity, or interruption blending quality. Those remain the independent motion metrics and visual-review scope. Prior authored-idle probe approval remains separate.

## Revision review

**APPROVED as revised.** Independently re-read the updated probe: `frame_post_draw` now precedes telemetry and capture; immediately preceding reversal and stop checks require walk state and absolute horizontal velocity above 20 px/s; supersession requires exactly one outcome; both arrivals compare the projected desktop foot against the requested point within 2 px. Required-assets readiness wording is also corrected. The 1.2-second transition deadline remains an explicit behavioral bound, permitting bounded braking/dispatch while excluding a multi-second pause.

This approves the measurement/assertion implementation, not an unperformed run or final motion naturalness. Runtime is being revised separately; final Windows evidence must use the frozen runtime. No Windows run or runtime edits were performed by this reviewer.

## New UI gesture-pair portion

**REVISE completion/ownership assertion.** Actual ControlPanel selections and the button's pressed signal exercise real UI signal wiring for three pairs without external desktop input. Both timeline progress snapshots are taken after frame-post-draw, copied, and reset per pair; >0.05 seconds of progress in each verifies live overlap.

The final inactive-and-preview-false check can also pass a cancellation after brief overlap. Furthermore, preview ownership is checked only while both timelines are present, not through the incoming-only tail. Before claiming sequence completion and ownership until finish, require promotion and incoming progress near its expected performed duration, and preview ownership on every active pair frame. This does not invalidate the earlier movement-only probe approval. No Windows execution or runtime edits by this reviewer.

### UI-pair assertion revision

**APPROVED as revised.** Re-read active-frame preview tracking, per-pair reset, incoming start-time identity, subsequent promotion detection, and maximum promoted progress. Completion now requires observed promotion, progress within 0.25 seconds of the performed incoming duration, active-frame preview ownership, and final release. This closes the brief-overlap/cancellation false positive to that explicitly stated endpoint tolerance. The check does not establish an exact end-event cause; final actual Windows execution remains pending.

## Cursor-aware corridor and transition context

**APPROVED for the bounded probe amendment.** The startup position chooses the opposite horizontal quarter of the current usable screen from the observed pointer. It reads pointer coordinates without warping input or disabling pointer priority. Added state-transition records expose pointer interaction, blocked/panel/audio/mic/foreground/preview state and gesture ownership. Existing acceptance assertions remain unchanged.

This reduces initial interference but cannot guarantee an uninterrupted corridor or prove the earlier failure was pointer-caused. Context is recorded on state changes, not every pointer update. Preserve `windows-uma-chain` as failed evidence; use the new run's actual trace to establish its cause/outcome. On smaller monitors the quarter corridor may leave less target clearance, which existing reachability/arrival checks must still enforce.
