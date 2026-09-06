extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var clip:=VrmaClip.new()
	clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar:=VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		avatar.apply_pose({"head":Vector3(10,4,0)})
		var saved:=[]
		for idx in avatar.skeleton.get_bone_count(): saved.append(avatar.skeleton.get_bone_pose(idx))
		var previous:Vector3=avatar.contact_anchors().sit
		var geometry:=avatar.calibrate_seated_pose(clip.sample(0))
		for idx in saved.size():
			if not saved[idx].is_equal_approx(avatar.skeleton.get_bone_pose(idx)): failures+=1
		if geometry.is_empty() or geometry.diagnostics.patch_vertices<10 or geometry.diagnostics.bind_rest_max_error_m>0.001: failures+=1
		for size in [0.6,1.0]:
			for yaw in [0.0,PI/2,-PI/2]:
				avatar.transform=Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*size),Vector3(0.3,0.2,-0.1))
				if avatar.contact_anchors().sit.distance_to(avatar.global_transform*Vector3(geometry.anchor))>0.00001: failures+=1
		avatar.transform=Transform3D.IDENTITY
		var repeated:=avatar.calibrate_seated_pose(clip.sample(0))
		if repeated.anchor.distance_to(geometry.anchor)>0.00001 or not repeated.bounds.is_equal_approx(geometry.bounds): failures+=1
		print("SEATED ",name," previous_anchor=",previous," geometry=",geometry)
		avatar.free()
	print("SEATED_FAILURES=",failures)
	quit(1 if failures else 0)
