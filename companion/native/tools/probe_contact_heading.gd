extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var failures := 0
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var pivot: Vector3 = avatar.contact_anchors().foot
		var motion := MotionPlayer.new()
		root.add_child(motion)
		motion.avatar = avatar
		motion.set_process(false)
		for direction in [215.0,0.0,35.0]:
			if not motion.set_contact_heading(deg_to_rad(direction)): failures+=1
			if motion.set_contact_heading(INF): failures+=1
			var prior := {}
			var max_drift := 0.0
			var max_speed := 0.0
			var max_accel := 0.0
			var previous_yaw := avatar.rotation.y
			var previous_speed := 0.0
			var held_frames := 0
			var finish_time := 6.0
			var depth_min := INF
			var depth_max := -INF
			for frame in 360:
				motion._process(1.0/60)
				avatar.position = -(avatar.basis*pivot)
				var speed := angle_difference(previous_yaw,avatar.rotation.y)*60
				max_speed = maxf(max_speed,absf(rad_to_deg(speed)))
				max_accel = maxf(max_accel,absf(rad_to_deg(speed-previous_speed)*60))
				previous_yaw = avatar.rotation.y
				previous_speed = speed
				for side in motion.turn.diagnostics:
					var d: Dictionary = motion.turn.diagnostics[side]
					var point := avatar.bone_global_position(side+"Foot")
					depth_min = minf(depth_min,point.z)
					depth_max = maxf(depth_max,point.z)
					if d.stance and prior.has(side) and prior[side].stance:
						max_drift = maxf(max_drift,point.distance_to(prior[side].point))
						held_frames += 1
					prior[side] = {"stance":d.stance,"point":point}
				if motion.heading_ready():
					finish_time = (frame+1)/60.0
					break
			print("TURN ",character," direction=",direction," ready_seconds=",finish_time," held_frames=",held_frames," held_drift_m=",max_drift," speed_deg_s=",max_speed," accel_deg_s2=",max_accel," actual_foot_depth_span_m=",depth_max-depth_min)
			if finish_time >= 6 or held_frames < 30 or max_drift > 0.003 or max_speed > 71 or max_accel > 105:
				failures += 1
		motion.free()
		avatar.free()
	print("CONTACT_HEADING_FAILURES=",failures)
	quit(1 if failures else 0)
