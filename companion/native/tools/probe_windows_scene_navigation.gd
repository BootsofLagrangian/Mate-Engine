extends SceneTree
## External, opt-in production Windows temporal probe. Root exclusively launches.
## --output ABS_DIR [--character cheval-grand|rice-shower|eishin-flash]
## --abort-case none|cancel|support_loss (optional separate finite-entry abort).
## Samples and saves the owned shared viewport at every rendered frame; timing
## checks reject finite transitions whose retained samples fall below 20 Hz.
const LIMIT_MS := 180000
const JOINTS := ["hips","leftUpperLeg","leftLowerLeg","leftFoot","rightUpperLeg","rightLowerLeg","rightFoot"]
var app
var settings_node
var original := {}
var output := ""
var character := "cheval-grand"
var started := 0
var closing := false
var recording := false
var sequence := ""
var csv: FileAccess
var samples: Array = []
var report := {"checks":[],"commands":[],"phases":[],"sequences":[],"frames":[]}

func _initialize() -> void:
	call_deferred("run")

func arg(key: String, fallback: String = "") -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i] == key: return args[i+1]
	return fallback

func elapsed() -> int: return Time.get_ticks_msec()-started

func json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)] = json_safe(value[key])
		return result
	if value is Array:
		var result := []
		for entry in value: result.append(json_safe(entry))
		return result
	if value is float: return value if is_finite(value) else null
	if value is Vector3: return json_safe([value.x,value.y,value.z])
	if value is Vector2 or value is Vector2i: return json_safe([value.x,value.y])
	if value is Quaternion: return json_safe([value.x,value.y,value.z,value.w])
	if typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING]: return value
	return str(value)

func write_report() -> void:
	if output.is_empty(): return
	report["elapsed_ms"] = elapsed()
	report["failures"] = report.checks.filter(func(row): return not row.ok).size()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(json_safe(report),"  "))

func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok":ok,"label":label,"ms":elapsed()})
	print("AUTHORED_SEATING ",label," ",ok)
	write_report()
	return ok

func stage() -> String: return str(app.objects._interaction.get("stage","idle"))

func knee_angle(points: Dictionary, side: String) -> float:
	if not points.has(side+"UpperLeg") or not points.has(side+"LowerLeg") or not points.has(side+"Foot"): return -1.0
	var thigh: Vector3 = points[side+"UpperLeg"]-points[side+"LowerLeg"]
	var shin: Vector3 = points[side+"Foot"]-points[side+"LowerLeg"]
	return 180.0-rad_to_deg(thigh.angle_to(shin))

func sample_frame() -> void:
	if not recording or closing or not app.avatar.has_model(): return
	var state: Dictionary = app.motion.seated_transition_state()
	var joints := {}
	var scene_joints := {}
	var physical_joints := {}
	var pixels := {}
	var rotations := {}
	var shared: bool = app.objects.contact_scene_active()
	for joint in JOINTS:
		var index: int = app.avatar.bone_index.get(joint,-1)
		if index < 0: continue
		var world: Vector3 = app.avatar.skeleton.global_transform*app.avatar.skeleton.get_bone_global_pose(index).origin
		joints[joint] = world
		pixels[joint] = Vector2(root.position)+app.camera.unproject_position(world)
		# Front orthographic fixture: desktop pixel coordinates / true projection
		# derivative cancel crop/window translations; optical depth retains Z.
		var ppm: float = DesktopView.projection_axes(app.camera,world).get("screen_pixels_per_metre",0.0)
		if ppm > 0.0:
			physical_joints[joint] = Vector3(pixels[joint].x/ppm,-pixels[joint].y/ppm,DesktopView.depth(app.camera,world))
		rotations[joint] = app.avatar.skeleton.get_bone_pose_rotation(index)
		if shared: scene_joints[joint] = app.objects._contact_scene.to_local(world)
	var anchors: Dictionary = app.avatar.contact_anchors()
	var row := {"ms":elapsed(),"sequence":sequence,"stage":stage(),"window":root.position,
		"camera":app.camera.global_transform,"transition":state,"joints_world":joints,
		"joints_prop_local":scene_joints,"joints_physical_desktop":physical_joints,"joints_desktop_px":pixels,"joint_rotations":rotations,
		"left_knee_deg":knee_angle(joints,"left"),"right_knee_deg":knee_angle(joints,"right"),
		"anchors":anchors,"support":app.autonomy.get_support_contact(),"shared":shared,
		"presentation_offset":app.objects.presentation_offset(),"sit_active":app.is_sitting(),
		"sit_attached":app._sit_attached,"interaction":app.objects._interaction.duplicate(true)}
	if shared:
		row["seat_error_px"] = (Vector2(root.position)+Vector2(app._projected_anchors().sit)).distance_to(app.objects.contact_socket_screen("seat"))
		row["seat_world"] = app.objects.contact_socket_world("seat")
	var clip_name := str(state.get("clip",""))
	if app.motion.vrma_clips.has(clip_name):
		var clip = app.motion.vrma_clips[clip_name]
		row["source_hips_normalized"] = clip.sample_hips_offset(float(state.time))
		row["source_rotations"] = clip.sample(float(state.time))
	if samples.is_empty() or samples[-1].stage != row.stage or samples[-1].sequence != sequence:
		report.phases.append({"ms":row.ms,"sequence":sequence,"stage":row.stage,"frame":samples.size(),"transition":state})
	var filename := "frames/%06d.png" % samples.size()
	var image := root.get_texture().get_image()
	row["image_error"] = image.save_png(output.path_join(filename))
	row["image"] = filename
	samples.append(row)
	csv.store_csv_line(PackedStringArray([str(row.ms),sequence,row.stage,str(root.position.x),str(root.position.y),clip_name,
		str(state.get("time",0)),str(state.get("duration",0)),str(state.get("root_progress",0)),
		str(row.left_knee_deg),str(row.right_knee_deg),JSON.stringify(json_safe(joints)),
		JSON.stringify(json_safe(scene_joints)),JSON.stringify(json_safe(pixels)),JSON.stringify(json_safe(row.get("source_hips_normalized"))),
		str(row.get("seat_error_px",-1)),filename]))
	csv.flush()

func tick() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	sample_frame()

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := mini(Time.get_ticks_msec()+int(seconds*1000),started+LIMIT_MS-500)
	while not closing and Time.get_ticks_msec() < deadline:
		await tick()
		if predicate.call(): return true
	return false

func command(intent: Dictionary, id: String) -> bool:
	var result: Dictionary = app.living.request_intent(intent,"user",id)
	report.commands.append({"id":id,"intent":intent,"result":result,"ms":elapsed()})
	return check(result.get("accepted",false),"production validated command accepted: "+id)

func settled_floor() -> bool:
	var support: Dictionary = app.autonomy.get_support_contact()
	return app.autonomy.can_request_move() and support.get("attached",false) and str(support.get("surface_id","")).begins_with("floor:")

func corridor() -> bool:
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var cursor := DisplayServer.mouse_get_position()
	var fraction := .60 if cursor.x < area.position.x+area.size.x*.5 else .25
	var foot := Vector2(area.position.x+area.size.x*fraction,area.end.y)
	root.position = Vector2i(foot-Vector2(app._projected_anchors().foot))
	report["corridor"] = {"area":area,"cursor":cursor,"foot":foot,"policy":"own window only; no cursor injection or pointer policy bypass"}
	return await wait_for(settled_floor,12.0)

func analyze_phase(rows: Array, phase: String, label: String) -> void:
	var finite: Array = rows.filter(func(row): return row.stage == phase)
	if not check(finite.size() >= 4,label+" captures finite "+phase): return
	var first: Dictionary = finite.front()
	var last: Dictionary = finite.back()
	var max_gap := 0
	var window_drift := 0.0
	var left_min := 1e9
	var left_max := -1e9
	var right_min := 1e9
	var right_max := -1e9
	var source_spread := 0.0
	var monotonic := true
	for i in finite.size():
		var row: Dictionary = finite[i]
		window_drift = maxf(window_drift,Vector2(row.window).distance_to(Vector2(first.window)))
		left_min = minf(left_min,row.left_knee_deg); left_max = maxf(left_max,row.left_knee_deg)
		right_min = minf(right_min,row.right_knee_deg); right_max = maxf(right_max,row.right_knee_deg)
		if row.has("source_hips_normalized") and first.has("source_hips_normalized"):
			source_spread = maxf(source_spread,Vector3(row.source_hips_normalized).distance_to(first.source_hips_normalized))
		if i > 0:
			max_gap = maxi(max_gap,int(row.ms-finite[i-1].ms))
			monotonic = monotonic and float(row.transition.time)>float(finite[i-1].transition.time)
	var metrics := {"phase":phase,"count":finite.size(),"max_gap_ms":max_gap,"window_drift_px":window_drift,
		"left_knee_spread_deg":left_max-left_min,"right_knee_spread_deg":right_max-right_min,"source_hips_spread_normalized":source_spread,
		"timeline_first":first.transition,"timeline_last":last.transition}
	report.sequences.append({"label":label,"metrics":metrics})
	check(max_gap <= 50,label+" "+phase+" retained samples at least20Hz (maximum gap<=50ms)")
	check(monotonic and float(last.transition.time)-float(first.transition.time)>.3,label+" "+phase+" actual authored time advances")
	check(source_spread>.03,label+" "+phase+" source hips change during finite clip")
	# Motion owner measured UMA01 source21→95deg and retarget86–93deg entry
	# ranges across3rigs.30deg excludes a static final pose; it is not a speed limit.
	check(left_max-left_min>30.0 and right_max-right_min>30.0,label+" "+phase+" both real knees change before handoff")
	check(window_drift<=1.0,label+" "+phase+" OS window held throughout finite authored phase")
	check(finite.all(func(row): return not row.transition.get("clip","").is_empty() and row.has("source_rotations")),label+" "+phase+" samples actual registered source clip")
	check(finite.all(func(row): return row.joints_world.size() == JOINTS.size() and row.joints_world.values().all(func(point): return Vector3(point).is_finite())),label+" "+phase+" measured joint coordinates finite")

func analyze_sequence(label: String) -> void:
	var rows: Array = samples.filter(func(row): return row.sequence == label)
	analyze_phase(rows,"entering",label)
	analyze_phase(rows,"exiting",label)
	check(rows.any(func(row): return row.stage == "approaching"),label+" captures real approach")
	check(rows.any(func(row): return row.stage == "facing"),label+" captures orientation phase")
	var seated: Array = rows.filter(func(row): return row.stage in ["seated","using"] and row.sit_attached)
	check(not seated.is_empty() and seated.all(func(row): return row.get("seat_error_px",1e9)<1.0),label+" terminal support coincides within1px")
	for i in range(1,rows.size()):
		var before: Dictionary = rows[i-1]
		var after: Dictionary = rows[i]
		if before.stage not in ["entering","exiting"] or before.stage == after.stage: continue
		var gap := float(after.ms-before.ms)/1000.0
		var residual := 0.0
		var count := 0
		# Desktop metres remain available after the occupied scene is released.
		for joint in JOINTS:
			if before.joints_world.has(joint) and after.joints_world.has(joint):
				residual = maxf(residual,Vector3(before.joints_world[joint]).distance_to(after.joints_world[joint])); count += 1
		report.sequences.append({"label":label,"handoff":before.stage+"->"+after.stage,"dt":gap,"max_joint_step_world_m":residual,"joint_count":count,"window_delta":Vector2(after.window)-Vector2(before.window)})
		# Explicit conservative discontinuity gate; raw physical joints remain for
		# temporal review. This does not assert the clip itself is aesthetically natural.
		check(gap>0.0 and gap<=.05,label+" "+before.stage+" handoff boundary retained at least20Hz")
		check(gap>0.0 and gap<=.05 and count == JOINTS.size() and residual<=.025+gap*1.5,label+" "+before.stage+" physical joint handoff continuous")
	check(rows.all(func(row): return row.image_error == OK),label+" all owned frames retained")

func legacy_run_sequence(type: String) -> bool:
	sequence = type
	recording = true
	var verb := "use" if type == "computer" else "sit"
	if not command({"kind":"furniture","object_type":type,"verb":verb,"placement":"near"},"temporal-"+type): return false
	if not check(await wait_for(func(): return stage() == ("using" if type == "computer" else "seated") and app._sit_attached,35.0),type+" completes authored entry and attaches"):
		report["failed_creation_diagnostics"]=app.objects.fit_diagnostics.duplicate(true)
		return false
	await wait_for(func(): return false,.4)
	if type == "chair":
		if not check(app.objects.request_stand(),"chair normal stand request starts authored exit"): return false
	if not check(await wait_for(func(): return stage() == "idle" and not app.motion.seated_transition_state().get("active",false),15.0),type+" normal authored exit completes"):
		return false
	await wait_for(func(): return false,.2)
	recording = false
	analyze_sequence(type)
	for row in app.objects.rows(): app.objects.remove_object(str(row.id))
	return check(await wait_for(settled_floor,8.0),type+" returns to normal floor support")

func run_abort(kind: String) -> void:
	sequence = "abort_"+kind
	recording = true
	if not command({"kind":"furniture","object_type":"chair","verb":"sit","placement":"near"},sequence): return
	if not check(await wait_for(func(): return stage() == "entering" and float(app.motion.seated_transition_state().get("progress",0))>.25,30.0),sequence+" reaches actual partial authored entry"): return
	var object_id := str(app.objects._interaction.id)
	if kind == "support_loss": app.objects.remove_object(object_id)
	else: app.objects.cancel_interaction("cancelled")
	check(await wait_for(func(): return stage() == "idle" and not app.motion.seated_transition_state().get("active",false),3.0),sequence+" terminates finite transition without stale ownership")
	await wait_for(func(): return false,.2)
	check(not app.objects.has_presentation_transition() and not app._sit_attached,sequence+" clears displacement and seat attachment")
	recording = false

func run() -> void:
	if OS.get_name() != "Windows": print("AUTHORED_SEATING_NOT_RUN: actual Windows required"); quit(2); return
	output = arg("--output")
	character = arg("--character","cheval-grand")
	if output.is_empty() or character not in ["cheval-grand","rice-shower","eishin-flash"]:
		push_error("--output and a supported --character are required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	started = Time.get_ticks_msec()
	csv = FileAccess.open(output.path_join("timeline.csv"),FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["ms","sequence","stage","window_x","window_y","clip","clip_time","duration","root_progress","left_knee_deg","right_knee_deg","joints_world","joints_prop_local","joints_desktop_px","source_hips_normalized","seat_error_px","image"]))
	create_timer(float(LIMIT_MS)/1000).timeout.connect(func():
		if not closing: check(false,"180second watchdog"); finish())
	settings_node = root.get_node("Settings")
	original = settings_node.data.duplicate(true)
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":character,"pet_scale":.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,"view_projection":"perspective",
		"view_fov_deg":45.0,"view_distance_m":3.6,"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app); current_scene = app
	app.objects.command_finished.connect(func(id: String,outcome: String): report.commands.append({"record_type":"terminal","id":id,"outcome":outcome,"ms":elapsed()}))
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() and app._vrma_pending == 0,40.0),"production backend and avatar ready"):
		await finish(); return
	app._switch_character(character)
	var expected := BackendClient.avatar_cache_path(character).get_file()
	if not check(await wait_for(func(): return app.session.character_id == character and app.avatar.has_model() and app.avatar.model_path.get_file() == expected and not app.loading_label.visible,15.0),"explicit production rig loaded"):
		await finish(); return
	report["identity"] = {"character":character,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_video_adapter_name(),"transition_clips":app.motion.seated_transition.clips}
	report["scope"] = "Production direct validated furniture skills; authored temporal evidence, not LM routing. Own Windows viewport. Static support and numeric gates do not alone accept natural choreography."
	if not check(app.motion.seated_transition.clips.has("enter") and app.motion.seated_transition.clips.has("exit"),"production manifest registered authored enter and exit (no test injection)"):
		await finish(); return
	if not check(await corridor(),"normal policy floor corridor ready"):
		await finish(); return
	if await run_sequence("chair"):
		if await run_sequence("computer"):
			var abort := arg("--abort-case","none")
			if abort in ["cancel","support_loss"]: await run_abort(abort)
	await finish()

func finish() -> void:
	if closing: return
	closing = true; recording = false
	if csv != null: csv.flush(); csv = null
	var data := FileAccess.open(output.path_join("samples.json"),FileAccess.WRITE)
	if data != null: data.store_string(JSON.stringify(json_safe(samples)))
	report["sample_count"] = samples.size()
	if app != null:
		app.objects.cancel_commands("probe_cleanup")
		app.objects.cancel_interaction("probe_cleanup")
		app.objects.shutdown(); app.mic.cancel_recording(); app.audio.cancel()
		app.world_source.stop(); app.client.disconnect_ws(); app.queue_free()
		await process_frame; await process_frame
	if settings_node != null:
		settings_node.data = original.duplicate(true); settings_node.save_now()
		check(settings_node.data == original,"original settings restored")
	write_report()
	print("AUTHORED_SEATING_REPORT ",output.path_join("report.json")," failures=",report.get("failures",0))
	quit(0 if int(report.get("failures",0)) == 0 else 1)

# This source is a separate probe; previous authored traces remain untouched.
func run_sequence(type: String) -> bool:
	if type == "chair":
		sequence="scene_depth_path";recording=true
		var start:Vector3=app.avatar.contact_anchors().foot
		var target:=start+Vector3(.25,0,-.35)
		var obstacle:=AABB(start+Vector3(.085,0,-.215),Vector3(.08,.8,.08))
		report["controlled_route_obstacle"]=str(obstacle)
		var request:Dictionary=app.request_scene_approach(target,[obstacle])
		check(request.get("accepted",false),"production perspective scene path accepted")
		var maximum_yaw_error:=0.0;var distance:=0.0;var depth:=0.0
		var previous_yaw:float=app.avatar.rotation.y
		var previous_ms:=elapsed()
		var turning_travel_time:=0.0
		var turning_travel_angle:=0.0
		var collision_free:=true
		var previous:=start
		var deadline:=elapsed()+15000
		while app.scene_navigation.navigation.active and elapsed()<deadline:
			await process_frame
			await RenderingServer.frame_post_draw
			sample_frame()
			var foot:Vector3=app.avatar.contact_anchors().foot
			var step:=foot.distance_to(previous)
			var obstacle_xz:=Rect2(Vector2(obstacle.position.x,obstacle.position.z),Vector2(obstacle.size.x,obstacle.size.z)).grow(.12*app._pet_scale)
			if obstacle_xz.has_point(Vector2(foot.x,foot.z)):collision_free=false
			distance+=step;depth+=absf(foot.z-previous.z)
			if step>.00001:maximum_yaw_error=maxf(maximum_yaw_error,absf(angle_difference(app.avatar.rotation.y,app.scene_navigation.navigation._heading)))
			var dt:=float(elapsed()-previous_ms)/1000.0
			var yaw_delta:=absf(angle_difference(previous_yaw,app.avatar.rotation.y))
			if step>.00001 and dt>0 and dt<=.1 and yaw_delta>.0001:
				turning_travel_time+=dt;turning_travel_angle+=yaw_delta
			previous=foot;previous_yaw=app.avatar.rotation.y;previous_ms=elapsed()
			var row={"ms":elapsed(),"foot_world":foot,"step_m":step,"dt":dt,"yaw_delta":yaw_delta,"yaw":app.avatar.rotation.y,"navigation":app.scene_navigation.diagnostics}
			report.phases.append(row)
		check(depth>.3 and distance>.4,"real rendered avatar traverses scene Z and X")
		check(collision_free,"rendered foot stays outside obstacle expanded by actor radius")
		check(turning_travel_time>=.25 and turning_travel_angle>=deg_to_rad(10),"actual body yaw changes at least10degrees during cumulative concurrent travel")
		report["turning_overlap"]={"seconds":turning_travel_time,"angle_radians":turning_travel_angle,"max_heading_error":maximum_yaw_error}
		check(previous.distance_to(target)<.015,"rendered scene endpoint reached")
		app.cancel_scene_approach("probe_complete")
		var cancellation_start:Vector3=app.avatar.contact_anchors().foot
		var second:Dictionary=app.request_scene_approach(cancellation_start+Vector3(.3,0,-.1),[])
		check(second.get("accepted",false),"second production scene request accepted")
		await wait_for(func():return app.avatar.contact_anchors().foot.distance_to(cancellation_start)>.01,5.0)
		app._cancel_current()
		var stopped:Vector3=app.avatar.contact_anchors().foot
		await wait_for(func():return false,.3)
		check(not app.scene_navigation.navigation.active and not app.scene_navigation.has_completion_owner() and app.scene_navigation.ground_latched and app.avatar.contact_anchors().foot.distance_to(stopped)<.005,"actual user stop ends travel and retains virtual ground without drift")
		recording=false
		await wait_for(func():return false,.5)
		return await legacy_run_sequence(type)
	sequence="computer_collision";recording=true
	var command_id := "computer-solid-test"
	if not command({"kind":"furniture","object_type":"computer","verb":"use","placement":"near"},command_id):
		recording=false;return false
	var observed := await wait_for(func():return stage()=="using" or not terminal_event(report.commands,command_id).is_empty(),35.0)
	var terminal := terminal_event(report.commands,command_id)
	var outcome := str(terminal.get("outcome",""))
	report["computer_observation"]={"command_id":command_id,"observed":observed,"stage":stage(),"terminal":terminal,"fit_diagnostics":app.objects.fit_diagnostics}
	if observed and outcome in ["blocked_endpoint","unreachable","no_free_ground"]:
		check(true,"desk solid blocks physically inaccessible authored staging")
		report["computer_limitation"]="No successful use claimed: original backward entry staging intersects actual desk solids."
		app.objects.cancel_interaction("probe_complete");recording=false;return true
	var reached := observed and stage()=="using"
	check(reached,"computer either reaches valid contact or explicitly reports physical blockage")
	app.objects.cancel_interaction("probe_complete");recording=false
	return reached

static func terminal_event(events: Array, command_id: String) -> Dictionary:
	for event in events:
		if event is Dictionary and event.get("record_type","")=="terminal" and event.get("id","")==command_id and event.get("outcome") is String and not str(event.outcome).is_empty():
			return event
	return {}
