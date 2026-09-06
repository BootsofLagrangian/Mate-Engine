extends SceneTree
const Source = preload("res://scripts/desktop_world_source.gd")
var checks := 0
var failures := 0
var source
var events: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func write(text: String) -> void:
	var file := FileAccess.open(source._snapshot_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
func _initialize() -> void:
	source = Source.new()
	source._snapshot_path = OS.get_cache_dir().path_join("mate-reader-test-%d.json" % OS.get_process_id())
	source.snapshot_changed.connect(func(snapshot): events.append(snapshot))
	var good := {"version":1,"timestamp_msec":10000,"monitors":[],"windows":[{"id":"window","x":0,"y":0,"width":100,"height":100,"z":0}]}
	write(JSON.stringify(good))
	source._read_snapshot(10000)
	check(source.available and events.size()==1,"valid geometry accepted")
	for invalid in ["", "{\"version\":1,", "{}", "null"]:
		write(invalid)
		source._read_snapshot(12000)
		check(source.available and source.snapshot.windows.size()==1 and events.size()==1 and source._last_timestamp==10000,"transient invalid publication retains original freshness")
	DirAccess.remove_absolute(source._snapshot_path)
	source._read_snapshot(15000)
	check(source.available and events.size()==1,"missing read at existing inclusive TTL retains geometry")
	source._read_snapshot(15001)
	check(not source.available and source.snapshot.is_empty() and events.size()==2 and events.back().is_empty(),"missing reads expire exactly after original TTL")
	source._read_snapshot(16000)
	check(events.size()==2,"repeated invalid reads do not emit repeated detachments")
	good.timestamp_msec = 17000
	write(JSON.stringify(good))
	source._read_snapshot(17000)
	check(source.available and events.size()==3,"valid recovery restores geometry")
	good.timestamp_msec = 17001
	good.windows = []
	write(JSON.stringify(good))
	source._read_snapshot(17001)
	check(source.available and source.snapshot.windows.is_empty() and events.size()==4,"valid empty window list applies immediately")
	write("{")
	source._read_snapshot(22002)
	check(not source.available and source.snapshot.is_empty() and events.size()==5,"malformed content expires rather than extending empty snapshot TTL")
	DirAccess.remove_absolute(source._snapshot_path)
	source.free()
	print("Snapshot reader: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
