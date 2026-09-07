class_name ArmIK
extends RefCounted
## Analytic two-bone solve in skeleton space. A fixed torso-relative pole avoids
## elbow flips. Reach is clamped to elbow flexion [8, 145] degrees.
var diagnostics: Dictionary = {}

func solve(avatar: VrmAvatar, side: String, goal: Vector3, pole: Vector3) -> void:
	var sk := avatar.skeleton
	var ids: Array[int] = []
	for suffix in ["UpperArm", "LowerArm", "Hand"]:
		if not avatar.bone_index.has(side + suffix):
			return
		ids.append(avatar.bone_index[side + suffix])
	var a := sk.get_bone_global_pose(ids[0]).origin
	var b := sk.get_bone_global_pose(ids[1]).origin
	var c := sk.get_bone_global_pose(ids[2]).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if minf(l1, l2) < 0.00001:
		return
	var requested := goal - a
	var dmin := sqrt(l1*l1 + l2*l2 + 2*l1*l2*cos(deg_to_rad(145.0)))
	var dmax := sqrt(l1*l1 + l2*l2 + 2*l1*l2*cos(deg_to_rad(8.0)))
	var distance := clampf(requested.length(), dmin, dmax)
	var direction := requested.normalized() if requested.length() > 0.00001 else Vector3.DOWN
	var tangent := pole - a
	tangent -= direction * tangent.dot(direction)
	if tangent.length_squared() < 0.00001:
		tangent = direction.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.00001:
		tangent = direction.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var along := (l1*l1 - l2*l2 + distance*distance) / (2.0*distance)
	var elbow := a + direction*along + tangent*sqrt(maxf(0.0,l1*l1-along*along))
	var wrist := a + direction*distance
	_rotate_to(sk, ids[0], b-a, elbow-a)
	b = sk.get_bone_global_pose(ids[1]).origin
	c = sk.get_bone_global_pose(ids[2]).origin
	_rotate_to(sk, ids[1], c-b, wrist-b)
	var actual := sk.get_bone_global_pose(ids[2]).origin
	diagnostics[side] = {"requested": goal, "target": wrist, "actual": actual, "error": actual.distance_to(wrist), "clamped": goal.distance_to(wrist), "elbow_degrees": rad_to_deg(acos(clampf((distance*distance-l1*l1-l2*l2)/(2*l1*l2),-1,1)))}

func _rotate_to(sk: Skeleton3D, idx: int, from: Vector3, to: Vector3) -> void:
	var global_basis := sk.get_bone_global_pose(idx).basis.orthonormalized()
	var rotation := Quaternion(from.normalized(), to.normalized())
	var parent := sk.get_bone_parent(idx)
	var parent_basis := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(idx, (parent_basis.inverse() * Basis(rotation) * global_basis).get_rotation_quaternion().normalized())
