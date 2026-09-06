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
		output = "/tmp/uma-seated-renders"
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
		player.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
		player.start_contact_pose("sit")
		var geometry := avatar.calibrate_seated_pose(player.vrma_clips.sit_idle.sample(0))
		avatar.rotation.y=PI/2
		for i in 120: player._process(1.0/60)
		avatar.rotation.y=PI/2
		var plane:=MeshInstance3D.new()
		var box:=BoxMesh.new()
		box.size=Vector3(1.5,0.006,1.0)
		plane.mesh=box
		plane.position.y=geometry.anchor.y
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color(0.2,0.7,0.8)
		plane.material_override=material
		stage.add_child(plane)
		for child in avatar.skeleton.get_children(true):
			if child.name == "VRM_internal_skeleton_modifier":
				child.modification_processed.connect(func():
					var modified := preload("res://tools/seated_snapshot.gd").measure(avatar,{})
					print("MODIFIED_SEAT ",character," bounds=",modified.bounds)
					var secondary:={}
					for idx in avatar.skeleton.get_bone_count():
						if not avatar.bone_rest_local.has(idx): secondary[idx]=[avatar.skeleton.get_bone_pose_position(idx),avatar.skeleton.get_bone_pose_rotation(idx),avatar.skeleton.get_bone_pose_scale(idx)]
					var cached := preload("res://tools/seated_cached_candidate.gd").measure(avatar,player.vrma_clips.sit_idle.sample(0),secondary)
					print("CACHED_SEAT ",character," bounds=",cached.bounds," anchor=",cached.anchor)
				,CONNECT_ONE_SHOT)
		await process_frame
		await RenderingServer.frame_post_draw
		var live_geometry := preload("res://tools/seated_snapshot.gd").measure(avatar,{})
		print("LIVE_SEAT ",character," canonical=",geometry.bounds," live=",live_geometry.bounds," anchor=",live_geometry.anchor)
		root.get_texture().get_image().save_png(output.path_join(character+"-seat.png"))
		plane.free()
		player.free()
		avatar.free()
	print("RENDERS=",output)
	quit()
