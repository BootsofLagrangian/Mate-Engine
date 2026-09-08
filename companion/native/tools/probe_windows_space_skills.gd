extends SceneTree
## Opt-in Windows integration: actual Korean chat -> model furniture intent ->
## Japanese-response PCM -> native physical work -> acknowledged execution result.
## Then exercise validated chair commands and the real separate settings UI.
## Captures only owned viewports. No cursor/key injection or policy flag bypass.
const LIMIT_MS := 120000
const CHAT := "컴퓨터를 꺼내서 써 봐. 먼저 짧게 대답해 줘."
var app
var settings_node
var original := {}
var output := ""
var started := 0
var closing := false
var turn := ""
var done := {}
var action := {}
var feedback := {}
var pcm_bytes := 0
var played := false
var max_envelope := 0.0
var first_playback_ms := -1
var first_using_ms := -1
var voice_overlap_using := false
var next_sample := 0
var area := Rect2i()
var report := {"checks":[],"events":[],"commands":[],"interactions":[],"contexts":[],"captures":[],"skill_calls":[]}

func _initialize() -> void:
	call_deferred("run")

func argument(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i] == key: return args[i+1]
	return ""

func elapsed() -> int:
	return Time.get_ticks_msec()-started

func write_report() -> void:
	if output.is_empty(): return
	report["elapsed_ms"] = elapsed()
	report["failures"] = report.checks.filter(func(row): return not row.ok).size()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  "))

func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok":ok,"label":label,"ms":elapsed()})
	print("SPACE_SKILLS ",label," ",ok)
	write_report()
	return ok

func snapshot() -> Dictionary:
	if app == null: return {}
	return {"ms":elapsed(),"window":str(root.position),"pointer":str(DisplayServer.mouse_get_position()),
		"state":app.autonomy.state,"blocked":app.autonomy._blocked,"pointer_interaction":app.autonomy._pointer_interaction,
		"panel_open":app.panel_open,"speaking":app.audio.voice_active,"foreground_busy":app.session.is_foreground_busy(),
		"support":app.autonomy.get_support_contact(),"interaction":app.objects._interaction.duplicate(true),
		"pending_command":app.objects._pending_command.duplicate(true),"status":app.objects.last_status}

func sample() -> void:
	if app == null: return
	max_envelope = maxf(max_envelope,app.audio.envelope)
	if app.objects._interaction.get("stage","") == "using":
		if first_using_ms < 0: first_using_ms = elapsed()
		voice_overlap_using = voice_overlap_using or bool(app.audio.voice_active)
	if elapsed() >= next_sample:
		next_sample = elapsed()+250
		report.contexts.append(snapshot())

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := mini(Time.get_ticks_msec()+int(seconds*1000),started+LIMIT_MS-250)
	while not closing and Time.get_ticks_msec() < deadline:
		sample()
		if predicate.call(): return true
		await process_frame
		await RenderingServer.frame_post_draw
	return false

func received(event: Dictionary) -> void:
	var record := event.duplicate(true)
	if record.has("pcm"):
		record["pcm_bytes"] = Marshalls.base64_to_raw(str(record.pcm)).size()
		record.erase("pcm")
	record["ms"] = elapsed()
	report.events.append(record)
	if event.get("type","") == "intent_result" and str(event.get("intent_id","")) == turn+":intent":
		feedback = record
	if str(event.get("turn_id","")) != turn: return
	match str(event.get("type","")):
		"action": action = record
		"done": done = record
		"audio": pcm_bytes += int(record.get("pcm_bytes",0))

func contains_japanese(text: String) -> bool:
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= 0x3040 and code <= 0x30ff: return true
	return false

func command_outcome(id: String, outcome: String = "") -> bool:
	return report.commands.any(func(row): return row.id == id and (outcome.is_empty() or row.outcome == outcome))

func command_rows(id: String) -> Array:
	return report.commands.filter(func(row): return row.id == id)

func shared_seated(id: String, stage: String = "seated") -> bool:
	return app.objects.contact_scene_active() and app.objects._interaction.get("id","") == id \
		and app.objects._interaction.get("stage","") == stage and app.is_sitting() and app._sit_attached

func seat_metrics(label: String) -> Dictionary:
	# Keep failure evidence valid JSON: Godot serializes INF as a non-JSON token.
	if not app.objects.contact_scene_active():
		return {"label":label,"active":false,"error_px":1.0e9,
			"reason":"contact_scene_inactive","fit_diagnostics":app.objects.fit_diagnostics.duplicate(true),
			"context":snapshot()}
	var socket: Vector2 = app.objects.contact_socket_screen("seat")
	var anchor: Vector2 = Vector2(root.position)+Vector2(app._projected_anchors().sit)
	return {"label":label,"active":true,"socket_px":str(socket),"anchor_px":str(anchor),
		"error_px":anchor.distance_to(socket),"support":app.autonomy.get_support_contact(),
		"view":app._view_settings.duplicate(true),"context":snapshot()}

func camera_state() -> Dictionary:
	return {"global_basis":str(app.camera.global_basis),"global_position":str(app.camera.global_position),
		"local_basis":str(app.camera.basis),"local_position":str(app.camera.position),
		"size":app.camera.size,"projection":app.camera.projection}

func shot(name: String, window: Window = null) -> void:
	if closing: return
	await RenderingServer.frame_post_draw
	var owned: Window = root if window == null else window
	var filename := name+".png"
	var error := owned.get_texture().get_image().save_png(output.path_join(filename))
	report.captures.append({"file":filename,"ms":elapsed(),"window_id":owned.get_window_id(),
		"position":str(owned.position),"shared_depth":owned == root and app.objects.contact_scene_active(),"save_error":error})
	check(error == OK,"capture owned viewport "+name)

func direct_skill(intent: Dictionary, id: String) -> bool:
	var result: Dictionary = app.living.request_intent(intent,"user",id)
	report.skill_calls.append({"id":id,"intent":intent.duplicate(true),"result":result,"ms":elapsed()})
	return check(bool(result.get("accepted",false)),"validated host skill accepted "+id)

func choose_floor_corridor() -> bool:
	app.objects.cancel_interaction("probe_setup")
	app.living.cancel("probe_setup")
	app._set_panel_open(false,false)
	if app.is_sitting(): app._stand_up("")
	var cursor := DisplayServer.mouse_get_position()
	# Furniture's 'near' default is +100px. Start in the opposite monitor half,
	# away from the stationary cursor, with room for that normal rightward approach.
	var fraction := 0.58 if cursor.x < area.position.x+area.size.x*.5 else 0.26
	var foot := Vector2(area.position.x+area.size.x*fraction,area.end.y)
	root.position = Vector2i(foot-Vector2(app._projected_anchors().foot))
	report["corridor"] = {"cursor":str(cursor),"workarea":str(area),"start_fraction":fraction,
		"rationale":"own window placed away from the cursor; normal hover/busy/contact policies remain active"}
	return await wait_for(func(): return app.autonomy.can_request_move() \
		and bool(app.autonomy.get_support_contact().get("attached",false)) \
		and str(app.autonomy.get_support_contact().get("kind","")) in ["floor","taskbar"],12.0)

func cool_materials_applied(window: Window) -> bool:
	var checked := 0
	for mesh in window._scene.find_children("*","MeshInstance3D",true,false):
		if not mesh.has_meta("object_original_materials"): continue
		var originals: Array = mesh.get_meta("object_original_materials")
		for i in mesh.mesh.get_surface_count():
			if not originals[i] is StandardMaterial3D: continue
			var material = mesh.get_surface_override_material(i)
			if not material is StandardMaterial3D: return false
			var expected: Color = originals[i].albedo_color*Color(.76,.89,1.0)
			var actual: Color = material.albedo_color
			if absf(actual.r-expected.r)>0.00001 or absf(actual.g-expected.g)>0.00001 or absf(actual.b-expected.b)>0.00001: return false
			checked += 1
	return checked > 0

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
	report["scope"] = "One real Korean chat; Japanese response text plus actual local PCM playback; strict furniture execution and backend acknowledgment; validated direct chair skills and shared camera contact. Own viewports only; no external input; no scripted model response or policy bypass."
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
	area = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if not check(await choose_floor_corridor(),"normal floor support and movement readiness"):
		await finish(); return
	var catalog: Array = app.objects.furniture_catalog()
	check(catalog.any(func(row): return row.id == "computer" and "use" in row.verbs),"live computer-use skill advertised")
	app.living.publish_world(true)
	app._send_chat(CHAT)
	turn = app.session.turn_id
	report["chat"] = {"text":CHAT,"turn_id":turn,"sent_ms":elapsed()}
	if not check(await wait_for(func(): return not done.is_empty() and not app.audio.is_voice_active() and app.audio.queue.pending_frames() == 0,38.0),"actual model response finishes and voice drains"):
		await finish(); return
	check(bool(done.get("ok",false)) and contains_japanese(str(done.get("text",""))),"successful response contains Japanese speech text")
	check(played and pcm_bytes>0 and max_envelope>.01,"streamed PCM actually played through native audio")
	report["voice"] = {"reply":done.get("text",""),"pcm_bytes":pcm_bytes,"native_playback_seen":played,"max_envelope":max_envelope,"first_playback_ms":first_playback_ms,"scope":"PCM playback and Japanese reply text, not independent audio transcription"}
	var intent: Variant = done.get("intent",{})
	if not check(intent is Dictionary and intent.get("kind","") == "furniture" and intent.get("object_type","") == "computer" and intent.get("verb","") == "use","real model requests computer use"):
		await finish(); return
	check(action.get("intent",{}) == intent,"streamed action and done carry identical intent")
	var lm_id := turn+":intent"
	if not check(await wait_for(func(): return app.objects._interaction.get("stage","") == "using" or command_outcome(lm_id),25.0) \
		and app.objects._interaction.get("stage","") == "using","model-issued skill reaches actual using stage"):
		await shot("lm-use-failed"); await finish(); return
	var computer_id := str(app.objects._interaction.id)
	check(app.objects.rows().size() == 1 and app.objects.store.get_object(computer_id).type == "computer","model skill spawns exactly one real computer")
	await wait_for(func(): return bool(app.objects._interaction.get("left_hand_reachable",false)) and bool(app.objects._interaction.get("right_hand_reachable",false)),1.0)
	await RenderingServer.frame_post_draw
	var hands := {}
	for side in ["left","right"]:
		var target: Vector3 = app.objects.contact_socket_world("keyboard_"+side)
		var wrist: Vector3 = app.avatar.bone_global_position(side+"Hand")
		var projected: Vector2 = Vector2(root.position)+app.camera.unproject_position(wrist)
		var socket: Vector2 = app.objects.contact_socket_screen("keyboard_"+side)
		var reached := bool(app.objects._interaction.get(side+"_hand_reachable",false))
		hands[side] = {"reachable":reached,"error_world_m":wrist.distance_to(target),"error_px":projected.distance_to(socket)}
		check(reached and wrist.distance_to(target)<.02 and projected.distance_to(socket)<3.0,"actual "+side+" wrist reaches physical keyboard")
	report["computer_hands"] = hands
	report["computer_seat"] = seat_metrics("lm-computer")
	check(shared_seated(computer_id,"using") and float(report.computer_seat.error_px)<1.0,"computer use seated in shared depth with subpixel seat contact")
	check(first_playback_ms >= 0 and first_using_ms>first_playback_ms and not voice_overlap_using,"spoken acknowledgement precedes physical use")
	await shot("lm-computer-using")
	if not check(await wait_for(func(): return command_outcome(lm_id),12.0),"model furniture command reaches terminal outcome"):
		await finish(); return
	var lm_outcomes := command_rows(lm_id)
	check(lm_outcomes.size() == 1 and lm_outcomes[0].outcome == "completed" and app.objects._interaction.is_empty(),"actual use completes once without cancellation or action/done duplicate")
	check(await wait_for(func(): return bool(feedback.get("accepted",false)),4.0),"live backend acknowledges native execution feedback")
	report["feedback_ack"] = feedback
	# Independent direct host validation. These IDs are deliberately not :intent
	# IDs, so direct test commands cannot masquerade as model-issued feedback.
	if not direct_skill({"kind":"furniture","object_type":"chair","verb":"place"},"probe:chair-place"):
		await finish(); return
	if not check(await wait_for(func(): return command_outcome("probe:chair-place"),8.0) and command_outcome("probe:chair-place","completed"),"chair place skill actually completes"):
		await finish(); return
	var chairs: Array = app.objects.rows().filter(func(row): return row.type == "chair")
	if not check(chairs.size() == 1 and app.objects.rows().size() == 2,"one chair plus one computer; below three-object bound"):
		await finish(); return
	var chair_id := str(chairs[0].id)
	var config := {"kind":"furniture","object_type":"chair","verb":"configure","target_id":"object:"+chair_id,"yaw_deg":45.0,"scale":.8,"appearance":"cool"}
	if not direct_skill(config,"probe:chair-configure"):
		await finish(); return
	if not check(await wait_for(func(): return command_outcome("probe:chair-configure"),6.0) and command_outcome("probe:chair-configure","completed"),"targeted chair configure skill completes"):
		await finish(); return
	var configured: Dictionary = app.objects.store.get_object(chair_id)
	report["configured_chair"] = configured.duplicate(true)
	check(absf(float(configured.get("yaw_deg",0))-45.0)<.001 and absf(float(configured.get("scale",0))-.8)<.0001 and configured.get("appearance","") == "cool","chair stores exact yaw45 scale0.8 cool configuration")
	check(cool_materials_applied(app.objects.windows[chair_id]),"cool appearance applied to actual chair material instances")
	if not direct_skill({"kind":"furniture","object_type":"chair","verb":"sit","target_id":"object:"+chair_id},"probe:chair-sit"):
		await finish(); return
	if not check(await wait_for(func(): return shared_seated(chair_id) or command_outcome("probe:chair-sit"),20.0) and shared_seated(chair_id),"validated sit uses existing configured chair"):
		await shot("chair-sit-failed"); await finish(); return
	check(command_outcome("probe:chair-sit","arrived") and app.objects.rows().size() == 2,"seat arrival reported without duplicate furniture")
	var before := seat_metrics("before-view")
	var camera_before: Transform3D = app.camera.transform
	var camera_size_before: float = app.camera.size
	report["camera_before"] = camera_state()
	report["chair_before_view"] = before
	check(float(before.error_px)<1.0,"chair contact begins within one pixel")
	app._set_panel_open(true,false)
	var panel_visible := await wait_for(func(): return app.panel_window.visible,1.0)
	check(panel_visible and app.panel_window.visible and app.panel.get_viewport() != root and not app.panel_window.is_embedded(),"settings actually visible in separate native viewport")
	check(not Rect2i(app.panel_window.position,app.panel_window.size).intersects(app._global_pet_rect()),"settings window does not cover rendered seated pet")
	app.panel._view_pitch.value = 45.0
	app.panel._view_yaw.value = 45.0
	await wait_for(func(): return float(app._view_settings.get("view_pitch_deg",0)) == 45.0 and float(app._view_settings.get("view_yaw_deg",0)) == 45.0,1.0)
	await RenderingServer.frame_post_draw
	var after := seat_metrics("pitch45-yaw45")
	report["chair_after_view"] = after
	report["camera_after"] = camera_state()
	var expected_basis := DesktopView.orbit_basis(45.0,45.0,0.0)
	var expected_position: Vector3 = expected_basis*(camera_before.basis.inverse()*camera_before.origin)
	check(app.camera.basis.is_equal_approx(expected_basis) and not app.camera.basis.is_equal_approx(camera_before.basis),"actual Camera3D rotates to requested 45-degree yaw and pitch")
	check(app.camera.position.distance_to(expected_position)<0.00001 and absf(app.camera.size-camera_size_before)<0.00001,"actual camera orbit position and unchanged zoom match requested view")
	check(shared_seated(chair_id) and float(after.error_px)<1.0,"45-degree pitch and yaw preserve shared chair seat within one pixel")
	check(str(after.get("support",{}).get("surface_id","")) == "object:"+chair_id+":seat","view controls preserve occupied support identity")
	check(float(settings_node.get_value("view_pitch_deg",0)) == 45.0 and float(settings_node.get_value("view_yaw_deg",0)) == 45.0,"real UI controls update persisted camera settings")
	await shot("chair-view45-shared")
	await shot("separate-settings-view45",app.panel_window)
	app.panel.reset_view_settings()
	await process_frame
	await RenderingServer.frame_post_draw
	var reset := seat_metrics("reset-view")
	report["chair_reset_view"] = reset
	report["camera_reset"] = camera_state()
	check(app.camera.transform.is_equal_approx(camera_before) and absf(app.camera.size-camera_size_before)<0.00001,"reset restores actual camera transform and size")
	check(shared_seated(chair_id) and float(reset.error_px)<1.0,"reset view retains actual chair contact")
	check(app._view_settings == {"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0},"view reset restores all four defaults")
	app.panel_window.close_panel()
	check(not app.panel_open and shared_seated(chair_id),"closing settings preserves seated companion")
	await finish()

func finish() -> void:
	if closing: return
	closing = true
	if app != null:
		report["fit_diagnostics"]=app.objects.fit_diagnostics.duplicate(true)
		report["object_records"]=app.objects.store.data()
		for key in ["planning_input","restoration_input"]:
			if report.fit_diagnostics.has(key):
				var fixture:=FileAccess.open(output.path_join(key.replace("_","-")+".bin"),FileAccess.WRITE)
				if fixture!=null:fixture.store_var(report.fit_diagnostics[key]);fixture.close()
		report["final_object_count"] = app.objects.rows().size()
		check(app.objects.rows().size() <= 3,"total object bound respected")
		app.objects.cancel_commands("probe_cleanup")
		app.objects.cancel_interaction("probe_cleanup")
		app._set_panel_open(false,false)
		app.objects.shutdown()
		app.mic.cancel_recording()
		app.audio.cancel()
		app.world_source.stop()
		app.client.disconnect_ws()
		app.queue_free()
		await process_frame
		await process_frame
	if settings_node != null:
		settings_node.data = original.duplicate(true)
		settings_node.save_now()
		check(settings_node.data == original,"original settings restored after test")
	write_report()
	print("SPACE_SKILLS_REPORT ",output.path_join("report.json")," failures=",report.get("failures",0))
	quit(0 if int(report.get("failures",0)) == 0 else 1)
