class_name LegIK
extends RefCounted
## Two-bone leg solve in skeleton coordinates. A forward knee pole excludes
## backwards knee bends. Limits: 2..140 degrees flexion, fixed bone lengths.
var diagnostics: Dictionary = {}
func solve(avatar: VrmAvatar, side: String, ankle_target: Vector3, weight: float, foot_basis: Basis = Basis.IDENTITY, use_foot_basis: bool = false) -> void:
	var sk := avatar.skeleton
	var ids: Array[int] = []
	for suffix in ["UpperLeg","LowerLeg","Foot"]:
		if not avatar.bone_index.has(side+suffix):
			return
		ids.append(avatar.bone_index[side+suffix])
	var initial: Array[Quaternion] = []
	for idx in ids:
		initial.append(sk.get_bone_pose_rotation(idx))
	var hip := sk.get_bone_global_pose(ids[0]).origin
	var knee := sk.get_bone_global_pose(ids[1]).origin
	var ankle := sk.get_bone_global_pose(ids[2]).origin
	var thigh := hip.distance_to(knee)
	var shin := knee.distance_to(ankle)
	if minf(thigh,shin) < 0.001:
		return
	var requested := ankle_target-hip
	var minimum := sqrt(thigh*thigh+shin*shin+2*thigh*shin*cos(deg_to_rad(140)))
	var maximum := sqrt(thigh*thigh+shin*shin+2*thigh*shin*cos(deg_to_rad(2)))
	var distance := clampf(requested.length(),minimum,maximum)
	var direction := requested.normalized() if requested.length() > 0.00001 else Vector3.DOWN
	var pole := Vector3.BACK-direction*direction.dot(Vector3.BACK)
	if pole.length_squared() < 0.00001:
		pole = Vector3.RIGHT-direction*direction.dot(Vector3.RIGHT)
	pole = pole.normalized()
	var along := (thigh*thigh-shin*shin+distance*distance)/(2*distance)
	var knee_goal := hip+direction*along+pole*sqrt(maxf(0,thigh*thigh-along*along))
	var ankle_goal := hip+direction*distance
	_rotate(sk,ids[0],knee-hip,knee_goal-hip)
	knee = sk.get_bone_global_pose(ids[1]).origin
	ankle = sk.get_bone_global_pose(ids[2]).origin
	_rotate(sk,ids[1],ankle-knee,ankle_goal-knee)
	# Keep the sole parallel to the support plane; ankle rotation cancels shin
	# swing instead of dragging the toe through the desktop surface.
	var parent := sk.get_bone_parent(ids[2])
	var wanted_foot := foot_basis if use_foot_basis else sk.get_bone_global_rest(ids[2]).basis.orthonormalized()
	var basis := sk.get_bone_global_pose(parent).basis.orthonormalized().inverse()*wanted_foot
	sk.set_bone_pose_rotation(ids[2],basis.get_rotation_quaternion().normalized())
	for i in ids.size():
		var solved := sk.get_bone_pose_rotation(ids[i])
		sk.set_bone_pose_rotation(ids[i],initial[i].slerp(solved,clampf(weight,0,1)))
	var actual := sk.get_bone_global_pose(ids[2]).origin
	diagnostics[side] = {"requested":ankle_target,"target":ankle_goal,"actual":actual,"error":actual.distance_to(ankle_target),"reach_clamp":ankle_goal.distance_to(ankle_target),"knee_degrees":rad_to_deg(acos(clampf((distance*distance-thigh*thigh-shin*shin)/(2*thigh*shin),-1,1)))}
func _rotate(sk: Skeleton3D, idx: int, from: Vector3, to: Vector3) -> void:
	var basis := sk.get_bone_global_pose(idx).basis.orthonormalized()
	var parent := sk.get_bone_parent(idx)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(idx,(parent_basis.inverse()*Basis(Quaternion(from.normalized(),to.normalized()))*basis).get_rotation_quaternion().normalized())
