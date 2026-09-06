extends SceneTree
## Raw retargeted FK screening, before contact/gait corrections; not acceptance.
func _init() -> void: call_deferred("run")
func run() -> void:
	var avatar:=VrmAvatar.new()
	root.add_child(avatar)
	avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/mambo.vrm"))
	var directory:=ProjectSettings.globalize_path("res://../assets/research/playful-walk/candidates")
	var paths: Array[String]=[ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma")]
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".vrma"):paths.append(directory.path_join(file))
	var rows: Array=[]
	for path in paths:
		var clip:=VrmaClip.new()
		if not clip.load_file(path):continue
		var low:={}
		var high:={}
		var hip_roll: Array[float]=[]
		var head_angles: Array[Vector3]=[]
		for frame in 121:
			avatar.reset_pose()
			avatar.apply_normalized_rotations(clip.sample(clip.duration*frame/120.0),1)
			var hips:=avatar.bone_global_position("hips")
			for bone in ["leftFoot","rightFoot","leftHand","rightHand"]:
				var point:=avatar.bone_global_position(bone)-hips
				low[bone]=Vector3(low.get(bone,point)).min(point)
				high[bone]=Vector3(high.get(bone,point)).max(point)
			var sk:=avatar.skeleton
			for bone in ["hips","head"]:
				var id:int=avatar.bone_index[bone]
				var relative:Basis=sk.get_bone_global_pose(id).basis*sk.get_bone_global_rest(id).basis.inverse()
				var angles:=relative.get_euler()*180/PI
				if bone=="hips":hip_roll.append(angles.z)
				else:head_angles.append(angles)
		var row:={"name":path.get_file().get_basename(),"duration":clip.duration,"sha256":FileAccess.get_sha256(path),"foot_span_m":{},"hand_span_m":{},"hip_roll_range_deg":hip_roll.max()-hip_roll.min()}
		for bone in ["leftFoot","rightFoot","leftHand","rightHand"]:
			var span:Vector3=high[bone]-low[bone]
			row["foot_span_m" if "Foot" in bone else "hand_span_m"][bone]=[span.x,span.y,span.z]
		var lo:=head_angles[0]
		var hi:=lo
		for angle in head_angles:lo=lo.min(angle);hi=hi.max(angle)
		row.head_euler_range_deg=[hi.x-lo.x,hi.y-lo.y,hi.z-lo.z]
		rows.append(row)
		print(row.name," duration=",row.duration," foot=",row.foot_span_m," hipsroll=",row.hip_roll_range_deg," head=",row.head_euler_range_deg)
	var output:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/meme_motion/playful-screening.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope":"Raw retargeted FK screening on Mambo; before runtime contact constraints","rows":rows},"  ")+"\n")
	output.close()
	avatar.free()
	quit()
