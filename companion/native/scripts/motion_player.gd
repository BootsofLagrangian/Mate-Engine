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
var _transition_velocity: Dictionary = {}
var _previous_pose: Dictionary = {}
var _pose_velocity: Dictionary = {}
var _transition_start := 0.0
const TRANSITION_SECONDS := 0.45
var _facing_target := 0.0
var _facing_velocity := 0.0
var _contact_pose := "foot"
var _contact_hand := "right"
var _contact_target := Vector3.INF
var contact_reachable := false
var gait := DesktopGait.new()
var turn := TurnStepper.new()
var _heading_pending := false
const HEADING_SPEED := deg_to_rad(70.0)
const HEADING_ACCEL := deg_to_rad(100.0)
var _ambient_name := "rest"
var _ambient_strength := 0.0
var _ambient_target := 0.0
var _ambient_look := Vector2.INF
var _ambient_pose: Dictionary = {}
var _ambient_velocity: Dictionary = {}
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


func set_bank(new_bank: MotionBank) -> void:
	bank = new_bank if new_bank else MotionBank.new()


## Play a gesture from the bank. Unknown names fall back to idle (contract: gesture IDs from the fetched bank).
func play_gesture(name: String, emotion: String = "", intensity: float = 1.0, speed: float = 1.0, repeat: int = 1, preview: bool = false) -> bool:
	if not emotion.is_empty():
		set_emotion(emotion)
	if vrma_clips.has(name):
		var started := play_vrma(name, speed, false, repeat)
		_vrma_intensity = clampf(intensity, 0.0, 1.0)
		_preview = preview
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
	_contact_target = Vector3.INF
	contact_reachable = false
	turn.cancel()
	gait = DesktopGait.new()
	_facing_target = 0.0
	_facing_velocity = 0.0
	_heading_pending = false
	_hand_goals.clear()
	_applied.clear()
	_transition_from.clear()
	_transition_velocity.clear()
	_previous_pose.clear()
	_pose_velocity.clear()
	_ambient_pose.clear()
	_ambient_velocity.clear()
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
			if _vrma_loop and _vrma_name in ["walk","walk_formal"] and gait.has_sample() and _contact_pose == "foot":
				local_time = gait.phase*clip.duration
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
	_apply_ambient(delta)
	var contact_solvable := false
	if _contact_pose == "lean":
		contact_solvable = avatar.apply_hand_contact(_contact_hand,_contact_target)
	_apply_transition()
	gait.apply(avatar,delta,_vrma_loop and _vrma_name in ["walk","walk_formal"] and _contact_pose == "foot" and not _custom_motion and not turn.active)
	turn.apply(avatar,delta,_facing_target,_preview or _custom_motion or _contact_pose != "foot")
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
	_record_pose_velocity(delta)


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
	_transition_velocity = _pose_velocity.duplicate()
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

func set_heading_intent(direction_px: Vector2) -> void:
	if absf(direction_px.x) <= 0.001:
		return
	var wanted := deg_to_rad(82.0)*signf(direction_px.x)
	if absf(angle_difference(_facing_target,wanted)) > 0.001:
		_facing_target = wanted
		_heading_pending = true

func face_front() -> void:
	_facing_target = 0.0
	_heading_pending = true

func heading_ready() -> bool:
	return avatar != null and absf(angle_difference(avatar.rotation.y,_facing_target)) < deg_to_rad(1.0) and absf(_facing_velocity) < deg_to_rad(2.0) and not turn.active

func cancel_heading() -> void:
	if avatar == null:
		return
	# Preserve current velocity while braking; stopping the OS window does not
	# require an instantaneous stop in the character's angular motion.
	_facing_target = avatar.rotation.y+signf(_facing_velocity)*_facing_velocity*_facing_velocity/(2*HEADING_ACCEL)
	_heading_pending = absf(_facing_velocity) > deg_to_rad(1)

func _update_facing(delta: float) -> void:
	var blocked := _preview or _custom_motion
	if blocked:
		turn.cancel()
		cancel_heading()
	var difference := angle_difference(avatar.rotation.y,_facing_target)
	if _heading_pending and not blocked and _contact_pose == "foot" and absf(difference) > deg_to_rad(2) and not turn.active:
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


## Host calls once after actual window movement, even when displacement is zero.
## Effective pixels/metre = orthographic camera ppm * user avatar scale.
func set_locomotion_sample(velocity_px: Vector2, traveled_px: Vector2, pixels_per_metre: float, supported: bool = true) -> void:
	var owns_legs := _vrma_loop and _vrma_name in ["walk","walk_formal"] and _contact_pose == "foot" and not _custom_motion and not _preview and not turn.active
	if owns_legs:
		set_locomotion_direction(velocity_px)
	gait.sample(velocity_px,traveled_px,pixels_per_metre,supported and owns_legs)
	if avatar != null and avatar.has_model():
		gait.compensate_movement(avatar)

## Bounded low-rate behavior intent; speech/gestures retain expression ownership.
## Optional look point is normalized viewport coordinates. Explicit user gaze
## remains higher priority. Strength clamps to 0..1, unknown states become rest.
func set_ambient_state(name: String, strength: float = 1.0, look: Vector2 = Vector2.INF) -> void:
	_ambient_name = name if name in ["rest","curious","anticipate","settle","sleepy","attentive","thinking","working","listening"] else "rest"
	_ambient_target = clampf(strength,0.0,1.0)
	_ambient_look = look.clamp(Vector2.ZERO,Vector2.ONE) if look.is_finite() else Vector2.INF

func _apply_ambient(delta: float) -> void:
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
	if delta <= 0.00001:
		return
	for idx in avatar.bone_rest_local:
		var current := avatar.skeleton.get_bone_pose_rotation(idx)
		if _previous_pose.has(idx):
			var change: Quaternion = (_previous_pose[idx].inverse()*current).normalized()
			if change.w < 0:
				change = Quaternion(-change.x,-change.y,-change.z,-change.w)
			var vector := Vector3(change.x,change.y,change.z)
			var sine := vector.length()
			# atan2 avoids acos(w) precision loss for sub-degree pose steps.
			var angle := 2.0*atan2(sine,change.w)
			var velocity := vector*(angle/(sine*delta)) if sine > 0.0000001 else Vector3.ZERO
			_pose_velocity[idx] = velocity.limit_length(deg_to_rad(120.0))
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
	_applied.clear()
	if replacing:
		turn.cancel()
		gait = DesktopGait.new()
		_facing_target = avatar.rotation.y
		_facing_velocity = 0.0
		_heading_pending = false
		_contact_pose = "foot"
		_contact_target = Vector3.INF
		contact_reachable = false
