class_name DesktopGait
extends RefCounted
## Desktop-displacement driven gait. Coordinates are unscaled skeleton metres;
## the caller supplies actual OS-window displacement and effective px/metre.
const STANCE_FRACTION := 0.60
var view_yaw_radians := 0.0
var phase := 0.0
var phase_distance := 0.0 # unwrapped measured distance/angular target, diagnostic
var _phase_position := 0.0
var _phase_velocity := 0.0
var stride := 0.45
var diagnostics: Dictionary = {}
var leg_ik := LegIK.new()
var _velocity := Vector2.ZERO
var _pending := Vector2.ZERO
var _pending_world := Vector3.ZERO
var _support_height_offset := 0.0
var authored_locomotion: Dictionary = {}
var _scene_driven := false
var _scene_velocity_world := Vector3.ZERO
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
var steering := false
var steering_heading := 0.0

## Opt-in measured source gait. Phases use the source clip's raw zero; intervals
## may wrap across one. The source owns all swing/hip motion; only plants correct.
func configure_authored_locomotion(metadata: Dictionary = {}) -> bool:
	if metadata == authored_locomotion:
		return true
	if not metadata.is_empty():
		if not (metadata.get("version") is int or metadata.get("version") is float) or metadata.get("version") != 1 or not metadata.get("contacts") is Dictionary:
			return false
		var span = metadata.get("cycle_stride_leg_lengths")
		if not (span is float or span is int) or not is_finite(float(span)) or float(span) < 0.1 or float(span) > 5.0:
			return false
		var fade = metadata.get("contact_blend_phase",0.06)
		if not (fade is float or fade is int) or not is_finite(float(fade)) or float(fade) < 0.02 or float(fade) > 0.2:
			return false
		if metadata.has("preserve_source_hip_height") and not metadata.preserve_source_hip_height is bool: return false
		if metadata.has("hip_translation_limit_leg_lengths"):
			var hip_limit = metadata.hip_translation_limit_leg_lengths
			if not (hip_limit is float or hip_limit is int) or not is_finite(float(hip_limit)) or float(hip_limit) < 0 or float(hip_limit) > 0.5: return false
		for side in ["left","right"]:
			var intervals := _contact_intervals(metadata.contacts.get(side))
			if intervals.is_empty(): return false
			var segments: Array = []
			for interval in intervals:
				for endpoint in interval:
					if not (endpoint is float or endpoint is int) or not is_finite(float(endpoint)) or float(endpoint) < 0 or float(endpoint) >= 1:
						return false
				if fposmod(float(interval[1])-float(interval[0]),1.0) < float(fade)*2:
					return false
				var pieces: Array = [[interval[0],interval[1]]] if interval[0] < interval[1] else [[interval[0],1.0],[0.0,interval[1]]]
				for piece in pieces:
					for existing in segments:
						if maxf(piece[0],existing[0]) < minf(piece[1],existing[1]): return false
					segments.append(piece)

	authored_locomotion = metadata.duplicate(true)
	_feet.clear()
	_weight = 0.0
	_last_crouch = 0.0
	_pending = Vector2.ZERO
	_pending_world = Vector3.ZERO
	_support_height_offset = 0.0
	diagnostics.clear()
	return true

func _contact_intervals(value: Variant) -> Array:
	if not value is Array: return []
	if value.size() == 2 and not value[0] is Array: return [value]
	if value.is_empty() or value.size() > 4: return []
	for interval in value:
		if not interval is Array or interval.size() != 2: return []
	return value

func _take_movement(avatar: VrmAvatar) -> Vector3:
	var basis := avatar.skeleton.global_transform.basis
	var movement := basis.orthonormalized().inverse()*Basis(Vector3.UP,view_yaw_radians)*Vector3(_pending.x,-_pending.y,0)
	var world_movement := basis.inverse()*_pending_world
	movement += world_movement
	if _supported: _support_height_offset -= world_movement.y
	_pending = Vector2.ZERO
	_pending_world = Vector3.ZERO
	return movement

func begin_steering(avatar: VrmAvatar, heading: float) -> void:
	steering_heading = heading
	if steering or not avatar.has_model():
		return
	steering = true
	_avatar_id = avatar.model.get_instance_id()
	_last_yaw = avatar.rotation.y
	if _feet.is_empty():
		# Begin with the foot on the destination side leading. Thereafter phase
		# continues through angular and linear travel, including direction changes.
		phase = 0.5 if angle_difference(avatar.rotation.y,heading) > 0 else 0.0
		phase_distance = phase
		_phase_position = phase
		_phase_velocity = 0.0
		for side in ["left","right"]:
			var foot: int = avatar.bone_index[side+"Foot"]
			var pose := avatar.skeleton.get_bone_global_pose(foot)
			_feet[side] = {"target":pose.origin,"stance":true,"basis":pose.basis.orthonormalized()}

func end_steering() -> void:
	steering = false

func sample(velocity_px: Vector2, traveled_px: Vector2, pixels_per_metre: float, supported: bool, actual_world_delta: Variant = null) -> void:
	_scene_driven = false
	if (actual_world_delta != null and (not actual_world_delta is Vector3 or not actual_world_delta.is_finite())) or not velocity_px.is_finite() or not traveled_px.is_finite() or not is_finite(pixels_per_metre) or pixels_per_metre <= 1.0:
		_supported = false
		diagnostics.clear()
		_feet.clear()
		_pending = Vector2.ZERO
		_pending_world = Vector3.ZERO
		_support_height_offset = 0.0
		_weight = 0.0
		return
	if _last_ppm > 0 and absf(pixels_per_metre/_last_ppm-1.0) > 0.0001:
		_feet.clear()
		_weight = 0.0
		_support_height_offset = 0.0
		_pending = Vector2.ZERO
		_pending_world = Vector3.ZERO
		diagnostics.clear()
	if actual_world_delta is Vector3 and actual_world_delta.is_finite():
		_pending_world += actual_world_delta
	else:
		_pending += traveled_px/pixels_per_metre
	_velocity = velocity_px/pixels_per_metre
	_ppm = pixels_per_metre
	_last_ppm = pixels_per_metre
	_supported = supported
	if not supported and not steering:
		diagnostics.clear()
		_feet.clear()
		_support_height_offset = 0.0
		_pending = Vector2.ZERO
		_pending_world = Vector3.ZERO
	_age = 0.0
	var direction := signf(velocity_px.x)
	if absf(velocity_px.x) > 1.0:
		if _direction != 0 and direction != _direction and not steering:
			_feet.clear()
			_weight = 0.0
		_direction = direction
		phase_distance += absf(traveled_px.x/pixels_per_metre)/maxf(stride,0.1)

## Scene locomotion uses actual world X/Z arc length, including depth-only
## travel. Pixel X never substitutes for physical path distance or heading.
func sample_scene(avatar: VrmAvatar, velocity_world: Vector3, traveled_world: Vector3,
		supported: bool = true, distance_world_m: float = -1.0, reverse_phase: bool = false) -> void:
	if not avatar.has_model() or not velocity_world.is_finite() or not traveled_world.is_finite() or not is_finite(distance_world_m) or distance_world_m < -1.0:
		sample(Vector2.ZERO,Vector2.ZERO,2.0,false)
		return
	var inverse := avatar.skeleton.global_transform.basis.inverse()
	var horizontal_velocity := Vector3(velocity_world.x,0,velocity_world.z)
	var horizontal_delta := Vector3(traveled_world.x,0,traveled_world.z)
	var local_speed := (inverse*horizontal_velocity).length()
	# Keep normal sample lifecycle handling but suppress its screen-X phase.
	var prior_phase := phase_distance
	sample(Vector2(local_speed*1000,0),Vector2.ZERO,1000,supported,traveled_world)
	_scene_driven = true
	_scene_velocity_world = horizontal_velocity
	if supported:
		var distance := (inverse*horizontal_delta).length()
		if distance_world_m >= 0.0 and horizontal_delta.length() > 0.0000001:
			distance *= maxf(distance_world_m,horizontal_delta.length())/horizontal_delta.length()
		phase_distance = prior_phase+(-1.0 if reverse_phase else 1.0)*distance/maxf(stride,0.1)

## Exact critically damped pursuit smooths OS integer-pixel distance impulses.
## Contacts still compensate the full actual displacement on the same frame.
func advance_phase(delta: float) -> void:
	var omega := 18.0
	var error := _phase_position-phase_distance
	var term := _phase_velocity+omega*error
	var decay := exp(-omega*delta)
	_phase_position = phase_distance+(error+term*delta)*decay
	_phase_velocity = (_phase_velocity-omega*term*delta)*decay
	phase = fposmod(_phase_position,1.0)

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
		_support_height_offset = 0.0
		if _avatar_id != 0:
			_pending = Vector2.ZERO
			_pending_world = Vector3.ZERO
		_avatar_id = avatar.model.get_instance_id()
		_feet.clear()
		_weight = 0.0
		_last_yaw = avatar.rotation.y
	var yaw_delta := angle_difference(_last_yaw,avatar.rotation.y)
	var yaw_step := absf(yaw_delta)
	_last_yaw = avatar.rotation.y
	# A supported deceleration sample still owns its planted feet even below
	# the motion threshold. Releasing here (before the host ends the clip)
	# exposed the raw walk ankles and produced a visible pre-arrival stomp.
	var active := enabled and (has_sample() or steering)
	if steering:
		# Rotational travel also progresses a step, so anticipation cannot twist
		# both planted feet while waiting for linear displacement to begin.
		phase_distance += yaw_step*0.16/maxf(stride,0.1)
	if not enabled:
		# MotionPlayer's common inertial transition already carries the final
		# solved leg pose and velocity. A second frozen-pose fade here would
		# overwrite that handoff and stop moving knees on its first frame.
		_feet.clear()
		_weight = 0.0
		_last_leg_pose.clear()
		_pending = Vector2.ZERO
		_pending_world = Vector3.ZERO
		_support_height_offset = 0.0
		diagnostics.clear()
		return
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
			if state.has("basis"):
				state.basis = undo_turn*Basis(state.basis)
			if state.has("lift_basis"):
				state.lift_basis = undo_turn*Basis(state.lift_basis)
			if state.has("lift_off"):
				state.lift_off = pivot+undo_turn*(Vector3(state.lift_off)-pivot)
			_feet[side] = state
	_weight = move_toward(_weight,1.0 if active else 0.0,delta/0.25)
	var movement := _take_movement(avatar)
	diagnostics.clear()
	if not active:
		_weight = 0.0
		_last_leg_pose.clear()
		return
	if _weight <= 0.0:
		return
	var leg_length := 0.8
	if avatar.bone_index.has("leftUpperLeg") and avatar.bone_index.has("leftFoot"):
		leg_length = sk.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(sk.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
	if not authored_locomotion.is_empty():
		stride = leg_length*float(authored_locomotion.cycle_stride_leg_lengths)
		_apply_authored_contacts(avatar,movement)
		return
	# Shorter steps at low speed keep cadence conversational. Bound and slowly
	# adapt stride; the phase itself always advances by actual travelled length.
	var wanted_stride := clampf(absf(_velocity.x)*1.45,leg_length*0.28,leg_length*0.95)
	if is_driven():
		stride = lerpf(stride,wanted_stride,1-exp(-2.0*delta))
	var targets := {}
	var travel := sk.global_transform.basis.orthonormalized().inverse()*Basis(Vector3.UP,view_yaw_radians)*Vector3(_velocity.x,0,0)
	if _scene_driven: travel = sk.global_transform.basis.inverse()*_scene_velocity_world
	if travel.length() < 0.001:
		travel = Basis(Vector3.UP,angle_difference(avatar.rotation.y,steering_heading))*Vector3.BACK if steering else Vector3.BACK
	travel.y = 0
	travel = travel.normalized()
	for side in ["left","right"]:
		if not avatar.bone_index.has(side+"Foot"):
			continue
		var foot: int = avatar.bone_index[side+"Foot"]
		var rest := sk.get_bone_global_rest(foot).origin
		rest.y += _support_height_offset
		var cycle := fposmod(phase+(0.0 if side == "left" else 0.5),1.0)
		var stance := cycle < STANCE_FRACTION
		var prior: Dictionary = _feet.get(side,{})
		var target := rest
		var rest_basis := sk.get_bone_global_rest(foot).basis.orthonormalized()
		var landing_basis := Basis(Vector3.UP,angle_difference(avatar.rotation.y,steering_heading))*rest_basis if steering else rest_basis
		if stance:
			if prior.is_empty() or not bool(prior.get("stance",false)):
				# If contact begins mid-stance, plant under the current animated
				# ankle, not at an unrelated heel-strike position.
				target = sk.get_bone_global_pose(foot).origin if prior.is_empty() else Vector3(prior.target)
				target.y = rest.y
				if not prior.has("basis"):
					prior.basis = sk.get_bone_global_pose(foot).basis.orthonormalized()
			else:
				target = Vector3(prior.target)-movement
				target.y = rest.y
		else:
			var lift_off: Vector3 = prior.get("lift_off",sk.get_bone_global_pose(foot).origin)
			if prior.is_empty() or bool(prior.get("stance",true)):
				lift_off = prior.get("target",sk.get_bone_global_pose(foot).origin)
				lift_off.y = rest.y
				prior.lift_basis = prior.get("basis",sk.get_bone_global_pose(foot).basis.orthonormalized())
			var u := (cycle-STANCE_FRACTION)/(1-STANCE_FRACTION)
			var eased := u*u*u*(u*(u*6-15)+10)
			var landing := rest+travel*stride*0.30
			target = lift_off.lerp(landing,eased)
			target.y = rest.y+minf(leg_length*0.08,stride*0.15)*sin(u*PI)*sin(u*PI)
			prior.lift_off = lift_off
			var lift_basis: Basis = prior.get("lift_basis",rest_basis)
			prior.basis = Basis(lift_basis.get_rotation_quaternion().slerp(landing_basis.get_rotation_quaternion(),eased))
		targets[side] = target
		prior.target = target
		prior.stance = stance
		_feet[side] = prior
	var required := _required_lowering(avatar,targets)
	_last_crouch = lerpf(_last_crouch,-required,1-exp(-12.0*delta))
	_applied_height = _last_crouch*_weight
	avatar.set_hips_offset(avatar.get_hips_offset()+Vector3.UP*_applied_height)
	for side in targets:
		leg_ik.solve(avatar,side,targets[side],_weight,_feet[side].get("basis",Basis.IDENTITY),true)
		_record_diagnostic(side)
	_capture_leg_pose(avatar)

## Called by the host's post-window-move sample. Correct the already posed
## stance immediately in this same rendered frame; do not wait one frame.
func compensate_movement(avatar: VrmAvatar) -> void:
	if not avatar.has_model():
		_pending = Vector2.ZERO
		_pending_world = Vector3.ZERO
		return
	var movement := _take_movement(avatar)
	if not _supported or _feet.is_empty():
		return
	if not authored_locomotion.is_empty():
		_compensate_authored_contacts(avatar,movement)
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
		var prior_height := _applied_height
		_last_crouch = -required
		_applied_height = _last_crouch*_weight
		avatar.set_hips_offset(avatar.get_hips_offset()+Vector3.UP*(_applied_height-prior_height))
	for side in targets:
		leg_ik.solve(avatar,side,targets[side],_weight,_feet[side].get("basis",Basis.IDENTITY),true)
		_record_diagnostic(side)
	_capture_leg_pose(avatar)


func _apply_authored_contacts(avatar: VrmAvatar, movement: Vector3) -> void:
	var sk := avatar.skeleton
	for side in ["left","right"]:
		if not avatar.bone_index.has(side+"Foot"):
			continue
		var foot: int = avatar.bone_index[side+"Foot"]
		var pose := sk.get_bone_global_pose(foot)
		var duration := 0.0
		var t := 1.0
		var contact := false
		var interval_index := -1
		var intervals := _contact_intervals(authored_locomotion.contacts[side])
		for i in intervals.size():
			var interval: Array = intervals[i]
			duration = fposmod(float(interval[1])-float(interval[0]),1.0)
			t = fposmod(phase-float(interval[0]),1.0)
			if t < duration:
				contact = true
				interval_index = i
				break
		var prior: Dictionary = _feet.get(side,{})
		var weight := 0.0
		if contact:
			var fade := float(authored_locomotion.get("contact_blend_phase",0.06))
			weight = smoothstep(0.0,fade,t)*smoothstep(0.0,fade,duration-t)*_weight
			if prior.is_empty() or not bool(prior.get("stance",false)) or prior.get("interval",-1) != interval_index:
				prior.target = pose.origin
				prior.basis = pose.basis.orthonormalized()
			else:
				prior.target = Vector3(prior.target)-movement
		else:
			prior.target = pose.origin
			prior.basis = pose.basis.orthonormalized()
		prior.stance = contact
		prior.contact_weight = weight
		prior.interval = interval_index
		# Keep the source pose so a post-window correction replaces, rather than
		# cumulatively applies, a partial contact blend on this same frame.
		prior.source_rotations = _source_leg_rotations(avatar,side)
		_feet[side] = prior
		_solve_authored_contact(avatar,side)
	_capture_leg_pose(avatar)

func _source_leg_rotations(avatar: VrmAvatar, side: String) -> Dictionary:
	var result := {}
	for suffix in ["UpperLeg","LowerLeg","Foot"]:
		if avatar.bone_index.has(side+suffix):
			var index: int = avatar.bone_index[side+suffix]
			result[index] = avatar.skeleton.get_bone_pose_rotation(index)
	return result

func _solve_authored_contact(avatar: VrmAvatar, side: String) -> void:
	var state: Dictionary = _feet[side]
	var weight := float(state.get("contact_weight",0.0))
	if weight > 0.0:
		leg_ik.solve(avatar,side,state.target,weight,state.basis,true)
		_record_diagnostic(side)
	else:
		# Zero correction is literal source preservation, including authored
		# knee pole/foot roll. There is no synthetic swing trajectory.
		diagnostics[side] = {"stance":false,"weight":0.0,"phase":phase,"stride":stride,"pelvis_lowering":0.0}
	diagnostics[side].authored = true
	diagnostics[side].contact_weight = weight
	diagnostics[side].stance = bool(state.stance) and weight >= 0.999

func _compensate_authored_contacts(avatar: VrmAvatar, movement: Vector3) -> void:
	for side in _feet:
		var state: Dictionary = _feet[side]
		if not bool(state.get("stance",false)):
			continue
		state.target = Vector3(state.target)-movement
		for index in state.get("source_rotations",{}):
			avatar.skeleton.set_bone_pose_rotation(index,state.source_rotations[index])
		_feet[side] = state
		_solve_authored_contact(avatar,side)
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
