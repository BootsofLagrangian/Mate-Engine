extends RefCounted
## Pure persistence and monitor placement model. Screens are usable Rect2/Rect2i areas.
## clamp_position returns null when no single screen can contain the full object.
const MAX_OBJECTS := 8
const MAX_COORD := 100000
const MIN_SCALE := 0.5
const MAX_SCALE := 1.8
const APPEARANCES := ["default","warm","cool","porcelain","flat"]
const MAX_ID := 2147483646
var objects: Array[Dictionary] = []
var next_id: int = 1

static func catalogue() -> Array:
	return [
		{"type": "chair", "label": "의자", "verbs": ["inspect", "sit"], "description": "앉는 자세를 위한 의자입니다."},
		{"type": "sofa", "label": "소파", "verbs": ["inspect", "sit"], "description": "넓은 좌석에 앉는 자세를 위한 소파입니다."},
		{"type": "computer", "label": "컴퓨터 책상", "verbs": ["inspect", "use"], "description": "컴퓨터를 사용하는 자세를 위한 책상입니다."},
	]

static func base_size(type: String) -> Vector2i:
	match type:
		"chair": return Vector2i(260, 300)
		"sofa": return Vector2i(500, 340)
		"computer": return Vector2i(360, 300)
	return Vector2i.ZERO

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _label(value: Variant, fallback: String) -> String:
	if not value is String:
		return fallback
	var result := ""
	for character in value:
		var code: int = character.unicode_at(0)
		if code >= 32 and not (code >= 127 and code <= 159):
			result += character
	result = result.strip_edges().left(40)
	return fallback if result.is_empty() else result

static func _default_label(type: String) -> String:
	for entry in catalogue():
		if entry.type == type:
			return entry.label
	return "Object"

static func _id_number(value: Variant) -> int:
	if not value is String or not value.begins_with("obj_"):
		return 0
	var suffix: String = value.substr(4)
	if suffix.is_empty() or suffix.length() > 10 or not suffix.is_valid_int():
		return 0
	var number := suffix.to_int()
	if number < 1 or number > MAX_ID or str(number) != suffix:
		return 0
	return number

func set_data(value: Variant) -> void:
	objects.clear()
	next_id = 1
	if not value is Dictionary or value.get("version", 1) != 1:
		return
	var incoming: Variant = value.get("objects", [])
	if not incoming is Array:
		return
	var counter: Variant = value.get("next_id", 1)
	if _number(counter) and float(counter) >= 1 and float(counter) <= MAX_ID + 1:
		next_id = int(counter)
	var seen := {}
	for item in incoming:
		if not item is Dictionary:
			continue
		var number := _id_number(item.get("id"))
		if number == 0:
			continue
		# Even discarded records reserve their IDs, so removed/corrupt IDs cannot return.
		next_id = maxi(next_id, number + 1)
		if seen.has(item.id):
			continue
		seen[item.id] = true
		var type: Variant = item.get("type")
		if not type is String or base_size(type) == Vector2i.ZERO:
			continue
		var x: Variant = item.get("x")
		var y: Variant = item.get("y")
		if not _number(x) or not _number(y) or absf(float(x)) > MAX_COORD or absf(float(y)) > MAX_COORD:
			continue
		var scale_value: Variant = item.get("scale", 1.0)
		if not _number(scale_value):
			continue
		var visible_value: Variant = item.get("visible", true)
		if not visible_value is bool:
			visible_value = true
		if objects.size() < MAX_OBJECTS:
			objects.append({"id": item.id, "type": type, "label": _label(item.get("label"), _default_label(type)), "x": int(x), "y": int(y), "scale": clampf(float(scale_value), MIN_SCALE, MAX_SCALE), "visible": visible_value,"yaw_deg":clampf(float(item.get("yaw_deg",0.0)),-180.0,180.0) if _number(item.get("yaw_deg",0.0)) else 0.0,"appearance":str(item.get("appearance","default")) if item.get("appearance","default") in APPEARANCES else "default"})

			if valid_position_m(item.get("position_m")): objects[-1]["position_m"] = item.position_m.duplicate()
			if _number(item.get("spatial_unit_scale")) and .001 <= float(item.spatial_unit_scale) and float(item.spatial_unit_scale) <= 100.0: objects[-1]["spatial_unit_scale"] = float(item.spatial_unit_scale)

func data() -> Dictionary:
	return {"version": 1, "next_id": next_id, "objects": objects.duplicate(true)}

func get_object(id: String) -> Dictionary:
	for item in objects:
		if item.id == id:
			return item.duplicate(true)
	return {}

func has_object(id: String) -> bool:
	return not get_object(id).is_empty()

func rect_for(record: Dictionary) -> Rect2i:
	var size := base_size(str(record.get("type", "")))
	var scale_value := float(record.get("scale", 1.0))
	return Rect2i(Vector2i(int(record.get("x", 0)), int(record.get("y", 0))), Vector2i(roundi(size.x * scale_value), roundi(size.y * scale_value)))

static func _screen_rect(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value
	if value is Rect2:
		if not value.position.is_finite() or not value.size.is_finite():
			return Rect2i()
		# Round inward so fractional usable bounds never leak a pixel.
		var start := Vector2i(ceili(value.position.x), ceili(value.position.y))
		var end := Vector2i(floori(value.end.x), floori(value.end.y))
		return Rect2i(start, end - start)
	return Rect2i()

func clamp_position(position: Vector2i, size: Vector2i, screens: Array) -> Variant:
	if absi(position.x) > MAX_COORD or absi(position.y) > MAX_COORD or size.x <= 0 or size.y <= 0:
		return null
	var best: Variant = null
	var distance := INF
	for screen in screens:
		var area := _screen_rect(screen)
		if area.size.x < size.x or area.size.y < size.y:
			continue
		var low := Vector2i(maxi(area.position.x, -MAX_COORD), maxi(area.position.y, -MAX_COORD))
		var high := Vector2i(mini(area.end.x - size.x, MAX_COORD), mini(area.end.y - size.y, MAX_COORD))
		if low.x > high.x or low.y > high.y:
			continue
		var candidate := Vector2i(clampi(position.x, low.x, high.x), clampi(position.y, low.y, high.y))
		var candidate_distance := Vector2(position).distance_squared_to(Vector2(candidate))
		if candidate_distance < distance:
			best = candidate
			distance = candidate_distance
	return best

func add_object(type: String, position: Vector2i, screens: Array) -> String:
	if objects.size() >= MAX_OBJECTS or next_id > MAX_ID or base_size(type) == Vector2i.ZERO:
		return ""
	var placed: Variant = clamp_position(position, base_size(type), screens)
	if placed == null:
		return ""
	var id := "obj_%d" % next_id
	next_id += 1
	objects.append({"id": id, "type": type, "label": _default_label(type), "x": placed.x, "y": placed.y, "scale": 1.0, "visible": true,"yaw_deg":0.0,"appearance":"default"})
	return id

func rename_object(id: String, label: String) -> bool:
	for item in objects:
		if item.id == id:
			item.label = _label(label, _default_label(item.type))
			return true
	return false

func move_object(id: String, position: Vector2i, screens: Array) -> bool:
	for item in objects:
		if item.id == id:
			var placed: Variant = clamp_position(position, rect_for(item).size, screens)
			if placed == null:
				return false
			item.x = placed.x
			item.y = placed.y
			return true
	return false

func resize_object(id: String, scale_value: float, screens: Array) -> bool:
	if not is_finite(scale_value) or scale_value < MIN_SCALE or scale_value > MAX_SCALE:
		return false
	for item in objects:
		if item.id == id:
			var resized: Dictionary = item.duplicate(true)
			resized.scale = scale_value
			var placed: Variant = clamp_position(Vector2i(item.x, item.y), rect_for(resized).size, screens)
			if placed == null:
				return false
			item.scale = scale_value
			item.x = placed.x
			item.y = placed.y
			return true
	return false

func remove_object(id: String) -> bool:
	for index in objects.size():
		if objects[index].id == id:
			objects.remove_at(index)
			return true
	return false

func set_object_visible(id: String, visible: bool) -> bool:
	for item in objects:
		if item.id == id:
			item.visible = visible
			return true
	return false

func rows(screens: Array) -> Array:
	var result: Array = []
	for item in objects:
		var row: Dictionary = item.duplicate(true)
		var fits := false
		for screen in screens:
			if _screen_rect(screen).encloses(rect_for(item)):
				fits = true
		row.status = "ready" if fits and item.visible else "parked"
		row.status_text = "보임" if row.status == "ready" else ("숨김" if not item.visible else "화면 밖 · 보류")
		for entry in catalogue():
			if entry.type == item.type:
				row.verbs = entry.verbs.duplicate()
		result.append(row)
	return result

func configure_object(id: String, yaw_deg: float, appearance: String) -> bool:
	if not is_finite(yaw_deg) or yaw_deg < -180.0 or yaw_deg > 180.0 or appearance not in APPEARANCES: return false
	for item in objects:
		if item.id == id:
			item.yaw_deg = yaw_deg
			item.appearance = appearance
			return true
	return false

## Canonical desktop scene metres; origin and world axes belong to the fixed
## virtual-camera workarea frame, not this object's native window or current eye.
const SPATIAL_FRAME := "desktop_scene_v1"
const MAX_POSITION_M := 20.0
static func valid_position_m(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3: return false
	for axis in ["x","y","z"]:
		if not _number(value.get(axis)) or absf(float(value[axis])) > MAX_POSITION_M: return false
	return true

func set_position_m(id: String, value: Vector3) -> bool:
	var position := {"x":value.x,"y":value.y,"z":value.z}
	if not valid_position_m(position): return false
	for item in objects:
		if item.id == id:
			item["position_m"] = position
			return true
	return false

func set_spatial_unit_scale(id: String, value: float) -> bool:
	if not is_finite(value) or value < .001 or value > 100.0: return false
	for item in objects:
		if item.id == id:
			item["spatial_unit_scale"] = value
			return true
	return false
