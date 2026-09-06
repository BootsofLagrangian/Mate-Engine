extends Node3D
## Desktop pet host: transparent always-on-top window, VRM pet on the right,
## control panel on the left (collapsible to a pure pet with mouse passthrough
## outside the pet region), and the wiring between backend, session, audio,
## microphone, motion and UI.

const WINDOW_SIZE := Vector2i(680, 760)
const PANEL_MARGIN := 8.0
## Everything right of the panel (window width - panel - margins) belongs to the pet.
const PET_ZONE_WIDTH := float(WINDOW_SIZE.x) - ControlPanel.PANEL_WIDTH - 2.0 * PANEL_MARGIN
const DRAG_THRESHOLD := 6.0
const SUBTITLE_HOLD := 7.0
# Lighting (see _setup_scene): verified only by code inspection here; root re-checks on Windows.
const SUN_ENERGY := 0.8
const FILL_ENERGY := 0.3
const AMBIENT_ENERGY := 0.45
const TONEMAP_EXPOSURE := 0.85

var avatar: VrmAvatar
var motion: MotionPlayer
var audio: AudioOutput
var mic: Microphone
var client: BackendClient
var session := CompanionSession.new()
var autonomy: DesktopAutonomy # window roaming (Astra-owned module); policy in AutonomyBridge
var world_source: DesktopWorldSource # Windows window/monitor rectangles at 1 Hz (Astra-owned; geometry only)
var bridge := AutonomyBridge.new()
var panel: ControlPanel
var camera: Camera3D
var ui_layer: CanvasLayer
var handle_button: Button
var handle_dot: ColorRect
var subtitle: Label
var loading_label: Label

var panel_open := true
var pet_rect := Rect2(WINDOW_SIZE.x - PET_ZONE_WIDTH + 60, 120, 220, 560)
var _unclipped_pet_rect := pet_rect # projected body rect before clipping to the window
var _model_aabb := AABB(Vector3(-0.4, 0, -0.3), Vector3(0.8, 1.6, 0.6))
var _last_passthrough := PackedVector2Array()
var _drag_active := false
var _drag_moved := false
var _drag_start_mouse := Vector2i.ZERO
var _drag_start_window := Vector2i.ZERO
var _ptt_key_down := false
var _subtitle_until := 0.0
var _stats_timer := 0.0
var _avatar_loading_for := ""
var _pending_avatar_path := ""
var _selection_announced := "" # character id last sent as select_character on this connection
var _action_seen_turn := "" # done metadata is a legacy fallback, never a replay of an action
var _fps_active := true
# VRMA catalog (GET /motion-assets): every valid entry, and the subset MotionPlayer accepted.
var _vrma_catalog: Dictionary = {}
var _vrma_loaded: Dictionary = {}
var _vrma_pending := 0
# Roaming presentation state.
var _autonomy_state := "paused"
var _walk_started := "" # walk clip we started for locomotion (never stop a dialogue gesture)
var _floating := false
var _float_blend := 0.0
var _camera_base := Vector3.ZERO
var _travel_dir := 0.0 # -1..1 screen-x direction of the current roaming target (gaze cue)
var _ambient_clip := ""
# Pet size: the avatar node is scaled about a pivot (standing foot / seat while sitting) that is
# held at a fixed window pixel, so the support contact never slides while scaling or turning.
var _pet_scale := AutonomyBridge.SCALE_DEFAULT
var _pet_scale_target := AutonomyBridge.SCALE_DEFAULT
var _pivot_kind := "foot"
var _pivot_px := Vector2.ZERO
var _pivot_px_target := Vector2.ZERO
var _pivot_local: Dictionary = {} # "foot"/"sit" -> avatar-local metres (rest-based, stable)
var _px_per_m := 300.0
# Desktop surfaces: latest support contact from the module, manual sit lifecycle.
var _support: Dictionary = {"attached": false, "pose": "foot"}
var _sit_active := false # user asked to sit (body seated, window re-seating or seated)
var _sit_attached := false # the module reported the seated contact
var _sit_pending := false # panel button intent; body stays standing until movement is allowed


func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	_setup_window()
	_setup_scene()
	_setup_nodes()
	_setup_ui()
	_wire()
	session.character_id = str(Settings.get_value("character", ""))
	client.configure(Settings.backend_url())
	panel.set_backend(client.base_url, Settings.backend_source())
	panel.set_input_devices(AudioServer.get_input_device_list(), AudioServer.input_device)
	mic.set_input_device(str(Settings.get_value("mic_device", "")))
	mic.vad_threshold = float(Settings.get_value("vad_threshold", 0.035))
	mic.target_rate = int(Settings.get_value("mic_target_rate", 0))
	motion.gaze_enabled = bool(Settings.get_value("idle_gaze", true))
	audio.set_volume_db(float(Settings.get_value("volume_db", 0.0)))
	_set_panel_open(bool(Settings.get_value("panel_open", true)), false)
	var vad_saved := bool(Settings.get_value("vad_enabled", false))
	mic.set_vad_enabled(vad_saved)
	panel.set_vad_enabled(mic.vad_enabled)
	_update_input_mode()
	_pet_scale_target = AutonomyBridge.clamp_scale(float(Settings.get_value("pet_scale", AutonomyBridge.SCALE_DEFAULT)))
	_pet_scale = _pet_scale_target
	_pivot_px_target = AutonomyBridge.foot_pivot_px(Vector2(WINDOW_SIZE), PET_ZONE_WIDTH)
	_pivot_px = _pivot_px_target
	panel.set_pet_scale(_pet_scale_target)
	# Roaming: the module reads the window, the visible pet rect and the projected contact anchors;
	# it starts blocked and only moves in collapsed pet mode once update_context() (per frame,
	# below) clears every block.
	autonomy.configure(get_window(), func() -> Rect2: return pet_rect, _projected_anchors)
	autonomy.set_enabled(bool(Settings.get_value("autonomy_enabled", true)))
	autonomy.set_speed(float(Settings.get_value("autonomy_speed", 75.0)))
	_apply_surface_mode()
	_refresh_autonomy_label()
	_refresh_sit_button()
	client.connect_ws()
	client.fetch_characters()
	client.fetch_motions()
	client.fetch_motion_assets()
	panel.set_status_message("백엔드 %s 에 연결 중…" % client.base_url)


# ----------------------------------------------------------------- setup

func _setup_window() -> void:
	var win := get_window()
	win.size = WINDOW_SIZE
	win.borderless = true
	win.always_on_top = true
	win.transparent = true
	win.transparent_bg = true
	win.title = "Mate Companion"
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	_restore_window_position()


func _restore_window_position() -> void:
	# Negative origins are valid on multi-monitor desktops; validity = the window still touches a
	# current monitor (AutonomyBridge.restore_position), not the sign of the coordinates.
	var screens: Array = []
	for i in DisplayServer.get_screen_count():
		screens.append(DisplayServer.screen_get_usable_rect(i))
	var fallback := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var pos := AutonomyBridge.restore_position(bool(Settings.get_value("window_pos_saved", false)),
		int(Settings.get_value("window_x", -1)), int(Settings.get_value("window_y", -1)), WINDOW_SIZE, screens, fallback)
	DisplayServer.window_set_position(pos)


func _save_window_position() -> void:
	var p := DisplayServer.window_get_position()
	Settings.set_value("window_x", p.x)
	Settings.set_value("window_y", p.y)
	Settings.set_value("window_pos_saved", true)


func _setup_scene() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 28.0
	camera.near = 0.05
	camera.far = 50.0
	camera.position = Vector3(0, 1.1, 3.6)
	add_child(camera)
	camera.current = true
	# MToon-converted VRM materials are already close to their albedo at unit light; the
	# Forward+ Windows captures blew white cloth/skin out with 1.35 + 0.45 + 0.9 ambient.
	# Keep the key/fill ratio but lower the total energy and pull the exposure down instead
	# of letting the tonemapper saturate.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.97, 0.93)
	sun.rotation_degrees = Vector3(-38, 28, 0)
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = FILL_ENERGY
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.rotation_degrees = Vector3(-15, -120, 0)
	add_child(fill)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = AMBIENT_ENERGY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = TONEMAP_EXPOSURE
	e.tonemap_white = 1.6
	env.environment = e
	add_child(env)


func _setup_nodes() -> void:
	avatar = VrmAvatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	motion = MotionPlayer.new()
	motion.name = "Motion"
	motion.avatar = avatar
	add_child(motion)
	audio = AudioOutput.new()
	audio.name = "AudioOutput"
	add_child(audio)
	mic = Microphone.new()
	mic.name = "Microphone"
	add_child(mic)
	client = BackendClient.new()
	client.name = "Backend"
	add_child(client)
	# Child of the host: its _process runs after ours in the same frame, so the context we push in
	# _process is always current before it decides to move the window.
	autonomy = DesktopAutonomy.new()
	autonomy.name = "Autonomy"
	add_child(autonomy)
	# Window geometry helper (Windows only, started on demand by _apply_surface_mode, stopped on
	# exit). It reads rectangles, never window contents or pixels.
	world_source = DesktopWorldSource.new()
	world_source.name = "WorldSource"
	add_child(world_source)


func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	panel = ControlPanel.new()
	panel.name = "ControlPanel"
	ui_layer.add_child(panel)
	panel.offset_left = PANEL_MARGIN
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN
	panel.offset_right = PANEL_MARGIN + ControlPanel.PANEL_WIDTH
	panel.clip_contents = true # never paint over the pet zone even if a child asks for more width

	handle_button = Button.new()
	handle_button.name = "Handle"
	handle_button.text = "≡"
	handle_button.tooltip_text = "패널 열기 (F8)"
	handle_button.custom_minimum_size = Vector2(30, 30)
	handle_button.focus_mode = Control.FOCUS_NONE
	handle_button.pressed.connect(func(): _set_panel_open(true))
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.1, 0.09, 0.14, 0.85)
	hs.set_corner_radius_all(15)
	handle_button.add_theme_stylebox_override("normal", hs)
	handle_button.add_theme_stylebox_override("hover", hs)
	handle_button.add_theme_stylebox_override("pressed", hs)
	ui_layer.add_child(handle_button)
	handle_dot = ColorRect.new()
	handle_dot.size = Vector2(8, 8)
	handle_dot.color = Color(0.6, 0.6, 0.6)
	handle_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(handle_dot)

	subtitle = Label.new()
	subtitle.name = "Subtitle"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("outline_size", 4)
	subtitle.visible = false
	ui_layer.add_child(subtitle)

	loading_label = Label.new()
	loading_label.text = "아바타 대기 중"
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	loading_label.add_theme_constant_override("outline_size", 4)
	ui_layer.add_child(loading_label)


func _wire() -> void:
	client.connection_state_changed.connect(func(s: String):
		panel.set_connection(s, client.last_error if s == "closed" else "")
		_update_handle_dot())
	client.connected.connect(func():
		panel.set_status_message("연결됨 · %s" % client.base_url))
	client.disconnected.connect(func(reason: String):
		_selection_announced = ""
		session.reset_connection()
		audio.cancel() # flush playback; the server's accounting is reset with the connection
		motion.stop_gesture()
		var why := reason
		if reason.begins_with("1013"):
			why = "서버가 클라이언트를 느리다고 판단해 연결을 닫음 (1013)"
		panel.set_status_message("연결 끊김 (%s) · 재접속 시도 중" % why)
		panel.append_transcript("system", "연결이 끊겼습니다: %s · 재생 중이던 음성을 비웠습니다" % why))
	client.event_received.connect(func(ev: Dictionary): session.handle(ev))
	client.characters_loaded.connect(_on_characters_loaded)
	client.motions_loaded.connect(_on_motions_loaded)
	client.avatar_ready.connect(_on_avatar_ready)
	client.motion_saved.connect(func(ok: bool, id: String, msg: String):
		panel.set_motion_result(("저장됨: %s · 뱅크 새로고침" % id) if ok else msg, ok)
		if ok:
			client.fetch_motions())
	client.motion_assets_loaded.connect(_on_motion_assets_loaded)
	client.motion_asset_ready.connect(_on_motion_asset_ready)

	autonomy.state_changed.connect(func(s: String):
		_autonomy_state = s
		if s == "no_surface" and _sit_active and not _sit_attached:
			# The seated pose fits no safe support (would clip the work area): stand back up.
			_stand_up("앉을 자리가 맞지 않아 다시 일어섭니다")
		_refresh_autonomy_label())
	autonomy.locomotion_changed.connect(_on_locomotion)
	autonomy.support_changed.connect(_on_support_changed)
	world_source.snapshot_changed.connect(func(snapshot: Dictionary): autonomy.set_world_snapshot(snapshot))
	autonomy.target_chosen.connect(func(_id: String, screen_point: Vector2, _kind: String):
		var here := Vector2(get_window().position) + pet_rect.get_center()
		_travel_dir = clampf((screen_point.x - here.x) / 400.0, -1.0, 1.0))

	session.event_accepted.connect(_on_event)
	session.event_discarded.connect(func(ev: Dictionary, reason: String):
		if str(ev.get("type", "")) == "audio":
			return
		print("[session] discarded %s: %s" % [ev.get("type", "?"), reason]))
	session.turn_started.connect(func(id: String):
		_action_seen_turn = ""
		audio.begin_turn(id))
	session.turn_finished.connect(func(_id: String, outcome: String):
		if outcome != "done":
			audio.cancel()
			motion.stop_gesture())
	session.activity_changed.connect(func(a: String):
		panel.set_activity(a)
		_update_handle_dot())
	session.characters_changed.connect(func(chars: Array): panel.set_characters(chars, session.character_id))
	session.character_changed.connect(func(id: String):
		Settings.set_value("character", id)
		panel.set_characters(session.characters, id)
		_announce_character(id)
		_load_avatar_for(id, false))
	session.job_changed.connect(func(job: Dictionary): panel.set_job(job))

	audio.voice_active_changed.connect(func(active: bool):
		session.set_voice_active(active)
		mic.set_own_voice_active(active)
		_update_handle_dot())
	audio.overflow.connect(func(turn: String, seconds: float):
		panel.append_transcript("system", "오디오 버퍼 한계 초과 (%.0f초 대기) · 응답을 중단했습니다" % seconds)
		panel.set_status_message("오디오 버퍼 초과로 중단: " + turn)
		_cancel_current())
	# Real playback accounting for the server (jobs never speak over foreground playback).
	audio.playback_changed.connect(func(turn: String, playing: bool):
		if client.state == "open" and not turn.is_empty():
			client.send(session.make_playback(turn, playing)))

	mic.utterance_ready.connect(_on_utterance)
	mic.level_changed.connect(func(l: float): panel.set_mic_level(l))
	mic.recording_changed.connect(func(active: bool, source: String):
		panel.set_recording(active, source)
		session.set_listening(active)
		_update_input_mode())
	mic.capture_changed.connect(func(_on: bool): _update_input_mode())
	mic.vad_state_changed.connect(func(_s: String): _update_input_mode())
	mic.error.connect(func(m: String): panel.set_status_message(m))

	panel.send_text.connect(_send_chat)
	panel.ptt_pressed.connect(_ptt_down)
	panel.ptt_released.connect(_ptt_up)
	panel.vad_toggled.connect(_set_vad)
	panel.cancel_requested.connect(_cancel_current)
	panel.character_selected.connect(_switch_character)
	panel.refresh_requested.connect(func():
		client.fetch_characters()
		client.fetch_motions()
		client.fetch_motion_assets()
		client.check_health())
	panel.reload_avatar_requested.connect(func(): _load_avatar_for(session.character_id, true))
	panel.preview_gesture.connect(func(name: String, emotion: String, intensity: float, speed: float, repeat: int):
		if not motion.play_gesture(name, emotion, intensity, speed, repeat, true):
			motion.set_emotion(emotion))
	panel.preview_motion.connect(func(m: Dictionary): motion.play_motion_dict(m, 1.0, 1.0, 1))
	panel.save_motion.connect(func(m: Dictionary): client.save_motion(m))
	panel.job_start.connect(_start_job)
	panel.job_cancel.connect(_cancel_job)
	panel.setting_changed.connect(_on_setting)
	panel.backend_changed.connect(_set_backend)
	panel.collapse_requested.connect(func(): _set_panel_open(false))
	panel.sit_requested.connect(func(sit: bool):
		if sit:
			_request_sit()
		else:
			_stand_up(""))
	client.health_checked.connect(func(ok: bool, msg: String): panel.set_status_message(("health OK: " if ok else "health 실패: ") + msg))


# ----------------------------------------------------------------- backend data

func _on_characters_loaded(ok: bool, characters: Array, message: String) -> void:
	if not ok:
		panel.set_status_message(message)
		return
	session.characters = characters
	if session.character_id.is_empty() or session.character_by_id(session.character_id).is_empty():
		if not characters.is_empty():
			session.set_character(str(characters[0].get("id", "")))
	else:
		_load_avatar_for(session.character_id, false)
	panel.set_characters(characters, session.character_id)


func _on_motions_loaded(ok: bool, bank: MotionBank, message: String) -> void:
	if not ok or bank == null:
		panel.set_status_message(message)
		return
	motion.set_bank(bank)
	panel.set_bank(bank)
	if not bank.errors.is_empty():
		panel.set_motion_result("뱅크 경고: " + message, false)


## GET /motion-assets. Missing endpoint / older backend: keep the built-in bank silently (one
## motion-tab note), nothing else changes.
func _on_motion_assets_loaded(ok: bool, entries: Array[Dictionary], message: String) -> void:
	if not ok:
		print("[motion-assets] " + message)
		panel.set_motion_result("VRMA 카탈로그 없음 · 내장 프리셋만 사용 (%s)" % message, true)
		return
	_vrma_catalog.clear()
	_vrma_pending = 0
	for e in entries:
		_vrma_catalog[str(e["name"])] = e
		_vrma_pending += 1
		client.fetch_motion_asset(e)
	if entries.is_empty():
		panel.set_motion_result("VRMA 카탈로그 비어 있음 · 내장 프리셋만 사용", true)
	else:
		panel.set_motion_result("VRMA 클립 %d개 받는 중… (%s)" % [entries.size(), message], true)


## One clip cached + checksum verified -> hand it to the motion owner (read-only clip).
func _on_motion_asset_ready(ok: bool, name: String, path: String, message: String) -> void:
	_vrma_pending = maxi(_vrma_pending - 1, 0)
	if ok and _vrma_catalog.has(name):
		if motion.load_vrma(name, path):
			_vrma_loaded[name] = _vrma_catalog[name]
		else:
			print("[motion-assets] %s: clip rejected by MotionPlayer (%s)" % [name, path])
	elif not ok:
		print("[motion-assets] " + message)
	if _vrma_pending == 0:
		panel.set_vrma_clips(_vrma_loaded)
		var names := _vrma_loaded.keys()
		names.sort()
		panel.set_motion_result("VRMA 클립 %d/%d 준비: %s" % [_vrma_loaded.size(), _vrma_catalog.size(), ", ".join(PackedStringArray(names))], _vrma_loaded.size() == _vrma_catalog.size())
		_apply_ambient_idle()
		_refresh_sit_button()


## Imported walk clip name for roaming ("" when none loaded). Exposed for the autonomy owner/tests.
func walk_clip() -> String:
	return AutonomyBridge.pick_walk_clip(_vrma_loaded)


## Ambient idle loop: only through the motion owner's API that blends under gestures/gaze/IK.
## Until MotionPlayer exposes set_ambient_loop(name), the procedural idle stays (a raw looping
## play_vrma would override head gaze and be killed by the first gesture).
func _apply_ambient_idle() -> void:
	var setting := str(Settings.get_value("idle_clip", "auto"))
	var has_api := motion.has_method("set_ambient_loop")
	var choice := AutonomyBridge.ambient_idle_choice(setting, _vrma_loaded, has_api)
	if choice != _ambient_clip or (has_api and choice.is_empty() and not _ambient_clip.is_empty()):
		_ambient_clip = choice
		if has_api:
			motion.call("set_ambient_loop", choice)


func _load_avatar_for(character_id: String, force: bool) -> void:
	if character_id.is_empty():
		return
	var info := session.character_by_id(character_id)
	var url := str(info.get("avatar_url", ""))
	_avatar_loading_for = character_id
	loading_label.text = "아바타 받는 중: %s" % str(info.get("name", character_id))
	loading_label.visible = true
	client.fetch_avatar(character_id, url, force)


func _on_avatar_ready(ok: bool, character_id: String, path: String, message: String) -> void:
	if character_id != session.character_id:
		return # latest-only: a newer selection superseded this download
	if not ok:
		loading_label.text = "아바타 실패: " + message
		panel.set_status_message(message)
		return
	loading_label.text = "아바타 불러오는 중…"
	_pending_avatar_path = path
	call_deferred("_apply_avatar", character_id, path, message)


func _apply_avatar(character_id: String, path: String, message: String) -> void:
	if character_id != session.character_id or path != _pending_avatar_path:
		return
	_stand_up("") # reset_all() below drops the seated pose; keep the module's pose in step
	motion.reset_all()
	var loaded := avatar.load_from_file(ProjectSettings.globalize_path(path))
	loading_label.visible = not loaded
	if not loaded:
		loading_label.text = "VRM 로드 실패"
		panel.set_avatar_info("VRM 로드 실패: " + path)
		return
	_frame_avatar()
	var missing: Array = []
	for b in ["head", "neck", "spine", "chest", "leftUpperArm", "rightUpperArm", "leftLowerArm", "rightLowerArm"]:
		if not avatar.bone_index.has(b):
			missing.append(b)
	panel.set_avatar_info("%s (%s) · 본 %d · 표정 %d · %s%s" % [avatar.meta_title, message, avatar.bone_index.size(), avatar.expressions.size(), path, ("\n누락 본: " + ", ".join(missing)) if not missing.is_empty() else ""])
	panel.set_status_message("아바타 준비: %s" % avatar.meta_title)


## Fixed camera per model: the model is reference_height_px tall at scale 1 (so SCALE_MAX still
## fits the window), looking straight down -Z; the standing foot pivot pixel maps to the world
## origin. The avatar itself is placed/scaled every frame by _update_avatar_transform.
func _frame_avatar() -> void:
	if not avatar.has_model():
		return
	avatar.transform = Transform3D.IDENTITY
	_model_aabb = avatar.compute_aabb()
	var anchors := avatar.contact_anchors() # avatar at identity: global == avatar-local
	var bottom := Vector3(_model_aabb.get_center().x, _model_aabb.position.y, _model_aabb.get_center().z)
	_pivot_local = {
		"foot": anchors.get("foot", bottom),
		"sit": anchors.get("sit", bottom + Vector3(0, _model_aabb.size.y * 0.45, 0)),
	}
	var foot_px := AutonomyBridge.foot_pivot_px(Vector2(WINDOW_SIZE), PET_ZONE_WIDTH)
	var cam := AutonomyBridge.pet_camera(_model_aabb.size.y, camera.fov, Vector2(WINDOW_SIZE), foot_px,
		AutonomyBridge.reference_height_px(float(WINDOW_SIZE.y)))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(cam["size"])
	camera.transform = Transform3D(Basis.IDENTITY, cam["position"])
	_camera_base = camera.position
	_px_per_m = float(cam["px_per_m"])
	_pivot_kind = "foot"
	_pivot_px_target = foot_px
	_pivot_px = foot_px
	_update_avatar_transform(0.0)
	_update_pet_rect()


## Place the avatar so the current pivot (stable rest foot, or seat while sitting) sits exactly at
## its window pixel for the smoothed scale and the facing yaw MotionPlayer applied this frame.
## Runs after MotionPlayer (priority -10) and before DesktopAutonomy (child) reads the anchors.
func _update_avatar_transform(delta: float) -> void:
	if not avatar.has_model() or _pivot_local.is_empty():
		return
	if delta > 0.0:
		_pet_scale = AutonomyBridge.smooth_scale(_pet_scale, _pet_scale_target, delta)
		var k := 1.0 - pow(1.0 - AutonomyBridge.SCALE_SMOOTH_FACTOR, delta * 60.0)
		_pivot_px = _pivot_px_target if _pivot_px.distance_to(_pivot_px_target) < 0.05 else _pivot_px.lerp(_pivot_px_target, k)
	var basis := Basis.from_euler(Vector3(0.0, avatar.rotation.y, 0.0)).scaled(Vector3.ONE * _pet_scale)
	var pivot_world := AutonomyBridge.pixel_to_world(_pivot_px, _camera_base, _px_per_m, Vector2(WINDOW_SIZE))
	avatar.transform = AutonomyBridge.pivot_transform(basis, pivot_world, _pivot_local.get(_pivot_kind, Vector3.ZERO))


## Window-local projections of the avatar's stable contact anchors for DesktopAutonomy
## (foot: rest sole under the hips, sit: rest seat, lean: right hand). Never foot_current.
func _projected_anchors() -> Dictionary:
	if not avatar.has_model():
		return {}
	var anchors := avatar.contact_anchors()
	var out := {}
	for key in ["foot", "sit", "lean"]:
		if anchors.has(key) and not camera.is_position_behind(anchors[key]):
			out[key] = camera.unproject_position(anchors[key])
	return out


func pet_scale() -> float:
	return _pet_scale


func _set_scale_target(value: float) -> void:
	var clamped := AutonomyBridge.clamp_scale(value)
	if is_equal_approx(clamped, _pet_scale_target):
		return
	_pet_scale_target = clamped
	Settings.set_value("pet_scale", clamped)
	panel.set_pet_scale(clamped)


# ----------------------------------------------------------------- conversation

func _on_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"hello":
			panel.set_status_message("hello · protocol %d · 캐릭터 %d" % [session.protocol, session.characters.size()])
			var caps: Dictionary = ev.get("capabilities", {}) if typeof(ev.get("capabilities")) == TYPE_DICTIONARY else {}
			var job_info := ""
			var workspace := str(caps.get("job_workspace", ev.get("job_workspace", ev.get("job_root", ""))))
			var sandbox := str(caps.get("job_sandbox", ev.get("job_sandbox", ev.get("sandbox", ""))))
			if not workspace.is_empty() and workspace != "<null>":
				job_info += "폴더 %s " % workspace
			if not sandbox.is_empty() and sandbox != "<null>":
				job_info += "· 모드 %s" % sandbox
			if bool(caps.get("jobs", false)):
				panel.set_job_workspace("작업 폴더/모드: " + (job_info if not job_info.is_empty() else "서버가 hello에 명시하지 않음 (MATE_JOB_ROOT, 기본 read-only)"))
			else:
				panel.set_job_workspace("이 백엔드는 작업(jobs)을 지원하지 않습니다" + ((" (" + job_info + ")") if not job_info.is_empty() else " (MATE_JOB_ROOT 미설정)"))
			var provider := str(caps.get("provider", ""))
			if provider == "stub":
				panel.append_transcript("system", "주의: 백엔드가 테스트 전용 stub 프로바이더로 실행 중입니다")
			# Initial selection is announced even when hello's default matched the saved character.
			_announce_character(session.character_id)
		"character_selected":
			if str(ev.get("character", "")) != session.character_id:
				panel.set_status_message("서버 선택 캐릭터 불일치: %s" % str(ev.get("character", "")))
			if not session.character_id.is_empty() and not avatar.has_model() and _avatar_loading_for != session.character_id:
				_load_avatar_for(session.character_id, false)
		"text":
			bridge.note_dialogue(_now())
			var t := str(ev.get("text", ""))
			panel.update_live_reply(t, false)
			_show_subtitle(t)
		"audio":
			bridge.note_dialogue(_now())
			audio.push_event(ev)
		"action":
			_action_seen_turn = str(ev.get("turn_id", session.turn_id))
			# Dialogue owns the body immediately: the roaming walk loop (if any) is superseded here
			# and never restarted by a later locomotion stop.
			bridge.note_dialogue(_now())
			_walk_started = ""
			motion.play_gesture(str(ev.get("gesture", "idle")), str(ev.get("emotion", "")), float(ev.get("intensity", 1.0)), float(ev.get("speed", 1.0)), int(ev.get("repeat", 1)))
		"done":
			bridge.note_dialogue(_now())
			var t := str(ev.get("text", session.text))
			var ok := bool(ev.get("ok", true))
			if not ok:
				panel.update_live_reply(t if not t.is_empty() else "(응답 실패)", true)
				return
			panel.update_live_reply(t, true)
			_show_subtitle(t)
			var done_turn := str(ev.get("turn_id", session.turn_id))
			var action_seen := not done_turn.is_empty() and done_turn == _action_seen_turn
			if not action_seen and not _dialogue_gesture_active() and ev.has("gesture"):
				_walk_started = ""
				motion.play_gesture(str(ev.get("gesture", "idle")), str(ev.get("emotion", "")),
					float(ev.get("intensity", 1.0)), float(ev.get("speed", 1.0)), int(ev.get("repeat", 1)))
			elif ev.has("emotion"):
				motion.set_emotion(str(ev["emotion"]))
		"cancelled":
			var reason := str(ev.get("reason", ""))
			if reason != "superseded":
				panel.append_transcript("system", "서버가 응답을 취소했습니다 (%s)" % reason)
		"error":
			panel.append_transcript("system", "오류: " + str(ev.get("message", "")))
			if str(ev.get("turn_id", "")).is_empty():
				panel.set_status_message("서버 오류: " + str(ev.get("message", "")))
			else:
				# Active-turn error: hard-flush queued PCM and stop playback now, even when
				# generation had already finished (turn_finished only fires while generating).
				audio.cancel()
				motion.stop_gesture()
				panel.set_status_message("응답 오류로 음성을 중단했습니다")
		"voice_error":
			panel.append_transcript("system", "음성 오류: " + str(ev.get("message", "")))


func _send_chat(text: String) -> void:
	if client.state != "open":
		panel.append_transcript("system", "백엔드에 연결되어 있지 않습니다")
		return
	_own_body_for_dialogue()
	_cancel_current()
	var msg := session.make_chat(text)
	audio.begin_turn(msg["turn_id"])
	client.send(msg)
	panel.append_transcript("user", text)


func _on_utterance(wav: PackedByteArray, seconds: float, source: String) -> void:
	if client.state != "open":
		panel.append_transcript("system", "백엔드에 연결되어 있지 않습니다 (음성 %.1fs 버림)" % seconds)
		return
	_own_body_for_dialogue()
	_cancel_current()
	var msg := session.make_audio(Marshalls.raw_to_base64(wav))
	audio.begin_turn(msg["turn_id"])
	client.send(msg)
	panel.append_transcript("user", "[음성 %.1f초 · %s · %d bytes]" % [seconds, "PTT" if source == "ptt" else "VAD", wav.size()])


func _cancel_current() -> void:
	var id := session.cancel_turn()
	if not id.is_empty():
		client.send(session.make_cancel(id))
	audio.cancel()
	motion.stop_gesture()


func _switch_character(id: String) -> void:
	if id == session.character_id or id.is_empty():
		return
	_cancel_current() # hard flush + local cancel first: the accepted turn id changes immediately
	_stand_up("")
	motion.reset_all()
	session.set_character(id) # emits character_changed -> select_character + avatar load


func _announce_character(id: String) -> void:
	if id.is_empty() or client.state != "open" or _selection_announced == id:
		return
	if client.send(session.make_select_character(id)):
		_selection_announced = id


func _start_job(prompt: String) -> void:
	if client.state != "open":
		panel.set_status_message("백엔드에 연결되어 있지 않습니다")
		return
	if not session.job.is_empty() and not CompanionSession.JOB_TERMINAL.has(session.job.get("status", "")):
		panel.set_status_message("이미 실행 중인 작업이 있습니다")
		return
	client.send(session.make_job(prompt))


func _cancel_job() -> void:
	var id := session.cancel_job_local()
	if not id.is_empty():
		client.send(session.make_cancel_job(id))


# ----------------------------------------------------------------- input / mic

func _ptt_down() -> void:
	mic.start_push_to_talk()


func _ptt_up() -> void:
	mic.stop_push_to_talk()


func _set_vad(on: bool) -> void:
	mic.set_vad_enabled(on)
	panel.set_vad_enabled(mic.vad_enabled)
	Settings.set_value("vad_enabled", mic.vad_enabled)
	_update_input_mode()


func _update_input_mode() -> void:
	var mode := "텍스트"
	if mic.is_recording():
		mode = "녹음 중 (%s)" % ("PTT" if mic._record_source == "ptt" else "VAD")
	elif mic.vad_enabled:
		var st: String = {"waiting": "VAD 대기", "paused": "VAD 일시정지(자기 음성)", "speech": "VAD 감지"}.get(mic.vad_state(), "VAD")
		mode = "%s · 마이크 켜짐 · noAEC" % st
	elif mic.available:
		mode = "텍스트 / PTT · 마이크 꺼짐"
	else:
		mode = "텍스트 (마이크 입력 비활성)"
	panel.set_input_mode(mode)


func _on_setting(key: String, value: Variant) -> void:
	match key:
		"reset_window":
			Settings.set_value("window_x", -1)
			Settings.set_value("window_y", -1)
			Settings.set_value("window_pos_saved", false)
			_restore_window_position()
			return
		"autonomy_enabled":
			Settings.set_value(key, value)
			autonomy.set_enabled(bool(value))
			_apply_surface_mode()
			_refresh_autonomy_label()
			return
		"surface_roam":
			Settings.set_value(key, value)
			if not bool(value):
				_stand_up("")
			_apply_surface_mode()
			return
		"autonomy_speed":
			autonomy.set_speed(float(value))
		"idle_clip":
			Settings.set_value(key, value)
			_apply_ambient_idle()
			return
		"vad_threshold":
			mic.vad_threshold = float(value)
		"mic_target_rate":
			mic.target_rate = int(value)
		"mic_device":
			mic.set_input_device(str(value))
		"pet_scale":
			_set_scale_target(float(value)) # smoothed in _update_avatar_transform, persisted there
			return
		"volume_db":
			audio.set_volume_db(float(value))
		"idle_gaze":
			motion.gaze_enabled = bool(value)
	Settings.set_value(key, value)


func _set_backend(url: String) -> void:
	url = url.strip_edges()
	if url.is_empty():
		return
	# Replacing the peer immediately bypasses the old peer's disconnected signal.
	# End its owned work and flush local state before opening a different backend.
	_cancel_current()
	_cancel_job()
	_selection_announced = ""
	session.reset_connection()
	Settings.set_value("backend_url", url)
	client.disconnect_ws()
	client.configure(Settings.backend_url())
	panel.set_backend(client.base_url, Settings.backend_source())
	client.connect_ws()
	client.fetch_characters()
	client.fetch_motions()
	client.fetch_motion_assets()


func _set_panel_open(open: bool, persist: bool = true) -> void:
	if open and _sit_pending:
		_sit_pending = false
		_refresh_sit_button()
	panel_open = open
	panel.visible = open
	handle_button.visible = not open
	handle_dot.visible = not open
	if persist:
		Settings.set_value("panel_open", open)
	if open:
		panel.focus_input()
		# Never let the window run away while the user is in the panel: block this very frame
		# instead of waiting for the next _process tick.
		_push_autonomy_context()
	_refresh_autonomy_label()
	_update_passthrough(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		if key.pressed and key.physical_keycode == KEY_F8:
			_set_panel_open(not panel_open)
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_F9:
			if key.pressed and not _ptt_key_down:
				_ptt_key_down = true
				_ptt_down()
			elif not key.pressed and _ptt_key_down:
				_ptt_key_down = false
				_ptt_up()
			get_viewport().set_input_as_handled()
		elif key.pressed and key.physical_keycode == KEY_F10:
			_set_vad(not mic.vad_enabled)
			get_viewport().set_input_as_handled()
		elif key.pressed and key.physical_keycode == KEY_ESCAPE:
			_cancel_current()
			if mic.is_recording():
				mic.cancel_recording()
	elif _drag_active and event is InputEventMouseMotion:
		var delta := DisplayServer.mouse_get_position() - _drag_start_mouse
		if delta.length() > DRAG_THRESHOLD:
			_drag_moved = true
		if _drag_moved:
			DisplayServer.window_set_position(_drag_start_window + delta)
	elif _drag_active and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_active = false
		if _drag_moved:
			_save_window_position()
		else:
			motion.pet_reaction()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Wheel over the pet resizes it (Unity AvatarScaleController behaviour). The panel's own
			# controls consume wheel events over the panel, and a drag in progress ignores it.
			var notches := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var over_pet := pet_rect.grow(20).has_point(event.position)
			var wanted := AutonomyBridge.wheel_scale(_pet_scale_target, notches, _drag_active, over_pet)
			if not is_equal_approx(wanted, _pet_scale_target):
				_set_scale_target(wanted)
				get_viewport().set_input_as_handled()
			return
		if pet_rect.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_LEFT:
				_drag_active = true
				_drag_moved = false
				_drag_start_mouse = DisplayServer.mouse_get_position()
				_drag_start_window = DisplayServer.window_get_position()
				if _sit_active:
					_stand_up("") # a manual drag releases the support; the module detaches too
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_set_panel_open(not panel_open)


# ----------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_update_fps_cap()
	motion.mouth_open = audio.envelope
	_update_avatar_transform(delta)
	_update_pet_rect()
	_keep_pet_in_window()
	_update_gaze()
	_push_autonomy_context()
	_advance_pending_sit()
	_update_float(delta)
	_update_passthrough(false)
	_layout_overlays()
	if subtitle.visible and Time.get_ticks_msec() / 1000.0 > _subtitle_until:
		subtitle.visible = false
	_stats_timer += delta
	if _stats_timer > 0.5:
		_stats_timer = 0.0
		panel.set_audio_stats(audio.stats())
		_refresh_surface_status()


## Scaling about the seat can push the dangling legs past the window bottom (or a tall scale past
## the top): nudge the pivot target so the projected pet stays inside the window. The module sees
## the anchor move and re-seats smoothly when the shift is material.
func _keep_pet_in_window() -> void:
	if not avatar.has_model():
		return
	var shift := AutonomyBridge.fit_shift(_unclipped_pet_rect, Vector2(WINDOW_SIZE))
	if shift != Vector2.ZERO:
		# Correct the current pivot, not the already-easing target: accumulating
		# overflow every frame overshoots and can clip the opposite edge.
		_pivot_px_target = _pivot_px + shift


## Desktop pets must not render unbounded: 60 fps while interacting/speaking/animating,
## 30 fps when idle (panel closed, no audio, no gesture, window unfocused).
func _update_fps_cap() -> void:
	var active := panel_open or audio.voice_active or motion.is_gesture_active() or _drag_active \
		or mic.is_recording() or DisplayServer.window_is_focused() or session.activity != "idle" \
		or _autonomy_state == "walk" or _autonomy_state == "approach" or _floating \
		or not is_equal_approx(_pet_scale, _pet_scale_target)
	if active != _fps_active or Engine.max_fps == 0:
		_fps_active = active
		Engine.max_fps = 60 if active else 30


func _update_pet_rect() -> void:
	if not avatar.has_model():
		return
	var box := _model_aabb
	var xf := avatar.global_transform
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for i in 8:
		var corner := box.get_endpoint(i)
		var world := xf * corner
		if camera.is_position_behind(world):
			continue
		var p := camera.unproject_position(world)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	if min_p.x < max_p.x:
		var r := AutonomyBridge.body_rect(Rect2(min_p, max_p - min_p))
		_unclipped_pet_rect = r
		pet_rect = r.intersection(Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE)))


func _update_gaze() -> void:
	var mouse := get_viewport().get_mouse_position()
	var inside := Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE)).has_point(mouse) and DisplayServer.window_is_focused() or pet_rect.grow(120).has_point(mouse)
	if inside:
		# Normalised relative to the pet head (0.5,0.45 = straight ahead)
		var head := camera.unproject_position(avatar.bone_global_position("head")) if avatar.has_model() else pet_rect.get_center()
		var dx := clampf((mouse.x - head.x) / 320.0, -1.0, 1.0)
		var dy := clampf((mouse.y - head.y) / 320.0, -1.0, 1.0)
		# Screen right is the character's left (it faces the camera), so invert x for "+y = look right".
		motion.gaze_target = Vector2(0.5 - dx * 0.5, 0.45 + dy * 0.5)
		motion.gaze_has_target = true
	elif _autonomy_state == "walk" and not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
		# Slow, constant gaze cue toward the roaming destination (a fixed target, not per-frame
		# noise; MotionPlayer smooths it at its usual rate, so no extra head jitter).
		motion.gaze_target = Vector2(0.5 - _travel_dir * 0.2, 0.45)
		motion.gaze_has_target = true
	else:
		motion.gaze_has_target = false


func _update_passthrough(force: bool) -> void:
	var region := pet_rect.grow(10)
	if handle_button.visible:
		region = region.merge(Rect2(handle_button.position, handle_button.size).grow(4))
	if panel_open:
		region = region.merge(Rect2(panel.position, panel.size).grow(4))
	if subtitle.visible:
		region = region.merge(Rect2(subtitle.position, subtitle.size))
	region = region.intersection(Rect2(Vector2.ZERO, Vector2(WINDOW_SIZE)))
	var poly := PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)])
	if force or poly != _last_passthrough:
		_last_passthrough = poly
		DisplayServer.window_set_mouse_passthrough(poly) # no-op on platforms without support


func _layout_overlays() -> void:
	handle_button.position = Vector2(pet_rect.get_center().x - 15, maxf(pet_rect.position.y - 36, 4))
	handle_dot.position = handle_button.position + Vector2(24, -2)
	loading_label.size = Vector2(PET_ZONE_WIDTH, 24)
	loading_label.position = Vector2(WINDOW_SIZE.x - PET_ZONE_WIDTH, WINDOW_SIZE.y * 0.5)
	subtitle.size = Vector2(PET_ZONE_WIDTH - 20, 0)
	subtitle.position = Vector2(WINDOW_SIZE.x - PET_ZONE_WIDTH + 10, minf(pet_rect.end.y + 6, WINDOW_SIZE.y - 70))


func _show_subtitle(text: String) -> void:
	if panel_open or not bool(Settings.get_value("show_subtitles", true)) or text.is_empty():
		subtitle.visible = false
		return
	subtitle.text = text
	subtitle.visible = true
	_subtitle_until = Time.get_ticks_msec() / 1000.0 + SUBTITLE_HOLD


func _update_handle_dot() -> void:
	var c := Color(0.85, 0.35, 0.35)
	if client.state == "open":
		match session.activity:
			"speaking":
				c = Color(0.55, 0.75, 1.0)
			"thinking":
				c = Color(0.95, 0.8, 0.3)
			"listening":
				c = Color(1.0, 0.5, 0.5)
			_:
				c = Color(0.35, 0.85, 0.45)
	elif client.state == "connecting":
		c = Color(0.95, 0.75, 0.3)
	handle_dot.color = c


# ----------------------------------------------------------------- roaming (desktop autonomy)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Per-frame context for DesktopAutonomy: any true field freezes movement immediately; movement
## resumes only after the module's own settle delay once everything is clear again.
func _push_autonomy_context() -> void:
	if autonomy == null:
		return
	# Seated on a support: hold the module (it keeps the contact) so it never walks off until stood up.
	var ctx := bridge.context(panel_open, mic.is_recording(), audio.voice_active, _drag_active,
		session.activity, session.is_foreground_busy(), session.is_foreground_playing(), _now(),
		_sit_active and _sit_attached)
	autonomy.update_context(bool(ctx["panel_open"]), bool(ctx["listening"]), bool(ctx["speaking"]),
		bool(ctx["dragging"]), bool(ctx["foreground_busy"]))
	# Passthrough hides pointer events outside the pet region, so use the global pointer.
	var mouse_local := Vector2(DisplayServer.mouse_get_position() - get_window().position)
	var handle_rect := Rect2(handle_button.position, handle_button.size) if handle_button.visible else Rect2()
	autonomy.set_pointer_interaction(AutonomyBridge.pointer_near(mouse_local, pet_rect, handle_rect, _drag_active))


## A user dialogue turn starts: the body belongs to the conversation from this instant. Roaming is
## blocked by the context (hold window), the walk loop is dropped so it cannot resume mid-reply.
func _own_body_for_dialogue() -> void:
	bridge.note_dialogue(_now())
	if not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
		motion.stop_gesture()
	_walk_started = ""
	_floating = false
	_push_autonomy_context()


## Gesture owned by dialogue/preview (anything that is not the walk loop we started or the seated
## idle loop, which the motion owner keeps under later gestures anyway).
func _dialogue_gesture_active() -> bool:
	if not motion.is_gesture_active():
		return false
	var current := motion.current_gesture()
	if current == _walk_started:
		return false
	return not (_sit_active and current == AutonomyBridge.SIT_CLIP)


func _on_locomotion(moving: bool, velocity: Vector2) -> void:
	# Surface mode: grounded walk only while the module is in "walk" on an attached support; an
	# "approach" glide toward a support floats/idles instead. Facing follows real walking only and
	# returns to the front on stop; it never touches gestures, so speech is not overridden.
	var grounded := AutonomyBridge.grounded(autonomy.surface_mode, autonomy.state, _support)
	motion.set_locomotion_direction(AutonomyBridge.facing_velocity(moving, grounded, _sit_active, velocity))
	var plan := AutonomyBridge.locomotion_plan(moving, _vrma_loaded, _dialogue_gesture_active(), autonomy.speed, grounded, _sit_active)
	match str(plan["action"]):
		"walk":
			var clip := str(plan["clip"])
			# Start the loop once per travel; never restart it per velocity sample (that is the
			# rapid preemption that produced head jitter).
			if _walk_started != clip or motion.current_gesture() != clip:
				if motion.play_vrma(clip, float(plan["speed"]), true):
					_walk_started = clip
			_floating = false
		"float":
			_floating = not autonomy.surface_mode
		"stop":
			if not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
				motion.stop_gesture()
			_walk_started = ""
			_floating = false
			_save_window_position() # roaming destinations persist like a manual drag
		_:
			pass


## No walk clip: gentle vertical float while the window travels (legs keep the idle pose; a
## sliding walk without a clip would look wrong). Fades in/out, camera-only, tiny amplitude.
func _update_float(delta: float) -> void:
	# A desktop support is physical screen geometry: moving the projection camera
	# would move the visible shoe/bounds independently of its attached anchor.
	if autonomy != null and autonomy.surface_mode:
		_float_blend = 0.0
		_floating = false
		if camera != null and _camera_base != Vector3.ZERO:
			camera.position = _camera_base
		return
	var wanted := 1.0 if _floating else 0.0
	if is_equal_approx(_float_blend, wanted) and wanted == 0.0:
		return
	_float_blend = move_toward(_float_blend, wanted, delta / 0.6)
	if _camera_base != Vector3.ZERO:
		camera.position = _camera_base + Vector3(0.0, AutonomyBridge.float_offset(_now(), _float_blend), 0.0)


func _refresh_autonomy_label() -> void:
	if panel != null and autonomy != null:
		panel.set_autonomy_state("앉을 준비 중" if _sit_pending else AutonomyBridge.state_label(_autonomy_state, autonomy.enabled, panel_open, _sit_active))


# ----------------------------------------------------------------- desktop surfaces (sit / walk on windows)

## Surface mode = roaming enabled AND the surface toggle. The Windows geometry helper runs only
## while surface mode is wanted (and only on Windows); elsewhere the module keeps the monitor
## work-area floor as its only surface. Turning it off returns to free roaming.
func _apply_surface_mode() -> void:
	var wanted := bool(Settings.get_value("surface_roam", true)) and bool(Settings.get_value("autonomy_enabled", true))
	autonomy.set_surface_mode(wanted)
	world_source.configure(wanted and OS.get_name() == "Windows")
	_refresh_surface_status()
	_refresh_sit_button()


func _refresh_surface_status() -> void:
	if panel == null or world_source == null:
		return
	panel.set_surface_status(AutonomyBridge.surface_status(autonomy.surface_mode, OS.get_name(),
		world_source.available, world_source.last_error, world_source.snapshot))


func _refresh_sit_button() -> void:
	if panel == null:
		return
	panel.set_sit_state(AutonomyBridge.can_sit(autonomy.surface_mode, _support, motion.vrma_clips.has(AutonomyBridge.SIT_CLIP), _sit_active), _sit_active)


func support_contact() -> Dictionary:
	return _support


func is_sitting() -> bool:
	return _sit_active


func _on_support_changed(contact: Dictionary) -> void:
	_support = contact
	if _sit_pending and not bool(contact.get("attached", false)):
		_sit_pending = false
	if _sit_active:
		if bool(contact.get("attached", false)) and str(contact.get("pose", "")) == "sit":
			_sit_attached = true
			_push_autonomy_context() # hold from this frame on: no new targets while seated
		elif _sit_attached and not bool(contact.get("attached", false)):
			# The window under us moved/closed, or the geometry went stale: stand and let the
			# module re-seat with foot contact after its settle.
			_stand_up("지지면이 사라져 다시 일어섭니다")
	# Detached while standing (drag, moved window): the standing pivot stays; nothing to undo.
	_refresh_sit_button()
	_refresh_autonomy_label()


## Manual sit: seated pose from the motion owner (loops sit_idle, lower body stays seated under
## later gestures), pivot moves to the seat pixel so scaling keeps the seat still, and the module
## re-seats the window so the seat anchor rests on the current support (legs hang below its top).
func _request_sit() -> void:
	if _sit_active or _sit_pending or not AutonomyBridge.can_sit(autonomy.surface_mode, _support, motion.vrma_clips.has(AutonomyBridge.SIT_CLIP), false):
		panel.set_status_message("지지면에 서 있을 때 앉을 수 있습니다")
		return
	_sit_pending = true
	_set_panel_open(false) # The button explicitly enters pet mode; never move an open panel.
	_push_autonomy_context()
	_refresh_autonomy_label()


## Wait for pointer/dialogue/settle policy before changing the body or support anchor.
## Reopening the panel or losing the original support cancels this pending intent.
func _advance_pending_sit() -> void:
	if not _sit_pending or panel_open or not autonomy.enabled:
		return
	if autonomy.state not in ["walk", "inspect", "rest"]:
		return
	if not AutonomyBridge.can_sit(autonomy.surface_mode, _support, motion.vrma_clips.has(AutonomyBridge.SIT_CLIP), false):
		_sit_pending = false
		_refresh_autonomy_label()
		return
	_sit_pending = false
	if not motion.start_contact_pose("sit"):
		panel.set_status_message("앉기 실패: 모션 플레이어가 sit_idle 을 시작하지 못했습니다")
		return
	_sit_active = true
	_sit_attached = false
	_walk_started = ""
	_floating = false
	_switch_pivot("sit")
	autonomy.set_contact_pose("sit")
	_refresh_sit_button()
	_refresh_autonomy_label()


## Stand up (button, drag, character change, surface mode off, lost support): standing pose,
## pivot back to the foot, module pose "foot" so it re-seats with foot contact and roaming resumes.
func _stand_up(message: String) -> void:
	_sit_pending = false
	if not _sit_active:
		return
	_sit_active = false
	_sit_attached = false
	if motion.current_contact_pose() != "foot":
		motion.stop_contact_pose()
	_switch_pivot("foot")
	autonomy.set_contact_pose("foot")
	if not message.is_empty():
		panel.set_status_message(message)
	_refresh_sit_button()
	_refresh_autonomy_label()


## Change the scale/turn pivot without moving the body: the new pivot starts at its current
## projected pixel. Standing eases back to the canonical foot pixel (bottom of the pet zone).
func _switch_pivot(kind: String) -> void:
	if kind == _pivot_kind:
		return
	if avatar.has_model() and _pivot_local.has(kind):
		var world: Vector3 = avatar.global_transform * _pivot_local[kind]
		_pivot_px = camera.unproject_position(world) if not camera.is_position_behind(world) else _pivot_px
	_pivot_kind = kind
	_pivot_px_target = _pivot_px if kind == "sit" else AutonomyBridge.foot_pivot_px(Vector2(WINDOW_SIZE), PET_ZONE_WIDTH)


## Public hook for future perception/owned-task sources: "something of interest is at this global
## desktop point". This host never captures or reads the screen; callers supply the point.
## kind: "external" | "owned_task" | ... (free-form, forwarded to the autonomy module).
func observe_interest(id: String, screen_point: Vector2, confidence: float = 0.5, ttl: float = 20.0, kind: String = "external") -> void:
	if autonomy != null:
		autonomy.observe_interest(id, screen_point, confidence, ttl, kind)


func autonomy_state() -> String:
	return _autonomy_state


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Key/button releases can occur in another application. Never keep a manual
		# recording or drag latched until the 30-second microphone safety limit.
		_ptt_key_down = false
		if mic != null and mic.is_recording() and mic._record_source == "ptt":
			mic.cancel_recording() # No utterance is submitted on focus loss; VAD stays opt-in.
		var moved := _drag_active and _drag_moved
		_drag_active = false
		_drag_moved = false
		if moved:
			_save_window_position()
		if autonomy != null and panel != null and handle_button != null:
			_push_autonomy_context()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		world_source.stop() # terminate only our own geometry helper
		_save_window_position()
		Settings.save_now()
		var id := session.cancel_turn()
		if not id.is_empty():
			client.send(session.make_cancel(id))
		_cancel_job()
