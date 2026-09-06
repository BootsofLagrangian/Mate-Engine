extends SceneTree
var checks := 0
var failures: Array = []
var maximum := 0.0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = load("res://scripts/main.gd").WINDOW_SIZE
	await process_frame
	var settings := root.get_node("Settings")
	var saved: Dictionary = settings.data.duplicate(true)
	var script := GDScript.new()
	script.source_code = "extends \"res://scripts/main.gd\"\nfunc _ready() -> void: set_process(false)\n"
	if script.reload()!=OK: quit(2); return
	var app = script.new()
	root.add_child(app)
	app.avatar = VrmAvatar.new();app.add_child(app.avatar)
	app.motion = MotionPlayer.new();app.add_child(app.motion);app.motion.set_process(false);app.motion.avatar=app.avatar
	app.camera = Camera3D.new();app.add_child(app.camera)
	app._spatial_viewport = SubViewport.new();app._spatial_viewport.size=app.REFERENCE_SIZE;app.add_child(app._spatial_viewport)
	app._spatial_reference_camera = Camera3D.new();app._spatial_viewport.add_child(app._spatial_reference_camera)
	app._spatial_origin = Vector2(-500,-200)
	for rig in ["cheval-grand","rice-shower","eishin-flash"]:
		settings.data.merge({"view_projection":"perspective","view_fov_deg":45.0,"view_distance_m":3.6,"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0},true)
		app.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+rig+".vrm"))
		app._frame_avatar()
		var pivot: Vector3 = app.avatar.global_transform * Vector3(app._pivot_local.foot)
		var expected_ppm := 760.0 / (2.0 * 3.6 * tan(deg_to_rad(45.0) * 0.5))
		var measured_ppm: float = app.camera.unproject_position(pivot + app.camera.global_basis.y).distance_to(app.camera.unproject_position(pivot))
		check(absf(measured_ppm - expected_ppm) < .01,"render padding preserves original perspective pixel scale")
		check(root.size.x >= 1100 and root.size.y >= 1100,"expanded render canvas reserves room around the existing character scale")
		for yaw in [0.0,45.0]:
			settings.data.view_yaw_deg=yaw;settings.data.view_pitch_deg=35.0
			app._apply_view_settings(false)
			var canonical: Transform3D = app.spatial_camera().global_transform
			var fixed_world := Vector3(0.2,0.3,-0.8)
			var reference_pixel: Vector2 = app.spatial_desktop_origin()+app.spatial_camera().unproject_position(fixed_world)
			for origin in [Vector2i(-800,-250),Vector2i(100,300),Vector2i(850,-80)]:
				root.position=origin
				app._update_avatar_transform(0.0)
				var actual: Vector2=app.camera.unproject_position(app.avatar.global_transform*Vector3(app._pivot_local.foot))
				maximum=maxf(maximum,actual.distance_to(app._pivot_px))
				check(actual.distance_to(app._pivot_px)<.02,"actual main foot retains local pivot after OS origin change")
				check(app.spatial_camera().global_transform.is_equal_approx(canonical),"native window motion cannot move canonical camera")
				check((Vector2(root.position)+app.camera.unproject_position(fixed_world)).distance_to(reference_pixel)<.02,"fixed world prop global projection invariant under root crop")
		settings.data.view_projection="orthographic"
		app._apply_view_settings(false)
		app._update_avatar_transform(0.0)
		pivot=app.avatar.global_transform * Vector3(app._pivot_local.foot)
		expected_ppm=AutonomyBridge.reference_height_px(760.0) / maxf(app._model_aabb.size.y,.5)
		measured_ppm=app.camera.unproject_position(pivot + app.camera.global_basis.y).distance_to(app.camera.unproject_position(pivot))
		check(absf(measured_ppm - expected_ppm) < .01,"render padding preserves original orthographic pixel scale")
	settings.data=saved
	app.free()
	print(JSON.stringify({"checks":checks,"failures":failures,"max_pivot_error_px":maximum,"scope":"Real main projection methods and three imported rigs; suppressed networking/autonomy/UI and headless OS origin simulation"}))
	quit(1 if failures else 0)
