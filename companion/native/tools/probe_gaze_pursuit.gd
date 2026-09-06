extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var failures := 0
	var traces := {}
	for fps in [30,60]:
		var motion := MotionPlayer.new()
		root.add_child(motion)
		motion.set_process(false)
		var last_velocity := Vector2.ZERO
		var max_speed := 0.0
		var max_accel := 0.0
		var points: Array[Vector2] = []
		for frame in fps*6:
			var target := Vector2(0.9,0.75) if frame < fps*3 else Vector2(0.1,0.2)
			motion._advance_gaze(target,1.0/fps)
			max_speed = maxf(max_speed,motion._gaze_velocity.length())
			max_accel = maxf(max_accel,(motion._gaze_velocity-last_velocity).length()*fps)
			last_velocity = motion._gaze_velocity
			if fps == 30 or frame%2 == 1:
				points.append(motion._gaze_current)
			if not Rect2(Vector2(0.09,0.19),Vector2(0.82,0.57)).has_point(motion._gaze_current):
				failures += 1
		traces[fps] = points
		print("GAZE fps=",fps," max_normalized_speed=",max_speed," max_normalized_acceleration=",max_accel," final=",motion._gaze_current)
		if max_speed > 0.601 or max_accel > 1.9:
			failures += 1
		motion.free()
	var frame_difference := 0.0
	for i in traces[30].size():
		frame_difference = maxf(frame_difference,traces[30][i].distance_to(traces[60][i]))
	if frame_difference > 0.001:
		failures += 1
	var ambient := MotionPlayer.new()
	root.add_child(ambient)
	ambient.set_process(false)
	ambient.avatar = VrmAvatar.new()
	root.add_child(ambient.avatar)
	ambient._ambient_strength = 1.0
	var previous := Vector3.ZERO
	var ambient_max_accel := 0.0
	for frame in 600:
		if frame%120 == 0:
			ambient.set_ambient_state(["curious","working","thinking","attentive","rest"][int(frame/120)],1.0)
		ambient.elapsed += 1.0/60
		ambient._apply_ambient(1.0/60)
		var velocity: Vector3 = ambient._ambient_velocity.get("head",Vector3.ZERO)
		ambient_max_accel = maxf(ambient_max_accel,(velocity-previous).length()*60)
		if velocity.length() > 3.001:
			failures += 1
		previous = velocity
	if ambient_max_accel > 12.01:
		failures += 1
	ambient._preview = true
	ambient._apply_ambient(1.0/60)
	if not ambient._ambient_pose.is_empty():
		failures += 1
	ambient.avatar.free()
	ambient.free()
	print("AMBIENT_MAX_ACCEL_DEGREES=",ambient_max_accel)
	print("GAZE_30_60_MAX_DIFFERENCE=",frame_difference," GAZE_FAILURES=",failures)
	quit(1 if failures else 0)
