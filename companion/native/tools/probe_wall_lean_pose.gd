extends SceneTree
const Lean = preload("../scripts/wall_lean_pose.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:failures+=1;push_error(label)
func _init() -> void:call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<2:quit(2);return
	var avatar := VrmAvatar.new();root.add_child(avatar)
	if not avatar.load_from_file(args[0]):quit(2);return
	avatar.scale=Vector3.ONE*.6
	var idle := VrmaClip.new()
	if not idle.load_file(args[1]):quit(2);return
	var rows := []
	for sign in [-1.0,1.0]:
		avatar.reset_pose();avatar.apply_normalized_rotations(idle.sample(0.0),1.0)
		var chest := avatar.bone_global_position("chest")
		var point := chest+Vector3(sign*.14,0,0)
		var normal := Vector3(-sign,0,0)
		var lean = Lean.new();lean.configure(avatar,point,normal)
		var max_feet := 0.0
		var min_clearance := INF
		var torso_shift := 0.0
		var reachable := false
		for frame in 91:
			avatar.reset_pose();avatar.apply_normalized_rotations(idle.sample(frame/60.0),1.0)
			var before := {}
			for bone in ["hips","leftFoot","rightFoot"]:before[bone]=avatar.bone_global_position(bone)
			var old_chest := avatar.bone_global_position("chest")
			lean.apply(avatar,MotionPlayer._blend_weight(frame/60.0/.55))
			var side := "left" if avatar.to_local(point).x>=0 else "right"
			reachable=avatar.apply_hand_contact(side,point)
			for bone in before:max_feet=maxf(max_feet,Vector3(before[bone]).distance_to(avatar.bone_global_position(bone)))
			min_clearance=minf(min_clearance,float(lean.diagnostics.get("clearance_m",-INF)))
			torso_shift=maxf(torso_shift,old_chest.distance_to(avatar.bone_global_position("chest")))
		check(max_feet<0.00001,"hips and feet unchanged")
		check(torso_shift>0.001,"torso visibly offsets toward wall")
		check(reachable,"hand remains reachable after lean")
		check(min_clearance>=0.0,"torso head proxy stays outside wall")
		rows.append({"side":sign,"max_foot_hip_shift_m":max_feet,"torso_shift_m":torso_shift,"minimum_capsule_clearance_m":min_clearance,"reachable":reachable,"diagnostics":lean.diagnostics})
		avatar.reset_pose();avatar.apply_normalized_rotations(idle.sample(0),1)
		var tight = Lean.new();tight.configure(avatar,chest,normal);tight.apply(avatar,1)
		check(float(tight.diagnostics.get("amplitude",1))==0.0,"preexisting tight wall never adds penetration")
	print(JSON.stringify({"failed":failures,"frames_per_side":91,"rows":rows,"scope":"real avatar authored idle plus additive layer and IK; no native compositor"}))
	avatar.free();quit(1 if failures else 0)
