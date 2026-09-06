extends SceneTree
var failures:=0
func _init() -> void:call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var a:=VrmAvatar.new()
		root.add_child(a)
		a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var p:=MotionPlayer.new()
		root.add_child(p)
		p.set_process(false)
		p.avatar=a
		p.load_vrma("sit_enter",ProjectSettings.globalize_path("res://../assets/motions/sit_enter.vrma"))
		p.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
		p.register_seated_transition("enter","sit_enter")
		if p.play_gesture("sit_enter") or p.play_vrma("sit_enter") or p.play_upper_body_gesture("sit_enter"):failures+=1
		p._process(1.0/60)
		var seen_keys:=[]
		for pose in [{},{"rightUpperArm":Vector3(0,0,-100)}]:
			a.apply_pose(pose)
			var before:=[]
			for idx in a.skeleton.get_bone_count():before.append(a.skeleton.get_bone_pose(idx))
			if not p.start_seated_transition("enter",Vector3(0,-0.3,-0.3)):failures+=1
			for idx in a.skeleton.get_bone_count():
				if a.skeleton.get_bone_pose(idx)!=before[idx]:failures+=1
			seen_keys.append(p.seated_transition._bounds_cache.keys().duplicate())
			p.cancel_seated_transition()
		if seen_keys[1].size()<=seen_keys[0].size():failures+=1
		# A failed fresh measurement must not return the preceding cached box.
		p.seated_transition._bounds_cache.clear()
		var meshes:=[]
		a._collect_meshes(a.model,meshes)
		for mesh in meshes:mesh.hide()
		if p.start_seated_transition("enter",Vector3(0,-0.3,-0.3)):failures+=1
		if p.seated_transition.active:failures+=1
		p.free()
		a.free()
	print("SEATED_LIFECYCLE_FAILURES=",failures)
	quit(1 if failures else 0)
