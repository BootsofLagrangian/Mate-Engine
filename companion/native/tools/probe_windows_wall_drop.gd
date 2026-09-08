extends "probe_windows_space_skills.gd"
## Actual external owned HWND -> native geometry worker -> normal drop hook -> IK.
var fixture_pid := -1
var sequence := 0
var fixture_record := {}
var contact_frames: Array = []

func write_report() -> void:
	if closing: super.write_report()

func sample() -> void:
	super.sample()
	if app == null or app.living._drop_contact.is_empty(): return
	contact_frames.append({"ms":elapsed(),"contact":app.motion.current_contact_pose(),
		"reachable":app.motion.contact_reachable,"diagnostics":app.living.drop_diagnostics.duplicate(true),
		"foot":str(app.avatar.contact_anchors().foot)})

func observed_fixture() -> Dictionary:
	if app==null: return {}
	for item: Dictionary in app.world_source.snapshot.get("windows",[]):
		if str(item.id).begins_with(str(fixture_pid)+":"): return item
	return {}

func release_owned_drag() -> Dictionary:
	# Deliver events only to this app's handlers. The actual desktop cursor is
	# neither moved nor clicked; the owned window displacement models dragging.
	var before:Dictionary=app.autonomy.get_support_contact().duplicate(true)
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=app.pet_rect.get_center()
	app._unhandled_input(press)
	var detached:bool=not app.autonomy.get_support_contact().get("attached",false)
	await process_frame
	root.position+=Vector2i(2,0)
	app._drag_moved=true
	var release:=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=app.pet_rect.get_center()
	app._input(release)
	var initial:Dictionary=app.living._drop_contact.duplicate(true)
	var initial_diagnostics:Dictionary=app.living.drop_diagnostics.duplicate(true)
	# A real release starts detached. Observe ordinary surface reacquisition and
	# the arm blend rather than requiring synchronous support to be fabricated.
	if initial.get("kind","")=="window_wall" and not initial.get("active",false):
		await wait_for(func():return app.living._drop_contact.is_empty() or app.living._drop_contact.get("active",false) or app.living._drop_contact.get("kind","")!="window_wall",8.0)
	return {"support_before":before,"press_detached_support":detached,"release_cleared_drag":not app._drag_active,
		"initial_match":initial,"initial_diagnostics":initial_diagnostics,"final_match":app.living._drop_contact.duplicate(true)}

func place_fixture(x: int, y: int) -> bool:
	sequence+=1
	# A normal window stops above the actual taskbar. Covering it with a topmost
	# fixture would correctly invalidate the support we intend to test.
	var height:=clampi(area.end.y-4-y,80,420)
	var file:=FileAccess.open(output.path_join("wall-control.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"sequence":sequence,"x":x,"y":y,"width":360,"height":height}));file.close()
	if not await wait_for(func():
		var ready_path:=output.path_join("wall-ready.json")
		if not FileAccess.file_exists(ready_path):return false
		var ready:Variant=JSON.parse_string(FileAccess.get_file_as_string(ready_path))
		return ready is Dictionary and int(ready.get("sequence",-1))==sequence and int(ready.get("process_id",-1))==fixture_pid,4.0):return false
	# Require a native publication after the fixture acknowledges its move.
	# The prior position may be within the DWM border tolerance of the next one.
	var before:int=app.world_source.snapshot.get("timestamp_msec",0)
	return await wait_for(func():
		var record:=observed_fixture()
		# DWM omits classic invisible borders, so compare with a small margin.
		return app.world_source.snapshot.get("timestamp_msec",0)>before and not record.is_empty() and absf(float(record.x)-x)<=12 and absf(float(record.y)-y)<=12,4.0)

func run() -> void:
	if OS.get_name()!="Windows":quit(2);return
	output=argument("--output")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	started=Time.get_ticks_msec()
	create_timer(110).timeout.connect(func():
		if not closing:check(false,"wall test watchdog");finish())
	settings_node=root.get_node("Settings");original=settings_node.data.duplicate(true)
	var fixture:={"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":0.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,"scene_exploration_enabled":false,
		"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}}
	settings_node.data.merge(fixture,true);report["fixture_settings"]=fixture
	report["scope"]="Real owned external WinForms window observed by normal Windows geometry source; owned app press/release handlers, real support detach/reacquisition, hand reach, source movement invalidation. Only owned window moved; no fabricated snapshot, OS input or cursor movement."
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not check(await wait_for(func():return app.avatar.has_model() and app.world_source.available and app._vrma_pending==0,35),"real avatar and Windows geometry ready"):
		await finish();return
	area=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	# Reuse the real floor/taskbar placement fixture, including pointer avoidance
	# and normal support attachment. The drop hook owns subsequent lean admission.
	if not check(await choose_floor_corridor(),"normal observed floor or taskbar support ready"):
		await finish();return
	report["initial_support"]=app.autonomy.get_support_contact().duplicate(true)
	var helper:String=get_script().resource_path.get_base_dir().path_join("probe_owned_wall.ps1")
	fixture_pid=OS.create_process("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",helper,"-ControlPath",output.path_join("wall-control.json"),"-ReadyPath",output.path_join("wall-ready.json")]))
	if not check(fixture_pid>0,"separate owned wall fixture process started"):
		await finish();return
	var attempts:Array=[]
	var matched:Dictionary={}
	for offset in [36,48,24,60,72,18,84]:
		var foot:Vector2=Vector2(root.position)+app.camera.unproject_position(app.avatar.contact_anchors().foot)
		var actor:Rect2=Rect2(Vector2(root.position)+app.pet_rect.position,app.pet_rect.size)
		if not await place_fixture(roundi(foot.x+offset),roundi(actor.position.y-70)):continue
		fixture_record=observed_fixture()
		var drag:Dictionary=await release_owned_drag()
		matched=drag.final_match
		attempts.append({"offset":offset,"source":fixture_record.duplicate(true),"drag":drag,"match":matched.duplicate(true),"diagnostics":app.living.drop_diagnostics.duplicate(true),"context":snapshot(),"ground_fit":app.normalize_scene_ground_placement(app.avatar.contact_anchors().foot)})
		if matched.get("active",false):break
	report["attempts"]=attempts
	if not check(matched.get("active",false) and str(matched.get("source_id","")).begins_with("window:"+str(fixture_pid)+":"),"actual owned window edge starts lean through press and release handlers"):
		await finish();return
	check(attempts[-1].drag.press_detached_support and attempts[-1].drag.release_cleared_drag,"real drag detaches support then releases input ownership")
	var initial_foot:Vector3=app.avatar.contact_anchors().foot
	check(await wait_for(func():return app.motion.current_contact_pose()=="lean" and app.motion.contact_reachable,2.5),"actual arm IK reaches wall")
	await wait_for(func():return elapsed()>int(report.checks[-1].ms)+1200,1.8)
	check(not app.living._drop_contact.is_empty() and app.avatar.contact_anchors().foot.distance_to(initial_foot)<0.002,"lean holds ground foot within 2mm")
	report["torso_lean"]=app.motion.wall_lean.diagnostics.duplicate(true)
	check(float(report.torso_lean.get("amplitude",0))>0 and float(report.torso_lean.get("clearance_m",-1))>=0,"torso leans toward wall within rig capsule clearance")
	await shot("wall-lean")
	var previous_stamp:int=app.world_source.snapshot.get("timestamp_msec",0)
	await place_fixture(int(fixture_record.x)+160,int(fixture_record.y))
	check(await wait_for(func():return app.world_source.snapshot.get("timestamp_msec",0)>previous_stamp and app.living._drop_contact.is_empty(),4),"actual source window movement invalidates lean")
	check(app.living.drop_diagnostics.get("last_outcome","")=="surface_changed","release reports changed source geometry")
	check(await wait_for(func():return app.motion.current_contact_pose()!="lean",2),"contact pose releases after source moves")
	report["contact_frames"]=contact_frames
	await finish()

func finish() -> void:
	if closing:return
	if fixture_pid>0:
		var file:=FileAccess.open(output.path_join("wall-control.json"),FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"sequence":sequence+1,"close":true}));file.close()
		var deadline:=Time.get_ticks_msec()+1500
		while OS.is_process_running(fixture_pid) and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
		if OS.is_process_running(fixture_pid):OS.kill(fixture_pid)
		check(not OS.is_process_running(fixture_pid),"owned fixture process cleaned up")
		fixture_pid=-1
	await super.finish()
