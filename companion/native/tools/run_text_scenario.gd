extends "probe_windows_space_skills.gd"
## Generic real-native text scenario. The model chooses every intent.
## No fabricated capabilities, direct skill calls, microphone capture or OS input.
var scenario: Dictionary = {}
var requested_character := ""
var active_trial: Dictionary = {}
var terminal_rows: Array = []
var playback_intervals: Array = []
var playback_started := -1
var avatar_seen := 0
var scenario_limit := 600000

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := mini(Time.get_ticks_msec()+int(seconds*1000),started+scenario_limit-250)
	while not closing and Time.get_ticks_msec()<deadline:
		sample()
		if predicate.call(): return true
		await process_frame
		await RenderingServer.frame_post_draw
	return false

func sample() -> void:
	super.sample()
	if app == null: return
	while avatar_seen < app.avatar_variant_outcomes.size():
		var row: Dictionary = app.avatar_variant_outcomes[avatar_seen].duplicate(true)
		avatar_seen += 1
		record_terminal(str(row.id),str(row.outcome),str(row.get("reason","")),"avatar")
	if active_trial.is_empty(): return
	var id := turn+":intent"
	var native_active: bool = str(app._avatar_variant_command.get("id","")) == id \
		or str(app.objects._pending_command.get("id","")) == id \
		or str(app.objects._interaction.get("command_id","")) == id \
		or str(app.living.director._active.get("id","")) == id
	if native_active and not active_trial.has("native_active_ms"):
		active_trial["native_active_ms"] = elapsed()
	if native_active and app.audio.is_voice_active():
		active_trial["simultaneous_native_active_playback_samples"] += 1
		var interaction: Dictionary = app.objects._interaction
		var active_move: Dictionary = app.living.director._active
		var direct_owner: bool = str(active_move.get("id","")) == id and str(active_move.get("kind","")) == "move_to"
		var furniture_owner: bool = str(interaction.get("command_id","")) == id
		var scene_owner: bool = direct_owner or (furniture_owner and str(interaction.get("stage","")) == "scene_approaching")
		var legacy_owner: bool = direct_owner or (furniture_owner and str(interaction.get("stage","")) == "approaching" and str(active_move.get("id","")) == str(interaction.get("request_id","")))
		var scene_delta: Vector3 = app.scene_navigation.diagnostics.get("committed_world_delta",Vector3.ZERO)
		var moving_scene: bool = scene_owner and app.scene_navigation.navigation.active and scene_delta.length() > 0.00001
		var moving_legacy: bool = legacy_owner and app.autonomy.state == "walk" and absf(app.autonomy.velocity.x) > 1.0
		var frame_id := Engine.get_process_frames()
		if (moving_scene or moving_legacy) and int(active_trial.get("last_travel_sample_frame",-1)) != frame_id:
			active_trial["simultaneous_travel_playback_samples"] += 1
			active_trial["last_travel_sample_frame"] = frame_id

func record_terminal(id: String, outcome: String, reason: String, owner: String) -> void:
	var row := {"id":id,"outcome":outcome,"reason":reason,"owner":owner,"ms":elapsed()}
	if not active_trial.is_empty() and id == turn+":intent":
		row["native_diagnostics"] = native_diagnostic_snapshot()
	terminal_rows.append(row)
	report["native_outcomes"].append(row)
	write_report()

func bounded_diagnostic(value: Variant, depth: int = 0, budget: Array = []) -> Variant:
	if budget.is_empty(): budget.append(1024)
	budget[0] -= 1
	if budget[0] < 0: return "<node limit>"
	if depth >= 8: return "<depth limit>"
	if value is Dictionary:
		var result := {}
		for key in value:
			if budget[0] <= 0: result["_truncated"] = true; break
			if result.size() >= 64: result["_truncated"] = true; break
			result[str(key).left(128)] = bounded_diagnostic(value[key],depth+1,budget)
		return result
	if value is Array:
		var result: Array = []
		for item in value.slice(0,32):
			if budget[0] <= 0: result.append("<node limit>"); break
			result.append(bounded_diagnostic(item,depth+1,budget))
		if value.size()>32: result.append("<array truncated>")
		return result
	if value is float and not is_finite(value): return str(value)
	if value == null or value is bool or value is int or value is float: return value
	return str(value).left(2048)

func native_diagnostic_snapshot() -> Dictionary:
	if app == null: return {"available":false}
	var camera: Camera3D = app.spatial_camera()
	var role := "canonical_reference"
	if camera == null: camera=app.camera; role="root_viewport"
	var anchors: Dictionary = app._projected_anchors()
	var nav = app.scene_navigation
	var state := {"ms":elapsed(),"fit_diagnostics":app.objects.fit_diagnostics.duplicate(true),
		"objects":app.objects.rows().slice(0,16).duplicate(true),"interaction":app.objects._interaction.duplicate(true),
		"pending_command":app.objects._pending_command.duplicate(true),"last_status":app.objects.last_status,
		"window":str(Rect2i(root.position,root.size)),"workareas":app.objects.screen_rects(),
		"foot_global_px":Vector2(root.position)+Vector2(anchors.get("foot",Vector2.ZERO)),
		"anchors_local_px":anchors,"support":app.autonomy.get_support_contact(),
		"autonomy_state":app.autonomy.state,"pointer_interaction":app.autonomy._pointer_interaction,
		"navigation":{"active":nav.navigation.active,"holding":nav.holding,"ground_latched":nav.ground_latched,
			"foot_world_m":nav.foot_world,"diagnostics":nav.diagnostics.duplicate(true)},
		"view":app._view_settings.duplicate(true),"camera_role":role,
		"camera":{"projection":camera.projection,"transform":camera.global_transform,"fov_deg":camera.fov,
			"near_m":camera.near,"far_m":camera.far,"size":camera.size}}
	return bounded_diagnostic(state)

func received(event: Dictionary) -> void:
	super.received(event)
	if active_trial.is_empty() or str(event.get("turn_id","")) != turn: return
	var key := ""
	match str(event.get("type","")):
		"text": key = "first_text_ms"
		"audio": key = "first_pcm_received_ms"
		"action": key = "action_delivered_ms"
		"done": key = "done_ms"
	if not key.is_empty() and not active_trial.has(key): active_trial[key] = elapsed()

func subset_matches(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary: return false
		for key in expected:
			if not actual.has(key) or not subset_matches(actual[key],expected[key]): return false
		return true
	return actual == expected

func fetch_raw() -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request); request.timeout = 4.0
	if request.request(app.client.base_url+"/health") != OK:
		request.queue_free(); return {"available":false,"reason":"health_request_failed"}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[1]) != 200: return {"available":false,"reason":"health_http_failed"}
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary: return {"available":false,"reason":"health_json_failed"}
	var last: Dictionary = data.get("provider",{}).get("last",{})
	if str(last.get("turn_id","")) != turn: return {"available":false,"reason":"provider_last_belongs_to_other_turn"}
	return {"available":true,"record":last}

func trial(step: Dictionary, index: int) -> void:
	done = {}; action = {}; feedback = {}; pcm_bytes = 0; played = false
	max_envelope = 0.0; playback_intervals = []; playback_started = -1
	active_trial = {"index":index,"text":step.text,"started_ms":elapsed(),"simultaneous_native_active_playback_samples":0,"simultaneous_travel_playback_samples":0,"failures":[]}
	report["trials"].append(active_trial)
	active_trial["native_capabilities_before_publish"] = {"living_enabled":app.living.enabled,"furniture_native_available":app.objects.native_available(),"furniture_catalog":app.objects.furniture_catalog().duplicate(true)}
	app.living.publish_world(true)
	app._send_chat(str(step.text))
	turn = app.session.turn_id
	active_trial["turn_id"] = turn
	var wants_intent: bool = step.has("expect_intent")
	var ended := await wait_for(func(): return not done.is_empty() and not app.audio.is_voice_active() and app.audio.queue.pending_frames()==0 \
		and (not wants_intent or not terminal_rows.filter(func(row): return row.id == turn+":intent").is_empty() or not action.has("intent")),float(step.get("timeout_s",60)))
	var failures: Array = active_trial.failures
	if not ended: failures.append("timeout")
	if not bool(done.get("ok",false)): failures.append("reply_failed")
	if pcm_bytes == 0 or not played: failures.append("native_playback_missing")
	var issued: Dictionary = action.get("intent",{})
	if wants_intent and not subset_matches(issued,step.expect_intent): failures.append("expected_intent_missing_or_different")
	if wants_intent and issued != done.get("intent",{}): failures.append("action_done_metadata_mismatch")
	if not no_intent_assertion_passes(step,action,done):
		failures.append("unexpected_intent_for_conversation")
	var outcomes: Array = terminal_rows.filter(func(row): return row.id == turn+":intent")
	if wants_intent:
		if outcomes.size()!=1: failures.append("terminal_count_not_one")
		elif str(outcomes[0].outcome) not in step.get("expected_outcomes",["completed","arrived"]): failures.append("native_execution_unsuccessful")
		if not feedback.get("accepted",false):
			await wait_for(func(): return not feedback.is_empty(),3.0)
			if not feedback.get("accepted",false): failures.append("feedback_not_acknowledged")
	active_trial["reply"] = done.get("text","")
	active_trial["action"] = action; active_trial["done"] = done
	active_trial["pcm_bytes"] = pcm_bytes; active_trial["playback_intervals_ms"] = playback_intervals.duplicate(true)
	active_trial["outcomes"] = outcomes; active_trial["feedback"] = feedback
	active_trial["raw_provider"] = await fetch_raw()
	active_trial["actual_character"] = app.session.character_id
	active_trial["actual_variant"] = app.active_avatar_variant()
	active_trial["actual_model_sha256"] = FileAccess.get_sha256(app.avatar.model_path)
	# Delivery-to-terminal overlap is an interval bound, not a claim that every
	# intermediate frame was moving. Sample count above observes actual active state.
	var overlap := 0
	if active_trial.has("action_delivered_ms") and not outcomes.is_empty():
		for interval in playback_intervals:
			overlap += maxi(0,mini(int(interval[1]),int(outcomes[0].ms))-maxi(int(interval[0]),int(active_trial.action_delivered_ms)))
	active_trial["delivered_action_to_terminal_playback_overlap_ms"] = overlap
	active_trial["overlap_required"] = false
	active_trial["finished_ms"] = elapsed()
	active_trial["native_diagnostics_finished"] = native_diagnostic_snapshot()
	check(failures.is_empty(),"scenario step "+str(index)+" actual reply / playback / intent / native outcome")
	if bool(scenario.get("captures",false)): await shot("scenario-"+str(index))
	write_report()
	active_trial = {}


func valid_step(step: Variant) -> bool:
	if not step is Dictionary: return false
	for key in step:
		if key not in ["text","timeout_s","expect_intent","expect_no_intent","expected_outcomes"]: return false
	if not step.get("text") is String or step.text.strip_edges().is_empty() or step.text.length()>4000: return false
	var timeout: Variant = step.get("timeout_s",60)
	if typeof(timeout) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(timeout)) or float(timeout)<1 or float(timeout)>90: return false
	if typeof(step.get("expect_no_intent",false)) != TYPE_BOOL: return false
	if bool(step.get("expect_no_intent",false)) and step.has("expect_intent"): return false
	if step.has("expect_intent") and (not step.expect_intent is Dictionary or step.expect_intent.is_empty()): return false
	var outcomes: Variant = step.get("expected_outcomes",["completed","arrived"])
	if not outcomes is Array or outcomes.is_empty(): return false
	for outcome in outcomes:
		if outcome not in ["completed","arrived","rejected","failed","cancelled","expired","interrupted"]: return false
	return true

func no_intent_assertion_passes(step: Dictionary, delivered_action: Dictionary, final_event: Dictionary) -> bool:
	return not bool(step.get("expect_no_intent",false)) or (not delivered_action.has("intent") and not final_event.has("intent"))

func run() -> void:
	if OS.get_name() != "Windows": print("TEXT_SCENARIO_NOT_RUN: Windows native display required"); quit(2); return
	output = argument("--output"); requested_character = argument("--character")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(argument("--scenario")))
	if output.is_empty() or requested_character.is_empty() or not parsed is Dictionary or parsed.get("version",0)!=1 or not parsed.get("steps") is Array or parsed.steps.is_empty() or parsed.steps.size()>8:
		push_error("Require --output, --character and version1 scenario with1..8 steps"); quit(2); return
	scenario = parsed
	for step in scenario.steps:
		if not valid_step(step):
			push_error("Invalid scenario step or conflicting assertions"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	started = Time.get_ticks_msec()
	report["trials"] = []; report["native_outcomes"] = []
	report["scope"] = "Actual native session text input, real local LM/PCM, native execution outcomes and backend feedback. No injected intent or fabricated world catalogue. Overlap measured separately; short actions need not overlap speech."
	settings_node = root.get_node("Settings"); original = settings_node.data.duplicate(true)
	var product_defaults := OS.get_cmdline_user_args().has("--product-defaults")
	if product_defaults:
		settings_node.data = settings_node.DEFAULTS.duplicate(true)
		settings_node.data["backend_url"] = original.get("backend_url","")
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":requested_character,"behavior_enabled":true,"autonomy_enabled":true},true)
	report["settings_profile"] = "product_defaults" if product_defaults else "saved_settings"
	report["initial_settings"] = settings_node.data.duplicate(true)
	create_timer(float(scenario_limit)/1000.0).timeout.connect(func():
		if not closing: check(false,"scenario watchdog"); finish())
	app = load("res://main.tscn").instantiate(); root.add_child(app); current_scene=app
	app.client.event_received.connect(received)
	app.objects.command_finished.connect(func(id: String,outcome: String): record_terminal(id,outcome,"","furniture"))
	app.living.director.intent_outcome.connect(func(id: String,outcome: String): record_terminal(id,outcome,"","director"))
	app.audio.playback_changed.connect(func(id: String,active: bool):
		if id != turn: return
		if active:
			played=true; playback_started=elapsed()
			if not active_trial.is_empty() and not active_trial.has("first_playback_ms"): active_trial["first_playback_ms"]=elapsed()
		elif playback_started>=0:
			playback_intervals.append([playback_started,elapsed()]); playback_started=-1)
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() and app._vrma_pending==0,45),"native ready"):
		await finish(); return
	app._switch_character(requested_character)
	if not check(await wait_for(func(): return app.session.character_id==requested_character and app._selection_announced==requested_character and not app.loading_label.visible,20),"actual selected character ready"):
		await finish(); return
	if not check(str(app.session.capabilities.get("provider","")) not in ["","stub"],"real model provider"):
		await finish(); return
	report["identity"]={"character":requested_character,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_video_adapter_name(),"scenario_sha256":FileAccess.get_sha256(argument("--scenario"))}
	var actual_camera: Camera3D = app.spatial_camera()
	var camera_role := "canonical_reference"
	if actual_camera == null:
		actual_camera = app.camera
		camera_role = "root_viewport"
	report["actual_view"] = {"settings":app._view_settings.duplicate(true),"camera_role":camera_role,"projection":actual_camera.projection,"camera_transform":str(actual_camera.global_transform),"fov_deg":actual_camera.fov}
	for index in scenario.steps.size():
		await trial(scenario.steps[index],index)
		if closing: return
	await finish()
