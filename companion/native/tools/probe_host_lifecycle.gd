extends SceneTree
## Actual main.gd handlers with isolated node doubles; no network, world helper or desktop GUI.
## Run with a temporary XDG_DATA_HOME so settings writes stay isolated from the user's settings.

class Avatar:
	extends VrmAvatar
	var present := false
	func has_model() -> bool:
		return present

class Motion:
	extends MotionPlayer
	var starts := 0
	var stops := 0
	var contact := "foot"
	var gestures: Array = []
	func _ready() -> void:
		set_process(false)
	func start_contact_pose(pose: String, _target: Vector3 = Vector3.INF) -> bool:
		starts += 1
		contact = pose
		return true
	func stop_contact_pose() -> void:
		contact = "foot"
	func current_contact_pose() -> String:
		return contact
	func stop_gesture() -> void:
		stops += 1
	func play_gesture(gesture: String, emotion: String = "", intensity: float = 1.0,
		speed: float = 1.0, repeat: int = 1, preview: bool = false) -> bool:
		gestures.append([gesture, emotion, intensity, speed, repeat, preview])
		return true
	func set_emotion(_emotion: String, _strength: float = 0.5, _hold: float = 4.0) -> void:
		pass

class HostPanel:
	extends ControlPanel
	var status := ""
	var autonomy_label := ""
	func _ready() -> void:
		pass
	func set_status_message(text: String) -> void:
		status = text
	func set_autonomy_state(text: String) -> void:
		autonomy_label = text
	func set_sit_state(_can_sit: bool, _sitting: bool) -> void:
		pass
	func focus_input() -> void:
		pass
	func set_backend(_url: String, _source: String) -> void:
		pass
	func update_live_reply(_text: String, _final: bool) -> void:
		pass

class Client:
	extends BackendClient
	var outbound: Array = []
	var transitions: Array = []
	func _ready() -> void:
		set_process(false)
	func send(message: Dictionary) -> bool:
		outbound.append(message.duplicate(true))
		return true
	func disconnect_ws() -> void:
		transitions.append("disconnect")
		# Deliberately no disconnected signal: immediate replacement bypasses it.
	func connect_ws() -> void:
		transitions.append("connect")
		state = "open"
	func fetch_characters() -> void:
		pass
	func fetch_motions() -> void:
		pass
	func fetch_motion_assets() -> void:
		pass

var host_script: GDScript
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func make_host() -> Node:
	var host = host_script.new()
	root.add_child(host)
	host.avatar = Avatar.new()
	host.add_child(host.avatar)
	host.motion = Motion.new()
	host.add_child(host.motion)
	host.panel = HostPanel.new()
	host.add_child(host.panel)
	host.audio = AudioOutput.new()
	host.add_child(host.audio)
	host.audio.set_process(false)
	host.mic = Microphone.new()
	host.add_child(host.mic)
	host.mic.set_process(false)
	host.client = Client.new()
	host.add_child(host.client)
	host.autonomy = DesktopAutonomy.new()
	host.add_child(host.autonomy)
	var areas: Array[Rect2] = [Rect2(0, 0, 1920, 1040)]
	host.autonomy.configure_simulation(areas, Vector2.ZERO, Rect2(400, 120, 220, 560))
	host.handle_button = Button.new()
	host.add_child(host.handle_button)
	host.handle_dot = ColorRect.new()
	host.add_child(host.handle_dot)
	host.subtitle = Label.new()
	host.add_child(host.subtitle)
	host.pet_rect = Rect2(400, 120, 220, 560)
	host.autonomy.support_changed.connect(host._on_support_changed)
	return host

func _run() -> void:
	# Load main only after the SceneTree has registered the Settings autoload.
	host_script = GDScript.new()
	host_script.source_code = 'extends "res://scripts/main.gd"\nvar position_saves := 0\nfunc _ready() -> void:\n\tset_process(false)\nfunc _update_passthrough(_force: bool) -> void:\n\tpass\nfunc _save_window_position() -> void:\n\tposition_saves += 1\n'
	if host_script.reload() != OK:
		push_error("Host probe could not compile main.gd")
		quit(1)
		return
	_test_fit()
	_test_backend_switch()
	_test_focus_loss()
	_test_sit()
	_test_done_fallback()
	print("Host lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures or checks < 25 else 0)

func _test_fit() -> void:
	var host := make_host()
	host.avatar.present = true
	host._pivot_px = Vector2.ZERO
	host._pivot_px_target = Vector2.ZERO
	var min_pivot := INF
	var max_pivot := -INF
	for i in 120:
		host._pivot_px = host._pivot_px.lerp(host._pivot_px_target, 0.1)
		host._unclipped_pet_rect = Rect2(100, -100 + host._pivot_px.y, 200, 690)
		host._keep_pet_in_window()
		min_pivot = minf(min_pivot, host._pivot_px.y)
		max_pivot = maxf(max_pivot, host._pivot_px.y)
	check(max_pivot <= 100.01 and min_pivot >= 0.0, "fit converges without overshooting into opposite edge")
	check(absf(host._pivot_px.y - 100.0) < 0.01, "fit reaches only required 100px correction")
	check(absf(host._pivot_px_target.y - 100.0) < 0.01, "fit target does not accumulate overflow")
	host.free()

func _test_backend_switch() -> void:
	var host := make_host()
	host.client.state = "open"
	host.session.character_id = "test-character"
	var turn: String = host.session.new_turn()
	host.session.start_job("owned-old-job", "probe")
	host._selection_announced = "test-character"
	host.audio.begin_turn(turn)
	var pcm := PackedByteArray()
	pcm.resize(6400)
	check(host.audio.push_raw(turn, 0, pcm), "old backend audio queued")
	host.audio._process(0.016)
	host._set_backend("http://127.0.0.1:1")
	check(host.audio.turn_id.is_empty() and host.audio.queue.pending_frames() == 0 and host.audio.buffered_frames() == 0, "backend switch immediately flushes old audio")
	check(host.session.turn_id.is_empty() and not host.session.turn_generating, "backend switch clears old foreground turn")
	check(host.session.job.status == "cancelled", "old owned job reset on backend switch")
	check(host._selection_announced.is_empty(), "backend switch invalidates selection announcement cache")
	check(host.client.transitions == ["disconnect", "connect"], "backend replaced without needing disconnected callback")
	host._announce_character("test-character")
	check(host.client.outbound.back() == {"type": "select_character", "character": "test-character"}, "saved character re-announced on new connection")
	check(not host.session.handle({"type": "audio", "turn_id": turn, "pcm": "AAAA"}), "late cancelled backend audio rejected")
	host.free()

func _test_focus_loss() -> void:
	var host := make_host()
	var utterances: Array = []
	host.mic.utterance_ready.connect(func(_wav: PackedByteArray, _seconds: float, _source: String): utterances.append(true))
	host.mic.start_push_to_talk()
	host.mic._buffer.resize(24000)
	host._ptt_key_down = true
	host._drag_active = true
	host._drag_moved = true
	host._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not host._ptt_key_down and not host.mic.is_recording(), "focus loss clears F9 latch and PTT recording")
	check(not host.mic.is_capturing(), "focus loss closes manual capture when VAD off")
	check(utterances.is_empty(), "focus loss discards recording without submission")
	check(not host._drag_active and not host._drag_moved and host.position_saves == 1, "focus loss releases drag and saves moved position")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F9
	event.pressed = true
	host._input(event)
	check(host._ptt_key_down and host.mic.is_recording(), "next F9 press works after lost key-up")
	host._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	host.free()

func world() -> Dictionary:
	return {"monitors": [{"id": "test", "x": 0, "y": 0, "width": 1920, "height": 1040}],
		"windows": [{"id": "shelf", "x": 300, "y": 700, "width": 1000, "height": 300, "z": 0}]}

func _test_sit() -> void:
	var host := make_host()
	host.motion.vrma_clips["sit_idle"] = {}
	host.autonomy.set_surface_mode(true)
	host.autonomy.set_contact_anchors({"foot": Vector2(510, 680), "sit": Vector2(510, 500)})
	host.autonomy.update_context(false, false, false, false, false)
	for i in 1000:
		host.autonomy.set_world_snapshot(world())
		host.autonomy.advance(1.0 / 60.0)
		if host._support.get("attached", false):
			break
	check(host._support.get("attached", false), "sit fixture starts attached")
	host._set_panel_open(true, false)
	var before: Vector2 = host.autonomy.position
	host._request_sit()
	check(not host.panel_open and host._sit_pending, "sit button explicitly collapses panel and queues intent")
	check(host.motion.starts == 0 and not host._sit_active and host.autonomy.position == before, "pending sit does not change body or window while settling")
	host.autonomy.set_pointer_interaction(true)
	host.autonomy.advance(3.0)
	host._advance_pending_sit()
	check(host.motion.starts == 0, "pointer pause keeps pending sit standing")
	host.autonomy.set_pointer_interaction(false)
	for i in 1800:
		host.autonomy.set_world_snapshot(world())
		host.autonomy.advance(1.0 / 60.0)
		host._advance_pending_sit()
		if host._sit_attached:
			break
	check(host.motion.starts == 1 and host._sit_active and host._sit_attached, "safe pending sit starts once and reaches seated support")
	check(absf(host.autonomy.get_support_contact().screen_point.y - 700.0) < 0.01, "seated host contact reaches original shelf")
	host._stand_up("")
	for i in 1000:
		host.autonomy.update_context(false, false, false, false, false)
		host.autonomy.set_world_snapshot(world())
		host.autonomy.advance(1.0 / 60.0)
		if host._support.get("attached", false):
			break
	host._set_panel_open(true, false)
	host._request_sit()
	host._set_panel_open(true, false)
	check(not host._sit_pending and not host._sit_active, "reopening panel cancels pending sit without animation")
	host.free()

func _test_done_fallback() -> void:
	var host := make_host()
	host.panel_open = true # subtitles stay hidden
	host._on_event({"type": "done", "turn_id": "legacy", "gesture": "nod", "emotion": "happy",
		"intensity": 0.65, "speed": 0.82, "repeat": 2})
	check(host.motion.gestures.size() == 1 and host.motion.gestures[0].slice(0, 5) == ["nod", "happy", 0.65, 0.82, 2], "legacy done forwards personality-scaled metadata unchanged")
	host.motion.gestures.clear()
	host._on_event({"type": "action", "turn_id": "acted", "gesture": "wave", "intensity": 0.7, "speed": 0.9})
	host._on_event({"type": "done", "turn_id": "acted", "gesture": "wave", "intensity": 0.7, "speed": 0.9})
	check(host.motion.gestures.size() == 1, "done never replays an already completed action gesture")
	host.free()
