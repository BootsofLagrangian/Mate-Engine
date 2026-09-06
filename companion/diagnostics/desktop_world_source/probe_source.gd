extends SceneTree
const Source = preload("res://scripts/desktop_world_source.gd")
func _initialize() -> void:
	root.hide()
	call_deferred("run")
func run() -> void:
	create_timer(22.0).timeout.connect(func(): push_error("SOURCE_TIMEOUT"); quit(1))
	var source := Source.new()
	root.add_child(source)
	var valid := {"version":1,"timestamp_msec":123,"monitors":[{"id":"display","x":-1920,"y":0,"width":1920,"height":1080,"work_x":-1920,"work_y":0,"work_width":1920,"work_height":1040}],"windows":[{"id":"12:AB","x":-100,"y":30,"width":600,"height":400,"z":3}]}
	assert(Source.is_valid_snapshot(valid))
	var shifted: Dictionary = Source.to_godot_coordinates(valid)
	assert(shifted["monitors"][0]["x"] == 0)
	assert(shifted["monitors"][0]["work_x"] == 0)
	assert(shifted["windows"][0]["x"] == 1820)
	assert(valid["monitors"][0]["x"] == -1920) # Input is preserved.
	var above: Dictionary = valid.duplicate(true)
	above["monitors"][0]["y"] = -1080
	above["monitors"][0]["work_y"] = -1080
	assert(Source.to_godot_coordinates(above)["windows"][0]["y"] == 1110)
	for key in ["version", "timestamp_msec", "monitors", "windows"]:
		var bad: Dictionary = valid.duplicate(true)
		bad.erase(key)
		assert(not Source.is_valid_snapshot(bad))
	var bad: Dictionary = valid.duplicate(true)
	bad["windows"][0]["width"] = -1
	assert(not Source.is_valid_snapshot(bad))
	bad = valid.duplicate(true)
	bad["windows"][0]["x"] = NAN
	assert(not Source.is_valid_snapshot(bad))
	if OS.get_name() == "Windows":
		assert(source.start())
		var helper_pid: int = source._pid
		var cache_directory: String = source._directory
		for i in 15:
			await create_timer(1.0).timeout
			if source.available: break
		assert(source.available, source.last_error)
		assert(Source.is_valid_snapshot(source.snapshot))
		assert(not source.snapshot["monitors"].is_empty())
		if DisplayServer.get_name() == "Windows":
			assert(source.snapshot["monitors"].size() == DisplayServer.get_screen_count())
			for i in DisplayServer.get_screen_count():
				var expected := DisplayServer.screen_get_usable_rect(i)
				var found := false
				for monitor in source.snapshot["monitors"]:
					var actual := Rect2i(int(monitor["work_x"]),int(monitor["work_y"]),int(monitor["work_width"]),int(monitor["work_height"]))
					if actual == expected: found = true
				assert(found, "Helper workarea differs from Godot DisplayServer")
			print("WINDOWS_COORDINATES_PASS all workareas equal DisplayServer")
		var first_stamp: int = int(source.snapshot["timestamp_msec"])
		await create_timer(2.2).timeout
		assert(int(source.snapshot["timestamp_msec"]) > first_stamp)
		source.stop()
		assert(not OS.is_process_running(helper_pid))
		assert(not DirAccess.dir_exists_absolute(cache_directory))
		assert(source.snapshot.is_empty())
		print("WINDOWS_SOURCE_PASS persistent snapshots, monitor geometry, owned child and cache cleanup")
	else:
		assert(not source.start())
		assert(not source.available)
		assert(source._pid == -1)
		source.stop()
		print("LINUX_SOURCE_PASS contract validation, unavailable, no child")
	source.free()
	quit()
