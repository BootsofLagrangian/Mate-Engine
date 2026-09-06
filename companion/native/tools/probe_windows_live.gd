extends SceneTree
## Opt-in real Windows/GPU integration probe. Opens the microphone briefly without
## sending/saving that recording, then uses an existing Korean fixture for audio input.
## Generated character speech is played through the actual Windows audio driver.
var app
var output_dir: String
var report := {"platform": OS.get_name(), "checks": [], "events": [], "turns": []}
var started := 0
var settings_node
var original_settings: Dictionary
var done: Dictionary = {}
var spoken: Dictionary = {}
var drained: Dictionary = {}
var max_envelope := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	print("CHECK ", label, " ", ok)

func wait_for(test: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < limit:
		if test.call():
			return true
		max_envelope = maxf(max_envelope, app.audio.envelope)
		await process_frame
	return false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join(name + ".png")) == OK, "capture " + name)

func received(event: Dictionary) -> void:
	var e := event.duplicate(true)
	e["received_ms"] = Time.get_ticks_msec() - started
	if e.has("pcm"):
		e["pcm_bytes"] = Marshalls.base64_to_raw(str(e["pcm"])).size()
		e.erase("pcm")
	if e.get("type") == "done":
		done[str(e.get("turn_id"))] = e
	report.events.append(e)

func companion_path(relative: String) -> String:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--test-root" and index + 1 < args.size():
			return args[index + 1].path_join(relative)
	return ProjectSettings.globalize_path("res://../" + relative)

func run() -> void:
	if OS.get_name() != "Windows":
		push_error("This probe requires actual Windows. Use the headless selftest separately.")
		quit(2)
		return
	started = Time.get_ticks_msec()
	output_dir = companion_path("logs/windows-live")
	if OS.get_cmdline_user_args().has("--microphone-only"):
		output_dir = companion_path("logs/windows-live-microphone")
	DirAccess.make_dir_recursive_absolute(output_dir)
	settings_node = root.get_node("Settings")
	original_settings = settings_node.data.duplicate(true)
	settings_node.data["vad_enabled"] = false
	settings_node.data["panel_open"] = true
	settings_node.data["autonomy_enabled"] = false
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	app.client.event_received.connect(received)
	app.audio.playback_changed.connect(func(id: String, active: bool):
		report.events.append({"type": "native_playback", "turn_id": id, "playing": active, "received_ms": Time.get_ticks_msec() - started})
		if active:
			spoken[id] = true
		else:
			drained[id] = true)
	check(await wait_for(func(): return app.session.hello_received and app.session.characters.size() == 3, 25), "native WS and three profiles")
	report["renderer"] = RenderingServer.get_video_adapter_name()
	report["input_devices"] = AudioServer.get_input_device_list()
	report["output_device"] = AudioServer.output_device
	check(root.transparent and root.always_on_top, "transparent always-on-top")
	check(await wait_for(func(): return app.motion.vrma_clips.has("walk") and app.motion.vrma_clips.has("sit_idle") and app._vrma_pending == 0, 30), "downloaded verified VRMA catalog ready")
	# Driver capture lifecycle only: no claim of recognizing physical speech.
	var mic_started := Time.get_ticks_msec()
	var mic_events: Array = []
	var on_recording := func(active: bool, source: String): mic_events.append({"ms": Time.get_ticks_msec() - mic_started, "recording": active, "source": source})
	var on_focus_out := func(): mic_events.append({"ms": Time.get_ticks_msec() - mic_started, "focus": "out"})
	app.mic.recording_changed.connect(on_recording)
	root.focus_exited.connect(on_focus_out)
	app.mic.start_push_to_talk()
	check(app.mic.is_recording() and app.mic.is_capturing(), "Windows PTT opens input")
	# Avatar import can stall the main thread past a fixed timer; wait for
	# microphone processing to catch up, while retaining a bounded frame check.
	var received_frames := await wait_for(func(): return app.mic.recording_seconds() > 0.1, 5.0)
	report["microphone_captured_seconds"] = app.mic.recording_seconds()
	report["microphone_wait_ms"] = Time.get_ticks_msec() - mic_started
	report["microphone_state"] = {"recording": app.mic.is_recording(), "capturing": app.mic.is_capturing(), "driver": AudioServer.get_driver_name(), "enable_input": ProjectSettings.get_setting("audio/driver/enable_input")}
	check(received_frames, "Windows microphone driver supplies frames")
	app.mic.cancel_recording()
	app.mic.recording_changed.disconnect(on_recording)
	root.focus_exited.disconnect(on_focus_out)
	report["microphone_events"] = mic_events
	check(not app.mic.is_recording() and not app.mic.is_capturing(), "PTT cancel closes input")
	if OS.get_cmdline_user_args().has("--microphone-only"):
		finish()
		return
	for id in ["cheval-grand", "rice-shower", "eishin-flash"]:
		if app.session.character_id != id:
			app._switch_character(id)
		else:
			app._load_avatar_for(id, false)
		await create_timer(0.2).timeout
		check(await wait_for(func(): return app.avatar.has_model() and not app.loading_label.visible, 25), "native VRM " + id)
		await create_timer(0.6).timeout
		await shot(id + "-idle")
		app._send_chat("오늘 시험에 합격했어. 한마디만 축하해 줄래?")
		var turn: String = app.session.turn_id
		check(await wait_for(func(): return spoken.has(turn), 30), "actual PCM playback " + id)
		await create_timer(0.3).timeout
		await shot(id + "-speaking")
		check(await wait_for(func(): return done.has(turn) and not app.audio.is_voice_active() and app.audio.queue.pending_frames() == 0, 60), "done and actual audio drained " + id)
		check(bool(done.get(turn, {}).get("ok", false)), "valid response " + id)
		report.turns.append({"character": id, "turn_id": turn, "text": done.get(turn, {}).get("text", ""), "stats": app.audio.stats()})
	# Korean speech fixture goes through native audio message -> raw-audio Thinker.
	var fixture := companion_path("logs/omni-inputs/p01.wav")
	if FileAccess.file_exists(fixture):
		app._on_utterance(FileAccess.get_file_as_bytes(fixture), 5.168, "fixture")
		var turn: String = app.session.turn_id
		check(await wait_for(func(): return spoken.has(turn), 35), "raw Korean fixture produces native speech")
		check(await wait_for(func(): return done.has(turn) and not app.audio.is_voice_active(), 60), "raw Korean fixture turn drains")
		report["audio_input_reply"] = done.get(turn, {}).get("text", "")
	else:
		check(false, "Korean fixture installed")
	# An interrupt must remove both the pending PCM and the Windows generator buffer.
	app._send_chat("오늘 함께 할 수 있는 일을 일본어로 조금 길게 이야기해 줘.")
	var interrupted: String = app.session.turn_id
	check(await wait_for(func(): return spoken.has(interrupted), 35), "interrupt test began actual playback")
	app._cancel_current()
	await process_frame
	check(not app.audio.is_voice_active() and app.audio.queue.pending_frames() == 0 and app.audio.buffered_frames() <= 64, "cancel clears native audio")
	check(drained.has(interrupted), "cancel reports playback false for old turn")
	report["max_lip_envelope"] = max_envelope
	check(max_envelope > 0.01, "live audio drives lip envelope")
	finish()

func finish() -> void:
	app.client.disconnect_ws()
	app.mic.cancel_recording()
	settings_node.data = original_settings
	settings_node.save_now()
	var failures := 0
	for entry in report.checks:
		if not entry.ok:
			failures += 1
	report["failures"] = failures
	var f := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("WINDOWS_LIVE failures=", failures)
	quit(0 if failures == 0 else 1)
