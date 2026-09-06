class_name TurnStepper
extends RefCounted
## Turn-in-place contacts are stored in an unscaled world-oriented frame about
## the host's stable foot pivot. One foot stays planted while the other travels
## through an X/Z arc with clearance; the body never swivels both planted shoes.
const STEP_SECONDS := 0.55
var diagnostics: Dictionary = {}
var active := false
var _avatar_id := 0
var _feet: Dictionary = {}
var _swing := "left"
var _time := 0.0
var _swing_start := Vector3.ZERO
var _swing_basis := Basis.IDENTITY
var _pivot := Vector3.ZERO
var _start_yaw := 0.0
var _last_yaw := 0.0
var _weight := 0.0
var _ik := LegIK.new()
var _last_pose: Dictionary = {}
var _height := 0.0

func begin(avatar: VrmAvatar, target_yaw: float) -> void:
	if not avatar.has_model():
		return
	if active and _avatar_id != avatar.model.get_instance_id():
		cancel()
	if active:
		return
	_avatar_id = avatar.model.get_instance_id()
	var sk := avatar.skeleton
	_pivot = sk.get_bone_global_rest(avatar.bone_index.hips).origin
	_pivot.y = float(avatar.sole_calibration.get("floor_y",0.0))
	_start_yaw = avatar.rotation.y
	_last_yaw = _start_yaw
	var orientation := Basis(Vector3.UP,_start_yaw)
	_feet.clear()
	for side in ["left","right"]:
		if not avatar.bone_index.has(side+"Foot"):
			return
		var idx: int = avatar.bone_index[side+"Foot"]
		var ankle := sk.get_bone_global_pose(idx).origin
		ankle.y = sk.get_bone_global_rest(idx).origin.y
		_feet[side] = {"point":orientation*(ankle-_pivot),"basis":orientation*sk.get_bone_global_pose(idx).basis.orthonormalized()}
	_swing = "left" if angle_difference(_start_yaw,target_yaw) >= 0 else "right"
	_time = 0.0
	_weight = 0.0
	active = true
	_begin_step()

func _begin_step() -> void:
	_swing_start = _feet[_swing].point
	_swing_basis = _feet[_swing].basis
	_time = 0.0

func apply(avatar: VrmAvatar, delta: float, target_yaw: float, blocked: bool = false) -> void:
	diagnostics.clear()
	if not active or not avatar.has_model():
		return
	if _avatar_id != avatar.model.get_instance_id():
		cancel()
		return
	if blocked:
		active = false
		_feet.clear()
		return
	var sk := avatar.skeleton
	var yaw := avatar.rotation.y
	var orientation := Basis(Vector3.UP,yaw)
	var inverse := orientation.inverse()
	_time += delta
	_weight = minf(1.0,_weight+delta/0.18)
	var u := clampf(_time/STEP_SECONDS,0,1)
	var ease := u*u*u*(u*(u*6-15)+10)
	var swing_idx: int = avatar.bone_index[_swing+"Foot"]
	var rest := sk.get_bone_global_rest(swing_idx)
	# The destination is the new stance at current body heading. X/Z both
	# change around the planted support; this is a geometric arc, not Z bob.
	var landing := orientation*(rest.origin-_pivot)
	var radius_start := Vector2(_swing_start.x,_swing_start.z)
	var radius_end := Vector2(landing.x,landing.z)
	var angle_start := atan2(radius_start.y,radius_start.x)
	var angle_end := atan2(radius_end.y,radius_end.x)
	var angle := lerp_angle(angle_start,angle_end,ease)
	var radius := lerpf(radius_start.length(),radius_end.length(),ease)
	var point := Vector3(cos(angle)*radius,lerpf(_swing_start.y,landing.y,ease),sin(angle)*radius)
	point.y += 0.035*sin(PI*u)*sin(PI*u)
	_feet[_swing].point = point
	_feet[_swing].basis = Basis(_swing_basis.get_rotation_quaternion().slerp((orientation*rest.basis.orthonormalized()).get_rotation_quaternion(),ease))
	var goals := {}
	for side in _feet:
		goals[side] = _pivot+inverse*Vector3(_feet[side].point)
	# Lower the pelvis only enough for the held ankle targets to be reachable.
	var required := 0.0
	for side in goals:
		var hip := sk.get_bone_global_pose(avatar.bone_index[side+"UpperLeg"]).origin
		var knee := sk.get_bone_global_pose(avatar.bone_index[side+"LowerLeg"]).origin
		var ankle := sk.get_bone_global_pose(avatar.bone_index[side+"Foot"]).origin
		var l1 := hip.distance_to(knee)
		var l2 := knee.distance_to(ankle)
		var target: Vector3 = goals[side]
		var reach := l1*l1+l2*l2+2*l1*l2*cos(deg_to_rad(6))
		var horizontal := pow(hip.x-target.x,2)+pow(hip.z-target.z,2)
		required = maxf(required,hip.y-target.y-sqrt(maxf(0.001,reach-horizontal)))
	_height = clampf(required+0.002,0.002,0.06)*_weight
	var support_side := "right" if _swing == "left" else "left"
	var support_idx: int = avatar.bone_index[support_side+"Foot"]
	var support_rest := sk.get_bone_global_rest(support_idx)
	var settled_support := Vector3(_feet[support_side].point).distance_to(orientation*(support_rest.origin-_pivot)) < 0.008
	if absf(angle_difference(yaw,target_yaw)) < deg_to_rad(1.0) and settled_support:
		_height *= 1.0-smoothstep(0.6,1.0,u)
	avatar.set_hips_height_offset(-_height)
	for side in goals:
		var foot_basis: Basis = inverse*Basis(_feet[side].basis)
		_ik.solve(avatar,side,goals[side],_weight,foot_basis,true)
		var measured: Dictionary = _ik.diagnostics.get(side,{}).duplicate()
		measured["stance"] = side != _swing and _weight >= 0.999
		measured["swing"] = side == _swing
		measured["turn_phase"] = u
		measured["world_pivot_relative_target"] = _feet[side].point
		diagnostics[side] = measured
	_last_yaw = yaw
	if u >= 1:
		var heading_error := absf(angle_difference(yaw,target_yaw))
		var other := "right" if _swing == "left" else "left"
		var other_idx: int = avatar.bone_index[other+"Foot"]
		var other_wanted := orientation*(sk.get_bone_global_rest(other_idx).origin-_pivot)
		var distance := Vector3(_feet[other].point).distance_to(other_wanted)
		var foot_yaw_error := Basis(_feet[other].basis).get_rotation_quaternion().angle_to((orientation*sk.get_bone_global_rest(other_idx).basis.orthonormalized()).get_rotation_quaternion())
		if heading_error < deg_to_rad(1.0) and distance < 0.008 and foot_yaw_error < deg_to_rad(5):
			active = false
		else:
			_swing = other
			_begin_step()

func cancel() -> void:
	active = false
	_avatar_id = 0
	_feet.clear()
	diagnostics.clear()
