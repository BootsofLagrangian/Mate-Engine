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
var _vrma_name := ""
var _vrma_start := 0.0
var _vrma_speed := 1.0
var _vrma_loop := false
var _vrma_repeat := 1
var _vrma_intensity := 1.0
var _transition_from: Dictionary = {}
var _transition_start := 0.0
const TRANSITION_SECONDS := 0.45
var _facing_target := 0.0
var _facing_velocity := 0.0
var _contact_pose := "foot"
var _contact_hand := "right"
var _contact_target := Vector3.INF
var contact_reachable := false
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
var _noise := FastNoiseLite.new()
var _blink_value := 0.0
var _mouth_smooth := 0.0


func _ready() -> void:
	process_priority = -10 # pose before spring bones/secondary update
	_noise.seed = randi()
	_noise.frequency = 0.35
	_blink_next = randf_range(1.5, 4.0)


func set_bank(new_bank: MotionBank) -> void:
	bank = new_bank if new_bank else MotionBank.new()


## Play a gesture from the bank. Unknown names fall back to idle (contract: gesture IDs from the fetched bank).
func play_gesture(name: String, emotion: String = "", intensity: float = 1.0, speed: float = 1.0, repeat: int = 1, preview: bool = false) -> bool:
	if not emotion.is_empty():
		set_emotion(emotion)
	if vrma_clips.has(name):
		var started := play_vrma(name, speed, false, repeat)
		_vrma_intensity = clampf(intensity, 0.0, 1.0)
		return started
	_begin_transition()
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
	return _vrma_name if not _vrma_name.is_empty() else (_gesture_name if _gesture_active else "idle")


func is_gesture_active() -> bool:
	return _gesture_active or not _vrma_name.is_empty()


func set_emotion(emotion: String, weight: float = 0.5, hold: float = EMOTION_HOLD) -> void:
	var mapped: String = EMOTION_MAP.get(emotion.to_lower(), "neutral")
	_emotion = mapped
	_emotion_target = 0.0 if mapped == "neutral" else weight
	_emotion_until = elapsed + hold


func current_emotion() -> String:
	return _emotion


## Reset gesture, emotion and mouth (used on cancel/character switch).
func reset_all() -> void:
	stop_gesture()
	_emotion = "neutral"
	_emotion_target = 0.0
	mouth_open = 0.0
	_mouth_smooth = 0.0
	_contact_pose = "foot"
	_facing_target = 0.0
	_pet_until = 0.0


func pet_reaction() -> void:
	_pet_until = elapsed + 1.6
	set_emotion("happy", 0.6, 2.5)


func _process(delta: float) -> void:
	elapsed += delta
	if avatar == null or not avatar.has_model():
		return
	_update_facing(delta)
	var k := 1.0 - exp(-SMOOTH_RATE * delta)
	var target := {}

	# 1. Bank gesture layer
	if _gesture_active:
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
	if gaze_enabled:
		var wanted := gaze_target if gaze_has_target else Vector2(0.5 + 0.12 * sin(elapsed * 0.23), 0.45 + 0.08 * sin(elapsed * 0.31 + 0.4))
		_gaze_current = _gaze_current.lerp(wanted, 1.0 - exp(-4.0 * delta))
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
	if _avatar_id != avatar.model.get_instance_id():
		_avatar_id = avatar.model.get_instance_id()
		_hand_goals.clear()
		_transition_from.clear()
	var use_ik := ik_enabled and not _custom_motion
	if use_ik:
		for side in ["left", "right"]:
			for joint in ["UpperArm", "LowerArm", "Hand"]:
				_applied.erase(side + joint)
	avatar.apply_pose(_applied)
	_apply_seated_base()
	if use_ik:
		_update_hand_goals(delta)
		avatar.apply_hand_goals(_hand_goals)
		if _gesture_active and _gesture_name == "wave":
			var phase := fmod((elapsed-_gesture_start)*_gesture_speed, maxf(float(_gesture.get("duration",4.0)),0.1))
			var envelope := smoothstep(0.0,0.8,phase) * smoothstep(0.0,0.8,float(_gesture.get("duration",4.0))-phase)
			avatar.add_wrist_rotation("right", Vector3(0,0,12.0*sin(phase*TAU*1.5)*envelope*minf(_gesture_intensity,1.25)))

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
			var blend := smoothstep(0.0, TRANSITION_SECONDS, elapsed-_vrma_start)
			if not _vrma_loop:
				blend *= smoothstep(0.0, TRANSITION_SECONDS, (total-time)/_vrma_speed)
			var sampled_pose := clip.sample(local_time)
			if _contact_pose == "sit":
				# Contact owns the seated lower body even when dialogue plays a
				# full-body imported clip over it.
				for bone in sampled_pose.keys():
					if bone == "hips" or "Leg" in bone or "Foot" in bone or "Toes" in bone:
						sampled_pose.erase(bone)
			avatar.apply_normalized_rotations(sampled_pose, blend * _vrma_intensity)
	var contact_solvable := false
	if _contact_pose == "lean":
		contact_solvable = avatar.apply_hand_contact(_contact_hand,_contact_target)
	_apply_transition()
	# A geometrically solvable target is not yet attached while blending in.
	# Report the rendered wrist's final world-space error (1.5 cm threshold).
	contact_reachable = contact_solvable and avatar.bone_global_position(_contact_hand+"Hand").distance_to(_contact_target) < 0.015

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


func _update_hand_goals(delta: float) -> void:
	var age := (elapsed - _gesture_start) * _gesture_speed
	var duration := float(_gesture.get("duration", 1.0))
	var phase := fmod(age, maxf(duration, 0.1))
	# Quintic ease has zero velocity and acceleration at each end.
	var fade := minf(clampf(phase / 0.8, 0, 1), clampf((duration - phase) / 0.8, 0, 1)) if _gesture_active else 0.0
	fade = fade * fade * fade * (fade * (fade * 6.0 - 15.0) + 10.0)
	fade *= minf(_gesture_intensity, 1.25)
	for side in ["left", "right"]:
		var sign_side := 1.0 if side == "left" else -1.0
		var rest := Vector3(sign_side * 0.20 * float(motion_style.get("openness", 1.0)), -0.94, 0.08)
		var goal := rest
		var energy := float(motion_style.get("energy", 1.0))
		match _gesture_name:
			"wave":
				if side == "right":
					goal = Vector3(-0.57 + sin(phase * TAU * 1.5) * 0.075 * energy, 0.32, 0.32)
			"stretch":
				goal = Vector3(sign_side * 0.42, 0.85, 0.06)
			"think":
				if side == "right":
					goal = Vector3(0.08, 0.04, 0.42)
			"shy":
				goal = Vector3(-sign_side * 0.12, -0.38, 0.46)
			"bow":
				goal = Vector3(sign_side * 0.14, -0.90, 0.25)
		goal = rest.lerp(goal, fade)
		if idle_enabled:
			goal.z += 0.008 * sin(elapsed * TAU / 4.2)
		var current: Vector3 = _hand_goals.get(side, rest)
		var smooth := current.lerp(goal, 1.0 - exp(-float(motion_style.get("response", 7.0)) * delta))
		_hand_goals[side] = current.move_toward(smooth, 2.0 * delta)


func load_vrma(name: String, path: String) -> bool:
	var clip := VrmaClip.new()
	if not clip.load_file(path):
		push_warning("VRMA: " + clip.error)
		return false
	vrma_clips[name] = clip
	return true

## loop=true plays until stop/supersession; otherwise repeat is a finite cycle count.
func play_vrma(name: String, speed: float = 1.0, loop: bool = false, repeat: int = 1) -> bool:
	if not vrma_clips.has(name):
		return false
	stop_gesture()
	_vrma_name = name
	_vrma_start = elapsed
	_vrma_speed = clampf(speed,0.5,2.0)
	_vrma_loop = loop
	_vrma_repeat = clampi(repeat,1,3)
	_vrma_intensity = 1.0
	gesture_started.emit(name, -1.0 if loop else vrma_clips[name].duration * _vrma_repeat / _vrma_speed)
	return true


func _begin_transition() -> void:
	_transition_from.clear()
	_transition_start = elapsed
	if avatar == null or not avatar.has_model():
		return
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
	for idx in _transition_from:
		if idx >= avatar.skeleton.get_bone_count():
			continue
		var wanted := avatar.skeleton.get_bone_pose_rotation(idx)
		avatar.skeleton.set_bone_pose_rotation(idx, _transition_from[idx].slerp(wanted,weight))


## Screen-space velocity (+X right). No model translation: the desktop host
## owns window position; this only turns the character into its travel direction.
func set_locomotion_direction(velocity: Vector2) -> void:
	_facing_target = deg_to_rad(82.0)*signf(velocity.x) if absf(velocity.x) > 1.0 else 0.0

func _update_facing(delta: float) -> void:
	var difference := angle_difference(avatar.rotation.y,_facing_target)
	var wanted := clampf(difference*5.0,-deg_to_rad(140),deg_to_rad(140))
	_facing_velocity = move_toward(_facing_velocity,wanted,deg_to_rad(360)*delta)
	var step := _facing_velocity*delta
	if absf(step) > absf(difference) and signf(step) == signf(difference):
		step = difference
		_facing_velocity = 0.0
	avatar.rotation.y += step

## A sit needs the imported sit_idle clip. Lean requires an explicit nearby
## surface point; the host must inspect contact_reachable before attaching it.
func start_contact_pose(pose: String, world_hand_target: Vector3 = Vector3.INF) -> bool:
	contact_reachable = false
	if pose == "sit":
		if not play_vrma("sit_idle",1.0,true):
			return false
		_contact_pose = "sit"
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
	var pose := clip.sample(fmod(elapsed,maxf(clip.duration,0.001)))
	for bone in pose.keys():
		if bone != "hips" and not ("Leg" in bone or "Foot" in bone or "Toes" in bone):
			pose.erase(bone)
	avatar.apply_normalized_rotations(pose,1.0)
