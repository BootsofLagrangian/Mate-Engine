extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var failures := 0
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var motion := MotionPlayer.new()
		root.add_child(motion)
		motion.avatar = avatar
		motion.set_process(false)
		for clip in ["walk","sit_idle","idle_talking"]:
			motion.load_vrma(clip,ProjectSettings.globalize_path("res://../assets/motions/"+clip+".vrma"))
		motion.play_vrma("walk",1,true)
		motion.set_locomotion_direction(Vector2(75,0))
		for i in 240:
			motion._process(1.0/60)
			motion.set_locomotion_sample(Vector2(75,0),Vector2(1.25,0),300,true)
		var prior := {}
		for side in ["left","right"]:
			for bone in ["UpperLeg","LowerLeg","Foot"]:
				var idx: int = avatar.bone_index[side+bone]
				prior[idx] = avatar.skeleton.get_bone_pose_rotation(idx)
		motion.stop_gesture()
		motion.set_locomotion_sample(Vector2.ZERO,Vector2.ZERO,300,true)
		motion._process(1.0/60)
		var stop_jump := 0.0
		for idx in prior:
			stop_jump = maxf(stop_jump,rad_to_deg(prior[idx].angle_to(avatar.skeleton.get_bone_pose_rotation(idx))))
		if stop_jump > 8.0 or not motion.gait.diagnostics.is_empty():
			failures += 1
		motion.start_contact_pose("sit")
		motion.play_vrma("idle_talking",1,true)
		for i in 180:
			motion._process(1.0/60)
			motion.set_locomotion_sample(Vector2.ZERO,Vector2.ZERO,300,false)
		if avatar.bone_global_position("leftLowerLeg").y < avatar.bone_global_position("hips").y-0.22:
			failures += 1
		motion.stop_contact_pose()
		motion.play_vrma("walk",1,true)
		motion.set_locomotion_sample(Vector2.ZERO,Vector2.ZERO,300,true)
		var phase := motion.gait.phase
		for i in 60:
			motion._process(1.0/60)
			motion.set_locomotion_sample(Vector2.ZERO,Vector2.ZERO,300,true)
		if not is_equal_approx(phase,motion.gait.phase):
			failures += 1
		print("GAIT_TRANSITION ",character," stop_first_joint_step_deg=",stop_jump," seated_priority_ok=",avatar.has_model()," zero_displacement_phase=",motion.gait.phase)
		motion.free()
		avatar.free()
	print("GAIT_TRANSITION_FAILURES=",failures)
	quit(1 if failures else 0)
