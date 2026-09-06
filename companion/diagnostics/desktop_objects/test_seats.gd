extends SceneTree
const Autonomy = preload("res://scripts/desktop_autonomy.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var a := Autonomy.new()
	a.configure_simulation([Rect2(-1920,0,3840,1040)],Vector2(300,360),Rect2(400,120,220,680-120))
	a.set_contact_anchors({"foot":Vector2(510,680),"sit":Vector2(510,500)})
	a.set_surface_mode(true)
	a.set_external_decisions(true)
	a.update_context(false,false,false,false,false)
	for i in 240: a.advance(1.0/60.0)
	a.set_seat_surfaces([{"id":"object:chair:seat","x1":790,"x2":830,"y":850}])
	check(a.get_support_contact().get("attached",false),"floor support exists before explicit seat")
	check(a.can_request_seat_contact("object:chair:seat",Vector2(810,850),Vector2(510,500)),"real40px seat admits pelvis while body is220px wide")
	check(not a.can_request_seat_contact("object:chair:seat",Vector2(810,990),Vector2(510,500)),"wrong plane rejects contact")
	a.set_seat_surfaces([{"id":"object:chair:seat","x1":790,"x2":830,"y":990}])
	check(not a.can_request_seat_contact("object:chair:seat",Vector2(810,990),Vector2(510,500)),"full body workarea safety rejects seat below safe clearance")
	a.set_seat_surfaces([{"id":"object:chair:seat","x1":790,"x2":830,"y":850}])
	a.set_contact_pose("sit")
	check(a.request_seat_contact("object:chair:seat",Vector2(810,850)),"explicit seated pose starts smooth contact approach")
	var origin := a.position
	check(origin != a.target,"contact does not teleport to target")
	for i in 1000:
		a.advance(1.0/120.0)
		if a.get_support_contact().get("attached",false): break
	# Repeated projection roundoff must not invalidate an immobile owned seat.
	for i in 120:
		var tiny := 0.0001 if i%2 else -0.0001
		a.set_seat_surfaces([{"id":"object:chair:seat","x1":790+tiny,"x2":830+tiny,"y":850+tiny}])
		a.advance(1.0/120.0)
	check(a.get_support_contact().get("attached",false),"subpixel projection noise retains owned contact")
	var contact := a.get_support_contact()
	check(contact.get("attached",false) and contact.pose=="sit" and contact.kind=="object_seat","narrow seat becomes real native sit support")
	check(Vector2(contact.screen_point).distance_to(Vector2(810,850)) < 0.01,"actual seat anchor reaches exact socket")
	check(a.is_origin_safe(a.position),"full avatar remains on usable desktop while seated")
	a.set_seat_surfaces([{"id":"object:chair:seat","x1":795,"x2":835,"y":850}])
	check(not a.get_support_contact().get("attached",false),"moved prop invalidates seat immediately")
	for i in 600: a.advance(1.0/60.0)
	check(not a.get_support_contact().get("attached",false) and a.state == "no_surface","lost owned seat never falls back to an unrelated surface while sitting")
	a.set_contact_pose("foot")
	a.set_seat_surfaces([])
	for i in 600: a.advance(1.0/60.0)
	check(a.get_support_contact().get("kind","") == "floor","ordinary foot reacquires floor, never imaginary wide chair platform")
	a.free()
	print("Object seats: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
