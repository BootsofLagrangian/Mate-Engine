# Native desktop autonomy

`native/scripts/desktop_autonomy.gd` moves the host window using the visible pet's window-local rectangle. The transparent conversation-panel allocation may extend beyond a monitor only while that panel is closed. Always update the context before movement; an open panel, listening, speaking, dragging, foreground activity, or pointer interaction freezes movement immediately. Resuming waits 2.5 seconds. The module defaults enabled, but starts blocked until the host supplies context.

Curiosity uses desktop geometry and a recent pointer location, plus optional interest observations supplied by the host. It does not recognize desktop content, capture screenshots, inject clicks, or read/write other applications. The future perception hook is `observe_interest(id, global_screen_point, confidence, ttl, kind)`. Entries expire, are consumed on selection, and the queue holds at most 24 entries. Repeated IDs replace earlier observations. Host-owned task locations can use kind `owned_task`; callers are responsible for supplying a meaningful global point.

Movement uses acceleration-limited substeps, braking toward a target, and a 35-second travel watchdog. A reached destination enters a three-second inspection followed by seven seconds of rest. Desktop landmarks rotate deterministically; decisions never generate random per-frame jitter. `set_speed` accepts 20–160 desktop pixels per second (default 75). Interruptions stop immediately to prioritize user interaction; that emergency stop intentionally overrides the normal acceleration limit. A scheduling stall advances expiry/watchdog time normally but integrates at most 100 ms of motion, avoiding a large catch-up jump.

The exact union of usable desktop rectangles determines safety, excluding taskbars and allowing continuous crossings between adjacent monitors, including negative monitor coordinates. A four-pixel margin covers coordinate rounding. Direct paths that cross gaps or leave the usable union are declined. This version does not plan detours around complex monitor arrangements. If no monitor can fit the visible pet and its margin, the module reports `no_space` and stops. Monitor removal or changed avatar bounds may require one immediate recovery clamp once interaction has settled; ordinary travel never teleports. Recovery cannot repair a pet larger than every available workarea, so the host may choose to reduce avatar scale in that case.

## Integration

```gdscript
var autonomy := DesktopAutonomy.new()

# After the window and pet UI exist:
add_child(autonomy)
autonomy.configure(get_window(), func() -> Rect2: return pet_rect)
autonomy.set_enabled(bool(Settings.get_value("autonomy_enabled", true)))
autonomy.set_speed(float(Settings.get_value("autonomy_speed", 75.0)))
autonomy.locomotion_changed.connect(_on_locomotion_changed)
autonomy.state_changed.connect(_on_autonomy_state_changed)
autonomy.target_chosen.connect(_on_autonomy_target_chosen)

# In the parent's _process, before the child processes:
autonomy.update_context(panel_open, is_listening, is_speaking,
    _drag_active, foreground_busy)
autonomy.set_pointer_interaction(pointer_over_interactive_pet_or_handle)
```

The module samples global pointer history itself when configured with a real window. `target_chosen(id: String, screen_point: Vector2, kind: String)` supplies the global destination of the pet's center, suitable for a gaze cue. `state_changed(state: String)` supplies `walk`, `inspect`, `rest`, `settle`, `paused`, or `no_space`. `locomotion_changed(moving: bool, velocity: Vector2)` emits native desktop velocity while moving and zero on stop; the host can select a walk VRMA if available, or its native floating/bobbing fallback. These signals deliberately do not depend on MotionPlayer's interface.

`move_to_interest(id)` is an explicit selection request; it returns false when blocked, settling, stale, too close, or geometrically unreachable. It still uses smooth safe travel. The normal autonomous selector observes decision/rest cooldowns.

## Verification

Run from the Mate-Engine repository:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless \
  --path companion/native --script ../diagnostics/autonomy/test_autonomy.gd
```

Recorded result: **3,636 checks, zero failures**, Godot 4.5.2 stable Linux. The test uses deterministic simulated workareas and never launches a desktop window. Coverage includes negative origins, adjacent monitor seams, disconnected monitors, taskbar exclusion, small/oversized workareas, monitor reconfiguration, speed/acceleration/displacement limits under frame jitter, matching 60/120 Hz trajectories, long frame handling, interaction/panel/listening/speaking/task/drag pauses, settling and toggles, queue caps, future-interest TTL and one-shot consumption, inspection/rest/no-jitter behavior, and the travel watchdog.

This is module-level mathematical/state-machine verification. Windows window-placement behavior, real monitor DPI behavior, the host's context wiring, and VRMA/fallback appearance require integrated desktop validation.

## Optional desktop surfaces

`desktop_surfaces.gd` is a pure geometry extractor. It reads version-1 world snapshots with monitor/workarea rectangles and visible window rectangles (`z=0` means foreground). It emits visible window-top segments after subtracting nearer windows, clipped to individual usable monitors, plus workarea floors and authored horizontal lines. Segments narrower than the requested pet width are excluded. IDs are `source@monitor:segment-index`, stable for unchanged source/occlusion topology and independent of input window order. Splitting/merging a segment may change its ID; contact validation also compares its coordinates and never blindly follows an ID.

The original Unity `AvatarLocomotionController` uses lateral desktop-pixel movement and projected avatar bounds to block screen-edge clipping. The native implementation follows those principles while accepting the new geometry source. It does not import Unity components or infer surfaces from desktop content.

```gdscript
# Optional third callback supplies camera-projected, window-local anchors.
# avatar.contact_anchors().foot/sit are stable rest/root-relative anchors;
# do not feed animation's foot_current diagnostic as the support anchor.
autonomy.configure(get_window(), func(): return pet_rect, projected_contact_anchors)
world_source.snapshot_changed.connect(autonomy.set_world_snapshot)
autonomy.set_surface_mode(true)
autonomy.support_changed.connect(_on_support_changed)

# Optional authored global desktop lines:
autonomy.set_authored_surfaces([
    {"id": "my_shelf", "x1": 100.0, "x2": 900.0, "y": 800.0}
])

# Optional supported pose (only after the host starts a compatible animation):
autonomy.set_contact_pose("sit") # "foot" restores standing; "lean" is hook-only
```

`set_contact_anchors({foot: Vector2, sit: Vector2, lean: Vector2})` can also be called directly. Anchors use **window-local pixels**; surfaces use **global desktop pixels**. The default foot anchor is the bottom-center of `visible_bounds`. `support_changed(contact)` reports `{attached: false, pose}` while detached, or `{attached: true, surface_id, kind, pose, screen_point, local_anchor}` on contact. `get_support_contact()` supplies the current point during lateral travel. Motion should use grounded walk only when `state == "walk"` and contact is attached. `approach` means floating/gliding toward support; it must not be presented as grounded walking.

An unsupported pet settles, chooses the nearest safely reachable surface, and approaches with bounded speed/acceleration. Only after arrival does it become attached. A final contact correction is less than 0.8 pixel. Once attached, walking stays **strictly horizontal on the same segment**; interest points affect lateral targets only. Inspection/rest remain in place. No jumping, stepping between disconnected platforms, gravity simulation, or obstacle-detour navigation is claimed. Window movement, closure, foreground occlusion, stale geometry, or dragging releases contact immediately; after settling, the pet can approach a new safe support without following the moved window by teleport. Pose changes prefer the previous support if that pose still fits safely.

Contact anchors are latched at attachment to avoid chasing animation noise; a material change greater than 24 pixels requests smooth reacquisition. The motion module supplies stable rest/root anchors; current animated foot anchors are diagnostics only. Window-top and authored supports may permit legs below the line for a sitting pose, but the entire visible pet must still fit usable desktop space. A floor sitting pose that would clip below the workarea is declined. The lean anchor/API is reserved for later validated pose/side-surface support and is never selected automatically.

Floor supports use the actual usable-area lower edge, and surface mode uses exact pet bounds vertically for contact instead of the free-roam four-pixel margin. Segment ends retain a four-pixel horizontal margin. Floors and authored lines are explicit host support surfaces; window-occlusion subtraction applies to window tops. Monitor clipping is conservative: a window top spanning two monitors becomes separate segments and grounded walking does not switch between those segments.

World-source success must refresh snapshots at least every five seconds, even when geometry is unchanged. Stale geometry discards window supports while keeping monitor floors. An unavailable-source `{}` snapshot also keeps a floor fallback. The module remains compatible with free roaming when `set_surface_mode(false)`.

Additional verification:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless \
  --path companion/native --script ../diagnostics/autonomy/test_surfaces.gd
```

Recorded result: **769 checks, zero failures** in `surface-test-results.txt`. Tests cover foreground occlusion/splitting, stable IDs, negative coordinates, monitor clipping, taskbar floors, authored surfaces, width/scale filtering, grounded horizontal motion, exact foot/sit contacts, moved/closed windows, drag detach/resume, interrupted approach, new occlusion, scaling, stale source expiry, and unavailable-source floor fallback. The original 3,636 free-roam checks still pass. These tests do not validate actual Windows helper geometry, rendered foot placement, or integrated posture transitions.

Surface coordinate boundary: consume DesktopWorldSource output in Godot DisplayServer desktop coordinates. On Windows the source adapter translates raw Win32 coordinates by the virtual desktop origin; autonomy must not translate again. Negative-coordinate geometry tests remain portable math coverage. Fallback monitor resize and in-progress scale-change regressions are included.
