extends "test_host_objects.gd"
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	h.avatar.present=true
	var rig_path:=ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm")
	h.avatar.load_from_file(rig_path)
	var old_motion=h.motion;h.motion=MotionPlayer.new();h.add_child(h.motion);old_motion.free()
	h.motion.set_process(false);h.motion.avatar=h.avatar;h.motion.idle_enabled=false;h.motion.gaze_enabled=false
	var prefix=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/")
	for pair in [["sit_enter","s"],["sit_idle","loop"],["sit_exit","e"]]:h.motion.load_vrma(pair[0],prefix+"uma_sitdown01_"+pair[1]+".vrma")
	h.motion.register_seated_transition("enter","sit_enter");h.motion.register_seated_transition("exit","sit_exit")
	h.camera=Camera3D.new();h.add_child(h.camera);h.camera.current=true;root.size=Vector2i(1920,1760)
	var panel=h.panel;h.panel=null;h._pet_scale=1.0;h._frame_avatar();h.panel=panel
	h.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;h.camera.size=1760.0/332.48
	h._pivot_kind="foot";h._pivot_px=Vector2(960,1200);h._pivot_px_target=h._pivot_px
	h._update_avatar_transform(0)
	h.motion.set_seated_floor(.48);h._ensure_seated_geometry()
	var objects=h.objects
	var scene=DesktopObjectContactScene.new();h.add_child(scene)
	check(scene.configure("computer"),"actual premium computer scene loads")
	objects._contact_scene=scene;objects._contact_id="obj_1";scene.rotation.y=deg_to_rad(35)
	h.avatar.rotation.y=deg_to_rad(215)
	h.avatar.scale=Vector3.ONE
	var requirements:Dictionary=h.motion.seated_transition_requirements("enter")
	var source:Vector3=requirements.source_root_delta_local
	var expected_seat:Vector3=scene.socket_world("seat")-h.avatar.global_basis*source
	var actual_seat:Vector3=h.avatar.global_transform*Vector3(h._pivot_local.sit)
	h.avatar.global_position+=expected_seat-actual_seat
	h.autonomy.position=Vector2(h.get_window().position)
	h.autonomy.visible_bounds=Rect2(700,500,450,650)
	h.autonomy.workareas.assign([Rect2(-10000,-10000,20000,20000)])
	h.autonomy._blocked=false;h.autonomy._pointer_interaction=false
	h.autonomy.contact_pose="foot"
	h.autonomy._support={"id":"floor","kind":"screen_floor"}
	var point:Vector2=objects.contact_socket_screen("seat")
	h.autonomy.set_seat_surfaces([{"id":"object:obj_1:seat","x1":point.x-12,"x2":point.x+12,"y":point.y}])
	h.autonomy._support={"id":"floor","kind":"screen_floor"}
	var anchor:Vector2=h._projected_anchors().sit
	objects._interaction={"id":"obj_1","verb":"use","stage":"ready_contact","entry_plan":objects._capture_entry_plan()}
	var distance:=absf((point-anchor).x-h.autonomy.position.x)
	print("AUTHORED_ADMISSION_GEOMETRY source=",source," projected_distance_px=",distance)
	check(distance>48,"actual Cheval UMA source at working yaw exceeds instant-seat radius")
	check(not h.autonomy.can_request_seat_contact("object:obj_1:seat",point,anchor),"old immediate gate reproduces rejection")
	var admitted:bool=objects._authored_entry_admission("obj_1",point,anchor)
	print("ACTUAL_ADMISSION ",h.autonomy.last_seat_admission)
	check(admitted,"actual installed source/rig planned entry is admitted")
	h.autonomy.position.x+=25
	check(not objects._authored_entry_admission("obj_1",point,anchor) and h.autonomy.last_seat_admission.reason=="authored_staging_misaligned","unplanned 25px drift rejected")
	h.autonomy.position.x-=25
	h.autonomy._support.clear()
	check(not objects._authored_entry_admission("obj_1",point,anchor) and h.autonomy.last_seat_admission.reason=="authored_ground_support_missing","detached standing actor rejected")
	h.autonomy._support={"id":"floor","kind":"screen_floor"}
	scene.position.x+=.02
	check(not objects._authored_entry_admission("obj_1",objects.contact_socket_screen("seat"),anchor) and h.autonomy.last_seat_admission.reason=="authored_seat_moved","physical seat move invalidates old approach")
	scene.position.x-=.02
	h._pet_scale=.6
	check(not objects._authored_entry_admission("obj_1",point,anchor) and h.autonomy.last_seat_admission.reason=="authored_plan_changed","pet scale edit invalidates old approach")
	h._pet_scale=1.0
	h.motion.load_vrma("sit_enter",prefix+"uma_sitdown01_s.vrma")
	check(not objects._authored_entry_admission("obj_1",point,anchor) and h.autonomy.last_seat_admission.reason=="authored_plan_changed","same-name source replacement invalidates old approach")
	objects._interaction.entry_plan=objects._capture_entry_plan()
	h.avatar.load_from_file(rig_path)
	check(not objects._authored_entry_admission("obj_1",point,anchor) and h.autonomy.last_seat_admission.reason=="authored_plan_changed","same-path rig reload invalidates old approach")
	objects._interaction.clear();h.free()
	print("Authored admission: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
