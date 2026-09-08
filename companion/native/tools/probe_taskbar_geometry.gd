extends SceneTree
var passed := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var snapshot := {"version":1,"timestamp_msec":1000,"monitors":[{"id":"m","x":-1000,"y":0,"width":1000,"height":800,"work_x":-1000,"work_y":0,"work_width":1000,"work_height":760}],"windows":[],"taskbars":[{"id":"shell","class_name":"Shell_TrayWnd","x":-1000,"y":760,"width":1000,"height":40,"z":1}]}
	check(DesktopWorldSource.is_valid_snapshot(snapshot), "taskbar metadata accepted")
	var converted := DesktopWorldSource.to_godot_coordinates(snapshot)
	check(converted.taskbars[0].x == 0 and converted.monitors[0].x == 0, "taskbar monitor origin conversion consistent")
	var geometry := DesktopSurfaces.new()
	geometry.set_world_snapshot(converted)
	var surfaces := geometry.get_surfaces()
	check(surfaces.size() == 1 and surfaces[0].kind == "taskbar" and str(surfaces[0].id).begins_with("taskbar:"), "positive shell replaces coincident floor")
	converted.windows = [{"id":"foreground","x":400,"y":700,"width":200,"height":90,"z":0}]
	geometry.set_world_snapshot(converted)
	var bars := geometry.get_surfaces().filter(func(line): return line.kind == "taskbar")
	check(bars.size() == 2 and bars[0].x2 == 400 and bars[1].x1 == 600, "foreground rectangle cuts taskbar support")
	converted.windows = [{"id":"back","x":100,"y":100,"width":200,"height":400,"z":2},{"id":"front","x":50,"y":250,"width":100,"height":100,"z":0}]
	geometry.set_world_snapshot(converted)
	var edges := geometry.get_contact_edges().filter(func(edge): return edge.source_id == "window:back" and edge.side == "left")
	check(edges.size() == 2 and edges[0].b == Vector2(100,250) and edges[1].a == Vector2(100,350), "foreground rectangle cuts vertical edge")
	check(edges[0].normal == Vector2.LEFT and edges[0].timestamp_msec == 1000, "wall edge normal and freshness explicit")
	converted.taskbars.clear()
	geometry.set_world_snapshot(converted)
	check(geometry.get_surfaces().filter(func(line): return line.kind == "taskbar").is_empty(), "workarea margin never fabricates taskbar")
	var path := "res://../logs/taskbar-geometry.json"
	if FileAccess.file_exists(path):
		var actual = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(DesktopWorldSource.is_valid_snapshot(actual), "actual Windows metadata valid")
		check(not actual.taskbars.is_empty(), "actual Windows shell taskbars detected")
		var ids: Array = actual.windows.map(func(window): return window.id)
		check(actual.taskbars.all(func(bar): return not ids.has(bar.id)), "shell bars excluded from ordinary windows")
		geometry.set_world_snapshot(DesktopWorldSource.to_godot_coordinates(actual))
		check(not geometry.get_surfaces().filter(func(line): return line.kind == "taskbar").is_empty(), "actual shell geometry produces visible support")
	geometry.get_surfaces()
	var builds := geometry.geometry_builds
	var refreshed := geometry._snapshot.duplicate(true)
	refreshed.timestamp_msec = 2000
	geometry.set_world_snapshot(refreshed)
	geometry.get_surfaces()
	check(geometry.geometry_builds == builds, "timestamp heartbeat reuses geometry cache")
	refreshed.windows.append({"id":"new","x":20,"y":20,"width":100,"height":100,"z":0})
	geometry.set_world_snapshot(refreshed)
	geometry.get_surfaces()
	check(geometry.geometry_builds == builds+1, "changed geometry invalidates cache")
	var started := Time.get_ticks_usec()
	for index in 1000: geometry.get_surfaces()
	print("cached surface query mean_us: %.3f" % (float(Time.get_ticks_usec()-started)/1000.0))
	print("taskbar geometry: %d passed, %d failed" % [passed,failures.size()])
	for failure in failures: print("FAIL: "+failure)
	quit(0 if failures.is_empty() else 1)
