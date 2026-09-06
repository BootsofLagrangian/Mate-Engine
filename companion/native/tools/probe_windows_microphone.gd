extends SceneTree
## Opt-in driver diagnostics. Captures only in memory and cancels each recording;
## no utterance, WAV, or audio sample is saved or transmitted. --with-main
## connects to the backend for profile/avatar/catalog setup only.
var mic
var events: Array = []
var started := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if OS.get_name() != "Windows":
		quit(2)
		return
	var app
	var settings = root.get_node("Settings")
	var original: Dictionary = settings.data.duplicate(true)
	var integrated := OS.get_cmdline_user_args().has("--with-main")
	if integrated:
		settings.data["vad_enabled"] = false
		settings.data["panel_open"] = true
		settings.data["autonomy_enabled"] = false
		app = load("res://main.tscn").instantiate()
		root.add_child(app)
		mic = app.mic
		var deadline := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline and (not app.session.hello_received or app.motion.vrma_clips.size() != 8):
			await process_frame
	else:
		root.position = Vector2i(-10000, -10000)
		mic = load("res://scripts/microphone.gd").new()
		root.add_child(mic)
	root.focus_exited.connect(func(): events.append({"ms":Time.get_ticks_msec()-started,"focus":"out"}))
	var utterances := [0]
	mic.utterance_ready.connect(func(_wav, _seconds, _source): utterances[0] += 1)
	mic.recording_changed.connect(func(active, source): events.append({"ms":Time.get_ticks_msec()-started,"recording":active,"source":source}))
	mic.error.connect(func(message): events.append({"error":message}))
	var results: Array = []
	for trial in 2:
		started = Time.get_ticks_msec()
		mic.start_push_to_talk()
		var first_frame_ms := -1
		while Time.get_ticks_msec() - started < 3000:
			await create_timer(0.05).timeout
			if first_frame_ms < 0 and mic.recording_seconds() > 0:
				first_frame_ms = Time.get_ticks_msec() - started
		results.append({"trial":trial,"first_frame_ms":first_frame_ms,"seconds":mic.recording_seconds(),"recording":mic.is_recording(),"capturing":mic.is_capturing(),"capture_frames":mic._capture.get_pushed_frames()})
		mic.cancel_recording()
		await create_timer(0.2).timeout
	var passed: bool = results.all(func(r): return r.seconds > 0.1) and utterances[0] == 0 and not mic.is_capturing()
	print("MICROPHONE_PROBE ",JSON.stringify({"passed":passed,"integrated":integrated,"enable_input":ProjectSettings.get_setting("audio/driver/enable_input"),"driver":AudioServer.get_driver_name(),"input_device":AudioServer.input_device,"mix_rate":AudioServer.get_mix_rate(),"results":results,"events":events,"utterances":utterances[0]}))
	if integrated:
		app.queue_free()
	else:
		mic.queue_free()
	await process_frame
	settings.data = original
	if integrated:
		settings.save_now()
	quit(0 if passed else 1)
