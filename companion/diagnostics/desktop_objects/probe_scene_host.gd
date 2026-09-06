extends "test_host_objects.gd"
class RoutingLiving:
	extends LivingBehavior
	func _refresh_targets():pass
class TimelineObjects:
	extends Objects
	func _fit_contact_view(_preserve=false)->bool:return true
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nvar scene_view_enabled=true\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _refresh_autonomy_label():\n\tpass\nfunc _save_window_position():\n\tpass\nfunc spatial_camera():\n\treturn camera if scene_view_enabled else null\nfunc spatial_desktop_origin():\n\treturn Vector2.ZERO\nfunc _refresh_spatial_crop():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var blocker:=[AABB(Vector3(-.01,0,-.02),Vector3(.02,1,.04))]
	check(not DesktopSceneNavigationHost.placement_is_clear(Vector3(-.1,0,0),Vector3(.1,0,0),blocker,.01,1),"placement cannot cross solid even with free endpoints")
	check(DesktopSceneNavigationHost.placement_is_clear(Vector3(-.1,0,.1),Vector3(.1,0,.1),blocker,.01,1),"clear placement segment remains admitted")
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

	var adapter=load("res://scripts/desktop_scene_navigation_host.gd").new();h.add_child(adapter);adapter.configure(h);h.scene_navigation=adapter
	h._vrma_loaded={"walk":true}
	h.motion.load_vrma("walk",ProjectSettings.globalize_path("res://../assets/motions/walk.vrma"))
	h.objects._screen_provider=func():return [Rect2i(-4000,-4000,8000,8000)]
	h._model_aabb=h.avatar.compute_aabb()
	h.autonomy._pointer_interaction=false;h.autonomy.enabled=true
	h.objects._interaction={"id":"obj_1","verb":"sit","stage":"scene_approaching","scene_target":Vector3.ZERO}
	var start:Vector3=h.avatar.contact_anchors().foot
	var target:=start+Vector3(.25,0,-.35)
	h.objects._interaction.scene_target=target
	var accepted:Dictionary=adapter.request(target,[])
	check(accepted.accepted,"true scene path accepted")
	h.autonomy.state_changed.connect(h._on_autonomy_state_changed)
	var total:=0.0;var depth:=0.0;var overlap:=false;var rear_distance:=0.0;var turning_travel:=0.0
	for frame in 600:
		if frame==30:
			h.autonomy.state_changed.emit("settle")
			check(h.motion._travel_intent,"legacy state callback cannot revoke scene heading owner")
			h._on_locomotion(false,Vector2.ZERO)
			check(h.motion.current_gesture()==h._walk_started and not h._walk_started.is_empty(),"legacy stop callback cannot stop scene-owned walk clip")
		var prior_yaw:float=h.avatar.rotation.y
		h.motion._process(1.0/60)
		h._update_avatar_transform(0)
		var before:Vector3=h.avatar.contact_anchors().foot
		adapter.tick(1.0/60)
		var actual:Vector3=h.avatar.contact_anchors().foot
		total+=actual.distance_to(before);depth+=absf(actual.z-before.z)
		var step:=actual-before
		var forward:=Vector3(sin(h.avatar.rotation.y),0,cos(h.avatar.rotation.y))
		if step.dot(forward)<-0.000001:rear_distance+=step.length()
		if step.length()>.00001:turning_travel+=absf(angle_difference(prior_yaw,h.avatar.rotation.y))
		if actual.distance_to(before)>.00001 and absf(angle_difference(h.avatar.rotation.y,adapter.navigation._heading))>.3:overlap=true
		check(actual.distance_to(adapter.foot_world)<.00001,"camera commit preserves actual world foot")
		if not adapter.navigation.active:break
	check(depth>.3 and total>.4,"actual avatar travels depth and full measured world distance")
	check(overlap,"translation overlaps unfinished body yaw")
	check(rear_distance<.0001,"opposed heading cannot translate under forward walk")
	check(turning_travel>deg_to_rad(10),"actual body rotates at least ten degrees while translating")
	check(h.objects._interaction.get("stage","")=="ready","arrival hands off only at exact scene target")
	adapter.release_to_contact()
	var saved_windows:Dictionary=h.objects.windows
	h.objects.windows={}
	var interests=load("res://scripts/desktop_scene_interests.gd").new()
	var first:Array=interests.refresh(h)
	check(first.size()>0 and first.size()<=6,"bounded geometry-derived scene targets exist")
	var worlds:Dictionary=interests.targets.duplicate(true)
	for i in 20:interests.refresh(h)
	check(interests.targets==worlds,"quiet repeated refresh preserves stable IDs and world targets")
	h.objects.windows=saved_windows
	var callbacks:Array=[]
	var owner_result:Dictionary=adapter.request_owned(h.avatar.contact_anchors().foot+Vector3(-.12,0,-.1),[],func(outcome:String):callbacks.append(outcome))
	check(owner_result.accepted,"director-owned route accepted")
	for frame in 400:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
		if not adapter.navigation.active:break
	check(callbacks==["arrived"] and adapter.ground_latched and adapter.holding,"generic owner receives one terminal and retains virtual ground")
	var idle_foot:Vector3=h.avatar.contact_anchors().foot
	h.autonomy._support={"id":"floor:stale-pixel-floor","kind":"floor","x1":-4000.0,"x2":4000.0,"y":3000.0}
	for frame in 300:
		h.motion._process(1.0/60);h._update_avatar_transform(0);h._follow_standing_projection();adapter.tick(1.0/60)
	check(h.avatar.contact_anchors().foot.distance_to(idle_foot)<.00001 and not h.autonomy.is_processing(),"five seconds idle preserves actual XYZ despite old desktop-floor support")
	adapter.cancel("late_cancel")
	check(callbacks==["arrived"],"late cancel cannot duplicate terminal")
	var before_cancel:Vector3=h.avatar.contact_anchors().foot
	h.objects._interaction={"id":"obj_1","verb":"sit","stage":"scene_approaching","scene_target":before_cancel+Vector3(.2,0,0)}
	check(adapter.request(before_cancel+Vector3(.2,0,0),[]).accepted,"second scene path starts")
	h._drag_active=true;adapter.tick(.016)
	check(not adapter.holding and not adapter.navigation.active,"drag immediately cancels scene ownership")
	check(h.avatar.contact_anchors().foot.distance_to(before_cancel)<.00001,"urgent stop produces no world drift")
	h._drag_active=false
	var chain:Array=[]
	h.objects._interaction={}
	check(adapter.request_owned(h.avatar.contact_anchors().foot+Vector3(.2,0,-.1),[],func(outcome:String):chain.append(outcome)).accepted,"generic route starts before legacy handoff")
	for frame in 40:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
	var routing:=RoutingLiving.new();h.add_child(routing);routing.host=h

	var rejected_legacy:Dictionary=routing.request_intent({"kind":"move_to","target_id":"legacy"},"user","legacy-user")
	check(not rejected_legacy.get("accepted",false) and h._walk_started.is_empty(),"unavailable legacy target stops old scene walk instead of marching in place")
	check(chain==["superseded"] and not adapter.has_completion_owner() and not adapter.holding,"actual Living legacy request cancels old owner exactly once")
	var furniture_target:Vector3=h.avatar.contact_anchors().foot+Vector3(-.12,0,-.1)
	h.objects._interaction={"id":"obj_1","verb":"sit","stage":"scene_approaching","scene_target":furniture_target}
	check(adapter.request(furniture_target,[]).accepted,"subsequent furniture route starts without stale owner")
	for frame in 400:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
		if not adapter.navigation.active:break
	check(h.objects._interaction.get("stage","")=="ready" and chain==["superseded"],"furniture arrival reaches Objects rather than stale director callback")
	adapter.release_to_contact();h.objects._interaction={}
	for mode in ["projection","surface","enabled"]:
		var terminal:Array=[]
		var start_mode:Vector3=h.avatar.contact_anchors().foot
		check(adapter.request_owned(start_mode+Vector3(.2,0,-.1),[],func(outcome:String):terminal.append(outcome)).accepted,"mode-exit route starts")
		for frame in 120:
			h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
			if h.avatar.contact_anchors().foot.distance_to(start_mode)>.005:break
		var stopped_mode:Vector3=h.avatar.contact_anchors().foot
		if mode=="projection":h.scene_view_enabled=false
		elif mode=="surface":h.autonomy.surface_mode=false
		else:h.autonomy.enabled=false
		adapter.tick(.016)
		check(terminal==["disabled"] and not adapter.holding and not adapter.has_completion_owner(),"active mode exit clears route/owner immediately: "+mode)
		check(h.avatar.contact_anchors().foot.distance_to(stopped_mode)<.00001,"active mode exit has zero world drift: "+mode)
		h.scene_view_enabled=true;h.autonomy.surface_mode=true;h.autonomy.enabled=true
	var chair:=DesktopObjectContactScene.new();h.add_child(chair);chair.configure("chair")
	var chair_start:Vector3=h.avatar.contact_anchors().foot
	chair.transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.6),chair_start+Vector3(.42,0,0))
	var chair_solids:Array=[];DesktopObjectsHost._append_scene_solids(chair,chair_solids)
	var source_delta:Vector3=h.motion.seated_transition_requirements("enter").source_root_delta_local
	var stage:=DesktopObjectsHost.select_authored_staging(chair_start,chair.socket_world("seat"),chair.basis,h._pivot_local.sit-h._pivot_local.foot,source_delta,chair_solids,.072,h._model_aabb.size.y*.6)
	check(stage.get("accepted",false),"actual rig chair staging admitted before low-FPS route")
	if stage.get("accepted",false):
		h.objects._interaction={"id":"obj_1","verb":"sit","stage":"scene_approaching","scene_target":stage.target_world}
		check(adapter.request(stage.target_world,chair_solids).accepted,"actual imported chair route starts with all components")
		for frame in 600:
			h.motion._process(.09);h._update_avatar_transform(0);adapter.tick(.09)
			if frame==8:h.autonomy.state_changed.emit("settle");h._on_locomotion(false,Vector2.ZERO)
			if not adapter.navigation.active:break
		check(h.avatar.contact_anchors().foot.distance_to(stage.target_world)<.001 and h.objects._interaction.get("stage","")=="ready","low-FPS chair route survives legacy state/stop callbacks and arrives before timeout")
	adapter.release_to_contact();chair.free()
	h.objects._interaction={}
	check(adapter.request(h.avatar.contact_anchors().foot+Vector3(.2,0,-.1),[]).accepted,"direct route before user stop")
	for frame in 60:
		h.motion._process(1.0/60);h._update_avatar_transform(0);adapter.tick(1.0/60)
	var stopped:Vector3=h.avatar.contact_anchors().foot
	adapter.cancel("cancelled")
	for frame in 300:
		h.motion._process(1.0/60);h._update_avatar_transform(0);h._follow_standing_projection();adapter.tick(1.0/60)
	check(adapter.ground_latched and not adapter.navigation.active and h.avatar.contact_anchors().foot.distance_to(stopped)<.00001,"user stop holds actual scene XYZ for five seconds")
	h.objects._interaction={"id":"obj_1","stage":"approaching","request_id":"object-use:owned"}
	routing.director.request_intent("object-use:owned","rest","","user")
	check(routing._owns_legacy_furniture_approach(),"owned queued legacy approach bypasses only its furniture busy guard")
	routing.director.cancel_all();routing.director.request_intent("other","rest","","user")
	check(not routing._owns_legacy_furniture_approach(),"unrelated queued request stays blocked by furniture")
	h.objects._interaction={}
	adapter.shutdown();h.scene_navigation=null
	h.free()
	print("Scene host: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
