extends "test_host_objects.gd"
class GroundCommands:
	extends Objects
	var dispatched:=0
	func _execute_command(_command:Dictionary):dispatched+=1
func _run():
	root.size=Vector2i(680,760)
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=45;camera.position=Vector3(0,1,3.6);camera.current=true
	var origin:=Vector2(940,632)
	var areas:Array=[Rect2(0,0,2560,1392)]
	var actor:=DesktopView.screen_to_world_at_depth(camera,Vector2(340,760),3.6)
	for type in ["chair","sofa","computer"]:
		var scene:=DesktopObjectContactScene.new();root.add_child(scene);check(scene.configure(type),"actual imported placement geometry loads "+type)
		var basis:=Basis(Vector3.UP,deg_to_rad(scene.recommended_yaw_degrees)).scaled(Vector3.ONE*.6)
		var parts:Array=[];DesktopObjectsHost._append_scene_solids(scene,parts)
		var desired:=actor+Vector3(.42,0,0)
		var result:=DesktopObjectPlacement.find(camera,origin,areas,desired,basis,scene.geometry_points_local(),parts,[AABB(actor-Vector3(.072,0,.072),Vector3(.144,1,.144))])
		check(result.get("ok",false),"actual full furniture fits bounded ground search "+type)
		if result.get("ok",false):
			check(result.point.y==actor.y and result.point.distance_to(desired)<=1.5,"placement preserves exact ground Y and bounded XZ "+type)
			var projected:=ProjectedAvatarGeometry._project(camera,scene.geometry_points_local(),Transform3D(basis,result.point));projected.position+=origin
			check(Rect2(areas[0]).grow(-8).encloses(projected),"all actual vertices preserve native crop border "+type)
			check(result.point.z<desired.z,"floor-edge furniture moves inward in real Z "+type)
			print("PLACEMENT ",type," desired=",desired," result=",result)
		var blocked:=DesktopObjectPlacement.find(camera,origin,areas,desired,basis,scene.geometry_points_local(),parts,[AABB(Vector3(-10,-10,-10),Vector3(20,20,20))])
		check(not blocked.get("ok",true),"solid-filled ground remains rejected "+type)
		scene.free()
	camera.free()
	host_script=GDScript.new();host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc spatial_camera():\n\treturn camera\nfunc _save_window_position():\n\tpass\n'
	check(host_script.reload()==OK,"real host fixture parses")
	var h=fixture();h.avatar.present=true;h.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	var c:=GroundCommands.new();h.add_child(c);c.host=h;c._last_character=h.session.character_id
	h.camera=Camera3D.new();h.add_child(h.camera)
	h.autonomy.enabled=true;h.autonomy.surface_mode=true;h.autonomy._support={};h.autonomy._pending_support={}
	c._pending_command={"id":"ground","character":h.session.character_id,"source":"user","expires":30.0,"intent":{"kind":"furniture","object_type":"computer","verb":"use"}}
	c._tick_command();check(c.dispatched==0 and not c._pending_command.is_empty(),"ungrounded command stays queued without furniture mutation")
	c._pending_command.intent.verb="place"
	c._pending_command.intent["position_m"]={"x":0,"y":0,"z":0}
	c._tick_command();check(c.dispatched==0 and not c._pending_command.is_empty(),"new explicit-position furniture also waits for grounded creation")
	c._pending_command.intent.erase("position_m");c._pending_command.intent.verb="use"
	h.autonomy._support={"id":"floor:test","kind":"floor","x1":0.0,"x2":3000.0,"y":1000.0};h.autonomy._locked_anchor=Vector2.ZERO
	var ground:=c._ground_context();check(not ground.is_empty(),"attached floor establishes canonical ground")
	if not ground.is_empty():
		var y:float=ground.ground_y;h.avatar.position.y-=.2
		check(c._ground_context().ground_y==y,"post-contact pose-anchor offset cannot replace canonical plane")
	c._tick_command();check(c.dispatched==1 and c._pending_command.is_empty(),"ground-ready command dispatches exactly once")
	var prefix:=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/")
	h.motion.load_vrma("sit_idle",prefix+"uma_sitdown01_loop.vrma");h.motion.load_vrma("sit_enter",prefix+"uma_sitdown01_s.vrma");h.motion.register_seated_transition("enter","sit_enter")
	var source:Dictionary=h.motion.seated_transition_requirements("enter")
	check(float(source.get("source_seat_clearance_local",0))>.3,"actual authored source exposes measured seat clearance")
	check(absf(c._default_source_seat_ratio("chair")-float(source.get("source_seat_clearance_local",0))/.48)<.001,"new chair physical scale follows source clearance rather than fixed seat height")
	check(c._default_source_seat_ratio("computer")==1.0,"workstation source fit does not shrink fixed desktop height")
	check(absf(c._default_workstation_seat_scale()-float(source.get("source_seat_clearance_local",0))/.48)<.001,"adjustable computer chair alone follows installed source clearance")
	h._drag_active=true;check(c._ground_context().is_empty() and not is_finite(c._scene_ground_y),"explicit pet drag invalidates ground admission")
	c.host=null;c.free();h.free()
	print("Ground placement: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
