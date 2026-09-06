class_name MotionPlayer
extends Node
## Drives a VrmAvatar every frame: bank gestures (with intensity/speed/repeat),
## procedural idle (breath, sway, micro head motion), blink, mouse gaze,
## emotion expressions, lip sync from the audio envelope and a pet reaction.
## Everything blends additively and is exponentially smoothed so cancels
## return to idle without pops.

signal gesture_started(name: String, duration: float)
signal gesture_finished(name: String)

const SMOOTH_RATE := 16.0
const EMOTION_HOLD := 6.0
const EMOTION_MAP := {"happy": "happy", "sad": "sad", "relaxed": "relaxed", "surprised": "surprised", "angry": "angry", "neutral": "neutral", "fun": "relaxed", "joy": "happy", "sorrow": "sad"}

## Style is reusable across rigs: arm lengths normalize all hand targets.
var motion_style := {"openness": 1.0, "energy": 1.0, "response": 7.0}
var ik_enabled := true
var _hand_goals: Dictionary = {}
var _avatar_id := 0
var vrma_clips: Dictionary = {}
var vrma_contact_modes: Dictionary = {}
var _vrma_name := ""
var _vrma_start := 0.0
var _vrma_speed := 1.0
var _vrma_loop := false
var _vrma_repeat := 1
var _vrma_intensity := 1.0
var _transition_from: Dictionary = {}
var _transition_velocity: Dictionary = {}
var _previous_pose: Dictionary = {}
var _pose_velocity: Dictionary = {}
var _transition_start := 0.0
var _transition_hips_from := Vector3.INF
var _transition_hips_velocity := Vector3.ZERO
var _previous_hips_position := Vector3.INF
var _hips_velocity := Vector3.ZERO
var _frame_reference_pose: Dictionary = {}
var _frame_reference_hips := Vector3.INF
var _process_sample_delta := 0.0
var _posing_from_previous := false
var locomotion_clips: Dictionary = {"walk":false,"walk_formal":false}
var _locomotion_hip_centers: Dictionary = {}
var locomotion_styles: Dictionary = {}
var _source_seat_profiles: Dictionary = {}
var authored_seated_feet:=AuthoredFootContacts.new()
var seated_carrier:=SeatedCarrier.new()
var action_overlap := ActionOverlap.new()
var upper_body := UpperBodyOverlay.new()
var seated_transition := SeatedTransition.new()
var overlap_diagnostics: Dictionary = {}
var _overlap_outgoing: Dictionary = {}
var _overlap_incoming: Dictionary = {}
var _overlap_incoming_signaled := false
var _ambient_was_allowed := false
const TRANSITION_SECONDS := 0.45
var view_yaw_radians := 0.0:
	set(value):
		if is_finite(value):
			view_yaw_radians = wrapf(value,-PI,PI)
			gait.view_yaw_radians = view_yaw_radians
var _facing_target := 0.0
var _facing_velocity := 0.0
var _contact_pose := "foot"
var _seated_idle_start := 0.0
var _contact_hand := "right"
var _contact_target := Vector3.INF
var contact_reachable := false
var gait := DesktopGait.new()
var turn := TurnStepper.new()
var _heading_pending := false
var _travel_intent := false
var _travel_start_yaw := 0.0
const HEADING_SPEED := deg_to_rad(70.0)
const HEADING_ACCEL := deg_to_rad(100.0)
var _ambient_name := "rest"
var _ambient_strength := 0.0
var _ambient_target := 0.0
var _ambient_look := Vector2.INF
var _ambient_pose: Dictionary = {}
var _ambient_velocity: Dictionary = {}
var authored_ambient := AmbientMotion.new()
var _ambient_attention_override := false
var _ambient_suspended := false
var avatar: VrmAvatar
var bank: MotionBank = MotionBank.new()
var idle_enabled := true
var gaze_enabled := true
var gaze_target := Vector2(0.5, 0.45) # normalized window coords of the point of interest
var gaze_has_target := false
var mouth_open := 0.0 # 0..1 envelope from AudioOutput
var elapsed := 0.0

var _gesture: Dictionary = {}
var _gesture_name := "idle"
var _gesture_intensity := 1.0
var _gesture_speed := 1.0
var _gesture_repeat := 1
var _gesture_start := 0.0
var _gesture_active := false
var _preview := false
var _custom_motion := false
var _applied: Dictionary = {} # bone -> Vector3 smoothed degrees
var _emotion := "neutral"
var _emotion_weight := 0.0
var _emotion_target := 0.0
var _emotion_until := 0.0
var _blink_next := 2.0
var _blink_phase := -1.0
var _pet_until := 0.0
var _gaze_current := Vector2(0.5, 0.45)
var _gaze_velocity := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _blink_value := 0.0
var _mouth_smooth := 0.0


func _ready() -> void:
	process_priority = -10 # pose before spring bones/secondary update
	_noise.seed = randi()
	_noise.frequency = 0.35
	_blink_next = randf_range(1.5, 4.0)


func play_upper_body_gesture(name: String, intensity: float = 1.0, speed: float = 1.0, repeat: int = 1, channels: Array = ["head","arms","torso"]) -> bool:
	return upper_body.start(self,name,intensity,speed,repeat,channels)

func stop_upper_body_gesture() -> void:
	upper_body.stop(elapsed)

func is_upper_body_active() -> bool:
	return not upper_body.actions.is_empty()

func set_upper_body_contact_lock(locked: bool) -> void:
	if locked:
		# Retire smoothly, permanently for this request. Unlocking must not
		# resurrect a half-finished wave; the host contact solver owns final IK.
		for action in upper_body.actions:
			if not action.has("retire_at"):
				action.retire_at = elapsed
	upper_body.contact_locked = locked

func clear_seated_transition_registrations() -> void:
	if seated_transition.active: cancel_seated_transition()
	seated_transition.clips.clear()
	seated_transition._bounds_cache.clear()

func register_seated_transition(kind: String, clip_name: String) -> bool:
	var registered:=seated_transition.register_clip(kind,clip_name,vrma_clips)
	if registered:
		prepare_seated_geometry_inputs()
		if kind=="enter": _source_seat_profile(clip_name)
	return registered

func _source_seat_profile(name:String) -> Dictionary:
	if avatar==null or not avatar.has_model() or not vrma_clips.has(name):return {}
	var clip:VrmaClip=vrma_clips[name]
	var key:=str(avatar.model.get_instance_id())+":"+str(clip.get_instance_id())
	if _source_seat_profiles.has(key):return _source_seat_profiles[key]
	# Canonical source endpoint, without floor IK or host root adaptation.
	var measured:=SeatedGeometryCalibrator.measure(avatar,clip.sample(clip.duration),false,false)
	if measured.is_empty():return {}
	var height:=avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
	var hips:=clip.sample_hips_offset(clip.duration)*height
	var clearance:float=measured.anchor.y+hips.y-float(avatar.sole_calibration.floor_y)
	if not is_finite(clearance) or clearance<=0:return {}
	if _source_seat_profiles.size()>=3:_source_seat_profiles.clear()
	var profile:Dictionary={"source_seat_clearance_local":clearance,"source_full_endpoint_hips_local":hips}
	_source_seat_profiles[key]=profile
	return profile

func prepare_seated_geometry_inputs() -> bool:
	# Immutable mesh indexing belongs to model/asset preparation, not the
	# user's sit-down boundary. This never captures a future outgoing pose.
	if avatar==null or not avatar.has_model():return false
	authored_seated_feet.prepare(avatar)
	return not TransitionBoundsMeasure.measure(avatar,true).is_empty()

func seated_transition_requirements(kind: String) -> Dictionary:
	if not seated_transition.clips.has(kind) or avatar == null or not avatar.has_model(): return {}
	var name: String = seated_transition.clips[kind]
	if not vrma_clips.has(name): return {}
	var clip: VrmaClip = vrma_clips[name]
	var height := avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
	var requirements:Dictionary={"clip":name,"duration":clip.duration,"source_root_delta_local":(clip.sample_hips_offset(clip.duration)-clip.sample_hips_offset(0))*height}
	if kind=="enter":requirements.merge(_source_seat_profile(name))
	return requirements

func start_seated_transition(kind: String, root_delta_local: Vector3 = Vector3.ZERO) -> bool:
	if not seated_transition.begin(self,kind,root_delta_local): return false
	finish_locomotion()
	turn.cancel()
	_heading_pending = false
	_facing_velocity = 0.0
	upper_body.clear()
	stop_gesture()
	_contact_pose = "seat_"+kind
	return true

func seated_transition_state() -> Dictionary:
	return seated_transition.diagnostics.duplicate()

func finish_seated_transition() -> bool:
	return seated_transition.finish(self)

func cancel_seated_transition() -> void:
	seated_transition.reset()
	stop_contact_pose()

func set_bank(new_bank: MotionBank) -> void:
	bank = new_bank if new_bank else MotionBank.new()


## Play a gesture from the bank. Unknown names fall back to idle (contract: gesture IDs from the fetched bank).
func play_gesture(name: String, emotion: String = "", intensity: float = 1.0, speed: float = 1.0, repeat: int = 1, preview: bool = false) -> bool:
	if seated_transition.active or name in seated_transition.clips.values(): return false
	_clear_overlap()
	if not emotion.is_empty():
		set_emotion(emotion)
	if vrma_clips.has(name):
		var started := play_vrma(name, speed, false, repeat)
		_vrma_intensity = clampf(intensity, 0.0, 1.0)
		_preview = preview
		return started
	_begin_transition()
	upper_body.clear() # The common inertial snapshot now owns this outgoing layer.
	_vrma_name = ""
	var motion := bank.get_motion(name)
	if motion.is_empty() or name == "idle":
		stop_gesture()
		return false
	_custom_motion = false
	_gesture = motion
	_gesture_name = name
	_gesture_intensity = clampf(intensity, MotionBank.INTENSITY_RANGE.x, MotionBank.INTENSITY_RANGE.y)
	_gesture_speed = clampf(speed, MotionBank.SPEED_RANGE.x, MotionBank.SPEED_RANGE.y)
	_gesture_repeat = clampi(repeat, MotionBank.REPEAT_RANGE.x, MotionBank.REPEAT_RANGE.y)
	_gesture_start = elapsed
	_gesture_active = true
	_preview = preview
	gesture_started.emit(name, MotionBank.performed_duration(motion, _gesture_speed, _gesture_repeat))
	return true


## Preview an arbitrary bank-format motion dictionary (editor use).
func play_motion_dict(motion: Dictionary, intensity: float = 1.0, speed: float = 1.0, repeat: int = 1) -> void:
	if motion.is_empty():
		return
	_clear_overlap()
	_begin_transition()
	_vrma_name = ""
	_gesture = motion
	_custom_motion = true
	_gesture_name = str(motion.get("name", "preview"))
	_gesture_intensity = intensity
	_gesture_speed = speed
	_gesture_repeat = repeat
	_gesture_start = elapsed
	_gesture_active = true
	_preview = true
	gesture_started.emit(_gesture_name, MotionBank.performed_duration(motion, speed, repeat))


func stop_gesture() -> void:
	_begin_transition()
	_clear_overlap()
	var finished := _vrma_name if not _vrma_name.is_empty() else (_gesture_name if _gesture_active else "")
	_vrma_name = ""
	_gesture_active = false
	_gesture = {}
	_gesture_name = "idle"
	_preview = false
	_custom_motion = false
	# Observers may immediately start a new idle; publish after clearing state.
	if not finished.is_empty():
		gesture_finished.emit(finished)


func current_gesture() -> String:
	return seated_transition.clip_name if seated_transition.active else _vrma_name if not _vrma_name.is_empty() else (_gesture_name if _gesture_active else "idle")


func is_gesture_active() -> bool:
	return seated_transition.active or _gesture_active or not _vrma_name.is_empty()


func set_emotion(emotion: String, weight: float = 0.5, hold: float = EMOTION_HOLD) -> void:
	var mapped: String = EMOTION_MAP.get(emotion.to_lower(), "neutral")
	_emotion = mapped
	_emotion_target = 0.0 if mapped == "neutral" else weight
	_emotion_until = elapsed + hold


func current_emotion() -> String:
	return _emotion

## Overlap two finite live bank actions. Locomotion/root/support-changing
## channels remain boundary-gated; unsupported sources reject explicitly.
func queue_gesture(name: String, lead_seconds: float = 0.35, channels: Array = [], intensity: float = 1.0, speed: float = 1.0, repeat: int = 1) -> Dictionary:
	var incoming := bank.get_motion(name)
	if incoming.is_empty() or name == "idle" or _custom_motion or not _vrma_name.is_empty():
		return {"accepted":false,"reason":"unsupported_source"}
	if not _gesture_active or elapsed-_gesture_start >= MotionBank.performed_duration(_gesture,_gesture_speed,_gesture_repeat):
		return {"accepted":play_gesture(name,"",intensity,speed,repeat,_preview),"reason":"started"}
	var selected := _motion_channels(incoming) if channels.is_empty() else channels
	var descriptor := {"name":name,"motion":incoming,"intensity":clampf(intensity,MotionBank.INTENSITY_RANGE.x,MotionBank.INTENSITY_RANGE.y),"speed":clampf(speed,MotionBank.SPEED_RANGE.x,MotionBank.SPEED_RANGE.y),"repeat":clampi(repeat,MotionBank.REPEAT_RANGE.x,MotionBank.REPEAT_RANGE.y),"channels":selected}
	if not action_overlap.is_active():
		_overlap_outgoing = {"name":_gesture_name,"motion":_gesture,"intensity":_gesture_intensity,"speed":_gesture_speed,"repeat":_gesture_repeat,"channels":_motion_channels(_gesture)}
		action_overlap.start(_gesture_name,MotionBank.performed_duration(_gesture,_gesture_speed,_gesture_repeat),_overlap_outgoing.channels,_contact_pose,_gesture_start)
		action_overlap.advance(elapsed-_gesture_start)
	var result := action_overlap.queue(name,MotionBank.performed_duration(incoming,descriptor.speed,descriptor.repeat),lead_seconds,selected,_contact_pose)
	if bool(result.get("accepted",false)):
		_overlap_incoming = descriptor
		_overlap_incoming_signaled = false
	return result

## User-facing finite bank pair. Preview priority remains owned until both finish.
func play_gesture_sequence(first: String, second: String, lead_seconds: float = 0.5, preview: bool = true) -> Dictionary:
	if first == "idle" or second == "idle" or bank.get_motion(first).is_empty() or bank.get_motion(second).is_empty() or vrma_clips.has(first) or vrma_clips.has(second):
		return {"accepted":false,"reason":"unsupported_source"}
	play_gesture(first,"",1.0,1.0,1,preview)
	return queue_gesture(second,lead_seconds)

func _clear_overlap() -> void:
	action_overlap.reset()
	overlap_diagnostics.clear()
	_overlap_outgoing.clear()
	_overlap_incoming.clear()
	_overlap_incoming_signaled = false

func _motion_channels(motion: Dictionary) -> Array:
	var channels := []
	for track in motion.get("tracks",[]):
		var channel := _bone_channel(str(track.get("bone","")))
		if channel not in channels:
			channels.append(channel)
	return channels if not channels.is_empty() else ["torso"]

func _bone_channel(bone: String) -> String:
	if bone in ["head","neck"]:
		return "head"
	if "Leg" in bone or "Foot" in bone or "Toes" in bone:
		return "legs"
	if bone == "hips":
		return "root"
	if "Arm" in bone or "Hand" in bone or "Shoulder" in bone or bone.begins_with("left") or bone.begins_with("right"):
		return "arms"
	return "torso"

func _sample_overlap(delta: float) -> Dictionary:
	var state := action_overlap.advance(delta)
	if bool(state.promoted):
		_overlap_outgoing = _overlap_incoming
		_overlap_incoming = {}
		if not _overlap_outgoing.is_empty() and not state.outgoing.is_empty():
			_gesture = _overlap_outgoing.motion
			_gesture_name = _overlap_outgoing.name
			_gesture_intensity = _overlap_outgoing.intensity
			_gesture_speed = _overlap_outgoing.speed
			_gesture_repeat = _overlap_outgoing.repeat
			_gesture_start = state.outgoing.start_time
			if not _overlap_incoming_signaled:
				gesture_started.emit(_gesture_name,state.outgoing.duration)
	if not state.incoming.is_empty() and not _overlap_incoming_signaled:
		_overlap_incoming_signaled = true
		gesture_started.emit(str(state.incoming.name),float(state.incoming.duration))
	var pose := {}
	for pair in [[state.outgoing,_overlap_outgoing],[state.incoming,_overlap_incoming]]:
		var active: Dictionary = pair[0]
		var descriptor: Dictionary = pair[1]
		if active.is_empty() or descriptor.is_empty():
			continue
		var sampled := MotionBank.sample_performed(descriptor.motion,active.time,descriptor.intensity,descriptor.speed,descriptor.repeat)
		for bone in sampled:
			_add(pose,bone,sampled[bone]*float(active.weight_by_channel.get(_bone_channel(bone),0.0)))
	overlap_diagnostics = state.duplicate(true)
	for finished in state.finished:
		gesture_finished.emit(str(finished))
	if state.outgoing.is_empty():
		_begin_transition()
		_preview = false
		_gesture_active = false
		_gesture_name = "idle"
		_gesture = {}
	return pose


## Reset gesture, emotion and mouth (used on cancel/character switch).
func reset_all() -> void:
	seated_transition.reset()
	upper_body.clear()
	upper_body.contact_locked=false
	clear_seated_floor()
	stop_gesture()
	_emotion = "neutral"
	_emotion_target = 0.0
	mouth_open = 0.0
	_mouth_smooth = 0.0
	_contact_pose = "foot"
	_contact_target = Vector3.INF
	contact_reachable = false
	turn.cancel()
	gait = DesktopGait.new()
	gait.view_yaw_radians = view_yaw_radians
	_facing_target = view_yaw_radians
	_facing_velocity = 0.0
	_heading_pending = false
	_travel_intent = false
	_hand_goals.clear()
	_applied.clear()
	_transition_from.clear()
	_transition_velocity.clear()
	_transition_hips_from = Vector3.INF
	_previous_hips_position = Vector3.INF
	_hips_velocity = Vector3.ZERO
	_transition_hips_velocity = Vector3.ZERO
	_frame_reference_pose.clear()
	_frame_reference_hips = Vector3.INF
	_process_sample_delta = 0.0
	_posing_from_previous = false
	_previous_pose.clear()
	_pose_velocity.clear()
	_ambient_pose.clear()
	_ambient_velocity.clear()
	authored_ambient.reset()
	_ambient_attention_override = false
	_gaze_velocity = Vector2.ZERO
	_gaze_current = Vector2(0.5,0.45)
	_pet_until = 0.0


func pet_reaction() -> void:
	_pet_until = elapsed + 1.6
	set_emotion("happy", 0.6, 2.5)


func _process(delta: float) -> void:
	elapsed += delta
	if avatar == null or not avatar.has_model():
		return
	_check_model_identity()
	_process_sample_delta = delta
	_frame_reference_pose = _previous_pose.duplicate()
	_frame_reference_hips = _previous_hips_position
	_posing_from_previous = true
	_update_facing(delta)
	gait.advance_phase(delta)
	var ambient_allowed := idle_enabled and not _ambient_suspended and not is_gesture_active() and not _preview and not _custom_motion and not turn.active and not _heading_pending and not _travel_intent and _contact_pose == "foot" and _ambient_name not in ["anticipate","listening","thinking","working"]
	if _ambient_was_allowed and not ambient_allowed and authored_ambient.weight > 0.0 and not is_gesture_active():
		_begin_transition()
	_ambient_was_allowed = ambient_allowed
	authored_ambient.advance(delta,vrma_clips,ambient_allowed,avatar)
	var k := 1.0 - exp(-SMOOTH_RATE * delta)
	var target := {}

	# 1. Bank gesture layer
	if action_overlap.is_active():
		target = _sample_overlap(delta)
	elif _gesture_active:
		var sampled := MotionBank.sample_performed(_gesture, elapsed - _gesture_start, _gesture_intensity, _gesture_speed, _gesture_repeat)
		if sampled.is_empty() and elapsed - _gesture_start >= MotionBank.performed_duration(_gesture, _gesture_speed, _gesture_repeat):
			stop_gesture()
		else:
			for bone in sampled.keys():
				target[bone] = sampled[bone]

	# 2. Procedural idle layer (breath / sway / micro head motion)
	if idle_enabled:
		var breath := sin(elapsed * TAU / 4.2)
		_add(target, "chest", Vector3(1.2 * breath, 0.0, 0.0))
		_add(target, "spine", Vector3(0.6 * breath, 0.0, 0.3 * sin(elapsed * TAU / 9.0)))
		# Slow analytic drift has bounded derivatives; high-rate noise caused visible head jitter.
		_add(target, "head", Vector3(-0.8 * breath + 0.45 * sin(elapsed * 0.63), 0.9 * sin(elapsed * 0.41) + 0.3 * sin(elapsed * 0.17), 0.4 * sin(elapsed * 0.53)))
		_add(target, "leftUpperArm", Vector3(0.0, 0.0, 0.8 * breath))
		_add(target, "rightUpperArm", Vector3(0.0, 0.0, -0.8 * breath))

	# 3. Gaze toward the pointer (head only; eye bones differ between rigs)
	# Keep the underlying gaze trajectory alive. Authored head slerp owns the
	# final rotation at full weight; dropping this base at the first nonzero
	# ambient weight would create a head jump on resume/attention release.
	if gaze_enabled:
		var wanted := gaze_target if gaze_has_target else Vector2(0.5 + 0.12 * sin(elapsed * 0.23), 0.45 + 0.08 * sin(elapsed * 0.31 + 0.4))
		_advance_gaze(wanted,delta)
		var yaw := clampf((_gaze_current.x - 0.5) * 36.0, -14.0, 14.0) # + = look toward the character's right
		var pitch := clampf((_gaze_current.y - 0.45) * 24.0, -10.0, 12.0)
		_add(target, "head", Vector3(pitch * 0.7, yaw * 0.7, 0.0))
		_add(target, "neck", Vector3(pitch * 0.3, yaw * 0.3, 0.0))

	# 4. Pet reaction (small head tilt + lean)
	if elapsed < _pet_until:
		var u := clampf((_pet_until - elapsed) / 1.6, 0.0, 1.0)
		var wobble := sin(elapsed * TAU * 1.6) * 6.0 * u
		_add(target, "head", Vector3(3.0 * u, 0.0, wobble))
		_add(target, "chest", Vector3(0.0, 0.0, wobble * 0.25))

	if _contact_pose == "lean":
		_add(target,"chest",Vector3(0,0,6.0 if _contact_hand == "left" else -6.0))

	# Smooth + apply
	for bone in _applied.keys():
		if not target.has(bone):
			target[bone] = Vector3.ZERO
	for bone in target.keys():
		var cur: Vector3 = _applied.get(bone, Vector3.ZERO)
		var nxt: Vector3 = cur.lerp(target[bone], k)
		if nxt.length() < 0.01 and target[bone].is_zero_approx():
			_applied.erase(bone)
		else:
			_applied[bone] = nxt
	var use_ik := ik_enabled and not _custom_motion
	if use_ik:
		for side in ["left", "right"]:
			for joint in ["UpperArm", "LowerArm", "Hand"]:
				_applied.erase(side + joint)
	avatar.apply_pose(_applied)
	_posing_from_previous = false
	_apply_seated_base()
	if use_ik:
		_update_hand_goals(delta)
		avatar.apply_hand_goals(_hand_goals)
		var wrist := _wave_wrist(_gesture_name,_gesture,elapsed-_gesture_start,_gesture_speed,_gesture_intensity) if _gesture_active else 0.0
		if action_overlap.is_active():
			wrist = 0.0
			for pair in [[overlap_diagnostics.outgoing,_overlap_outgoing],[overlap_diagnostics.incoming,_overlap_incoming]]:
				var timeline: Dictionary = pair[0]
				var descriptor: Dictionary = pair[1]
				if not timeline.is_empty() and not descriptor.is_empty():
					wrist += _wave_wrist(descriptor.name,descriptor.motion,timeline.time,descriptor.speed,descriptor.intensity)*float(timeline.weight_by_channel.get("arms",0.0))
		avatar.add_wrist_rotation("right",Vector3(0,0,wrist))

	authored_ambient.apply(avatar,vrma_clips)
	var vrma_foot_contact := false
	var vrma_contact_weight := 0.0
	if not _vrma_name.is_empty():
		var clip: VrmaClip = vrma_clips[_vrma_name]
		var time := (elapsed - _vrma_start) * _vrma_speed
		var total := clip.duration * _vrma_repeat
		if not _vrma_loop and time >= total:
			var finished := _vrma_name
			_vrma_name = ""
			gesture_finished.emit(finished)
		else:
			var local_time := fmod(time, maxf(clip.duration,0.001))
			if seated_carrier.active and _vrma_name=="sit_idle":local_time=fmod(seated_carrier.phase_time,maxf(clip.duration,.001))
			if _vrma_loop and locomotion_clips.has(_vrma_name) and (gait.has_sample() or _travel_intent) and _contact_pose == "foot":
				local_time = gait.phase*clip.duration
			var blend := _blend_weight((elapsed-_vrma_start)/TRANSITION_SECONDS)
			if not _vrma_loop:
				blend *= _blend_weight((total-time)/(_vrma_speed*TRANSITION_SECONDS))
			var sampled_pose := clip.sample(local_time)
			if _contact_pose == "sit":
				# Contact owns the seated lower body even when dialogue plays a
				# full-body imported clip over it.
				for bone in sampled_pose.keys():
					if bone == "hips" or "Leg" in bone or "Foot" in bone or "Toes" in bone:
						sampled_pose.erase(bone)
			avatar.apply_normalized_rotations(sampled_pose, blend * _vrma_intensity)
			if _vrma_loop and bool(locomotion_clips.get(_vrma_name,false)) and _contact_pose == "foot":
				var height := avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
				var oscillation: Vector3 = clip.sample_hips_offset(local_time)-Vector3(_locomotion_hip_centers.get(_vrma_name,Vector3.ZERO))
				var hip_limit := height*0.035
				var source_style: Dictionary = locomotion_styles.get(_vrma_name,{})
				if bool(source_style.get("preserve_source_hip_height",false)):
					oscillation.y = clip.sample_hips_offset(local_time).y
				if source_style.has("hip_translation_limit_leg_lengths") and avatar.bone_index.has("leftUpperLeg") and avatar.bone_index.has("leftFoot"):
					var leg_length := avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
					hip_limit = leg_length*float(source_style.hip_translation_limit_leg_lengths)
				avatar.set_hips_offset((oscillation*height).limit_length(hip_limit)*blend*_vrma_intensity)
			if vrma_contact_modes.get(_vrma_name,"") == "foot" and _contact_pose == "foot":
				var height := avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
				avatar.set_hips_offset((clip.sample_hips_offset(local_time)*height*blend*_vrma_intensity).limit_length(height*0.12))
				vrma_foot_contact = true
				vrma_contact_weight = smoothstep(0.0,TRANSITION_SECONDS,elapsed-_vrma_start)
	_apply_ambient(delta)
	upper_body.apply(self,delta)
	var contact_solvable := false
	if _contact_pose == "lean":
		contact_solvable = avatar.apply_hand_contact(_contact_hand,_contact_target)
	_apply_transition()
	authored_ambient.solve_contacts(avatar,vrma_foot_contact,vrma_contact_weight)
	gait.apply(avatar,delta,(_travel_intent or (_vrma_loop and locomotion_clips.has(_vrma_name))) and _contact_pose == "foot" and not _custom_motion and not _preview and not turn.active)
	var turn_was_active := turn.active
	var turn_blocked := _preview or _custom_motion or _contact_pose != "foot"
	turn.apply(avatar,delta,_facing_target,turn_blocked)
	seated_carrier.restore_body(self)
	if is_finite(avatar.seated_floor.clearance) and not seated_transition.active:
		avatar.seated_floor.set_active(_contact_pose == "sit")
		if _contact_pose == "sit":
			if authored_seated_feet.active and vrma_clips.has("sit_idle"):
				var seated_clip:VrmaClip=vrma_clips.sit_idle
				var seated_time:=fmod(seated_carrier.phase_time if seated_carrier.active else elapsed-_seated_idle_start,maxf(seated_clip.duration,.001))
				authored_seated_feet.apply_contact(seated_clip.sample(seated_time),seated_clip.sample_hips_offset(seated_time),0,avatar.seated_floor.floor_y)
			else:avatar.seated_floor.solve_legs(smoothstep(0.0,TRANSITION_SECONDS,elapsed-_transition_start))
	var completed_turn := turn_was_active and not turn.active and not turn_blocked
	# A geometrically solvable target is not yet attached while blending in.
	# Report the rendered wrist's final world-space error (1.5 cm threshold).
	contact_reachable = contact_solvable and avatar.bone_global_position(_contact_hand+"Hand").distance_to(_contact_target) < 0.015

	seated_transition.apply(self,delta)
	seated_carrier.apply(self)

	# Expressions: blink, emotion, mouth
	_update_blink(delta)
	if elapsed > _emotion_until:
		_emotion_target = 0.0
	_emotion_weight = lerpf(_emotion_weight, _emotion_target, 1.0 - exp(-5.0 * delta))
	_mouth_smooth = lerpf(_mouth_smooth, mouth_open, 1.0 - exp(-(30.0 if mouth_open > _mouth_smooth else 14.0) * delta))
	for name in ["happy", "sad", "relaxed", "surprised", "angry"]:
		avatar.set_expression(name, _emotion_weight if name == _emotion else 0.0)
	avatar.set_expression("blink", _blink_value)
	avatar.set_expression("aa", clampf(_mouth_smooth * 0.55, 0.0, 0.55))
	avatar.set_expression("oh", minf(0.6 - clampf(_mouth_smooth * 0.55, 0.0, 0.55), clampf(_mouth_smooth * 0.10 * (0.5 + 0.5 * sin(elapsed * 9.0)), 0.0, 0.10)))
	avatar.apply_expressions()
	_record_pose_velocity(delta)
	if completed_turn:
		# Preserve the final solved turn pose through the host's one-frame
		# readiness→walk handoff. Otherwise the next base-pose reset can expose
		# the remaining foot yaw/knee motion before walk playback is requested.
		_begin_transition()


func _update_blink(delta: float) -> void:
	if _blink_phase < 0.0:
		_blink_next -= delta
		if _blink_next <= 0.0:
			_blink_phase = 0.0
		_blink_value = lerpf(_blink_value, 0.0, 0.5)
		return
	_blink_phase += delta
	var d := 0.16
	if _blink_phase >= d:
		_blink_phase = -1.0
		_blink_value = 0.0
		_blink_next = randf_range(1.8, 5.5) if randf() > 0.15 else 0.25 # occasional double blink
		return
	var u := _blink_phase / d
	_blink_value = 1.0 - absf(u * 2.0 - 1.0)
	_blink_value = _blink_value * _blink_value * (3.0 - 2.0 * _blink_value)


static func _add(target: Dictionary, bone: String, v: Vector3) -> void:
	target[bone] = target.get(bone, Vector3.ZERO) + v


func _wave_wrist(name: String, motion: Dictionary, age: float, speed: float, intensity: float) -> float:
	if name != "wave":
		return 0.0
	var duration := maxf(float(motion.get("duration",4.0)),0.1)
	var phase := fmod(age*speed,duration)
	var envelope := smoothstep(0.0,0.8,phase)*smoothstep(0.0,0.8,duration-phase)
	return 12.0*sin(phase*TAU*1.5)*envelope*minf(intensity,1.25)

func _action_hand_goal(side: String, name: String, motion: Dictionary, age_seconds: float, intensity: float, speed: float, active: bool = true) -> Vector3:
	var duration := float(motion.get("duration",1.0))
	var phase := fmod(age_seconds*speed,maxf(duration,0.1))
	var fade := minf(clampf(phase/0.8,0,1),clampf((duration-phase)/0.8,0,1)) if active else 0.0
	fade = fade*fade*fade*(fade*(fade*6.0-15.0)+10.0)*minf(intensity,1.25)
	var sign_side := 1.0 if side == "left" else -1.0
	var rest := Vector3(sign_side*0.20*float(motion_style.get("openness",1.0)),-0.94,0.08)
	var goal := rest
	var energy := float(motion_style.get("energy",1.0))
	match name:
		"wave":
			if side == "right":
				goal = Vector3(-0.57+sin(phase*TAU*1.5)*0.075*energy,0.32,0.32)
		"stretch":
			goal = Vector3(sign_side*0.42,0.85,0.06)
		"think":
			if side == "right":
				goal = Vector3(0.08,0.04,0.42)
		"shy":
			goal = Vector3(-sign_side*0.12,-0.38,0.46)
		"bow":
			goal = Vector3(sign_side*0.14,-0.90,0.25)
	return rest.lerp(goal,fade)

func _update_hand_goals(delta: float) -> void:
	for side in ["left","right"]:
		var rest := _action_hand_goal(side,"",{},0,0,1,false)
		var goal := _action_hand_goal(side,_gesture_name,_gesture,elapsed-_gesture_start,_gesture_intensity,_gesture_speed,_gesture_active)
		if not overlap_diagnostics.is_empty() and action_overlap.is_active():
			goal = rest
			for pair in [[overlap_diagnostics.outgoing,_overlap_outgoing],[overlap_diagnostics.incoming,_overlap_incoming]]:
				var timeline: Dictionary = pair[0]
				var descriptor: Dictionary = pair[1]
				if timeline.is_empty() or descriptor.is_empty():
					continue
				var weight := float(timeline.weight_by_channel.get("arms",0.0))
				goal += (_action_hand_goal(side,descriptor.name,descriptor.motion,timeline.time,descriptor.intensity,descriptor.speed)-rest)*weight
		if idle_enabled:
			goal.z += 0.008*sin(elapsed*TAU/4.2)
		var current: Vector3 = _hand_goals.get(side,rest)
		var smooth := current.lerp(goal,1-exp(-float(motion_style.get("response",7.0))*delta))
		_hand_goals[side] = current.move_toward(smooth,2.0*delta)


## Register a reusable authored locomotion source. Centered hip oscillation
## preserves its weight shift without importing world travel/root placement.
func clear_locomotion_registrations() -> void:
	locomotion_clips = {"walk":false,"walk_formal":false}
	_locomotion_hip_centers.clear()
	locomotion_styles.clear()
	if gait.has_method("configure_authored_locomotion"): gait.call("configure_authored_locomotion",{})

func register_locomotion_style(name: String, metadata: Dictionary) -> bool:
	if not locomotion_clips.has(name): return false
	# Validate on a temporary solver; registration must not disturb live feet.
	var validator := DesktopGait.new()
	if not validator.has_method("configure_authored_locomotion") or not validator.call("configure_authored_locomotion",metadata): return false
	locomotion_styles[name] = metadata.duplicate(true)
	return true

func register_locomotion_clip(name: String, preserve_hips: bool = true) -> bool:
	if not vrma_clips.has(name):
		return false
	locomotion_clips[name] = preserve_hips
	var clip: VrmaClip = vrma_clips[name]
	var center := Vector3.ZERO
	for sample in 120:
		center += clip.sample_hips_offset(clip.duration*sample/120.0)/120.0
	_locomotion_hip_centers[name] = center
	return true

func load_vrma(name: String, path: String, contact_mode: String = "") -> bool:
	var clip := VrmaClip.new()
	if not clip.load_file(path):
		push_warning("VRMA: " + clip.error)
		return false
	vrma_clips[name] = clip
	seated_transition._bounds_cache.clear()
	if name == "sit_idle" and avatar != null:
		avatar.seated_geometry.clear()
		avatar._seated_canonical_rotations.clear()
	vrma_contact_modes[name] = contact_mode if contact_mode in ["foot",""] else ""
	return true

## loop=true plays until stop/supersession; otherwise repeat is a finite cycle count.
func play_vrma(name: String, speed: float = 1.0, loop: bool = false, repeat: int = 1) -> bool:
	if seated_transition.active or name in seated_transition.clips.values(): return false
	if not loop and not Dictionary(locomotion_styles.get(name,{})).is_empty(): return false
	if not vrma_clips.has(name):
		return false
	_clear_overlap()
	if vrma_contact_modes.get(name,"") == "foot":
		authored_ambient.capture_contact_origin(avatar)
	stop_gesture()
	if not (loop and locomotion_clips.has(name)):
		upper_body.clear() # Avoid a second arm fade over the common velocity-carry handoff.
	_vrma_name = name
	if gait.has_method("configure_authored_locomotion"):
		gait.call("configure_authored_locomotion",locomotion_styles.get(name,{}))
	_vrma_start = elapsed
	_vrma_speed = clampf(speed,0.5,2.0)
	_vrma_loop = loop
	_vrma_repeat = clampi(repeat,1,3)
	_vrma_intensity = 1.0
	gesture_started.emit(name, -1.0 if loop else vrma_clips[name].duration * _vrma_repeat / _vrma_speed)
	return true


func _begin_transition() -> void:
	_transition_velocity = _pose_velocity.duplicate()
	_transition_from.clear()
	# An internal transition begins from the previous rendered pose, before
	# this frame's pose pass. Advance it by this frame's dt instead of holding
	# u=0 for one visible frame and overwriting its outgoing velocity with zero.
	_transition_start = elapsed-_process_sample_delta if _posing_from_previous else elapsed
	if avatar == null or not avatar.has_model():
		return
	if avatar.bone_index.has("hips"):
		_transition_hips_from = avatar.skeleton.get_bone_pose_position(avatar.bone_index.hips)
		_transition_hips_velocity = _hips_velocity
	for idx in avatar.bone_index.values():
		_transition_from[idx] = avatar.skeleton.get_bone_pose_rotation(idx)

func _apply_transition() -> void:
	if _transition_from.is_empty():
		return
	var u := clampf((elapsed-_transition_start)/TRANSITION_SECONDS,0.0,1.0)
	if u >= 1.0:
		_transition_from.clear()
		return
	var weight := u*u*u*(u*(u*6.0-15.0)+10.0)
	if _transition_hips_from.is_finite() and avatar.bone_index.has("hips"):
		var hips: int = avatar.bone_index.hips
		var travel := TRANSITION_SECONDS*(u-u*u+u*u*u/3.0)
		var carried_hips := _transition_hips_from+_transition_hips_velocity*travel
		avatar.skeleton.set_bone_pose_position(hips,carried_hips.lerp(avatar.skeleton.get_bone_pose_position(hips),weight))
	for idx in _transition_from:
		if idx >= avatar.skeleton.get_bone_count():
			continue
		var wanted := avatar.skeleton.get_bone_pose_rotation(idx)
		var carried: Quaternion = _transition_from[idx]
		var velocity: Vector3 = _transition_velocity.get(idx,Vector3.ZERO)
		if velocity.length() > 0.00001:
			# Integrate a decaying outgoing angular velocity. Quintic blending
			# then preserves the pose derivative at interruption instead of
			# instantly freezing a moving head at a static snapshot.
			var travel := TRANSITION_SECONDS*(u-u*u+u*u*u/3.0)
			carried = (carried*Quaternion(velocity.normalized(),velocity.length()*travel)).normalized()
		avatar.skeleton.set_bone_pose_rotation(idx, carried.slerp(wanted,weight))


## Screen-space velocity (+X right). No model translation: the desktop host
## owns window position; this only turns the character into its travel direction.
func set_locomotion_direction(velocity: Vector2) -> void:
	if absf(velocity.x) > 1.0:
		set_heading_intent(velocity)

func prepare_locomotion(direction_px: Vector2) -> bool:
	if avatar == null or not avatar.has_model() or _contact_pose != "foot" or _preview or _custom_motion or absf(direction_px.x) < 0.001:
		return false
	if not _travel_intent:
		_begin_transition()
		_travel_start_yaw = avatar.rotation.y
	_travel_intent = true
	turn.cancel()
	set_heading_intent(direction_px)
	gait.begin_steering(avatar,_facing_target)
	return true

## World-scene travel retains the same concurrent steering/foot owner.
func prepare_scene_locomotion(yaw_radians: float) -> bool:
	if not is_finite(yaw_radians) or avatar == null or not avatar.has_model() or _contact_pose != "foot" or _preview or _custom_motion:
		return false
	if not _travel_intent:
		_begin_transition()
		_travel_start_yaw = avatar.rotation.y
	_travel_intent = true
	turn.cancel()
	update_scene_heading(yaw_radians)
	gait.begin_steering(avatar,_facing_target)
	return true

func update_scene_heading(yaw_radians: float) -> bool:
	if not is_finite(yaw_radians) or not _travel_intent or _contact_pose != "foot": return false
	_facing_target = wrapf(yaw_radians,-PI,PI)
	_heading_pending = true
	gait.steering_heading = _facing_target
	return true

func set_scene_locomotion_sample(velocity_world: Vector3, displacement_world: Vector3, heading_world: float, supported: bool = true, distance_world_m: float = -1.0) -> void:
	if avatar == null or not avatar.has_model(): return
	var owns_legs := (_travel_intent or (_vrma_loop and locomotion_clips.has(_vrma_name))) and _contact_pose == "foot" and not _custom_motion and not _preview and not turn.active
	if owns_legs: update_scene_heading(heading_world)
	gait.sample_scene(avatar,velocity_world,displacement_world,supported and owns_legs,distance_world_m)
	gait.compensate_movement(avatar)
	_record_pose_velocity(_process_sample_delta)
	if is_equal_approx(_transition_start,elapsed) and not _transition_from.is_empty():
		_transition_velocity = _pose_velocity.duplicate()
		_transition_hips_velocity = _hips_velocity
		_transition_hips_from = avatar.skeleton.get_bone_pose_position(avatar.bone_index.hips)
		for idx in avatar.bone_index.values():
			_transition_from[idx] = avatar.skeleton.get_bone_pose_rotation(idx)

func locomotion_ready() -> bool:
	if not _travel_intent or avatar == null or not avatar.has_model() or _preview or _custom_motion or _contact_pose != "foot":
		return false
	var error := absf(angle_difference(avatar.rotation.y,_facing_target))
	var lead := absf(angle_difference(_travel_start_yaw,avatar.rotation.y))
	return gait.steering and error <= deg_to_rad(72) and (lead >= deg_to_rad(10) or error <= deg_to_rad(20))

func finish_locomotion() -> void:
	_travel_intent = false
	gait.end_steering()

func set_heading_intent(direction_px: Vector2) -> void:
	if absf(direction_px.x) <= 0.001:
		return
	var wanted := wrapf(view_yaw_radians+deg_to_rad(82.0)*signf(direction_px.x),-PI,PI)
	if absf(angle_difference(_facing_target,wanted)) > 0.001:
		_facing_target = wanted
		_heading_pending = true
		if _travel_intent:
			gait.steering_heading = wanted

## Orient a standing character for a seat/workspace before attachment.
## The host waits for heading_ready(); seated feet never swivel in place.
func set_contact_heading(yaw_radians: float) -> bool:
	if not is_finite(yaw_radians) or avatar == null or not avatar.has_model() or _contact_pose != "foot" or _preview or _custom_motion:
		return false
	finish_locomotion()
	_facing_target = wrapf(yaw_radians,-PI,PI)
	_heading_pending = true
	return true

func face_front() -> void:
	finish_locomotion()
	_facing_target = view_yaw_radians
	_heading_pending = true

func heading_ready() -> bool:
	return avatar != null and absf(angle_difference(avatar.rotation.y,_facing_target)) < deg_to_rad(1.0) and absf(_facing_velocity) < deg_to_rad(2.0) and not turn.active

func cancel_heading() -> void:
	finish_locomotion()
	if avatar == null:
		return
	# Preserve current velocity while braking; stopping the OS window does not
	# require an instantaneous stop in the character's angular motion.
	_facing_target = avatar.rotation.y+signf(_facing_velocity)*_facing_velocity*_facing_velocity/(2*HEADING_ACCEL)
	_heading_pending = absf(_facing_velocity) > deg_to_rad(1)

func _update_facing(delta: float) -> void:
	if seated_carrier.active:return
	var blocked := _preview or _custom_motion
	if blocked:
		turn.cancel()
		cancel_heading()
	var difference := angle_difference(avatar.rotation.y,_facing_target)
	if _heading_pending and not _travel_intent and not blocked and _contact_pose == "foot" and absf(difference) > deg_to_rad(2) and not turn.active:
		turn.begin(avatar,_facing_target)
		_heading_pending = false
	var steps := maxi(1,int(ceil(delta*120)))
	var dt := delta/steps
	for i in steps:
		difference = angle_difference(avatar.rotation.y,_facing_target)
		var braking := maxf(0,sqrt(2*HEADING_ACCEL*absf(difference))-HEADING_ACCEL*dt)
		var wanted := signf(difference)*minf(HEADING_SPEED,braking)
		_facing_velocity = move_toward(_facing_velocity,wanted,HEADING_ACCEL*dt)
		var step := _facing_velocity*dt
		if absf(step) > absf(difference) and signf(step) == signf(difference):
			step = difference
			_facing_velocity = 0.0
		avatar.rotation.y += step

## A sit needs the imported sit_idle clip. Lean requires an explicit nearby
## surface point; the host must inspect contact_reachable before attaching it.
## Host supplies a continuous eased lift and the physical chair's current yaw.
## No standing turn solver runs while the seat owns the body's orientation.
func set_seated_carrier(lift_weight:float,yaw_world:float)->bool:
	if avatar==null or not avatar.has_model() or _contact_pose!="sit" or seated_transition.active or _preview or _custom_motion:return false
	if not is_finite(lift_weight) or not is_finite(yaw_world) or lift_weight<0 or lift_weight>1:return false
	if not is_finite(avatar.seated_floor.clearance) or not authored_seated_feet.active:return false
	if absf(angle_difference(avatar.rotation.y,yaw_world))>deg_to_rad(12):return false
	if not is_equal_approx(seated_carrier.lift,lift_weight):
		seated_carrier.diagnostics["ready"]=false
	if not seated_carrier.active:
		if _vrma_name!="sit_idle" or not vrma_clips.has("sit_idle"):return false
		seated_carrier.capture(self)
	seated_carrier.active=true
	seated_carrier.lift=lift_weight
	turn.cancel();_heading_pending=false;_facing_velocity=0
	avatar.rotation.y=wrapf(yaw_world,-PI,PI)
	_facing_target=avatar.rotation.y
	return true

func seated_carrier_state()->Dictionary:
	return seated_carrier.diagnostics.duplicate()

func seated_carrier_lift_envelope()->Dictionary:
	if not seated_carrier.active or not seated_carrier.valid(self):return {}
	var envelope:Dictionary=preload("res://scripts/carrier_lift_envelope.gd").build(seated_carrier.lift_reference)
	if not envelope.is_empty():envelope["transform"]=avatar.global_transform
	return envelope

func seated_carrier_body_snapshot()->Dictionary:
	if not seated_carrier.active or not seated_carrier.valid(self) or not seated_carrier.diagnostics.get("ready",false):return {}
	var snapshot:=avatar.body_capsule_snapshot()
	if snapshot.is_empty():return {}
	snapshot["articulation_frozen"]=true
	snapshot["source_phase"]=seated_carrier.phase_time
	snapshot["source_clip_id"]=seated_carrier.clip_id
	return snapshot

func clear_seated_carrier()->void:
	if seated_carrier.active:_begin_transition()
	seated_carrier.clear(self)
	if avatar!=null and avatar.has_model():_facing_target=avatar.rotation.y

func set_seated_floor(clearance_m: float) -> bool:
	return avatar != null and avatar.set_seated_floor(clearance_m)

func clear_seated_floor() -> void:
	seated_carrier.clear(self)
	authored_seated_feet.clear_reference()
	if avatar != null: avatar.clear_seated_floor()

func start_contact_pose(pose: String, world_hand_target: Vector3 = Vector3.INF) -> bool:
	if seated_carrier.active:return false
	contact_reachable = false
	if pose == "sit":
		if not play_vrma("sit_idle",1.0,true):
			return false
		_contact_pose = "sit"
		_seated_idle_start = elapsed
		if is_finite(avatar.seated_floor.clearance):
			authored_seated_feet.prepare(avatar)
			var clip:VrmaClip=vrma_clips.sit_idle
			authored_seated_feet.begin_reference(clip.sample(0),clip.sample_hips_offset(0))
		set_locomotion_direction(Vector2.ZERO)
		return true
	if pose == "lean" and world_hand_target.is_finite() and avatar != null and avatar.has_model():
		stop_gesture()
		_contact_pose = "lean"
		_contact_target = world_hand_target
		_contact_hand = "left" if avatar.to_local(world_hand_target).x >= 0 else "right"
		set_locomotion_direction(Vector2.ZERO)
		return true
	return false

func stop_contact_pose() -> void:
	seated_transition.reset()
	clear_seated_floor()
	_contact_pose = "foot"
	_contact_target = Vector3.INF
	contact_reachable = false
	stop_gesture()

func current_contact_pose() -> String:
	return _contact_pose


func _apply_seated_base() -> void:
	if _contact_pose != "sit" or not vrma_clips.has("sit_idle"):
		return
	var clip: VrmaClip = vrma_clips["sit_idle"]
	var pose := clip.sample(fmod(seated_carrier.phase_time if seated_carrier.active else elapsed-_seated_idle_start,maxf(clip.duration,0.001)))
	for bone in pose.keys():
		if bone != "hips" and not ("Leg" in bone or "Foot" in bone or "Toes" in bone):
			pose.erase(bone)
	avatar.apply_normalized_rotations(pose,1.0)


## Host calls once after actual window movement, even when displacement is zero.
## Effective pixels/metre = orthographic camera ppm * user avatar scale.
func set_locomotion_sample(velocity_px: Vector2, traveled_px: Vector2, pixels_per_metre: float, supported: bool = true, actual_world_delta: Variant = null) -> void:
	var owns_legs := (_travel_intent or (_vrma_loop and locomotion_clips.has(_vrma_name))) and _contact_pose == "foot" and not _custom_motion and not _preview and not turn.active
	if owns_legs:
		set_locomotion_direction(velocity_px)
	if actual_world_delta == null:
		gait.sample(velocity_px,traveled_px,pixels_per_metre,supported and owns_legs)
	else:
		gait.call("sample",velocity_px,traveled_px,pixels_per_metre,supported and owns_legs,actual_world_delta)
	if avatar != null and avatar.has_model():
		gait.compensate_movement(avatar)
		# Re-evaluate against the same previous FINAL-frame reference. A second
		# naive sample would compare to this frame's pre-compensation pose and
		# mistake only the compensation delta for the visible angular velocity.
		_record_pose_velocity(_process_sample_delta)
		if is_equal_approx(_transition_start,elapsed) and not _transition_from.is_empty():
			_transition_velocity = _pose_velocity.duplicate()
			_transition_hips_velocity = _hips_velocity
			_transition_hips_from = avatar.skeleton.get_bone_pose_position(avatar.bone_index.hips)
			for idx in avatar.bone_index.values():
				_transition_from[idx] = avatar.skeleton.get_bone_pose_rotation(idx)

## Bounded low-rate behavior intent; speech/gestures retain expression ownership.
## Optional look point is normalized viewport coordinates. Explicit user gaze
## remains higher priority. Strength clamps to 0..1, unknown states become rest.
func set_ambient_state(name: String, strength: float = 1.0, look: Vector2 = Vector2.INF) -> void:
	_ambient_name = name if name in ["rest","curious","anticipate","settle","sleepy","attentive","thinking","working","listening"] else "rest"
	_ambient_target = clampf(strength,0.0,1.0)
	_ambient_look = look.clamp(Vector2.ZERO,Vector2.ONE) if look.is_finite() else Vector2.INF

func set_ambient_loop(name: String) -> bool:
	if not name.is_empty() and not vrma_clips.has(name):
		return false
	if authored_ambient.loop_name != name:
		_begin_transition()
		authored_ambient.reset()
		authored_ambient.loop_name = name
		authored_ambient.attention_override = _ambient_attention_override
		authored_ambient.head_weight = 0.0 if _ambient_attention_override else 1.0
	return true

func play_ambient_action(name: String) -> bool:
	if not idle_enabled or not vrma_clips.has(authored_ambient.loop_name) or not vrma_clips.has(name) or _ambient_suspended or is_gesture_active() or _preview or _custom_motion or turn.active or _heading_pending or _contact_pose != "foot" or _ambient_attention_override or _ambient_name in ["anticipate","listening","thinking","working"]:
		return false
	authored_ambient.action_name = name
	authored_ambient.action_time = 0.0
	return true

func set_ambient_attention_override(enabled: bool) -> void:
	_ambient_attention_override = enabled
	authored_ambient.attention_override = enabled

func set_ambient_suspended(suspended: bool) -> void:
	_ambient_suspended = suspended

func _apply_ambient(delta: float) -> void:
	if authored_ambient.owns_head():
		return
	if _custom_motion or _preview:
		_ambient_pose.clear()
		_ambient_velocity.clear()
		return
	_ambient_strength = lerpf(_ambient_strength,_ambient_target,1-exp(-1.8*delta))
	var desired := {"chest":Vector3.ZERO,"head":Vector3.ZERO,"neck":Vector3.ZERO}
	var strength := _ambient_strength
	# Authored gestures remain dominant; ambient never alters an editor preview.
	if _custom_motion or _preview:
		strength = 0.0
	elif is_gesture_active():
		strength *= 0.25
	match _ambient_name:
		"attentive", "listening":
			desired.chest = Vector3(0.7,0,0)*strength
			desired.head = Vector3(-0.5,0,0.8)*strength
		"thinking":
			desired.head = Vector3(1.0,-1.5,1.2)*strength
			desired.chest = Vector3(0.4,0,0)*strength
		"working":
			desired.head = Vector3(1.8,0,0.3*sin(elapsed*0.21))*strength
			desired.chest = Vector3(1.0,0,0)*strength
		"curious":
			desired.head = Vector3(-1.0,0,2.0)*strength
			desired.chest = Vector3(0.8,0,0)*strength
		"anticipate":
			desired.chest = Vector3(1.8,0,0.5*sin(elapsed*0.5))*strength
			desired.head = Vector3(-0.7,0,0)*strength
		"settle":
			desired.chest = Vector3(-0.8,0,0)*strength
		"sleepy":
			desired.head = Vector3(2.0,0,1.0)*strength
			# No forced blink/speech changes: expression driver owns the face.
		"rest":
			desired.chest = Vector3(0,0,0.6*sin(elapsed*0.23))*strength
	if _ambient_look.is_finite() and not gaze_has_target:
		var yaw := clampf((_ambient_look.x-0.5)*16,-6,6)*strength
		var pitch := clampf((_ambient_look.y-0.5)*10,-4,4)*strength
		desired.head += Vector3(pitch*0.65,yaw*0.65,0)
		desired.neck = Vector3(pitch*0.35,yaw*0.35,0)
	for bone in desired:
		var position: Vector3 = _ambient_pose.get(bone,Vector3.ZERO)
		var velocity: Vector3 = _ambient_velocity.get(bone,Vector3.ZERO)
		var steps := maxi(1,int(ceil(delta*120)))
		var dt := delta/steps
		for i in steps:
			var remaining: Vector3 = desired[bone]-position
			var limit := minf(3.0,maxf(0,sqrt(24.0*remaining.length())-12.0*dt))
			velocity = velocity.move_toward(remaining.normalized()*limit,12.0*dt)
			var step := velocity*dt
			if step.dot(remaining) > remaining.length_squared():
				step = remaining
				velocity = Vector3.ZERO
			position += step
		_ambient_pose[bone] = position
		_ambient_velocity[bone] = velocity
	avatar.add_pose_offsets(_ambient_pose)


## Acceleration-limited pursuit with a stopping-distance speed limit. A fixed
## integration ceiling makes 30/60 FPS target steps follow the same trajectory.
func _advance_gaze(wanted: Vector2, delta: float) -> void:
	# Pursue the reachable angular endpoint. Clamping only the output yaw
	# would abruptly cut velocity while the normalized pursuit kept moving.
	wanted = wanted.clamp(Vector2(0.5-14.0/36.0,0.45-10.0/24.0),Vector2(0.5+14.0/36.0,0.45+12.0/24.0))
	const MAX_SPEED := 0.6
	const MAX_ACCEL := 1.8
	var steps := maxi(1,int(ceil(delta*120.0)))
	var dt := delta/steps
	for i in steps:
		var remaining := wanted-_gaze_current
		var distance := remaining.length()
		if distance < 0.00001 and _gaze_velocity.length() < MAX_ACCEL*dt:
			_gaze_current = wanted
			_gaze_velocity = Vector2.ZERO
			continue
		var stopping_speed := maxf(0.0,sqrt(2.0*MAX_ACCEL*distance)-MAX_ACCEL*dt)
		var wanted_velocity := remaining.normalized()*minf(MAX_SPEED,stopping_speed)
		_gaze_velocity = _gaze_velocity.move_toward(wanted_velocity,MAX_ACCEL*dt)
		var step := _gaze_velocity*dt
		if step.dot(remaining) > remaining.length_squared():
			step = remaining
			_gaze_velocity = Vector2.ZERO
		_gaze_current += step


func _record_pose_velocity(delta: float) -> void:
	if avatar.bone_index.has("hips") and delta > 0.000001:
		var hips_position := avatar.skeleton.get_bone_pose_position(avatar.bone_index.hips)
		if _frame_reference_hips.is_finite():
			_hips_velocity = ((hips_position-_frame_reference_hips)/delta).limit_length(0.5)
		_previous_hips_position = hips_position
	if delta <= 0.00001:
		return
	for idx in avatar.bone_rest_local:
		var current := avatar.skeleton.get_bone_pose_rotation(idx)
		if _frame_reference_pose.has(idx):
			var change: Quaternion = (_frame_reference_pose[idx].inverse()*current).normalized()
			if change.w < 0:
				change = Quaternion(-change.x,-change.y,-change.z,-change.w)
			var vector := Vector3(change.x,change.y,change.z)
			var sine := vector.length()
			# atan2 avoids acos(w) precision loss for sub-degree pose steps.
			var angle := 2.0*atan2(sine,change.w)
			var velocity := vector*(angle/(sine*delta)) if sine > 0.0000001 else Vector3.ZERO
			# IK arm joints can counter-rotate faster than their composed world
			# hand motion. A head-sized cap destroys that cancellation at release.
			var humanoid := str(avatar.bone_index.find_key(idx))
			var carry_limit := 720.0 if _bone_channel(humanoid) == "arms" else 120.0
			_pose_velocity[idx] = velocity.limit_length(deg_to_rad(carry_limit))
		_previous_pose[idx] = current


## This runs before facing or any IK. A caller may replace the model directly,
## so correctness cannot depend on the host remembering reset_all().
func _check_model_identity() -> void:
	var current_id := avatar.model.get_instance_id()
	if current_id == _avatar_id:
		return
	var replacing := _avatar_id != 0
	_avatar_id = current_id
	_hand_goals.clear()
	_transition_from.clear()
	_transition_velocity.clear()
	_previous_pose.clear()
	_pose_velocity.clear()
	_previous_hips_position = Vector3.INF
	_hips_velocity = Vector3.ZERO
	_transition_hips_velocity = Vector3.ZERO
	_applied.clear()
	if replacing:
		seated_carrier.clear(self)
		authored_seated_feet.clear_reference()
		_source_seat_profiles.clear()
		seated_transition.reset()
		upper_body.clear()
		upper_body.contact_locked = false
		authored_ambient.reset()
		_ambient_attention_override = false
		_transition_hips_from = Vector3.INF
		_ambient_was_allowed = false
		turn.cancel()
		gait = DesktopGait.new()
		gait.view_yaw_radians = view_yaw_radians
		_facing_target = avatar.rotation.y
		_facing_velocity = 0.0
		_heading_pending = false
		_travel_intent = false
		_contact_pose = "foot"
		_contact_target = Vector3.INF
		contact_reachable = false
	# Assets can register before the avatar exists. Complete the immutable
	# mesh-input warmup at model readiness, not the first user sit boundary.
	if not seated_transition.clips.is_empty():
		prepare_seated_geometry_inputs()

## Zero velocity and acceleration at both ends of authored layer ownership.
static func _blend_weight(value: float) -> float:
	var u := clampf(value,0.0,1.0)
	return u*u*u*(u*(u*6.0-15.0)+10.0)
