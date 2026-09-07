class_name DesktopWorldSource
extends Node
## Geometry-only Windows desktop source. Coordinates match Godot DisplayServer desktop pixels.
## A single hidden child polls at 1 Hz while enabled; no process-per-frame work.

signal snapshot_changed(snapshot: Dictionary)

const HELPER_PATH := "res://platform/windows_world.ps1"
const POLL_SECONDS := 1.0
const STALE_MSEC := 5000
var enabled := false
var available := false
var last_error := ""
var snapshot: Dictionary = {}
var _pid := -1
var _directory := ""
var _snapshot_path := ""
var _timer: Timer
var _last_timestamp := 0


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(_poll)
	add_child(_timer)
	if enabled:
		start()


func configure(value: bool) -> void:
	enabled = value
	if not value:
		stop()
	elif is_inside_tree():
		start()


func start() -> bool:
	enabled = true
	if _pid > 0:
		return true
	available = false
	if OS.get_name() != "Windows":
		last_error = "Desktop window geometry is available on Windows only."
		return false
	if not is_inside_tree() or _timer == null:
		last_error = "DesktopWorldSource must be added to the scene before starting."
		return false
	var helper := FileAccess.get_file_as_string(HELPER_PATH)
	if helper.is_empty():
		last_error = "Desktop geometry helper is missing."
		return false
	_directory = OS.get_cache_dir().path_join("mate-desktop-world-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		last_error = "Could not create desktop geometry cache."
		_directory = ""
		return false
	var script_path := _directory.path_join("windows_world.ps1")
	var file := FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not prepare desktop geometry helper."
		_cleanup_files()
		return false
	file.store_string(helper)
	file.close()
	_snapshot_path = _directory.path_join("snapshot.json")
	var powershell := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	_pid = OS.create_process(powershell, PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", script_path, "-OutputPath", _snapshot_path, "-OwnerPid", str(OS.get_process_id()), "-IntervalMsec", "1000"
	]), false)
	if _pid <= 0:
		last_error = "Could not start desktop geometry helper."
		_cleanup_files()
		return false
	last_error = ""
	_last_timestamp = 0
	_timer.start()
	return true


func stop() -> void:
	enabled = false
	if _timer:
		_timer.stop()
	if _pid > 0 and OS.is_process_running(_pid):
		# Only the exact child PID created by this node is terminated.
		OS.kill(_pid)
	_pid = -1
	available = false
	_last_timestamp = 0
	_cleanup_files()
	_clear_snapshot()


func _exit_tree() -> void:
	stop()


func _poll() -> void:
	if not enabled or _pid <= 0:
		return
	if not OS.is_process_running(_pid):
		last_error = "Desktop geometry helper exited."
		stop()
		return
	_read_snapshot(int(Time.get_unix_time_from_system() * 1000.0))


func _retain_or_expire(now_msec: int, reason: String) -> void:
	last_error = reason
	# A failed transport/parse is not evidence that desktop surfaces disappeared.
	# Retention never refreshes the last accepted geometry's freshness deadline.
	if _last_timestamp <= 0 or now_msec - _last_timestamp > STALE_MSEC:
		available = false
		_clear_snapshot()


func _read_snapshot(now_msec: int) -> void:
	var file := FileAccess.open(_snapshot_path, FileAccess.READ)
	if file == null:
		_retain_or_expire(now_msec, "Desktop geometry snapshot is temporarily unreadable.")
		return
	var payload := file.get_as_text()
	file.close()
	var decoder := JSON.new()
	if decoder.parse(payload) != OK or not is_valid_snapshot(decoder.data):
		_retain_or_expire(now_msec, "Invalid desktop geometry snapshot; waiting for next publication.")
		return
	var parsed: Dictionary = decoder.data
	var stamp := int(parsed["timestamp_msec"])
	if now_msec - stamp > STALE_MSEC:
		last_error = "Desktop geometry snapshot is stale."
		available = false
		_clear_snapshot()
		return
	if stamp == _last_timestamp and not snapshot.is_empty():
		last_error = ""
		available = true
		return
	_last_timestamp = stamp
	last_error = ""
	available = true
	snapshot = to_godot_coordinates(parsed)
	snapshot_changed.emit(snapshot.duplicate(true))


## Win32 uses primary-monitor origin; Godot Windows shifts by the minimum
## monitor origin (including zero). Translate once at this source boundary.
static func to_godot_coordinates(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var origin := Vector2.ZERO
	for monitor in result["monitors"]:
		origin = origin.min(Vector2(float(monitor["x"]), float(monitor["y"])))
	for monitor in result["monitors"]:
		monitor["x"] -= int(origin.x)
		monitor["y"] -= int(origin.y)
		monitor["work_x"] -= int(origin.x)
		monitor["work_y"] -= int(origin.y)
	for window in result["windows"]:
		window["x"] -= int(origin.x)
		window["y"] -= int(origin.y)
	return result


static func is_valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	if not _number(value.get("timestamp_msec")) or float(value["timestamp_msec"]) <= 0:
		return false
	if not value.get("monitors") is Array or not value.get("windows") is Array:
		return false
	if value["monitors"].size() > 64 or value["windows"].size() > 4096:
		return false
	for monitor in value["monitors"]:
		if not _valid_rect(monitor):
			return false
		for key in ["work_x", "work_y", "work_width", "work_height"]:
			if not _number(monitor.get(key)):
				return false
		if monitor["work_width"] <= 0 or monitor["work_height"] <= 0:
			return false
	for window in value["windows"]:
		if not _valid_rect(window) or not _number(window.get("z")) or window["z"] < 0:
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _valid_rect(value: Variant) -> bool:
	if not value is Dictionary or not value.get("id") is String or value["id"].is_empty():
		return false
	for key in ["x", "y", "width", "height"]:
		if not _number(value.get(key)):
			return false
	return value["width"] > 0 and value["height"] > 0


func _clear_snapshot() -> void:
	if not snapshot.is_empty():
		snapshot = {}
		snapshot_changed.emit({})


func _cleanup_files() -> void:
	if _directory.is_empty():
		return
	for name in ["windows_world.ps1", "snapshot.json", "snapshot.json.tmp", "snapshot.json.stop"]:
		var path := _directory.path_join(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_directory)
	_directory = ""
	_snapshot_path = ""
