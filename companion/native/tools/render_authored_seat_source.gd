extends SceneTree
## Visual probe: run with a real display (not --headless). Saves rendered poses.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := str(args[0]) if not args.is_empty() else "wave"
	root.size = Vector2i(480,600)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.15,0.18,0.23)
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
	for marker in 35:
		var grid := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.01,0.01,0.5)
		grid.mesh = box
		grid.position = Vector3(-2.0+marker*0.15,-0.01,0)
		stage.add_child(grid)
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	var output := OS.get_environment("MOTION_RENDER_DIR")
	if output.is_empty():
		output = "/tmp/gait-sequence-" + selected
	DirAccess.make_dir_recursive_absolute(output)
	for character in [OS.get_environment("WALK_CHARACTER") if not OS.get_environment("WALK_CHARACTER").is_empty() else "cheval-grand"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		avatar.rotation.y = deg_to_rad(65)
		var clip := VrmaClip.new()
		clip.load_file(OS.get_environment("SEAT_SOURCE") if not OS.get_environment("SEAT_SOURCE").is_empty() else ProjectSettings.globalize_path("res://../assets/research/seating-candidates/quaternius_sit_down.vrma"))
		var height := avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
		for frame in 90:
			avatar.apply_pose({})
			var t := clampf((frame-10.0)/45.0,0,clip.duration)
			avatar.apply_normalized_rotations(clip.sample(t),1.0)
			avatar.set_hips_offset(clip.sample_hips_offset(t)*height)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("seat-%03d.png" % frame))
		avatar.free()
	print("RENDERS=",output)
	quit()
