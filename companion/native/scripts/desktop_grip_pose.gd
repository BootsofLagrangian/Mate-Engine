class_name DesktopGripPose
extends RefCounted
## Chair-only anatomy-relative grip. Four fingers flex toward their measured
## palm plane; no character-specific axis or mirrored Euler table is required.
static var _cache:Dictionary={}
static func anatomy(avatar:VrmAvatar,side:String)->Dictionary:
	var key:=str(avatar.model.get_instance_id())+":"+side
	if _cache.has(key):return _cache[key]
	var sk:=avatar.skeleton
	for suffix in ["Hand","IndexProximal","LittleProximal","MiddleProximal"]:
		if not avatar.bone_index.has(side+suffix):return {}
	var wrist:Vector3=sk.get_bone_global_rest(avatar.bone_index[side+"Hand"]).origin
	var index:Vector3=sk.get_bone_global_rest(avatar.bone_index[side+"IndexProximal"]).origin-wrist
	var little:Vector3=sk.get_bone_global_rest(avatar.bone_index[side+"LittleProximal"]).origin-wrist
	var forward:Vector3=(sk.get_bone_global_rest(avatar.bone_index[side+"MiddleProximal"]).origin-wrist).normalized()
	var palm:=index.cross(little).normalized()*(-1.0 if side=="left" else 1.0)
	palm=(palm-forward*palm.dot(forward)).normalized()
	if forward.length()<.99 or palm.length()<.99:return {}
	var fingers:Array=[]
	for finger in ["Index","Middle","Ring","Little"]:
		for pair in [["Proximal","Intermediate",35.0],["Intermediate","Distal",45.0],["Distal","",20.0]]:
			var name:String=side+finger+str(pair[0])
			if not avatar.bone_index.has(name):continue
			var bone:int=avatar.bone_index[name]
			var rest:Transform3D=sk.get_bone_global_rest(bone)
			var direction:=forward
			if not str(pair[1]).is_empty() and avatar.bone_index.has(side+finger+str(pair[1])):
				direction=(sk.get_bone_global_rest(avatar.bone_index[side+finger+str(pair[1])]).origin-rest.origin).normalized()
			var axis:Vector3=rest.basis.inverse()*direction.cross(palm).normalized()
			fingers.append({"bone":bone,"axis":axis.normalized(),"angle":deg_to_rad(float(pair[2]))})
	var middle:Vector3=sk.get_bone_global_rest(avatar.bone_index[side+"MiddleProximal"]).origin-wrist
	var thickness:=index.distance_to(little)*.12
	var palm_offset:Vector3=sk.get_bone_global_rest(avatar.bone_index[side+"Hand"]).basis.inverse()*(middle*.6+palm*thickness)
	var result:Dictionary={"frame":Basis(forward,palm,forward.cross(palm)),"fingers":fingers,"palm_offset":palm_offset}
	_cache[key]=result
	return result
static func align_wrist(avatar:VrmAvatar,side:String,forward_world:Vector3,weight:float)->bool:
	if not is_finite(weight) or not forward_world.is_finite():return false
	weight=clampf(weight,0,1)
	var data:=anatomy(avatar,side)
	if data.is_empty():return false
	var sk:=avatar.skeleton
	var hand:int=avatar.bone_index[side+"Hand"]
	var parent:int=sk.get_bone_parent(hand)
	var forward:Vector3=(sk.global_basis.inverse()*forward_world).normalized()
	var palm:Vector3=(sk.global_basis.inverse()*Vector3.DOWN).normalized()
	palm=(palm-forward*palm.dot(forward)).normalized()
	var desired:Basis=Basis(forward,palm,forward.cross(palm))*Basis(data.frame).inverse()*sk.get_bone_global_rest(hand).basis.orthonormalized()
	var wanted:Quaternion=(sk.get_bone_global_pose(parent).basis.orthonormalized().inverse()*desired).get_rotation_quaternion().normalized()
	var rest:Quaternion=avatar.bone_rest_local[hand]
	var angle:=rest.angle_to(wanted)
	if angle>deg_to_rad(75):wanted=rest.slerp(wanted,deg_to_rad(75)/angle)
	sk.set_bone_pose_rotation(hand,sk.get_bone_pose_rotation(hand).slerp(wanted,weight))
	return true

static func apply_fingers(avatar:VrmAvatar,side:String,weight:float)->void:
	var data:=anatomy(avatar,side)
	if data.is_empty():return
	for finger in data.fingers:
		var index:int=finger.bone
		var desired:Quaternion=(Quaternion(avatar.bone_rest_local[index])*Quaternion(finger.axis,float(finger.angle))).normalized()
		avatar.skeleton.set_bone_pose_rotation(index,avatar.skeleton.get_bone_pose_rotation(index).slerp(desired,clampf(weight,0,1)))

static func palm_world(avatar:VrmAvatar,side:String)->Vector3:
	var data:=anatomy(avatar,side)
	if data.is_empty():return Vector3.INF
	return avatar.skeleton.global_transform*(avatar.skeleton.get_bone_global_pose(avatar.bone_index[side+"Hand"])*Vector3(data.palm_offset))

static func solve(avatar:VrmAvatar,side:String,surface:Vector3,forward_world:Vector3,weight:float,loft_m:float=0)->Dictionary:
	var data:=anatomy(avatar,side)
	if data.is_empty() or not surface.is_finite() or not forward_world.is_finite() or not is_finite(weight):return {"reached":false,"reason":"missing_grip_anatomy"}
	var sk:=avatar.skeleton
	var forward:Vector3=(sk.global_basis.inverse()*forward_world).normalized()
	var palm:Vector3=(sk.global_basis.inverse()*Vector3.DOWN).normalized()
	palm=(palm-forward*palm.dot(forward)).normalized()
	var desired:Basis=Basis(forward,palm,forward.cross(palm))*Basis(data.frame).inverse()*sk.get_bone_global_rest(avatar.bone_index[side+"Hand"]).basis.orthonormalized()
	var wrist_target:Vector3=surface-sk.global_basis*(desired*Vector3(data.palm_offset))+Vector3.UP*loft_m
	var solved:=false
	var iterations:=3 if weight>.9 else 1
	var incoming:Dictionary={}
	for suffix in ["UpperArm","LowerArm","Hand"]:
		var index:int=avatar.bone_index[side+suffix]
		incoming[index]=sk.get_bone_pose_rotation(index)
	var correction_weight:=smoothstep(.9,1.0,weight)
	for i in iterations:
		for index in incoming:sk.set_bone_pose_rotation(index,incoming[index])
		solved=avatar.apply_hand_contact(side,wrist_target,weight)
		align_wrist(avatar,side,forward_world,weight)
		if i+1<iterations:wrist_target+=(surface+Vector3.UP*loft_m-palm_world(avatar,side))*correction_weight
	apply_fingers(avatar,side,smoothstep(.5,1.0,weight))
	var contact:=palm_world(avatar,side)
	var contact_error:=contact.distance_to(surface)
	var wrist_error:=avatar.bone_global_position(side+"Hand").distance_to(wrist_target)
	return {"reached":solved and contact_error<=.008,"contact_feature":"palm_pad_proxy","contact_world":contact,"surface_world":surface,"contact_error_m":contact_error,"wrist_target":wrist_target,"wrist_error_m":wrist_error,"ik":avatar.arm_ik.diagnostics.get(side,{}).duplicate(),"finger_weight":smoothstep(.5,1.0,weight)}
