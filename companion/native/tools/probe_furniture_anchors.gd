extends SceneTree
## Real furniture geometry, no desktop/compositor or manipulation-motion claim.
var failures := 0
var checks := 0
func _init() -> void: call_deferred("run")
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(label, " ", ok)
func run() -> void:
	for kind in ["chair", "sofa", "computer"]:
		var scene := DesktopObjectContactScene.new()
		root.add_child(scene)
		verify(scene.configure(kind), kind+" loads with additive anchor metadata")
		if not scene.loaded: scene.free(); continue
		var anchors := scene.interaction_anchor_catalogue(false)
		verify(anchors.has("seat") and anchors.has("approach") and anchors.has("inspect"), kind+" standard anchors")
		for name in anchors:
			verify(Vector3(anchors[name].position).is_equal_approx(scene.socket_local(anchors[name].socket)), kind+" socket equivalence "+name)
		if kind == "chair":
			for grip in ["grip_left","grip_right"]:
				var distance := INF
				for point in scene.geometry_points_local():
					distance = minf(distance,point.distance_to(anchors[grip].position))
				verify(distance < .025 and Vector3(anchors[grip].position).y > scene.get_local_bounds().end.y-.025,"top grip remains within 2.5cm of actual upper rim")
			verify(Vector3(anchors.manipulate_approach.position).z < scene.get_local_bounds().position.z-.10,"actor reference outside chair rear bounds")
		scene.transform = Transform3D(Basis(Vector3.UP,.73).scaled(Vector3.ONE*.6),Vector3(2,0,-3))
		var world := scene.interaction_anchor_catalogue()
		for name in world:
			verify(Vector3(world[name].position).is_equal_approx(scene.global_transform*Vector3(anchors[name].position)) and is_equal_approx(Vector3(world[name].facing).length(),1.0) and absf(Vector3(world[name].facing).dot(Vector3(world[name].up)))<.00001, kind+" transformed pose "+name)
		if kind == "computer":
			var keyboard: Vector3 = world.keyboard_left.position
			verify(scene.set_seat_setup(.6,90) and scene.set_seat_scale(.8),"articulated setup")
			world = scene.interaction_anchor_catalogue()
			verify(Vector3(world.grip_left.position).is_equal_approx(scene.seat_node().global_transform*Vector3(.14515,1.015,-.225)),"grip follows actual chair mesh translation rotation scale")
			verify(Vector3(world.manipulate_approach.position).is_equal_approx(scene.seat_node().global_transform*Vector3(0,0,-.50)),"actor reference follows articulated chair")
			verify(Vector3(world.keyboard_left.position).is_equal_approx(keyboard),"keyboard does not follow chair")
			verify(Vector3(world.grip_left.facing).is_equal_approx((scene.seat_node().global_basis*Vector3.BACK).normalized()),"grip facing follows articulation")
			verify(is_zero_approx(float(scene.manipulation_contract().translation.limits[0])) and is_equal_approx(float(scene.manipulation_contract().translation.limits[1]),float(scene.seat_setup().capability.max_pullout_m)),"translation limits retain physical chair capability")
		# Legacy assets with no new metadata remain valid, bad references rejected.
		verify(scene._read_interaction_anchors({},{}),"absent metadata backwards compatible")
		var invalid := {"interaction_anchors":{"bad":{"socket":"missing","frame":"object","facing":[0,0,1],"up":[0,1,0],"role":"hand","verbs":[],"execution":"reference_only"}}}
		verify(not scene._read_interaction_anchors(invalid,{}),"missing socket rejected")
		invalid.interaction_anchors.bad.socket = "seat"
		invalid.interaction_anchors.bad.up = [0,0,1]
		verify(not scene._read_interaction_anchors(invalid,{}),"degenerate orientation rejected")
		scene.clear()
		verify(scene.interaction_anchor_catalogue().is_empty(),"clear removes anchor state")
		scene.free()
	print("furniture anchors: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
