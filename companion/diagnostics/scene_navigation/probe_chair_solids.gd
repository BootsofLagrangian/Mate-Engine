extends SceneTree
func _initialize():call_deferred("run")
func run():
	var avatar:=VrmAvatar.new();root.add_child(avatar);avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	var motion:=MotionPlayer.new();root.add_child(motion);motion.set_process(false);motion.avatar=avatar
	var prefix:=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/")
	motion.load_vrma("sit_idle",prefix+"uma_sitdown01_loop.vrma");motion.load_vrma("sit_enter",prefix+"uma_sitdown01_s.vrma");motion.register_seated_transition("enter","sit_enter")
	motion.set_seated_floor(.48)
	avatar.calibrate_seated_pose(motion.vrma_clips.sit_idle.sample(0))
	var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("chair")
	scene.transform=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.6),Vector3(1.00245094,-1.33028185,-.37647962))
	var actor:=Vector3(.58245099,-1.33028185,-.37647962)
	var anchors:=avatar.contact_anchors()
	var source:Vector3=motion.seated_transition_requirements("enter").source_root_delta_local
	var target:=DesktopObjectsHost.authored_staging_foot(scene.socket_world("seat"),Basis.IDENTITY.scaled(Vector3.ONE*.6),anchors.sit-anchors.foot,source,actor.y)
	var solids:Array=[];DesktopObjectsHost._append_scene_solids(scene,solids)
	var selected:=DesktopObjectsHost.select_authored_staging(actor,scene.socket_world("seat"),Basis.IDENTITY.scaled(Vector3.ONE*.6),anchors.sit-anchors.foot,source,solids,.072,1.0)
	var okay:bool=selected.get("accepted",false) and selected.get("factor",99.0)<=1.25 and selected.get("factor",0.0)>1.0
	print("CHAIR_STAGING ",selected," solids=",solids.size())
	if not okay:push_error("actual chair requires and admits bounded source-distance staging with all solids")
	# A solid enclosure remains blocked at every permitted source displacement.
	var wall:=solids.duplicate();wall.append(AABB(actor-Vector3(.1,0,.1),Vector3(.2,1,.2)))
	var rejected:=DesktopObjectsHost.select_authored_staging(actor,scene.socket_world("seat"),Basis.IDENTITY.scaled(Vector3.ONE*.6),anchors.sit-anchors.foot,source,wall,.072,1.0)
	okay=okay and not rejected.get("accepted",true)
	motion.free();avatar.free();scene.free()
	print("Chair physical staging: 2 checks, ",0 if okay else 1," failures")
	quit(0 if okay else 1)
