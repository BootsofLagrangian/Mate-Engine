# Main presentation integration review

**APPROVED within the reviewed scope.** Compared main, settings and backend send changes against `3107e1ab`, and inspected the independent panel window and view-control signal paths. Prop compositor/refresh code was under separate development and is excluded.

The [targeted probe](test_main_projection.gd) invokes actual main `_frame_avatar`, `_apply_view_settings`, `_update_avatar_transform` and reset methods on all three real rigs. It suppresses main's network/UI/autonomy/props setup. [Results](main-projection-results.json): **756 pivot cases, zero failures**, maximum screen error **0.0000864 pixels**. Cases cover seven yaw angles including ±90°/±180°, pitch −60°/0°/70°, zoom 0.6/1/1.6, scale 0.6/1 and both foot/seat pivots, with height +0.5 m. Reset restores all four defaults. A client with logical state `open` but an actually closed WebSocket rejects sends.

Main correctly applies zoom to both orthographic size and anchor offsets, transforms camera placement with the roll-free orbit basis, and uses camera depth to preserve the selected avatar pivot. The seat-pivot checks establish projection only; they do not establish furniture contact. Motion receives view yaw for subsequent screen-relative heading requests. The head handle uses projected head position and is clamped to the viewport.

Panel content belongs to its native window's viewport. Hotkeys are forwarded with echo suppression and F9 release handling; focus loss cancels held PTT. Opening the panel pauses autonomy synchronously and focuses text input. Hiding through the main toggle relies on the native window's focus-exit signal for input release; this review does not independently exercise that OS signal. The panel's explicit close path also emits input release. The startup policy intentionally ignores a stale open-panel preference unless `--panel` is supplied. Settings clamp invalid camera values and update controls without signal recursion.

Walking direct-action events and walking previews use the bounded upper-body API, while cancellation requests its fade-out. Opening the panel normally pauses walking, so an ordinary panel preview will usually use the stationary branch; a branch's presence alone is not evidence of a walking GUI sequence. Upper-body runtime review is recorded [separately](../upper_body_review/INDEPENDENT-REVIEW.md).

Native focus, clear viewport pixels and panel placement require the root's Windows acceptance. Extreme combined zoom and avatar scale can exceed the viewport; exact pivot projection is not a claim that every view keeps the entire character visible. No runtime files were edited during this review.

## Follow-up: explicit input release and Windows dispatcher probe

**APPROVED source-only follow-up.** Main now calls `_release_panel_input()` before hiding the panel. It clears the held-key latch and cancels PTT recording directly; duplicate later focus-exit cleanup is harmless. The focus-signal dependency described above is therefore resolved in the new source. The original 756-case result and its hashes remain unchanged historical evidence; [follow-up hashes](presentation-followup-hashes.json) identify this small reviewed delta.

The external Windows chain probe now accepts view yaw/pitch overrides and records resolved view settings plus actual camera basis. During an already established third walk, it invokes the root's action dispatcher with a wave, waits half a second, and asserts both a live upper-body action with the same owned walk and more than ten pixels of actual window travel. It retains the original total 1.5-second pre-stop interval and stops the overlay before stationary pair tests. Those checks meaningfully exercise **direct root dispatch during native travel**, not concurrent LLM generation or speech. Sampling continues after completed rendered frames; capture cost remains included. Verdict: **APPROVED** for this declared probe scope, pending the root's actual Windows run. No Windows window was launched by this reviewer.

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/desktop_view/test_main_projection.gd
```
