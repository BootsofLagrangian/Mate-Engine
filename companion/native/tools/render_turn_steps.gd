extends SceneTree
## Visual probe: run with a real display (not --headless). Saves rendered poses.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var baseline := not args.is_empty() and args[0] == "baseline"
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
	for i in 17:
		var mark := MeshInstance3D.new()
		var marker := BoxMesh.new()
		marker.size = Vector3(0.004,0.01,0.7)
		mark.mesh = marker
		mark.position = Vector3(-0.8+i*0.1,-0.004,0)
		stage.add_child(mark)
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	var output := OS.get_environment("MOTION_RENDER_DIR")
	if output.is_empty():
		output = "/tmp/turn-baseline" if baseline else "/tmp/turn-stepped"
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["cheval-grand"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var player := MotionPlayer.new()
		stage.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(bank)
		player.idle_enabled = false
		player.gaze_enabled = false
		var pivot: Vector3 = avatar.contact_anchors().foot
		var baseline_yaw := 0.0
		var baseline_velocity := 0.0
		var target := deg_to_rad(82.0)
		if not baseline:
			player.set_heading_intent(Vector2.RIGHT)
		for frame in 240:
			if frame == 120:
				target = 0.0
				if not baseline:
					player.face_front()
			player._process(1.0/30)
			if baseline:
				var difference := angle_difference(baseline_yaw,target)
				baseline_velocity = move_toward(baseline_velocity,clampf(difference*5,-deg_to_rad(140),deg_to_rad(140)),deg_to_rad(360)/30)
				var step := baseline_velocity/30
				if absf(step) > absf(difference) and signf(step) == signf(difference):
					step = difference
					baseline_velocity = 0.0
				baseline_yaw += step
				avatar.rotation.y = baseline_yaw
			avatar.position = -(avatar.basis*pivot)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("turn-%03d.png" % frame))
		player.free()
		avatar.free()
	print("RENDERS=",output)
	quit()
