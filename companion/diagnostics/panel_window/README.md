# Independent settings window and view controls

`CompanionPanelWindow` owns a separate native modeless settings viewport, with the existing `ControlPanel` reparented intact. It does not resize or draw into the avatar viewport. Normal placement chooses the right/left of the provided global pet rectangle, then above/below; constrained monitors get a clamped rectangle with the least tested overlap. All geometry is in desktop pixels, including negative monitor origins. Host must pass the actual pet global rectangle and current usable monitor area.

Window API:

- `configure(panel: Control, pet_global_rect: Rect2i, workarea: Rect2i) -> bool`: reparent and size the panel, initially hidden.
- `open_next_to(pet_global_rect, workarea) -> bool`: position, show and focus settings.
- `close_panel()`: hide settings, release focus-dependent input, emit `closed` once. Does not quit.
- Signals: `closed`, `hotkey(action: String, pressed: bool)`, `panel_focus_lost`.
- Hotkey actions: `toggle_panel` (F8), `push_to_talk` (F9 press **and release**), `toggle_vad` (F10), `cancel` (Escape). Repeat echoes are ignored. Root handles actions; focus loss/close must release PTT.
- `force_native=true`, `transient=false`, `exclusive=false`; borderless and nonresizable; minimize/maximize disabled. Drag the unused title area to move the panel within its remembered workarea.

Fable CLI actually resumed its earlier frontend session and implemented the panel's full-rectangle layout, close wording, top-level **시점** tab and conversation-first space wording. CLI prompt/transcript/summary are retained under `logs/collaboration/fable-panel-window*`. No camera/projection/settings/main code was authored in this subtask. Root wires application state and camera behavior.

View controls emit existing `setting_changed(key, value)`:

| Key | Range | Default |
|---|---|---|
| `view_projection` | `orthographic` / `perspective` | `orthographic` |
| `view_fov_deg` | 20…80° base vertical FOV (perspective) | 45 |
| `view_distance_m` | 1…12m actual camera anchor distance (perspective) | 3.6 |
| `view_yaw_deg` | −180…180° | 0 |
| `view_pitch_deg` | −60…70° | 0 |
| `view_height` | −0.5…0.5m camera eye-height offset | 0 |
| `view_zoom` | 0.6…1.6× | 1 |

`ControlPanel.set_view_settings(values)` silently synchronizes controls; `view_settings()` reads them; `reset_view_settings()` restores all seven controls and emits one atomic `setting_changed("view_reset", true)`. The host restores all seven persisted defaults before updating projection, avoiding intermediate camera states that could cancel seating. Projection is a string; the other six values are numbers. Unknown projection values are ignored. FOV and distance controls are disabled in orthographic mode, with their saved values retained for switching back. The camera implementation is Face/root-owned: perspective distance moves the actual camera, and zoom is lens magnification with effective vertical FOV `2 atan(tan(base_FOV / 2) / zoom)`. The UI never changes a mesh scale to simulate depth. Space text offers conversation commands first and retains optional manual editors.

Validation:

- `test_panel_window.gd`: **34/0** — usable-area placement, negative coordinates, constrained fallback, native/modeless flags, reparenting to a separate viewport, F9 release/echo handling, close/focus cleanup, unchanged avatar viewport dimensions.
- `test_control_panel_view.gd`: **38/0** — real panel build, full-rect sizing, slider ranges/defaults/events, silent sync, reset, close signal, space wording and 340px minimum layout; projection selection, perspective-only availability, inactive value preservation, FOV/distance events, invalid projection rejection, silent clamping and atomic seven-key reset.
- Existing `native/tools/probe_desktop_objects_panel.gd`: Fable **45/0** after two expected tab-order/wording updates.
- `render_panel_window.gd`: actual Godot 4.5.2 GL Compatibility/Mesa llvmpipe rendered **native window ID 1, embedded=false, 380×720, avatar_viewport_unchanged=true**. Inspected refreshed `native-view-tab.png` and `native-view-perspective-tab.png`; Korean labels, projection choice and all six numeric controls render correctly. The inactive FOV/distance controls dim in orthographic mode. These are UI screenshots, not evidence of actual perspective camera behavior. The Linux diagnostic reads the existing Windows Malgun font solely for the preview because this Linux environment has no Korean font; the font is neither copied nor bundled.

Independent reviewer `astra_face` approved the bounded source design and requested disabling minimize/maximize capabilities explicitly, rather than relying on borderless chrome. Those two properties are now set and asserted by the wrapper test. Final Windows focused-key dispatch, root camera response and app close/reopen behavior remain integration checks.

Fable and Astra initially chose the same diagnostic filename. Both test implementations were retained: wrapper tests remain `test_panel_window.gd`, and the exact Fable UI test was recovered from its recorded CLI command into `test_control_panel_view.gd`; both were rerun after separation.

Projection extension (2026-09-06): Astra authored this narrow UI extension against Face’s agreed camera settings contract. Orthographic remains the default. No main/settings/camera files were edited in this UI task. Actual perspective projection, depth-aware furniture placement, contact retention and projected-floor safety are separate integration checks; passing panel tests does not establish them. Static seating endpoint checks also do not accept the user-rejected sit-down transition; authored motion/choreography work remains separate.

Independent projection UI review: `astra_face` **APPROVED** the final source/API and inspected `native-view-perspective-tab.png`. The agreed FOV/distance ranges, retained inactive values, silent host sync and one-event atomic reset are correct; all controls fit the 380×720 native window. This approval covers the UI; camera semantics still require root/helper integration verification.
