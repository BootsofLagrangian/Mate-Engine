extends SceneTree
var output := "/tmp/mini-springs"
func _init() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(500,650)
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,.49,1.6)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.15
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-25,0)
	stage.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.1,.13,.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	stage.add_child(env)
	var rows := []
	var failures := []
	for character in ["mambo", "hachimi"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		if not avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + character + ".vrm")):
			failures.append("load " + character)
			continue
		var secondary = avatar.spring_contacts.secondary
		var max_tail_step := 0.0
		var previous := {}
		var min_y := INF
		var finite := true
		var max_angle := 0.0
		for frame in 360:
			var t := frame / 60.0
			avatar.apply_pose({"head": Vector3(0, sin(t * 2) * 18, sin(t * 1.5) * 8)})
			await create_timer(1.0/60.0).timeout
			await RenderingServer.frame_post_draw
			if secondary:
				for state in secondary.spring_bones_internal:
					for joint in state.verlets:
						finite = finite and joint.current_tail.is_finite()
						min_y = minf(min_y, joint.current_tail.y)
						if previous.has(joint.bone_idx) and frame > 30: max_tail_step = maxf(max_tail_step, joint.current_tail.distance_to(previous[joint.bone_idx]))
						previous[joint.bone_idx] = joint.current_tail
						var pose := avatar.skeleton.get_bone_pose_rotation(joint.bone_idx)
						var rest := avatar.skeleton.get_bone_rest(joint.bone_idx).basis.get_rotation_quaternion()
						max_angle = maxf(max_angle, rad_to_deg(rest.angle_to(pose)))
			if frame in [59,179,359]: root.get_texture().get_image().save_png(output.path_join(character + "-%d.png" % frame))
		var info := avatar.spring_contacts.diagnostics.duplicate()
		info.character = character
		info.runtime_springs = secondary.spring_bones_internal.size() if secondary else 0
		info.max_tail_step_m = max_tail_step
		info.min_tail_y = min_y
		info.max_pose_angle_deg_after_modifier_reset = max_angle
		info.finite = finite
		rows.append(info)
		if not finite or info.runtime_springs == 0 or max_tail_step > .06: failures.append(character)
		avatar.free()
	var report := {"scope": "published authored spring assets, 360 displayed frames per rig, head yaw18deg and roll8deg; no cloth mesh simulation", "rows": rows, "failures": failures}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
