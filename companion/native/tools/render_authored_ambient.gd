extends SceneTree
## Visual probe: run with a real display (not --headless). Saves rendered poses.
func _init() -> void:
	call_deferred("run")
func run() -> void:
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
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	var output := OS.get_environment("MOTION_RENDER_DIR")
	if output.is_empty():
		output = "/tmp/authored-ambient-renders"
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var player := MotionPlayer.new()
		stage.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(bank)
		player.idle_enabled = true
		player.gaze_enabled = false
		if "sequence" in OS.get_cmdline_user_args() and character == "cheval-grand":
			for alias in ["uma_home_idle","uma_cheval_idle_action"]:
				player.load_vrma(alias,ProjectSettings.globalize_path("res://../assets/research/uma/candidates/"+alias+".vrma"))
			player.set_ambient_loop("uma_home_idle")
			for frame in 240:
				if frame == 90:
					player.play_ambient_action("uma_cheval_idle_action")
				player._process(1.0/30)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("sequence-%04d.png" % frame))
			player.free()
			avatar.free()
			quit()
			return
		for gesture in ["uma_home_idle","uma_cheval_idle","uma_rice_idle","uma_eishin_idle"]:
			player.load_vrma(gesture, ProjectSettings.globalize_path("res://../assets/research/uma/candidates/"+gesture+".vrma"))
			player.set_ambient_loop(gesture)
			var clip: VrmaClip = player.vrma_clips[gesture]
			for i in 180:
				player._process(1.0/60)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(character+"-"+gesture+".png"))
		player.free()
		avatar.free()
	print("RENDERS=",output)
	quit()
