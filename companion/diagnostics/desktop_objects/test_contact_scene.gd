extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var script = load("res://scripts/desktop_object_contact_scene.gd")
	check(script != null, "contact scene script parses")
	if script == null:
		quit(1)
		return
	var scene = script.new()
	root.add_child(scene)
	for type in ["chair", "sofa", "computer"]:
		check(scene.configure(type), type+" actual premium GLB loads")
		check(scene.get_child_count() == 1, type+" owns one geometry container after reconfigure")
		check(scene.has_socket("seat"), type+" supplies seat")
		check(scene.geometry_points_local().size() > 100, type+" contains actual mesh vertices")
		var initial: Vector3 = scene.socket_local("seat")
		var expected_yaw := 35.0 if type == "computer" else 0.0
		check(is_equal_approx(scene.recommended_yaw_degrees, expected_yaw), type+" presentation yaw")
		scene.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(expected_yaw)).scaled(Vector3.ONE*1.3), Vector3(-2.0,0.4,1.0))
		check(scene.socket_world("seat").distance_to(scene.transform*initial) < 0.00001, type+" socket follows host translation scale and yaw")
		var bounds: AABB = scene.get_world_bounds().grow(0.0001)
		var all_inside := true
		for point in scene.geometry_points_local():
			all_inside = all_inside and bounds.has_point(scene.global_transform*point)
		check(all_inside, type+" world bounds contain every transformed vertex")
		if type == "computer":
			check(initial.distance_to(Vector3(0,.48,.52)) < 0.00001, "computer seat follows rotated chair")
			check(scene.socket_local("keyboard_left").x < scene.socket_local("keyboard_right").x, "keyboard left right order")
			check(scene.socket_local("inspect").z < scene.socket_local("use").z and scene.socket_local("use").z < initial.z, "monitor keyboard user depth order")
			check(scene.facing_direction_world().distance_to((scene.global_basis*Vector3.FORWARD).normalized()) < 0.00001, "user faces monitor after yaw")
			check(scene.get_local_bounds().end.z > .90, "bounds include chair behind desk")
		scene.transform = Transform3D.IDENTITY
	check(not scene.configure("unknown"), "unsupported type rejected")
	check(not scene.loaded and scene.get_child_count() == 0 and scene.socket_catalogue().is_empty(), "failed configure clears stale state")
	check(not scene.error.is_empty(), "failure explanation")
	scene.clear()
	scene.clear()
	check(scene.get_child_count() == 0, "clear idempotent")
	scene.free()
	print("Contact scene: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
