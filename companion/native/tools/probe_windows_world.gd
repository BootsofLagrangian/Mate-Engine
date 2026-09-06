extends SceneTree
## Opt-in real Windows window/grounding probe. Run with --fixture-dir <owned fixture>
## and --test-root <companion>. Only the companion window and a separate owned
## fixture are moved. No desktop pixels or window contents are captured.
var app
var output: String
var fixture_dir: String
var fixture_id := ""
var fixture: Dictionary = {}
var report := {"checks": [], "travel": [], "states": []}
var next_sample := 0
var settings_node
var original_settings: Dictionary
var surface_line: ColorRect

func _initialize() -> void:
	call_deferred("run")

func argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]
	return ""

func check(ok: bool, label: String) -> void:
	report.checks.append({"ok": ok, "label": label})
	print("CHECK ", label, " ", ok)

func wait_for(test: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		update_line()
		await process_frame
	return false

func update_line() -> void:
	if app != null and Time.get_ticks_msec() >= next_sample:
		next_sample = Time.get_ticks_msec() + 250
		report.states.append({"time": Time.get_ticks_msec(), "state": app.autonomy.state,
			"position": str(root.position), "target": str(app.autonomy.target),
			"bounds": str(app.pet_rect), "anchor": str(app._projected_anchors()),
			"locked_anchor": str(app.autonomy._locked_anchor), "support": app.autonomy.get_support_contact(),
			"blocked": app.autonomy._blocked, "pointer": app.autonomy._pointer_interaction,
			"settle_until": app.autonomy._settle_until, "clock": app.autonomy._time,
			"workareas": str(app.autonomy.workareas)})
	if surface_line == null or fixture.is_empty():
		return
	surface_line.position = Vector2(float(fixture.x), float(fixture.y)) - Vector2(root.position)
	surface_line.size = Vector2(float(fixture.width), 2)

func find_fixture() -> bool:
	for item: Dictionary in app.world_source.snapshot.get("windows", []):
		if str(item.id) == fixture_id:
			fixture = item
			return true
	return false

func attached_to_fixture() -> bool:
	var contact: Dictionary = app.autonomy.get_support_contact()
	return bool(contact.get("attached", false)) and str(contact.get("surface_id", "")).contains(fixture_id)

func shot(name: String) -> void:
	update_line()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	if OS.get_name() != "Windows":
		quit(2)
		return
	fixture_dir = argument("--fixture-dir")
	output = argument("--test-root").path_join("logs/windows-world")
	if not argument("--output").is_empty():
		output = argument("--output")
	DirAccess.make_dir_recursive_absolute(output)
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_dir.path_join("fixture.json")))
	fixture_id = str(metadata.id)
	settings_node = root.get_node("Settings")
	original_settings = settings_node.data.duplicate(true)
	settings_node.data["vad_enabled"] = false
	settings_node.data["autonomy_enabled"] = true
	settings_node.data["surface_roam"] = true
	settings_node.data["panel_open"] = true
	settings_node.data["pet_scale"] = 0.6
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	check(await wait_for(func(): return app.avatar.has_model() and app.motion.vrma_clips.size() == 8, 40), "avatar and motions ready")
	check(await wait_for(find_fixture, 15), "actual fixture detected by Windows source")
	if fixture.is_empty():
		await finish()
		return
	report["fixture_geometry"] = fixture.duplicate(true)
	report["world_snapshot"] = app.world_source.snapshot.duplicate(true)
	surface_line = ColorRect.new()
	surface_line.color = Color(0.25, 0.65, 1.0, 0.8)
	surface_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.ui_layer.add_child(surface_line)
	# Controlled placement stands on the actual detected window-top, equivalent to
	# the user placing the pet. Subsequent movement is produced by DesktopAutonomy.
	app._set_panel_open(false, false)
	await process_frame
	var anchors: Dictionary = app._projected_anchors()
	root.position = Vector2i(Vector2(float(fixture.x) + float(fixture.width) * 0.5, float(fixture.y)) - Vector2(anchors.foot))
	report["placement"] = {"window": str(root.position), "anchors": str(anchors)}
	check(await wait_for(attached_to_fixture, 14), "foot attaches to actual window top")
	await shot("foot-contact")
	var foot_before := Vector2(root.position) + Vector2(app._projected_anchors().foot)
	app._set_scale_target(0.8)
	check(await wait_for(func(): return absf(app.pet_scale() - 0.8) < 0.005, 5), "manual scale applies")
	var foot_after := Vector2(root.position) + Vector2(app._projected_anchors().foot)
	check(absf(foot_after.y - foot_before.y) < 3.0, "scale preserves support height")
	await shot("scaled-contact")
	app._set_scale_target(0.6)
	await create_timer(2.0).timeout
	# Request a lateral target and record the actual OS window position and foot height.
	var target := Vector2(float(fixture.x) + float(fixture.width) * 0.78, float(fixture.y))
	app.observe_interest("fixture-right", target, 1.0, 30.0, "owned_fixture")
	var requested: bool = app.autonomy.move_to_interest("fixture-right")
	check(requested, "surface target accepted")
	var x0 := root.position.x
	var end := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < end:
		update_line()
		var foot := Vector2(root.position) + Vector2(app._projected_anchors().foot)
		report.travel.append({"time_msec": Time.get_ticks_msec(), "window_x": root.position.x, "window_y": root.position.y,
			"foot_y": foot.y, "state": app.autonomy.state, "yaw": app.avatar.rotation.y, "motion": app.motion.current_gesture()})
		await process_frame
	check(absi(root.position.x - x0) > 40, "actual native window moved laterally")
	await shot("lateral-walk")
	app._set_panel_open(true, false)
	var paused_position := root.position
	await create_timer(1.0).timeout
	check(root.position == paused_position, "opening panel pauses actual movement")
	# Exercise the same sit request used by the panel button.
	app._request_sit()
	check(await wait_for(func(): return app.is_sitting() and attached_to_fixture() and str(app.autonomy.get_support_contact().get("pose")) == "sit", 18), "manual sit reattaches seat on window")
	await shot("seated-window")
	app.motion.play_gesture("idle_talking")
	await create_timer(1.0).timeout
	check(app.motion.current_contact_pose() == "sit", "talking retains seated contact")
	await shot("seated-talking")
	# Close only the owned fixture: attachment must be released.
	var stop := FileAccess.open(fixture_dir.path_join("fixture.stop"), FileAccess.WRITE)
	stop.store_string("stop")
	stop.close()
	check(await wait_for(func(): return not attached_to_fixture() and not app.is_sitting(), 8), "closed support detaches and stands")
	# Real monitor workarea floor, using the same source and OS window movement.
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	fixture = {"x": area.position.x, "y": area.end.y, "width": area.size.x}
	var floor_anchor := Vector2(app._projected_anchors().foot)
	root.position = Vector2i(Vector2(area.position.x + area.size.x * 0.4, area.end.y) - floor_anchor)
	check(await wait_for(func(): return bool(app.autonomy.get_support_contact().get("attached", false)) and str(app.autonomy.get_support_contact().get("surface_id", "")).begins_with("floor:"), 18), "actual workarea floor attaches")
	var floor_point := Vector2(root.position) + Vector2(app._projected_anchors().foot)
	check(absf(floor_point.y - area.end.y) < 2.0, "measured sole matches actual floor")
	check(absf(app.pet_rect.end.y - Vector2(app._projected_anchors().foot).y) < 0.1, "visible bounds and sole agree")
	await shot("floor-contact")
	var floor_x0 := root.position.x
	app.observe_interest("floor-right", Vector2(area.position.x + area.size.x * 0.65, area.end.y), 1.0, 30.0, "owned_floor_test")
	check(app.autonomy.move_to_interest("floor-right"), "actual floor lateral target accepted")
	check(await wait_for(func(): return absi(root.position.x - floor_x0) > 80, 8), "actual native window walks along floor")
	await shot("floor-walk")
	await finish()

func finish() -> void:
	app.autonomy.set_enabled(false)
	app.world_source.stop()
	check(not app.world_source.available and app.world_source._pid == -1, "owned geometry helper stopped")
	app.client.disconnect_ws()
	settings_node.data = original_settings
	settings_node.save_now()
	var failures := 0
	for entry in report.checks:
		if not entry.ok:
			failures += 1
	report["failures"] = failures
	report["renderer"] = RenderingServer.get_video_adapter_name()
	var f := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("WINDOWS_WORLD failures=", failures)
	quit(0 if failures == 0 else 1)
