extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var failures := 0
	var avatar := VrmAvatar.new()
	root.add_child(avatar)
	var motion := MotionPlayer.new()
	root.add_child(motion)
	motion.avatar = avatar
	motion.set_process(false)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		if avatar.has_model():
			motion.set_heading_intent(Vector2.RIGHT if avatar.rotation.y < 0.5 else Vector2.LEFT)
			for i in 20: motion._process(1.0/60)
			if not motion.turn.active: failures += 1
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		motion._process(1.0/60)
		if motion.turn.active or not motion.turn.diagnostics.is_empty() or not motion.gait.diagnostics.is_empty() or absf(motion._facing_velocity) > 0.00001:
			failures += 1
		for idx in avatar.bone_index.values():
			if not avatar.skeleton.get_bone_global_pose(idx).is_finite(): failures += 1
		print("SWITCH ",character," turn_active=",motion.turn.active," old_contact_count=",motion.turn.diagnostics.size())
	motion.set_heading_intent(Vector2.LEFT if avatar.rotation.y > -0.5 else Vector2.RIGHT)
	for i in 20: motion._process(1.0/60)
	motion.reset_all()
	if motion.turn.active or not motion._transition_from.is_empty() or not motion._pose_velocity.is_empty() or absf(motion._facing_velocity) > 0.00001 or motion._heading_pending:
		failures += 1
	motion.free()
	avatar.free()
	print("MODEL_SWITCH_FAILURES=",failures)
	quit(1 if failures else 0)
