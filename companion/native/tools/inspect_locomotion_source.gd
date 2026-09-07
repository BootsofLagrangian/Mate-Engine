extends SceneTree
## Raw full-source FK including authored hips, without gait or contact correction.
## Usage: -- avatar.vrm output.json clip.vrma [clip.vrma ...]
func _init() -> void: call_deferred("run")
func vec(value: Vector3) -> Array: return [value.x,value.y,value.z]
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3: push_error("avatar, output and clips required"); quit(2); return
	var avatar := VrmAvatar.new()
	root.add_child(avatar)
	if not avatar.load_from_file(args[0]): push_error("avatar load failed"); quit(2); return
	var skeleton := avatar.skeleton
	var height := skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
	var leg := skeleton.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(skeleton.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
	var rows: Array = []
	for path in args.slice(2):
		var clip := VrmaClip.new()
		if not clip.load_file(path): push_error("clip load failed: "+path); quit(2); return
		var samples: Array = []
		for frame in 481:
			var phase := frame/480.0
			var time := clip.duration*phase
			avatar.reset_pose()
			avatar.apply_normalized_rotations(clip.sample(time),1.0)
			avatar.set_hips_offset(clip.sample_hips_offset(time)*height)
			var points := {}
			for bone in ["hips","leftFoot","rightFoot","leftToes","rightToes","leftLowerLeg","rightLowerLeg","head"]:
				if avatar.bone_index.has(bone): points[bone]=vec(avatar.bone_global_position(bone))
			samples.append({"phase":phase,"time":time,"points":points,"hips_offset":vec(clip.sample_hips_offset(time)*height)})
		rows.append({"name":path.get_file().get_basename(),"path":path,"sha256":FileAccess.get_sha256(path),"duration":clip.duration,"samples":samples})
	var report := {"scope":"Raw retargeted FK on supplied rig; full authored hips, no gait/IK or runtime acceptance","avatar":args[0],"avatar_sha256":FileAccess.get_sha256(args[0]),"rest_leg_length_m":leg,"hips_rest_height_m":height,"samples_per_period":480,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"rows":rows}
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	if file==null: push_error("output open failed"); quit(2); return
	file.store_string(JSON.stringify(report));file.close()
	avatar.free()
	quit()
