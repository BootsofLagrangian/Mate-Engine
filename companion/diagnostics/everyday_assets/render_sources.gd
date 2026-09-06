extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var output := args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(420,520)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16,0.19,0.23)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.65
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-30,0)
	light.light_energy = 0.65
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,0.85,3)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.95
	camera.current = true
	var avatar := VrmAvatar.new()
	stage.add_child(avatar)
	avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	avatar.rotation.y = deg_to_rad(25)
	for path in paths:
		var clip := VrmaClip.new()
		if not clip.load_file(str(path)):
			push_error("Cannot load "+str(path))
			quit(1)
			return
		for frame in 8:
			avatar.apply_pose({})
			var t := clip.duration*float(frame)/7.0
			avatar.apply_normalized_rotations(clip.sample(t),1.0)
			var height := avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
			avatar.set_hips_offset(clip.sample_hips_offset(t)*height)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(str(path).get_file().get_basename()+"-%02d.png"%frame))
		print("RENDERED ",path)
	quit()
