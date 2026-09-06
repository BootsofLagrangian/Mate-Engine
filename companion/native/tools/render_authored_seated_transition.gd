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
		var player:=MotionPlayer.new()
		stage.add_child(player)
		player.set_process(false)
		player.avatar=avatar
		player.idle_enabled=false
		player.gaze_enabled=false
		var prefix:=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/uma_sitdown01_")
		player.load_vrma("sit_enter",prefix+"s.vrma")
		player.load_vrma("sit_exit",prefix+"e.vrma")
		player.load_vrma("sit_idle",prefix+"loop.vrma")
		player.register_seated_transition("enter","sit_enter")
		player.register_seated_transition("exit","sit_exit")
		for frame in 30:
			player._process(1.0/30)
			await process_frame
		avatar.rotation.y=deg_to_rad(65)
		player._facing_target=avatar.rotation.y
		player._facing_velocity=0
		player._heading_pending=false
		player.turn.cancel()
		player.set_seated_floor(0.48)
		var geometry:=avatar.calibrate_seated_pose(player.vrma_clips.sit_idle.sample(0))
		var delta:Vector3=player.seated_transition_requirements("enter").source_root_delta_local
		delta.y=0.48-Vector3(geometry.anchor).y
		var world_delta:=avatar.global_basis*delta
		var seat:=MeshInstance3D.new()
		var box:=BoxMesh.new()
		box.size=Vector3(0.48,0.04,0.42)
		seat.mesh=box
		seat.rotation.y=avatar.rotation.y
		seat.position=avatar.global_transform*Vector3(0,Vector3(geometry.anchor).y-0.02,0)+world_delta
		stage.add_child(seat)
		var origin:=avatar.position
		player.start_seated_transition("enter",delta)
		var entered:=false
		var exiting:=false
		var seated_frames:=0
		for frame in 130:
			player._process(1.0/30)
			var state:=player.seated_transition_state()
			if not state.is_empty() and state.active:
				avatar.position=origin+(world_delta if not exiting else -world_delta)*float(state.root_progress)
				if state.finished:
					player.finish_seated_transition()
					entered=true
			elif entered and not exiting:
				seated_frames+=1
				if seated_frames==20:
					origin=avatar.position
					exiting=true
					player.start_seated_transition("exit",-delta)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("seat-%03d.png" % frame))
		player.free()

		avatar.free()
	print("RENDERS=",output)
	quit()
