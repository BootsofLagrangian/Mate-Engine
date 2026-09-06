extends SceneTree
## Production native movement chain with user intentions; own viewport only.
## No manually stepped motion, injected bone poses, LLM turns or unrelated desktop input.
var app
var original: Dictionary
var output := ""
var phase := "loading"
var checks: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var previous_state := ""
var next_capture := 0
var started := 0
var max_stop_drift := 0.0
var csv: FileAccess
var pair_samples: Array[Dictionary] = []
var pairs: Array[Dictionary] = []
var pair_preview_owned := true
var pair_incoming_start := -1.0
var pair_promoted := false
var pair_max_progress := 0.0
var character_identity := {}

func _initialize() -> void: call_deferred("run")
func argument(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i+1 < args.size(): return args[i+1]
	return ""
func check(ok: bool,label: String) -> void:
	checks.append({"ok":ok,"label":label})
	print("CHAIN_WINDOWS ",label," ",ok)
func sample() -> void:
	# Sample the completed production frame, including post-window-move IK.
	await RenderingServer.frame_post_draw
	var ms := Time.get_ticks_msec()-started
	var state: String = app.autonomy.state
	if phase.begins_with("pair:"):
		var overlap: Dictionary = app.motion.overlap_diagnostics
		if app.motion.is_gesture_active():
			pair_preview_owned = pair_preview_owned and app.motion._preview
		if not overlap.get("incoming", {}).is_empty() and not overlap.get("outgoing", {}).is_empty():
			pair_incoming_start = float(overlap.incoming.start_time)
			pair_samples.append({"ms":ms,"phase":phase,"outgoing":overlap.outgoing.duplicate(true),
				"incoming":overlap.incoming.duplicate(true),"preview":app.motion._preview})
		elif pair_incoming_start >= 0.0 and not overlap.get("outgoing",{}).is_empty():
			if is_equal_approx(float(overlap.outgoing.start_time),pair_incoming_start) and app.motion.is_gesture_active():
				pair_promoted = true
				pair_max_progress = maxf(pair_max_progress,float(overlap.outgoing.time))
	if state != previous_state:
		transitions.append({"ms":ms,"state":state,"phase":phase,"window":str(root.position),
			"pointer":str(DisplayServer.mouse_get_position()),"pointer_interaction":app.autonomy._pointer_interaction,
			"blocked":app.autonomy._blocked,"panel_open":app.panel_open,"gesture":app.motion.current_gesture(),
			"owned_walk":app._walk_started,"voice":app.audio.voice_active,"listening":app.mic.is_recording(),
			"foreground":app.session.is_foreground_busy(),"preview":app.motion._preview})
		previous_state = state
	if app.avatar.has_model():
		var hips: Vector3 = app.avatar.bone_global_position("hips")
		var left: Vector3 = app.avatar.bone_global_position("leftFoot")
		var right: Vector3 = app.avatar.bone_global_position("rightFoot")
		csv.store_csv_line(PackedStringArray([str(ms),phase,state,str(root.position.x),str(root.position.y),str(app.autonomy.velocity.x),str(app.avatar.rotation.y),str(app.motion.gait.phase),str(app.motion.gait._weight),str(hips.x),str(hips.y),str(hips.z),str(left.x),str(left.y),str(left.z),str(right.x),str(right.y),str(right.z)]))
	if Time.get_ticks_msec() < next_capture: return
	var name := "frames/%05d.png" % frames.size()
	var err := root.get_texture().get_image().save_png(output.path_join(name))
	frames.append({"file":name,"ms":ms,"phase":phase,"state":state,"window":str(root.position),
		"yaw":app.avatar.rotation.y,"gait_phase":app.motion.gait.phase,"gait_weight":app.motion.gait._weight,"save_error":err})
	next_capture = Time.get_ticks_msec()+125
func wait_for(predicate: Callable,seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await process_frame
		await sample()
	return false
func moving_owned_walk() -> bool:
	# State "walk" is emitted before the first locomotion sample starts its
	# clip. Dispatch only after production has acquired that loop and moved
	# past the existing 20 px/s interruption threshold.
	return app.autonomy.state == "walk" and absf(app.autonomy.velocity.x) > 20.0 \
		and not app._walk_started.is_empty() and app.motion.current_gesture() == app._walk_started
func arrived(id: String) -> bool:
	return app.living.outcomes.any(func(row): return row.id == id and row.outcome == "arrived")
func request(id: String,target: String) -> bool:
	return bool(app.living.request_intent({"kind":"move_to","target_id":target},"user",id).get("accepted",false))
func run() -> void:
	if OS.get_name() != "Windows": quit(2); return
	output = argument("--output")
	if output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	csv = FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	csv.store_line("ms,phase,state,window_x,window_y,velocity_x,yaw,gait_phase,gait_weight,hips_x,hips_y,hips_z,left_x,left_y,left_z,right_x,right_y,right_z")
	var settings = root.get_node("Settings")
	original = settings.data.duplicate(true)
	settings.data.merge({"vad_enabled":false,"panel_open":false,"autonomy_enabled":true,"surface_roam":true,"behavior_enabled":true,"character":"cheval-grand","pet_scale":0.6,"idle_clip":"auto"},true)
	for option in [["--view-yaw","view_yaw_deg"],["--view-pitch","view_pitch_deg"]]:
		if not argument(option[0]).is_empty(): settings.data[option[1]] = float(argument(option[0]))
	started = Time.get_ticks_msec()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	var ready := await wait_for(func(): return app.avatar.has_model() and app.session.hello_received and app.motion.vrma_clips.has("walk") and app.motion.vrma_clips.has("uma_home_idle") and app._vrma_pending == 0,45)
	check(ready,"native backend, avatar and required motion assets ready")
	if not ready: finish(); return
	var requested := argument("--character")
	if requested.is_empty(): requested = "cheval-grand"
	app._switch_character(requested)
	var rig_ready := await wait_for(func(): return app.session.character_id == requested and app.avatar.has_model() and app.avatar.model_path.get_file() == requested + ".vrm" and not app.loading_label.visible,25)
	character_identity = {"requested":requested,"actual":app.session.character_id,"model_path":app.avatar.model_path,
		"model_sha256":FileAccess.get_sha256(app.avatar.model_path) if app.avatar.has_model() else ""}
	check(rig_ready,"requested character and actual loaded VRM agree")
	if not rig_ready: finish(); return
	app.living.cancel("probe_placement")
	app._set_panel_open(false,false)
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Choose a test corridor away from the current pointer; retain normal pointer
	# priority throughout and record any later real interaction in the trace.
	var column := 0.25 if DisplayServer.mouse_get_position().x > area.get_center().x else 0.75
	root.position = Vector2i(Vector2(area.position.x+area.size.x*column,area.end.y)-Vector2(app._projected_anchors().foot))
	check(await wait_for(func(): return app.autonomy.can_request_move(),18),"actual monitor floor support ready")
	var foot: Vector2 = Vector2(root.position)+Vector2(app._projected_anchors().foot)
	app.living.observe_interest("chain_left",foot-Vector2(240,0),1,120,"point","왼쪽 연속 동작 검사 지점")
	app.living.observe_interest("chain_right",foot+Vector2(240,0),1,120,"point","오른쪽 연속 동작 검사 지점")
	phase = "idle_to_right"
	check(request("chain:first","chain_right"),"first rightward user move accepted")
	check(await wait_for(func(): return app.autonomy.state == "walk",12),"idle to turn to actual rightward walk")
	await wait_for(func(): return false,2.0)
	check(app.autonomy.state == "walk" and absf(app.autonomy.velocity.x) > 20.0,"replacement is issued during moving gait")
	phase = "moving_reversal"
	var replacement_ms := Time.get_ticks_msec()
	check(request("chain:reverse","chain_left"),"walking direction replacement accepted")
	check(await wait_for(func(): return app.autonomy.state == "anticipate",5),"replacement transitions to turning")
	check(Time.get_ticks_msec()-replacement_ms < 1200,"replacement has no redundant multi-second settle pause")
	check(await wait_for(func(): return arrived("chain:reverse"),22),"reversed turn and walk reach left point")
	var replaced: Array = app.living.outcomes.filter(func(row): return row.id == "chain:first")
	check(replaced.size() == 1 and replaced[0].outcome == "superseded","superseded trip has one explicit outcome")
	check((Vector2(root.position)+Vector2(app._projected_anchors().foot)).distance_to(foot-Vector2(240,0)) < 2.0,"rendered foot actually reaches left point")
	phase = "left_to_right"
	check(request("chain:repeat","chain_right"),"next rightward trip accepted")
	check(await wait_for(func(): return arrived("chain:repeat"),22),"repeated turn and walk reach right point")
	check((Vector2(root.position)+Vector2(app._projected_anchors().foot)).distance_to(foot+Vector2(240,0)) < 2.0,"rendered foot actually reaches right point")
	phase = "stop_and_settle"
	check(request("chain:stop","chain_left"),"trip for interruption accepted")
	check(await wait_for(moving_owned_walk,12),"interruption begins during actual walk")
	var upper_start := root.position
	app._play_dialogue_action({"gesture":"wave","emotion":"neutral","intensity":1.0,"speed":1.0})
	await wait_for(func(): return false,0.5)
	check(app.motion.is_upper_body_active() and app.motion.current_gesture() == app._walk_started and not app._walk_started.is_empty(),"native action dispatcher layers upper body over the owned walk")
	check(abs(root.position.x-upper_start.x)>10 and app.autonomy.state == "walk","upper-body action preserves actual window travel")
	await wait_for(func(): return false,1.0)
	check(await wait_for(moving_owned_walk,3),"stop is issued during moving gait")
	app.living.cancel("user_stop")
	var stop_position := root.position
	var until := Time.get_ticks_msec()+2200
	while Time.get_ticks_msec() < until:
		await process_frame
		await sample()
		max_stop_drift = maxf(max_stop_drift,Vector2(root.position-stop_position).length())
	check(max_stop_drift == 0.0,"user stop freezes the native window while the body settles")
	app.motion.stop_upper_body_gesture()
	app._set_panel_open(true,false)
	for pair in [["wave","nod"],["nod","wave"],["wave","wave"]]:
		await preview_pair(str(pair[0]),str(pair[1]))
	check(frames.all(func(row):return row.save_error == OK),"continuous own-viewport captures saved")
	finish()

func preview_pair(first: String, second: String) -> void:
	phase = "pair:"+first+"->"+second
	pair_samples.clear()
	pair_preview_owned = true
	pair_incoming_start = -1.0
	pair_promoted = false
	pair_max_progress = 0.0
	ControlPanel._chain_select(app.panel._chain_first,first,0)
	ControlPanel._chain_select(app.panel._chain_second,second,0)
	app.panel._chain_lead.value = 0.5
	app.panel._chain_button.pressed.emit()
	check(app.motion.current_gesture() == first and app.motion._preview,phase+" starts through the actual panel button")
	var finished := await wait_for(func():return not app.motion.is_gesture_active(),15)
	var advancing := false
	if pair_samples.size() >= 2:
		var begin: Dictionary = pair_samples.front()
		var end: Dictionary = pair_samples.back()
		advancing = end.outgoing.time-begin.outgoing.time > 0.05 and end.incoming.time-begin.incoming.time > 0.05 \
			and begin.outgoing.name == first and begin.incoming.name == second \
			and pair_samples.all(func(row):return row.preview)
	check(advancing,phase+" both live timelines advance before outgoing completion")
	var duration := MotionBank.performed_duration(app.motion.bank.get_motion(second),1.0,1)
	var natural_finish: bool = finished and pair_promoted and pair_max_progress >= duration-0.25 \
		and pair_preview_owned and not app.motion._preview
	check(natural_finish,phase+" reaches incoming endpoint with preview ownership and releases it")
	pairs.append({"first":first,"second":second,"finished":finished,"advancing":advancing,
		"promoted":pair_promoted,"maximum_incoming_progress":pair_max_progress,"incoming_duration":duration,
		"active_preview_owned":pair_preview_owned,"natural_finish":natural_finish,
		"overlap_samples":pair_samples.duplicate(true)})

func finish() -> void:
	app.living.cancel("probe_finished")
	app.client.disconnect_ws()
	app.world_source.stop()
	app.autonomy.set_enabled(false)
	var settings = root.get_node("Settings")
	settings.data = original
	settings.save_now()
	if csv: csv.close()
	var report := {"checks":checks,"frames":frames,"transitions":transitions,"outcomes":app.living.outcomes,"pairs":pairs,
		"renderer":RenderingServer.get_video_adapter_name(),"character_identity":character_identity,"view":app._view_settings.duplicate(),"camera_basis":str(app.camera.basis),"stop_drift_px":max_stop_drift,
		"failures":checks.filter(func(row):return not row.ok).size(),
		"scope":"Normal production native scene, actual Windows placement/movement, user intentions, moving reversal, repeated turns/walks, user stop and three overlapping gesture pairs through the panel button; own viewport only; capture overhead included."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CHAIN_WINDOWS_FAILURES=",report.failures)
	quit(0 if report.failures == 0 else 1)
