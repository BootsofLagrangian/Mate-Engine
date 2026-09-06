extends SceneTree
## Run with native project --headless --script absolute/path/probe_head.gd -- [out-dir] [model-path]
## Fixed-delta deterministic pose measurements, NOT a wall-clock/render benchmark.
var out_dir := "/tmp/head-motion"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var model_path := ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm")
	if args.size() > 1: model_path = args[1]
	var avatar := VrmAvatar.new()
	root.add_child(avatar)
	if not avatar.load_from_file(model_path):
		quit(1)
		return
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	var members: Array = []
	inspect_nodes(avatar, members)
	var results: Array = []
	for fps in [30, 60]:
		for scenario in ["frozen", "idle_stable_gaze", "idle_free_gaze", "gaze_step", "wave", "nod", "bow", "wave_idle", "nod_idle", "bow_idle", "rapid_gestures"]:
			avatar.skeleton.reset_bone_poses()
			var motion := MotionPlayer.new()
			motion.avatar = avatar
			root.add_child(motion)
			motion.set_process(false)
			motion.ik_enabled = false
			motion._noise.seed = 2251
			motion.bank = MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
			motion.idle_enabled = scenario in ["idle_stable_gaze", "idle_free_gaze", "wave_idle", "nod_idle", "bow_idle"]
			motion.gaze_enabled = scenario in ["idle_stable_gaze", "idle_free_gaze", "gaze_step"]
			motion.gaze_has_target = scenario != "idle_free_gaze"
			var csv := FileAccess.open(out_dir.path_join("%s_%s_%dfps.csv" % [model_path.get_file().get_basename(), scenario, fps]), FileAccess.WRITE)
			csv.store_line("time,head_qx,head_qy,head_qz,head_qw,head_step_deg,head_speed_deg_s,head_accel_deg_s2,neck_step_deg,gesture")
			var prev := Quaternion.IDENTITY
			var prev_neck := Quaternion.IDENTITY
			var previous_velocity := Vector3.ZERO
			var peak_step := 0.0
			var peak_speed := 0.0
			var peak_accel := 0.0
			var speeds: Array[float] = []
			var accelerations: Array[float] = []
			var dt: float = 1.0 / fps
			for i in range(20 * fps):
				if i == fps * 2 and scenario in ["wave", "nod", "bow", "wave_idle", "nod_idle", "bow_idle"]: motion.play_gesture(scenario.trim_suffix("_idle"))
				if scenario == "gaze_step" and i == fps * 5: motion.gaze_target = Vector2(0.95, 0.75)
				if scenario == "rapid_gestures" and i % int(fps * 0.9) == 0: motion.play_gesture(["wave", "nod", "bow"][int(i / int(fps * 0.9)) % 3])
				motion._process(dt)
				var q: Quaternion = avatar.skeleton.get_bone_global_pose(avatar.bone_index["head"]).basis.orthonormalized().get_rotation_quaternion().normalized()
				var n: Quaternion = avatar.skeleton.get_bone_global_pose(avatar.bone_index["neck"]).basis.orthonormalized().get_rotation_quaternion().normalized()
				var dq := (q * prev.inverse()).normalized()
				if dq.w < 0: dq = -dq
				# atan2 vector norm avoids float32 acos(dot) quantization for tiny steps.
				var v := Vector3(dq.x, dq.y, dq.z)
				var angle := 2.0 * atan2(v.length(), dq.w)
				var velocity := v.normalized() * rad_to_deg(angle) / dt
				var step := rad_to_deg(angle)
				var accel := (velocity - previous_velocity).length() / dt
				var dn := (n * prev_neck.inverse()).normalized()
				var neck_step := rad_to_deg(2.0 * atan2(Vector3(dn.x,dn.y,dn.z).length(), absf(dn.w)))
				if i > fps:
					peak_step = maxf(peak_step, step)
					peak_speed = maxf(peak_speed, velocity.length())
					peak_accel = maxf(peak_accel, accel)
					speeds.append(velocity.length())
					accelerations.append(accel)
				csv.store_line("%.6f,%.9f,%.9f,%.9f,%.9f,%.8f,%.8f,%.8f,%.8f,%s" % [(i+1)*dt,q.x,q.y,q.z,q.w,step,velocity.length(),accel,neck_step,motion.current_gesture()])
				prev = q
				prev_neck = n
				previous_velocity = velocity
			csv.close()
			speeds.sort()
			accelerations.sort()
			results.append({"scenario":scenario,"fps":fps,"peak_step_deg":peak_step,"peak_speed_deg_s":peak_speed,"p95_speed_deg_s":speeds[int(speeds.size()*0.95)],"peak_accel_deg_s2":peak_accel,"p95_accel_deg_s2":accelerations[int(accelerations.size()*0.95)]})
			motion.free()
	var report := {"model":model_path,"scope":"20s deterministic fixed-delta; first 1s excluded from summaries; head GLOBAL quaternion includes torso; secondary disabled; IK disabled", "secondary_and_constraints":members,"results":results}
	var report_file := FileAccess.open(out_dir.path_join(model_path.get_file().get_basename()+"_summary.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
func inspect_nodes(node: Node, out: Array) -> void:
	if node is VRMSecondary:
		var joints: Array = []
		for spring in node.spring_bones:
			for joint in spring.joint_nodes: joints.append(str(joint))
		out.append({"node":str(node.get_path()),"kind":"secondary","joint_names":joints})
	if node is BoneNodeConstraintApplier:
		out.append({"node":str(node.get_path()),"kind":"constraints","count":node.constraints.size()})
	for child in node.get_children(): inspect_nodes(child,out)
