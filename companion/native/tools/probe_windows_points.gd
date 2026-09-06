extends SceneTree
## Opt-in real-Windows probe for interest points and native marker windows. Run by root only:
##
##   Godot_v4.5.2-stable_win64_console.exe --path companion/native --script tools/probe_windows_points.gd \
##       -- --test-root <companion dir> --drag-dx 160 --drag-dy -90 [--no-input] [--wait-seconds 60] [--output <dir>]
##   MateCompanion.exe --script <absolute path to this external script> -- ... (packaged build)
##
## Loads the actual main scene (live backend, preserved user Settings), adds one point next to the
## pet through the panel path, shows the actual native pin, writes its geometry to
## <output>/ready.json (gitignored logs) and then waits for an external drag of THAT pin by
## diagnostics/liveliness/run_windows_points.py (or nothing with --no-input). It verifies the
## committed tip shift, persisted data, a coordinate-free catalog, native window visibility /
## unfocusable / transparency flags, the user 가보기/살펴보기 flow into LivingBehavior.request_intent,
## marker hiding, marker window cleanup and Settings restoration. It captures only its own
## viewport; no desktop pixels are read. This script never verifies anything by itself on Linux.
var app
var settings_node
var original_settings: Dictionary
var output_dir: String
var report := {"platform": OS.get_name(), "checks": [], "notes": []}
var started := 0
var placed: Array = []
var point_id := ""


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	print("CHECK ", label, " ", ok)


func note(key: String, value: Variant) -> void:
	report[key] = value


func arg_value(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with(name + "="):
			return args[i].substr(name.length() + 1)
	return fallback


func companion_path(relative: String) -> String:
	var test_root := arg_value("--test-root", "")
	if not test_root.is_empty():
		return test_root.path_join(relative)
	return ProjectSettings.globalize_path("res://../" + relative)


func wait_for(test: Callable, seconds: float) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < limit:
		if test.call():
			return true
		await process_frame
	return false


func shot(name: String) -> void:
	# Own viewport only (the pet window); never the desktop.
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output_dir.path_join(name + ".png")) == OK, "capture own viewport " + name)


func write_json(name: String, data: Dictionary) -> void:
	var f := FileAccess.open(output_dir.path_join(name), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func rect_dict(pos: Vector2i, size: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y, "w": size.x, "h": size.y}


func run() -> void:
	if OS.get_name() != "Windows":
		push_error("probe_windows_points.gd requires actual Windows; the headless selftest covers the logic separately.")
		quit(2)
		return
	started = Time.get_ticks_msec()
	output_dir = arg_value("--output", companion_path("logs/windows-points"))
	DirAccess.make_dir_recursive_absolute(output_dir)
	var no_input := OS.get_cmdline_user_args().has("--no-input")
	var drag := Vector2i(int(arg_value("--drag-dx", "160")), int(arg_value("--drag-dy", "-90")))
	var wait_seconds := float(arg_value("--wait-seconds", "60"))
	note("args", {"no_input": no_input, "drag": [drag.x, drag.y], "wait_seconds": wait_seconds})

	settings_node = root.get_node("Settings")
	original_settings = settings_node.data.duplicate(true)
	# Keep the pet still and the panel open; the user's saved points are untouched and restored.
	settings_node.data["vad_enabled"] = false
	settings_node.data["panel_open"] = true
	settings_node.data["autonomy_enabled"] = false
	settings_node.data["behavior_enabled"] = true
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	check(await wait_for(func(): return app.session.hello_received, 25), "live backend hello (WS)")
	check(await wait_for(func(): return app.avatar.has_model() and not app.loading_label.visible, 40), "avatar loaded")
	await create_timer(0.5).timeout
	note("renderer", RenderingServer.get_video_adapter_name())
	var living = app.living
	check(living != null and living.points != null, "LivingBehavior owns an InterestPoints manager")
	if living == null or living.points == null:
		finish()
		return
	var points = living.points
	check(not root.gui_embed_subwindows, "root viewport does not embed sub-windows (main setting)")
	var status: Dictionary = points.marker_status()
	check(bool(status.ok), "native markers available (%s)" % str(status.reason))
	var pins_before: int = points.count()
	var catalog_before: Array = points.catalog().duplicate(true)
	note("points_before", pins_before)

	# --- add one point next to the pet through the panel (same code path as the user)
	var main_focused := DisplayServer.window_is_focused(DisplayServer.MAIN_WINDOW_ID)
	app.panel._point_name.text = "탐침 지점"
	app.panel._request_add_point()
	point_id = app.panel.selected_point_id()
	check(not point_id.is_empty() and points.has_point(point_id) and points.count() == pins_before + 1, "point added via the panel (%s)" % point_id)
	check(points.markers_shown and app.panel.markers_shown(), "adding turns markers on for placing")
	await process_frame
	await process_frame
	var marker: Window = points.marker_for(point_id)
	check(marker != null and marker.visible, "marker window exists and is visible")
	if marker == null:
		finish()
		return
	var wid: int = marker.get_window_id()
	check(not marker.is_embedded() and wid != DisplayServer.INVALID_WINDOW_ID and DisplayServer.get_window_list().has(wid), "marker is a native OS window (id %d), not embedded" % wid)
	check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, wid) and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, wid) and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, wid) and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, wid), "OS flags: unfocusable, transparent, always on top, borderless")
	check(DisplayServer.window_is_focused(DisplayServer.MAIN_WINDOW_ID) == main_focused and not DisplayServer.window_is_focused(wid), "marker creation did not take focus")
	var os_pos := DisplayServer.window_get_position(wid)
	var os_size := DisplayServer.window_get_size(wid)
	var tip0: Vector2i = points.position_of(point_id)
	check(os_pos == marker.position and os_size == InterestPoints.MARKER_SIZE and os_pos + InterestPoints.MARKER_TIP == tip0, "OS window rect matches: position + MARKER_TIP == saved point")
	var anchor: Vector2i = Vector2i(app.get_window().position) + Vector2i(app.pet_rect.get_center())
	check(Vector2(tip0).distance_to(Vector2(anchor)) < 400.0, "new point is next to the pet (%.0f px from the pet centre)" % Vector2(tip0).distance_to(Vector2(anchor)))
	check(points.reachable(point_id), "new point is on a current monitor (ready)")
	await shot("pin-placed")

	var grab := os_pos + Vector2i(InterestPoints.MARKER_SIZE.x / 2, 15) # pin head centre, inside the passthrough polygon
	var screens: Array = []
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_usable_rect(i)
		screens.append(rect_dict(r.position, r.size))
	var ready := {
		"pid": OS.get_process_id(),
		"main_window": rect_dict(DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID), DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)),
		"marker": {"id": point_id, "window_id": wid, "rect": rect_dict(os_pos, os_size), "tip": [tip0.x, tip0.y], "grab": [grab.x, grab.y]},
		"drag": [drag.x, drag.y],
		"screens": screens,
		"no_input": no_input,
		"wait_seconds": wait_seconds,
		"written_ms": Time.get_ticks_msec() - started,
	}
	write_json("ready.json", ready)
	note("ready", ready)
	points.point_placed.connect(func(id: String, pos: Vector2i): placed.append({"id": id, "pos": [pos.x, pos.y], "ms": Time.get_ticks_msec() - started}))

	if no_input:
		report.notes.append("no-input: external drag skipped; tip shift not measured")
	else:
		var got := await wait_for(func(): return not placed.is_empty(), wait_seconds)
		check(got, "external drag of the owned pin produced point_placed within %.0fs" % wait_seconds)
		if got:
			var tip1: Vector2i = points.position_of(point_id)
			var shift := tip1 - tip0
			note("tip_shift", [shift.x, shift.y])
			check(str(placed[0].id) == point_id, "point_placed names the dragged point")
			check(shift == drag, "tip shifted by exactly the requested drag (%s vs %s)" % [str(shift), str(drag)])
			check(not marker.dragging, "drag ended cleanly (no latched drag)")
			var os_after := DisplayServer.window_get_position(wid)
			check(os_after + InterestPoints.MARKER_TIP == tip1 and marker.tip() == tip1, "OS window position + MARKER_TIP equals the saved point after the drag")
			check(DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID) == Vector2i(ready.main_window.x, ready.main_window.y), "pet window did not move during the pin drag")
			await shot("pin-dragged")
	# --- persistence + catalog
	var saved: Dictionary = settings_node.get_value("interest_points", {})
	var saved_entry := {}
	for p in saved.get("points", []):
		if str(p.get("id", "")) == point_id:
			saved_entry = p
	check(not saved_entry.is_empty() and Vector2i(int(saved_entry.get("x", 0)), int(saved_entry.get("y", 0))) == points.position_of(point_id), "Settings hold the committed coordinates for the new point")
	var cat: Array = points.catalog()
	var cat_ok: bool = cat.size() == points.count()
	for c in cat:
		cat_ok = cat_ok and c.keys().size() == 3 and not c.has("x") and not c.has("y")
	check(cat_ok, "catalog carries only id/label/kind (no coordinates)")

	# --- user 가보기 / 살펴보기 -> LivingBehavior.request_intent (director queue), markers hide
	var director = living.director
	app.panel.select_point(point_id)
	var queued_before: int = director._queue.size()
	app.panel.point_go.emit(point_id)
	await process_frame
	var go_intent := _queued_intent(director, point_id, "move_to")
	check(not go_intent.is_empty() and str(go_intent.get("source", "")) == "user", "가보기 queued a user move_to intent for the point (%d -> %d queued)" % [queued_before, director._queue.size()])
	check(not points.markers_shown and points.marker_count() == 0 and not app.panel_open, "가보기 hid the markers and closed the panel")
	check(not is_instance_valid(marker) or marker.get_parent() == null, "marker window released after hiding")
	check(not DisplayServer.get_window_list().has(wid), "marker OS window destroyed after hiding")
	living.cancel("probe")
	app._set_panel_open(true, false)
	app.panel.select_point(point_id)
	app.panel.point_inspect.emit(point_id)
	await process_frame
	var look_intent := _queued_intent(director, point_id, "inspect")
	check(not look_intent.is_empty(), "살펴보기 queued a user inspect intent (no walking requested)")
	check(not app.panel_open, "살펴보기 closed the panel")
	living.cancel("probe")
	app._set_panel_open(true, false)

	# --- cleanup: remove the probe point, markers gone, settings restored
	app.panel.select_point(point_id)
	app.panel._markers_check.button_pressed = true
	await process_frame
	var again: Window = points.marker_for(point_id)
	var again_id: int = again.get_window_id() if again != null else DisplayServer.INVALID_WINDOW_ID
	check(again != null and again.visible and again_id != DisplayServer.INVALID_WINDOW_ID, "markers can be shown again")
	app.panel._request_remove_point()
	await process_frame
	await process_frame
	check(not points.has_point(point_id) and points.count() == pins_before and points.marker_for(point_id) == null, "probe point removed; count back to %d" % pins_before)
	check(not DisplayServer.get_window_list().has(again_id), "removed point's OS window destroyed")
	check(points.catalog() == catalog_before, "catalog identical to before the probe")
	finish()


func _queued_intent(director, target: String, kind: String) -> Dictionary:
	if not director._active.is_empty() and str(director._active.get("target_id", "")) == target and str(director._active.get("kind", "")) == kind:
		return director._active
	for q in director._queue:
		if str(q.get("target_id", "")) == target and str(q.get("kind", "")) == kind:
			return q
	return {}


func finish() -> void:
	if app != null:
		if app.living != null and app.living.points != null:
			app.living.points.set_markers_visible(false)
			if not point_id.is_empty():
				app.living.points.remove_point(point_id)
		app.client.disconnect_ws()
		app.mic.cancel_recording()
	# Restore the user's settings exactly (points, toggles, window position) and check the file.
	settings_node.data = original_settings.duplicate(true)
	settings_node.save_now()
	var reread: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_node.PATH))
	check(typeof(reread) == TYPE_DICTIONARY and reread.get("interest_points") == JSON.parse_string(JSON.stringify(original_settings.get("interest_points"))), "settings file restored to the pre-probe interest points")
	var leftovers := 0
	for w in DisplayServer.get_window_list():
		if w != DisplayServer.MAIN_WINDOW_ID:
			leftovers += 1
	check(leftovers == 0, "no marker windows left (%d extra OS windows)" % leftovers)
	var failures := 0
	for entry in report.checks:
		if not entry.ok:
			failures += 1
	report["failures"] = failures
	report["elapsed_ms"] = Time.get_ticks_msec() - started
	write_json("report.json", report)
	print("WINDOWS_POINTS failures=", failures)
	quit(0 if failures == 0 else 1)
