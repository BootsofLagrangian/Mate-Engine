extends SceneTree
## Actual-main integration acceptance. Headless mode uses rounded simulated OS
## origins; --realtime uses this probe's real Window.position (Windows run owned
## by the coordinator). No backend/LLM calls are needed; local VRM/VRMA assets load.
## Args: --output ABS_DIR --model cheval-grand --fps 60 [--realtime]

var app
var settings_node
var original_settings: Dictionary
var output := "/tmp/liveliness"
var model_name := "cheval-grand"
var test_root := ""
var authored_profile: Dictionary = {}
var fps := 60
var realtime := false
var capture_fps := 0.0
var capture_until := 90.0
var next_capture := 0.0
var capture_metadata: Array[Dictionary] = []
var test_scale := 0.6
var manifest: Dictionary = {}
var previous_yaw := 0.0
var previous_heading_speed := 0.0
var turn_epochs: Dictionary = {}
var turn_epoch_results: Array[Dictionary] = []
var previous_skeleton_q := Quaternion.IDENTITY
var previous_skeleton_velocity := Vector3.ZERO
var _last_wall_usec := -1
var frame_deltas: Array[float] = []
var clock := 0.0
var frames: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var events: Array[Dictionary] = []
var csv: FileAccess
var prior_q := Quaternion.IDENTITY
var prior_torso_q := Quaternion.IDENTITY
var prior_velocity := Vector3.ZERO
var prior_origin := Vector2.ZERO
var phase_previous := 0.0
var previous_stride := 0.45
var phase_ready := false
var stance_epochs: Dictionary = {}
var epoch_results: Array[Dictionary] = []
var last_attention := Vector2.INF
var attention_changed_at := -INF
var _finish_started := false

func _initialize() -> void:
	call_deferred("run")

func companion_path(relative: String) -> String:
	return test_root.path_join(relative).simplify_path()

func argument(name: String, fallback: String = "") -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size(): return args[i+1]
	return fallback

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok":ok,"label":label,"details":details})
	print("LIVELINESS_CHECK ",label," ",ok," ",JSON.stringify(details))

func run() -> void:
	output = argument("--output",output)
	model_name = argument("--model",model_name)
	test_root = argument("--test-root",ProjectSettings.globalize_path("res://.."))
	fps = clampi(int(argument("--fps","60")),30,60)
	realtime = "--realtime" in OS.get_cmdline_user_args()
	test_scale = clampf(float(argument("--scale","0.6")),0.35,1.0)
	capture_fps = clampf(float(argument("--capture-fps","0")),0.0,12.0) if realtime else 0.0
	capture_until = clampf(float(argument("--capture-seconds","90")),1.0,180.0)
	if capture_fps > 0.0: DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(output)
	if not realtime and DisplayServer.get_name() != "headless":
		push_error("Use --headless for simulation, or explicitly --realtime for an owned visible Windows run.")
		quit(2)
		return
	seed(2251)
	OS.set_environment("MATE_BACKEND_URL","http://127.0.0.1:1")
	settings_node = root.get_node("Settings")
	original_settings = settings_node.data.duplicate(true)
	settings_node.data["vad_enabled"] = false
	settings_node.data["panel_open"] = false
	settings_node.data["surface_roam"] = false # Do not launch a Windows geometry helper.
	settings_node.data["pet_scale"] = test_scale
	settings_node.data["idle_clip"] = "auto"
	settings_node.data["behavior_enabled"] = true
	settings_node.data["interest_points"] = {}
	settings_node.data["character"] = model_name
	# Compile the derived test host after autoloads exist; static preload of main
	# from a SceneTree --script occurs before Settings is registered.
	var host_script := GDScript.new()
	host_script.source_code = "extends \"res://scripts/main.gd\"\nvar probe_clock := 0.0\nfunc _now() -> float:\n\treturn probe_clock\nfunc _save_window_position() -> void:\n\tpass\n"
	if host_script.reload() != OK:
		check(false,"test host compiled")
		finish()
		return
	app = host_script.new()
	app.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(app)
	current_scene = app
	app.client.disconnect_ws()
	app.client.set_process(false)
	for child in app.client.get_children():
		if child is HTTPRequest: child.cancel_request()
	app.world_source.stop()
	app.motion.set_process(false)
	app.audio.set_process(false)
	app.mic.set_vad_enabled(false)
	settings_node._save_timer.stop()
	if not app.avatar.load_from_file(companion_path("assets/"+model_name+".vrm")):
		check(false,"model loaded")
		finish()
		return
	app._frame_avatar()
	app.motion.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(companion_path("../Assets/StreamingAssets/cheval-motions.json"))))
	for clip in ["idle_natural","idle_talking","walk","walk_formal","sit_idle","dance","interact","pick_up"]:
		if app.motion.load_vrma(clip,companion_path("assets/motions/"+clip+".vrma")):
			app._vrma_loaded[clip] = true
	if app.get("living") == null:
		check(false,"main LivingBehavior integration is present")
		finish()
		return
	app._set_panel_open(false,false)
	app.session.activity = "idle"
	app._pet_scale = test_scale
	app._pet_scale_target = test_scale
	app._update_avatar_transform(1.0)
	app._update_pet_rect()
	var areas: Array[Rect2] = [Rect2(0,0,2400,1400)]
	if realtime:
		areas.clear()
		for i in DisplayServer.get_screen_count(): areas.append(Rect2(DisplayServer.screen_get_usable_rect(i)))
	else:
		app.autonomy.configure_simulation(areas,Vector2(300,100),app._navigation_rect())
		root.position = Vector2i(app.autonomy.position.round())
	app.autonomy.set_surface_mode(true)
	app.autonomy.set_contact_anchors(app._projected_anchors())
	app.autonomy.set_enabled(true)
	app.autonomy.set_pointer_interaction(false)
	app.session.characters.clear()
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(companion_path("characters/"+str(character)+".json")))
		if profile is Dictionary:
			app.session.characters.append(profile)
			if str(profile.get("id","")) == model_name: authored_profile = profile
	check(not authored_profile.is_empty() and authored_profile.has("behavior_style"),"matching authored behavior profile loaded")
	app.session.character_id = model_name
	app.living.tick(0.0) # Initialize character/catalogue before injecting test interests.
	var style_matches := true
	for key in authored_profile.get("behavior_style",{}):
		if not is_equal_approx(float(app.living.director.style.get(key,NAN)),float(authored_profile.behavior_style[key])): style_matches = false
	check(style_matches,"director uses matching authored profile",{"effective_style":app.living.director.style})
	app.living.observe_interest("quiet-left",Vector2(650,500),1.0,120.0,"point","Left quiet interest")
	app.living.observe_interest("quiet-right",Vector2(1650,400),1.0,120.0,"point","Right quiet interest")
	manifest = source_hashes()
	csv = FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	csv.store_line("time,scenario,origin_x,origin_y,head_speed,head_acceleration,torso_speed,state,ambient,gait_phase,left_stance,left_foot_x,left_foot_y,right_stance,right_foot_x,right_foot_y,head_qx,head_qy,head_qz,head_qw,left_sole_x,left_sole_y,right_sole_x,right_sole_y,attention_transition,autonomy_state,motion,phase_residual,dt,head_skeleton_speed,head_skeleton_acceleration,gaze_pursuit_speed,attention_kind,head_skeleton_qx,head_skeleton_qy,head_skeleton_qz,head_skeleton_qw,pointer_interaction,yaw,heading_speed,heading_acceleration,heading_target,heading_error,heading_ready,turn_active,left_turn_stance,right_turn_stance,left_turn_swing,right_turn_swing,left_foot_world_z,right_foot_world_z,left_turn_phase,right_turn_phase")
	# Quiet observation does not manufacture repeated gestures; the real director owns it.
	await observe("quiet_idle",90.0)
	analyze_quiet()
	# More scenario stages are added against the agreed LivingBehavior API below.
	await intent_scenarios()
	await interrupt_turn_scenario()
	analyze_turns()
	finish()

func observe(scenario: String, seconds: float) -> void:
	var until := clock+seconds
	while clock < until-0.000001:
		await step(scenario)

func step(scenario: String) -> void:
	var dt := 1.0/fps
	if realtime:
		var wall := Time.get_ticks_usec()
		if _last_wall_usec >= 0: dt = maxf((wall-_last_wall_usec)/1000000.0,0.000001)
		_last_wall_usec = wall
	frame_deltas.append(dt)
	clock += dt
	app.probe_clock = clock
	# Same ordering as production: Motion priority -10, main priority 0, then
	# child autonomy commit; frame_moved compensates the final pose after commit.
	app.motion._process(dt)
	app._process(dt)
	app.autonomy.set_visible_bounds(app._navigation_rect())
	app.autonomy.set_contact_anchors(app._projected_anchors())
	if realtime:
		app.autonomy._process(dt)
	else:
		app.autonomy.advance(dt)
		root.position = Vector2i(app.autonomy.position.round())
	capture(scenario,dt)
	if realtime and capture_fps > 0.0 and clock <= capture_until and clock >= next_capture:
		await RenderingServer.frame_post_draw
		var filename := "frames/%010d.png" % int(round(clock*1000.0))
		var result := root.get_texture().get_image().save_png(output.path_join(filename))
		capture_metadata.append({"file":filename,"simulation_time":clock,"wall_usec":Time.get_ticks_usec(),"scenario":scenario,"state":app.autonomy.state,"origin":{ "x":root.position.x,"y":root.position.y },"save_error":result})
		next_capture = clock + 1.0/capture_fps
	if realtime:
		await create_timer(1.0/fps).timeout

func desktop_origin() -> Vector2:
	return Vector2(root.position) if realtime else Vector2(app.autonomy.position).round()

func live_foot(side: String) -> Vector2:
	return desktop_origin()+app.camera.unproject_position(app.avatar.bone_global_position(side+"Foot"))

func live_sole_reference(side: String) -> Vector2:
	var sk: Skeleton3D = app.avatar.skeleton
	var idx: int = app.avatar.bone_index[side+"Foot"]
	var rest: Transform3D = sk.get_bone_global_rest(idx)
	var floor_y: float = float(app.avatar.sole_calibration.get("floor_y",rest.origin.y))
	var rest_point := Vector3(rest.origin.x,floor_y,rest.origin.z)
	var local_point := rest.affine_inverse()*rest_point
	var actual := sk.global_transform*sk.get_bone_global_pose(idx)*local_point
	return desktop_origin()+app.camera.unproject_position(actual)

func rotation_velocity(current: Quaternion, before: Quaternion, dt: float) -> Vector3:
	var delta := (current*before.inverse()).normalized()
	if delta.w < 0: delta = -delta
	var axis := Vector3(delta.x,delta.y,delta.z)
	return axis.normalized()*rad_to_deg(2*atan2(axis.length(),delta.w))/dt

func capture(scenario: String, dt: float) -> void:
	var sk: Skeleton3D = app.avatar.skeleton
	var skeleton_q := sk.get_bone_global_pose(app.avatar.bone_index.head).basis.orthonormalized().get_rotation_quaternion().normalized()
	var q := (sk.global_transform.basis*sk.get_bone_global_pose(app.avatar.bone_index.head).basis).orthonormalized().get_rotation_quaternion().normalized()
	var torso := (sk.global_transform.basis*sk.get_bone_global_pose(app.avatar.bone_index.chest).basis).orthonormalized().get_rotation_quaternion().normalized()
	var skeleton_velocity := rotation_velocity(skeleton_q,previous_skeleton_q,dt)
	var skeleton_acceleration := (skeleton_velocity-previous_skeleton_velocity).length()/dt
	var velocity := rotation_velocity(q,prior_q,dt)
	var torso_velocity := rotation_velocity(torso,prior_torso_q,dt)
	var acceleration := (velocity-prior_velocity).length()/dt
	var origin := desktop_origin()
	var traveled := origin-prior_origin
	var living_output: Dictionary = app.living.last_output
	var attention: Vector2 = living_output.get("attention_point",Vector2.INF)
	if attention != last_attention:
		attention_changed_at = clock
		last_attention = attention
	var phase_value: float = app.motion.gait.phase
	var observed_phase := fposmod(phase_value-phase_previous+0.5,1.0)-0.5
	var expected_phase := absf(traveled.x)/maxf(app._px_per_m*app.pet_scale(),1.0)/maxf(previous_stride,0.1)
	var phase_residual := absf(observed_phase-expected_phase) if phase_ready and app.autonomy.state == "walk" else 0.0
	phase_previous = phase_value
	previous_stride = app.motion.gait.stride
	phase_ready = true
	var heading_speed := rad_to_deg(angle_difference(previous_yaw,app.avatar.rotation.y))/dt
	var heading_acceleration := (heading_speed-previous_heading_speed)/dt
	var row := {"yaw":rad_to_deg(app.avatar.rotation.y),"heading_speed":heading_speed,"heading_acceleration":heading_acceleration,"heading_target":rad_to_deg(app.motion._facing_target),"heading_error":absf(rad_to_deg(angle_difference(app.avatar.rotation.y,app.motion._facing_target))),"heading_ready":app.motion.heading_ready(),"turn_active":app.motion.turn.active,"time":clock,"dt":dt,"scenario":scenario,"origin":origin,"displacement":traveled,"head_q":q,
		"head_speed":velocity.length(),"head_acceleration":acceleration,"head_skeleton_speed":skeleton_velocity.length(),"head_skeleton_acceleration":skeleton_acceleration,"torso_speed":torso_velocity.length(),
		"state":living_output.get("state",""),"ambient":living_output.get("ambient",""),
		"autonomy_state":app.autonomy.state,"motion":app.motion.current_gesture(),
		"pointer_interaction":app.autonomy._pointer_interaction,"yaw_step":absf(rad_to_deg(angle_difference(previous_yaw,app.avatar.rotation.y))),"travel_speed":app.autonomy.velocity.length(),
		"attention_transition":clock-attention_changed_at < 0.6,"gaze_pursuit_speed":app.motion._gaze_velocity.length(),"attention_kind":"look" if attention.is_finite() else "neutral_return","phase":app.motion.gait.phase,"phase_residual":phase_residual,
		"left_foot":live_foot("left"),"right_foot":live_foot("right"),
		"left_sole":live_sole_reference("left"),"right_sole":live_sole_reference("right")}
	for side in ["left","right"]:
		var diagnostic: Dictionary = app.motion.gait.diagnostics.get(side,{})
		row[side+"_stance"] = bool(diagnostic.get("stance",false))
		row[side+"_weight"] = float(diagnostic.get("weight",0))
		var contact: Dictionary = app.autonomy.get_support_contact()
		var surface_point: Vector2 = contact.get("screen_point",Vector2.INF)
		row[side+"_support_error"] = absf(Vector2(row[side+"_sole"]).y-surface_point.y) if surface_point.is_finite() else INF
		update_epoch(side,row)
		var turning: Dictionary = app.motion.turn.diagnostics.get(side,{})
		row[side+"_turn_stance"] = bool(turning.get("stance",false))
		row[side+"_turn_swing"] = bool(turning.get("swing",false))
		row[side+"_turn_phase"] = float(turning.get("turn_phase",-1.0))
		row[side+"_foot_world_z"] = app.avatar.bone_global_position(side+"Foot").z
		if row[side+"_turn_stance"]:
			if not turn_epochs.has(side): turn_epochs[side] = {"side":side,"start":clock,"point":row[side+"_foot"],"sole":row[side+"_sole"],"max_drift":0.0,"sole_drift":0.0,"frames":0}
			var epoch: Dictionary = turn_epochs[side]
			epoch.max_drift = maxf(epoch.max_drift,Vector2(row[side+"_foot"]).distance_to(epoch.point))
			epoch.sole_drift = maxf(epoch.sole_drift,Vector2(row[side+"_sole"]).distance_to(epoch.sole))
			epoch.frames += 1
		else:
			if turn_epochs.has(side):
				turn_epoch_results.append(turn_epochs[side])
				turn_epochs.erase(side)
	frames.append(row)
	csv.store_csv_line(PackedStringArray([str(clock),scenario,str(origin.x),str(origin.y),str(velocity.length()),str(acceleration),str(torso_velocity.length()),str(row.state),str(row.ambient),str(row.phase),str(row.left_stance),str(row.left_foot.x),str(row.left_foot.y),str(row.right_stance),str(row.right_foot.x),str(row.right_foot.y),str(q.x),str(q.y),str(q.z),str(q.w),str(row.left_sole.x),str(row.left_sole.y),str(row.right_sole.x),str(row.right_sole.y),str(row.attention_transition),str(row.autonomy_state),str(row.motion),str(phase_residual),str(dt),str(skeleton_velocity.length()),str(skeleton_acceleration),str(row.gaze_pursuit_speed),str(row.attention_kind),str(skeleton_q.x),str(skeleton_q.y),str(skeleton_q.z),str(skeleton_q.w),str(row.pointer_interaction),str(row.yaw),str(row.heading_speed),str(row.heading_acceleration),str(row.heading_target),str(row.heading_error),str(row.heading_ready),str(row.turn_active),str(row.left_turn_stance),str(row.right_turn_stance),str(row.left_turn_swing),str(row.right_turn_swing),str(row.left_foot_world_z),str(row.right_foot_world_z),str(row.left_turn_phase),str(row.right_turn_phase)]))
	prior_q = q
	prior_torso_q = torso
	prior_velocity = velocity
	prior_origin = origin
	previous_yaw = app.avatar.rotation.y
	previous_heading_speed = heading_speed
	previous_skeleton_q = skeleton_q
	previous_skeleton_velocity = skeleton_velocity

func update_epoch(side: String,row: Dictionary) -> void:
	if bool(row[side+"_stance"]) and float(row.yaw_step) <= 0.5:
		var point: Vector2 = row[side+"_foot"]
		var sole: Vector2 = row[side+"_sole"]
		if not stance_epochs.has(side):
			stance_epochs[side] = {"side":side,"start":clock,"scenario":row.scenario,"point":point,"sole":sole,"frames":0,"peak_drift":0.0,"sole_peak_drift":0.0,"distances":[],"support_errors":[]}
		var epoch: Dictionary = stance_epochs[side]
		epoch.frames += 1
		epoch.peak_drift = maxf(epoch.peak_drift,point.distance_to(epoch.point))
		epoch.sole_peak_drift = maxf(epoch.sole_peak_drift,sole.distance_to(epoch.sole))
		epoch.distances.append(point.distance_to(epoch.point))
		epoch.support_errors.append(row[side+"_support_error"])
	elif stance_epochs.has(side):
		epoch_results.append(stance_epochs[side].duplicate(true))
		stance_epochs.erase(side)

func analyze_quiet() -> void:
	var intervals: Array[float] = []
	var run := 0.0
	var quiet_time := 0.0
	var states := {}
	var peak := 0.0
	var peak_accel := 0.0
	var quiet_speeds: Array[float] = []
	var quiet_accels: Array[float] = []
	var glance_speeds: Array[float] = []
	var glance_accels: Array[float] = []
	var all_speeds: Array[float] = []
	var all_accels: Array[float] = []
	var orientation := Quaternion.IDENTITY
	var excursions := 0
	var orientation_ready := false
	for row in frames:
		if row.scenario != "quiet_idle" or row.time < 2.0: continue
		states[row.state] = true
		all_speeds.append(row.head_speed)
		all_accels.append(row.head_acceleration)
		if not orientation_ready:
			orientation = row.head_q
			orientation_ready = true
		elif row.state in ["rest","curious","sleepy"] and rotation_velocity(row.head_q,orientation,1.0).length() >= 3.0:
			excursions += 1
			orientation = row.head_q
		var is_quiet: bool = row.displacement.length() < 0.5 and row.head_speed < 5 and row.torso_speed < 3
		if is_quiet:
			run += row.dt
			quiet_time += row.dt
		else:
			if run >= 2.0: intervals.append(run)
			run = 0
		if row.displacement.length() < 0.5 and row.state in ["rest","curious","sleepy"] and row.motion == "idle":
			# Active bounded pursuit includes deliberate looks and their neutral
			# return; a fixed timeout does not prove that a look has settled.
			if row.gaze_pursuit_speed > 0.01:
				glance_speeds.append(row.head_speed)
				glance_accels.append(row.head_acceleration)
			else:
				peak = maxf(peak,row.head_speed)
				peak_accel = maxf(peak_accel,row.head_acceleration)
				quiet_speeds.append(row.head_speed)
				quiet_accels.append(row.head_acceleration)
	if run >= 2.0: intervals.append(run)
	check(intervals.size() >= 2 and quiet_time >= 18.0,"meaningful quiet gaps",{"intervals":intervals,"quiet_seconds":quiet_time})
	check(states.size() >= 2,"varied director states",{"states":states.keys()})
	check(peak < 12 and peak_accel < 150,"stationary head avoids jitter",{"peak_speed":peak,"peak_acceleration":peak_accel,"p95_speed":percentile(quiet_speeds,0.95),"p95_acceleration":percentile(quiet_accels,0.95),"allframe_peak_speed":percentile(all_speeds,1.0),"allframe_peak_acceleration":percentile(all_accels,1.0),"head_excursions_over3deg":excursions})
	check(percentile(glance_speeds,1.0) <= 30 and percentile(glance_accels,1.0) <= 150,"purposeful glances stay bounded",{"peak_speed":percentile(glance_speeds,1.0),"peak_acceleration":percentile(glance_accels,1.0),"p95_speed":percentile(glance_speeds,0.95),"p95_acceleration":percentile(glance_accels,0.95),"measured_frames":glance_speeds.size()})

func intent_scenarios() -> void:
	app.living.cancel("probe_phase_change")
	await observe("settle_before_intents",4.0)
	var unknown_user: Dictionary = app.living.request_intent({"kind":"move_to","target_id":"missing-probe-target"},"user","probe:unknown:user")
	var unknown_llm: Dictionary = app.living.request_intent({"kind":"move_to","target_id":"missing-probe-target"},"llm","probe:unknown:llm")
	check(not bool(unknown_user.get("accepted",true)) and unknown_user.get("reason") == "unknown_target","unknown target explicitly rejected",unknown_user)
	check(unknown_user == unknown_llm,"user and LLM use same unknown-target path",{"user":unknown_user,"llm":unknown_llm})
	var invalid: Dictionary = app.living.request_intent({"kind":"invented_action"},"user","probe:invalid")
	check(not bool(invalid.get("accepted",true)),"unknown action explicitly rejected",invalid)
	# A catalogued point outside any current surface must resolve unreachable,
	# rather than silently clamp to an unrelated safe target.
	app.living.observe_interest("probe-unreachable",Vector2(100000,-100000),1.0,40.0,"point","Unreachable probe target")
	var unreachable: Dictionary = app.living.request_intent({"kind":"move_to","target_id":"probe-unreachable"},"user","probe:unreachable")
	events.append({"time":clock,"request":"unreachable","result":unreachable})
	await observe("unreachable_intent",4.0)
	check(has_outcome("probe:unreachable","unreachable"),"catalogued unreachable point reports terminal status",{"outcomes":app.living.outcomes})
	app.living.cancel("probe_next")
	var travel := await request_trip("user","probe:travel")
	if travel:
		var first_motion_time := -1.0
		var first_gaze_time := -1.0
		var anticipate_time := -1.0
		var request_time := clock
		var initial_origin := desktop_origin()
		var head: int = app.avatar.bone_index.head
		var initial_head: Quaternion = app.avatar.skeleton.get_bone_global_pose(head).basis.orthonormalized().get_rotation_quaternion()
		for i in 18*fps:
			await step("directed_walk")
			var q: Quaternion = app.avatar.skeleton.get_bone_global_pose(head).basis.orthonormalized().get_rotation_quaternion()
			if anticipate_time < 0 and app.autonomy.state == "anticipate":
				anticipate_time = clock
				initial_head = q
			if anticipate_time >= 0 and first_gaze_time < 0 and rotation_velocity(q,initial_head,1.0).length() >= 1.5: first_gaze_time = clock
			if first_motion_time < 0 and desktop_origin().distance_to(initial_origin) > 0.5: first_motion_time = clock
			if i > fps*3 and has_outcome("probe:travel","arrived"): break
		check(first_gaze_time >= request_time and first_motion_time-first_gaze_time >= 0.15,"visible anticipatory gaze before desktop travel",{"anticipate_start":anticipate_time,"first_gaze":first_gaze_time,"first_motion":first_motion_time,"lead_seconds":first_motion_time-first_gaze_time})
		check(desktop_origin().distance_to(initial_origin) >= 200,"directed journey covers 200 desktop pixels",{"distance":desktop_origin().distance_to(initial_origin)})
	for kind in ["speaking","dragging","panel"]:
		app.living.cancel("probe_preemption_setup")
		await observe("preemption_settle",4.0)
		var trip := await request_trip("llm","probe:preempt:"+kind)
		if not trip: continue
		var began := false
		for i in 6*fps:
			await step("preempt_"+kind+"_before")
			if app.autonomy.velocity.length() > 20:
				began = true
				break
		check(began,"travel starts before "+kind+" preemption")
		var before_hold := desktop_origin()
		set_context(kind,true)
		await step("preempt_"+kind+"_hold")
		var held := desktop_origin()
		check(app.autonomy.velocity.length() < 0.01 and held.distance_to(before_hold) <= 0.5,kind+" stops within first post-context frame",{"first_frame_speed":app.autonomy.velocity.length(),"first_frame_displacement":held.distance_to(before_hold)})
		var max_drift := 0.0
		for i in 2*fps:
			await step("preempt_"+kind+"_hold")
			max_drift = maxf(max_drift,desktop_origin().distance_to(held))
		check(max_drift <= 0.5 and app.autonomy.velocity.length() < 0.01,kind+" holds desktop position",{"drift":max_drift})
		set_context(kind,false)
		var release_time := clock
		var release_origin := desktop_origin()
		await observe("preempt_"+kind+"_release",0.3)
		check(desktop_origin().distance_to(release_origin) <= 0.5,kind+" release does not instantly restart obsolete travel")
		await observe("preempt_"+kind+"_resume",4.0)
		check(str(app.living.last_output.get("state","")) not in ["held","speaking","attentive"],kind+" resumes eligible behavior",{"state":app.living.last_output.get("state"),"elapsed":clock-release_time})
	analyze_gait()

func request_trip(source: String,id: String) -> bool:
	var candidates: Array = app.autonomy.available_surface_targets()
	var best := Vector2.INF
	var distance := 0.0
	var here := desktop_origin()+Vector2(app._projected_anchors().foot)
	for entry in candidates:
		var point: Vector2 = entry.point
		if point.distance_to(here) > distance:
			distance = point.distance_to(here)
			best = point
	if not best.is_finite():
		check(false,"reachable journey target available",{"support":app.autonomy.get_support_contact()})
		return false
	app.living.observe_interest(id+":target",best,1.0,60.0,"floor","Probe journey")
	var response: Dictionary = app.living.request_intent({"kind":"move_to","target_id":id+":target"},source,id)
	events.append({"time":clock,"request":id,"source":source,"response":response,"target":best})
	check(bool(response.get("accepted",false)),"known "+source+" target accepted",response)
	return bool(response.get("accepted",false))

func has_outcome(id: String,outcome: String) -> bool:
	for item in app.living.outcomes:
		if str(item.get("id","")) == id and str(item.get("outcome","")) == outcome: return true
	return false

func set_context(kind: String,value: bool) -> void:
	match kind:
		"speaking":
			app.audio.voice_active = value
			app.audio.envelope = 0.2 if value else 0.0
			app.audio.voice_active_changed.emit(value)
		"dragging": app._drag_active = value
		"panel": app._set_panel_open(value,false)

func analyze_gait() -> void:
	var epochs := epoch_results.duplicate(true)
	for side in stance_epochs: epochs.append(stance_epochs[side])
	var measured := 0
	var max_drift := 0.0
	var max_sole_drift := 0.0
	var drifts: Array[float] = []
	var support_errors: Array[float] = []
	var moving_frames := 0
	var measured_frames := 0
	var still_phase_drift := 0.0
	var max_phase_residual := 0.0
	var phase_last := 0.0
	var seen_phase := false
	var exclusion_counts := {"not_walking":0,"turning":0,"unplanted_or_blending":0}
	for row in frames:
		if seen_phase and absf(row.displacement.x) < 0.01:
			still_phase_drift = maxf(still_phase_drift,absf(fposmod(row.phase-phase_last+0.5,1.0)-0.5))
		phase_last = row.phase
		seen_phase = true
		max_phase_residual = maxf(max_phase_residual,row.phase_residual)
		if row.autonomy_state != "walk" or row.travel_speed < 20:
			exclusion_counts.not_walking += 1
			continue
		if row.yaw_step > 0.5:
			exclusion_counts.turning += 1
			continue
		moving_frames += 1
		if row.left_stance or row.right_stance: measured_frames += 1
		else: exclusion_counts.unplanted_or_blending += 1
	for epoch in epochs:
		if int(epoch.frames) < 4: continue
		measured += 1
		max_drift = maxf(max_drift,epoch.peak_drift)
		max_sole_drift = maxf(max_sole_drift,epoch.sole_peak_drift)
		for value in epoch.distances: drifts.append(float(value))
		for value in epoch.support_errors:
			if is_finite(float(value)): support_errors.append(float(value))
	check(measured >= 4 and measured_frames >= moving_frames*0.5,"non-vacuous planted-foot coverage",{"epochs":measured,"walking_frames":moving_frames,"measured_frames":measured_frames,"exclusions":exclusion_counts})
	check(measured >= 4 and max_drift <= 4.0 and percentile(drifts,0.95) <= 2.0,"actual desktop planted ankle drift",{"max_px":max_drift,"sole_reference_max_px":max_sole_drift,"p95_px":percentile(drifts,0.95),"support_height_peak_px":percentile(support_errors,1.0)})
	check(still_phase_drift < 0.000001,"gait phase freezes without desktop displacement",{"peak_phase_drift":still_phase_drift,"moving_phase_residual":max_phase_residual})


func percentile(values: Array[float],quantile: float) -> float:
	if values.is_empty(): return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[clampi(int(floor((ordered.size()-1)*quantile)),0,ordered.size()-1)]

func source_hashes() -> Dictionary:
	var hashes := {}
	var own_path: String = get_script().resource_path
	if FileAccess.file_exists(own_path): hashes["probe_liveliness.gd"] = FileAccess.get_sha256(own_path)
	for name in ["main.gd","living_behavior.gd","behavior_director.gd","desktop_autonomy.gd","desktop_gait.gd","leg_ik.gd","turn_stepper.gd","motion_player.gd","vrm_avatar.gd","autonomy_bridge.gd"]:
		var path: String = "res://scripts/"+str(name)
		if FileAccess.file_exists(path): hashes[name] = FileAccess.get_sha256(path)
	for path in ["res://tools/probe_liveliness.gd",companion_path("assets/"+model_name+".vrm"),companion_path("../Assets/StreamingAssets/cheval-motions.json"),companion_path("characters/"+model_name+".json")]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	for clip in ["idle_natural","idle_talking","walk","walk_formal","sit_idle","dance","interact","pick_up"]:
		var path: String = companion_path("assets/motions/"+str(clip)+".vrma")
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func finish() -> void:
	if _finish_started: return
	_finish_started = true
	if csv: csv.close()
	if capture_fps > 0.0:
		var capture_file := FileAccess.open(output.path_join("captures.json"),FileAccess.WRITE)
		capture_file.store_string(JSON.stringify({"scope":"own root viewport only; capture and PNG write time included in next measured update delta","requested_fps":capture_fps,"duration_cap_seconds":capture_until,"frames":capture_metadata},"\t"))
		capture_file.close()
	for side in stance_epochs: epoch_results.append(stance_epochs[side])
	var failures := 0
	for item in checks:
		if not item.ok: failures += 1
	var pointer_interference := 0
	for row in frames:
		if row.pointer_interaction and row.scenario in ["quiet_idle","directed_walk"]: pointer_interference += 1
	var report := {"uncontrolled_pointer_frames":pointer_interference,"controlled_run_valid":not realtime or pointer_interference == 0,"scope":"actual main wiring; deterministic fixed-delta" if not realtime else "actual main wiring, real owned Windows origin, measured wall-clock frame deltas",
		"fps":fps,"scale":test_scale,"model":model_name,"seed":2251,"behavior_style":authored_profile.get("behavior_style",{}),"effective_behavior_style":app.living.director.style if app and app.get("living") else {},"checks":checks,"failures":failures,"epochs":epoch_results,"events":events,
		"missing_cells":["additional scales: main-scene matrix uses default 0.6; standalone gait scale matrix separate", "actual Windows run: coordinator-owned" ] if not realtime else ["additional scales: this run uses one selected scale"],"frames":frames.size(),"source_sha256":manifest,"frame_dt_p50":percentile(frame_deltas,0.5),"frame_dt_p95":percentile(frame_deltas,0.95)}
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if app:
		app.world_source.stop()
		app.client.disconnect_ws()
		app.free()
	if settings_node:
		settings_node._save_timer.stop()
		settings_node.data = original_settings
		settings_node._dirty = false
	print("LIVELINESS_RESULT failures=",failures," frames=",frames.size()," report=",output.path_join("report.json"))
	quit(1 if failures else 0)

func analyze_turns() -> void:
	for side in turn_epochs: turn_epoch_results.append(turn_epochs[side])
	turn_epochs.clear()
	var peak_speed := 0.0
	var peak_acceleration := 0.0
	var peak_error_moving := 0.0
	var turning_frames := 0
	var supported_frames := 0
	var unsupported_seconds := 0.0
	var max_drift := 0.0
	var max_sole := 0.0
	var interrupted_head_acceleration := 0.0
	for row in frames:
		if row.time < 1.0: continue
		peak_speed = maxf(peak_speed,absf(row.heading_speed))
		peak_acceleration = maxf(peak_acceleration,absf(row.heading_acceleration))
		if row.displacement.length() > 0.5 and row.autonomy_state == "walk": peak_error_moving = maxf(peak_error_moving,row.heading_error)
		if row.turn_active:
			turning_frames += 1
			if row.left_turn_stance or row.right_turn_stance: supported_frames += 1
			else: unsupported_seconds += row.dt
		if str(row.scenario).ends_with("_hold"): interrupted_head_acceleration = maxf(interrupted_head_acceleration,row.head_skeleton_acceleration)
	for epoch in turn_epoch_results:
		max_drift = maxf(max_drift,epoch.max_drift)
		max_sole = maxf(max_sole,epoch.sole_drift)
	check(peak_speed <= 90.1 and peak_acceleration <= 180.5,"turn heading derivative limits",{"speed_deg_s":peak_speed,"acceleration_deg_s2":peak_acceleration})
	check(peak_error_moving <= 15.0,"departure heading aligned",{"max_error_degrees":peak_error_moving})
	check(turn_epoch_results.size() >= 4 and max_drift <= 4.0 and max_sole <= 4.0,"turn actual desktop support drift",{"epochs":turn_epoch_results.size(),"max_ankle_px":max_drift,"max_sole_reference_px":max_sole,"turn_frames":turning_frames,"supported_frames":supported_frames,"unsupported_seconds":unsupported_seconds})
	events.append({"kind":"turn_quality","epochs":turn_epoch_results,"interrupted_skeleton_head_acceleration":interrupted_head_acceleration,"support_coverage":float(supported_frames)/maxi(turning_frames,1)})

func interrupt_turn_scenario() -> void:
	app.living.cancel("probe_turn_interrupt_setup")
	await observe("turn_interrupt_settle",4.0)
	if not await request_trip("user","probe:turn-interrupt"): return
	var began := false
	for i in 6*fps:
		await step("turn_interrupt_before")
		if app.motion.turn.active and absf(rad_to_deg(app.motion._facing_velocity)) >= 20.0:
			began = true
			break
	check(began,"interrupted turn has nonzero heading velocity")
	var held := desktop_origin()
	set_context("speaking",true)
	await step("turn_interrupt_hold")
	check(app.autonomy.velocity.length() < 0.01 and desktop_origin().distance_to(held) <= 0.5,"speaking preempts mid-turn desktop departure")
	await observe("turn_interrupt_hold",3.0)
	set_context("speaking",false)
	await observe("turn_interrupt_release",4.3)
