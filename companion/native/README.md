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
root-owned. The desktop-world plan (surfaces now, props later) is `companion/DESKTOP-WORLD.md`.

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
  and faces front; decorative camera bob is disabled throughout surface mode; free roaming with the toggle off keeps the previous behaviour. Stopping
  returns the facing to the front through the motion API, never by touching gestures, so a
  speech gesture is not overridden.
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
  the lean anchor is projected but never selected), props (see DESKTOP-WORLD.md), any reading of
  screen content.

## Desktop roaming (pet mode only)

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
- The default idle selector is disabled and displays "기본 대기 동작 사용" while the native
  procedural idle runs. Imported idle clips remain available for motion-tab previews. An ambient
  loop must eventually blend under gestures/gaze/IK before it can become an enabled setting.
  `Main.walk_clip()` exposes the imported walk name.

## Tests (headless Linux, fake audio driver, no GPU / mic / display)

```sh
companion/native/tools/run_selftest.sh            # selftest: 407 passed, 0 failed
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
button states), `[pet scale on rig]` (real Cheval Grand VRM: foot anchor on the foot pixel at
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

Recorded: 25 checks, zero failures; full selftest 407/0 and fake-backend protocol probe 59/0.
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
