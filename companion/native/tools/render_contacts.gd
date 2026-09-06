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
		output = "/tmp/contact-renders"
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
		player.idle_enabled = false
		player.gaze_enabled = false
		for clip in ["walk","sit_idle"]:
			player.load_vrma(clip,ProjectSettings.globalize_path("res://../assets/motions/"+clip+".vrma"))
		for gesture in ["side_walk","sit_contact","lean_contact"]:
			player.stop_contact_pose()
			var surface := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.25,0.45,0.6)
			surface.mesh = mesh
			surface.material_override = material
			stage.add_child(surface)
			if gesture == "side_walk":
				player.play_vrma("walk",1,true)
				player.set_locomotion_direction(Vector2(75,0))
				mesh.size = Vector3(1.5,0.03,0.8)
				surface.position = avatar.contact_anchors().foot-Vector3(0,0.015,0)
			elif gesture == "sit_contact":
				player.start_contact_pose("sit")
				mesh.size = Vector3(1.0,0.03,0.40)
				surface.position = avatar.contact_anchors().sit-Vector3(0,0.015,0.1)
			else:
				for i in 180:
					player._process(1.0/60)
				var target := avatar.bone_global_position("leftUpperArm")+Vector3(0.24,-0.12,0.12)
				player.start_contact_pose("lean",target)
				mesh.size = Vector3(0.03,1.1,0.4)
				surface.position = target+Vector3(0.025,-0.3,0)
			for i in 180:
				player._process(1.0/60)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(character+"-"+gesture+".png"))
			surface.free()
		player.free()
		avatar.free()
	print("RENDERS=",output)
	quit()
