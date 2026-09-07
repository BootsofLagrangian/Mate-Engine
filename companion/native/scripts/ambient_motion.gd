class_name AmbientMotion
extends RefCounted
## Authored standing idle is independent of dialogue gesture ownership.
## Source translations drive the pelvis; final two-foot IK owns support.
var loop_name := ""
var action_name := ""
var time := 0.0
var action_time := 0.0
var weight := 0.0
var diagnostics: Dictionary = {}
var solver := LegIK.new()
var _owns_pose := false
var _hip_offset := Vector3.ZERO
var attention_override := false
var head_weight := 1.0
var _head_velocity := 0.0
var _blend_progress := 0.0
var _contact_origins: Dictionary = {}
var _contact_bases: Dictionary = {}

func reset() -> void:
	action_name = ""
	weight = 0.0
	time = 0.0
	action_time = 0.0
	diagnostics.clear()
	_owns_pose = false
	_hip_offset = Vector3.ZERO
	attention_override = false
	head_weight = 1.0
	_head_velocity = 0.0
	_blend_progress = 0.0
	_contact_origins.clear()
	_contact_bases.clear()

func advance(delta: float, clips: Dictionary, allowed: bool, avatar: VrmAvatar = null) -> void:
	if allowed and not _owns_pose and avatar != null:
		capture_contact_origin(avatar)
	var wanted_head := 0.0 if attention_override else 1.0
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining,1.0/120)
		var difference := wanted_head-head_weight
		var wanted_velocity := signf(difference)*minf(0.65,sqrt(1.6*absf(difference)))
		_head_velocity = move_toward(_head_velocity,wanted_velocity,0.8*step)
		var next := head_weight+_head_velocity*step
		if (wanted_head-head_weight)*(wanted_head-next) <= 0:
			head_weight = wanted_head
			_head_velocity = 0.0
		else:
			head_weight = clampf(next,0,1)
		remaining -= step
	time += delta
	if not action_name.is_empty():
		action_time += delta
		if not clips.has(action_name) or action_time >= clips[action_name].duration:
			action_name = ""
	_blend_progress = move_toward(_blend_progress,1.0 if allowed and clips.has(loop_name) else 0.0,delta/1.2)
	weight = smoothstep(0.0,1.0,_blend_progress)
	_owns_pose = allowed and (weight > 0.0001 or not action_name.is_empty())
	if not allowed:
		weight = 0.0
		_blend_progress = 0.0
		action_name = ""
		diagnostics.clear()

func owns_head() -> bool:
	return _owns_pose

func capture_contact_origin(avatar: VrmAvatar) -> void:
	_contact_origins.clear()
	_contact_bases.clear()
	if avatar == null or not avatar.has_model():
		return
	for side in ["left","right"]:
		if avatar.bone_index.has(side+"Foot"):
			_contact_origins[side] = avatar.skeleton.get_bone_global_pose(avatar.bone_index[side+"Foot"]).origin
			_contact_bases[side] = avatar.skeleton.get_bone_global_pose(avatar.bone_index[side+"Foot"]).basis.orthonormalized()

func apply(avatar: VrmAvatar, clips: Dictionary) -> void:
	if not _owns_pose:
		return
	var clip: VrmaClip = clips.get(loop_name)
	var active_weight := weight
	var sample_time := fmod(time,maxf(clip.duration,0.001)) if clip else 0.0
	if clip == null:
		return
	var pose := clip.sample(sample_time)
	var translation := clip.sample_hips_offset(sample_time)
	# Blend a short cyclic seam without resetting the ongoing body phase.
	if action_name.is_empty() and sample_time > clip.duration-0.15:
		var first := clip.sample(0)
		var seam := smoothstep(clip.duration-0.15,clip.duration,sample_time)
		for bone in pose:
			pose[bone] = pose[bone].slerp(first[bone],seam)
		translation = translation.lerp(clip.sample_hips_offset(0),seam)
	if not action_name.is_empty() and clips.has(action_name):
		var action: VrmaClip = clips[action_name]
		var action_pose := action.sample(action_time)
		var action_weight := smoothstep(0.0,0.6,action_time)*smoothstep(0.0,0.6,action.duration-action_time)
		for bone in action_pose:
			pose[bone] = pose.get(bone,Quaternion.IDENTITY).slerp(action_pose[bone],action_weight)
		translation = translation.lerp(action.sample_hips_offset(action_time),action_weight)
	var head_pose := {}
	for bone in ["head","neck"]:
		if pose.has(bone):
			head_pose[bone] = pose[bone]
			pose.erase(bone)
	avatar.apply_normalized_rotations(pose,active_weight)
	avatar.apply_normalized_rotations(head_pose,active_weight*head_weight)
	var hips_id: int = avatar.bone_index.get("hips",-1)
	if hips_id < 0:
		return
	var height := avatar.skeleton.get_bone_global_rest(hips_id).origin.y
	_hip_offset = translation*height*active_weight
	# Reject excessive root travel: these are standing-idle assets, not walks.
	_hip_offset = _hip_offset.limit_length(height*0.12)
	avatar.set_hips_offset(_hip_offset)
	diagnostics = {"loop":loop_name,"action":action_name,"time":sample_time,"weight":active_weight,"hips_offset":_hip_offset,"feet":{}}

func solve_contacts(avatar: VrmAvatar, force: bool = false, contact_weight: float = 1.0) -> void:
	if not _owns_pose and not force:
		return
	# Small safety flexion plus geometric reach lowering, never a constant crouch.
	var lowering := 0.0
	var solve_weight := clampf(contact_weight if force else weight,0,1)
	var hips: int = avatar.bone_index.hips
	var hips_parent := avatar.skeleton.get_bone_parent(hips)
	var hips_basis := avatar.skeleton.get_bone_global_pose(hips_parent).basis.orthonormalized() if hips_parent >= 0 else Basis.IDENTITY
	var current_offset := hips_basis*(avatar.skeleton.get_bone_pose_position(hips)-avatar.skeleton.get_bone_rest(hips).origin)
	var goals := {}
	for side in ["left","right"]:
		var upper: int = avatar.bone_index[side+"UpperLeg"]
		var lower: int = avatar.bone_index[side+"LowerLeg"]
		var foot: int = avatar.bone_index[side+"Foot"]
		var hip := avatar.skeleton.get_bone_global_pose(upper).origin
		var knee := avatar.skeleton.get_bone_global_pose(lower).origin
		var ankle := avatar.skeleton.get_bone_global_pose(foot).origin
		var rest_target := avatar.skeleton.get_bone_global_rest(foot).origin
		var target: Vector3 = Vector3(_contact_origins.get(side,rest_target)).lerp(rest_target,solve_weight)
		goals[side] = target
		var length := hip.distance_to(knee)+knee.distance_to(ankle)
		var reach := length*cos(deg_to_rad(3.0))-0.001
		var horizontal := Vector2(hip.x-target.x,hip.z-target.z).length()
		var vertical := sqrt(maxf(0,reach*reach-horizontal*horizontal))
		lowering = maxf(lowering,hip.y-target.y-vertical)
	avatar.set_hips_offset(current_offset-Vector3.UP*maxf(lowering,0))
	for side in ["left","right"]:
		var foot: int = avatar.bone_index[side+"Foot"]
		var rest_basis := avatar.skeleton.get_bone_global_rest(foot).basis.orthonormalized()
		var from_basis: Basis = _contact_bases.get(side,rest_basis)
		var foot_basis := Basis(from_basis.get_rotation_quaternion().slerp(rest_basis.get_rotation_quaternion(),solve_weight))
		solver.solve(avatar,side,goals[side],1.0,foot_basis,true)
	diagnostics["feet"] = solver.diagnostics.duplicate(true)
	diagnostics["contact_weight"] = solve_weight
