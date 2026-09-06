extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var failed := false
	for name in ["pixiv-test", "quaternius-dance"]:
		var clip := VrmaClip.new()
		if not clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/" + name + ".vrma")):
			push_error(clip.error)
			failed = true
			continue
		print("VRMA ",name," duration=",clip.duration," tracks=",clip.tracks.size())
		for t in [0.0,clip.duration*0.5,clip.duration]:
			for q: Quaternion in clip.sample(t).values():
				if not q.is_finite() or absf(q.length()-1.0) > 0.001:
					failed = true
		for character in ["cheval-grand", "rice-shower", "eishin-flash"]:
			var avatar := VrmAvatar.new()
			root.add_child(avatar)
			avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + character + ".vrm"))
			avatar.apply_pose({})
			avatar.apply_normalized_rotations(clip.sample(clip.duration*0.5),1.0)
			for i in avatar.skeleton.get_bone_count():
				if not avatar.skeleton.get_bone_global_pose(i).is_finite():
					failed = true
			avatar.free()
	print("VRMA_FAILURE=",failed)
	quit(1 if failed else 0)
