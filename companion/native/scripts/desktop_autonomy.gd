class_name DesktopAutonomy
extends Node
## Desktop geometry only: no screen capture, recognition, input injection or file access.
## Positions use Godot DisplayServer desktop pixels; visible_bounds is window-local.
signal state_changed(state: String)
signal locomotion_changed(moving: bool, velocity: Vector2)
signal target_chosen(id: String, screen_point: Vector2, kind: String)
signal support_changed(contact: Dictionary)

const SurfaceGeometry = preload("desktop_surfaces.gd")

const MAX_INTERESTS := 24
const SETTLE_SECONDS := 2.5
const DECISION_SECONDS := 5.0
const TRAVEL_TIMEOUT := 35.0
const STEP := 1.0 / 120.0
const MARGIN := 4.0

var enabled := true
var speed := 75.0
var acceleration := 110.0
var state := "paused"
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var visible_bounds := Rect2(400, 120, 220, 560)
var target := Vector2.ZERO
var workareas: Array[Rect2] = []
var _window: Window
var _bounds_callback := Callable()
var _interests: Dictionary = {}
var _time := 0.0
var _settle_until := SETTLE_SECONDS
var _next_decision := SETTLE_SECONDS
var _state_until := 0.0
var _travel_until := 0.0
var _blocked := true
var _pointer_interaction := false
var _monitor_poll := 0.0
var _pointer_last := Vector2.INF
var _pointer_sample_at := 0.0
var _choice_index := 0
var _moving := false
var _simulation := false
var _needs_clamp := true
var surface_mode := false
var contact_pose := "foot"
var _surfaces = SurfaceGeometry.new()
var _anchors: Dictionary = {}
var _anchors_callback := Callable()
var _support: Dictionary = {}
var _pending_support: Dictionary = {}
var _locked_anchor := Vector2.ZERO
var _world_received_at := -INF
var _world_snapshot: Dictionary = {}
var _world_stale := false
var _using_fallback_monitors := true
var _preferred_surface_id := ""


func configure(host: Window, bounds_callback: Callable = Callable(), anchors_callback: Callable = Callable()) -> void:
	_window = host
	_bounds_callback = bounds_callback
	_anchors_callback = anchors_callback
	position = Vector2(host.position)
	_refresh_monitors()


func set_visible_bounds(bounds: Rect2) -> void:
	if bounds.size.x > 0 and bounds.size.y > 0 and bounds != visible_bounds:
		visible_bounds = bounds
		_needs_clamp = true
		if surface_mode:
			_validate_support()


func set_enabled(value: bool) -> void:
	enabled = value
	_interrupt()


func set_speed(pixels_per_second: float) -> void:
	speed = clampf(pixels_per_second, 20.0, 160.0)


func update_context(panel_open: bool, listening: bool, speaking: bool,
		dragging: bool, foreground_busy: bool) -> void:
	if dragging and surface_mode and (not _support.is_empty() or not _pending_support.is_empty()):
		_detach_support()
	var blocked := panel_open or listening or speaking or dragging or foreground_busy
	if blocked != _blocked:
		_blocked = blocked
		_interrupt()


func set_pointer_interaction(active: bool) -> void:
	if active != _pointer_interaction:
		_pointer_interaction = active
		_interrupt()


func observe_pointer(screen_point: Vector2) -> void:
	if not screen_point.is_finite() or _time < _pointer_sample_at:
		return
	_pointer_sample_at = _time + 4.0
	if not _pointer_last.is_finite() or screen_point.distance_to(_pointer_last) > 100.0:
		_pointer_last = screen_point
		observe_interest("pointer_history", screen_point, 0.45, 16.0, "pointer_history")


func observe_interest(id: String, screen_point: Vector2, confidence: float = 0.5,
		ttl: float = 20.0, kind: String = "external") -> void:
	if id.is_empty() or not screen_point.is_finite() or not is_finite(confidence) or not is_finite(ttl) or ttl <= 0:
		return
	_expire_interests()
	if not _interests.has(id) and _interests.size() >= MAX_INTERESTS:
		var oldest: String = _interests.keys()[0]
		for key: String in _interests:
			if float(_interests[key].expires) < float(_interests[oldest].expires):
				oldest = key
		_interests.erase(oldest)
	_interests[id] = {"point": screen_point, "confidence": clampf(confidence, 0.0, 1.0),
		"expires": _time + clampf(ttl, 0.1, 120.0), "kind": kind}


func move_to_interest(id: String) -> bool:
	_expire_interests()
	if not enabled or _blocked or _pointer_interaction or _time < _settle_until or not _interests.has(id):
		return false
	var entry: Dictionary = _interests[id]
	var destination := _nearest_safe_origin(Vector2(entry.point) - visible_bounds.get_center())
	if surface_mode:
		if _support.is_empty() or contact_pose != "foot":
			return false
		var span := _surface_origin_span(_support, _locked_anchor)
		destination = Vector2(clampf(Vector2(entry.point).x - _locked_anchor.x, span.x, span.y),
			float(_support.y) - _locked_anchor.y)
	if not destination.is_finite() or not _path_safe(position, destination):
		return false
	if position.distance_to(destination) < 24.0:
		_interests.erase(id)
		return false
	target = destination
	_travel_until = _time + TRAVEL_TIMEOUT
	_next_decision = _time + DECISION_SECONDS
	_interests.erase(id)
	_set_state("walk")
	target_chosen.emit(id, target + visible_bounds.get_center(), str(entry.kind))
	return true


func _process(delta: float) -> void:
	if _simulation or not is_instance_valid(_window):
		return
	if _bounds_callback.is_valid():
		set_visible_bounds(_bounds_callback.call())
	if _anchors_callback.is_valid():
		set_contact_anchors(_anchors_callback.call())
	_monitor_poll -= delta
	if _monitor_poll <= 0.0:
		_refresh_monitors()
		_monitor_poll = 1.0
	# External window dragging / panel placement is authoritative.
	if Vector2(_window.position).distance_to(position) > 2.0:
		position = Vector2(_window.position)
		_needs_clamp = true
		if surface_mode:
			_detach_support()
		_interrupt()
	observe_pointer(Vector2(DisplayServer.mouse_get_position()))
	advance(delta)
	if enabled and not _blocked and not _pointer_interaction and _time >= _settle_until:
		_window.position = Vector2i(position.round())


## Test hook: no DisplayServer or actual window mutation.
func configure_simulation(areas: Array[Rect2], origin: Vector2, bounds: Rect2) -> void:
	_simulation = true
	position = origin
	visible_bounds = bounds
	set_workareas(areas)


func set_workareas(areas: Array) -> void:
	var clean: Array[Rect2] = []
	for area in areas:
		if area.size.x > 0 and area.size.y > 0:
			clean.append(area)
	if clean != workareas:
		workareas = clean
		if _using_fallback_monitors or _world_stale:
			_surfaces.set_world_snapshot({"monitors": _fallback_monitors(), "windows": []})
		_needs_clamp = true
		if surface_mode:
			_detach_support()
		_interrupt()


func _refresh_monitors() -> void:
	var areas: Array[Rect2] = []
	for index in DisplayServer.get_screen_count():
		areas.append(Rect2(DisplayServer.screen_get_usable_rect(index)))
	set_workareas(areas)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0:
		return
	_time += delta
	_expire_interests()
	if surface_mode and not _world_stale and _time - _world_received_at > 5.0:
		_world_stale = true
		var stale_snapshot := _world_snapshot.duplicate(true)
		stale_snapshot["windows"] = []
		_surfaces.set_world_snapshot(stale_snapshot)
		_validate_support()
	if not enabled or _blocked or _pointer_interaction:
		_stop_motion()
		_set_state("paused")
		return
	if _time < _settle_until:
		_set_state("settle")
		return
	if _needs_clamp:
		_needs_clamp = false
		if not is_origin_safe(position):
			var safe := _nearest_safe_origin(position)
			if not safe.is_finite():
				_set_state("no_space")
				return
			# Only recovery after monitor/bounds change may reposition immediately.
			position = safe
			_stop_motion()
	if not is_origin_safe(position):
		_set_state("no_space")
		return
	if surface_mode and _support.is_empty() and _pending_support.is_empty():
		if _time >= _next_decision:
			_begin_surface_attach()
		return
	if state == "walk" or state == "approach":
		if _time >= _travel_until:
			_stop_motion()
			_pending_support.clear()
			_set_state("rest")
			_state_until = _time + 8.0
			_next_decision = _state_until
			return
		# Long scheduling stalls never become large desktop jumps. Wall clock TTLs
		# still advance fully, while movement catches up by at most 100 ms.
		var remaining := minf(delta, 0.1)
		while remaining > 0.000001 and (state == "walk" or state == "approach"):
			var dt := minf(remaining, STEP)
			_integrate(dt)
			remaining -= dt
	elif state == "inspect":
		if _time >= _state_until:
			_set_state("rest")
			_state_until = _time + 7.0
	elif state == "rest":
		if _time >= _state_until and _time >= _next_decision:
			_choose_target()
	else:
		if _time >= _next_decision:
			_choose_target()


func _integrate(dt: float) -> void:
	var offset := target - position
	var distance := offset.length()
	if distance < 0.8 and velocity.length() < acceleration * dt + 0.01:
		_stop_motion()
		if state == "approach":
			# Final subpixel contact correction is bounded to <0.8px.
			position = target
			_support = _pending_support.duplicate()
			_pending_support.clear()
			_emit_support()
		_set_state("inspect")
		_state_until = _time + 3.0
		return
	var desired_speed := minf(speed, sqrt(maxf(0.0, 2.0 * acceleration * maxf(0.0, distance - 0.6))))
	var desired := offset.normalized() * desired_speed
	velocity = velocity.move_toward(desired, acceleration * dt)
	var next := position + velocity * dt
	if not is_origin_safe(next):
		_stop_motion()
		_pending_support.clear()
		_set_state("rest")
		_state_until = _time + 8.0
		_next_decision = _state_until
		return
	position = next
	var moving := velocity.length() > 0.01
	if moving or moving != _moving:
		_moving = moving
		locomotion_changed.emit(moving, velocity)


func _choose_target() -> void:
	_next_decision = _time + DECISION_SECONDS
	var ids := _interests.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return float(_interests[a].confidence) > float(_interests[b].confidence))
	for id: String in ids:
		if move_to_interest(id):
			return
	if surface_mode:
		_choose_surface_target()
		return
	# Deterministic, widely spaced desktop landmarks; no per-frame random jitter.
	var candidates: Array[Vector2] = []
	for area in workareas:
		var safe := _origin_region(area)
		if safe.size.x < 0 or safe.size.y < 0:
			continue
		candidates.append(safe.position)
		candidates.append(Vector2(safe.end.x, safe.position.y))
		candidates.append(safe.end)
		candidates.append(Vector2(safe.position.x, safe.end.y))
	for attempt in candidates.size():
		var point := candidates[(_choice_index + attempt) % candidates.size()]
		if position.distance_to(point) < 100.0 or not _path_safe(position, point):
			continue
		_choice_index = (_choice_index + attempt + 1) % candidates.size()
		observe_interest("desktop_landmark", point + visible_bounds.get_center(), 0.2, 10.0, "desktop_geometry")
		if move_to_interest("desktop_landmark"):
			return
	_set_state("rest")
	_state_until = _time + 10.0


func _origin_region(area: Rect2) -> Rect2:
	return Rect2(area.position + Vector2.ONE * MARGIN - visible_bounds.position,
		area.size - visible_bounds.size - Vector2.ONE * MARGIN * 2.0)


func _nearest_safe_origin(origin: Vector2) -> Vector2:
	if is_origin_safe(origin):
		return origin
	var best := Vector2.INF
	var best_distance := INF
	for area in workareas:
		var region := _origin_region(area)
		if region.size.x < 0 or region.size.y < 0:
			continue
		var candidate := origin.clamp(region.position, region.end)
		var distance := origin.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Exact rectangle-union coverage, including adjacent monitors and negative origins.
func is_origin_safe(origin: Vector2) -> bool:
	var pet := Rect2(origin + visible_bounds.position, visible_bounds.size).grow(0.0 if surface_mode else MARGIN)
	var uncovered: Array[Rect2] = [pet]
	for area in workareas:
		var next: Array[Rect2] = []
		for piece in uncovered:
			var overlap := piece.intersection(area)
			if not overlap.has_area():
				next.append(piece)
				continue
			if overlap.position.x > piece.position.x:
				next.append(Rect2(piece.position, Vector2(overlap.position.x - piece.position.x, piece.size.y)))
			if overlap.end.x < piece.end.x:
				next.append(Rect2(Vector2(overlap.end.x, piece.position.y), Vector2(piece.end.x - overlap.end.x, piece.size.y)))
			if overlap.position.y > piece.position.y:
				next.append(Rect2(Vector2(overlap.position.x, piece.position.y), Vector2(overlap.size.x, overlap.position.y - piece.position.y)))
			if overlap.end.y < piece.end.y:
				next.append(Rect2(Vector2(overlap.position.x, overlap.end.y), Vector2(overlap.size.x, piece.end.y - overlap.end.y)))
		uncovered = next
		if uncovered.is_empty():
			return true
	return false


func _path_safe(from: Vector2, to: Vector2) -> bool:
	# Test all geometry boundary crossing times, plus each open interval midpoint.
	# Safety can change only when an edge of the pet crosses an area edge.
	var times: Array[float] = [0.0, 1.0]
	var displacement := to - from
	var bounds := visible_bounds.grow(0.0 if surface_mode else MARGIN)
	for area in workareas:
		for axis in 2:
			if absf(displacement[axis]) < 0.000001:
				continue
			for edge in [area.position[axis], area.end[axis]]:
				for pet_edge in [bounds.position[axis], bounds.end[axis]]:
					var t: float = (edge - from[axis] - pet_edge) / displacement[axis]
					if t > 0.0 and t < 1.0:
						times.append(t)
	times.sort()
	for i in times.size():
		if not is_origin_safe(from.lerp(to, times[i])):
			return false
		if i > 0 and not is_origin_safe(from.lerp(to, (times[i - 1] + times[i]) * 0.5)):
			return false
	return true


func _interrupt() -> void:
	_pending_support.clear()
	_stop_motion()
	_set_state("paused" if not enabled or _blocked or _pointer_interaction else "settle")
	_settle_until = _time + SETTLE_SECONDS
	_next_decision = _settle_until


func _stop_motion() -> void:
	velocity = Vector2.ZERO
	if _moving:
		_moving = false
		locomotion_changed.emit(false, velocity)


func _set_state(value: String) -> void:
	if state != value:
		state = value
		state_changed.emit(state)


func _expire_interests() -> void:
	for id: String in _interests.keys():
		if float(_interests[id].expires) <= _time:
			_interests.erase(id)


## Optional desktop-platform mode; free roaming remains the default API behavior.
func set_surface_mode(value: bool) -> void:
	if value == surface_mode:
		return
	surface_mode = value
	if value and _world_snapshot.is_empty():
		set_world_snapshot({})
	_detach_support()
	_interrupt()


func set_world_snapshot(snapshot: Dictionary) -> void:
	_world_snapshot = snapshot.duplicate(true)
	_using_fallback_monitors = _world_snapshot.get("monitors", []).is_empty()
	if _using_fallback_monitors:
		_world_snapshot["monitors"] = _fallback_monitors()
	_world_received_at = _time
	_world_stale = false
	_surfaces.set_world_snapshot(_world_snapshot)
	var areas: Array[Rect2] = []
	for monitor: Dictionary in snapshot.get("monitors", []):
		areas.append(Rect2(float(monitor.get("work_x", monitor.get("x", 0))),
			float(monitor.get("work_y", monitor.get("y", 0))),
			float(monitor.get("work_width", monitor.get("width", 0))),
			float(monitor.get("work_height", monitor.get("height", 0)))))
	if not areas.is_empty():
		set_workareas(areas)
	if surface_mode:
		_validate_support()


func set_authored_surfaces(lines: Array) -> void:
	_surfaces.set_authored_surfaces(lines)
	if surface_mode:
		_validate_support()


func set_contact_anchors(anchors: Dictionary) -> void:
	# The attached anchor is latched: animation foot noise must not shake the OS
	# window. Pose changes and substantial scale changes request a smooth re-seat.
	_anchors = anchors.duplicate()
	if surface_mode and (not _support.is_empty() or not _pending_support.is_empty()) and _anchor().distance_to(_locked_anchor) > 24.0:
		_detach_support()


func set_contact_pose(pose: String) -> void:
	if pose not in ["foot", "sit", "lean"] or pose == contact_pose:
		return
	if not _support.is_empty():
		_preferred_surface_id = str(_support.id)
	contact_pose = pose
	if surface_mode:
		_detach_support()


func get_support_contact() -> Dictionary:
	if _support.is_empty():
		return {"attached": false, "pose": contact_pose}
	return {"attached": true, "surface_id": str(_support.id), "kind": str(_support.kind),
		"pose": contact_pose, "screen_point": position + _locked_anchor,
		"local_anchor": _locked_anchor}


func _anchor() -> Vector2:
	var fallback := Vector2(visible_bounds.get_center().x, visible_bounds.end.y)
	var value: Variant = _anchors.get(contact_pose, fallback)
	return value if value is Vector2 and value.is_finite() else fallback


func _surface_origin_span(surface: Dictionary, _anchor_point: Vector2) -> Vector2:
	return Vector2(float(surface.x1) - visible_bounds.position.x + MARGIN,
		float(surface.x2) - visible_bounds.end.x - MARGIN)


func _surface_destination(surface: Dictionary, anchor_point: Vector2) -> Vector2:
	var span := _surface_origin_span(surface, anchor_point)
	if span.y < span.x:
		return Vector2.INF
	return Vector2(clampf(position.x, span.x, span.y), float(surface.y) - anchor_point.y)


func _begin_surface_attach() -> void:
	_next_decision = _time + DECISION_SECONDS
	var anchor_point := _anchor()
	var best: Dictionary = {}
	var best_point := Vector2.INF
	var best_distance := INF
	for surface: Dictionary in _surfaces.get_surfaces(visible_bounds.size.x + MARGIN * 2.0):
		var point := _surface_destination(surface, anchor_point)
		if not point.is_finite() or not is_origin_safe(point) or not _path_safe(position, point):
			continue
		var distance := position.distance_squared_to(point)
		if str(surface.id) == _preferred_surface_id:
			best = surface
			best_point = point
			break
		if distance < best_distance:
			best = surface
			best_point = point
			best_distance = distance
	if best.is_empty():
		_set_state("no_surface")
		return
	_preferred_surface_id = ""
	_locked_anchor = anchor_point
	_pending_support = best.duplicate()
	target = best_point
	_travel_until = _time + TRAVEL_TIMEOUT
	_set_state("approach")
	if position.distance_to(target) < 0.01:
		_support = _pending_support.duplicate()
		_pending_support.clear()
		_set_state("inspect")
		_state_until = _time + 3.0
		_emit_support()
	else:
		target_chosen.emit(str(best.id), target + anchor_point, "surface_approach")


func _choose_surface_target() -> void:
	if _support.is_empty():
		return
	if contact_pose != "foot":
		set_contact_pose("foot")
		return
	var span := _surface_origin_span(_support, _locked_anchor)
	var x := span.y if _choice_index % 2 == 0 else span.x
	_choice_index += 1
	if absf(x - position.x) < 30.0:
		x = span.x if x == span.y else span.y
	if absf(x - position.x) < 30.0:
		_set_state("rest")
		_state_until = _time + 8.0
		return
	observe_interest("surface_landmark", Vector2(x + _locked_anchor.x, float(_support.y)),
		0.2, 10.0, "surface_geometry")
	if not move_to_interest("surface_landmark"):
		_set_state("rest")
		_state_until = _time + 8.0


func _validate_support() -> void:
	var current := _support if not _support.is_empty() else _pending_support
	if current.is_empty():
		return
	for surface: Dictionary in _surfaces.get_surfaces(visible_bounds.size.x + MARGIN * 2.0):
		if str(surface.id) != str(current.id):
			continue
		# Moving surfaces are not vehicles: detach instead of teleporting with them.
		if absf(float(surface.y) - float(current.y)) > 0.1 or absf(float(surface.x1) - float(current.x1)) > 0.1 or absf(float(surface.x2) - float(current.x2)) > 0.1:
			break
		var span := _surface_origin_span(surface, _locked_anchor)
		var probe := position if not _support.is_empty() else target
		if probe.x < span.x - 0.1 or probe.x > span.y + 0.1 or not is_origin_safe(probe):
			break
		return
	_detach_support()


func _detach_support() -> void:
	var had_contact := not _support.is_empty() or not _pending_support.is_empty()
	_support.clear()
	_pending_support.clear()
	_interrupt()
	if had_contact:
		_emit_support()


func _emit_support() -> void:
	support_changed.emit(get_support_contact())


func _fallback_monitors() -> Array:
	var monitors: Array = []
	for i in workareas.size():
		var area := workareas[i]
		monitors.append({"id": "fallback:%d" % i, "work_x": area.position.x,
			"work_y": area.position.y, "work_width": area.size.x, "work_height": area.size.y})
	return monitors
