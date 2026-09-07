class_name InterestPoints
extends Node
## User-named desktop interest points ("관심 지점") and their native marker windows.
##
## Data: at most MAX_POINTS persistent entries {id, label, kind, x, y}. x/y are Godot global desktop
## pixels (the same space as DisplayServer.window_get_position / mouse_get_position, negative
## origins allowed on multi-monitor desktops). IDs are stable ("pt_<n>", a counter that is never
## reused, persisted with the points), so the backend can refer to a point across renames/moves.
## The node is pure over its data: set_points() sanitizes whatever the settings file holds,
## sanitized_data() is what the host persists, catalog() is the backend-facing list without
## coordinates. The host owns persistence (Settings) and every movement decision.
##
## Markers: the user adds a point near the pet and then drags a small transparent always-on-top
## native window (one per point) to the desired place; the pin tip pixel IS the point. No global
## mouse hook, no screen capture, no window contents are read. Marker windows are created hidden
## and only shown when the host asked for them (set_markers_visible) and the display server can
## create native sub-windows that are not embedded in the main window (see markers_available()).
## Off-screen points are kept as data ("parked") and reported as such; they never get a marker
## and reachable() is false for them so the host never commands movement toward them.

signal changed
## A marker drag committed a new position for the point (also emits changed).
signal point_placed(id: String, position: Vector2i)
## Marker visibility or availability changed (markers_shown / marker_status()).
signal markers_changed

const MAX_POINTS := 8
const LABEL_MAX := 40
## |x|, |y| beyond this are treated as corrupt rather than as a far monitor.
const COORD_LIMIT := 100000
## Backend TARGET_KINDS minus "pointer" (which is a live cursor observation, not a saved point).
const KINDS := ["point", "prop", "window", "surface", "floor"]
const DEFAULT_KIND := "point"
const ID_PREFIX := "pt_"
## Marker window geometry: window.position + MARKER_TIP == the point (exact, integer pixels).
const MARKER_SIZE := Vector2i(36, 46)
const MARKER_TIP := Vector2i(18, 45)
## New points are staggered by this many pixels per existing point so stacked pins stay grabbable.
const ADD_STAGGER := 26

var _points: Array[Dictionary] = []
var _next_id := 1
var _markers: Dictionary = {} # id -> Marker
var markers_shown := false
## Host-supplied "near the pet" global point for new entries (Callable() -> Vector2 / Vector2i).
var anchor_provider: Callable
## Host/test-supplied usable screen rects (Callable() -> Array of Rect2i); defaults to DisplayServer.
var screen_provider: Callable


# ------------------------------------------------------------------ validation (static, pure)

static func is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 96:
		return false
	for c in id:
		var ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c in "_:./@-"
		if not ok:
			return false
	return true


static func sanitize_label(raw: Variant, fallback: String) -> String:
	var s := str(raw) if typeof(raw) == TYPE_STRING else ""
	var out := ""
	for c in s:
		if c.unicode_at(0) >= 32:
			out += c
	out = out.strip_edges()
	if out.length() > LABEL_MAX:
		out = out.substr(0, LABEL_MAX).strip_edges()
	return out if not out.is_empty() else fallback


static func sanitize_kind(raw: Variant) -> String:
	var k := str(raw) if typeof(raw) == TYPE_STRING else ""
	return k if KINDS.has(k) else DEFAULT_KIND


## Finite, bounded integer coordinate; returns null when the value is unusable.
static func sanitize_coord(raw: Variant) -> Variant:
	match typeof(raw):
		TYPE_INT:
			return raw if absi(raw) <= COORD_LIMIT else null
		TYPE_FLOAT:
			if not is_finite(raw) or absf(raw) > float(COORD_LIMIT):
				return null
			return int(roundf(raw))
		_:
			return null


## One entry from untrusted data -> {id,label,kind,x,y} or {} when it cannot be repaired.
static func sanitize_point(raw: Variant, fallback_label: String) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var id := str(raw.get("id", "")) if typeof(raw.get("id", "")) == TYPE_STRING else ""
	if not is_valid_id(id):
		return {}
	var x = sanitize_coord(raw.get("x", null))
	var y = sanitize_coord(raw.get("y", null))
	if x == null or y == null:
		return {}
	return {"id": id, "label": sanitize_label(raw.get("label", ""), fallback_label), "kind": sanitize_kind(raw.get("kind", "")), "x": int(x), "y": int(y)}


static func _id_number(id: String) -> int:
	if not id.begins_with(ID_PREFIX):
		return 0
	var tail := id.substr(ID_PREFIX.length())
	return int(tail) if tail.is_valid_int() and int(tail) > 0 else 0


# ------------------------------------------------------------------ data API

## Replace all points from persisted/untrusted data. Accepts the sanitized_data() dictionary
## {points, next_id} or a bare Array of points. Duplicates/invalid entries are dropped, the list is
## capped at MAX_POINTS, and the id counter never moves backwards. Emits changed only on a change.
func set_points(data: Variant) -> void:
	var raw_points: Array = []
	var raw_next := 0
	if typeof(data) == TYPE_DICTIONARY:
		if typeof(data.get("points", null)) == TYPE_ARRAY:
			raw_points = data["points"]
		var n = data.get("next_id", 0)
		if typeof(n) == TYPE_INT or (typeof(n) == TYPE_FLOAT and is_finite(n)):
			raw_next = int(n)
	elif typeof(data) == TYPE_ARRAY:
		raw_points = data
	var result: Array[Dictionary] = []
	var seen := {}
	var highest := 0
	for item in raw_points:
		if result.size() >= MAX_POINTS:
			break
		var p := sanitize_point(item, "지점 %d" % (result.size() + 1))
		if p.is_empty() or seen.has(p["id"]):
			continue
		seen[p["id"]] = true
		highest = maxi(highest, _id_number(p["id"]))
		result.append(p)
	var next := maxi(maxi(raw_next, highest + 1), _next_id) # never backwards, never reused
	var same := result == _points and next == _next_id
	_points = result
	_next_id = next
	if not same:
		_after_change()


## Persistable snapshot: {"points": [{id,label,kind,x,y}...], "next_id": int}. Always sanitized.
func sanitized_data() -> Dictionary:
	var out: Array = []
	for p in _points:
		out.append(p.duplicate())
	return {"points": out, "next_id": _next_id}


## Backend-facing list: only [{id,label,kind}], never coordinates.
func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _points:
		out.append({"id": p["id"], "label": p["label"], "kind": p["kind"]})
	return out


func points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _points:
		out.append(p.duplicate())
	return out


func count() -> int:
	return _points.size()


func is_full() -> bool:
	return _points.size() >= MAX_POINTS


func has_point(id: String) -> bool:
	return _index_of(id) >= 0


func get_point(id: String) -> Dictionary:
	var i := _index_of(id)
	return _points[i].duplicate() if i >= 0 else {}


func position_of(id: String) -> Vector2i:
	var i := _index_of(id)
	return Vector2i(int(_points[i]["x"]), int(_points[i]["y"])) if i >= 0 else Vector2i.ZERO


## Global point where a new marker should appear: the host's anchor (near the pet) or, without
## one, the main window centre; staggered so consecutive additions do not stack exactly.
func suggest_position() -> Vector2i:
	var base := Vector2i.ZERO
	if anchor_provider.is_valid():
		var v: Variant = anchor_provider.call()
		if typeof(v) == TYPE_VECTOR2 or typeof(v) == TYPE_VECTOR2I:
			base = Vector2i(v)
	elif DisplayServer.get_name() != "headless":
		base = DisplayServer.window_get_position() + DisplayServer.window_get_size() / 2
	return base + Vector2i(ADD_STAGGER * _points.size(), 0)


## Add a point; returns its id or "" when the list is full or the position is unusable.
func add_point(label: String, position: Variant = null, kind: String = DEFAULT_KIND) -> String:
	if is_full():
		return ""
	var pos: Vector2i = suggest_position() if position == null else Vector2i(position)
	var x = sanitize_coord(pos.x)
	var y = sanitize_coord(pos.y)
	if x == null or y == null:
		return ""
	var id := ID_PREFIX + str(_next_id)
	_next_id += 1
	_points.append({"id": id, "label": sanitize_label(label, "지점 %d" % _id_number(id)), "kind": sanitize_kind(kind), "x": int(x), "y": int(y)})
	_after_change()
	return id


func rename_point(id: String, label: String) -> bool:
	var i := _index_of(id)
	if i < 0:
		return false
	var clean := sanitize_label(label, str(_points[i]["label"]))
	if clean == str(_points[i]["label"]):
		return true
	_points[i]["label"] = clean
	_after_change()
	return true


func move_point(id: String, position: Vector2i) -> bool:
	var i := _index_of(id)
	if i < 0:
		return false
	var x = sanitize_coord(position.x)
	var y = sanitize_coord(position.y)
	if x == null or y == null:
		return false
	if int(_points[i]["x"]) == int(x) and int(_points[i]["y"]) == int(y):
		return true
	_points[i]["x"] = int(x)
	_points[i]["y"] = int(y)
	_after_change()
	return true


func remove_point(id: String) -> bool:
	var i := _index_of(id)
	if i < 0:
		return false
	_points.remove_at(i)
	_free_marker(id)
	_after_change()
	return true


func clear_points() -> void:
	if _points.is_empty():
		return
	_points.clear()
	_after_change()


# ------------------------------------------------------------------ screen validation

func screen_rects() -> Array:
	if screen_provider.is_valid():
		var v: Variant = screen_provider.call()
		if typeof(v) == TYPE_ARRAY:
			return v
		return []
	var out: Array = []
	for i in DisplayServer.get_screen_count():
		out.append(DisplayServer.screen_get_usable_rect(i))
	return out


## Inside a usable screen rect. x is half-open [left, right) like Rect2i.has_point, but y is closed
## [top, bottom]: a pin dropped exactly on the work-area floor (taskbar top) is a valid target,
## while the pixel column at the right edge already belongs to the next monitor or to nothing.
static func point_on_screens(point: Vector2i, screens: Array) -> bool:
	for r in screens:
		var rect: Rect2i
		if typeof(r) == TYPE_RECT2I:
			rect = r
		elif typeof(r) == TYPE_RECT2:
			rect = Rect2i(r)
		else:
			continue
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		if point.x >= rect.position.x and point.x < rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y:
			return true
	return false


## "ready" (inside a usable screen), "parked" (saved but off every current screen) or "missing".
func point_status(id: String) -> String:
	if not has_point(id):
		return "missing"
	return "ready" if point_on_screens(position_of(id), screen_rects()) else "parked"


## Only ready points may be handed to movement; parked ones stay saved until a monitor returns.
func reachable(id: String) -> bool:
	return point_status(id) == "ready"


static func status_text(status: String) -> String:
	match status:
		"ready":
			return "화면 안"
		"parked":
			return "화면 밖 · 보류"
	return "없음"


## Panel-facing rows: [{id,label,kind,x,y,status,status_text}] in stored order.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _points:
		var r := p.duplicate()
		r["status"] = point_status(str(p["id"]))
		r["status_text"] = status_text(r["status"])
		out.append(r)
	return out


# ------------------------------------------------------------------ markers (native windows)

## Native marker windows need real sub-windows that are NOT embedded in the main window: every
## descendant Window of an embedding viewport is embedded, so the host must turn the root's
## gui_embed_subwindows off (project display/window/subwindows/embed_subwindows=false, or
## get_tree().root.gui_embed_subwindows = false before the first marker). Reported, never forced.
func markers_available() -> bool:
	return marker_status()["ok"]


func marker_status() -> Dictionary:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		return {"ok": false, "reason": "이 환경에서는 표식 창을 띄울 수 없습니다"}
	if is_inside_tree() and get_tree().root.gui_embed_subwindows:
		return {"ok": false, "reason": "표식 창이 펫 창 안에 갇힙니다 (embed_subwindows 설정 필요)"}
	return {"ok": true, "reason": ""}


## Show/hide the pins. Marker nodes exist only while shown (one hidden node per ready point is
## created first; it becomes a real OS window only when markers_available()). Hiding frees them.
func set_markers_visible(on: bool) -> void:
	if on == markers_shown:
		if on:
			_sync_markers()
		return
	markers_shown = on
	if on:
		_sync_markers()
	else:
		_free_all_markers()
	markers_changed.emit()


func marker_count() -> int:
	return _markers.size()


func marker_for(id: String) -> Window:
	return _markers.get(id, null)


## Global window position that puts the pin tip exactly on the point.
static func marker_position_for(point: Vector2i) -> Vector2i:
	return point - MARKER_TIP


static func tip_of(window_position: Vector2i) -> Vector2i:
	return window_position + MARKER_TIP


## Pin outline in marker-window pixels, used for drawing and as the mouse passthrough polygon
## (clicks outside the pin fall through to whatever is under the transparent window).
static func pin_polygon() -> PackedVector2Array:
	var head := Vector2(MARKER_SIZE.x * 0.5, 15.0)
	var r := 14.0
	var poly := PackedVector2Array()
	# Traverse the remaining arc from lower-left through the top to lower-right,
	# then close through the tip. Appending the tip after a full top-started arc
	# would cross the polygon and fail renderer triangulation.
	for i in 25:
		var a := lerpf(PI * 0.68, TAU + PI * 0.32, float(i) / 24.0)
		poly.append(head + Vector2(cos(a), sin(a)) * r)
	poly.append(Vector2(MARKER_TIP))
	return poly


func _sync_markers() -> void:
	if not markers_shown:
		return
	var live := {}
	for i in _points.size():
		var p := _points[i]
		var id := str(p["id"])
		if not reachable(id):
			_free_marker(id) # parked: never place a window off every screen
			continue
		live[id] = true
		var m: Marker = _markers.get(id, null)
		if m == null:
			m = Marker.new(id)
			m.drag_finished.connect(_on_marker_dragged)
			m.dismissed.connect(_on_marker_dismissed)
			_markers[id] = m
			add_child(m)
		m.set_label(str(p["label"]), i + 1)
		if not m.dragging:
			m.position = marker_position_for(Vector2i(int(p["x"]), int(p["y"])))
		if markers_available() and not m.visible:
			m.show() # unfocusable: creation never takes focus from the user's app
	for id in _markers.keys():
		if not live.has(id):
			_free_marker(id)


func _on_marker_dragged(id: String, tip: Vector2i) -> void:
	if move_point(id, tip):
		point_placed.emit(id, tip)


func _on_marker_dismissed(_id: String) -> void:
	set_markers_visible(false)


func _free_marker(id: String) -> void:
	var m: Marker = _markers.get(id, null)
	if m == null:
		return
	_markers.erase(id)
	m.hide()
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	# queue_free: this may run from the marker's own close/drag signal handlers.
	m.queue_free()


func _free_all_markers() -> void:
	for id in _markers.keys():
		_free_marker(id)


func _index_of(id: String) -> int:
	for i in _points.size():
		if str(_points[i]["id"]) == id:
			return i
	return -1


func _after_change() -> void:
	_sync_markers()
	changed.emit()


func _exit_tree() -> void:
	_free_all_markers()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_all_markers()


# ------------------------------------------------------------------ marker window

## One small transparent always-on-top native window per point. Dragging moves the window with the
## global mouse position of our own window's events (no hook); release, focus loss or a close
## request end the drag and report the tip pixel as the new point position.
class Marker:
	extends Window
	signal drag_finished(id: String, tip: Vector2i)
	signal dismissed(id: String)

	var point_id: String
	var dragging := false
	var _grab := Vector2i.ZERO
	var _pin: PinControl

	func _init(id: String) -> void:
		point_id = id
		name = "Marker_" + id
		title = "Mate marker"
		visible = false # shown by InterestPoints only when native markers are available
		borderless = true
		always_on_top = true
		transparent = true
		transparent_bg = true
		unresizable = true
		unfocusable = true # never steal focus from the user's application on creation or drag
		popup_window = false
		size = InterestPoints.MARKER_SIZE
		min_size = InterestPoints.MARKER_SIZE
		max_size = InterestPoints.MARKER_SIZE
		mouse_passthrough_polygon = InterestPoints.pin_polygon()
		_pin = PinControl.new()
		_pin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pin.gui_input.connect(_on_gui_input)
		add_child(_pin)
		focus_exited.connect(_on_focus_lost)
		close_requested.connect(_on_close)
		mouse_exited.connect(_on_mouse_exited)

	func set_label(text: String, number: int) -> void:
		_pin.number = number
		_pin.label_text = text
		_pin.queue_redraw()

	func tip() -> Vector2i:
		return InterestPoints.tip_of(position)

	func drag_begin(global_mouse: Vector2i) -> void:
		dragging = true
		_grab = global_mouse - position
		_pin.active = true
		_pin.queue_redraw()

	func drag_update(global_mouse: Vector2i) -> void:
		if dragging:
			position = global_mouse - _grab

	## Ends the drag and reports the tip; the window position is authoritative even when the
	## release happened elsewhere (focus loss / close), so the saved point equals what is shown.
	func drag_end() -> void:
		if not dragging:
			return
		dragging = false
		_pin.active = false
		_pin.queue_redraw()
		drag_finished.emit(point_id, tip())

	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_begin(DisplayServer.mouse_get_position())
			else:
				drag_end()
		elif event is InputEventMouseMotion and dragging:
			drag_update(DisplayServer.mouse_get_position())

	func _on_mouse_exited() -> void:
		# Fast drags may leave the tiny window between motion events; the global cursor keeps
		# driving until a release or focus loss ends the drag.
		if dragging and (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) == 0:
			drag_end()

	func _on_focus_lost() -> void:
		drag_end()

	func _on_close() -> void:
		drag_end()
		dismissed.emit(point_id)


## Draws the pin (numbered head + tip) inside the marker window; nothing else is painted, so the
## rest of the window stays transparent and mouse-passthrough.
class PinControl:
	extends Control
	var number := 1
	var label_text := ""
	var active := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var poly := InterestPoints.pin_polygon()
		var fill := Color(0.98, 0.55, 0.25, 0.95) if active else Color(0.55, 0.45, 0.95, 0.92)
		draw_colored_polygon(poly, fill)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(1, 1, 1, 0.9), 1.5, true)
		var head := Vector2(InterestPoints.MARKER_SIZE.x * 0.5, 15.0)
		draw_circle(head, 8.0, Color(0.08, 0.06, 0.12, 0.85))
		var font := ThemeDB.fallback_font
		var text := str(number)
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		draw_string(font, head + Vector2(-ts.x * 0.5, ts.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		# The exact target pixel, so the user sees what is saved.
		draw_rect(Rect2(Vector2(InterestPoints.MARKER_TIP) - Vector2(0.5, 0.5), Vector2(1, 1)), Color(1, 1, 1, 1))
