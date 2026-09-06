extends SceneTree
## Opt-in actual Windows furniture probe. Creates/moves only this app's own
## windows, captures only their viewports, and never submits audio or app input.
const Store = preload("res://scripts/desktop_object_store.gd")
var app
var settings_node
var original: Dictionary = {}
var output := ""
var requested_character := "cheval-grand"
var contact_only := false
var requested_scale := 0.6
var started := 0
var closing := false
var next_context_ms := 0
var area := Rect2i()
var report := {"checks": [], "outcomes": [], "contacts": [], "captures": [], "contexts": [], "navigation_outcomes": [], "intent_outcomes": []}

func _initialize() -> void:
	call_deferred("run")

func argument(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == key and i + 1 < args.size(): return args[i + 1]
	return ""

func write_report() -> void:
	if output.is_empty(): return
	report["failures"] = report.checks.filter(func(row): return not row.ok).size()
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  "))

func check(value: bool, label: String) -> void:
	report.checks.append({"ok": value, "label": label})
	print("OBJECTS_WINDOWS ", label, " ", value)
	write_report()

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not closing and Time.get_ticks_msec() < deadline:
		sample_context()
		if predicate.call(): return true
		await process_frame
		await RenderingServer.frame_post_draw
	return false

func persistence_equal(expected: Dictionary, actual: Dictionary, label: String) -> bool:
	# Default JSON.stringify rounds doubles; preserve identity and pixel geometry
	# exactly while allowing only sub-pixel-irrelevant serialization error in scale.
	var detail := {"label":label,"scale_absolute_tolerance":1e-12,"scales":[],"ok":false}
	var lhs := expected.duplicate(true)
	var rhs := actual.duplicate(true)
	var numeric_ok := true
	var expected_rows: Array = lhs.get("objects", [])
	var actual_rows: Array = rhs.get("objects", [])
	if expected_rows.size() != actual_rows.size(): numeric_ok = false
	for i in mini(expected_rows.size(),actual_rows.size()):
		var first: Dictionary = expected_rows[i]
		var second: Dictionary = actual_rows[i]
		var a := float(first.get("scale",NAN))
		var b := float(second.get("scale",NAN))
		var rect_a: Rect2i = app.objects.store.rect_for(first)
		var rect_b: Rect2i = app.objects.store.rect_for(second)
		var within := is_finite(a) and is_finite(b) and absf(a-b)<=1e-12 and rect_a==rect_b
		detail.scales.append({"index":i,"id":first.get("id"),"before_17_decimal":"%.17f" % a,"after_17_decimal":"%.17f" % b,"absolute_error":absf(a-b),"before_rect":str(rect_a),"after_rect":str(rect_b),"within_tolerance_and_identical_pixels":within})
		numeric_ok = numeric_ok and within
		first.erase("scale")
		second.erase("scale")
	# This retains exact count/order, keys, ID, type, labels, visibility, canonical
	# integer positions/version/next_id; only scale was compared separately.
	detail["canonical_fields_exact"] = lhs==rhs
	detail.ok = numeric_ok and lhs==rhs
	if not report.has("persistence_comparisons"): report["persistence_comparisons"] = []
	report.persistence_comparisons.append(detail)
	return detail.ok

func context_snapshot() -> Dictionary:
	if app == null or app.autonomy == null: return {}
	return {"ms": Time.get_ticks_msec()-started, "window": str(root.position),
		"pointer_px": str(DisplayServer.mouse_get_position()), "pointer_interaction": app.autonomy._pointer_interaction,
		"panel_open": app.panel_open, "dragging": app._drag_active, "object_dragging": app.objects.is_dragging(),
		"foreground_busy": app.session.is_foreground_busy(), "job": app.session.job.duplicate(true),
		"speaking": app.audio.voice_active, "recording": app.mic.is_recording(),
		"preview": app.motion._preview, "custom_motion": app.motion._custom_motion,
		"blocked": app.autonomy._blocked, "state": app.autonomy.state,
		"support": app.autonomy.get_support_contact(), "target": str(app.autonomy.target),
		"request_outcome": app.autonomy.last_request_outcome,
		"interaction": app.objects._interaction.duplicate(true), "status": app.objects.last_status}

func sample_context() -> void:
	if Time.get_ticks_msec() < next_context_ms: return
	next_context_ms = Time.get_ticks_msec() + 250
	var snapshot := context_snapshot()
	if not snapshot.is_empty(): report.contexts.append(snapshot)

func isolate_object(id: String) -> bool:
	app.objects.cancel_interaction("probe_isolation")
	for record in app.objects.rows():
		app.objects.set_object_visible(str(record.id), str(record.id) == id)
	return await wait_for(func(): return app.objects.windows.has(id) and app.objects.windows[id].loaded and app.objects.windows[id].visible, 8.0)

func shared_contact_active() -> bool:
	return app.objects.has_method("contact_scene_active") and app.objects.contact_scene_active()

func shot_pair(label: String, prop: Window) -> void:
	await RenderingServer.frame_post_draw
	if shared_contact_active():
		var filename := label + "-shared-depth.png"
		var error := root.get_texture().get_image().save_png(output.path_join(filename))
		report.captures.append({"file":filename,"ms":Time.get_ticks_msec()-started,"window_position":str(root.position),"same_depth_buffer":true,"actual_character":app.session.character_id,"actual_model_path":app.avatar.model_path,"layer_scope":"avatar and contact furniture rendered in root World3D; no assumed composite layers","save_error":error})
		check(error==OK, "shared-depth owned viewport capture " + label)
		return
	# No await between these reads: same completed render frame, own buffers only.
	var timestamp := Time.get_ticks_msec()-started
	var pet_position := root.position
	var prop_position := prop.position
	var pet_image := root.get_texture().get_image()
	var prop_image := prop.get_texture().get_image()
	pet_image.convert(Image.FORMAT_RGBA8)
	prop_image.convert(Image.FORMAT_RGBA8)
	var bounds := Rect2i(pet_position, pet_image.get_size()).merge(Rect2i(prop_position, prop_image.get_size()))
	var composite := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	composite.fill(Color.TRANSPARENT)
	composite.blend_rect(prop_image, Rect2i(Vector2i.ZERO, prop_image.get_size()), prop_position-bounds.position)
	composite.blend_rect(pet_image, Rect2i(Vector2i.ZERO, pet_image.get_size()), pet_position-bounds.position)
	var errors := []
	for item in [["pet", pet_image], ["prop", prop_image], ["composite-assumed-pet-front", composite]]:
		var filename: String = label + "-" + str(item[0]) + ".png"
		var error: int = item[1].save_png(output.path_join(filename))
		errors.append(error)
		report.captures.append({"file": filename, "ms": timestamp, "pet_position": str(pet_position), "prop_position": str(prop_position), "composite_origin": str(bounds.position), "same_render_frame": true, "layer_scope": "assumed pet over prop; not actual OS z-order", "save_error": error})
	check(errors.all(func(error): return error == OK), "same-frame owned pair and assumed-layer composite " + label)

func shot(label: String, window: Window) -> void:
	await RenderingServer.frame_post_draw
	var path := label + ".png"
	var error := window.get_texture().get_image().save_png(output.path_join(path))
	report.captures.append({"file": path, "window_id": window.get_window_id(), "position": str(window.position), "ms": Time.get_ticks_msec()-started, "save_error": error})
	check(error == OK, "capture own viewport " + label)

func placed_floor(fraction: float = 0.35) -> bool:
	app.objects.cancel_interaction("probe_placement")
	app.living.cancel("probe_placement")
	if app.is_sitting(): app._stand_up("")
	app._set_panel_open(false, false)
	root.position = Vector2i(Vector2(area.position.x + area.size.x * fraction, area.end.y) - Vector2(app._projected_anchors().foot))
	return await wait_for(func():
		var contact: Dictionary = app.autonomy.get_support_contact()
		return app.autonomy.can_request_move() and contact.get("attached", false) and str(contact.get("surface_id", "")).begins_with("floor:"), 18.0)

func place_object(id: String, fraction: float) -> bool:
	var record: Dictionary = app.objects.store.get_object(id)
	var dimensions: Vector2i = app.objects.store.rect_for(record).size
	var left := clampi(roundi(area.position.x + area.size.x * fraction - dimensions.x * .5), area.position.x, area.end.x - dimensions.x)
	return app.objects.move_object(id, Vector2i(left, area.end.y - dimensions.y))

func interaction_terminated(id: String, verb: String, outcome_start: int) -> bool:
	return app.objects._interaction.is_empty() and report.outcomes.slice(outcome_start).any(func(row): return row.id==id and row.verb==verb)

func seated(id: String) -> bool:
	return not app.objects._interaction.is_empty() and app.objects._interaction.id == id and app.objects._interaction.stage == "seated" and app.is_sitting() and app._sit_attached

func seat(id: String, label: String) -> bool:
	check(await isolate_object(id), label + " target isolated and loaded")
	check(place_object(id, .62), label + " target placed on usable floor")
	var floor_ready := await placed_floor()
	check(floor_ready, label + " real floor approach precondition")
	if not floor_ready: return false
	app.objects.set_edit_enabled(false)
	var origin: Vector2i = root.position
	var foot_origin: Vector2 = Vector2(root.position)+Vector2(app._projected_anchors().foot)
	var outcome_start: int = report.outcomes.size()
	var accepted: Dictionary = app.objects.interact(id, "sit")
	check(accepted.get("accepted", false), label + " sit accepted")
	if not accepted.get("accepted", false): return false
	await wait_for(func(): return seated(id) or interaction_terminated(id, "sit", outcome_start), 50.0)
	var attached := seated(id)
	check(attached, label + " reaches seated state")
	if not attached:
		report.contacts.append({"label": label, "status": app.objects.last_status, "interaction": app.objects._interaction.duplicate(true), "context": context_snapshot()})
		write_report()
		return false
	await RenderingServer.frame_post_draw
	check(shared_contact_active(), label + " uses required shared contact scene")
	var socket: Vector2 = app.objects.contact_socket_screen("seat") if shared_contact_active() else app.objects.windows[id].socket_point("seat")
	var rendered := Vector2(root.position) + Vector2(app._projected_anchors().sit)
	var error := rendered.distance_to(socket)
	var foot_end: Vector2 = Vector2(root.position)+Vector2(app._projected_anchors().foot)
	report.contacts.append({"label": label, "shared_depth_buffer":shared_contact_active(), "socket_px": str(socket), "rendered_seat_px": str(rendered), "error_px": error, "window_start": str(origin), "window_end": str(root.position), "global_foot_start":str(foot_origin), "global_foot_end":str(foot_end), "global_foot_displacement_x":absf(foot_end.x-foot_origin.x), "support": app.autonomy.get_support_contact()})
	check(error <= 3.0, label + " calibrated avatar seat anchor matches projected prop socket within 3px")
	check(absf(foot_end.x-foot_origin.x)>100, label + " visible global foot approach exceeds 100px")
	await shot_pair(label, app.objects.windows[id])
	return true

func run() -> void:
	if OS.get_name() != "Windows":
		print("WINDOWS_OBJECTS_NOT_RUN: actual Windows display required")
		quit(2)
		return
	output = argument("--output")
	contact_only = OS.get_cmdline_user_args().has("--contact-only")
	report["mode"] = "contact-only" if contact_only else "full-lifecycle"
	var scale_argument := argument("--scale")
	if OS.get_cmdline_user_args().has("--scale"):
		if not scale_argument.is_valid_float():
			push_error("--scale requires a finite numeric value")
			quit(2)
			return
		requested_scale = scale_argument.to_float()
		if not is_finite(requested_scale) or requested_scale < AutonomyBridge.SCALE_MIN or requested_scale > AutonomyBridge.SCALE_MAX:
			push_error("--scale must be within [%s, %s]" % [AutonomyBridge.SCALE_MIN, AutonomyBridge.SCALE_MAX])
			quit(2)
			return
	report["requested_scale"] = requested_scale
	var selected_argument := argument("--character")
	if not selected_argument.is_empty(): requested_character = selected_argument
	report["requested_character"] = requested_character
	if output.is_empty(): push_error("--output is required"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	started = Time.get_ticks_msec()
	create_timer(420).timeout.connect(func():
		if not closing:
			check(false, "probe exceeded 420-second bound")
			finish())
	settings_node = root.get_node("Settings")
	original = settings_node.data.duplicate(true)
	settings_node.data.merge({"vad_enabled": false, "panel_open": false, "autonomy_enabled": true, "surface_roam": true,
		"behavior_enabled": true, "pet_scale": requested_scale, "character": requested_character,
		"desktop_objects": {"version": 1, "next_id": 1, "objects": []}}, true)
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	var ready := await wait_for(func(): return app.avatar.has_model() and app.session.hello_received and app.motion.vrma_clips.has("sit_idle") and app.motion.vrma_clips.has("walk") and app._vrma_pending == 0, 45.0)
	check(ready, "real avatar backend and required motions ready")
	if not ready: await finish(); return
	var known_character: bool = not app.session.character_by_id(requested_character).is_empty()
	check(known_character, "requested character exists in backend catalogue")
	if not known_character: await finish(); return
	# Hello may select the backend default after initial Settings were applied.
	app._switch_character(requested_character)
	var expected_path := BackendClient.avatar_cache_path(requested_character)
	var identity_ready := await wait_for(func(): return app.session.character_id == requested_character and app.avatar.has_model() and app.avatar.model_path.get_file() == expected_path.get_file() and not app.loading_label.visible, 45.0)
	report["actual_character"] = app.session.character_id
	report["actual_model_path"] = app.avatar.model_path
	report["actual_model_title"] = app.avatar.meta_title
	report["expected_model_filename"] = expected_path.get_file()
	report["actual_model_sha256"] = FileAccess.get_sha256(app.avatar.model_path) if app.avatar.has_model() else ""
	check(identity_ready, "explicit character selection matches actual loaded rig filename and session")
	if not identity_ready: await finish(); return
	var scale_ready := await wait_for(func(): return absf(app._pet_scale-requested_scale)<=0.001, 5.0)
	report["actual_pet_scale"] = app._pet_scale
	report["actual_px_per_m"] = app._px_per_m
	check(scale_ready, "actual pet scale matches requested %.3f" % requested_scale)
	if not scale_ready: await finish(); return
	report["renderer"] = RenderingServer.get_video_adapter_name()
	report["coordinate_scope"] = "Godot desktop pixels and world metres. Active contact scenes use the root camera and shared World3D/depth buffer for sockets and final avatar bones; legacy fallback uses separate prop-camera projection and is labeled accordingly. No OS input injection or external window content capture."
	check(app.objects.native_available(), "native furniture subwindows supported")
	area = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	report["workarea"] = str(area)
	check(await placed_floor(), "actual usable monitor floor at requested pet scale %.3f" % requested_scale)
	app.objects.interaction_finished.connect(func(id, verb, outcome): report.outcomes.append({"id": id, "verb": verb, "outcome": outcome, "ms": Time.get_ticks_msec()-started, "context": context_snapshot()}))
	app.autonomy.navigation_finished.connect(func(id, outcome): report.navigation_outcomes.append({"id": id, "outcome": outcome, "context": context_snapshot()}))
	app.living.director.intent_outcome.connect(func(id, outcome): report.intent_outcomes.append({"id": id, "outcome": outcome, "context": context_snapshot()}))
	var ids := {}
	for type in ["chair", "sofa", "computer"]:
		var id: String = app.objects.add_object(type)
		ids[type] = id
		check(not id.is_empty(), type + " object created")
		if id.is_empty(): await finish(); return
		var loaded := await wait_for(func(): return app.objects.windows.has(id) and app.objects.windows[id].loaded and app.objects.windows[id].visible, 8.0)
		check(loaded, type + " GLB loaded and actual owned window visible")
		if not loaded: await finish(); return
		check(app.objects.windows[id].get_window_id() != root.get_window_id(), type + " separate native window")
		check(place_object(id, {"chair": .2, "sofa": .5, "computer": .8}[type]), type + " placed on usable floor")
		await shot(type + "-loaded", app.objects.windows[id])
	app.objects.set_edit_enabled(false)
	var data: Dictionary = app.objects.store.data()
	var restored := Store.new()
	restored.set_data(JSON.parse_string(JSON.stringify(data)))
	check(persistence_equal(data, restored.data(), "JSON store round trip"), "object data survives JSON serialization with exact pixel geometry")
	settings_node.save_now()
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
	report["persisted_disk_payload"] = disk
	var disk_store := Store.new()
	if disk is Dictionary: disk_store.set_data(disk.get("desktop_objects"))
	report["persisted_canonical_objects"] = disk_store.data()
	check(disk is Dictionary and disk.has("desktop_objects") and persistence_equal(data, disk_store.data(), "Settings disk round trip"), "object data persisted through Settings with exact pixel geometry")
	report["object_data"] = data
	var chair_ok := await seat(ids.chair, "chair")
	app._cancel_current()
	check(await wait_for(func(): return not app.is_sitting() and app.objects._interaction.is_empty(), 3.0) and chair_ok, "explicit user stop releases occupied chair")
	await seat(ids.sofa, "sofa")
	app.objects.cancel_interaction("probe_next")
	var mutations: Array = [] if contact_only else ["move", "resize", "hide", "remove"]
	for mutation in mutations:
		var occupied := await seat(ids.chair, "chair-before-" + mutation)
		var record: Dictionary = app.objects.store.get_object(ids.chair)
		var changed := false
		match mutation:
			"move": changed = app.objects.move_object(ids.chair, Vector2i(app.objects.windows[ids.chair].position) + Vector2i(30, 0))
			"resize": changed = app.objects.resize_object(ids.chair, maxf(1.0, float(record.scale) - .1))
			"hide": changed = app.objects.set_object_visible(ids.chair, false)
			"remove": changed = app.objects.remove_object(ids.chair)
		check(changed, "occupied object " + mutation + " accepted")
		check(await wait_for(func(): return not app.is_sitting() and app.objects._interaction.is_empty(), 3.0) and occupied, "occupied object " + mutation + " releases seat")
		if mutation == "hide":
			app.objects.set_object_visible(ids.chair, true)
			check(await wait_for(func(): return app.objects.windows.has(ids.chair) and app.objects.windows[ids.chair].loaded, 8.0), "hidden chair can be restored")
		if mutation == "resize": app.objects.resize_object(ids.chair, float(record.scale))
	check(await isolate_object(ids.computer), "computer target isolated and loaded")
	check(place_object(ids.computer, .62), "computer target placed on usable floor")
	check(await placed_floor(), "computer approach real floor precondition")
	app.objects.set_edit_enabled(false)
	var use_outcome_start: int = report.outcomes.size()
	var use: Dictionary = app.objects.interact(ids.computer, "use")
	check(use.get("accepted", false), "computer use accepted")
	await wait_for(func(): return app.objects._interaction.get("stage", "") == "using" or interaction_terminated(ids.computer, "use", use_outcome_start), 45.0)
	var using: bool = app.objects._interaction.get("stage", "") == "using"
	check(using, "computer reaches finite work-pose stage")
	if using:
		check(shared_contact_active(), "computer uses required shared contact scene")
		var expiry_outcome_start: int = report.outcomes.size()
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		if shared_contact_active():
			var hand_metrics := {}
			for side in ["left", "right"]:
				var socket: Vector2 = app.objects.contact_socket_screen("keyboard_" + side)
				var target: Vector3 = app.objects.contact_socket_world("keyboard_" + side)
				var wrist: Vector3 = app.avatar.bone_global_position(side + "Hand")
				var projected: Vector2 = Vector2(root.position) + app.camera.unproject_position(wrist)
				var reachable: bool = app.objects._interaction.get(side + "_hand_reachable", false)
				hand_metrics[side] = {"hand_reachable":reachable,"keyboard_px":str(socket),"keyboard_world":str(target),"rendered_wrist_px":str(projected),"wrist_world":str(wrist),"error_px":projected.distance_to(socket),"error_world_m":wrist.distance_to(target)}
				check(reachable and projected.distance_to(socket)<=3.0 and wrist.distance_to(target)<=.02, "final shared-scene " + side + " wrist reaches keyboard within 3px and2cm")
			var seat_socket: Vector2 = app.objects.contact_socket_screen("seat")
			var seat_anchor: Vector2 = Vector2(root.position)+Vector2(app._projected_anchors().sit)
			report["computer_contact"] = {"shared_depth_buffer":true,"hand_reachable":app.objects._interaction.get("hand_reachable",false),"hands":hand_metrics,"seated":app.is_sitting(),"seat_attached":app._sit_attached,"seat_error_px":seat_anchor.distance_to(seat_socket)}
			check(app.is_sitting() and app._sit_attached and seat_anchor.distance_to(seat_socket)<=3.0, "computer use remains seated at shared-scene socket")
		else:
			var socket: Vector2 = app.objects.windows[ids.computer].socket_point("use")
			var wrist: Vector3 = app.avatar.bone_global_position("rightHand")
			var projected: Vector2 = Vector2(root.position) + app.camera.unproject_position(wrist)
			var target: Vector3 = AutonomyBridge.pixel_to_world(socket-Vector2(root.position), app._camera_base, app._px_per_m, Vector2(app.WINDOW_SIZE))
			var reachable: bool = app.objects._interaction.get("hand_reachable", false)
			report["computer_contact"] = {"hand_reachable": reachable, "keyboard_px": str(socket), "rendered_wrist_px": str(projected), "error_px": projected.distance_to(socket), "error_world_m": wrist.distance_to(target)}
			check(reachable and projected.distance_to(socket) <= 3.0 and wrist.distance_to(target) <= .02, "final rendered wrist reaches keyboard within 3px and2cm")
		await shot_pair("computer-use", app.objects.windows[ids.computer])
		var ended := await wait_for(func(): return app.objects._interaction.is_empty(), 12.0)
		var expiry_outcomes: Array = report.outcomes.slice(expiry_outcome_start).filter(func(row): return row.id == ids.computer and row.verb == "use")
		report["computer_expiry_outcomes"] = expiry_outcomes
		check(ended and expiry_outcomes.size()==1 and expiry_outcomes[0].outcome=="completed", "finite computer work pose ends with completed outcome, not cancellation")
	await finish()

func finish() -> void:
	if closing: return
	closing = true
	if app != null:
		var owned: Array = app.objects.windows.values().duplicate()
		app.objects.shutdown()
		app.objects.shutdown()
		await process_frame
		await process_frame
		check(app.objects.windows.is_empty() and owned.all(func(window): return not is_instance_valid(window)), "idempotent shutdown removes own furniture windows")
		app.mic.cancel_recording()
		app.world_source.stop()
		app.client.disconnect_ws()
		app.queue_free()
		await process_frame
	if settings_node != null:
		settings_node.data = original
		settings_node.save_now()
		check(settings_node.data == original, "original settings restored")
	write_report()
	print("WINDOWS_OBJECTS_REPORT ", output.path_join("report.json"), " failures=", report.get("failures", 0))
	quit(0 if report.get("failures", 0) == 0 else 1)
