extends SceneTree
## Replays typed native planning input with the actual rig. Camera/work-area
## callbacks are intentionally outside this headless geometry/reach check.
const Helper=preload("../scripts/desktop_contact_manipulation.gd")
var avatar:VrmAvatar
var scene:DesktopObjectContactScene
var input:Dictionary
var selected:Dictionary
var failures:=0
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print(label," ",value)
	if not value:failures+=1
func bones()->Array:
	var result:Array=[]
	for index in avatar.skeleton.get_bone_count():result.append(avatar.skeleton.get_bone_pose(index))
	return result
func candidate(pull:float,yaw:float)->Dictionary:
	var original:=scene.seat_setup()
	var radius:=.12*float(input.contact_scale)
	var height:=avatar.compute_aabb().size.y*float(input.contact_scale)
	var offset:Vector3=selected.stance_offset
	var result:=Helper.admit(scene,pull,float(input.seat_setup.yaw_delta_deg),input.actor_foot.y,radius,height,[],Callable(),Callable(),offset)
	if result.accepted:
		scene.set_seat_setup(pull,input.seat_setup.yaw_delta_deg)
		result=Helper.admit(scene,pull,yaw,input.actor_foot.y,radius,height,[],Callable(),Callable(),offset)
		if result.accepted:
			scene.set_seat_setup(pull,yaw)
			result.actor_after_world=Helper.target(scene,input.actor_foot.y,offset).foot
	scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
	return result
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:push_error("planning-input.bin and avatar.vrm required");quit(2);return
	input=FileAccess.open(args[0],FileAccess.READ).get_var()
	avatar=VrmAvatar.new();root.add_child(avatar)
	if not avatar.load_from_file(args[1]):quit(2);return
	avatar.global_transform=input.avatar_transform
	scene=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer")
	scene.global_transform=input.scene_transform;scene.set_seat_scale(input.seat_setup.seat_scale);scene.set_seat_setup(input.seat_setup.pullout_local_m,input.seat_setup.yaw_delta_deg)
	var before:=bones()
	var started:=Time.get_ticks_usec()
	selected=Helper.select_approach(avatar,scene,input.actor_foot,.12*float(input.contact_scale),avatar.compute_aabb().size.y*float(input.contact_scale))
	print("selection ",selected)
	check(selected.accepted,"captured native blocked endpoint gets reachable alternative")
	check(avatar.global_transform==input.avatar_transform and bones()==before,"all temporary actor FK and placement restored")
	check(scene.global_transform==input.scene_transform and scene.seat_setup()==input.seat_setup,"scene state preserved during selection")
	if not selected.accepted:avatar.free();scene.free();quit(1);return
	var nav:=DesktopSceneNavigation.new()
	var solids:Array=[];DesktopObjectsHost._append_scene_solids(scene,solids)
	nav.configure(selected.navigation_geometry.area,input.actor_foot.y,solids,.12*float(input.contact_scale),avatar.compute_aabb().size.y*float(input.contact_scale),selected.navigation_geometry.cell_size)
	var target:=Helper.target(scene,input.actor_foot.y,selected.stance_offset)
	check(nav.plan("replay",input.actor_foot,target.foot,.35*float(input.contact_scale)).accepted,"selected grid replays actual approach")
	nav.dispose()
	check(float(selected.pose_admission.maximum_hand_error_m)<=.018,"selected full grip reaches both anchors")
	var plan:=DesktopWorkstationSetup.plan(scene,input.actor_foot,float(input.contact_scale),input.sit_minus_foot,input.source_delta,.12*float(input.contact_scale),avatar.compute_aabb().size.y*float(input.contact_scale),[],Callable(),Callable(),PackedVector3Array(),candidate)
	check(plan.accepted,"complete checked standing setup and seating approach has a plan")
	print("plan ",plan)
	print("grip stance failures=",failures," total_ms=",(Time.get_ticks_usec()-started)/1000.0)
	if args.size()>2:
		var output:=FileAccess.open(args[2],FileAccess.WRITE)
		output.store_string(JSON.stringify({"scope":"Captured native transforms and actual rig; no camera/work-area callbacks or rendered motion","selection":selected,"plan":plan,"failures":failures},"  "));output.close()
	avatar.free();scene.free();quit(1 if failures else 0)
