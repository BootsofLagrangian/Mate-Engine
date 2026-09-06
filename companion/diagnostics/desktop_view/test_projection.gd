extends SceneTree
const View = preload("res://scripts/desktop_view.gd")
var checks := 0
var failures := []
var max_pixel_error := 0.0
var max_contact_error := 0.0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(680,760)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	await process_frame
	check(root.get_visible_rect().size == Vector2(680,760),"actual viewport dimensions")
	check(View.orbit_basis(0,0).is_equal_approx(Basis.IDENTITY),"default orientation preserves identity")
	var clamped: Dictionary = View.clamp_settings({"yaw_deg":999,"pitch_deg":-999,"height_m":NAN,"zoom":"bad"})
	check(clamped == {"yaw_deg":180.0,"pitch_deg":-60.0,"height_m":0.0,"zoom":1.0},"finite setting clamps and defaults")
	check(View.orbit_basis(0,0,0.5).z.y > 0.1,"height changes elevation instead of an invisible pan")
	var cases := 0
	for yaw in [-180.0,-135.0,-90.0,-45.0,0.0,45.0,90.0,135.0,180.0]:
		for pitch in [-60.0,-30.0,0.0,45.0,70.0]:
			for height in [-0.5,0.0,0.5]:
				for zoom in [0.6,1.0,1.6]:
					cases += 1
					var label := str([yaw,pitch,height,zoom])
					var basis: Basis = View.orbit_basis(yaw,pitch,height)
					camera.global_transform = Transform3D(basis,Vector3(0,0.8,0)+basis.z*3.6)
					camera.size = View.orthographic_size(2.2,zoom)
					check(absf(basis.x.dot(Vector3.UP)) < 0.000001 and basis.y.dot(Vector3.UP)>0 and absf(basis.determinant()-1)<0.000001,"no roll/right-handed basis "+label)
					for pixel in [Vector2.ZERO,Vector2(680,760),Vector2(340,380),Vector2(200,650),Vector2(-25,800)]:
						var point: Vector3 = View.screen_to_world_at_depth(camera,pixel,3.6)
						var error := camera.unproject_position(point).distance_to(pixel)
						max_pixel_error = maxf(max_pixel_error,error)
						check(error < 0.001 and absf(View.depth(camera,point)-3.6)<0.00001,"pixel/depth round trip "+label)
					var seat: Vector3 = View.screen_to_world_at_depth(camera,Vector2(350,500),3.6)
					var offset := Basis(Vector3.UP,0.37)*Vector3(0.08,0.68,0.11)
					var wanted_base := seat-offset
					var base_pixel := camera.unproject_position(wanted_base)
					var base_depth: float = View.base_depth_for_offset(camera,seat,offset)
					var base: Vector3 = View.screen_to_world_at_depth(camera,base_pixel,base_depth)
					max_contact_error = maxf(max_contact_error,(base+offset).distance_to(seat))
					check((base+offset).distance_to(seat)<0.00001,"shared seat coincidence at arbitrary orbit "+label)
					var shifted: Vector3 = seat+View.translation_to_depth(camera,seat,4.1)
					check(camera.unproject_position(shifted).distance_to(Vector2(350,500))<0.001 and absf(View.depth(camera,shifted)-4.1)<0.00001,"depth translation preserves screen pixel "+label)
					var delta := Vector2(17,-9)
					var moved: Vector3 = seat+View.screen_delta_to_world(camera,delta)
					check(camera.unproject_position(moved).distance_to(Vector2(350,500)+delta)<0.001,"screen movement uses rotated camera plane "+label)
					var axes: Dictionary = View.projection_axes(camera)
					var ppm: float = axes.screen_pixels_per_metre
					check(absf(ppm-760.0/camera.size)<0.001,"orthographic zoom preserves actual engine aspect semantics "+label)
					check(Vector2(axes.world_x).distance_to(Vector2(basis.x.x,-basis.y.x)*ppm)<0.001 and Vector2(axes.world_y).distance_to(Vector2(basis.x.y,-basis.y.y)*ppm)<0.001,"world projection derivatives "+label)
					for axis in [Vector3.UP,Vector3.BACK]:
						var solved: Dictionary = View.solve_screen_on_plane(camera,Vector2(350,500),seat,axis)
						var parallel := absf((-basis.z).dot(axis)) < View.EPSILON
						check((not solved.ok and solved.reason == "parallel") if parallel else (solved.ok and Vector3(solved.point).distance_to(seat)<0.00001),"physical plane explicit degeneracy "+label)
	camera.global_transform = Transform3D(Basis.IDENTITY,Vector3(0,0,3.6))
	check(not View.solve_screen_at_world_y(camera,Vector2(340,380),0).ok,"level camera world-Y degeneracy")
	camera.basis = View.orbit_basis(90,0)
	check(not View.solve_screen_at_world_z(camera,Vector2(340,380),0).ok,"side camera world-Z degeneracy")
	check(not View.screen_to_world_at_depth(camera,Vector2(NAN,0),2).is_finite(),"invalid pixel fails explicitly")
	check(not View.screen_to_world_at_depth(camera,Vector2.ZERO,-2).is_finite(),"invalid depth fails explicitly")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	check(View.screen_to_world_at_depth(camera,Vector2.ZERO,2).is_finite(),"perspective supported by explicit-depth contract")
	var report := {"scope":"Actual Godot orthographic projection680×760, pure geometry; no main/runtime integration or Windows rendering claim.","cases":cases,"checks":checks,"failures":failures,"max_pixel_error":max_pixel_error,"max_contact_error_m":max_contact_error,"module_sha256":FileAccess.get_sha256("res://scripts/desktop_view.gd")}
	var args := OS.get_cmdline_user_args()
	if "--output" in args:
		FileAccess.open(args[args.find("--output")+1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
