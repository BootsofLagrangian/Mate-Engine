extends SceneTree
## Actual Windows application processing and GPU render; only own viewport captured.
## The idle-action deadline is advanced once per rig; production scheduling and ownership stay active.
var app
var original: Dictionary
var output := ""
var checks: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var next_capture := 0
var phase := "loading"
var observed_actions := {}
var action_progress := {}

func _initialize() -> void:
	call_deferred("run")

func argument(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size(): return args[i + 1]
	return ""

func check(ok: bool, label: String) -> void:
	checks.append({"ok":ok,"label":label})
	print("AUTHORED_WINDOWS ",label," ",ok)

func sample() -> void:
	var ambient = app.motion.authored_ambient
	if not ambient.action_name.is_empty():
		observed_actions[ambient.action_name] = true
		action_progress[ambient.action_name] = maxf(float(action_progress.get(ambient.action_name,0.0)),ambient.action_time)
	if Time.get_ticks_msec() < next_capture: return
	await RenderingServer.frame_post_draw
	var name := "frames/%05d.png" % frames.size()
	var err := root.get_texture().get_image().save_png(output.path_join(name))
	frames.append({"file":name,"ms":Time.get_ticks_msec(),"phase":phase,"character":app.session.character_id,
		"loop":ambient.loop_name,"action":ambient.action_name,"action_time":ambient.action_time,"weight":ambient.weight,"head_weight":ambient.head_weight,
		"state":app.autonomy.state,"behavior":app.living.last_output.get("state",""),"window":str(root.position),"save_error":err})
	next_capture = Time.get_ticks_msec() + 200

func wait_for(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
		await sample()
	return false

func run() -> void:
	if OS.get_name() != "Windows": quit(2); return
	output = argument("--output")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var settings = root.get_node("Settings")
	original = settings.data.duplicate(true)
	settings.data.merge({"vad_enabled":false,"panel_open":false,"autonomy_enabled":true,"surface_roam":true,
		"behavior_enabled":true,"character":"cheval-grand","pet_scale":0.6,"idle_clip":"auto"},true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	app.session.event_accepted.connect(func(e):
		if e.get("type", "") in ["start","action","done","error"]: events.append(e.duplicate(true)))
	var ready := await wait_for(func(): return app.avatar.has_model() and app.session.hello_received and app.motion.vrma_clips.has("uma_home_idle") and app.motion.vrma_clips.has("uma_cheval_idle_action") and app.motion.vrma_clips.has("uma_rice_idle_action") and app.motion.vrma_clips.has("uma_eishin_idle_action"),45)
	check(ready,"live backend and authored catalog ready")
	if not ready:
		finish()
		return
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		phase = character+":load"
		app._switch_character(character)
		check(await wait_for(func(): return app.avatar.has_model() and app.avatar.model_path.get_file() == character+".vrm" and app.session.character_id == character,25),character+" VRM ready")
		app.living.cancel("probe_placement")
		app._set_panel_open(false,false)
		var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		root.position = Vector2i(Vector2(area.position.x+area.size.x*0.6,area.end.y)-Vector2(app._projected_anchors().foot))
		check(await wait_for(func(): return app.autonomy.can_request_move(),18),character+" floor support ready")
		# Hold an ordinary user rest intent to avoid an unrelated local trip during capture.
		app.living.request_intent({"kind":"rest","duration_s":30.0},"user")
		phase = character+":base"
		check(await wait_for(func(): return app.motion.authored_ambient.loop_name == "uma_home_idle" and app.motion.authored_ambient.weight > 0.95,12),character+" auto selects and plays authored home idle")
		await wait_for(func(): return false,3.0)
		var profile: Dictionary = app.session.character_by_id(character)
		var action_name := str(profile.get("idle_actions",[""])[0])
		phase = character+":action"
		observed_actions.erase(action_name)
		action_progress.erase(action_name)
		var action_duration: float = app.motion.vrma_clips[action_name].duration
		app.living._idle_action_next = app.living._clock
		check(await wait_for(func(): return observed_actions.has(action_name),12),character+" scheduler starts profile action")
		check(await wait_for(func(): return app.motion.authored_ambient.action_name.is_empty() and float(action_progress.get(action_name,0.0)) >= action_duration-0.2 and app.motion.authored_ambient.loop_name == "uma_home_idle" and app.motion.authored_ambient.weight > 0.95,10),character+" full-duration finite action returns to running base")
		await wait_for(func(): return false,1.5)
		check(not app.motion.is_gesture_active(),character+" idle leaves dialogue gesture ownership free")
		phase = character+":procedural"
		settings.data["idle_clip"] = ""
		app._apply_ambient_idle()
		app.living._idle_action_next = app.living._clock
		await wait_for(func(): return false,1.0)
		check(app.motion.authored_ambient.loop_name.is_empty() and app.motion.authored_ambient.action_name.is_empty(),character+" basic breathing disables authored base and actions")
		settings.data["idle_clip"] = "auto"
		app._apply_ambient_idle()
	check(events.is_empty(),"idle and local actions did not start LLM turns")
	check(frames.all(func(f): return f.save_error == OK),"all own-viewport captures saved")
	finish()

func finish() -> void:
	var settings = root.get_node("Settings")
	app.client.disconnect_ws()
	app.world_source.stop()
	app.autonomy.set_enabled(false)
	settings.data = original
	settings.save_now()
	var report := {"checks":checks,"frames":frames,"events":events,"actions":observed_actions,
		"action_progress_seconds":action_progress,"renderer":RenderingServer.get_video_adapter_name(),"failures":checks.filter(func(c):return not c.ok).size(),
		"scope":"Normal production scene processing, actual Windows/GPU; one action deadline advanced per rig; user rest intent prevents roaming; no model turns or unrelated desktop captures."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("AUTHORED_WINDOWS_FAILURES=",report.failures)
	quit(0 if report.failures == 0 else 1)
