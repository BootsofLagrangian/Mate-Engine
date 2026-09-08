extends RefCounted
## Small additive torso contact hint. Rig capsules bound torso/head, not garments.
const Bones := {"spine":3.0,"chest":2.0,"head":-2.0}
var normal := Vector3.INF
var target := Vector3.INF
var _radii := Vector3.ZERO
var _prepared := false
var _amplitude := 0.0
var diagnostics := {}
func configure(avatar: VrmAvatar, point: Vector3, outward: Vector3) -> void:
	normal=outward.normalized() if outward.is_finite() and outward.length()>0.5 else Vector3.INF
	target=point; _prepared=false; _amplitude=0.0; diagnostics.clear()
	if not normal.is_finite() or not avatar.has_model(): return
	var sk := avatar.skeleton
	for bone in ["leftUpperArm","rightUpperArm","neck","head","spine","chest","hips"]:
		if not avatar.bone_index.has(bone):normal=Vector3.INF;return
	var shoulder := sk.get_bone_global_rest(avatar.bone_index.leftUpperArm).origin.distance_to(sk.get_bone_global_rest(avatar.bone_index.rightUpperArm).origin)
	var neck := sk.get_bone_global_rest(avatar.bone_index.neck).origin.distance_to(sk.get_bone_global_rest(avatar.bone_index.head).origin)
	var scale := RigBodyCapsules.scale_bound(sk.global_transform.basis)
	_radii=Vector3(shoulder*.42,shoulder*.48,maxf(shoulder*.65,neck*2.2))*scale
func _clearance(avatar: VrmAvatar) -> float:
	var result := INF
	for bone in ["hips","chest"]:result=minf(result,normal.dot(avatar.bone_global_position(bone)-target)-_radii.x)
	for bone in ["chest","neck"]:result=minf(result,normal.dot(avatar.bone_global_position(bone)-target)-_radii.y)
	var sk := avatar.skeleton
	var idx: int=avatar.bone_index.head
	var rotation: Basis=sk.get_bone_global_pose(idx).basis.orthonormalized()*sk.get_bone_global_rest(idx).basis.orthonormalized().inverse()
	var up: Vector3=(sk.global_transform.basis*rotation*Vector3.UP).normalized()
	var head := avatar.bone_global_position("head")+up*_radii.z*.8
	return minf(result,normal.dot(head-target)-_radii.z)
func _offset(avatar: VrmAvatar, amount: float) -> void:
	var axis := Vector3.UP.cross(-normal).normalized()
	if axis.length()<0.5:return
	var sk := avatar.skeleton
	for bone in Bones:
		var idx: int=avatar.bone_index[bone]
		var parent := sk.get_bone_parent(idx)
		var frame: Basis=sk.global_transform.basis
		if parent>=0:frame=frame*sk.get_bone_global_pose(parent).basis
		var local_axis: Vector3=(frame.orthonormalized().inverse()*axis).normalized()
		sk.set_bone_pose_rotation(idx,(Quaternion(local_axis,deg_to_rad(float(Bones[bone])*amount))*sk.get_bone_pose_rotation(idx)).normalized())
func apply(avatar: VrmAvatar, weight: float) -> void:
	if not normal.is_finite() or not target.is_finite() or not avatar.has_model():return
	var original := {}
	for bone in Bones:original[bone]=avatar.skeleton.get_bone_pose_rotation(avatar.bone_index[bone])
	if not _prepared:
		_prepared=true
		for amount in [1.0,0.66,0.33]:
			_offset(avatar,amount)
			var clear := _clearance(avatar)>=0.003
			_restore(avatar,original)
			if clear:_amplitude=amount;break
	var applied := _amplitude*clampf(weight,0.0,1.0)
	_offset(avatar,applied)
	# Ambient motion is composed anew every frame. Never let a changed base pose
	# turn the cached amplitude into a new torso/head penetration.
	if _clearance(avatar)<0.0:
		_restore(avatar,original);applied=0.0
	diagnostics={"amplitude":applied,"clearance_m":_clearance(avatar),"scope":"torso_head_rig_capsules","preserves_hips_feet":true}
func _restore(avatar: VrmAvatar, pose: Dictionary) -> void:
	for bone in pose:avatar.skeleton.set_bone_pose_rotation(avatar.bone_index[bone],pose[bone])
