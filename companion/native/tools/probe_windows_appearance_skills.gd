extends "probe_windows_space_skills.gd"
## Root-exclusive Windows launch. Reuses strict real PCM/raw intent_result helpers.
## --output DIR --default-sha256 HEX --wet-sha256 HEX [--character mambo|hachimi]
## Two real LM turns, no fabricated intent/response, no external desktop input.
var appearance_character := "mambo"
var expected_default := ""
var expected_wet := ""
var disconnect_count := 0
var session_identity := 0
var last_avatar_path := ""

func sample() -> void:
	super.sample()
	if app != null and app.avatar.has_model() and app.avatar.model_path != last_avatar_path:
		last_avatar_path = app.avatar.model_path
		report.events.append({"type":"native_avatar_path","path":last_avatar_path,"sha256":FileAccess.get_sha256(last_avatar_path),"variant":app.active_avatar_variant(),"ms":elapsed()})

func appearance_turn(text: String, variant: String, expected_sha: String) -> bool:
	done = {}; action = {}; feedback = {}; pcm_bytes = 0; played = false
	max_envelope = 0.0; first_playback_ms = -1
	var disconnected_before := disconnect_count
	var old_hash := FileAccess.get_sha256(app.avatar.model_path)
	app.living.publish_world(true)
	app._send_chat(text)
	turn = app.session.turn_id
	var id := turn+":intent"
	var trial := {"variant":variant,"text":text,"turn_id":turn,"old_sha256":old_hash,"expected_sha256":expected_sha,"started_ms":elapsed()}
	report["attempts"].append(trial)
	write_report()
	var finished := await wait_for(func(): return not done.is_empty() and not app.audio.is_voice_active() and app.audio.queue.pending_frames() == 0 \
		and app.avatar_variant_outcomes.any(func(row): return row.id == id),42.0)
	check(finished,variant+" real response drains voice and reaches terminal native appearance outcome")
	check(bool(done.get("ok",false)) and contains_japanese(str(done.get("text",""))),variant+" successful real reply contains Japanese speech text")
	check(played and pcm_bytes>0 and max_envelope>.01,variant+" streamed PCM actually played")
	var intent: Dictionary = done.get("intent",{}) if done.get("intent",{}) is Dictionary else {}
	check(intent.get("kind","") == "change_appearance" and intent.get("variant_id","") == variant,variant+" real LM requested expected appearance skill")
	check(action.get("intent",{}) == intent,variant+" action and done agree")
	var outcomes: Array = app.avatar_variant_outcomes.filter(func(row): return row.id == id)
	check(outcomes.size() == 1 and outcomes[0].outcome == "completed",variant+" exactly one completed native outcome despite action/done duplication")
	check(await wait_for(func(): return not feedback.is_empty(),3.0) and bool(feedback.get("accepted",false)),variant+" backend acknowledges actual completion feedback")
	var actual_hash := FileAccess.get_sha256(app.avatar.model_path)
	check(actual_hash == expected_sha and actual_hash != old_hash,variant+" actual loaded VRM has expected different byte hash")
	check(app.active_avatar_variant() == variant and ProjectSettings.globalize_path(app.avatar.model_path).simplify_path() == ProjectSettings.globalize_path(BackendClient.avatar_cache_path(appearance_character,variant)).simplify_path(),variant+" active variant and loaded cache path match")
	check(app.session.character_id == appearance_character and app.session.get_instance_id() == session_identity \
		and disconnect_count == disconnected_before and app.client.state == "open" and app._selection_announced == appearance_character,variant+" same character session and connection retained")
	trial["reply"] = done.get("text",""); trial["pcm_bytes"] = pcm_bytes; trial["max_envelope"] = max_envelope
	trial["outcomes"] = outcomes; trial["feedback"] = feedback; trial["loaded_sha256"] = actual_hash; trial["finished_ms"] = elapsed()
	await shot("appearance-"+variant+"-loaded")
	write_report()
	return finished and actual_hash == expected_sha and app.active_avatar_variant() == variant

func run() -> void:
	if OS.get_name() != "Windows":
		print("APPEARANCE_SKILLS_NOT_RUN: actual Windows display and live backend required")
		quit(2); return
	output = argument("--output")
	appearance_character = argument("--character")
	if appearance_character.is_empty(): appearance_character = "mambo"
	expected_default = argument("--default-sha256").to_lower()
	expected_wet = argument("--wet-sha256").to_lower()
	var hash_pattern := RegEx.create_from_string("^[0-9a-f]{64}$")
	if output.is_empty() or appearance_character not in ["mambo","hachimi"] or hash_pattern.search(expected_default) == null or hash_pattern.search(expected_wet) == null or expected_default == expected_wet:
		push_error("Require --output and distinct --default-sha256/--wet-sha256; character mambo or hachimi")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	started = Time.get_ticks_msec()
	report["attempts"] = []
	report["scope"] = "Two actual Korean requests -> Japanese reply text and real native PCM -> LM change_appearance -> actual hash-verified VRM reload -> backend acknowledged completion. Same character/session/connection. No desktop input, arbitrary path, fabricated model output or native intent injection for the two tested turns."
	create_timer(float(LIMIT_MS)/1000.0).timeout.connect(func():
		if not closing: check(false,"120second overall appearance watchdog"); finish())
	settings_node = root.get_node("Settings")
	original = settings_node.data.duplicate(true)
	var choices: Dictionary = original.get("avatar_variant_choices",{}).duplicate(true)
	choices[appearance_character] = "default"
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":appearance_character,"pet_scale":.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,"view_projection":"orthographic",
		"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,"avatar_variant_choices":choices,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app); current_scene = app
	session_identity = app.session.get_instance_id()
	app.client.event_received.connect(received)
	app.client.disconnected.connect(func(_reason: String): disconnect_count += 1)
	app.audio.playback_changed.connect(func(id: String,active: bool):
		report.events.append({"type":"native_playback","turn_id":id,"active":active,"ms":elapsed()})
		if id == turn and active:
			played = true
			if first_playback_ms < 0: first_playback_ms = elapsed())
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() and app._vrma_pending == 0,35.0),"production backend avatar and motion readiness"):
		await finish(); return
	check(str(app.session.capabilities.get("provider","")) not in ["","stub"],"non-stub model provider declared")
	app._switch_character(appearance_character)
	if not check(await wait_for(func(): return app.session.character_id == appearance_character and not app.loading_label.visible,15.0),"explicit target character session ready"):
		await finish(); return
	var catalog: Dictionary = app.session.character_by_id(appearance_character)
	var variants: Array = catalog.get("avatar_variants",[])
	if not check(variants.any(func(row): return row.id == "wet" and row.get("avatar_available",false)) and variants.any(func(row): return row.id == "default" and row.get("avatar_available",false)),"installed selected-profile default and wet variants advertised"):
		await finish(); return
	# Explicit baseline setup only. The following two measured changes use LM.
	app.request_avatar_variant("default")
	if not check(await wait_for(func(): return not app.loading_label.visible and app._avatar_variant_command.is_empty() and app.active_avatar_variant() == "default",12.0) \
		and FileAccess.get_sha256(app.avatar.model_path) == expected_default,"actual default VRM baseline hash verified"):
		await finish(); return
	report["identity"] = {"character":appearance_character,"session_instance":session_identity,"default_sha256":expected_default,"wet_sha256":expected_wet,"renderer":RenderingServer.get_video_adapter_name(),"profile_variants":variants}
	await shot("appearance-default-baseline")
	if await appearance_turn("젖은 외형으로 바꿔 줘. 먼저 짧게 대답해 줘.","wet",expected_wet):
		await appearance_turn("원래의 기본 외형으로 돌아가 줘. 먼저 짧게 대답해 줘.","default",expected_default)
	await finish()
