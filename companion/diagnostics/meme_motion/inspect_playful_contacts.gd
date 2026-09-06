extends SceneTree
## Unsolved source motion samples for the generic authored-gait implementation.
func _init() -> void: call_deferred("run")
func vec(v:Vector3)->Array:return [v.x,v.y,v.z]
func run() -> void:
	var avatar:=VrmAvatar.new()
	root.add_child(avatar)
	avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/mambo.vrm"))
	var sk:=avatar.skeleton
	var height:=sk.get_bone_global_rest(avatar.bone_index.hips).origin.y
	var rows: Array=[]
	for name in ["uma_homewalk03_loop","uma_walkunique01_loop","uma_walkunique09_loop","uma_walkunique10_loop","uma_skip01_loop"]:
		var clip:=VrmaClip.new()
		clip.load_file(ProjectSettings.globalize_path("res://../assets/research/playful-walk/candidates/"+name+".vrma"))
		var samples: Array=[]
		for frame in 241:
			var time:=clip.duration*frame/240.0
			avatar.reset_pose()
			avatar.apply_normalized_rotations(clip.sample(time),1)
			avatar.set_hips_offset(clip.sample_hips_offset(time)*height)
			var points:={}
			for bone in ["hips","leftFoot","rightFoot","leftLowerLeg","rightLowerLeg","head"]:points[bone]=vec(avatar.bone_global_position(bone))
			samples.append({"time":time,"phase":frame/240.0,"points":points,"hips_offset":vec(clip.sample_hips_offset(time)*height)})
		rows.append({"name":name,"duration":clip.duration,"hips_rest_height_m":height,"samples":samples})
	var output:=FileAccess.open(ProjectSettings.globalize_path("res://../assets/research/playful-walk/contact-traces.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(rows))
	output.close()
	avatar.free()
	quit()
