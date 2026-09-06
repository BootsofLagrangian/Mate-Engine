class_name SeatedTransition
extends RefCounted
## Finite authored motion, with its measured pelvis trajectory shared with host.
## Host applies root_delta*root_progress; this layer never moves the OS window.
var clips:Dictionary={}
var active:=false
var kind:=""
var clip_name:=""
var time:=0.0
var duration:=0.0
var root_delta:=Vector3.ZERO
var diagnostics:Dictionary={}
var _from:Dictionary={}
var _from_hips:=Vector3.ZERO
var _from_velocity:Dictionary={}
var _from_hips_velocity:=Vector3.ZERO
var _floor_end:=-INF
var _model_id:=0
var _bounds:=AABB()
var _bounds_cache:Dictionary={}
const ACQUIRE:=0.20

func reset() -> void:
	active=false
	kind=""
	diagnostics.clear()
	_from.clear()
	_from_velocity.clear()
	_from_hips_velocity=Vector3.ZERO

func register_clip(mode:String,name:String,available:Dictionary) -> bool:
	if mode not in ["enter","exit"] or not available.has(name):return false
	var clip:VrmaClip=available[name]
	if clip.hips_translation.is_empty() or clip.duration<0.3:return false
	clips[mode]=name
	return true

func begin(player:MotionPlayer,mode:String,delta_local:Vector3) -> bool:
	if active or mode not in clips or not delta_local.is_finite() or player.avatar==null or not player.avatar.has_model():return false
	if player._preview or player._custom_motion:return false
	if mode=="enter" and player._contact_pose!="foot":return false
	if mode=="exit" and player._contact_pose!="sit":return false
	var avatar:=player.avatar
	clip_name=clips[mode]
	if not player.vrma_clips.has(clip_name):return false
	var clip:VrmaClip=player.vrma_clips[clip_name]
	kind=mode
	time=0
	duration=clip.duration
	root_delta=delta_local
	_model_id=avatar.model.get_instance_id()
	_floor_end=avatar.seated_floor.floor_y
	if not avatar.seated_geometry.is_empty() and is_finite(avatar.seated_floor.clearance):
		_floor_end=Vector3(avatar.seated_geometry.anchor).y-avatar.seated_floor.clearance
	_from.clear()
	for idx in avatar.bone_rest_local:_from[idx]=avatar.skeleton.get_bone_pose_rotation(idx)
	_from_hips=avatar.get_hips_offset()
	_from_velocity=player._pose_velocity.duplicate()
	_from_hips_velocity=player._hips_velocity
	active=true
	_update_state(clip)
	if not _build_bounds(player):
		reset()
		return false
	_update_state(clip)
	return true

func _update_state(clip:VrmaClip) -> void:
	var t:=clampf(time,0,duration)
	var first:=clip.sample_hips_offset(0)
	var last:=clip.sample_hips_offset(duration)
	var sampled:=clip.sample_hips_offset(t)
	var progress:=clampf(t/maxf(duration,0.001),0,1)
	var acquire:=_ease(t/ACQUIRE)
	var root_progress:=0.0
	var residual:=Vector3.ZERO
	if kind=="enter":
		# Source starts with a small preparatory bend; preserve it during
		# acquisition instead of assuming frame zero is a strict upright pose.
		root_progress=sampled.y/last.y if absf(last.y)>0.01 else progress
		root_progress*=acquire
		residual=sampled*acquire-last*root_progress
	else:
		root_progress=(sampled.y-first.y)/(-first.y) if absf(first.y)>0.01 else progress
		var release:=smoothstep(duration-ACQUIRE,duration,t)
		root_progress=lerpf(root_progress,1.0,release)
		residual=(sampled-first*(1-root_progress))*(1-release)
	root_progress=clampf(root_progress,-0.15,1.15)
	if time>=duration:
		root_progress=1
		residual=Vector3.ZERO
	diagnostics={"active":active,"finished":time>=duration,"kind":kind,"clip":clip_name,"time":t,"duration":duration,"progress":progress,"root_progress":root_progress,"local_root_residual":residual,"root_delta_local":root_delta,"transition_bounds":AABB(_bounds.position-root_delta*root_progress,_bounds.size)}

func apply(player:MotionPlayer,delta:float) -> void:
	if not active:return
	var avatar:=player.avatar
	if avatar.model.get_instance_id()!=_model_id or not player.vrma_clips.has(clip_name):reset();return
	time=minf(time+delta,duration)
	var clip:VrmaClip=player.vrma_clips[clip_name]
	_update_state(clip)
	avatar.apply_normalized_rotations(clip.sample(time),1.0)
	var u:=clampf(time/ACQUIRE,0,1)
	var weight:=_ease(u)
	var travel:=ACQUIRE*(u-u*u+u*u*u/3)
	for idx in _from:
		var carried:Quaternion=_from[idx]
		var velocity:Vector3=_from_velocity.get(idx,Vector3.ZERO)
		if velocity.length()>0.00001:
			carried=(carried*Quaternion(velocity.normalized(),velocity.length()*travel)).normalized()
		avatar.skeleton.set_bone_pose_rotation(idx,carried.slerp(avatar.skeleton.get_bone_pose_rotation(idx),weight))
	var height:=avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
	avatar.set_hips_offset((_from_hips+_from_hips_velocity*travel).lerp(Vector3(diagnostics.local_root_residual)*height,weight))
	if is_finite(_floor_end):
		var progress:float=diagnostics.root_progress
		avatar.seated_floor.floor_y=_floor_end+root_delta.y*(1-progress) if kind=="enter" else _floor_end-root_delta.y*progress
		avatar.seated_floor.set_active(true)
		avatar.seated_floor.solve_legs(1.0,true)

func finish(player:MotionPlayer) -> bool:
	if not active or time<duration:return false
	var completed:=kind
	if is_finite(_floor_end):player.avatar.seated_floor.floor_y=_floor_end
	reset()
	if completed=="enter":return player.start_contact_pose("sit")
	player.stop_contact_pose()
	return true


func _build_bounds(player:MotionPlayer) -> bool:
	var avatar:=player.avatar
	var key:=str(_model_id)+":"+clip_name+":"+str(root_delta)+":"+str(avatar.seated_floor.clearance)+":"+str(_from.hash())+":"+str(_from_hips)+":"+str(avatar._secondary_pose_cache.hash())+":"+str(_from_velocity.hash())+":"+str(_from_hips_velocity)
	if _bounds_cache.has(key):
		_bounds=_bounds_cache[key]
		return true
	var sk:=avatar.skeleton
	var saved:=[]
	for idx in sk.get_bone_count():saved.append([sk.get_bone_pose_position(idx),sk.get_bone_pose_rotation(idx),sk.get_bone_pose_scale(idx)])
	var ownership:=avatar._posed_bones.duplicate()
	var springs:=avatar.seated_floor.snapshot_springs()
	var floor_active:=avatar.seated_floor.active
	var floor_y:=avatar.seated_floor.floor_y
	var first:=true
	_bounds=AABB()
	# Acquisition includes a carried velocity arc, often much faster than the
	# authored seated clip. Bound it separately; thirteen whole-clip samples
	# can miss a hand extremum between the first two source samples.
	var sample_times:Array[float]=[]
	for sample_index in 13:sample_times.append(duration*sample_index/12.0)
	var peak_speed:=0.0
	for velocity in _from_velocity.values():peak_speed=maxf(peak_speed,velocity.length())
	# At least 30 Hz, with at most twelve degrees of outgoing rotation per
	# sample. Conservative influence boxes cover the acquisition envelope;
	# the dense exact-skin reference remains in diagnostic records.
	var acquisition_hz:=maxf(30.0,peak_speed/deg_to_rad(12.0))
	var acquisition_samples:=int(ceil(minf(ACQUIRE,duration)*acquisition_hz))
	for sample_index in acquisition_samples+1:
		sample_times.append(minf(ACQUIRE,duration)*sample_index/maxi(1,acquisition_samples))
	sample_times.sort()
	for sample_time in sample_times:
		time=sample_time
		avatar.apply_pose({})
		for idx in avatar._secondary_pose_cache:
			if idx>=0 and idx<sk.get_bone_count() and not avatar.bone_rest_local.has(idx):
				var cached:Array=avatar._secondary_pose_cache[idx]
				sk.set_bone_pose_position(idx,cached[0])
				sk.set_bone_pose_rotation(idx,cached[1])
				sk.set_bone_pose_scale(idx,cached[2])
		apply(player,0)
		if is_finite(floor_y):avatar.seated_floor.solve_secondary_pose()
		var measured:=TransitionBoundsMeasure.measure(avatar,true)
		if not measured.is_empty():
			var bound:AABB=measured.bounds
			bound.position+=root_delta*float(diagnostics.root_progress)
			_bounds=bound if first else _bounds.merge(bound)
			first=false
	for idx in sk.get_bone_count():
		sk.set_bone_pose_position(idx,saved[idx][0])
		sk.set_bone_pose_rotation(idx,saved[idx][1])
		sk.set_bone_pose_scale(idx,saved[idx][2])
	avatar._posed_bones=ownership
	avatar.seated_floor.set_active(floor_active)
	avatar.seated_floor.restore_springs(springs)
	avatar.seated_floor.floor_y=floor_y
	time=0
	if first or not _bounds.size.is_finite() or _bounds.size.length_squared()<=0.0:
		return false
	# A one-millimetre geometry envelope covers interpolation between samples;
	# it enlarges the advertised bounds, never relaxes host floor safety.
	_bounds=_bounds.grow(0.001)
	if _bounds_cache.size()>=4:_bounds_cache.clear()
	_bounds_cache[key]=_bounds
	return true

static func _ease(value:float) -> float:
	var x:=clampf(value,0,1)
	return x*x*x*(x*(x*6-15)+10)
