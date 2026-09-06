extends SceneTree
## Opt-in actual Windows/GPU: native chat -> streamed voice -> validated intent -> OS movement.
## No microphone capture, desktop screenshots, or external application input.
var app
var settings_node
var original: Dictionary
var output := ""
var records: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var done: Dictionary = {}
var action: Dictionary = {}
var turn := ""
var clock_start := 0
var position_at_request := Vector2i.ZERO
var speech_drift := 0.0
var first_pcm_ms := -1
var report: Dictionary = {}
var capture_fps := 0.0
var next_capture_ms := 0
var captures: Array[Dictionary] = []
var contexts: Array[Dictionary] = []
var navigation_events: Array[Dictionary] = []
var next_context_ms := 0
var target_id := "support:left"
var travel_sign := -1
var corridor_choice: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func argument(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size(): return args[i + 1]
	return ""

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	print("INTENT_CHECK ",label," ",ok)

func navigation_context() -> Dictionary:
	return {"ms":Time.get_ticks_msec()-clock_start,"state":app.autonomy.state,"clock":app.autonomy._time,
		"window":str(root.position),"target":str(app.autonomy.target),"pointer":str(DisplayServer.mouse_get_position()),
		"pointer_interaction":app.autonomy._pointer_interaction,"blocked":app.autonomy._blocked,
		"panel_open":app.panel_open,"dragging":app._drag_active,"speaking":app.audio.voice_active,
		"foreground_busy":app.session.is_foreground_busy(),"support":app.autonomy.get_support_contact(),
		"settle_until":app.autonomy._settle_until,"bounds":str(app.pet_rect),
		"world_timestamp":app.world_source._last_timestamp,"world_available":app.world_source.available,
		"world_error":app.world_source.last_error}

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if not turn.is_empty() and Time.get_ticks_msec()>=next_context_ms:
			next_context_ms=Time.get_ticks_msec()+250
			contexts.append(navigation_context())
		if predicate.call(): return true
		if not turn.is_empty() and app.audio.voice_active:
			speech_drift = maxf(speech_drift, Vector2(root.position - position_at_request).length())
		await process_frame
		if not turn.is_empty() and capture_fps > 0 and Time.get_ticks_msec() >= next_capture_ms:
			await RenderingServer.frame_post_draw
			var ms := Time.get_ticks_msec() - clock_start
			var filename := "frames/%010d.png" % ms
			var result := root.get_texture().get_image().save_png(output.path_join(filename))
			captures.append({"file":filename,"ms":ms,"state":app.autonomy.state,"yaw":app.avatar.rotation.y,"window":str(root.position),"save_error":result})
			next_capture_ms = Time.get_ticks_msec() + int(1000.0/capture_fps)
	return false

func event(value: Dictionary) -> void:
	var item := value.duplicate(true)
	item.erase("pcm")
	item["ms"] = Time.get_ticks_msec() - clock_start
	records.append(item)
	if str(item.get("turn_id", "")) != turn: return
	if item.get("type") == "action": action = item
	if item.get("type") == "done": done = item
	if item.get("type") == "audio" and first_pcm_ms < 0: first_pcm_ms = int(item.ms)

func run() -> void:
	if OS.get_name() != "Windows": quit(2); return
	output = argument("--test-root").path_join("logs/windows-native-intent")
	if not argument("--output").is_empty(): output = argument("--output")
	capture_fps = clampf(float(argument("--capture-fps")), 0.0, 12.0)
	DirAccess.make_dir_recursive_absolute(output)
	if capture_fps > 0: DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	settings_node = root.get_node("Settings")
	original = settings_node.data.duplicate(true)
	settings_node.data["vad_enabled"] = false
	settings_node.data["panel_open"] = true
	settings_node.data["autonomy_enabled"] = true
	settings_node.data["surface_roam"] = true
	settings_node.data["behavior_enabled"] = true
	settings_node.data["character"] = "cheval-grand"
	settings_node.data["pet_scale"] = 0.6
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	check(await wait_for(func(): return app.avatar.has_model() and app.motion.vrma_clips.has("walk") and app.session.hello_received and app._vrma_pending == 0, 40), "live native avatar and backend ready")
	app.living.cancel("probe_placement")
	app._set_panel_open(false, false)
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var pointer_at_placement := DisplayServer.mouse_get_position()
	var pointer_left := pointer_at_placement.x < area.position.x + area.size.x * 0.5
	travel_sign = 1 if pointer_left else -1
	target_id = "support:right" if pointer_left else "support:left"
	var start_fraction := 0.45 if pointer_left else 0.55
	corridor_choice = {"pointer_at_placement":str(pointer_at_placement),"workarea":str(area),"start_foot_fraction":start_fraction,"expected_target":target_id,"travel_sign":travel_sign,"rationale":"Walk away from the cursor's monitor half; preserve normal hover cancellation if the cursor subsequently enters the path."}
	root.position = Vector2i(Vector2(area.position.x + area.size.x * start_fraction, area.end.y) - Vector2(app._projected_anchors().foot))
	check(await wait_for(func(): return app.autonomy.can_request_move() and str(app.autonomy.get_support_contact().get("surface_id", "")).begins_with("floor:"), 18), "actual monitor floor ready for movement")
	app.living._refresh_targets()
	var targets: Array = app.living.director.interest_catalogue()
	check(targets.any(func(p): return p.id == target_id), "named chosen target available")
	app.session.event_accepted.connect(event)
	clock_start = Time.get_ticks_msec()
	app.autonomy.navigation_finished.connect(func(id, outcome): navigation_events.append({"id":id,"outcome":outcome,"context":navigation_context()}))
	app.autonomy.state_changed.connect(func(_state):
		if not turn.is_empty(): contexts.append(navigation_context()))
	var direction_word := "오른쪽" if travel_sign > 0 else "왼쪽"
	app._send_chat("지금 서 있는 곳의 %s 자리로 가 봐. 먼저 짧게 대답한 다음 이동해 줘." % direction_word)
	turn = app.session.turn_id
	position_at_request = root.position
	check(await wait_for(func(): return not done.is_empty() and not app.audio.is_voice_active(), 45), "GPU reply completed and actual voice drained")
	check(bool(done.get("ok", false)), "GPU returned valid Japanese dialogue")
	check(first_pcm_ms >= 0 and app.audio.queue.dropped_frames == 0, "streamed dedicated voice received without dropped frames")
	var intent: Dictionary = done.get("intent", {})
	check(intent.get("kind") == "move_to" and intent.get("target_id") == target_id, "real model requests the listed chosen target")
	check(action.get("intent", {}) == intent, "action and done carry identical intent")
	check(speech_drift == 0.0, "pet stays in place during actual spoken acknowledgement")
	await wait_for(func(): return app.living.outcomes.any(func(row): return row.id == turn + ":intent"), 45)
	check(app.living.outcomes.any(func(row): return row.id == turn + ":intent" and row.outcome == "arrived"), "native controller reports actual arrival")
	check((root.position.x-position_at_request.x)*travel_sign > 120, "actual Windows window moved in requested direction by over 120 pixels")
	var completions: Array = app.living.outcomes.filter(func(row): return row.id == turn + ":intent" and row.outcome == "arrived")
	check(completions.size() == 1, "action/done duplicates produce one arrival")
	app.living.cancel("probe_finished")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("arrival.png"))
	report = {"corridor_choice":corridor_choice,"character_identity":{"session":app.session.character_id,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path)},"contexts":contexts,"navigation_events":navigation_events,"checks":checks,"events":records,"done":done,"first_pcm_ms":first_pcm_ms,"speech_drift_px":speech_drift,
		"window_start":str(position_at_request),"window_end":str(root.position),"outcomes":app.living.outcomes,
		"renderer":RenderingServer.get_video_adapter_name(),"failures":checks.filter(func(row):return not row.ok).size(),
		"captures":captures,"capture_scope":"own viewport, normal production processing, capture overhead included in elapsed timing"}
	app.client.disconnect_ws()
	app.world_source.stop()
	app.autonomy.set_enabled(false)
	settings_node.data = original
	settings_node.save_now()
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("WINDOWS_NATIVE_INTENT failures=",report.failures)
	quit(0 if report.failures == 0 else 1)
