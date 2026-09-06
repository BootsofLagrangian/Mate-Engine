extends "test_host_objects.gd"
class TimelineObjects:
	extends Objects
	func _fit_contact_view(_preserve=false)->bool:return true
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	h.avatar.present=true
	h.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	var old_motion=h.motion;h.motion=MotionPlayer.new();h.add_child(h.motion);old_motion.free()
	h.motion.set_process(false);h.motion.avatar=h.avatar;h.motion.idle_enabled=false;h.motion.gaze_enabled=false
	var prefix=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/")
	for pair in [["sit_enter","s"],["sit_idle","loop"],["sit_exit","e"]]:h.motion.load_vrma(pair[0],prefix+"uma_sitdown01_"+pair[1]+".vrma")
	h.motion.register_seated_transition("enter","sit_enter");h.motion.register_seated_transition("exit","sit_exit")
	h.camera=Camera3D.new();h.add_child(h.camera);h.camera.current=true;root.size=Vector2i(680,760)
	var panel=h.panel;h.panel=null;h._pet_scale=.6;h._frame_avatar();h.panel=panel
	h._pivot_kind="foot";h._pivot_px=Vector2(510,680);h._pivot_px_target=h._pivot_px
	h._update_avatar_transform(0)
	h.motion.set_seated_floor(.48);h._ensure_seated_geometry()
	var old=h.objects
	var objects=TimelineObjects.new();h.add_child(objects);objects.host=h
	objects._settings=old._settings;old.remove_child(objects._settings);objects.add_child(objects._settings)
	old.host=null;old.free();h.objects=objects
	var origin:Vector3=h.avatar.global_transform*Vector3(h._pivot_local.foot)
	var displacement=Vector3(0,-.18,-.14)
	check(objects._start_presentation("enter",displacement),"real authored entry starts with cached bounds")
	objects._interaction={"id":"obj_1","stage":"entering","verb":"sit"}
	var window_origin:Vector2i=h.get_window().position
	var angles=[];var roots=[];var max_error=0.0
	for frame in 180:
		h.motion._process(1.0/60)
		var state:Dictionary=h.motion.seated_transition_state()
		h._update_avatar_transform(0)
		var hip:Vector3=h.avatar.bone_global_position("leftUpperLeg")
		var knee:Vector3=h.avatar.bone_global_position("leftLowerLeg")
		var foot:Vector3=h.avatar.bone_global_position("leftFoot")
		angles.append(rad_to_deg((knee-hip).angle_to(foot-knee)))
		roots.append(float(state.root_progress))
		var error=(h.avatar.global_transform*Vector3(h._pivot_local.foot)).distance_to(origin+displacement*float(state.root_progress))
		max_error=maxf(max_error,error)
		check(error<.00001,"host applies source root progression once")
		check(h.get_window().position==window_origin,"finite entry holds native window position")
		if state.finished:break
	print("MAX_ROOT_ERROR=",max_error," origin=",origin," current=",h.avatar.global_transform*Vector3(h._pivot_local.foot)," expected=",origin+displacement)
	check(angles.max()-angles.min()>30,"authored knee progression is visible before terminal seating")
	check(roots.front()<.2 and roots.back()==1.0,"entry progresses from standing to complete root endpoint")
	check(objects.presentation_bounds().size.length()>0,"host uses actual transition geometry bounds")
	objects.cancel_interaction("cancelled")
	check(not objects.has_presentation_transition() and not h.motion.seated_transition_state().get("active",false),"urgent cancellation clears timeline and displacement")
	check(h._pivot_kind=="foot" and not h._sit_active,"interrupted entry returns to standing contact lifecycle")
	h.free()
	print("Authored host presentation: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
