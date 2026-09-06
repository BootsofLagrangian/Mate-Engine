class_name DesktopSurfaces
extends RefCounted
## Geometry-only support lines. z=0 is foreground. No window content is inspected.
var _snapshot: Dictionary = {}
var _authored: Array = []

func set_world_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)

func set_authored_surfaces(lines: Array) -> void:
	_authored = lines.duplicate(true)

func get_surfaces(minimum_width: float = 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var windows: Array = _snapshot.get("windows", [])
	var monitors: Array = _snapshot.get("monitors", [])
	for monitor: Dictionary in monitors:
		var area := _monitor_rect(monitor)
		if not area.has_area():
			continue
		var monitor_id := str(monitor.get("id", "%s,%s" % [area.position.x, area.position.y]))
		_append_line(result, "floor:" + monitor_id, "floor", area.position.x, area.end.x,
			area.end.y, area, monitor_id, [], minimum_width)
		for window: Dictionary in windows:
			var rect := _window_rect(window)
			if not rect.has_area() or not window.has("id"):
				continue
			var blockers: Array = []
			for other: Dictionary in windows:
				if str(other.get("id", "")) == str(window.id):
					continue
				if int(other.get("z", 0)) < int(window.get("z", 0)):
					blockers.append(_window_rect(other))
			_append_line(result, "window:" + str(window.id), "window", rect.position.x,
				rect.end.x, rect.position.y, area, monitor_id, blockers, minimum_width)
		for line: Dictionary in _authored:
			if not line.has("id"):
				continue
			_append_line(result, "authored:" + str(line.id), "authored", float(line.get("x1", 0)),
				float(line.get("x2", 0)), float(line.get("y", 0)), area, monitor_id, [], minimum_width)
	return result

func _append_line(output: Array[Dictionary], source_id: String, kind: String,
		x1: float, x2: float, y: float, area: Rect2, monitor_id: String,
		blockers: Array, minimum_width: float) -> void:
	if not is_finite(x1) or not is_finite(x2) or not is_finite(y) or y < area.position.y or y > area.end.y:
		return
	var lo := maxf(minf(x1, x2), area.position.x)
	var hi := minf(maxf(x1, x2), area.end.x)
	if hi - lo < minimum_width:
		return
	var intervals: Array[Vector2] = [Vector2(lo, hi)]
	for blocker: Rect2 in blockers:
		if not blocker.has_area() or blocker.position.y > y or blocker.end.y <= y:
			continue
		var remaining: Array[Vector2] = []
		for interval in intervals:
			if blocker.end.x <= interval.x or blocker.position.x >= interval.y:
				remaining.append(interval)
				continue
			if blocker.position.x > interval.x:
				remaining.append(Vector2(interval.x, minf(blocker.position.x, interval.y)))
			if blocker.end.x < interval.y:
				remaining.append(Vector2(maxf(blocker.end.x, interval.x), interval.y))
		intervals = remaining
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	for index in intervals.size():
		var interval := intervals[index]
		if interval.y - interval.x < minimum_width:
			continue
		output.append({"id": "%s@%s:%d" % [source_id, monitor_id, index],
			"source_id": source_id, "kind": kind, "x1": interval.x, "x2": interval.y, "y": y})

func _monitor_rect(monitor: Dictionary) -> Rect2:
	return Rect2(float(monitor.get("work_x", monitor.get("x", 0))),
		float(monitor.get("work_y", monitor.get("y", 0))),
		float(monitor.get("work_width", monitor.get("width", 0))),
		float(monitor.get("work_height", monitor.get("height", 0))))

func _window_rect(window: Dictionary) -> Rect2:
	return Rect2(float(window.get("x", 0)), float(window.get("y", 0)),
		float(window.get("width", 0)), float(window.get("height", 0)))
