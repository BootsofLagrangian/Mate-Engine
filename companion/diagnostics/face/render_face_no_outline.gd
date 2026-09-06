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
	var output := ProjectSettings.globalize_path("res://../diagnostics/face/no-outline")
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var meshes: Array = []
		avatar._collect_meshes(avatar.model, meshes)
		for mesh in meshes:
			for surface in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(surface)
				if mat: mat.next_pass = null
		camera.position = avatar.bone_global_position("head") + Vector3(0,0.08,2)
		camera.size = 0.43
		print(character, " EXPRESSIONS ",avatar.expression_names())
		for expression in ["raw", "neutral", "aa", "oh", "ih"]:
			for weight in ([0.0] if expression == "raw" else ([1.0] if expression == "neutral" else [0.1,0.3,0.6])):
				avatar.clear_expressions()
				avatar.set_expression(expression,weight)
				avatar.apply_expressions()
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(character+"-"+expression+"-"+str(weight)+".png"))
		avatar.free()
	print("RENDERS=",output)
	quit()
