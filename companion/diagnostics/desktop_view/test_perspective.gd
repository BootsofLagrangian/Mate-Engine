extends SceneTree
const View = preload("res://scripts/desktop_view.gd")
var checks := 0
var failures: Array = []
var max_crop_error := 0.0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(680,760)
	var camera := Camera3D.new()
	root.add_child(camera)
	var crop_view := SubViewport.new()
	crop_view.size = Vector2i(300,240)
	root.add_child(crop_view)
	var child := Camera3D.new()
	crop_view.add_child(child)
	await process_frame
	for mode in ["orthographic","perspective"]:
		for yaw in [0.0,45.0,90.0]:
			camera.transform = Transform3D(View.orbit_basis(yaw,35),Vector3(0.3,1.2,3.6))
			camera.near = .05
			View.configure_projection(camera,mode,2.4,45.0,1.0)
			for distance in [1.0,3.6,8.0]:
				for pixel in [Vector2(80,110),Vector2(340,380),Vector2(-200,850)]:
					var point := View.screen_to_world_at_depth(camera,pixel,distance)
					check(camera.unproject_position(point).distance_to(pixel)<.002,"pixel/depth roundtrip")
					check(absf(View.depth(camera,point)-distance)<.00001,"optical depth")
					var shifted := point+View.translation_to_depth(camera,point,distance+1)
					check(camera.unproject_position(shifted).distance_to(pixel)<.002,"ray depth preserves pixel")
					var normal := camera.global_basis.z
					var hit := View.solve_screen_on_plane(camera,pixel,point,normal)
					check(hit.ok and hit.point.distance_to(point)<.00001,"ray plane intersection")
					var axes := View.projection_axes(camera,point)
					var eps := .001
					var numeric := (camera.unproject_position(point+Vector3.RIGHT*eps)-camera.unproject_position(point-Vector3.RIGHT*eps))/(2*eps)
					check(numeric.distance_to(axes.world_x)<.25,"local projection derivative")
			for crop in [Rect2(90,130,300,240),Rect2(-310,650,300,240),Rect2(740,-250,300,240)]:
				check(View.configure_crop(child,camera,crop),"configure off-axis crop")
				for distance in [1.2,3.6,9.0]:
					var pixel: Vector2 = crop.position+Vector2(90,160)
					var world := View.screen_to_world_at_depth(camera,pixel,distance)
					var error: float = (child.unproject_position(world)+crop.position).distance_to(pixel)
					max_crop_error = maxf(max_crop_error,error)
					check(error<.01,"same world global pixel under crop")
					check(View.screen_to_world_at_depth(child,Vector2(90,160),distance).distance_to(world)<.0002,"off-axis crop inverse")
					var shifted := world+View.translation_to_depth(child,world,distance+1)
					check(child.unproject_position(shifted).distance_to(Vector2(90,160))<.01,"off-axis own ray depth")
	View.configure_projection(camera,"perspective",2.4,45.0)
	camera.transform = Transform3D.IDENTITY
	var near_width := camera.unproject_position(Vector3(1,0,-2)).distance_to(camera.unproject_position(Vector3(0,0,-2)))
	var far_width := camera.unproject_position(Vector3(1,0,-4)).distance_to(camera.unproject_position(Vector3(0,0,-4)))
	check(absf(near_width/far_width-2)<.0001,"same metre mesh halves at double depth")
	check(not View.screen_delta_to_world(camera,Vector2.ONE).is_finite(),"perspective movement requires depth")
	check(View.projection_axes(camera).is_empty(),"perspective ppm requires reference")
	check(View.screen_delta_to_world(camera,Vector2.ONE,4).length()>View.screen_delta_to_world(camera,Vector2.ONE,2).length()*1.99,"depth changes pixel-to-world distance")
	print(JSON.stringify({"checks":checks,"failures":failures,"max_crop_error_px":max_crop_error,"scope":"Actual Godot cameras, 3D projection geometry and off-axis crop; no Windows rendering"}))
	quit(1 if failures else 0)
