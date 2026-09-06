extends SceneTree
## Standalone Jolt skirt proxy experiment. No character mesh is silently replaced.
var cloth: SoftBody3D
var stage: Node3D
var hand: AnimatableBody3D
var vertices := PackedVector3Array()
var rows := 9
var columns := 32
var phase := 0.0
var output := "/tmp/mate-cloth-physics"
func _init() -> void: call_deferred("run")
func sphere_body(radius: float) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	visual.mesh = mesh
	body.add_child(visual)
	return body
func make_skirt() -> ArrayMesh:
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in rows:
		var t := float(row) / (rows - 1)
		for column in columns:
			var angle := TAU * column / columns
			var radius := lerpf(0.22, 0.40, t)
			vertices.append(Vector3(cos(angle) * radius, 1.15 - t * 0.48, sin(angle) * radius))
			uv.append(Vector2(float(column) / columns, t))
	for row in rows - 1:
		for column in columns:
			var a := row * columns + column
			var b := row * columns + (column + 1) % columns
			indices.append_array(PackedInt32Array([a, a + columns, b, b, a + columns, b + columns]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh, 0)
	surface.generate_normals()
	return surface.commit()
func sample_frames(count: int) -> Dictionary:
	var cpu := []
	var render_gpu := []
	var render_cpu := []
	var start := Time.get_ticks_usec()
	var start_frames := Engine.get_process_frames()
	for i in count:
		phase += 1.0 / 60.0
		hand.position = Vector3(sin(phase * 1.7) * 0.36, 0.88, 0.25)
		await physics_frame
		cpu.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	cpu.sort()
	return {"physics_frames": count, "wall_ms": (Time.get_ticks_usec()-start)/1000.0, "render_frames": Engine.get_process_frames()-start_frames, "physics_ms_mean": mean(cpu), "physics_ms_p95": cpu[int(cpu.size()*0.95)], "render_gpu_ms_mean": mean(render_gpu), "render_cpu_ms_mean": mean(render_cpu)}
func mean(values: Array) -> float:
	var total := 0.0
	for value in values: total += value
	return total / max(1, values.size())
func run() -> void:
	if not OS.get_environment("CLOTH_OUTPUT").is_empty(): output = OS.get_environment("CLOTH_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(640, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.05,0.07,0.1)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-30,0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(1.4,1.6,2.1)
	camera.look_at(Vector3(0,0.85,0))
	var pelvis := sphere_body(0.18)
	pelvis.position = Vector3(0,1.07,0)
	stage.add_child(pelvis)
	hand = sphere_body(0.085)
	stage.add_child(hand)
	await sample_frames(120) # settle startup and shader compilation before the matched baseline
	var baseline: Dictionary = await sample_frames(120)
	cloth = SoftBody3D.new()
	cloth.mesh = make_skirt()
	vertices = cloth.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	cloth.simulation_precision = 8
	cloth.linear_stiffness = 0.75
	cloth.total_mass = 0.22
	cloth.damping_coefficient = 0.12
	cloth.pressure_coefficient = 0.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12,0.34,0.68)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.9
	cloth.material_override = material
	stage.add_child(cloth)
	var pin_count := 0
	for i in vertices.size():
		if vertices[i].y > 1.149:
			cloth.set_point_pinned(i, true)
			pin_count += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("before.png"))
	var active: Dictionary = await sample_frames(360)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("after.png"))
	var max_motion := 0.0
	var pinned_error := 0.0
	var min_y := INF
	var max_y := -INF
	var finite := true
	for i in vertices.size():
		var point := cloth.get_point_transform(i)
		finite = finite and point.is_finite()
		if cloth.is_point_pinned(i): pinned_error = maxf(pinned_error, point.distance_to(vertices[i]))
		else: max_motion = maxf(max_motion, point.distance_to(vertices[i]))
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var report := {"engine": Engine.get_version_info(), "physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"), "adapter": RenderingServer.get_video_adapter_name(), "scope": "new 288-vertex skirt proxy, not imported character garment; matched scene baseline excludes cloth", "vertices": vertices.size(), "triangles": (rows-1)*columns*2, "pinned_vertices": pin_count, "baseline": baseline, "cloth": active, "finite": finite, "max_deformation_m": max_motion, "pinned_max_error_m": pinned_error, "min_y": min_y, "max_y": max_y}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if finite and max_motion > 0.02 and pinned_error < 0.005 else 1)
