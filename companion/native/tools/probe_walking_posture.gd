extends SceneTree
## Static source-pose ablation: no gaze, idle, IK, camera pitch or window motion.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var output := "/tmp/walking-posture"
	var args := OS.get_cmdline_user_args()
	var clip_names := PackedStringArray(["walk","walk_formal","uma_homewalk_filtered","uma_homewalk_up_filtered","uma_homewalk_down_filtered","walk_fwd","walk_short_fwd"])
	if "--clips" in args: clip_names = args[args.find("--clips")+1].split(",")
	if "--output" in args: output = args[args.find("--output")+1]
	DirAccess.make_dir_recursive_absolute(output)
	var rows := []
	for model in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		assert(avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+model+".vrm")))
		for name in clip_names:
			var clip := VrmaClip.new()
			assert(clip.load_file(clip_path(name)))
			for ablation in ["source","without_head_neck","without_torso","head_neck_only","rest"]:
				var samples := []
				for frame in 120:
					avatar.apply_pose({})
					var pose: Dictionary = clip.sample(clip.duration*frame/120.0)
					for bone in pose.keys():
						if ablation == "rest" or (ablation == "without_head_neck" and bone in ["head","neck"]) or (ablation == "without_torso" and bone in ["hips","spine","chest","upperChest"]) or (ablation == "head_neck_only" and bone not in ["head","neck"]): pose.erase(bone)
					avatar.apply_normalized_rotations(pose,1.0)
					var offset: Vector3 = clip.sample_hips_offset(clip.duration*frame/120.0)
					var sample := {"phase":frame/120.0,"source_hips_offset":[offset.x,offset.y,offset.z]}
					for bone in ["hips","spine","chest","upperChest","neck","head","leftUpperArm","rightUpperArm"]:
						if not avatar.bone_index.has(bone): continue
						var index: int = avatar.bone_index[bone]
						var relative := avatar.skeleton.get_bone_global_pose(index).basis*avatar.skeleton.get_bone_global_rest(index).basis.inverse()
						var forward := (relative*Vector3(0,0,1)).normalized()
						sample[bone+"_down_pitch_deg"] = rad_to_deg(atan2(-forward.y,Vector2(forward.x,forward.z).length()))
						sample[bone+"_yaw_deg"] = rad_to_deg(atan2(forward.x,forward.z))
						if bone.ends_with("UpperArm"):
							var lower: String = bone.replace("UpperArm","LowerArm")
							var arm := avatar.bone_global_position(lower)-avatar.bone_global_position(bone)
							sample[bone+"_elevation_deg"] = rad_to_deg(atan2(arm.y,Vector2(arm.x,arm.z).length()))
							var q: Quaternion = avatar.skeleton.get_bone_pose_rotation(index)
							sample[bone+"_local_q"] = [q.x,q.y,q.z,q.w]
					samples.append(sample)
				rows.append({"model":model,"clip":name,"ablation":ablation,"samples":samples})
		avatar.free()
	var hashes := {}
	for name in ["vrma_clip.gd","vrm_avatar.gd","motion_player.gd","living_behavior.gd"]: hashes[name] = FileAccess.get_sha256("res://scripts/"+name)
	for name in clip_names: hashes[name] = FileAccess.get_sha256(clip_path(name))
	var f := FileAccess.open(output.path_join("source-ablation.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"Rest-relative humanoid forward +Z elevation; positive pitch is downward. Static normalized clip rotations only,120uniformphases each; no gaze or procedural/IK layer.","source_sha256":hashes,"rows":rows},"\t"))
	f.close()
	print("WALKING_POSTURE rows=",rows.size())
	quit()

func clip_path(name: String) -> String:
	return ProjectSettings.globalize_path("res://../assets/"+("motions/" if name in ["walk","walk_formal"] else "research/walking-candidates/")+name+".vrma")
