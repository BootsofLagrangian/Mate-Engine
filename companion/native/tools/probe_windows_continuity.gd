extends "probe_windows_space_skills.gd"
# Full per-frame JSON over the WSL filesystem can stall rendering for seconds.
# Keep samples in memory during the scenario; console checks remain live.
func write_report() -> void:
	if closing: super.write_report()

var frames: Array = []
var last_frame := -1
func sample() -> void:
	super.sample()
	if app == null or Engine.get_process_frames() == last_frame: return
	last_frame = Engine.get_process_frames()
	var nav = app.scene_navigation
	frames.append({"ms":elapsed(),"stage":app.objects._interaction.get("stage",""),"command":app.objects._interaction.get("command_id",""),"voice":app.audio.voice_active,"job":app.session.job.get("status",""),"yaw":app.avatar.rotation.y,"travel_m":Vector3(nav.diagnostics.get("committed_world_delta",Vector3.ZERO)).length() if nav.navigation.active else 0.0,"gesture":app.motion.current_gesture(),"arrival_pivot":nav._arrival_pending,"chair_kind":app.objects.fit_diagnostics.get("chair_phase",{}).get("kind",""),"hand_weight":app.objects._interaction.get("work_contact_weight",-1.0)})
	report["frames"] = frames
func run() -> void:
	if OS.get_name() != "Windows":
		print("SPACE_SKILLS_NOT_RUN: actual Windows display and live backend required")
		quit(2)
		return
	output = argument("--output")
	if output.is_empty(): push_error("--output is required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	started = Time.get_ticks_msec()
	create_timer(float(LIMIT_MS)/1000.0).timeout.connect(func():
		if not closing:
			check(false,"120-second total watchdog exceeded")
			finish())
	settings_node = root.get_node("Settings")
	original = settings_node.data.duplicate(true)
	var fixture := {"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":0.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,
		"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}}
	settings_node.data.merge(fixture,true)
	report["fixture_settings"] = fixture
	report["scope"] = "Accepted computer use across real foreground chat, then real Codex task and announcements through use/exit. Direct validated skill fixture; no fabricated LM or job events."
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	app.client.event_received.connect(received)
	app.audio.playback_changed.connect(func(id: String, active: bool):
		report.events.append({"type":"native_playback","turn_id":id,"active":active,"ms":elapsed()})
		if id == turn and active:
			played = true
			if first_playback_ms < 0: first_playback_ms = elapsed())
	app.objects.command_finished.connect(func(id: String,outcome: String):
		report.commands.append({"id":id,"outcome":outcome,"ms":elapsed(),"context":snapshot()})
		write_report())
	app.objects.interaction_finished.connect(func(id: String,verb: String,outcome: String):
		report.interactions.append({"id":id,"verb":verb,"outcome":outcome,"ms":elapsed()}))
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() \
		and app.motion.vrma_clips.has("sit_idle") and app.motion.vrma_clips.has("walk") and app._vrma_pending == 0,35.0),"real backend hello avatar and motion catalogue ready"):
		await finish(); return
	if not check(str(app.session.capabilities.get("provider","")) not in ["", "stub"],"backend declares a non-stub provider"):
		await finish(); return
	app._switch_character("cheval-grand")
	var expected := BackendClient.avatar_cache_path("cheval-grand").get_file()
	if not check(await wait_for(func(): return app.session.character_id == "cheval-grand" and app.avatar.has_model() \
		and app.avatar.model_path.get_file() == expected and not app.loading_label.visible,15.0),"explicit Cheval session and actual rig match"):
		await finish(); return
	report["identity"] = {"character":app.session.character_id,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_video_adapter_name(),"capabilities":app.session.capabilities}
	check(app.objects.rows().is_empty(),"starts with zero furniture objects")
	if not check(app.objects.native_available(),"actual native furniture windows supported"):
		await finish(); return
	var expected_walk := argument("--expect-walk")
	if not expected_walk.is_empty():
		check(AutonomyBridge.pick_walk_clip(app._vrma_loaded)==expected_walk,"requested replacement is the loaded default walk")
		check(not Dictionary(app.motion.locomotion_styles.get(expected_walk,{})).is_empty(),"replacement uses authored contacts instead of procedural legs")
	area = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if not check(await choose_floor_corridor(),"normal floor support and movement readiness"):
		await finish(); return

	if not direct_skill({"kind":"furniture","object_type":"computer","verb":"use"},"continuity:computer"):
		await finish(); return
	if not check(await wait_for(func(): return app.objects._interaction.get("stage","") in ["scene_approaching","approaching"],20.0),"authored computer sequence starts"):
		await finish(); return
	var owner: String = app.objects._interaction.get("command_id","")
	app._set_panel_open(true,false)
	app._send_chat("동작은 그대로 이어가면서 일본어로 짧게 인사만 해줘.")
	turn = app.session.turn_id
	check(app.objects._interaction.get("command_id","") == owner,"new chat preserves admitted body owner synchronously")
	if not check(await wait_for(func(): return app.objects._interaction.get("stage","") == "using",40.0),"computer approach and entry complete across conversation"):
		await finish(); return
	if check(await wait_for(func():return float(app.objects._interaction.get("work_contact_weight",-1))>.15 and float(app.objects._interaction.get("work_contact_weight",1))<.85,1.0),"partial hand contact available"):
		var object_window=app.objects.windows[app.objects._interaction.id]
		app.objects._apply_work_contact(object_window)
		var pose:Dictionary={}
		for side in ["left","right"]:
			for suffix in ["UpperArm","LowerArm","Hand"]:
				var index:int=app.avatar.bone_index[side+suffix]
				pose[index]=app.avatar.skeleton.get_bone_pose_rotation(index)
		app.objects._apply_work_contact(object_window)
		check(pose.keys().all(func(index):return Quaternion(pose[index]).is_equal_approx(app.avatar.skeleton.get_bone_pose_rotation(index))),"repeated same-frame hand contact is idempotent")
	check(await wait_for(func(): return not done.is_empty() and played and not app.audio.voice_active,25.0),"real local LM reply and dedicated voice finish")
	check(app.objects._interaction.get("command_id","") == owner,"reply leaves computer ownership intact")
	await shot("conversation-seated")
	await verify_owned_furniture_region()
	app._start_job("현재 작업 폴더의 파일 목록을 도구로 한 번 확인하고 한 문장으로 요약하세요. 파일을 수정하지 마세요.")
	check(await wait_for(func(): return not app.session.job.is_empty(),10.0),"real background task accepted")
	check(await wait_for(func(): return str(app.session.job.get("status","")) in app.session.JOB_TERMINAL,40.0),"real task reaches terminal state")
	check(app.session.job.get("status","") == "completed","task completed successfully")
	var result_turn := "job:%s:result" % str(app.session.job.get("job_id",""))
	check(await wait_for(func():return report.events.any(func(row):return row.get("type","")=="native_playback" and row.get("turn_id","")==result_turn and row.get("active",false)),20.0),"owned result voice starts")
	check(await wait_for(func():return report.events.any(func(row):return row.get("type","")=="done" and row.get("turn_id","")==result_turn) and not app.audio.voice_active and app.audio.queue.pending_frames()==0,20.0),"owned result voice finishes")
	check(await wait_for(func():return command_outcome(owner),25.0) and command_outcome(owner,"completed"),"computer use and authored exit finish normally across task announcements")
	check(report.commands.filter(func(row):return row.id==owner).size()==1 and command_outcome(owner,"completed"),"body action completes exactly once without cancellation")
	check(frames.any(func(row):return row.hand_weight>0.05 and row.hand_weight<0.95),"work hands acquire contact progressively")
	check(frames.any(func(row):return row.chair_kind=="settle_in"),"occupied chair swivels and rolls along one admitted path")
	if not expected_walk.is_empty():check(frames.any(func(row):return row.gesture==expected_walk and row.travel_m>0.00001),"replacement drives committed desktop movement")
	check(frames.any(func(row):return row.voice and row.travel_m>0.00001),"actual world travel overlaps voice playback")
	check(frames.any(func(row):return row.job in ["starting","running"] and not str(row.stage).is_empty()),"actual body action overlaps background task")
	app._cancel_current()
	check(not app.body_action_can_continue(),"explicit stop leaves no body owner")
	await finish()

func verify_owned_furniture_region() -> void:
	var tools_path: String = get_script().resource_path.get_base_dir()
	var helper = load(tools_path.path_join("probe_owned_window_region.gd"))
	var evidence: Dictionary = await helper.verify(app,output,tools_path.path_join("probe_owned_window_region.ps1"))
	report["owned_furniture_region"] = evidence
	check(bool(evidence.get("ok",false)),"owned Windows region preserves furniture outside character bounds")
