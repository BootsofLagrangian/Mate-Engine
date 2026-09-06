extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var failures := 0
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		print("SOLE ",name," calibration=",avatar.sole_calibration," mesh_min_y=",avatar.compute_aabb().position.y," anchor=",avatar.contact_anchors().foot)
		if absf(avatar.contact_anchors().foot.y-avatar.compute_aabb().position.y) > 0.00001:
			failures += 1
		var identity_points := avatar.sole_contact_points()
		if identity_points.is_empty():
			failures += 1
		for scale_value in [0.35,0.6,1.0,1.25]:
			for yaw in [-82.0,0.0,82.0]:
				avatar.transform = Transform3D(Basis(Vector3.UP,deg_to_rad(yaw)).scaled(Vector3.ONE*scale_value),Vector3.ZERO)
				var points := avatar.sole_contact_points()
				for i in points.size():
					if points[i].distance_to(avatar.transform*identity_points[i]) > 0.0001:
						failures += 1
		avatar.free()
	print("SOLE_FAILURES=",failures)
	quit(1 if failures else 0)
