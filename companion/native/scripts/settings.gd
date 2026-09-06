extends Node
## Autoload "Settings": persisted user preferences under user://settings.json plus
## backend URL resolution (command line --backend, env, saved value, default).

const PATH := "user://settings.json"
const DEFAULT_BACKEND := "http://127.0.0.1:8876"
const DEFAULTS := {
	"backend_url": "",
	"character": "",
	"window_x": -1,
	"window_y": -1,
	"panel_open": true,
	"vad_enabled": false,
	"vad_threshold": 0.035,
	"mic_target_rate": 0,
	"mic_device": "",
	# Pet size multiplier, AutonomyBridge.SCALE_MIN..SCALE_MAX (0.35..1.25); 0.6 is a small desktop
	# pet. Scaling pivots on the foot (or the seat while sitting) so the support contact never moves.
	"pet_scale": 0.6,
	"volume_db": 0.0,
	"motion_intensity": 1.0,
	"motion_speed": 1.0,
	"motion_repeat": 1,
	"idle_gaze": true,
	"show_subtitles": true,
	# window_x/window_y are only meaningful when window_pos_saved is true: negative values are
	# valid global desktop coordinates on multi-monitor setups (monitors left of/above the primary).
	"window_pos_saved": false,
	# Desktop roaming (desktop_autonomy.gd). Enabled by default, but the host only lets it move in
	# collapsed pet mode: an open panel, recording, speech, dragging or a live turn always pause it.
	"autonomy_enabled": true,
	"autonomy_speed": 75.0,
	# Desktop surfaces (desktop_surfaces.gd + desktop_world_source.gd): walk horizontally on window
	# tops / the taskbar floor and sit on edges. Window geometry (positions only, never contents)
	# comes from the Windows helper; elsewhere only the monitor work-area floor exists. Off = the
	# free-roaming behaviour above.
	"surface_roam": true,
	# "" = procedural idle only; "auto" = idle_natural when imported; or an explicit VRMA loop name.
	# Any imported loop is used as ambient idle only through the motion owner's ambient API that
	# blends under gestures/gaze/IK (see AutonomyBridge.ambient_idle_choice).
	"idle_clip": "auto",
	# Liveliness (behavior tab "행동"): may the pet act on its own toward the user's interest points
	# (walk over / look at them, rest)? Off = the roaming above only, no named intentions.
	"behavior_enabled": true,
	# InterestPoints.sanitized_data(): {"points": [{id,label,kind,x,y}...], "next_id": n}. x/y are
	# global desktop pixels (negative on monitors left of/above the primary); the id counter is
	# persisted so removed ids are never reused. Always re-sanitized by InterestPoints.set_points.
	"interest_points": {"points": [], "next_id": 1},
	# Desktop living-space objects (experimental; owned/persisted by the objects host, not the panel):
	# {"version": 1, "next_id": n, "objects": [{id,label,type,x,y,scale,visible}...]}. Empty by
	# default; only an explicit "추가" in the 공간 tab creates one.
	"desktop_objects": {"version": 1, "next_id": 1, "objects": []},
}

var data: Dictionary = {}
var _dirty := false
var _save_timer: Timer


func _ready() -> void:
	data = DEFAULTS.duplicate(true)
	_load()
	_save_timer = Timer.new()
	_save_timer.wait_time = 0.75
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_flush)
	add_child(_save_timer)


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for k in json.data.keys():
			data[k] = json.data[k]


func get_value(key: String, fallback: Variant = null) -> Variant:
	if data.has(key):
		return data[key]
	return DEFAULTS.get(key, fallback)


func set_value(key: String, value: Variant) -> void:
	if data.get(key) == value:
		return
	data[key] = value
	_dirty = true
	if _save_timer and is_inside_tree():
		_save_timer.start()


func _flush() -> void:
	if not _dirty:
		return
	_dirty = false
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


func save_now() -> void:
	_dirty = true
	_flush()


## Priority: --backend=URL / --backend URL argument, MATE_BACKEND_URL or MATE_BACKEND env, saved, default.
func backend_url() -> String:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for i in args.size():
		var a := args[i]
		if a.begins_with("--backend="):
			return _clean_url(a.substr(10))
		if a == "--backend" and i + 1 < args.size():
			return _clean_url(args[i + 1])
	for env_name in ["MATE_BACKEND_URL", "MATE_BACKEND"]:
		if OS.has_environment(env_name):
			var v := OS.get_environment(env_name)
			if not v.strip_edges().is_empty():
				return _clean_url(v)
	var saved := str(get_value("backend_url", ""))
	if not saved.strip_edges().is_empty():
		return _clean_url(saved)
	return DEFAULT_BACKEND


func backend_source() -> String:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for i in args.size():
		if args[i].begins_with("--backend=") or (args[i] == "--backend" and i + 1 < args.size()):
			return "argv"
	for env_name in ["MATE_BACKEND_URL", "MATE_BACKEND"]:
		if OS.has_environment(env_name) and not OS.get_environment(env_name).strip_edges().is_empty():
			return "env"
	if not str(get_value("backend_url", "")).strip_edges().is_empty():
		return "saved"
	return "default"


static func _clean_url(u: String) -> String:
	u = u.strip_edges()
	if not (u.begins_with("http://") or u.begins_with("https://")):
		u = "http://" + u
	return u.trim_suffix("/")


static func ws_url_for(http_url: String) -> String:
	var u := http_url.trim_suffix("/")
	if u.begins_with("https://"):
		return "wss://" + u.substr(8) + "/ws"
	if u.begins_with("http://"):
		return "ws://" + u.substr(7) + "/ws"
	return "ws://" + u + "/ws"
