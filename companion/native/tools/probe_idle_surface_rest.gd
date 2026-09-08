extends SceneTree
const Rest = preload("../scripts/idle_surface_rest.gd")
var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1
	print("%s %s" % ["PASS" if value else "FAIL",label])
func _initialize() -> void:
	var rest = Rest.new()
	var ctx := {"support":{"attached":true,"kind":"window","surface_id":"window:123"},"busy":false,"can_sit":true,"sitting_or_pending":false}
	check(rest.tick(10.0,ctx)=="","Initial idle does not immediately sit")
	check(rest.tick(66.0,ctx)=="sit","Stable verified window support eventually rests")
	check(rest.tick(0.1,ctx)=="","Failed admission does not spam retries")
	rest.admitted("window:123")
	ctx.sitting_or_pending = true
	check(rest.tick(1.0,ctx)=="" and rest.owns_rest(),"Admitted rest owns only its support")
	ctx.busy = true
	check(rest.tick(0.1,ctx)=="stand" and not rest.owns_rest(),"New activity releases automatic rest")
	check(rest.tick(1.0,ctx)=="","Manual seating is never released by idle policy")
	ctx.busy = false
	rest.admitted("window:123")
	ctx.support.surface_id = "window:456"
	check(rest.tick(0.1,ctx)=="stand","Changed support releases rest")
	ctx.support.surface_id = "window:123"
	rest.admitted("window:123")
	check(rest.tick(13.0,ctx)=="stand","Bounded rest returns to walking idle")
	ctx.support = {"attached":true,"kind":"floor","surface_id":"floor:monitor"}
	check(rest.tick(100.0,ctx)=="","Monitor floor is not a dangling-leg seat")
	ctx.support = {"attached":true,"kind":"taskbar","surface_id":"taskbar:123"}
	check(rest.tick(100.0,ctx)=="sit","Native taskbar support is an eligible seat")
	rest.admitted("taskbar:123")
	check(rest.tick(1.0,ctx)=="","Taskbar rest keeps admitted native support")
	ctx.support.surface_id = "floor:monitor"
	check(rest.tick(0.1,ctx)=="stand","Taskbar kind cannot legitimize an inferred floor")
	ctx.support = {"attached":false,"kind":"window","surface_id":"window:123"}
	check(rest.tick(100.0,ctx)=="","Detached or stale support cannot seat")
	ctx.support = {"attached":true,"kind":"authored","surface_id":"authored:chair"}
	check(rest.tick(100.0,ctx)=="","Furniture stays with its own skill owner")
	ctx.support = {"attached":true,"kind":"window","surface_id":"window:123"}
	ctx.busy = true
	check(rest.tick(100.0,ctx)=="","Busy interaction prevents idle admission")
	ctx.busy = false
	check(rest.tick(0.1,ctx)=="","Quiet stable interval required after interruption")
	check(rest.tick(6.0,ctx)=="sit","Returns to bounded policy after quiet interval")
	rest.admitted("window:123")
	ctx.support.attached = false
	ctx.rebinding = true
	check(rest.tick(0.2,ctx)=="" and rest.owns_rest(),"Native admitted seat-anchor exchange may briefly detach")
	check(rest.tick(2.0,ctx)=="stand","Failed reattachment cannot keep unsupported idle seat")
	rest.admitted("window:123")
	rest.reset()
	check(not rest.owns_rest(),"Character/behavior cancel revokes local ownership")
	var source = DesktopSurfaces.new()
	var snapshot := {"monitors":[{"id":"monitor","x":0,"y":0,"width":1920,"height":1080,"work_x":0,"work_y":0,"work_width":1920,"work_height":1032}],"windows":[],"taskbars":[{"id":"shell:123","x":0,"y":1032,"width":1920,"height":48,"z":0}]}
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
		check(DesktopWorldSource.is_valid_snapshot(loaded),"Captured native geometry passes source validation")
		if loaded is Dictionary: snapshot = loaded
	source.set_world_snapshot(snapshot)
	var seats: Array = source.get_surfaces(100.0).filter(func(surface): return surface.kind == "taskbar")
	check(not seats.is_empty(),"Native taskbar geometry produces real support segments")
	for seat in seats:
		var candidate = Rest.new()
		var connected := {"support":{"attached":true,"kind":seat.kind,"surface_id":seat.id},"busy":false,"can_sit":true,"sitting_or_pending":false}
		check(candidate.tick(76.0,connected)=="sit","Generated native taskbar support reaches idle sit policy")
	print("Idle surface rest: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
