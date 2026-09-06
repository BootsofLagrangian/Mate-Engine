extends SceneTree
## Visual probe: run with a real display (not --headless). Saves rendered poses.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var selected := str(args[0]) if not args.is_empty() else "mambo_sway"
	var walking := OS.get_environment("MEME_RENDER_WALK")=="1"
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
		var player := MotionPlayer.new()
		stage.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(bank)
		player.idle_enabled = true
		player.gaze_enabled = false
		player.load_vrma("uma_walk",ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma"))
		player.register_locomotion_clip("uma_walk",true)
		player.load_vrma(selected,ProjectSettings.globalize_path("res://../assets/motions/"+selected+".vrma"),"foot")
		player.load_vrma("uma_home_idle",ProjectSettings.globalize_path("res://../assets/motions/uma_home_idle.vrma"),"foot")
		player.set_ambient_loop("uma_home_idle")
		for frame in 60: player._process(1.0/30)
		if walking: player.prepare_locomotion(Vector2(80,0))
		else: player.play_ambient_action(selected)
		var moving:=false
		var started:=false
		var moving_time:=0.0
		for frame in (210 if walking else 165):
			player._process(1.0/30)
			if walking:
				if not moving and player.locomotion_ready():
					moving=true
					player.play_vrma("uma_walk",1,true)
				var speed:=80.0 if moving else 0.0
				var dx:=speed/30.0
				var ppm:=600.0/1.95
				avatar.position.x+=dx/ppm
				camera.position.x=avatar.position.x
				player.set_locomotion_sample(Vector2(speed,0),Vector2(dx,0),ppm,true)
				if moving: moving_time+=1.0/30
				if moving_time>=0.7 and not started:
					started=player.play_upper_body_gesture(selected)
			await process_frame
			await RenderingServer.frame_post_draw
			if frame%5==0: root.get_texture().get_image().save_png(output.path_join(selected + "-%03d.png" % frame))
		player.free()
		avatar.free()
	print("RENDERS=",output)
	quit()
