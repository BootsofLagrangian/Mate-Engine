class_name DesktopSurfaces
extends RefCounted
## Geometry-only support lines. z=0 is foreground. No window content is inspected.
var _snapshot: Dictionary = {}
var _authored: Array = []
var _surface_cache: Dictionary = {}
var _edge_cache: Dictionary = {}
var cache_hits := 0
var geometry_builds := 0

func set_world_snapshot(snapshot: Dictionary) -> void:
	if snapshot.get("monitors", []) != _snapshot.get("monitors", []) or snapshot.get("windows", []) != _snapshot.get("windows", []) or snapshot.get("taskbars", []) != _snapshot.get("taskbars", []):
		_surface_cache.clear()
		_edge_cache.clear()
	_snapshot = snapshot.duplicate(true)

func set_authored_surfaces(lines: Array) -> void:
	if lines != _authored: _surface_cache.clear()
	_authored = lines.duplicate(true)

func get_surfaces(minimum_width: float = 1.0) -> Array[Dictionary]:
	if _surface_cache.has(minimum_width): cache_hits += 1
	else:
		geometry_builds += 1
		_surface_cache[minimum_width] = _build_surfaces(minimum_width)
	return _surface_cache[minimum_width].duplicate(true)

func _build_surfaces(minimum_width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var windows: Array = _snapshot.get("windows", [])
	var monitors: Array = _snapshot.get("monitors", [])
	var taskbars: Array = _snapshot.get("taskbars", [])
	for monitor: Dictionary in monitors:
		var area := _monitor_rect(monitor)
		if not area.has_area():
			continue
		var monitor_id := str(monitor.get("id", "%s,%s" % [area.position.x, area.position.y]))
		var floor_blockers: Array = []
		for bar: Dictionary in taskbars:
			var bar_rect := _window_rect(bar)
			if bar_rect.size.x >= bar_rect.size.y and bar_rect.size.y >= 8: floor_blockers.append(bar_rect)
		_append_line(result, "floor:" + monitor_id, "floor", area.position.x, area.end.x,
			area.end.y, area, monitor_id, floor_blockers, minimum_width)
		for bar: Dictionary in taskbars:
			var rect := _window_rect(bar)
			if rect.size.x < rect.size.y or rect.size.y < 8: continue
			var blockers: Array = []
			for other: Dictionary in windows:
				if int(other.get("z", 0)) < int(bar.get("z", 0)): blockers.append(_window_rect(other))
			_append_line(result, "taskbar:"+str(bar.id), "taskbar", rect.position.x, rect.end.x,
				rect.position.y, area, monitor_id, blockers, minimum_width)
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


## Visible vertical frame edges for future wall/lean admission. This reports
## geometry only; it does not authorize a pose or infer window contents.
func get_contact_edges(minimum_length: float = 1.0) -> Array[Dictionary]:
	if _edge_cache.has(minimum_length): cache_hits += 1
	else:
		geometry_builds += 1
		_edge_cache[minimum_length] = _build_contact_edges(minimum_length)
	var result: Array[Dictionary] = _edge_cache[minimum_length].duplicate(true)
	for edge in result: edge.timestamp_msec = _snapshot.get("timestamp_msec",0)
	return result

func _build_contact_edges(minimum_length: float) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var windows: Array = _snapshot.get("windows", [])
	for window: Dictionary in windows:
		var rect := _window_rect(window)
		if not rect.has_area() or not window.has("id"): continue
		for monitor: Dictionary in _snapshot.get("monitors", []):
			var area := _monitor_rect(monitor)
			for side in ["left", "right"]:
				var x: float = rect.position.x if side == "left" else rect.end.x
				if x < area.position.x or x > area.end.x: continue
				var intervals: Array[Vector2] = [Vector2(maxf(rect.position.y,area.position.y),minf(rect.end.y,area.end.y))]
				for blocker: Dictionary in windows + _snapshot.get("taskbars", []):
					if str(blocker.get("id", "")) == str(window.id) or int(blocker.get("z",0)) >= int(window.get("z",0)): continue
					var box := _window_rect(blocker)
					if x < box.position.x or x > box.end.x: continue
					var remaining: Array[Vector2] = []
					for span in intervals:
						if box.end.y <= span.x or box.position.y >= span.y: remaining.append(span)
						else:
							if box.position.y > span.x: remaining.append(Vector2(span.x,box.position.y))
							if box.end.y < span.y: remaining.append(Vector2(box.end.y,span.y))
					intervals = remaining
				for index in intervals.size():
					var span := intervals[index]
					if span.y-span.x < maxf(1.0,minimum_length): continue
					output.append({"id":"window_edge:%s:%s@%s:%d" % [window.id,side,monitor.get("id",""),index],
						"source_id":"window:"+str(window.id),"kind":"window_wall","side":side,
						"a":Vector2(x,span.x),"b":Vector2(x,span.y),
						"normal":Vector2.LEFT if side == "left" else Vector2.RIGHT,
						"timestamp_msec":_snapshot.get("timestamp_msec",0)})
	return output
