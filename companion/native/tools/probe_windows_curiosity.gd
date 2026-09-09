extends "probe_windows_space_skills.gd"
## Passive native trajectory measurement. Only initial owned-window placement;
## production autonomy selects every subsequent target. No cursor or OS input.
var mode := "curiosity"
var duration_seconds := 180.0
var capture_active := false
var trajectory: Array = []
var capture_started_us := 0
var previous_frame_us := 0
var next_capture_us := 0
var previous_sample_us := 0
var previous_xy := Vector2.INF
var initial_xy := Vector2.INF
var path_px := 0.0
var max_displacement_px := 0.0
var finite_trajectory := true
var frame_count := 0
var max_frame_ms := 0.0
var nonzero_fly_output := false
var navigation_events:Array=[]
var pointer_transitions:Array=[]
var previous_pointer_active:=false

func write_report() -> void:
	# Avoid WSL filesystem stalls in the measured trajectory. Console checks
	# remain live, and parent finish preserves every failed check in final JSON.
	if closing: super.write_report()

func sample() -> void:
	if not capture_active or app == null: return
	var now := Time.get_ticks_usec()
	var frame_ms := float(now-previous_frame_us)/1000.0 if previous_frame_us>0 else 0.0
	previous_frame_us=now;frame_count+=1;max_frame_ms=maxf(max_frame_ms,frame_ms)
	var world:Vector3=app.avatar.contact_anchors().foot
	var xy:Vector2=Vector2(root.position)+app.camera.unproject_position(world)
	var valid:=world.is_finite() and xy.is_finite() and is_finite(app.avatar.rotation.y)
	finite_trajectory=finite_trajectory and valid
	if valid:
		if not initial_xy.is_finite():initial_xy=xy
		if previous_xy.is_finite():path_px+=previous_xy.distance_to(xy)
		previous_xy=xy
		max_displacement_px=maxf(max_displacement_px,initial_xy.distance_to(xy))
	if bool(app.autonomy._pointer_interaction)!=previous_pointer_active:
		previous_pointer_active=app.autonomy._pointer_interaction
		pointer_transitions.append({"t_s":float(now-capture_started_us)/1000000.0,"active":previous_pointer_active})
	if now<next_capture_us:return
	next_capture_us=now+100000
	var director=app.living.director
	var nav=app.scene_navigation
	var drive:Dictionary=director.curiosity_drive
	nonzero_fly_output=nonzero_fly_output or absf(float(drive.get("forward",0.0)))>0.000001 or absf(float(drive.get("turn",0.0)))>0.000001
	trajectory.append({"ms":elapsed(),"t_ms":float(now-capture_started_us)/1000.0,"t_s":float(now-capture_started_us)/1000000.0,
		"sample_dt_ms":float(now-previous_sample_us)/1000.0 if previous_sample_us>0 else 0.0,
		"frame_dt_ms":frame_ms,"engine_frame":Engine.get_process_frames(),
		"foot_xy":[xy.x,xy.y] if xy.is_finite() else null,
		"foot_world":[world.x,world.y,world.z] if world.is_finite() else null,
		"yaw_rad":app.avatar.rotation.y if is_finite(app.avatar.rotation.y) else null,
		"window_origin":[root.position.x,root.position.y],
		"navigation_state":app.autonomy.state,"foot_owner":"scene_navigation" if nav.owns_foot() else "desktop_autonomy",
		"movement_owner":"scene_navigation" if nav.owns_foot() else "desktop_autonomy","movement_stage":director.state,
		"scene_navigation_active":nav.navigation.active,"scene_holding":nav.holding,
		"director_active_id":str(director._active.get("id","")),
		"director_active_kind":str(director._active.get("kind","")),
		"director_target_id":str(director._active.get("target_id","")),
		"curiosity_decision_count":director.curiosity_decisions.size(),
		"fly_forward":float(drive.get("forward",0.0)),"fly_turn":float(drive.get("turn",0.0)),
		"blocked":app.autonomy._blocked,"pointer_interaction":app.autonomy._pointer_interaction,
		"contact_pose":app.motion.current_contact_pose(),"gesture":app.motion.current_gesture(),
		"support_attached":app.autonomy.get_support_contact().get("attached",false)})
	previous_sample_us=now

func run() -> void:
	if OS.get_name()!="Windows":quit(2);return
	output=argument("--output")
	if output.is_empty():push_error("--output is required");quit(2);return
	if not argument("--mode").is_empty():mode=argument("--mode")
	if mode not in ["baseline","curiosity","fly"]:push_error("invalid --mode");quit(2);return
	if not argument("--duration").is_empty():duration_seconds=clampf(float(argument("--duration")),1.0,3600.0)
	DirAccess.make_dir_recursive_absolute(output)
	started=Time.get_ticks_msec()
	create_timer(duration_seconds+90.0).timeout.connect(func():
		if not closing:check(false,"curiosity duration plus setup watchdog exceeded");finish())
	settings_node=root.get_node("Settings");original=settings_node.data.duplicate(true)
	var fixture:={"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":0.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,
		"curiosity_enabled":mode!="baseline","fly_curiosity_enabled":mode=="fly",
		"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}}
	settings_node.data.merge(fixture,true)
	report["variant"]=argument("--label") if not argument("--label").is_empty() else mode
	report["mode"]=mode;report["requested_duration_s"]=duration_seconds;report["fixture_settings"]=fixture
	report["scope"]="Passive native trajectory: initial normal supported placement only; every move selected by production policy. Actual global projected foot, world foot and OS window origin; no injected targets or OS input."
	report["forced_target_injections"]=0
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not check(await wait_for(func():return app.avatar.has_model() and app.world_source.available and app._vrma_pending==0,40),"actual VRM and native desktop geometry ready"):
		await finish();return
	area=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if not check(await choose_floor_corridor(),"initial normal floor or taskbar support ready"):
		await finish();return
	report["identity"]={"character":app.session.character_id,"model_path":app.avatar.model_path,
		"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_video_adapter_name()}
	check(app.objects.rows().is_empty(),"no furniture fixture")
	check(app.living.director.curiosity_enabled==(mode!="baseline"),"requested production curiosity mode applied")
	check(app.living.director.fly_enabled==(mode=="fly"),"requested production fly drive mode applied")
	if mode=="fly" and not check(app.living.director.fly_circuit.ready,"installed fly circuit is ready"):
		await finish();return
	app.autonomy.navigation_finished.connect(func(id:String,outcome:String):
		if capture_active:navigation_events.append({"t_s":float(Time.get_ticks_usec()-capture_started_us)/1000000.0,"id":id,"outcome":outcome,"pointer_active":app.autonomy._pointer_interaction,"pointer":str(DisplayServer.mouse_get_position())}))
	report["initial_support"]=app.autonomy.get_support_contact().duplicate(true)
	await shot("curiosity-start")
	capture_started_us=Time.get_ticks_usec();capture_active=true
	var deadline:=capture_started_us+int(duration_seconds*1000000.0)
	var next_progress:=capture_started_us+30000000
	# This capture has its own deadline; parent wait_for's 120-second setup cap
	# must not silently shorten 180-second or longer experiments.
	while not closing and Time.get_ticks_usec()<deadline:
		await process_frame
		await RenderingServer.frame_post_draw
		sample()
		if Time.get_ticks_usec()>=next_progress:
			print("CURIOSITY_PROGRESS ",mode," seconds=",int((Time.get_ticks_usec()-capture_started_us)/1000000)," samples=",trajectory.size())
			next_progress+=30000000
	if closing:return
	capture_active=false
	report["capture_duration_s"]=float(Time.get_ticks_usec()-capture_started_us)/1000000.0
	report["trajectory"]=trajectory
	report["navigation_events"]=navigation_events
	report["pointer_transitions"]=pointer_transitions
	report["motion_metrics"]={"frame_count":frame_count,"sample_count":trajectory.size(),"path_px":path_px,
		"max_displacement_px":max_displacement_px,"max_frame_ms":max_frame_ms}
	report["director_final"]={"active":app.living.director._active.duplicate(true),
		"curiosity_enabled":app.living.director.curiosity_enabled,
		"fly_enabled":app.living.director.fly_enabled,
		"fly_diagnostics":app.living.director.fly_circuit.diagnostics.duplicate(true),
		"fly_provenance":app.living.director.fly_circuit.provenance.duplicate(true),
		"decisions":app.living.director.curiosity_decisions.slice(-64).duplicate(true)}
	check(finite_trajectory and trajectory.size()>1,"finite actual native trajectory recorded")
	check(max_displacement_px>20.0 and trajectory.any(func(row): return row.director_active_kind=="move_to"),"autonomous move intent produces more than 20 pixels displacement")
	check(report.forced_target_injections==0,"no target injected during passive capture")
	if mode=="fly":check(nonzero_fly_output,"native fly circuit produced nonzero drive output")
	var chatter:=false
	for event in navigation_events:
		if event.outcome!="interrupted" or not event.pointer_active:continue
		var repeated:=navigation_events.filter(func(row):return row.id==event.id and row.outcome=="interrupted" and row.pointer_active and row.pointer==event.pointer and absf(float(row.t_s)-float(event.t_s))<30.0)
		if repeated.size()>=3:chatter=true
	check(not chatter,"stationary pointer does not cause repeated local navigation interruptions")
	await shot("curiosity-final")
	await finish()

func finish() -> void:
	if closing:return
	capture_active=false
	# Preserve partial trajectories on setup/runtime/watchdog failure too.
	if not trajectory.is_empty():report["trajectory"]=trajectory
	await super.finish()
