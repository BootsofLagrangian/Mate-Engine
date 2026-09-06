class_name MotionBank
extends RefCounted
## Parser/sampler for the shared additive motion bank
## (Assets/StreamingAssets/cheval-motions.json shape, served by GET /motions).
##
## Values are additive local Euler degrees (Unity/VRM authored semantics:
## +x pitches the bone forward/down, +y turns toward the character's right,
## +z rolls the top toward the character's left). Conversion into Godot bone
## space happens in VrmAvatar; this class stays coordinate agnostic.

const ALLOWED_BONES: Array[String] = [
	"hips", "spine", "chest", "upperChest", "neck", "head", "leftEye", "rightEye", "jaw",
	"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
	"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
	"leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes",
	"rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes",
	"leftThumbMetacarpal", "leftThumbProximal", "leftThumbDistal",
	"leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal",
	"leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal",
	"leftRingProximal", "leftRingIntermediate", "leftRingDistal",
	"leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal",
	"rightThumbMetacarpal", "rightThumbProximal", "rightThumbDistal",
	"rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal",
	"rightMiddleProximal", "rightMiddleIntermediate", "rightMiddleDistal",
	"rightRingProximal", "rightRingIntermediate", "rightRingDistal",
	"rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal",
]
## Bones exposed in the keyframe editor (the ones the bank already uses plus torso).
const EDITOR_BONES: Array[String] = [
	"head", "neck", "chest", "upperChest", "spine", "hips",
	"leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand",
	"rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand",
]
const MAX_ANGLE := 180.0
const MAX_DURATION := 20.0
const MAX_KEYS_PER_TRACK := 200
const MAX_STEPS := 12
const INTENSITY_RANGE := Vector2(0.0, 1.5)
const SPEED_RANGE := Vector2(0.5, 2.0)
const REPEAT_RANGE := Vector2i(1, 3)

var version: int = 1
var description: String = ""
var motions: Dictionary = {} # name -> motion Dictionary
var order: Array[String] = []
var errors: Array[String] = []


static func parse(data: Variant) -> MotionBank:
	var bank := MotionBank.new()
	if typeof(data) != TYPE_DICTIONARY:
		bank.errors.append("bank root is not an object")
		return bank
	bank.version = int(data.get("version", 1))
	bank.description = str(data.get("description", ""))
	var list: Variant = data.get("motions", [])
	if typeof(list) != TYPE_ARRAY:
		bank.errors.append("motions is not an array")
		return bank
	for entry in list:
		var problems := validate_motion(entry)
		if not problems.is_empty():
			var label := str(entry.get("name", "?")) if typeof(entry) == TYPE_DICTIONARY else "?"
			bank.errors.append("%s: %s" % [label, ", ".join(problems)])
			continue
		var motion: Dictionary = normalize_motion(entry)
		if not bank.motions.has(motion["name"]):
			bank.order.append(motion["name"])
		bank.motions[motion["name"]] = motion
	if not bank.motions.has("idle"):
		bank.motions["idle"] = {"name": "idle", "duration": 1.0, "tracks": []}
		bank.order.push_front("idle")
	return bank


static func parse_json_text(text: String) -> MotionBank:
	var json := JSON.new()
	if json.parse(text) != OK:
		var bank := MotionBank.new()
		bank.errors.append("json: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return bank
	return parse(json.data)


## Returns a list of validation problems; empty means valid.
static func validate_motion(entry: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(entry) != TYPE_DICTIONARY:
		problems.append("motion is not an object")
		return problems
	var name := str(entry.get("name", ""))
	if name.is_empty() or not name.is_valid_ascii_identifier() or name.length() > 40:
		problems.append("invalid name")
	var duration := _to_float(entry.get("duration", NAN))
	if not is_finite(duration) or duration <= 0.0 or duration > MAX_DURATION:
		problems.append("duration out of range")
	var tracks: Variant = entry.get("tracks", [])
	if typeof(tracks) != TYPE_ARRAY:
		problems.append("tracks is not an array")
		return problems
	var seen := {}
	for track in tracks:
		if typeof(track) != TYPE_DICTIONARY:
			problems.append("track is not an object")
			continue
		var bone := str(track.get("bone", ""))
		if not ALLOWED_BONES.has(bone):
			problems.append("unknown bone '%s'" % bone)
			continue
		if seen.has(bone):
			problems.append("duplicate track '%s'" % bone)
		seen[bone] = true
		var keys: Variant = track.get("keys", [])
		if typeof(keys) != TYPE_ARRAY or keys.is_empty():
			problems.append("track '%s' has no keys" % bone)
			continue
		if keys.size() > MAX_KEYS_PER_TRACK:
			problems.append("track '%s' has too many keys" % bone)
			continue
		var last_time := -1.0
		for i in keys.size():
			var key: Variant = keys[i]
			if typeof(key) != TYPE_DICTIONARY:
				problems.append("track '%s' key %d is not an object" % [bone, i])
				break
			var t := _to_float(key.get("time", NAN))
			var v := Vector3(_to_float(key.get("x", 0.0)), _to_float(key.get("y", 0.0)), _to_float(key.get("z", 0.0)))
			if not is_finite(t) or t < 0.0 or (is_finite(duration) and t > duration + 0.0001):
				problems.append("track '%s' key %d time out of range" % [bone, i])
				break
			if t <= last_time:
				problems.append("track '%s' keys not strictly increasing" % bone)
				break
			last_time = t
			if not (v.is_finite()) or absf(v.x) > MAX_ANGLE or absf(v.y) > MAX_ANGLE or absf(v.z) > MAX_ANGLE:
				problems.append("track '%s' key %d angle out of range" % [bone, i])
				break
		var first: Variant = keys[0]
		var last: Variant = keys[keys.size() - 1]
		if typeof(first) == TYPE_DICTIONARY and typeof(last) == TYPE_DICTIONARY:
			if not _is_zero(first) or not _is_zero(last):
				problems.append("track '%s' must start and end at zero" % bone)
	return problems


static func normalize_motion(entry: Dictionary) -> Dictionary:
	var tracks: Array = []
	for track in entry.get("tracks", []):
		var keys: Array = []
		for key in track.get("keys", []):
			keys.append({
				"time": _to_float(key.get("time", 0.0)),
				"x": _to_float(key.get("x", 0.0)),
				"y": _to_float(key.get("y", 0.0)),
				"z": _to_float(key.get("z", 0.0)),
			})
		tracks.append({"bone": str(track["bone"]), "keys": keys})
	var motion := {"name": str(entry["name"]), "duration": _to_float(entry["duration"]), "tracks": tracks}
	if entry.has("custom"):
		motion["custom"] = bool(entry["custom"])
	return motion


static func sample_track(track: Dictionary, time: float) -> Vector3:
	var keys: Array = track["keys"]
	if keys.is_empty():
		return Vector3.ZERO
	var first: Dictionary = keys[0]
	if time <= first["time"]:
		return Vector3(first["x"], first["y"], first["z"])
	for i in range(1, keys.size()):
		var b: Dictionary = keys[i]
		if time <= b["time"]:
			var a: Dictionary = keys[i - 1]
			var span: float = b["time"] - a["time"]
			var u: float = 0.0 if span <= 0.0 else (time - a["time"]) / span
			u = u * u * (3.0 - 2.0 * u) # smoothstep, same as web/motion.js
			return Vector3(a["x"], a["y"], a["z"]).lerp(Vector3(b["x"], b["y"], b["z"]), u)
	var last: Dictionary = keys[keys.size() - 1]
	return Vector3(last["x"], last["y"], last["z"])


## Sample every track at [time] seconds. Returns {bone: Vector3(degrees)}; empty outside the clip.
static func sample_motion(motion: Dictionary, time: float) -> Dictionary:
	var out := {}
	if motion.is_empty() or time < 0.0 or time >= float(motion["duration"]):
		return out
	for track in motion["tracks"]:
		out[track["bone"]] = sample_track(track, time)
	return out


## Sample with performance parameters (intensity/speed/repeat). Returns {} when finished.
static func sample_performed(motion: Dictionary, elapsed: float, intensity: float, speed: float, repeat: int) -> Dictionary:
	intensity = clampf(intensity, INTENSITY_RANGE.x, INTENSITY_RANGE.y)
	speed = clampf(speed, SPEED_RANGE.x, SPEED_RANGE.y)
	repeat = clampi(repeat, REPEAT_RANGE.x, REPEAT_RANGE.y)
	var duration: float = float(motion["duration"]) / speed
	if elapsed < 0.0 or elapsed >= duration * repeat:
		return {}
	var local_t := fmod(elapsed, duration) * speed
	var out := sample_motion(motion, local_t)
	if not is_equal_approx(intensity, 1.0):
		for bone in out.keys():
			out[bone] = out[bone] * intensity
	return out


static func performed_duration(motion: Dictionary, speed: float, repeat: int) -> float:
	speed = clampf(speed, SPEED_RANGE.x, SPEED_RANGE.y)
	repeat = clampi(repeat, REPEAT_RANGE.x, REPEAT_RANGE.y)
	return float(motion["duration"]) / speed * repeat


func get_motion(name: String) -> Dictionary:
	return motions.get(name, {})


func has_motion(name: String) -> bool:
	return motions.has(name)


func names() -> Array[String]:
	return order.duplicate()


func to_dict() -> Dictionary:
	var list: Array = []
	for name in order:
		list.append(motions[name])
	return {"version": version, "description": description, "motions": list}


## Compose a reusable custom motion from ordered steps of existing presets.
## steps: [{name, intensity, speed, repeat}], returns a bank-format motion or {} with errors filled.
func compose_sequence(new_name: String, steps: Array, out_errors: Array[String]) -> Dictionary:
	if steps.is_empty() or steps.size() > MAX_STEPS:
		out_errors.append("sequence needs 1..%d steps" % MAX_STEPS)
		return {}
	var tracks := {} # bone -> keys Array
	var offset := 0.0
	for step in steps:
		var preset := get_motion(str(step.get("name", "")))
		if preset.is_empty():
			out_errors.append("unknown preset '%s'" % str(step.get("name", "")))
			return {}
		var intensity := clampf(_to_float(step.get("intensity", 1.0)), INTENSITY_RANGE.x, INTENSITY_RANGE.y)
		var speed := clampf(_to_float(step.get("speed", 1.0)), SPEED_RANGE.x, SPEED_RANGE.y)
		var repeat := clampi(int(step.get("repeat", 1)), REPEAT_RANGE.x, REPEAT_RANGE.y)
		var step_len: float = float(preset["duration"]) / speed
		for r in repeat:
			var base := offset + step_len * r
			for track in preset["tracks"]:
				var bone: String = track["bone"]
				if not tracks.has(bone):
					tracks[bone] = []
				var keys: Array = tracks[bone]
				for key in track["keys"]:
					var t: float = base + float(key["time"]) / speed
					var v := Vector3(key["x"], key["y"], key["z"]) * intensity
					if not keys.is_empty() and t <= float(keys[keys.size() - 1]["time"]) + 0.0005:
						# Coincident boundary key (previous clip ended at zero): keep one.
						keys[keys.size() - 1] = {"time": t, "x": v.x, "y": v.y, "z": v.z}
					else:
						keys.append({"time": t, "x": v.x, "y": v.y, "z": v.z})
		offset += step_len * repeat
	if offset > MAX_DURATION:
		out_errors.append("sequence too long (%.1fs > %.0fs)" % [offset, MAX_DURATION])
		return {}
	var track_list: Array = []
	for bone in tracks.keys():
		var keys: Array = tracks[bone]
		_ensure_zero_ends(keys, offset)
		track_list.append({"bone": bone, "keys": keys})
	var motion := {"name": new_name, "duration": snappedf(offset, 0.001), "tracks": track_list, "custom": true}
	var problems := validate_motion(motion)
	if not problems.is_empty():
		out_errors.append_array(problems)
		return {}
	return motion


## Build a bank-format motion from sparse user keyframes [{bone,time,x,y,z}].
static func from_keyframes(new_name: String, duration: float, keyframes: Array, out_errors: Array[String]) -> Dictionary:
	if keyframes.is_empty():
		out_errors.append("no keyframes")
		return {}
	var by_bone := {}
	for kf in keyframes:
		var bone := str(kf.get("bone", ""))
		if not ALLOWED_BONES.has(bone):
			out_errors.append("unknown bone '%s'" % bone)
			return {}
		if not by_bone.has(bone):
			by_bone[bone] = []
		by_bone[bone].append({
			"time": clampf(_to_float(kf.get("time", 0.0)), 0.0, duration),
			"x": clampf(_to_float(kf.get("x", 0.0)), -MAX_ANGLE, MAX_ANGLE),
			"y": clampf(_to_float(kf.get("y", 0.0)), -MAX_ANGLE, MAX_ANGLE),
			"z": clampf(_to_float(kf.get("z", 0.0)), -MAX_ANGLE, MAX_ANGLE),
		})
	var tracks: Array = []
	for bone in by_bone.keys():
		var keys: Array = by_bone[bone]
		keys.sort_custom(func(a, b): return a["time"] < b["time"])
		var dedup: Array = []
		for key in keys:
			if not dedup.is_empty() and is_equal_approx(dedup[dedup.size() - 1]["time"], key["time"]):
				dedup[dedup.size() - 1] = key
			else:
				dedup.append(key)
		_ensure_zero_ends(dedup, duration)
		tracks.append({"bone": bone, "keys": dedup})
	var motion := {"name": new_name, "duration": duration, "tracks": tracks, "custom": true}
	var problems := validate_motion(motion)
	if not problems.is_empty():
		out_errors.append_array(problems)
		return {}
	return motion


static func _ensure_zero_ends(keys: Array, duration: float) -> void:
	if keys.is_empty():
		keys.append({"time": 0.0, "x": 0.0, "y": 0.0, "z": 0.0})
	var first: Dictionary = keys[0]
	if first["time"] > 0.0005:
		keys.push_front({"time": 0.0, "x": 0.0, "y": 0.0, "z": 0.0})
	elif not _is_zero(first):
		keys[0] = {"time": 0.0, "x": 0.0, "y": 0.0, "z": 0.0}
	var last: Dictionary = keys[keys.size() - 1]
	if last["time"] < duration - 0.0005:
		keys.append({"time": duration, "x": 0.0, "y": 0.0, "z": 0.0})
	elif not _is_zero(last):
		keys[keys.size() - 1] = {"time": last["time"], "x": 0.0, "y": 0.0, "z": 0.0}


## ------------------------------------------------------------------ VRMA asset catalog
## GET /motion-assets -> {motions:[{name, kind:"vrma", duration, asset_url, sha256, loop?, description?}]}
## Entries are read-only clips (no Euler tracks): they are never edited by the keyframe composer.
## Returns normalized entries in catalog order; invalid entries are skipped into out_errors.

const ASSET_MAX_DURATION := 120.0


static func parse_asset_catalog(data: Variant, out_errors: Array[String]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if typeof(data) != TYPE_DICTIONARY:
		out_errors.append("catalog root is not an object")
		return entries
	var list: Variant = data.get("motions", [])
	if typeof(list) != TYPE_ARRAY:
		out_errors.append("motions is not an array")
		return entries
	var seen := {}
	for item in list:
		var problems := validate_asset_entry(item)
		if not problems.is_empty():
			var label := str(item.get("name", "?")) if typeof(item) == TYPE_DICTIONARY else "?"
			out_errors.append("%s: %s" % [label, ", ".join(problems)])
			continue
		var name := str(item["name"])
		if seen.has(name):
			out_errors.append("%s: duplicate" % name)
			continue
		seen[name] = true
		var entry := {
			"name": name,
			"kind": "vrma",
			"duration": _to_float(item["duration"]),
			"asset_url": str(item.get("asset_url", "/motion-assets/" + name)),
			"sha256": str(item["sha256"]).to_lower(),
			"loop": bool(item.get("loop", false)),
			# Description is the manifest's own wording (used for tooltips and LLM hints); the
			# native side never relabels clips (a dance is a dance, not a greeting).
			"description": str(item.get("description", "")).left(500),
		}
		entries.append(entry)
	return entries


static func validate_asset_entry(item: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(item) != TYPE_DICTIONARY:
		problems.append("entry is not an object")
		return problems
	var name := str(item.get("name", ""))
	if name.is_empty() or not name.is_valid_ascii_identifier() or name.length() > 40:
		problems.append("invalid name")
	if str(item.get("kind", "vrma")) != "vrma":
		problems.append("unsupported kind '%s'" % str(item.get("kind")))
	var duration := _to_float(item.get("duration", NAN))
	if not is_finite(duration) or duration <= 0.0 or duration > ASSET_MAX_DURATION:
		problems.append("duration out of range")
	var sha := str(item.get("sha256", ""))
	if not is_sha256_hex(sha):
		problems.append("invalid sha256")
	if item.has("loop") and typeof(item["loop"]) != TYPE_BOOL:
		problems.append("loop is not a bool")
	var url: Variant = item.get("asset_url", "/motion-assets/" + name)
	if typeof(url) != TYPE_STRING or str(url).is_empty() or str(url).contains(" "):
		problems.append("invalid asset_url")
	return problems


static func is_sha256_hex(text: String) -> bool:
	if text.length() != 64:
		return false
	for c in text.to_lower():
		if not (c >= "0" and c <= "9") and not (c >= "a" and c <= "f"):
			return false
	return true


static func _is_zero(key: Dictionary) -> bool:
	return is_zero_approx(_to_float(key.get("x", 0.0))) and is_zero_approx(_to_float(key.get("y", 0.0))) and is_zero_approx(_to_float(key.get("z", 0.0)))


static func _to_float(v: Variant) -> float:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			return float(v)
		TYPE_STRING:
			return float(v) if (v as String).is_valid_float() else NAN
		_:
			return NAN
