# Mate Companion native host (Godot 4.5)

For Windows setup, build and launch, see [Windows 실행](../windows/README.md).
Current measured acceptance and limitations are in [VALIDATION.md](../VALIDATION.md).

Desktop pet host for `companion/engine` (FastAPI, port 8876): transparent always-on-top window,
VRM pet on the right, collapsible Korean control panel on the left, WebSocket conversation,
push-to-talk / VAD microphone, streamed PCM playback, motion bank gestures, imported VRMA
clips and desktop roaming.

Ownership (collaboration): frontend owns `scripts/{main,control_panel,backend_client,session,
settings,motion_bank,autonomy_bridge}.gd`, `selftest.gd` and `tools/{run_selftest.sh,
probe_protocol.gd,run_protocol_probe.sh}`. Motion (`motion_player`, `vrm_avatar`, `arm_ik`,
`vrma_clip`), `desktop_autonomy.gd`, `desktop_surfaces.gd`, `desktop_world_source.gd` and
`platform/windows_world.ps1` are Astra-owned; `addons/`, setup/export/launchers and the backend are
root-owned. The desktop-world architecture and future tool plan are in `companion/DESKTOP-WORLD.md`.

## Pet size (settings `pet_scale`, 0.35..1.25, default 0.6)

- Slider "펫 크기" in the settings tab and the mouse wheel over the pet (one notch = 0.05,
  `AutonomyBridge.wheel_scale`; ignored while dragging or over the panel, which consumes its own
  wheel events). Smoothed like the Unity `AvatarScaleController` (factor 0.1 per 60 Hz frame),
  persisted, and mirrored back into the slider without re-emitting.
- The orthographic camera is fixed per model (`AutonomyBridge.pet_camera`): it looks down -Z and a
  model is `reference_height_px` = (760 − 40 − 30)/1.25 = 552 px tall at scale 1, so 1.25 still
  fits the window. The avatar node is scaled about a **pivot held at a fixed window pixel**
  (`pivot_transform`): the measured rest-mesh sole anchor at the bottom of the pet zone while standing,
  the seat anchor while sitting. Scaling or turning therefore never slides the contact point, so
  the desktop support stays attached. The projected pet rect, passthrough polygon and contact
  anchors are recomputed every frame from the real transform; `fit_shift` nudges the pivot when a
  large seated scale would push the legs outside the window (the module then re-seats smoothly).
- A character change re-frames the camera for the new height and resets the pivot; the new
  projected anchors make the module release and re-seat instead of teleporting.

## Desktop surfaces (settings `surface_roam`, default on)

Surface mode = `autonomy_enabled` AND `surface_roam` (settings toggle "표면 걷기"). The host calls
`autonomy.set_surface_mode(...)`, feeds `DesktopWorldSource.snapshot_changed` into
`autonomy.set_world_snapshot`, and hands the module a third `configure` callback with the
camera-projected, window-local **stable** anchors (`VrmAvatar.contact_anchors()` foot/sit/lean,
never `foot_current`).

- The Windows geometry helper (`platform/windows_world.ps1`, PowerShell child, 1 Hz) is started
  only while surface mode is wanted on Windows and stopped when it is turned off or the app
  closes. It reads window/monitor rectangles only; **no window contents, titles or pixels, and
  no VLM/perception is implemented or claimed**. On Linux/macOS the module keeps the monitor
  work-area floor as its only surface; the settings line "표면 걷기: …" reports source status,
  window count, or the helper error.
- Grounded walk (imported `walk` loop + `MotionPlayer.set_locomotion_direction` side facing) is
  presented **only** when the module state is `walk` and `get_support_contact().attached`
  (`AutonomyBridge.grounded`). The `approach` state (re-seating toward a support) glides/idles
  without a walking claim; decorative camera bob is disabled throughout surface mode.
  Stopping retains the last heading. Opening the panel or entering conversation may request
  a separate return to front through the motion API.
- Manual sit: the "앉기 · 펫 모드" button is enabled only on an attached support when the `sit_idle`
  clip was imported (`AutonomyBridge.can_sit`). It closes the panel explicitly and queues the
  request while the body remains standing. Pointer/dialogue/settle blocking must clear before
  the pose changes; reopening the panel or losing support cancels the pending request. Sitting = `motion.start_contact_pose("sit")`
  (lower body stays seated under later nod/wave), pivot switches to the seat, and
  `autonomy.set_contact_pose("sit")` makes the module release and re-seat the window so the seat
  rests on the window top with the legs hanging below it. Once the seated contact is reported the
  host **holds** the module (context `hold`), so auto-walk pauses until "일어서기"; standing
  restores the foot pose, foot contact and roaming. A drag, a character change, turning surface
  roaming off, a lost support (window closed/moved/stale geometry) or a `no_surface` verdict for
  the seated pose all stand the pet up; the module's own first detach after a pose change is
  expected and not treated as lost support.
- Dragging releases the support (module + host); the window never runs away while the panel is
  open (unchanged). Readable states add 자리로 이동 중 (approach), 닿을 표면 없음 (no_surface),
  앉아 있음 / 앉을 자리로 이동 중 while seated.
- Not claimed: jumping or stepping between platforms, leaning (needs a validated 3D hand target;
  the lean anchor is projected but never selected), any reading of
  screen content.

## Turning and displacement-driven gait

Walking sources declare `locomotion`, `locomotion_priority` and optional
`locomotion_preserve_hips` catalogue capabilities. The host selects the highest
priority loaded loop; the original CC0 walks remain fallbacks. The installed
`uma_walk` uses the original UMA neutral home-walk quaternion curves, preserving
its upright head, arm motion and centered hip sway. Hip motion is bounded before
final contact IK. See [source conversion and comparison](../diagnostics/walking_assets/REPORT.md).

An accepted destination calls `MotionPlayer.prepare_locomotion`; replacing a
destination updates it even during an existing turn. DesktopAutonomy uses a short
0.25-second anticipation and `locomotion_ready()` first-step gate. The body gains
at least 10 degrees of heading lead and starts travelling with up to 72 degrees
of turn still remaining; the turn continues during movement. Already aligned
destinations can depart directly. A six-second readiness timeout and immediate
input preemption remain. Departure speed builds over one second.

`DesktopGait` owns both angular and linear travel, alternating planted contacts
and lifted feet along X/Z arcs while compensating stance contact with leg IK.
`TurnStepper` handles explicit in-place `face_front()` requests. The two solvers
never compete for travelling legs. This uses 3D rig geometry within the existing fixed
orthographic projection; it does not create arbitrary 3D navigation or perspective
depth scaling. Support, scale changes, preview ownership and cancellation remain
separate from decorative posture. See the measured scope and retained development
attempts in [`diagnostics/transition_chain`](../diagnostics/transition_chain/README.md).

Finite bank gestures can also overlap through
`MotionPlayer.play_gesture_sequence(first, second, lead_seconds, preview)` and the
motion tab's **두 동작 이어보기** controls. Both timelines keep advancing during
the overlap; head, arms and torso blend independently. Incoming playback retains
its elapsed time at promotion. Root/leg or support-changing sequences wait for
the contact boundary; arbitrary imported VRMA/custom sequences are not yet
supported by this API.

## Desktop roaming (pet mode only)

The **공간** tab adds a chair, sofa or computer desk as a separate transparent
native window. Select an object to rename, resize, hide or remove it; enable
placement editing to drag it. Turning editing off makes the object window ignore
mouse input. Saved objects are restored on launch and parked when no current
monitor can safely contain them.

**살펴보기** uses the normal attention director. **앉기** first approaches on the
current support, then fits the seat anchor against a dedicated narrow seat.
**사용하기** requests a finite computer work/contact posture. Object movement,
removal, explicit Stop, character changes and relevant input/setting interruptions
release the interaction. These are local furniture interactions; screen content
recognition, real application input and handheld tools remain separate extensions.
See [the object architecture](../DESKTOP-WORLD.md#placed-furniture) and
[validation](../diagnostics/desktop_objects/).

`scripts/desktop_autonomy.gd` moves the window using the union of usable monitor rects
(negative global origins included) and the visible pet rect; `scripts/autonomy_bridge.gd` is
the host policy, `main.gd` wires it:

- `autonomy.configure(get_window(), func() -> Rect2: return pet_rect)` at startup;
  `set_enabled` / `set_speed` from settings (`autonomy_enabled` default true,
  `autonomy_speed` default 75 px/s, 20..160). Settings tab: "자율 이동 (펫 모드)".
- Every frame the host pushes `update_context(panel_open, recording, speaking, dragging,
  conversation)`; any true value freezes movement immediately. "conversation" = a generating
  turn, audible foreground PCM, any non-idle activity, or the 6 s hold after the last dialogue
  event (`AutonomyBridge.DIALOGUE_HOLD`). The module adds its own 2.5 s settle before moving
  again. Opening the panel also pushes the context synchronously, so the window never runs away
  while the panel is open; roaming is therefore effectively "collapsed pet mode only".
- Pointer near the pet (pet rect grown by 40 px, the ≡ handle, or a drag) pauses via
  `set_pointer_interaction`; the global pointer is used because passthrough hides outside events.
- `locomotion_changed(moving, velocity)` → `AutonomyBridge.locomotion_plan`: with an imported
  `walk` (or `walk_formal`) clip the host starts `motion.play_vrma(clip, speed, loop=true)` once
  per travel (speed from the configured autonomy speed, never from per-frame velocity, so the
  loop is never restarted mid-stride). Without a walk clip the pet floats gently (camera-only
  ±1.2 cm bob, legs stay in idle) rather than gliding in a walk pose. On stop the host stops only
  the loop it started and persists the window position.
- Dialogue owns the body: a chat/utterance/`action`/`done` event drops the walk loop reference,
  so a later locomotion stop never cancels an LLM gesture, and the hold window keeps roaming
  paused. The host never issues gestures per velocity sample (no rapid preemption / head jitter);
  the only roaming gaze cue is a fixed target toward the destination, smoothed by MotionPlayer.
- Readable state (`state_changed` → settings tab "상태:"): 산책 중 / 살펴보는 중 / 쉬는 중 /
  잠시 대기 / 일시정지 / 공간 부족 / 꺼짐 / 패널 열림 · 정지. `Main.autonomy_state()` returns
  the raw module state.
- Perception hook: `Main.observe_interest(id, global_point, confidence, ttl, kind)` forwards to
  the module. **Nothing in the host reads or captures the screen**; callers supply points.
- Window position: `window_x/window_y` are only used when `window_pos_saved` is true and the
  window (inset 40 px) still touches a current monitor (`AutonomyBridge.restore_position`);
  negative coordinates are valid. "창 위치 초기화" clears the saved flag.

## Behavior tab ("행동") and interest points (`scripts/interest_points.gd`)

Frontend half of the liveliness feature: the user names desktop places, the pet may walk over to /
look at them. The panel and `InterestPoints` never move anything; the host (root's behavior layer)
persists the data, publishes the catalog to the backend and decides every movement.

- Settings: `behavior_enabled` (default true, toggle "스스로 행동하기") and `interest_points`
  (`InterestPoints.sanitized_data()`: `{"points": [{id,label,kind,x,y}...], "next_id": n}`).
- `InterestPoints` (Node, ≤ 8 entries): `set_points(data)` sanitizes untrusted/persisted data
  (finite bounded int coordinates, printable ≤ 40-char labels, backend id charset, saved-point kinds,
  duplicates/corrupt entries dropped, cap 8, id counter never rewinds); `add_point(label, pos?,
  kind?) -> id` ("" when full), `rename_point`, `move_point`, `remove_point`, `points()`,
  `get_point`, `position_of`, `catalog()` = `[{id,label,kind}]` **without coordinates**, `rows()`
  for the panel. IDs are `pt_<n>` and never reused. Signal `changed` after every effective edit.
  Coordinates are Godot global desktop pixels (negative origins valid).
- Screen validation: `point_status(id)` = `ready` / `parked` (saved but on no current monitor) /
  `missing`; `reachable(id)` is true only for `ready`. Parked points stay saved, are shown as
  "화면 밖 · 보류", get no marker window and disable 가보기/살펴보기. `screen_provider`
  (Callable → `Array[Rect2i]`) overrides `DisplayServer` screens for tests; `anchor_provider`
  (Callable → Vector2/Vector2i) is the host's "near the pet" origin for new points (staggered
  26 px per existing point).
- Markers: "표식 보기" / adding a point calls `set_markers_visible(true)`. One `Marker`
  (`Window`, 36×46, borderless, transparent, always-on-top, **unfocusable**, pin-only
  `mouse_passthrough_polygon`) per ready point, child of the node; `window.position +
  MARKER_TIP == point` exactly. Dragging uses our own window's mouse events plus
  `DisplayServer.mouse_get_position()` (no global hook); release, focus loss or a close request
  end the drag and commit the tip (`point_placed(id, pos)` + `changed`). Hiding, removing a
  point, leaving the tree or freeing the node frees the windows; a marker's close request hides
  all markers. Markers become real OS windows only when `markers_available()`:
  `DisplayServer.FEATURE_SUBWINDOWS` **and** the root viewport not embedding sub-windows.
  **Required host setting:** the project ships `display/window/subwindows/embed_subwindows=true`,
  and Godot embeds every descendant `Window` of an embedding viewport, so markers would be trapped
  inside the 680×760 pet window. The host must set `get_tree().root.gui_embed_subwindows = false`
  (or the project setting) before showing markers; popups (OptionButton lists, tooltips) then
  become native OS popups, as in the editor. Until then `marker_status().reason` is shown in the
  panel hint and the pins are not created as OS windows. Headless Linux reports unavailable.
- Panel: signals `point_go(id)`, `point_inspect(id)` (host closes the panel and queues the
  intention), `point_add_requested(label)`, `point_rename_requested(id, label)`,
  `point_remove_requested(id)`, `markers_toggled(on)`, and `setting_changed("behavior_enabled",
  bool)`. `bind_interest_points(manager)` makes the list follow `changed`/`markers_changed` and
  applies add/rename/remove/marker toggles to the manager directly; unbound, the host fills the list
  with `set_interest_points(rows)`. `set_behavior_state(text)` / `set_behavior_enabled(on)`
  (no re-emit) / `behavior_state_text(kind, label, enabled)` ("'책상' 쪽으로 가는 중", "'창'
  살펴보는 중", "쉬는 중", "자유롭게 지내는 중", "스스로 행동 끔 · 산책만"). No protocol words
  appear in the UI. Wording keeps the two actions apart: 가보기 walks to the point, 살펴보기 stays
  put and only looks (tooltips, hint and state line say so).
- Screen edges: `point_on_screens` treats x as half-open (`[left, right)`, the right edge column is
  the next monitor or nothing) and y as closed (`[top, bottom]`), so a pin dropped exactly on the
  work-area floor (taskbar top) is a valid, ready target.
- Opt-in real-Windows probe (root runs it; nothing here is verified on Linux):
  `tools/probe_windows_points.gd` loads the actual main scene against the live backend with the
  user's Settings preserved and restored, adds one point next to the pet through the panel, shows the
  actual native pin, writes `logs/windows-points/ready.json` (pid, pet window rect, marker window
  id/rect/tip/grab point, screens) and waits for `point_placed` from an external drag. It then checks
  the exact tip shift, persisted coordinates, coordinate-free catalog, OS flags (unfocusable /
  transparent / always-on-top / borderless), no focus theft, 가보기/살펴보기 → `LivingBehavior`
  intent queue + markers hidden + panel closed, marker window destruction on hide/remove and settings
  restoration; only its own viewport is captured. `diagnostics/liveliness/run_windows_points.py`
  launches the editor binary (or `--packaged` MateCompanion.exe), waits for `ready.json`, verifies
  with user32 that the window under the grab point belongs to that pid with that rect, performs one
  SetCursorPos/mouse_event left drag of that pin only, restores the cursor, and reports
  `report.json`. `--no-input` skips all synthetic input. Headless Linux only parses the script.

## VRMA motion assets (`GET /motion-assets`)

- `BackendClient.fetch_motion_assets()` parses `{motions:[{name, kind:"vrma", duration,
  asset_url, sha256, loop?, description?}]}` via `MotionBank.parse_asset_catalog` (invalid
  entries skipped and reported). A 404/connection failure only leaves a note in the motion tab:
  the built-in Euler bank keeps working.
- `fetch_motion_asset(entry)` caches to `user://motions/<name>.vrma`; a cached file is reused
  only when `FileAccess.get_sha256` matches the catalog, downloads are verified before rename,
  mismatches are deleted and reported. Each download uses its own temp file.
- Verified clips go to `motion.load_vrma(name, path)`; accepted names are shown in the preset
  list as `name ⟐ VRMA 1.3s ↻` with the manifest description as tooltip (never relabelled: the
  dance stays "Celebratory dance"). Bank names win duplicates (same rule as the backend's LLM
  allow-list). `motion.play_gesture(name)` dispatches VRMA names, so server `action` events and
  the preview button work unchanged.
- VRMA data is read-only: the sequence/keyframe composers refuse a selected clip with a
  message instead of inventing empty keyframes; only preview/speed apply.
- "두 동작 이어보기" (motion tab): two selectors over finite built-in bank gestures only
  (`ControlPanel.sequence_candidates()`: no procedural `idle`, no custom/saved motions, no loop
  entries, no contact/support names such as sit/seat/prop/hold, never VRMA clips), a 겹침(초)
  slider 0..1 (default 0.35) and the button, which emits `preview_sequence(first, second, lead)`
  once; the host forwards it to the motion owner's preview-sequence API. Selection survives a bank
  refresh; a dropped gesture falls back to a valid one; a null/empty bank disables the row.
- Idle selector "대기 동작" (settings tab, setting `idle_clip`, default `auto`): items are
  `auto` ("자동 (캐릭터에 맞게)", or "자동 · <description> (<clip>)" once the current character's
  declared `ambient_loop` from the character catalogue is loaded, "자동 (캐릭터 동작 준비 중)" while
  it is not), `""` ("기본 호흡만 (클립 없음)"), and every eligible imported clip
  (`ControlPanel.idle_candidates()`: catalogue `ambient == true` **and** `loop == true`, the legacy
  `idle_natural`, and the character's declared loop). A walk, dance or prop clip is never listed as
  an idle just because it loops. Labels are the manifest description (truncated) plus the clip
  name; nothing is relabelled or hardcoded per character. The saved choice survives catalogue
  refreshes, failed downloads and character switches: a saved clip that is not loaded stays
  selected as "<clip> (아직 없음)" and no `setting_changed` is emitted by refreshes or by the host
  mirror `set_idle_clip(value)`; only a user selection emits `setting_changed("idle_clip", value)`.
  `set_characters()` derives the profile loop from the `ambient_loop` field (`set_idle_profile`
  is also public). The host resolves the actual loop (`Main._apply_ambient_idle`, motion owner's
  `MotionPlayer.set_ambient_loop`); the panel only offers and mirrors choices. Preview of every
  imported clip (eligible or not) stays in the motion tab. `Main.walk_clip()` exposes the imported
  walk name.

## Tests (headless Linux, fake audio driver, no GPU / mic / display)

```sh
companion/native/tools/run_selftest.sh
companion/native/tools/run_protocol_probe.sh 8893 9893   # protocol probe: 59 passed, 0 failed
```

Selftest sections: `[motion asset catalog]`, `[motion asset cache]`, `[vrma local clip]`
(installed CC0 clips parsed through `VrmaClip`, checksums vs the root manifest, walk clip drives
leg bones), `[autonomy bridge]`, `[autonomy wiring]` (real `DesktopAutonomy` in simulation: panel
open never moves, walks only after settle, frozen the same frame the panel opens, dialogue hold,
pointer pause/resume, disable), `[pet scale]` (bounded wheel/slider/smoothing, framing math checked
against a real `Camera3D` projection, pivot invariance under yaw/scale, fit shift), `[surface
wiring]` (real `DesktopAutonomy` in surface mode with a fake window snapshot: approach never
plans a walk, grounded horizontal walk + facing only when attached, drag releases/reattaches,
character-change re-seat, sit lifecycle incl. hold/stand/lost support/floor fallback, status
lines), `[panel: vrma presets + roaming controls]` (scale slider range/sync, surface toggle, sit
button states), `[interest points: validation + persistence]` (id/label/kind/coordinate
sanitizing, JSON round trip, duplicate/corrupt entries dropped, cap 8, ids never reused, catalog
without coordinates, parked vs ready on negative-origin monitors), `[interest markers: geometry +
lifecycle]` (tip == point, pin polygon, hidden marker nodes in headless, drag grab offset/commit,
focus-loss/close cleanup, delete/hide/exit/free cleanup, parked points get no window), `[panel:
behavior tab]` (behavior toggle/state wording, bound manager add → markers on → rename/remove,
go/inspect only for reachable points, full list, unbound request signals, CJK width budget,
floor-row/right-edge screen rule, inspect-vs-go wording, Windows probe parses), `[panel: idle
selection]` (eligible-only candidates, description labels, placeholder for a missing saved clip,
catalogue/character round trips without emitting, user selection emits, preview list intact),
`[pet scale on rig]` (real Cheval Grand VRM: foot anchor on the foot pixel at
0.35/0.6/1.25 and ±82° yaw, body fits the window, seat pivot keeps the seat pixel while the legs
drop). The probe adds real `GET /motion-assets` + download + sha256 + `load_vrma` + `play_gesture`
dispatch against the running engine.

What these do **not** prove: Windows transparency/passthrough, the real PowerShell geometry
helper and its physical-pixel/DPI agreement with Godot's monitor rects, real monitor placement,
Forward+ rendering/MToon, the on-screen look of standing/sitting on an actual window edge,
physical microphone, GPU models. See the actual Windows acceptance record in [../VALIDATION.md](../VALIDATION.md).


## Host lifecycle regressions

`native/tools/probe_host_lifecycle.gd` invokes actual main handlers with isolated node doubles,
real headless audio/microphone nodes, and simulated desktop geometry. It checks iterative pivot
fitting (no accumulated overshoot), synchronous backend-switch audio/session reset and character
reannouncement, F9/drag cleanup on focus loss without submitting a recording, panel-safe pending
sit transitions, and done-event gesture metadata/deduplication. A changed scale/source may release
support while a sit is pending; the host cancels that intent rather than seat against an obsolete
anchor. Ordinary post-transition settling on the same current anchor is supported.

```sh
XDG_DATA_HOME=/tmp/mate-host-review/data \
XDG_CONFIG_HOME=/tmp/mate-host-review/config \
XDG_CACHE_HOME=/tmp/mate-host-review/cache \
companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless \
  --path companion/native --script tools/probe_host_lifecycle.gd
```

Recorded: 34 checks, zero failures, including late profile/catalogue delivery,
failed model intents preserving unrelated user commands, external target bounds,
and dialogue metadata not starting navigation clips. The fake-backend protocol
probe passes 59 checks. The separate
[`test_host_heading.gd`](../diagnostics/behavior/test_host_heading.gd) passes eight
actual-callback checks for heading readiness, replacement destinations, panel/drag
ownership and timeout cancellation.
Windows rendered contact and packaged-executable behavior remain separate validation.


## Measured sole / floor projection

The foot baseline is calibrated from rest-mesh geometry by VrmAvatar. Orthographic framing
keeps pixels-per-metre independent of vertex depth, so the projected body bottom and measured
sole agree while turning or scaling. This avoids rejecting every floor as unsafe because a
perspective AABB corner extended below the nominal bone-based sole. Workarea safety is unchanged;
no below-taskbar clipping or floor-specific fake anchor is allowed. Surface mode also disables
camera bob so decorative motion cannot invalidate contact geometry; free-roam fallback bob remains.

`diagnostics/autonomy/probe_floor_projection.gd` loads the actual three VRMs and runs actual main
framing with simulated floors: 135 checks pass over three scales (0.35/0.6/1.25) and three yaws
(-82/0/+82). Each case keeps floor contact for 120 frames, remains in the usable workarea, has no
camera bob, and places the projected sole within 0.1 px of the floor. This complements root's real
Windows window/floor render checks; it is not a replacement for them.
