class_name DesktopGait
extends RefCounted
## Desktop-displacement driven gait. Coordinates are unscaled skeleton metres;
## the caller supplies actual OS-window displacement and effective px/metre.
const STANCE_FRACTION := 0.60
var phase := 0.0
var stride := 0.45
var diagnostics: Dictionary = {}
var leg_ik := LegIK.new()
var _velocity := Vector2.ZERO
var _pending := Vector2.ZERO
var _ppm := 0.0
var _age := INF
var _supported := false
var _weight := 0.0
var _feet: Dictionary = {}
var _avatar_id := 0
var _last_yaw := 0.0
var _last_ppm := 0.0
var _direction := 0.0
var _last_leg_pose: Dictionary = {}
var _last_crouch := 0.0
var _applied_height := 0.0

func sample(velocity_px: Vector2, traveled_px: Vector2, pixels_per_metre: float, supported: bool) -> void:
	if not velocity_px.is_finite() or not traveled_px.is_finite() or not is_finite(pixels_per_metre) or pixels_per_metre <= 1.0:
		_supported = false
		diagnostics.clear()
		_feet.clear()
		return
	if _last_ppm > 0 and absf(pixels_per_metre/_last_ppm-1.0) > 0.0001:
		_feet.clear()
		_weight = 0.0
		diagnostics.clear()
	_pending += traveled_px/pixels_per_metre
	_velocity = velocity_px/pixels_per_metre
	_ppm = pixels_per_metre
	_last_ppm = pixels_per_metre
	_supported = supported
	if not supported:
		diagnostics.clear()
		_feet.clear()
	_age = 0.0
	var direction := signf(velocity_px.x)
	if absf(velocity_px.x) > 1.0:
		if _direction != 0 and direction != _direction:
			_feet.clear()
			_weight = 0.0
		_direction = direction
		phase = fposmod(phase+absf(traveled_px.x/pixels_per_metre)/maxf(stride,0.1),1.0)

func has_sample() -> bool:
	return _age < 0.15 and _supported

func is_driven() -> bool:
	return has_sample() and _velocity.length() > 0.015

func apply(avatar: VrmAvatar, delta: float, enabled: bool) -> void:
	_age += delta
	if not avatar.has_model():
		return
	var sk := avatar.skeleton
	_applied_height = 0.0 # VrmAvatar.apply_pose restored the hip translation this frame.
	if _avatar_id != avatar.model.get_instance_id():
		_avatar_id = avatar.model.get_instance_id()
		_feet.clear()
		_weight = 0.0
		_last_yaw = avatar.rotation.y
	var yaw_delta := angle_difference(_last_yaw,avatar.rotation.y)
	var yaw_step := absf(yaw_delta)
	_last_yaw = avatar.rotation.y
	# Replant during turns; a planted target in an obsolete body frame creates
	# knee torsion. Resume only when facing has almost stopped changing.
	var active := enabled and is_driven() and yaw_step < deg_to_rad(0.45)
	if not active:
		_feet.clear()
	elif not is_zero_approx(yaw_delta) and avatar.bone_index.has("hips"):
		# Small residual turn after the turn-release gate: rotate cached contacts
		# around the host's stable hip/foot pivot so desktop plants do not drift.
		var pivot := sk.get_bone_global_rest(avatar.bone_index.hips).origin
		var undo_turn := Basis(Vector3.UP,-yaw_delta)
		for side in _feet:
			var state: Dictionary = _feet[side]
			state.target = pivot+undo_turn*(Vector3(state.target)-pivot)
			if state.has("lift_off"):
				state.lift_off = pivot+undo_turn*(Vector3(state.lift_off)-pivot)
			_feet[side] = state
	_weight = move_toward(_weight,1.0 if active else 0.0,delta/0.25)
	var movement := sk.global_transform.basis.orthonormalized().inverse()*Vector3(_pending.x,-_pending.y,0)
	_pending = Vector2.ZERO
	diagnostics.clear()
	if not active:
		if _weight > 0.0:
			avatar.set_hips_height_offset(_last_crouch*_weight)
			for idx in _last_leg_pose:
				if idx < sk.get_bone_count():
					sk.set_bone_pose_rotation(idx,sk.get_bone_pose_rotation(idx).slerp(_last_leg_pose[idx],_weight))
		else:
			_last_leg_pose.clear()
		return
	if _weight <= 0.0:
		return
	var leg_length := 0.8
	if avatar.bone_index.has("leftUpperLeg") and avatar.bone_index.has("leftFoot"):
		leg_length = sk.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(sk.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
	# Shorter steps at low speed keep cadence conversational. Bound and slowly
	# adapt stride; the phase itself always advances by actual travelled length.
	var wanted_stride := clampf(absf(_velocity.x)*1.45,leg_length*0.28,leg_length*0.95)
	stride = lerpf(stride,wanted_stride,1-exp(-2.0*delta))
	var targets := {}
	for side in ["left","right"]:
		if not avatar.bone_index.has(side+"Foot"):
			continue
		var foot: int = avatar.bone_index[side+"Foot"]
		var rest := sk.get_bone_global_rest(foot).origin
		var cycle := fposmod(phase+(0.0 if side == "left" else 0.5),1.0)
		var stance := cycle < STANCE_FRACTION
		var prior: Dictionary = _feet.get(side,{})
		var target := rest
		if stance:
			if prior.is_empty() or not bool(prior.get("stance",false)):
				# If contact begins mid-stance, plant under the current animated
				# ankle, not at an unrelated heel-strike position.
				target = sk.get_bone_global_pose(foot).origin if prior.is_empty() else Vector3(prior.target)
				target.y = rest.y
			else:
				target = Vector3(prior.target)-movement
				target.y = rest.y
		else:
			var lift_off: Vector3 = prior.get("lift_off",sk.get_bone_global_pose(foot).origin)
			if prior.is_empty() or bool(prior.get("stance",true)):
				lift_off = prior.get("target",sk.get_bone_global_pose(foot).origin)
				lift_off.y = rest.y
			var u := (cycle-STANCE_FRACTION)/(1-STANCE_FRACTION)
			var eased := u*u*u*(u*(u*6-15)+10)
			var landing := rest+Vector3.BACK*stride*0.30
			target = lift_off.lerp(landing,eased)
			target.y = rest.y+minf(leg_length*0.08,stride*0.15)*sin(u*PI)*sin(u*PI)
			prior.lift_off = lift_off
		targets[side] = target
		prior.target = target
		prior.stance = stance
		_feet[side] = prior
	var required := _required_lowering(avatar,targets)
	_last_crouch = lerpf(_last_crouch,-required,1-exp(-12.0*delta))
	_applied_height = _last_crouch*_weight
	avatar.set_hips_height_offset(_applied_height)
	for side in targets:
		leg_ik.solve(avatar,side,targets[side],_weight)
		_record_diagnostic(side)
	_capture_leg_pose(avatar)

## Called by the host's post-window-move sample. Correct the already posed
## stance immediately in this same rendered frame; do not wait one frame.
func compensate_movement(avatar: VrmAvatar) -> void:
	if not avatar.has_model():
		_pending = Vector2.ZERO
		return
	var movement := avatar.skeleton.global_transform.basis.orthonormalized().inverse()*Vector3(_pending.x,-_pending.y,0)
	_pending = Vector2.ZERO
	if not _supported or _feet.is_empty():
		return
	var targets := {}
	for side in _feet:
		var state: Dictionary = _feet[side]
		if bool(state.get("stance",false)):
			state.target = Vector3(state.target)-movement
		_feet[side] = state
		targets[side] = state.target
	# Actual movement may extend a support leg after the normal pose pass.
	# Add only the geometric clearance needed, then re-solve both legs.
	var required := _required_lowering(avatar,targets)
	if -required*_weight < _applied_height:
		_last_crouch = -required
		_applied_height = _last_crouch*_weight
		avatar.set_hips_height_offset(_applied_height)
	for side in targets:
		leg_ik.solve(avatar,side,targets[side],_weight)
		_record_diagnostic(side)
	_capture_leg_pose(avatar)


func _capture_leg_pose(avatar: VrmAvatar) -> void:
	for side in ["left","right"]:
		for suffix in ["UpperLeg","LowerLeg","Foot"]:
			if avatar.bone_index.has(side+suffix):
				var idx: int = avatar.bone_index[side+suffix]
				_last_leg_pose[idx] = avatar.skeleton.get_bone_pose_rotation(idx)


func _required_lowering(avatar: VrmAvatar, targets: Dictionary) -> float:
	var required := 0.0
	var sk := avatar.skeleton
	for side in targets:
		var hip := sk.get_bone_global_pose(avatar.bone_index[side+"UpperLeg"]).origin
		var knee := sk.get_bone_global_pose(avatar.bone_index[side+"LowerLeg"]).origin
		var ankle := sk.get_bone_global_pose(avatar.bone_index[side+"Foot"]).origin
		var thigh := hip.distance_to(knee)
		var shin := knee.distance_to(ankle)
		var reach_squared := thigh*thigh+shin*shin+2*thigh*shin*cos(deg_to_rad(6.0))
		hip.y -= _applied_height
		var target: Vector3 = targets[side]
		var horizontal_squared := pow(hip.x-target.x,2)+pow(hip.z-target.z,2)
		var allowed_height := sqrt(maxf(0.001,reach_squared-horizontal_squared))
		required = maxf(required,hip.y-target.y-allowed_height)
	return clampf(required+0.002,0.002,0.09)

func _record_diagnostic(side: String) -> void:
	var measured: Dictionary = leg_ik.diagnostics.get(side,{}).duplicate()
	measured["stance"] = bool(_feet[side].get("stance",false)) and _weight >= 0.999
	measured["weight"] = _weight
	measured["phase"] = fposmod(phase+(0.0 if side == "left" else 0.5),1.0)
	measured["stride"] = stride
	measured["pelvis_lowering"] = -_applied_height
	diagnostics[side] = measured
