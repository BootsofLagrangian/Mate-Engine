extends RefCounted
## A drop is a local suggestion, never authority to teleport or bypass support.
const Geometry = preload("desktop_surfaces.gd")
const MAX_AGE_MS := 5000

static func fresh(snapshot: Dictionary, now_msec: int) -> bool:
	var stamp := int(snapshot.get("timestamp_msec",0))
	return stamp > 0 and now_msec >= stamp and now_msec-stamp <= MAX_AGE_MS

static func nearest(snapshot: Dictionary, foot: Vector2, actor: Rect2, now_msec: int, dpi_scale: float = 1.0, include_walls: bool = true) -> Dictionary:
	if not fresh(snapshot,now_msec) or not foot.is_finite() or not actor.has_area(): return {}
	var monitor := {}
	for item: Dictionary in snapshot.get("monitors",[]):
		var area := Rect2(float(item.get("x",0)),float(item.get("y",0)),float(item.get("width",0)),float(item.get("height",0)))
		if area.grow(0.5).has_point(foot): monitor = item; break
	if monitor.is_empty(): return {}
	var scale := clampf(dpi_scale,0.75,3.0)
	var max_distance := minf(96.0*scale,actor.size.y*0.35)
	var best := {}
	var score := INF
	var monitor_area := _rect(monitor)
	for bar: Dictionary in snapshot.get("taskbars",[]):
		var rect := _rect(bar)
		if rect.size.x<rect.size.y or rect.size.y<8.0 or not rect.intersects(monitor_area): continue
		var target := Vector2(foot.x,rect.position.y)
		if target.x-actor.size.x*0.5<maxf(rect.position.x,monitor_area.position.x) or target.x+actor.size.x*0.5>minf(rect.end.x,monitor_area.end.x): continue
		if foot.y>target.y+4.0*scale: continue
		var distance := foot.distance_to(target)
		if distance>max_distance or distance>=score: continue
		if _covered(snapshot,bar,Rect2(target-Vector2(actor.size.x*0.5,1),Vector2(actor.size.x,2))): continue
		score=distance
		best={"kind":"taskbar","source_id":"taskbar:"+str(bar.id),"target":target}
	# A floor/taskbar supports the feet while a nearby wall supports the hand.
	# The existing zero-distance foot support must not eclipse every wall.
	# Evaluate reachable-looking wall edges independently, then let real arm
	# reach/collision admission decide whether leaning can start.
	var wall_score := INF
	var chest_y := actor.position.y+actor.size.y*0.37
	for window: Dictionary in snapshot.get("windows",[]) if include_walls else []:
		var rect := _rect(window)
		if chest_y<maxf(rect.position.y,monitor_area.position.y)+8.0*scale or chest_y>minf(rect.end.y,monitor_area.end.y)-8.0*scale: continue
		for side in ["left","right"]:
			var x: float=rect.position.x if side=="left" else rect.end.x
			if x<monitor_area.position.x or x>monitor_area.end.x: continue
			var normal := Vector2.LEFT if side=="left" else Vector2.RIGHT
			var target := Vector2(x,chest_y)
			var outward := (foot-target).dot(normal)
			if outward<12.0*scale or outward>max_distance or outward>=wall_score: continue
			if _covered(snapshot,window,Rect2(target-Vector2(2,8)*scale,Vector2(4,16)*scale)): continue
			wall_score=outward
			best={"kind":"window_wall","source_id":"window:"+str(window.id),"target":target,"normal":normal,"side":side}
	if not best.is_empty():
		best["monitor_id"]=str(monitor.get("id",""))
		best["timestamp_msec"]=int(snapshot.timestamp_msec)
		best["drop_foot"]=foot
		best["source_rect"]=_source_rect(best,snapshot)
		best["monitor_geometry"]=monitor.duplicate(true)
	return best

## Called on new native geometry publication only. Movement/occlusion invalidates
## the original contact; a newly visible segment never silently relocates it.
static func still_valid(candidate: Dictionary, snapshot: Dictionary, now_msec: int) -> bool:
	if candidate.is_empty() or not fresh(snapshot,now_msec): return false
	if _source_rect(candidate,snapshot)!=candidate.get("source_rect",Rect2()): return false
	var monitor_found := false
	for monitor: Dictionary in snapshot.get("monitors",[]):
		if str(monitor.get("id",""))==candidate.monitor_id:
			monitor_found=monitor==candidate.monitor_geometry
	if not monitor_found: return false
	var source_z := 2147483647
	for item: Dictionary in snapshot.get("windows",[])+snapshot.get("taskbars",[]):
		if _source_matches(candidate,item): source_z=int(item.get("z",0)); break
	var target: Vector2=candidate.target
	var contact_area := Rect2(target-Vector2(2,8),Vector2(4,16)) if candidate.kind=="window_wall" else Rect2(target-Vector2(16,2),Vector2(32,4))
	for blocker: Dictionary in snapshot.get("windows",[])+snapshot.get("taskbars",[]):
		if not _source_matches(candidate,blocker) and int(blocker.get("z",0))<source_z and contact_area.intersects(_rect(blocker)):
			return false
	return true

static func _rect(item: Dictionary) -> Rect2:
	return Rect2(float(item.get("x",0)),float(item.get("y",0)),float(item.get("width",0)),float(item.get("height",0)))

static func _source_matches(candidate: Dictionary, item: Dictionary) -> bool:
	var prefix := "taskbar:" if candidate.kind=="taskbar" else "window:"
	return prefix+str(item.get("id",""))==str(candidate.source_id)

static func _source_rect(candidate: Dictionary,snapshot: Dictionary) -> Rect2:
	for item: Dictionary in snapshot.get("taskbars",[]) if candidate.kind=="taskbar" else snapshot.get("windows",[]):
		if _source_matches(candidate,item): return _rect(item)
	return Rect2()

static func _covered(snapshot: Dictionary, source: Dictionary, contact_area: Rect2) -> bool:
	for blocker: Dictionary in snapshot.get("windows",[])+snapshot.get("taskbars",[]):
		if str(blocker.get("id",""))!=str(source.get("id","")) and int(blocker.get("z",0))<int(source.get("z",0)) and contact_area.intersects(_rect(blocker)): return true
	return false
