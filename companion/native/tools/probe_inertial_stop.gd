extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var failures := 0
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var motion := MotionPlayer.new()
		root.add_child(motion)
		motion.avatar = avatar
		motion.set_process(false)
		motion.idle_enabled = false
		motion.gaze_enabled = false
		motion.play_motion_dict({"name":"controlled_head","duration":4.0,"tracks":[{"bone":"head","keys":[{"time":0.0,"x":0.0,"y":0.0,"z":0.0},{"time":4.0,"x":0.0,"y":40.0,"z":0.0}]}]})
		var head: int = avatar.bone_index.head
		var before := Quaternion.IDENTITY
		var current := Quaternion.IDENTITY
		for frame in 120:
			before = avatar.skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion()
			motion._process(1.0/60)
			current = avatar.skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion()
		var outgoing := angular_step(before,current)*60
		motion.stop_gesture()
		motion._process(1.0/60)
		var after := avatar.skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion()
		var incoming := angular_step(current,after)*60
		var ratio := incoming.length()/maxf(outgoing.length(),0.0001)
		print("INERTIAL ",character," before_deg_s=",rad_to_deg(outgoing.length())," after_deg_s=",rad_to_deg(incoming.length())," speed_ratio=",ratio," directional_dot=",outgoing.normalized().dot(incoming.normalized()))
		if outgoing.length() < deg_to_rad(5) or ratio < 0.75 or ratio > 1.2 or outgoing.dot(incoming) <= 0:
			failures += 1
		motion.free()
		avatar.free()
	print("INERTIAL_FAILURES=",failures)
	quit(1 if failures else 0)
func angular_step(a: Quaternion,b: Quaternion) -> Vector3:
	var q := (a.inverse()*b).normalized()
	if q.w < 0: q = Quaternion(-q.x,-q.y,-q.z,-q.w)
	var v := Vector3(q.x,q.y,q.z)
	return v.normalized()*2*atan2(v.length(),q.w) if v.length() > 0.0000001 else Vector3.ZERO
