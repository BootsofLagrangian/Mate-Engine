extends SceneTree
const Drop = preload("../scripts/desktop_drop_affordance.gd")
class ContactMotion extends RefCounted:
	var wall_lean = preload("../scripts/wall_lean_pose.gd").new()
	var stopped := 0
	var _preview := false
	var _custom_motion := false
	func current_contact_pose() -> String: return "lean"
	func stop_contact_pose() -> void: stopped+=1
class TestMicrophone extends RefCounted:
	func is_recording() -> bool: return false
class TestHost extends Node:
	var _drag_active := false
	var panel_open := false
	var motion = ContactMotion.new()
	var mic = TestMicrophone.new()
	var objects = null
	func body_dialogue_busy() -> bool: return false
var failed := 0
var passed := 0
func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1; push_error(label)
func _initialize() -> void:
	var scene := {"timestamp_msec":10000,"monitors":[{"id":"left","x":-1920,"y":0,"width":1920,"height":1080,"work_x":-1920,"work_y":0,"work_width":1920,"work_height":1040},{"id":"right","x":0,"y":0,"width":2560,"height":1440,"work_x":0,"work_y":0,"work_width":2560,"work_height":1400}],"taskbars":[{"id":"barL","x":-1920,"y":1040,"width":1920,"height":40,"z":0},{"id":"barR","x":0,"y":1400,"width":2560,"height":40,"z":0}],"windows":[{"id":"wall","x":-900,"y":200,"width":500,"height":700,"z":2}]}
	var foot := Vector2(-950,780)
	var actor := Rect2(-1020,480,140,300)
	var wall := Drop.nearest(scene,foot,actor,10000)
	check(wall.get("kind","")=="window_wall" and wall.get("monitor_id","")=="left","negative-origin wall")
	check(Drop.still_valid(wall,scene,12000),"unchanged contact valid")
	var moved := scene.duplicate(true); moved.windows[0].x+=1
	check(not Drop.still_valid(wall,moved,12000),"moved source releases")
	var hidden := scene.duplicate(true); hidden.windows=[]
	check(not Drop.still_valid(wall,hidden,12000),"minimized/removed source releases")
	var covered := scene.duplicate(true); covered.windows.append({"id":"cover","x":-980,"y":400,"width":200,"height":400,"z":1})
	check(not Drop.still_valid(wall,covered,12000),"foreground cover releases")
	check(not Drop.still_valid(wall,scene,15001),"stale publication releases")
	check(Drop.nearest(scene,foot,actor,15001).is_empty(),"stale drop rejected")
	check(Drop.nearest(scene,Vector2(-700,780),Rect2(-770,480,140,300),10000).is_empty(),"inside window not wall outside")
	check(Drop.nearest(scene,Vector2(-1200,780),Rect2(-1270,480,140,300),10000).is_empty(),"distant wall not approached")
	var bar := Drop.nearest(scene,Vector2(-1400,1020),Rect2(-1470,720,140,300),10000)
	check(bar.get("kind","")=="taskbar" and bar.get("monitor_id","")=="left","left taskbar matched")
	var supported_wall := Drop.nearest(scene,Vector2(-950,1040),Rect2(-1020,740,140,300),10000)
	check(supported_wall.get("kind","")=="window_wall","existing zero-distance taskbar support does not eclipse hand wall contact")
	var fallback := Drop.nearest(scene,Vector2(-950,1040),Rect2(-1020,740,140,300),10000,1.0,false)
	check(fallback.get("kind","")=="taskbar","reach rejection can request seat-only candidate")
	var covered_bar := scene.duplicate(true)
	covered_bar.windows.append({"id":"cover_bar","x":-1100,"y":950,"width":400,"height":130,"z":-1})
	check(Drop.nearest(covered_bar,Vector2(-950,1040),Rect2(-1020,740,140,300),10000,1.0,false).is_empty(),"seat-only fallback retains foreground window occlusion")
	var bar2 := Drop.nearest(scene,Vector2(900,1370),Rect2(830,1070,140,300),10000)
	check(bar2.get("kind","")=="taskbar" and bar2.get("monitor_id","")=="right","different-height second monitor taskbar")
	check(Drop.nearest(scene,Vector2(-1400,1070),Rect2(-1470,770,140,300),10000).is_empty(),"no upward support tunneling")
	var removed_monitor := scene.duplicate(true); removed_monitor.monitors.remove_at(0)
	check(not Drop.still_valid(wall,removed_monitor,12000),"monitor removal invalidates")
	var living = preload("../scripts/living_behavior.gd").new()
	var host := TestHost.new()
	living.host=host
	living._drop_contact={"kind":"window_wall","active":true}
	host._drag_active=true
	living._tick_drop_contact(0.016)
	check(living._drop_contact.is_empty() and host.motion.stopped==1,"new drag releases only owned lean")
	host._drag_active=false
	living._drop_contact={"kind":"window_wall","active":true}
	living.director._queue.append({"source":"user"})
	living._tick_drop_contact(0.016)
	check(living._drop_contact.is_empty() and host.motion.stopped==2,"queued explicit action immediately preempts lean")
	living._release_drop_contact("repeat")
	check(host.motion.stopped==2,"empty release never stops unrelated body")
	living._drop_contact={"kind":"window_wall","active":false}
	living._fallback_drop_seat(scene,Vector2(-950,1040),Rect2(-1020,740,140,300),10000,1.0)
	check(living._drop_contact.get("kind","")=="taskbar" and host.motion.stopped==2 and living.drop_diagnostics.last_outcome=="seat_fallback","failed unowned lean falls back without stopping other motion")
	living._drop_contact={"kind":"window_wall","active":true}
	host.motion.wall_lean.diagnostics={}
	check(living._guard_drop_wall_clearance() and not living._drop_contact.is_empty(),"unmeasured first pose does not reject lean")
	host.motion.wall_lean.diagnostics={"clearance_m":0.02}
	check(living._guard_drop_wall_clearance() and not living._drop_contact.is_empty() and host.motion.stopped==2,"positive measured torso clearance preserves owned contact")
	host.motion.wall_lean.diagnostics={"clearance_m":-0.003,"amplitude":0.0}
	check(not living._guard_drop_wall_clearance() and living._drop_contact.is_empty() and host.motion.stopped==3 and living.drop_diagnostics.last_outcome=="torso_overlap","overlapping restored base releases owned lean despite zero extra tilt")
	living.free(); host.free()
	var autonomy := DesktopAutonomy.new()
	root.add_child(autonomy)
	autonomy.configure_simulation([Rect2(-1920,0,1920,1040)],Vector2(-1500,700),Rect2(0,0,140,300))
	autonomy.set_contact_anchors({"foot":Vector2(70,304)})
	autonomy.set_world_snapshot(scene)
	autonomy.set_surface_mode(true)
	autonomy.update_context(false,false,false,false,false)
	for i in 600:
		autonomy.set_world_snapshot(scene)
		autonomy.advance(1.0/60.0)
		if autonomy.get_support_contact().get("attached",false): break
	check(autonomy.get_support_contact().get("attached",false),"real autonomy admits nearby taskbar support")
	var origin := autonomy.position
	var support_before := autonomy.get_support_contact()
	autonomy.update_context(false,false,false,false,true)
	for i in 60:
		autonomy.set_world_snapshot(scene)
		autonomy.advance(1.0/60.0)
	check(autonomy.position==origin and autonomy.get_support_contact()==support_before,"context lease preserves exact admitted foot for lean without canonical reposition")
	var no_bar := scene.duplicate(true); no_bar.taskbars=[]
	autonomy.set_world_snapshot(no_bar)
	check(not autonomy.get_support_contact().get("attached",false),"held support still invalidates on fresh geometry removal")
	autonomy.free()
	var busy := scene.duplicate(true)
	for i in 99: busy.windows.append({"id":"bench"+str(i),"x":100+i*4,"y":100+i*3,"width":900,"height":700,"z":3+i})
	var start := Time.get_ticks_usec()
	for i in 20: Drop.nearest(busy,foot,actor,10000)
	var query_us := float(Time.get_ticks_usec()-start)/20.0
	start=Time.get_ticks_usec()
	for i in 1000: Drop.still_valid(wall,busy,10000)
	var validation_us := float(Time.get_ticks_usec()-start)/1000.0
	print(JSON.stringify({"passed":passed,"failed":failed,"windows":100,"drop_query_mean_us":query_us,"active_validation_mean_us":validation_us,"validation_frequency":"new snapshot only; expiry O(1) each frame"}))
	quit(1 if failed else 0)
