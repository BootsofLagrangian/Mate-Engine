extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1;print("FAIL ",label)
func _initialize() -> void:call_deferred("run")
func original_guard(a: DesktopAutonomy,id: String,point: Vector2,anchor: Vector2) -> bool:
	if not a.enabled or not a.surface_mode or a._blocked or a._pointer_interaction or a._handoff_braking or not point.is_finite() or not anchor.is_finite():return false
	var seat: Dictionary=a._seat_surfaces.get(id,{})
	if seat.is_empty() or absf(point.y-float(seat.y))>.1:return false
	var destination:=point-anchor
	var span:=a._surface_origin_span(seat,anchor)
	if absf(destination.x-a.position.x)>48 or destination.x<span.x or destination.x>span.y:return false
	return a.is_origin_safe(destination) and a._path_safe(a.position,destination)
func run() -> void:
	var a:=DesktopAutonomy.new()
	a.surface_mode=true;a._blocked=false;a._pointer_interaction=false;a.visible_bounds=Rect2(0,0,100,200);a.position=Vector2(300,500)
	a.workareas.assign([Rect2(0,0,1000,1000)])
	a._seat_surfaces={"seat":{"id":"seat","x1":100.0,"x2":900.0,"y":700.0,"anchor_only":true}}
	var anchor:=Vector2(50,200)
	check(a.can_request_seat_contact("seat",Vector2(350,700),anchor) and a.last_seat_admission.reason=="accepted","normal seat accepted")
	for key in ["enabled","surface_mode","_blocked","_pointer_interaction","_handoff_braking"]:
		var old: bool=a.get(key);a.set(key,not old)
		check(a.can_request_seat_contact("seat",Vector2(350,700),anchor)==original_guard(a,"seat",Vector2(350,700),anchor),"policy equivalent "+key)
		check(not a.last_seat_admission.accepted and a.last_seat_admission.reason!="accepted","specific policy rejection "+key)
		a.set(key,old)
	for x in [50.0,301.0,302.0,350.0,398.0,399.0,950.0]:
		for y in [699.8,700.0,700.2]:
			var point:=Vector2(x,y)
			check(a.can_request_seat_contact("seat",point,anchor)==original_guard(a,"seat",point,anchor),"geometry equivalent %s"%point)
	check(not a.can_request_seat_contact("missing",Vector2(350,700),anchor) and a.last_seat_admission.reason=="missing_seat_surface","missing surface distinguished")
	check(not a.can_request_seat_contact("seat",Vector2.INF,anchor) and a.last_seat_admission.reason=="nonfinite_point","nonfinite point recorded safely")
	var json:=JSON.new();check(json.parse(JSON.stringify(a.last_seat_admission))==OK,"failure diagnostic valid JSON")
	a.workareas.assign([Rect2(0,0,1000,650)])
	check(not a.can_request_seat_contact("seat",Vector2(350,700),anchor) and a.last_seat_admission.reason=="destination_outside_workareas","real destination floor overflow distinguished")
	a.workareas.assign([Rect2(0,0,1000,1000)])
	a.visible_bounds=Rect2(0,0,10,10);a.position=Vector2(100,100)
	a._seat_surfaces.seat.y=100.0;anchor=Vector2.ZERO
	a.workareas.assign([Rect2(0,0,115,500),Rect2(125,0,500,500)])
	check(not a.can_request_seat_contact("seat",Vector2(140,100),anchor) and a.last_seat_admission.reason=="path_outside_workareas","safe endpoint with unsafe intermediate path distinguished")
	# The observed source-derived 60.4px entry is safe only at its planned start.
	a.workareas.assign([Rect2(0,0,1000,1000)])
	a.visible_bounds=Rect2(0,0,100,200);a.position=Vector2(300,500)
	a._seat_surfaces.seat.y=700.0;anchor=Vector2(50,200)
	var target:=Vector2(410.4,700)
	var planned_start:=Vector2(350,700)
	check(not a.can_request_seat_contact("seat",target,anchor),"ordinary contact retains 48px limit")
	check(a.can_request_authored_seat_entry("seat",target,anchor,planned_start),"source-staged 60.4px entry passes existing geometry")
	check(not a.can_request_authored_seat_entry("seat",target,anchor,planned_start+Vector2(24.1,0)) and a.last_seat_admission.reason=="authored_staging_misaligned","wrong standing position cannot reuse authored entry")
	check(not a.can_request_authored_seat_entry("seat",target,anchor,planned_start,100),"caller cannot inflate arrival tolerance")
	check(not a.can_request_authored_seat_entry("seat",target,anchor,Vector2.INF),"nonfinite source projection fails")
	a._blocked=true
	check(not a.can_request_authored_seat_entry("seat",target,anchor,planned_start) and a.last_seat_admission.reason=="blocked_context","authored entry keeps foreground gate")
	a._blocked=false;a.workareas.assign([Rect2(0,0,1000,650)])
	check(not a.can_request_authored_seat_entry("seat",target,anchor,planned_start) and a.last_seat_admission.reason=="destination_outside_workareas","authored entry still rejects endpoint overflow")
	a.visible_bounds=Rect2(0,0,10,10);a.position=Vector2(100,100);anchor=Vector2.ZERO
	a._seat_surfaces.seat.y=100.0
	a.workareas.assign([Rect2(0,0,115,500),Rect2(125,0,500,500)])
	check(not a.can_request_authored_seat_entry("seat",Vector2(180,100),anchor,Vector2(100,100)) and a.last_seat_admission.reason=="path_outside_workareas","authored entry cannot skip unsafe intermediate desktop path")
	a.contact_pose="foot"
	check(not a.request_seat_contact("seat",Vector2(140,100)) and a.last_seat_admission.reason=="wrong_contact_pose","request pose guard reports fresh reason")
	a.free();print("SEAT_ADMISSION_DIAGNOSTICS ",passed," passed ",failed," failed");quit(1 if failed else 0)
