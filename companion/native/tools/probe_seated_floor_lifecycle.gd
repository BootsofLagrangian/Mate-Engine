extends SceneTree
var failures:=0
func _init():call_deferred("run")
func run():
	var clip:=VrmaClip.new()
	clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar:=VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		avatar.set_seated_floor(.428)
		var secondary:Node=avatar.seated_floor.secondary
		var before:=avatar.seated_floor.snapshot_springs()
		avatar.calibrate_seated_pose(clip.sample(0))
		for record in before.records:
			if record[0].verlets.size()!=record[1].size():failures+=1
			for entry in record[1]:
				if entry[0].length!=entry[1] or entry[0].current_tail!=entry[2] or entry[0].prev_tail!=entry[3]: failures+=1
		if avatar.seated_floor.active or not avatar.seated_floor._colliders.is_empty():failures+=1
		avatar.apply_pose({})
		avatar.apply_normalized_rotations(clip.sample(0),1)
		avatar.seated_floor.set_active(true)
		avatar.seated_floor.solve_legs()
		avatar._secondary_pose_cache[0]=[Vector3.ZERO,Quaternion.IDENTITY,Vector3.ONE]
		avatar.clear_seated_floor()
		if not avatar._secondary_pose_cache.is_empty() or avatar._secondary_pose_samples!=0 or avatar._seated_refresh_pending: failures+=1
		for record in before.records:
			if record[0].verlets.size()!=record[1].size():failures+=1
			for entry in record[1]:
				if entry[0].length!=entry[1]: failures+=1
		for state in secondary.spring_bones_internal:
			for collider in state.colliders:
				if collider is SeatedFloorConstraint.FloorCollider:failures+=1
		if not avatar.seated_geometry.is_empty():failures+=1
		avatar.set_seated_floor(.48)
		avatar.calibrate_seated_pose(clip.sample(0))
		avatar.seated_floor.set_active(true)
		avatar.set_seated_floor(.5)
		if avatar.seated_floor.active or not avatar.seated_geometry.is_empty() or not avatar._secondary_pose_cache.is_empty():failures+=1
		avatar.clear_model()
		if avatar.seated_floor.active or is_finite(avatar.seated_floor.clearance) or not avatar._secondary_pose_cache.is_empty():failures+=1
		print("FLOOR_LIFECYCLE ",name," failures=",failures)
		avatar.free()
	print("FLOOR_LIFECYCLE_FAILURES=",failures)
	quit(1 if failures else 0)
