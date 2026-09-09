extends Node3D
## Desktop pet host: transparent always-on-top window, VRM pet on the right,
## control panel on the left (collapsible to a pure pet with mouse passthrough
## outside the pet region), and the wiring between backend, session, audio,
## microphone, motion and UI.

const REFERENCE_SIZE := Vector2i(680, 760)
const RENDER_PADDING := Vector2i(620, 500)
const WINDOW_SIZE := REFERENCE_SIZE + RENDER_PADDING * 2
const PANEL_MARGIN := 8.0
## Everything right of the panel (window width - panel - margins) belongs to the pet.
const PET_ZONE_WIDTH := float(REFERENCE_SIZE.x) - ControlPanel.PANEL_WIDTH - 2.0 * PANEL_MARGIN
const DRAG_THRESHOLD := 6.0
const SUBTITLE_HOLD := 7.0
# Lighting (see _setup_scene): verified only by code inspection here; root re-checks on Windows.
const SUN_ENERGY := 0.8
const FILL_ENERGY := 0.3
const AMBIENT_ENERGY := 0.45
const TONEMAP_EXPOSURE := 0.85

var _last_render_size:=Vector2.ZERO
var _last_render_origin:=Vector2.ZERO
var render_diagnostics:Dictionary={}

var avatar: VrmAvatar
var motion: MotionPlayer
var audio: AudioOutput
var mic: Microphone
var client: BackendClient
var session := CompanionSession.new()
var autonomy: DesktopAutonomy # window roaming (Astra-owned module); policy in AutonomyBridge
var world_source: DesktopWorldSource # Windows window/monitor rectangles at 1 Hz (Astra-owned; geometry only)
var bridge := AutonomyBridge.new()
var living: Node # local behavior/attention and user/LLM intention coordinator
var scene_navigation: Node
var objects: Node # native desktop props and their approach/contact lifecycle
var panel: ControlPanel
var panel_window: Window
var _camera_pivot_depth := 3.6
var _view_settings: Dictionary = {}
var _spatial_viewport: SubViewport
var _spatial_reference_camera: Camera3D
var _spatial_origin := Vector2.INF
var camera: Camera3D
var ui_layer: CanvasLayer
var handle_button: Button
var handle_dot: ColorRect
var subtitle: Label
var loading_label: Label

var panel_open := false
var pet_rect := Rect2(WINDOW_SIZE.x - PET_ZONE_WIDTH + 60, 120, 220, 560)
var _unclipped_pet_rect := pet_rect # projected body rect before clipping to the window
var _model_aabb := AABB(Vector3(-0.4, 0, -0.3), Vector3(0.8, 1.6, 0.6))
var _projection_geometry := preload("res://scripts/projected_avatar_geometry.gd").new()
var _projection_follow_state: Dictionary = {}
var _standing_floor_y := NAN
var _standing_floor_id := ""
var _standing_projection_error := ""
var _projection_world_before := Vector3.INF
var _committed_projection_delta: Variant = null
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
var _avatar_loading_variant := "default"
var _avatar_variant_command := {}
var _avatar_variant_seen := {}
var avatar_variant_outcomes: Array = []
var _selection_announced := "" # character id last sent as select_character on this connection
var _preserving_body_turn := false
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
var floor_rest_admission:Dictionary={}
var _floor_pending_scale:=NAN
var _floor_pending_view:=false
var _floor_rest_owned:=false
var _floor_exit_requested:=false
var _floor_support_id:=""
var _floor_navigation_rect:=Rect2()
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
	_set_panel_open("--panel" in OS.get_cmdline_user_args(), false)
	var vad_saved := bool(Settings.get_value("vad_enabled", false))
	mic.set_vad_enabled(vad_saved)
	panel.set_vad_enabled(mic.vad_enabled)
	_update_input_mode()
	_pet_scale_target = AutonomyBridge.clamp_scale(float(Settings.get_value("pet_scale", AutonomyBridge.SCALE_DEFAULT)))
	_pet_scale = _pet_scale_target
	_pivot_px_target = _default_foot_pixel()
	_pivot_px = _pivot_px_target
	panel.set_pet_scale(_pet_scale_target)
	# Roaming: the module reads the window, the visible pet rect and the projected contact anchors;
	# it starts blocked and only moves in collapsed pet mode once update_context() (per frame,
	# below) clears every block.
	autonomy.configure(get_window(), _navigation_rect, _projected_anchors)
	autonomy.projection_commit_callback = _finalize_projection_placement
	autonomy.set_heading_ready_provider(func(): return motion.locomotion_ready(), 0.25)
	autonomy.set_enabled(bool(Settings.get_value("autonomy_enabled", true)))
	autonomy.set_speed(float(Settings.get_value("autonomy_speed", 75.0)))
	_apply_surface_mode()
	_refresh_autonomy_label()
	_refresh_sit_button()
	living = load("res://scripts/living_behavior.gd").new()
	living.name = "LivingBehavior"
	add_child(living)
	living.configure(self)
	objects = load("res://scripts/desktop_objects_host.gd").new()
	objects.name = "DesktopObjects"
	add_child(objects)
	objects.configure(self)
	scene_navigation = load("res://scripts/desktop_scene_navigation_host.gd").new()
	add_child(scene_navigation)
	scene_navigation.configure(self)
	client.connect_ws()
	client.fetch_characters()
	client.fetch_motions()
	client.fetch_motion_assets()
	panel.set_status_message("백엔드 %s 에 연결 중…" % client.base_url)


# ----------------------------------------------------------------- setup

func _setup_window() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_size = Vector2i.ZERO
	win.content_scale_factor = 1.0
	win.size = WINDOW_SIZE
	win.borderless = true
	win.minimize_disabled = true
	win.maximize_disabled = true
	win.unresizable = true
	win.always_on_top = true
	win.transparent = true
	win.transparent_bg = true
	win.title = "Mate Companion"
	# Named interest markers are separate desktop windows, not child overlays.
	get_tree().root.gui_embed_subwindows = false
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	_restore_window_position()
	RenderingServer.frame_post_draw.connect(_remember_render_origin)


func _remember_render_origin() -> void:
	# Legacy autonomy and scene navigation can move after main._process. Keep
	# the last fully rendered origin, not the origin from before that travel.
	if _last_render_size == render_size() and _last_render_size == Vector2(get_window().size):
		_last_render_origin = Vector2(get_window().position)


func _restore_window_position() -> void:
	# Negative origins are valid on multi-monitor desktops; validity = the window still touches a
	# current monitor (AutonomyBridge.restore_position), not the sign of the coordinates.
	var screens: Array = []
	for i in DisplayServer.get_screen_count():
		screens.append(DisplayServer.screen_get_usable_rect(i))
	var fallback := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Persist the character's screen anchor, not the transparent render margin.
	# Legacy settings describe the original 680x760 canvas. Keeping that origin
	# with a larger foot pixel moved the character and changed its off-axis view.
	var reference_foot := AutonomyBridge.foot_pivot_px(Vector2(REFERENCE_SIZE), PET_ZONE_WIDTH)
	DisplayServer.window_set_position(AutonomyBridge.restore_render_position(Settings.data,
		REFERENCE_SIZE, reference_foot, _default_foot_pixel(), screens, fallback))


func _save_window_position() -> void:
	var p := DisplayServer.window_get_position()
	Settings.set_value("window_x", p.x)
	Settings.set_value("window_y", p.y)
	var foot := _default_foot_pixel()
	if avatar != null and avatar.has_model() and camera != null:
		foot = camera.unproject_position(avatar.contact_anchors().foot)
	Settings.set_value("window_foot_x", p.x + foot.x)
	Settings.set_value("window_foot_y", p.y + foot.y)
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
	# A projection-only reference camera defines an invariant desktop world.
	# Native windows render crops; moving the pet window never moves this camera.
	_spatial_viewport = SubViewport.new()
	_spatial_viewport.name = "DesktopSceneReference"
	_spatial_viewport.size = REFERENCE_SIZE
	_spatial_viewport.own_world_3d = true
	_spatial_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_spatial_viewport)
	_spatial_reference_camera = Camera3D.new()
	_spatial_viewport.add_child(_spatial_reference_camera)
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
	motion.floor_rest.finished.connect(_on_floor_rest_finished)
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
	panel_window = load("res://scripts/companion_panel_window.gd").new()
	add_child(panel_window)
	panel_window.configure(panel, _global_pet_rect(), _current_workarea())
	panel_window.closed.connect(func(): _set_panel_open(false))
	panel_window.hotkey.connect(_panel_hotkey)
	panel_window.panel_focus_lost.connect(_release_panel_input)

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
	# Register before living behavior's post-move foot correction.
	autonomy.frame_moved.connect(func(_displacement: Vector2, _velocity: Vector2):
		if scene_navigation != null and scene_navigation.owns_foot():return
		if spatial_camera() != null:
			_refresh_spatial_crop()
			_update_avatar_transform(0.0))
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

	autonomy.state_changed.connect(_on_autonomy_state_changed)
	autonomy.locomotion_changed.connect(_on_locomotion)
	autonomy.support_changed.connect(_on_support_changed)
	world_source.snapshot_changed.connect(func(snapshot: Dictionary): autonomy.set_world_snapshot(snapshot))
	autonomy.target_chosen.connect(func(_id: String, screen_point: Vector2, _kind: String):
		var here := Vector2(get_window().position) + pet_rect.get_center()
		_travel_dir = clampf((screen_point.x - here.x) / 400.0, -1.0, 1.0)
		# A replacement target can arrive while already anticipating; state_changed
		# would not fire again. Every accepted destination must update heading.
		if autonomy.state == "anticipate":
			motion.prepare_locomotion(autonomy.target - autonomy.position))

	session.event_accepted.connect(_on_event)
	session.event_discarded.connect(func(ev: Dictionary, reason: String):
		if str(ev.get("type", "")) == "audio":
			return
		print("[session] discarded %s: %s" % [ev.get("type", "?"), reason]))
	session.turn_started.connect(func(id: String):
		_action_seen_turn = ""
		audio.begin_turn(id))
	session.turn_finished.connect(func(id: String, outcome: String):
		if outcome != "done":
			audio.cancel()
			if not _preserving_body_turn and not session.is_owned_job_turn(id) and not body_action_can_continue(): motion.stop_gesture())
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
	panel.avatar_variant_selected.connect(func(id: String): request_avatar_variant(id))
	panel.refresh_requested.connect(func():
		client.fetch_characters()
		client.fetch_motions()
		client.fetch_motion_assets()
		client.check_health())
	panel.reload_avatar_requested.connect(func(): _load_avatar_for(session.character_id, true))
	panel.preview_gesture.connect(func(name: String, emotion: String, intensity: float, speed: float, repeat: int):
		if not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
			motion.play_upper_body_gesture(name, intensity, speed, repeat)
			motion.set_emotion(emotion)
		elif not motion.play_gesture(name, emotion, intensity, speed, repeat, true):
			motion.set_emotion(emotion))
	panel.preview_motion.connect(func(m: Dictionary): motion.play_motion_dict(m, 1.0, 1.0, 1))
	panel.preview_sequence.connect(func(first: String, second: String, lead: float):
		var result := motion.play_gesture_sequence(first, second, lead, true)
		if not bool(result.get("accepted", false)):
			panel.set_motion_result("이어보기 실패: " + str(result.get("reason", "동작을 시작할 수 없습니다")), false))
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
			if objects != null and objects.request_stand(): return
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
	# A successful catalogue replacement revokes removed capabilities immediately.
	# Re-admit cached clips only through the normal checksum-verified callback.
	if not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
		autonomy.cancel_target("motion_catalog_refresh")
		motion.stop_gesture()
		_walk_started = ""
	_vrma_loaded.clear()
	motion.clear_locomotion_registrations()
	if objects != null and (motion.seated_transition.active or motion.current_contact_pose() == "sit"):
		objects.cancel_interaction("motion_catalog_refresh")
	motion.clear_seated_transition_registrations()
	panel.set_vrma_clips(_vrma_loaded)
	_vrma_catalog.clear()
	_vrma_pending = 0
	for e in entries:
		_vrma_catalog[str(e["name"])] = e
		_vrma_pending += 1
		client.fetch_motion_asset(e)
	if entries.is_empty():
		panel.set_motion_result("VRMA 카탈로그 비어 있음 · 내장 프리셋만 사용", true)
		_apply_ambient_idle()
		_refresh_sit_button()
	else:
		panel.set_motion_result("VRMA 클립 %d개 받는 중… (%s)" % [entries.size(), message], true)


## One clip cached + checksum verified -> hand it to the motion owner (read-only clip).
func _on_motion_asset_ready(ok: bool, name: String, path: String, message: String) -> void:
	_vrma_pending = maxi(_vrma_pending - 1, 0)
	if ok and _vrma_catalog.has(name):
		if motion.load_vrma(name, path, str(_vrma_catalog[name].get("contact_mode", ""))):
			_vrma_loaded[name] = _vrma_catalog[name]
			if bool(_vrma_catalog[name].get("locomotion", false)):
				motion.register_locomotion_clip(name, bool(_vrma_catalog[name].get("locomotion_preserve_hips", false)))
				motion.register_locomotion_style(name, Dictionary(_vrma_catalog[name].get("locomotion_style", {})))
			var seated_kind := str(_vrma_catalog[name].get("seated_transition", ""))
			if not seated_kind.is_empty(): motion.register_seated_transition(seated_kind,name)
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
	var profile_loop := str(session.character_by_id(session.character_id).get("ambient_loop", ""))
	if setting == "auto" and has_api and _vrma_loaded.has(profile_loop):
		choice = profile_loop
	if choice != _ambient_clip or (has_api and choice.is_empty() and not _ambient_clip.is_empty()):
		_ambient_clip = choice
		if has_api:
			motion.call("set_ambient_loop", choice)


func _load_avatar_for(character_id: String, force: bool, variant_override: String = "") -> void:
	if character_id.is_empty():
		return
	if not _avatar_variant_command.is_empty() and _avatar_variant_command.get("character","") != character_id:
		cancel_avatar_variant("","cancelled","character_changed")
	var info := session.character_by_id(character_id)
	var preferences: Dictionary = Settings.get_value("avatar_variant_choices",{})
	var variant := variant_override if not variant_override.is_empty() else str(preferences.get(character_id,"default"))
	if variant_override.is_empty() and _avatar_variant_command.get("character","") == character_id:
		variant = str(_avatar_variant_command.variant)
	var entry := _avatar_variant_entry(character_id,variant)
	if entry.is_empty():
		cancel_avatar_variant("","cancelled","variant_unavailable")
		variant = "default"
		entry = _avatar_variant_entry(character_id,variant)
	var url := str(entry.get("avatar_url",info.get("avatar_url","")))
	_avatar_loading_for = character_id
	_avatar_loading_variant = variant
	_pending_avatar_path = ""
	panel.set_avatar_variants(info.get("avatar_variants",[]),variant)
	loading_label.text = "아바타 받는 중: %s" % str(info.get("name", character_id))
	loading_label.visible = true
	# Variant catalogues currently have no content hash. Refresh these local
	# downloads so a former wet default cannot survive a newly installed dry one.
	client.fetch_avatar(character_id,url,force or not info.get("avatar_variants",[]).is_empty(),variant)


func _on_avatar_ready(ok: bool, character_id: String, path: String, message: String) -> void:
	if character_id != session.character_id:
		return # latest-only: a newer selection superseded this download
	if not ok:
		loading_label.text = "아바타 실패: " + message
		panel.set_status_message(message)
		_finish_avatar_variant("failed","avatar_download_failed")
		return
	if path != BackendClient.avatar_cache_path(character_id,_avatar_loading_variant): return
	loading_label.text = "아바타 불러오는 중…"
	_pending_avatar_path = path
	call_deferred("_apply_avatar", character_id, path, message)


func _apply_avatar(character_id: String, path: String, message: String) -> void:
	if character_id != session.character_id or path != _pending_avatar_path:
		return
	_clear_avatar_contact()
	_stand_up("") # reset_all() below drops the seated pose; keep the module's pose in step
	motion.reset_all()
	var loaded := avatar.load_from_file(ProjectSettings.globalize_path(path))
	loading_label.visible = not loaded
	if not loaded:
		loading_label.text = "VRM 로드 실패"
		panel.set_avatar_info("VRM 로드 실패: " + path)
		_finish_avatar_variant("failed","avatar_load_failed")
		return
	_frame_avatar()
	var preferences: Dictionary = Settings.get_value("avatar_variant_choices",{}).duplicate(true)
	preferences[character_id] = _avatar_loading_variant
	Settings.set_value("avatar_variant_choices",preferences)
	panel.set_avatar_variants(session.character_by_id(character_id).get("avatar_variants",[]),_avatar_loading_variant)
	_finish_avatar_variant("completed","avatar_loaded")
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
	_standing_floor_y = NAN
	_standing_floor_id = ""
	_projection_follow_state.clear()
	avatar.transform = Transform3D.IDENTITY
	_model_aabb = avatar.compute_aabb()
	var anchors := avatar.contact_anchors() # avatar at identity: global == avatar-local
	var bottom := Vector3(_model_aabb.get_center().x, _model_aabb.position.y, _model_aabb.get_center().z)
	_pivot_local = {
		"foot": anchors.get("foot", bottom),
		"sit": anchors.get("sit", bottom + Vector3(0, _model_aabb.size.y * 0.45, 0)),
	}
	_projection_geometry.capture(avatar, _pivot_local.foot)
	var foot_px := _default_foot_pixel()
	_apply_view_settings(false)
	_pivot_kind = "foot"
	_pivot_px_target = foot_px
	_pivot_px = foot_px
	_update_avatar_transform(0.0)
	# Initial retargeting and screen placement are not physical motion. Seed
	# spring history in this final frame so an import cannot fling the clothes.
	avatar.rebase_secondary_physics()
	_update_pet_rect()


## View orientation is independent of avatar/object yaw. Both projection modes
## reconstruct the exact screen anchor at a declared optical-axis depth.
func _apply_view_settings(refresh_objects: bool = true) -> void:
	if _floor_rest_owned and motion.floor_rest.active:
		_floor_pending_view=true
		_stand_up("자세를 정리한 뒤 시점을 바꿉니다")
		return
	var requested := {}
	for key in ["view_yaw_deg", "view_pitch_deg", "view_height", "view_zoom"]:
		requested[key] = Settings.get_value(key, 1.0 if key == "view_zoom" else 0.0)
	var bounded := DesktopView.clamp_settings({"yaw_deg":requested.view_yaw_deg, "pitch_deg":requested.view_pitch_deg,
		"height_m":requested.view_height, "zoom":requested.view_zoom,
		"projection":Settings.get_value("view_projection", "perspective"),
		"fov_deg":Settings.get_value("view_fov_deg", 45.0),
		"distance_m":Settings.get_value("view_distance_m", 3.6)})
	_view_settings = {"view_yaw_deg":bounded.yaw_deg, "view_pitch_deg":bounded.pitch_deg,
		"view_height":bounded.height_m, "view_zoom":bounded.zoom,
		"view_projection":bounded.projection, "view_fov_deg":bounded.fov_deg,
		"view_distance_m":bounded.distance_m}
	var foot_px := _default_foot_pixel()
	# The original orthographic frame uses 28 degrees only to select its depth.
	# Switching lenses must not alter that baseline on return to orthographic.
	var cam := AutonomyBridge.pet_camera(_model_aabb.size.y, 28.0, render_size(), foot_px,
		AutonomyBridge.reference_height_px(float(REFERENCE_SIZE.y)))
	for key in _view_settings: Settings.set_value(key, _view_settings[key])
	# Shared off-axis crops must draw the same pixel-width MToon outline.
	# Zero selects the unchanged legacy branch outside the shared scene mode.
	DesktopView.set_outline_reference_height(avatar, float(REFERENCE_SIZE.y) if bounded.projection == "perspective" else 0.0,
		Vector2(REFERENCE_SIZE) if bounded.projection == "orthographic" else Vector2.ZERO)
	var zoom := float(_view_settings.get("view_zoom", 1.0))
	_px_per_m = float(cam.px_per_m) * zoom
	DesktopView.configure_projection(camera, bounded.projection, float(cam.size), bounded.fov_deg, zoom)
	var position: Vector3 = cam.position
	position.x /= zoom
	position.y /= zoom
	if bounded.projection == "perspective":
		position.z = bounded.distance_m
		_px_per_m = float(REFERENCE_SIZE.y) / (2.0 * position.z * tan(deg_to_rad(camera.fov) * 0.5))
		var centre := Vector2(REFERENCE_SIZE) * 0.5
		var reference_foot := AutonomyBridge.foot_pivot_px(Vector2(REFERENCE_SIZE), PET_ZONE_WIDTH)
		position.x = -(reference_foot.x - centre.x) / _px_per_m
		position.y = (reference_foot.y - centre.y) / _px_per_m
	var basis := DesktopView.orbit_basis(float(_view_settings.get("view_yaw_deg", 0.0)),
		float(_view_settings.get("view_pitch_deg", 0.0)), float(_view_settings.get("view_height", 0.0)),
		bounded.distance_m if bounded.projection == "perspective" else 3.6)
	camera.transform = Transform3D(basis, basis * position)
	_camera_base = camera.position
	_camera_pivot_depth = position.z
	if bounded.projection == "perspective":
		if not _spatial_origin.is_finite():
			_spatial_origin = Vector2(_current_workarea().get_center()) - Vector2(REFERENCE_SIZE) * 0.5
		DesktopView.configure_projection(_spatial_reference_camera, "perspective", float(cam.size), bounded.fov_deg, zoom)
		_spatial_reference_camera.near = camera.near
		_spatial_reference_camera.far = camera.far
		_spatial_reference_camera.transform = camera.transform
		_refresh_spatial_crop()
	motion.view_yaw_radians = deg_to_rad(float(_view_settings.get("view_yaw_deg", 0.0)))
	if panel != null: panel.set_view_settings(_view_settings)
	if refresh_objects and avatar.has_model():
		_update_avatar_transform(0.0)
		_update_pet_rect()
		if objects != null and objects.has_method("refresh_view"): objects.refresh_view()
		# A user camera edit changes the presentation frame, not cloth velocity.
		avatar.rebase_secondary_physics()
		if panel_open and Rect2i(panel_window.position, panel_window.size).intersects(_global_pet_rect()):
			panel_window.open_next_to(_global_pet_rect(), _current_workarea())


## Canonical metre frame: fixed orbit target at world origin, +Y up, +Z back.
## Its nominal film rectangle is REFERENCE_SIZE; render padding changes only crops.
## Crops outside that rectangle remain exact, including neighboring monitors.
func render_size() -> Vector2:
	var extent:=get_viewport().get_visible_rect().size
	return extent if extent.x>0 and extent.y>0 else Vector2(get_window().size)

func _default_foot_pixel() -> Vector2:
	var reference_foot:=AutonomyBridge.foot_pivot_px(Vector2(REFERENCE_SIZE),PET_ZONE_WIDTH)
	return RenderSurface.foot_pixel(render_size(),Vector2(REFERENCE_SIZE),reference_foot,Vector2(RENDER_PADDING))

## Rebase a changed render crop before any projected contact is consumed.
## Moving its transparent margin must not count as character locomotion.
func _sync_render_surface() -> bool:
	var extent:=render_size()
	if extent.distance_to(Vector2(get_window().size))>.01:
		render_diagnostics={"ready":false,"reason":"native_viewport_resize_pending","viewport":extent,"native":get_window().size}
		return false
	if _last_render_size==Vector2.ZERO:
		_last_render_size=extent;_last_render_origin=Vector2(get_window().position)
		return true
	if extent==_last_render_size:
		_last_render_origin=Vector2(get_window().position)
		return true
	var reference_foot:=AutonomyBridge.foot_pivot_px(Vector2(REFERENCE_SIZE),PET_ZONE_WIDTH)
	var before:=RenderSurface.foot_pixel(_last_render_size,Vector2(REFERENCE_SIZE),reference_foot,Vector2(RENDER_PADDING))
	var after:=_default_foot_pixel()
	var shift:=after-before
	var origin:=_last_render_origin-shift
	var desktop_shift:=Vector2.ZERO
	var anchor:=_last_render_origin+_pivot_px
	var on_screen:=false
	for i in DisplayServer.get_screen_count():
		if Rect2(DisplayServer.screen_get_usable_rect(i)).has_point(anchor):on_screen=true;break
	if not on_screen:
		var area:=Rect2(_current_workarea()).grow(-16)
		desktop_shift=anchor.clamp(area.position,area.end)-anchor
		origin+=desktop_shift
	get_window().position=Vector2i(origin.round())
	origin=Vector2(get_window().position)
	shift=_last_render_origin-origin+desktop_shift
	_pivot_px+=shift;_pivot_px_target+=shift
	if _floor_rest_owned:_floor_navigation_rect.position+=shift
	if spatial_camera()!=null:
		_spatial_origin+=desktop_shift
	else:
		RenderSurface.resize_orthographic(camera,_last_render_size,extent,origin-_last_render_origin,_px_per_m,desktop_shift)
		_camera_base=camera.position
	if autonomy!=null:autonomy.rebase_render_origin(origin-autonomy.position)
	_last_render_size=extent;_last_render_origin=origin
	_refresh_spatial_crop()
	if objects!=null:objects.refresh_view()
	if living!=null:living._refresh_at=0.0
	render_diagnostics={"ready":true,"viewport":extent,"native":get_window().size,"desktop_shift":desktop_shift,"pixels_per_metre":_px_per_m}
	return true


func spatial_camera() -> Camera3D:
	return _spatial_reference_camera if _view_settings.get("view_projection") == "perspective" else null


func spatial_desktop_origin() -> Vector2:
	return _spatial_origin


func _refresh_spatial_crop() -> void:
	if spatial_camera() == null or not _spatial_origin.is_finite(): return
	var origin := autonomy.position.round() if autonomy != null and autonomy._simulation else Vector2(get_window().position)
	var ready:=DesktopView.configure_crop(camera, _spatial_reference_camera,
		Rect2(origin - _spatial_origin, render_size()))
	render_diagnostics["crop_ready"]=ready


## Place the avatar so the current pivot (stable rest foot, or seat while sitting) sits exactly at
## its window pixel for the smoothed scale and the facing yaw MotionPlayer applied this frame.
## Runs after MotionPlayer (priority -10) and before DesktopAutonomy (child) reads the anchors.
func _update_avatar_transform(delta: float) -> void:
	if not avatar.has_model() or _pivot_local.is_empty():
		return
	_refresh_spatial_crop()
	if delta > 0.0:
		_pet_scale = AutonomyBridge.smooth_scale(_pet_scale, _pet_scale_target, delta)
		var k := 1.0 - pow(1.0 - AutonomyBridge.SCALE_SMOOTH_FACTOR, delta * 60.0)
		_pivot_px = _pivot_px_target if _pivot_px.distance_to(_pivot_px_target) < 0.05 else _pivot_px.lerp(_pivot_px_target, k)
	var basis := Basis.from_euler(Vector3(0.0, avatar.rotation.y, 0.0)).scaled(Vector3.ONE * _pet_scale)
	var pivot_world := DesktopView.screen_to_world_at_depth(camera, _pivot_px, _camera_pivot_depth)
	var presenting: bool = objects != null and objects.has_method("has_presentation_transition") and objects.has_presentation_transition()
	_standing_projection_error = ""
	if spatial_camera() != null and _pivot_kind == "foot" and not _sit_active and not presenting and is_finite(_standing_floor_y) and not _standing_floor_id.is_empty():
		var intersection := DesktopView.solve_screen_at_world_y(camera, _pivot_px, _standing_floor_y)
		if bool(intersection.ok):
			pivot_world = intersection.point
		elif str(intersection.reason) != "parallel":
			# Never silently replace a finite physical floor with another plane.
			_standing_projection_error = str(intersection.reason)
			return
	if scene_navigation != null and scene_navigation.owns_foot() and _pivot_kind == "foot" and not _sit_active:
		pivot_world = scene_navigation.foot_world
	if not pivot_world.is_finite(): return
	if spatial_camera() != null:
		_camera_pivot_depth = DesktopView.depth(camera, pivot_world)
		var axes := DesktopView.projection_axes(camera, pivot_world)
		if not axes.is_empty(): _px_per_m = float(axes.screen_pixels_per_metre)
	avatar.transform = AutonomyBridge.pivot_transform(basis, pivot_world, _pivot_local.get(_pivot_kind, Vector3.ZERO))
	if objects != null and objects.has_method("presentation_offset"):
		avatar.position += objects.presentation_offset()


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
	if out.has("foot"):
		out["foot_center"] = out.foot
		if not _sit_active and _projection_geometry.valid_for(avatar):
			# Use the current heading's real rest silhouette, never animated
			# bone noise or a worst-heading lower edge that makes shoes hover.
			var bounds: Rect2 = _standing_navigation_rect()
			# Native window origins are integer pixels. Rounding this edge up
			# keeps committed floor destinations inside the exact safety bounds.
			if bounds.has_area(): out.foot = Vector2(out.foot.x, ceilf(bounds.end.y))
	return out


func pet_scale() -> float:
	return _pet_scale


func _set_scale_target(value: float) -> void:
	var clamped := AutonomyBridge.clamp_scale(value)
	if _floor_rest_owned and motion.floor_rest.active:
		_floor_pending_scale=clamped
		panel.set_pet_scale(clamped)
		_stand_up("자세를 정리한 뒤 크기를 바꿉니다")
		return
	if is_equal_approx(clamped, _pet_scale_target):
		return
	if objects!=null and objects._interaction.get("stage","") in ["chair_setup","chair_restore"]:
		objects.cancel_interaction("actor_scale_changed")
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
			_note_body_dialogue()
			var t := str(ev.get("text", ""))
			panel.update_live_reply(t, false)
			_show_subtitle(t)
		"audio":
			_note_body_dialogue()
			audio.push_event(ev)
		"action":
			_action_seen_turn = str(ev.get("turn_id", session.turn_id))
			# Direct action notifications may animate the upper body over an owned walk;
			# ordinary chat already requests a safe stop before speech.
			_note_body_dialogue()
			_play_dialogue_action(ev)
		"done":
			_note_body_dialogue()
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
				_play_dialogue_action(ev)
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
				if not session.is_background_presentation() and not body_action_can_continue(): motion.stop_gesture()
				panel.set_status_message("응답 오류로 음성을 중단했습니다")
		"voice_error":
			panel.append_transcript("system", "음성 오류: " + str(ev.get("message", "")))


func _play_dialogue_action(event: Dictionary) -> void:
	# An acknowledged furniture skill owns its locomotion/contact pose while
	# the same turn speaks. Face and voice may continue without replacing it.
	if session.is_background_presentation() or (objects != null and not objects._interaction.is_empty()):
		motion.set_emotion(str(event.get("emotion", "")))
		return
	var name := _dialogue_gesture_name(event)
	var intensity := float(event.get("intensity", 1.0))
	var speed := float(event.get("speed", 1.0))
	var repeat := int(event.get("repeat", 1))
	if not _walk_started.is_empty() and motion.current_gesture() == _walk_started:
		motion.play_upper_body_gesture(name, intensity, speed, repeat)
		motion.set_emotion(str(event.get("emotion", "")))
	else:
		_walk_started = ""
		motion.play_gesture(name, str(event.get("emotion", "")), intensity, speed, repeat)


func _dialogue_gesture_name(event: Dictionary) -> String:
	var requested := str(event.get("gesture", "idle"))
	# Travel and seated clips need verified geometry and contact ownership.
	# A spoken suggestion cannot start marching in place or drop the seat anchor.
	var entry: Dictionary = _vrma_catalog.get(requested, {})
	if requested in ["floor_rest_enter","floor_rest_idle","floor_rest_exit"] or requested in AutonomyBridge.WALK_CLIPS or requested == AutonomyBridge.SIT_CLIP \
			or bool(entry.get("locomotion", false)):
		return "idle"
	return requested


func _send_chat(text: String) -> void:
	if client.state != "open":
		panel.append_transcript("system", "백엔드에 연결되어 있지 않습니다")
		return
	_cancel_current(body_action_can_continue())
	_own_body_for_dialogue()
	var msg := session.make_chat(text)
	audio.begin_turn(msg["turn_id"])
	if living != null:
		living.publish_world(true)
	client.send(msg)
	panel.append_transcript("user", text)


func _on_utterance(wav: PackedByteArray, seconds: float, source: String) -> void:
	if client.state != "open":
		panel.append_transcript("system", "백엔드에 연결되어 있지 않습니다 (음성 %.1fs 버림)" % seconds)
		return
	_cancel_current(body_action_can_continue())
	_own_body_for_dialogue()
	var msg := session.make_audio(Marshalls.raw_to_base64(wav))
	audio.begin_turn(msg["turn_id"])
	if living != null:
		living.publish_world(true)
	client.send(msg)
	panel.append_transcript("user", "[음성 %.1f초 · %s · %d bytes]" % [seconds, "PTT" if source == "ptt" else "VAD", wav.size()])


func _cancel_current(preserve_body: bool = false) -> void:
	if not preserve_body:
		cancel_scene_approach("cancelled")
		if objects != null: objects.cancel_interaction("cancelled")
		if living != null: living.cancel("cancelled")
	cancel_avatar_variant("","cancelled","local_stop")
	motion.stop_upper_body_gesture()
	_preserving_body_turn = preserve_body
	var id := session.cancel_turn()
	_preserving_body_turn = false
	if not id.is_empty(): client.send(session.make_cancel(id))
	audio.cancel()
	if not preserve_body: motion.stop_gesture()


func _avatar_variant_entry(character_id: String, variant_id: String) -> Dictionary:
	var info: Dictionary = session.character_by_id(character_id)
	var variants: Array = info.get("avatar_variants",[])
	if variants.is_empty() and variant_id == "default":
		return {"id":"default","avatar_url":info.get("avatar_url",""),"avatar_available":info.get("avatar_available",true)}
	for entry in variants:
		if str(entry.get("id","")) == variant_id and bool(entry.get("avatar_available",false)): return entry
	return {}


func active_avatar_variant() -> String:
	var preferences: Dictionary = Settings.get_value("avatar_variant_choices",{})
	var variant := str(preferences.get(session.character_id,"default"))
	return variant if not _avatar_variant_entry(session.character_id,variant).is_empty() else "default"


func _clear_avatar_contact() -> void:
	if objects != null:
		objects.cancel_commands("avatar_changed")
		objects.cancel_interaction("avatar_changed")
	if living != null: living.cancel("avatar_changed")
	motion.cancel_seated_transition()
	_stand_up("")
	motion.reset_all()


## Same character/session: a constrained catalogue ID only. UI and LM share
## this path; downloaded bytes must actually load before completion feedback.
func request_avatar_variant(variant_id: String, intent_id: String = "", source: String = "user") -> Dictionary:
	if not intent_id.is_empty() and _avatar_variant_seen.has(intent_id): return {"accepted":false,"reason":"duplicate"}
	if not intent_id.is_empty():
		_avatar_variant_seen[intent_id] = true
		if _avatar_variant_seen.size()>128: _avatar_variant_seen.erase(_avatar_variant_seen.keys()[0])
	var entry := _avatar_variant_entry(session.character_id,variant_id)
	if entry.is_empty():
		_avatar_variant_feedback(intent_id,session.character_id,"rejected","unknown_variant")
		panel.set_status_message("이 캐릭터에서 사용할 수 없는 외형입니다")
		return {"accepted":false,"reason":"unknown_variant","feedback_sent":true}
	cancel_avatar_variant("","cancelled","superseded")
	_avatar_variant_command = {"id":intent_id,"character":session.character_id,"variant":variant_id,"source":source}
	_clear_avatar_contact()
	_load_avatar_for(session.character_id,true,variant_id)
	return {"accepted":true,"variant_id":variant_id}


func _avatar_variant_feedback(id: String, character_id: String, outcome: String, reason: String) -> void:
	avatar_variant_outcomes.append({"id":id,"character_id":character_id,"outcome":outcome,"reason":reason})
	if avatar_variant_outcomes.size()>128: avatar_variant_outcomes.pop_front()
	if id.ends_with(":intent") and client.state == "open":
		client.send({"type":"intent_result","character_id":character_id,"intent_id":id,"outcome":outcome,"reason":reason})


func _finish_avatar_variant(outcome: String, reason: String) -> void:
	if _avatar_variant_command.is_empty(): return
	var command := _avatar_variant_command.duplicate()
	_avatar_variant_command.clear()
	if outcome == "completed" and (command.character != session.character_id or command.variant != _avatar_loading_variant):
		outcome = "failed"
		reason = "avatar_identity_mismatch"
	_avatar_variant_feedback(str(command.id),str(command.character),outcome,reason)
	if living != null: living.publish_world(true)
	if outcome != "completed":
		var preferences: Dictionary = Settings.get_value("avatar_variant_choices",{})
		panel.set_avatar_variants(session.character_by_id(session.character_id).get("avatar_variants",[]),str(preferences.get(session.character_id,"default")))


func cancel_avatar_variant(intent_id: String = "", outcome: String = "cancelled", reason: String = "cancelled") -> void:
	if _avatar_variant_command.is_empty() or (not intent_id.is_empty() and _avatar_variant_command.id != intent_id): return
	_pending_avatar_path = ""
	client.cancel_avatar_fetch()
	_finish_avatar_variant(outcome,reason)


func _switch_character(id: String) -> void:
	if id == session.character_id or id.is_empty():
		return
	cancel_avatar_variant("","cancelled","character_changed")
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
	if key in ["view_yaw_deg", "view_pitch_deg", "view_height", "view_zoom", "view_projection", "view_fov_deg", "view_distance_m", "view_reset"]:
		if key == "view_reset":
			for field in ["view_yaw_deg", "view_pitch_deg", "view_height", "view_zoom", "view_projection", "view_fov_deg", "view_distance_m"]:
				Settings.set_value(field, Settings.DEFAULTS[field])
		else:
			Settings.set_value(key, value)
		_apply_view_settings()
		return
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


func _current_workarea() -> Rect2i:
	return DisplayServer.screen_get_usable_rect(get_window().current_screen)

func _global_pet_rect() -> Rect2i:
	var bounds := _unclipped_pet_rect
	if objects != null and objects.has_method("occupied_rect"):
		var occupied: Rect2 = objects.occupied_rect()
		if occupied.has_area(): bounds = bounds.merge(occupied)
	return Rect2i(Vector2(get_window().position) + bounds.position, bounds.size)

func _release_panel_input() -> void:
	_ptt_key_down = false
	if mic != null and mic.is_recording() and mic._record_source == "ptt":
		mic.cancel_recording()

func _panel_hotkey(action: String, pressed: bool) -> void:
	match action:
		"toggle_panel": _set_panel_open(not panel_open)
		"push_to_talk":
			if pressed and not _ptt_key_down:
				_ptt_key_down = true
				_ptt_down()
			elif not pressed and _ptt_key_down:
				_ptt_key_down = false
				_ptt_up()
		"toggle_vad": _set_vad(not mic.vad_enabled)
		"cancel":
			_cancel_current()
			if mic.is_recording(): mic.cancel_recording()


func _set_panel_open(open: bool, persist: bool = true) -> void:
	if open and _sit_pending:
		_sit_pending = false
		_refresh_sit_button()
	panel_open = open
	if panel_window != null:
		if open: panel_window.open_next_to(_global_pet_rect(), _current_workarea())
		else:
			_release_panel_input()
			panel_window.hide()
	handle_button.visible = not open
	handle_dot.visible = not open
	if persist:
		Settings.set_value("panel_open", open)
	if open:
		panel.focus_input()
		# The settings panel has its own window. Preserve explicit body actions;
		# spontaneous roaming still yields while the user is typing.
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
			_update_avatar_transform(0.0)
			_update_pet_rect()
			_save_window_position()
			if living != null and avatar.has_model():living.on_drag_released(Vector2(get_window().position)+camera.unproject_position(avatar.contact_anchors().foot))
		else:
			motion.pet_reaction()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Wheel over the pet resizes it (Unity AvatarScaleController behaviour). The panel's own
			# controls consume wheel events over the panel, and a drag in progress ignores it.
			var notches := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			var over_pet := pet_rect.grow(20).has_point(event.position)
			var wanted := AutonomyBridge.wheel_scale(_floor_pending_scale if is_finite(_floor_pending_scale) else _pet_scale_target, notches, _drag_active, over_pet)
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
				if living!=null:living.cancel("dragged")
				if autonomy!=null:autonomy._detach_support()
				if _sit_active:
					_stand_up("") # a manual drag releases the support; the module detaches too
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_set_panel_open(not panel_open)


# ----------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not _sync_render_surface():return
	_update_fps_cap()
	motion.mouth_open = audio.envelope
	_update_avatar_transform(delta)
	_projection_world_before = avatar.global_transform * Vector3(_pivot_local.get("foot",Vector3.ZERO)) if avatar.has_model() else Vector3.INF
	_update_pet_rect()
	_keep_pet_in_window()
	_push_autonomy_context()
	_follow_standing_projection()
	if living != null:
		living.tick(delta)
	if scene_navigation != null:
		scene_navigation.tick(delta)
	if objects != null:
		objects.tick(delta)
	_update_gaze()
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
	# Reserve all-heading horizontal clearance before a turn, just as desktop
	# navigation does. Fitting the current yaw alone moves the stable foot pivot
	# while shoulders widen, eventually invalidating its latched support anchor.
	var fit_rect := _navigation_rect() if _pivot_local.has("foot") else _unclipped_pet_rect
	var shift := AutonomyBridge.fit_shift(fit_rect, render_size())
	if fit_rect.size.x > render_size().x:
		# A conservative AABB radius can exceed the viewport at the largest scale.
		# Centre that envelope consistently; never chase its left/right yaw edges.
		shift.x = float(render_size().x) * 0.5 - fit_rect.get_center().x
	if shift != Vector2.ZERO:
		# Correct the current pivot, not the already-easing target: accumulating
		# overflow every frame overshoots and can clip the opposite edge.
		_pivot_px_target = _pivot_px + shift


## Desktop pets must not render unbounded: 60 fps while interacting/speaking/animating,
## 30 fps when idle (panel closed, no audio, no gesture, window unfocused).
func _update_fps_cap() -> void:
	var active := panel_open or audio.voice_active or motion.is_gesture_active() or _drag_active \
		or mic.is_recording() or DisplayServer.window_is_focused() or session.activity != "idle" \
		or _autonomy_state in ["walk", "approach", "anticipate"] or not motion.heading_ready() or _floating \
		or not is_equal_approx(_pet_scale, _pet_scale_target)
	if active != _fps_active or Engine.max_fps == 0:
		_fps_active = active
		Engine.max_fps = 60 if active else 30


func _update_pet_rect() -> void:
	if not avatar.has_model():
		return
	var box := _model_aabb
	var seated: Dictionary = avatar.get("seated_geometry") if avatar.get("seated_geometry") is Dictionary else {}
	var presenting: bool = objects != null and objects.has_method("has_presentation_transition") and objects.has_presentation_transition()
	if presenting:
		box = objects.presentation_bounds()
	elif _floor_rest_owned and motion.floor_rest.active:
		box = motion.floor_rest.profile.get("bounds_local",_model_aabb)
	elif _sit_active and not seated.is_empty():
		box = seated.bounds
	elif _projection_geometry.valid_for(avatar):
		var measured: Rect2 = _projection_geometry.body_rect(camera, avatar.global_transform)
		if measured.has_area():
			_unclipped_pet_rect = AutonomyBridge.body_rect(measured)
			pet_rect = _unclipped_pet_rect.intersection(Rect2(Vector2.ZERO, render_size()))
			return
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
		pet_rect = r.intersection(Rect2(Vector2.ZERO, render_size()))


func _update_gaze() -> void:
	if living != null and living.apply_attention():
		return
	var mouse := get_viewport().get_mouse_position()
	var inside := Rect2(Vector2.ZERO, render_size()).has_point(mouse) and DisplayServer.window_is_focused() or pet_rect.grow(120).has_point(mouse)
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


## Reserve enough horizontal room to turn before selecting an edge destination.
## The hit area still follows the visible projection; navigation uses a yaw-invariant
## envelope so widening shoulders during a reversal cannot invalidate its support.
func _navigation_rect() -> Rect2:
	if _floor_rest_owned and _floor_navigation_rect.has_area():return _floor_navigation_rect
	if objects != null and objects.has_method("has_presentation_transition") and objects.has_presentation_transition():
		return _unclipped_pet_rect
	var seated: Dictionary = avatar.get("seated_geometry") if avatar != null and avatar.get("seated_geometry") is Dictionary else {}
	if _sit_active and not seated.is_empty(): return _seated_navigation_rect()
	if not avatar.has_model() or not _pivot_local.has("foot"):
		return pet_rect
	if _projection_geometry.valid_for(avatar):
		return _standing_navigation_rect()
	var pivot: Vector3 = _pivot_local.foot
	var radius := 0.0
	for i in 8:
		var corner := _model_aabb.get_endpoint(i) - pivot
		radius = maxf(radius, Vector2(corner.x, corner.z).length())
	var foot: Vector2 = _projected_anchors().get("foot", pet_rect.get_center())
	var half_width := radius * _px_per_m * _pet_scale
	return Rect2(foot.x - half_width, _unclipped_pet_rect.position.y, half_width * 2.0, _unclipped_pet_rect.size.y)


## One-time scene admission normalization; callers own the actual placement.
## Never applies a continuous correction to a scene-owned ground trajectory.
func normalize_scene_ground_placement(world_foot: Vector3) -> Dictionary:
	if spatial_camera() == null or not _projection_geometry.valid_for(avatar) or objects == null:
		return {"ok":false,"point":world_foot,"reason":"scene_unavailable"}
	return _projection_geometry.nearest_safe_ground(spatial_camera(),world_foot,_pet_scale,
		spatial_desktop_origin(),objects.screen_rects(),0.25)


func _standing_navigation_rect() -> Rect2:
	var reserve: Rect2 = _projection_geometry.navigation_rect(camera, avatar.global_transform * Vector3(_pivot_local.foot), _pet_scale)
	var current: Rect2 = _projection_geometry.body_rect(camera, avatar.global_transform)
	return Rect2(reserve.position.x, reserve.position.y, reserve.size.x, current.end.y-reserve.position.y)


## Only a smooth heading change may follow a standing support's projected edge.
## Explicit drag, scale, view and contact changes retain ordinary detach policy.
func _follow_standing_projection() -> void:
	if scene_navigation != null and scene_navigation.owns_foot():
		_projection_follow_state.clear()
		return
	if not avatar.has_model():
		_projection_follow_state.clear()
		return
	var current := {"model":avatar.model.get_instance_id(), "yaw":avatar.rotation.y,
		"scale":_pet_scale, "view":_view_settings.duplicate(), "pivot":_pivot_px}
	var prior := _projection_follow_state
	_projection_follow_state = current
	if prior.is_empty() or autonomy == null or _sit_active or _drag_active or not _projection_geometry.valid_for(avatar): return
	if current.model != prior.model or not is_equal_approx(current.scale,prior.scale) or current.view != prior.view: return
	if not bool(autonomy.get_support_contact().get("attached",false)) or autonomy.contact_pose != "foot": return
	if objects != null and objects.has_method("has_presentation_transition") and objects.has_presentation_transition(): return
	var anchor: Vector2 = _projected_anchors().foot
	var locked: Vector2 = autonomy.get_support_contact().get("local_anchor",anchor)
	if absf(angle_difference(current.yaw,prior.yaw)) < 0.000001 and anchor.distance_to(locked) < 0.00001: return
	# Keep the known desktop edge without integer-window chasing. Only cached
	# rest geometry drives this correction; the physical standing plane stays
	# fixed by _update_avatar_transform. Final contact compensation runs once.
	for iteration in 6:
		var bounds := _standing_navigation_rect()
		var error := locked.y - 0.02 - bounds.end.y
		if absf(error) <= 0.002: break
		# Perspective ground-plane projection is not unit gain in screen Y.
		# Measure its local slope rather than oscillating around the edge.
		_pivot_px.y += 0.25
		_update_avatar_transform(0.0)
		var slope := (_standing_navigation_rect().end.y - bounds.end.y) / 0.25
		_pivot_px.y -= 0.25
		var correction := error / slope if absf(slope) > 0.05 else error
		_pivot_px.y += correction
		_pivot_px_target.y += correction
		_update_avatar_transform(0.0)
		_update_pet_rect()
	autonomy.refresh_foot_projection(_standing_navigation_rect(), _projected_anchors().foot)


## Called before the module publishes its one committed displacement sample.
## A perspective crop and the support-aligned local pivot must be final first.
func _finalize_projection_placement() -> void:
	_committed_projection_delta = null
	if not avatar.has_model(): return
	var foot: Vector3 = _pivot_local.get("foot",Vector3.ZERO)
	var before := _projection_world_before if _projection_world_before.is_finite() else avatar.global_transform * foot
	_update_avatar_transform(0.0)
	_update_pet_rect()
	_follow_standing_projection()
	_committed_projection_delta = avatar.global_transform * foot - before
	_projection_world_before = Vector3.INF


func take_projection_world_delta() -> Variant:
	var value: Variant = _committed_projection_delta
	_committed_projection_delta = null
	return value


func _update_passthrough(force: bool) -> void:
	var region := pet_rect.grow(10)
	# Windows also clips drawing to this region. Occupied furniture moves from
	# its own native window into this viewport, so retain its visible geometry.
	if objects != null and objects.contact_scene_active() and objects._contact_scene.visible:
		region = region.merge(objects.contact_bounds().grow(10))
	if handle_button.visible:
		region = region.merge(Rect2(handle_button.position, handle_button.size).grow(4))
	if subtitle.visible:
		region = region.merge(Rect2(subtitle.position, subtitle.size))
	region = region.intersection(Rect2(Vector2.ZERO, render_size()))
	var poly := PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)])
	if force or poly != _last_passthrough:
		_last_passthrough = poly
		DisplayServer.window_set_mouse_passthrough(poly) # no-op on platforms without support


func _layout_overlays() -> void:
	var handle_at := Vector2(pet_rect.get_center().x - 15, maxf(pet_rect.position.y - 36, 4))
	if avatar.has_model() and avatar.bone_index.has("head"):
		var head := camera.unproject_position(avatar.bone_global_position("head"))
		var head_margin := _model_aabb.size.y * _px_per_m * _pet_scale * 0.13
		handle_at = head - Vector2(15.0, head_margin + 30.0)
	handle_button.position = handle_at.clamp(Vector2(4,4), render_size()-Vector2(34,34))
	handle_dot.position = handle_button.position + Vector2(24, -2)
	loading_label.size = Vector2(PET_ZONE_WIDTH, 24)
	loading_label.position = Vector2(_default_foot_pixel().x - PET_ZONE_WIDTH * 0.5, render_size().y * 0.5)
	subtitle.size = Vector2(PET_ZONE_WIDTH - 20, 0)
	subtitle.position = Vector2(clampf(pet_rect.get_center().x - subtitle.size.x * 0.5,
		10.0, render_size().x - subtitle.size.x - 10.0), minf(pet_rect.end.y + 6, render_size().y - 70))


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
## Speech for a background task never revokes an admitted body action or extends
## the conversation hold. Explicit user dialogue still takes attention normally.
func _note_body_dialogue() -> void:
	if not session.is_background_presentation(): bridge.note_dialogue(_now())

func body_dialogue_busy(include_hold: bool = false) -> bool:
	if body_action_can_continue(): return false
	return (audio.voice_active and not session.is_background_presentation()) or session.is_foreground_busy() or (include_hold and bridge.dialogue_holding(_now()))

func body_action_can_continue() -> bool:
	if objects != null and not objects._interaction.is_empty(): return true
	if living == null: return false
	if living.has_method("has_drop_intent") and living.has_drop_intent():return true
	return living.director.has_explicit_body_intent()


func body_action_owns_heading() -> bool:
	return (scene_navigation != null and scene_navigation.navigation.active) or (objects != null and not objects._interaction.is_empty()) or _sit_active or (living!=null and living.drop_owns_foot())


func _push_autonomy_context() -> void:
	if autonomy == null:
		return
	# Seated on a support: hold the module (it keeps the contact) so it never walks off until stood up.
	var marker_dragging: bool = living != null and living.is_marker_dragging()
	var object_dragging: bool = objects != null and objects.is_dragging()
	var object_hold: bool = objects != null and objects.blocks_roaming()
	var background := session.is_background_presentation()
	var continuing := body_action_can_continue()
	var ctx := bridge.context(panel_open and not continuing, mic.is_recording() and not continuing, audio.voice_active and not background and not continuing, _drag_active or marker_dragging or object_dragging,
		"idle" if background or continuing else session.activity, session.is_foreground_busy() and not continuing, session.is_foreground_playing() and not continuing, _now(),
		(_sit_active and _sit_attached) or _dialogue_gesture_active() or object_hold)
	if continuing and not object_hold and not (_sit_active and _sit_attached): ctx["foreground_busy"] = false
	if objects != null and objects.has_method("admits_contact_during_reply") and objects.admits_contact_during_reply():
		ctx["speaking"] = false
		ctx["foreground_busy"] = false
	if living!=null and living.drop_owns_foot():ctx["foreground_busy"]=true
	autonomy.update_context(bool(ctx["panel_open"]), bool(ctx["listening"]), bool(ctx["speaking"]),
		bool(ctx["dragging"]), bool(ctx["foreground_busy"]))
	# Passthrough hides pointer events outside the pet region, so use the global pointer.
	var mouse_local := Vector2(DisplayServer.mouse_get_position() - get_window().position)
	var handle_rect := Rect2(handle_button.position, handle_button.size) if handle_button.visible else Rect2()
	autonomy.set_pointer_interaction(not continuing and AutonomyBridge.pointer_near(mouse_local, pet_rect, handle_rect, _drag_active, autonomy._pointer_interaction))


## A user turn takes attention. Explicit actions retain their body; spontaneous
## roaming yields and waits through the normal conversation hold.
func _own_body_for_dialogue() -> void:
	_note_body_dialogue()
	if body_action_can_continue():
		_push_autonomy_context()
		return
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
	if scene_navigation != null and scene_navigation.owns_foot():return
	# Surface mode: grounded walk only while the module is in "walk" on an attached support; an
	# "approach" glide toward a support floats/idles instead. Facing follows real walking only and
	# holds its heading on stop; explicit interaction may request a stepped return to front.
	var grounded := AutonomyBridge.grounded(autonomy.surface_mode, autonomy.state, _support)
	motion.set_locomotion_direction(AutonomyBridge.facing_velocity(moving, grounded, _sit_active, velocity))
	var plan := AutonomyBridge.locomotion_plan(moving, _vrma_loaded, _dialogue_gesture_active(), autonomy.speed, grounded, _sit_active)
	match str(plan["action"]):
		"walk":
			var clip := str(plan["clip"])
			if living != null and not living.selected_locomotion_id.is_empty():
				if not living.is_locomotion_available(living.selected_locomotion_id):
					living.cancel("locomotion_revoked")
					return
				clip = living.selected_locomotion_id
			# Start the loop once per travel; never restart it per velocity sample (that is the
			# rapid preemption that produced head jitter).
			if _walk_started != clip or motion.current_gesture() != clip:
				if motion.play_vrma(clip, float(plan["speed"]), true):
					_walk_started = clip
			_floating = false
		"float":
			_floating = not autonomy.surface_mode
		"stop":
			motion.finish_locomotion()
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
	if spatial_camera() != null:
		_float_blend = 0.0
		_floating = false
		return
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
	if _floor_rest_owned:
		_sit_attached=bool(contact.get("attached",false)) and str(contact.get("surface_id",""))==_floor_support_id
		if not _sit_attached:_stand_up("지지면이 바뀌어 일어납니다")
		_refresh_sit_button();_refresh_autonomy_label()
		return
	var standing_id := str(contact.get("surface_id","")) if bool(contact.get("attached",false)) and str(contact.get("pose","")) == "foot" and not _sit_active else ""
	if standing_id != _standing_floor_id:
		_standing_floor_id = standing_id
		_standing_floor_y = (avatar.global_transform * Vector3(_pivot_local.get("foot",Vector3.ZERO))).y if not standing_id.is_empty() and avatar.has_model() else NAN
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
func _seated_navigation_rect() -> Rect2:
	var geometry: Dictionary = avatar.get("seated_geometry") if avatar.get("seated_geometry") is Dictionary else {}
	if geometry.is_empty(): return _navigation_rect()
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	var bounds: AABB = geometry.bounds
	for i in 8:
		var point := camera.unproject_position(avatar.global_transform*bounds.get_endpoint(i))
		low = low.min(point)
		high = high.max(point)
	# Keep the existing full-turn horizontal reserve for upper-body gestures;
	# only the vertical envelope changes to measured seated geometry.
	var pivot: Vector3 = _pivot_local.get("foot",Vector3.ZERO)
	var radius := 0.0
	for i in 8:
		var corner := _model_aabb.get_endpoint(i)-pivot
		radius = maxf(radius,Vector2(corner.x,corner.z).length())
	var foot: Vector2 = _projected_anchors().get("foot",pet_rect.get_center())
	low.x = minf(low.x,foot.x-radius*_px_per_m*_pet_scale)
	high.x = maxf(high.x,foot.x+radius*_px_per_m*_pet_scale)
	return Rect2(low,high-low)

func _ensure_seated_geometry() -> bool:
	if not avatar.has_model() or not motion.vrma_clips.has("sit_idle"): return false
	var geometry: Dictionary = avatar.get("seated_geometry") if avatar.get("seated_geometry") is Dictionary else {}
	var clip = motion.vrma_clips["sit_idle"]
	if geometry.is_empty() or geometry.get("clip_instance",0) != clip.get_instance_id():
		geometry = avatar.call("calibrate_seated_pose",clip.sample(0.0))
		if not geometry.get("anchor") is Vector3 or not geometry.get("bounds") is AABB:
			avatar.seated_geometry.clear()
			return false
		geometry["clip_instance"] = clip.get_instance_id()
	if not geometry.get("anchor") is Vector3 or not geometry.get("bounds") is AABB: return false
	_pivot_local["sit"] = geometry.anchor
	return true

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
	if not _sit_pending or panel_open or not autonomy.enabled or _drag_active or body_dialogue_busy(true) or mic.is_recording() or motion._preview or motion._custom_motion:
		return
	if autonomy.state not in ["walk", "inspect", "rest"]:
		return
	if not AutonomyBridge.can_sit(autonomy.surface_mode, _support, motion.vrma_clips.has(AutonomyBridge.SIT_CLIP), false):
		_sit_pending = false
		_refresh_autonomy_label()
		return
	_sit_pending = false
	if _support.get("kind","")=="taskbar":
		_begin_taskbar_rest()
		return
	if avatar.has_model() and not _ensure_seated_geometry(): return
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
	if _floor_rest_owned and motion.floor_rest.active:
		if _drag_active:
			motion.cancel_floor_rest()
		else:
			_floor_exit_requested=true
			motion.end_floor_rest()
		return
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


func _begin_taskbar_rest() -> void:
	floor_rest_admission={"accepted":false,"reason":"source_unavailable"}
	if not avatar.has_model() or not motion.floor_rest_available():return
	var profile:=motion.prepare_floor_rest()
	if profile.is_empty():return
	# Keep the existing foot support. The whole authored motion may overlap the
	# actual taskbar strip, but must still fit a physical monitor and render crop.
	var bounds:AABB=profile.bounds_local
	var region:=Rect2()
	for i in 8:
		var point:Vector3=avatar.global_transform*bounds.get_endpoint(i)
		if camera.is_position_behind(point):return
		var pixel:=camera.unproject_position(point)
		region=Rect2(pixel,Vector2.ZERO) if i==0 else region.expand(pixel)
	var screen_region:=Rect2(Vector2(get_window().position)+region.position,region.size)
	var fits:=false
	for i in DisplayServer.get_screen_count():
		var screen:=Rect2(Vector2(DisplayServer.screen_get_position(i)),Vector2(DisplayServer.screen_get_size(i)))
		if screen.encloses(screen_region):fits=true;break
	floor_rest_admission={"accepted":false,"reason":"outside_display" if not fits else "outside_viewport","region":region,"global_region":screen_region}
	if not fits or not Rect2(Vector2.ZERO,render_size()).encloses(region):return
	var navigation:=_navigation_rect()
	if not motion.begin_floor_rest():return
	floor_rest_admission["accepted"]=true;floor_rest_admission["reason"]="ready"
	_floor_navigation_rect=navigation
	_floor_rest_owned=true;_floor_exit_requested=false
	_floor_support_id=str(_support.get("surface_id",""))
	_sit_active=true;_sit_attached=true
	_walk_started="";_floating=false
	_push_autonomy_context();_refresh_sit_button();_refresh_autonomy_label()

func _on_floor_rest_finished(outcome:String) -> void:
	if outcome=="entered":
		if _floor_exit_requested:motion.end_floor_rest()
		return
	_floor_rest_owned=false;_floor_exit_requested=false
	_floor_navigation_rect=Rect2();_floor_support_id=""
	_sit_active=false;_sit_attached=false
	if autonomy!=null:
		autonomy.set_contact_pose("foot")
		_on_support_changed(autonomy.get_support_contact())
	_push_autonomy_context();_refresh_sit_button();_refresh_autonomy_label()
	if outcome=="exited" and living!=null:living.queue_idle_recovery("floor_rest_completed")
	if is_finite(_floor_pending_scale) or _floor_pending_view:call_deferred("_apply_floor_pending_edits")

func _apply_floor_pending_edits() -> void:
	var scale:=_floor_pending_scale
	var view:=_floor_pending_view
	_floor_pending_scale=NAN;_floor_pending_view=false
	if view:_apply_view_settings()
	if is_finite(scale):_set_scale_target(scale)

## Change the scale/turn pivot without moving the body: the new pivot starts at its current
## projected pixel. Standing eases back to the canonical foot pixel (bottom of the pet zone).
func _switch_pivot(kind: String) -> void:
	if kind == _pivot_kind:
		return
	if avatar.has_model() and _pivot_local.has(kind):
		var world: Vector3 = avatar.global_transform * _pivot_local[kind]
		_pivot_px = camera.unproject_position(world) if not camera.is_position_behind(world) else _pivot_px
	_pivot_kind = kind
	_pivot_px_target = _pivot_px if kind == "sit" else _default_foot_pixel()


## Public hook for future perception/owned-task sources: "something of interest is at this global
## desktop point". This host never captures or reads the screen; callers supply the point.
## kind: "external" | "owned_task" | ... (free-form, forwarded to the autonomy module).
func observe_interest(id: String, screen_point: Vector2, confidence: float = 0.5, ttl: float = 20.0, kind: String = "external") -> void:
	if living != null:
		living.observe_interest(id, screen_point, confidence, ttl, kind)
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
		if objects != null:
			objects.shutdown()
		world_source.stop() # terminate only our own geometry helper
		_save_window_position()
		Settings.save_now()
		var id := session.cancel_turn()
		if not id.is_empty():
			client.send(session.make_cancel(id))
		_cancel_job()


func _exit_tree() -> void:
	if is_instance_valid(scene_navigation):
		scene_navigation.shutdown()
	if is_instance_valid(objects):
		objects.shutdown()

func request_scene_approach(target_world: Vector3, obstacle_bounds: Array, grid: Dictionary = {}) -> Dictionary:
	if scene_navigation == null:return {"accepted":false,"reason":"scene_unavailable"}
	return scene_navigation.request(target_world,obstacle_bounds,grid)

func cancel_scene_approach(reason: String = "cancelled") -> void:
	if scene_navigation != null:scene_navigation.cancel(reason)

func _on_autonomy_state_changed(s: String) -> void:
	_autonomy_state = s
	if s in ["paused", "settle", "no_surface", "no_space"] and not (scene_navigation != null and scene_navigation.owns_foot()):
		motion.finish_locomotion()
		motion.cancel_heading()
	if s == "no_surface" and _sit_active and not _sit_attached:
		_stand_up("앉을 자리가 맞지 않아 다시 일어섭니다")
	_refresh_autonomy_label()
