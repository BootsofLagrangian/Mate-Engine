extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(680,760)
	root.transparent_bg = true
	var stage := Node3D.new()
	root.add_child(stage)
	var props = load("res://scripts/desktop_object_contact_scene.gd").new()
	stage.add_child(props)
	if not props.configure("computer"):
		push_error(props.error)
		quit(1)
		return
	props.rotation_degrees.y = props.recommended_yaw_degrees
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.90,0.92,0.91)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 0.8
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,1.15,3.0)
	camera.look_at(Vector3(0,.60,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.25
	camera.current = true
	for i in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../diagnostics/desktop_objects/premium-previews/computer-shared-scene-native.png")
	root.get_texture().get_image().save_png(path)
	print("SHARED_PROP_RENDER=",path)
	quit()
