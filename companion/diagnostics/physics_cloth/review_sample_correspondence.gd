extends SceneTree
const Samples=preload("res://tools/garment_quality_samples.gd")
func _init(): call_deferred("run")
func run():
	var at_origin := OS.get_cmdline_user_args().has("--at-origin")
	var rows:=[]
	for character in ["cheval-grand","rice-shower","eishin-flash","mambo","hachimi"]:
		var avatars:=[]
		var samplers:=[]
		for side in 2:
			var a:=VrmAvatar.new()
			root.add_child(a)
			a.position.x=0.0 if at_origin else (-.56 if side==0 else .56)
			a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
			a.spring_contacts.secondary.internal_modifier_node.active=false
			a.skeleton.reset_bone_poses()
			a.apply_pose({})
			avatars.append(a)
			var sampler:=Samples.new()
			sampler.configure(a)
			samplers.append(sampler)
		var mismatch:=[]
		for i in samplers[0].surfaces.size():
			var a:Dictionary=samplers[0].surfaces[i]
			var b:Dictionary=samplers[1].surfaces[i]
			for field in ["ids","vertices","joints","weights","selected","triangles"]:
				if a[field]!=b[field]: mismatch.append({"surface":i,"field":field})
		var sa:Dictionary=samplers[0].sample(avatars[0])
		var sb:Dictionary=samplers[1].sample(avatars[1])
		var max_error:=0.0
		var worst:=-1
		for i in sa.points.size():
			var error:float=sa.points[i].distance_to(sb.points[i])
			if error>max_error:
				max_error=error
				worst=i
		var physics_error:=0.0
		var physics_errors:=[]
		for frame in 60:
			for a in avatars:
				a.skeleton.reset_bone_poses()
				a.apply_pose({})
				a.spring_contacts.secondary.do_process(1.0/60.0)
			sa=samplers[0].sample(avatars[0])
			sb=samplers[1].sample(avatars[1])
			var frame_error:=0.0
			for i in sa.points.size(): frame_error=maxf(frame_error,sa.points[i].distance_to(sb.points[i]))
			physics_error=maxf(physics_error,frame_error)
			if frame in [0,1,2,10,30,59]:physics_errors.append({"frame":frame,"error":frame_error})
		rows.append({"character":character,"mismatch":mismatch,"sampled_points":sa.points.size(),"before_physics_max_point_error_m":max_error,"worst_point":worst,"same_physics_max_error":physics_error,"same_physics_frames":physics_errors})
		for a in avatars:a.free()
	var report:={"rows":rows,"at_origin":at_origin,"scope":"Pair at +/-0.56m; rest sampling then60identical authored spring ticks; all local poses reset and same relaxed pose; compare exact sampling identities and skinned points."}
	FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/physics_cloth/review-sample-correspondence"+("-origin" if at_origin else "")+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
