extends SceneTree
class Host extends RefCounted:
	var avatar:VrmAvatar
	var _pet_scale:=.6
func _init()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():push_error("VRM path required");quit(2);return
	var host:=Host.new();host.avatar=VrmAvatar.new();root.add_child(host.avatar)
	if not host.avatar.load_from_file(args[0]):quit(2);return
	host.avatar.scale=Vector3.ONE*.6
	var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer");scene.scale=Vector3.ONE*.6;scene.set_seat_scale(.906176591431814)
	var target:=DesktopContactManipulation.target(scene,0)
	host.avatar.rotation.y=target.yaw;host.avatar.global_position+=Vector3(target.foot)-Vector3(host.avatar.contact_anchors().foot)
	var sk:=host.avatar.skeleton
	var rest:Dictionary={}
	host.avatar.reset_pose()
	for index in host.avatar.bone_index.values():rest[index]=sk.get_bone_pose_rotation(index)
	host.avatar.add_pose_offsets({"spine":Vector3(25,0,0),"chest":Vector3(15,0,0)})
	for side in ["left","right"]:DesktopGripPose.solve(host.avatar,side,target[side],Vector3(sin(float(target.yaw)),0,cos(float(target.yaw))),1)
	var contact:Dictionary={};var torso:Dictionary={}
	for index in host.avatar.bone_index.values():contact[index]=sk.get_bone_pose_rotation(index)
	for bone in ["spine","chest"]:torso[host.avatar.bone_index[bone]]=contact[host.avatar.bone_index[bone]]
	var objects:=DesktopObjectsHost.new();objects.host=host;objects._contact_scene=scene
	objects._interaction={"chair_step":{"phase":"release"},"grip_release_torso":torso,"grip_route":{"lean":Vector2(25,15)},"grip_fixed_solids":[],"grip_seat_parts":[]}
	var failures:=0;var worst_overshoot:=0.0
	for frame in 31:
		var elapsed:=float(frame)/60.0
		for index in contact:sk.set_bone_pose_rotation(index,Quaternion(contact[index]).slerp(rest[index],smoothstep(0,.25,elapsed)))
		objects._interaction.erase("grip_frame")
		objects._apply_manipulation_contact(target,1.0-smoothstep(0,.5,elapsed))
		for index in torso:
			var overshoot:float=Quaternion(rest[index]).angle_to(sk.get_bone_pose_rotation(index))-Quaternion(rest[index]).angle_to(torso[index])
			worst_overshoot=maxf(worst_overshoot,overshoot)
			if overshoot>.00001:failures+=1
	print(JSON.stringify({"scope":"Actual rig and host contact composition over a captured-pose release blend; no desktop rendering","samples":31,"torso_overshoot_degrees":rad_to_deg(worst_overshoot),"failures":failures}))
	objects._contact_scene=null;objects.free();scene.free();host.avatar.free();quit(1 if failures else 0)
