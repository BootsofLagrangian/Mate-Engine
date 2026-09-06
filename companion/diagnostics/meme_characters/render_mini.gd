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
	var output := OS.get_environment("FACE_RENDER_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../logs/meme-renders")
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["mambo","hachimi"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		camera.position = Vector3(0,0.70,2)
		camera.size = 0.72
		avatar.rotation_degrees.y = float(OS.get_environment("MINI_YAW"))
		print(character, " EXPRESSIONS ",avatar.expression_names())
		for expression_name in ["aa", "ih", "oh", "neutral"]:
			for bind in avatar.expressions.get(expression_name, []):
				print("BIND ", character, " ", expression_name, " ", bind[0].mesh.get_blend_shape_name(bind[1]), " index=", bind[1], " weight=", bind[2])
		var jaw := avatar.skeleton.find_bone("Jaw")
		if jaw >= 0:
			print("JAW ", character, " pose=",avatar.skeleton.get_bone_pose(jaw), " rest=",avatar.skeleton.get_bone_rest(jaw))
		for expression in ["raw", "blink", "aa", "oh", "ih", "ee", "ou"]:
			for weight in ([0.0] if expression == "raw" else ([1.0] if expression == "neutral" else [0.3,0.6,1.0])):
				avatar.clear_expressions()
				avatar.set_expression(expression,weight)
				avatar.apply_expressions()
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(character+"-"+expression+"-"+str(weight)+".png"))
		avatar.free()
	print("RENDERS=",output)
	quit()
