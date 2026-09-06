extends "test_host_objects.gd"
class RestoreObjects:
	extends Objects
	var completed := false
	func _chair_setup_fits(_scene:DesktopObjectContactScene,_envelope:AABB=AABB())->bool:return true
	func _fit_contact_view(_preserve=false)->bool:return true
	func _refresh_adapters():pass
	func _complete_contact_exit(_foot:Vector3,_model:int,_owner:Dictionary):completed=true;_interaction.clear()
class WindowStub:
	extends Furniture
	func show():visible=true
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _refresh_autonomy_label():\n\tpass\nfunc _save_window_position():\n\tpass\nfunc spatial_camera():\n\treturn camera\nfunc spatial_desktop_origin():\n\treturn Vector2.ZERO\nfunc _refresh_spatial_crop():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	h.avatar.present=true;h.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	var old=h.motion;h.motion=MotionPlayer.new();h.add_child(h.motion);old.free()
	h.motion.set_process(false);h.motion.avatar=h.avatar;h.motion.idle_enabled=false;h.motion.gaze_enabled=false
	h.motion.load_vrma("walk",ProjectSettings.globalize_path("res://../assets/motions/walk.vrma"));h._vrma_loaded={"walk":true}
	h.camera=Camera3D.new();h.add_child(h.camera);h.camera.current=true
	var panel=h.panel;h.panel=null;h._pet_scale=.6;h._frame_avatar();h.panel=panel
	h._pivot_kind="foot";h._pivot_px=Vector2(960,1200);h._pivot_px_target=h._pivot_px
	h._model_aabb=h.avatar.compute_aabb();h.autonomy._pointer_interaction=false;h.autonomy.enabled=true
	h.handle_button.visible=false # fixture creates an unlaid-out handle at the headless pointer origin
	var objects=RestoreObjects.new();h.add_child(objects);h.objects.free();h.objects=objects;objects.host=h
	objects._screen_provider=func():return [Rect2i(-4000,-4000,8000,8000)]
	var window=WindowStub.new();objects.add_child(window);objects.windows.obj_1=window
	var scene=DesktopObjectContactScene.new();h.add_child(scene);scene.configure("computer");scene.set_seat_scale(.4349648273/.48)
	var start:=Vector3(1.81110954284668,-1.33028185367584,-.104586124420166)
	scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
	scene.position=start-scene.basis*Vector3(-.241796970367432,0,1.10460007190704)
	scene.set_seat_setup(.1,144.999995)
	objects._contact_scene=scene;objects._contact_id="obj_1";objects._contact_scale=.6
	var adapter=DesktopSceneNavigationHost.new();h.add_child(adapter);adapter.configure(h);h.scene_navigation=adapter
	adapter.holding=true;adapter.ground_latched=true;adapter.foot_world=start;h.autonomy.set_process(false)
	h._update_avatar_transform(0);h._update_pet_rect()
	objects._interaction={"id":"obj_1","stage":"chair_restore","verb":"use","completed_foot":start,"completed_model":h.avatar.model.get_instance_id(),"completed_owner":adapter.contact_exit_token(),"chair_step":{},"chair_lift":0.0,"chair_steps":[{"kind":"swivel_restore","pull":.1,"yaw":0.0,"lift":0.0},{"kind":"roll_restore","pull":0.0,"yaw":0.0,"lift":0.0}]}
	var initial=scene.seat_setup()
	objects._tick_chair_steps(1.0/60)
	check(objects._interaction.get("stage")=="restore_approaching" and adapter.navigation.active,"blocked empty swivel starts owned real clearance walk")
	check(scene.seat_setup()==initial and not objects.completed,"chair stays stationary and command remains incomplete during departure")
	var token:int=objects._interaction.get("restore_token",-1)
	objects._restore_clearance_finished("arrived",token+1)
	check(objects._interaction.get("stage")=="restore_approaching","stale route callback cannot resume restoration")
	var distance:=0.0
	for frame in 600:
		h.motion._process(1.0/60);h._update_avatar_transform(0)
		var before:Vector3=h.avatar.contact_anchors().foot
		adapter.tick(1.0/60)
		distance+=before.distance_to(h.avatar.contact_anchors().foot)
		if not adapter.navigation.active:break
	check(objects._interaction.get("stage")=="chair_restore" and distance>.08,"actual authored XZ walk reaches restoration clearance")
	check(absf(h.avatar.contact_anchors().foot.y-start.y)<.000001,"step-away preserves canonical groundY")
	var end:Vector3=h.avatar.contact_anchors().foot
	for frame in 600:
		objects._tick_chair_steps(1.0/60)
		if objects.completed:break
	check(objects.completed and scene.seat_setup().pullout_local_m==0 and scene.seat_setup().yaw_delta_deg==0,"only cleared and fully restored chair completes interaction")
	check(h.avatar.contact_anchors().foot.distance_to(end)<.000001 and adapter.ground_latched,"empty restoration retains actual walked endpoint")
	# Failed custom geometry cannot replace an already owned idle endpoint.
	var invalid=adapter.request(end+Vector3(.1,0,0),[],{"area":Rect2(0,0,1,1),"cell_size":NAN})
	check(not invalid.accepted and adapter.foot_world==end,"invalid route geometry rejects before ownership mutation")
	objects.completed=false
	objects._interaction={"id":"obj_1","verb":"use","stage":"restore_approaching","restore_token":42,"restore_target":end+Vector3(0,0,.1),"command_id":"cleanup-cancel"}
	var accepted=adapter.request_owned(end+Vector3(0,0,.1),objects.scene_obstacle_bounds(),objects._restore_clearance_finished.bind(42))
	check(accepted.accepted,"second owned cleanup route starts for cancellation regression")
	for frame in 40:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
	var stopped:Vector3=h.avatar.contact_anchors().foot
	objects.cancel_interaction("cancelled")
	objects._restore_clearance_finished("arrived",42)
	check(objects._interaction.is_empty() and not adapter.has_completion_owner() and not adapter.navigation.active,"user cancellation removes cleanup route and stale callback cannot restore chair")
	check(objects.command_outcomes.size()==1 and objects.command_outcomes[0].outcome=="cancelled" and not objects.completed,"cancelled cleanup emits one cancellation and no completion")
	for frame in 120:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
	check(h.avatar.contact_anchors().foot.distance_to(stopped)<.000001,"cancelled cleanup retains stopped actual world position")
	objects._closed=true;objects._contact_scene=null
	if is_instance_valid(scene):scene.free()
	adapter.shutdown();h.scene_navigation=null;adapter.free();h.free()
	print("Restore walk: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
