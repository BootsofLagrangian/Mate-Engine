# Orthographic desktop camera math

[DesktopView](../../native/scripts/desktop_view.gd) keeps screen anchors solvable across orbit angles by using camera depth as the third coordinate. Camera-taking helpers require an orthographic `Camera3D` inside a viewport. They delegate projection to Godot, preserving its viewport, aspect and camera-offset behavior.

`clamp_settings` accepts yaw −180…180°, pitch −60…70°, height −0.5…0.5 m and zoom 0.6…1.6; defaults are 0/0/0/1. Nonfinite values use defaults. `orbit_basis` gives a roll-free camera basis. Positive pitch raises the eye. Height adds world-up displacement to the nominal orbit eye before looking at the fixed target, so it changes effective elevation rather than panning. `orthographic_size(base_size, zoom)` supplies the adjusted camera size; host code owns camera placement and anchor offsets.

Use `screen_to_world_at_depth(camera, pixel, depth)` for a stable screen anchor, or `screen_to_world_at_reference_depth` to retain a reference point's depth. `depth` measures positive distance along camera forward. `screen_delta_to_world` converts desktop movement into the rotated screen plane. `projection_axes` returns projected world-axis vectors in pixels/metre: a particular world axis can collapse, so callers must not assume its scalar projection is nonzero.

For shared furniture contact, let `offset` be the rotated, scaled vector from the prop floor anchor to its seat, and `seat_world` be the avatar's seat point:

```gdscript
var base_depth = DesktopView.base_depth_for_offset(camera, seat_world, offset)
var base_world = DesktopView.screen_to_world_at_depth(camera, floor_pixel, base_depth)
```

This implements `base_depth = seat_depth - camera_forward.dot(offset)`. When the prop seat's projected pixel matches the avatar seat's pixel, their equal depth gives exact world-space contact. `translation_to_depth` moves a point along camera forward without changing its orthographic screen pixel. Derive the physical floor's world Y from the resulting prop placement; a pixel cannot generally satisfy independently prescribed world Y and world Z as well.

Explicit `solve_screen_at_world_y`, `solve_screen_at_world_z` and `solve_screen_on_plane` return `{ok, point, reason}`. A horizontal view parallel to the floor, or a 90° yaw parallel to a fixed world-Z plane, returns `reason: "parallel"`; callers must handle it. Invalid inputs and intersections behind the camera also fail explicitly. Simple unprojection helpers return `Vector3.INF` on invalid input.

The [projection test](test_projection.gd) checks actual Godot projection at 680×760 across 405 yaw/pitch/height/zoom combinations, including off-viewport pixels, projected axis derivatives, shared-seat coincidence, depth translation and plane degeneracies. [Results](projection-results.json): **5,274 checks, zero failures**, maximum round-trip error 0.000192 pixels and maximum shared-seat error 0.000000826 m. These tests establish camera math, not integrated gait, furniture collision or rendered appearance.

Run from the repository root:

```sh
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native --script ../diagnostics/desktop_view/test_projection.gd -- --output ../diagnostics/desktop_view/projection-results.json
```
