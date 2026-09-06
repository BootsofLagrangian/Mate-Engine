extends SceneTree
const Samples=preload("res://tools/garment_quality_samples.gd")
var output:="/tmp/garment-quality-rebased"
func _init() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1000,650)
	var stage:=Node3D.new()
	root.add_child(stage)
	var camera:=Camera3D.new()
	camera.position=Vector3(0,.85,3)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.5
	stage.add_child(camera)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-25,-30,0)
	stage.add_child(light)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.1,.13,.18)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.7
	stage.add_child(env)
	var rows:=[]
	for character in ["cheval-grand","rice-shower","eishin-flash","mambo","hachimi"]:
		var mini:bool=character in ["mambo","hachimi"]
		for motion in ["rest","uma_walk","sit_idle"]:
			var avatars:=[]
			var samplers:=[]
			for enabled in [false,true]:
				var avatar:=VrmAvatar.new()
				stage.add_child(avatar)
				avatar.position.x=0.0 # same physics origin; render A/B sequentially
				avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				avatar.spring_contacts.configure(avatar, not mini) # explicit experimental contacts; default runtime is off
				avatar.spring_contacts.secondary.internal_modifier_node.active=false
				if not enabled:
					for entry in avatar.spring_contacts.entries: entry[0].colliders.erase(entry[1])
				avatars.append(avatar)
				var sampler:=Samples.new()
				sampler.configure(avatar)
				samplers.append(sampler)
			camera.position.y=.53 if mini else .85
			camera.size=1.4 if mini else 2.1
			var clip:=VrmaClip.new()
			if motion!="rest": clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/"+motion+".vrma"))
			var displacements:=[]
			var strains:=[]
			var normal_reversed:=0
			var normals_total:=0
			var max_step:=0.0
			var settling_step:=0.0
			var motion_step:=0.0
			var reset_step:=0.0
			var max_length_error:=0.0
			var previous:={}
			var max_vertices:=0
			var subdir:=output.path_join(character+"-"+motion)
			DirAccess.make_dir_recursive_absolute(subdir)
			for frame in 360:
				for side in 2:
					var avatar:VrmAvatar=avatars[side]
					avatar.skeleton.reset_bone_poses()
					avatar.apply_pose({})
					if motion!="rest" and frame<180: avatar.apply_normalized_rotations(clip.sample(fmod(frame/60.0,clip.duration)),1.0)
					var secondary=avatar.spring_contacts.secondary
					if not mini or side==1: secondary.do_process(1.0/60.0)
					if side==1:
						for si in secondary.spring_bones_internal.size():
							var state=secondary.spring_bones_internal[si]
							var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[si]]
							for joint in state.verlets:
								var origin:Vector3=xf*avatar.skeleton.get_bone_global_pose(joint.bone_idx).origin
								max_length_error=maxf(max_length_error,absf(joint.current_tail.distance_to(origin)-joint.length))
								if previous.has(joint.bone_idx) and frame>30:
									var delta:float=joint.current_tail.distance_to(previous[joint.bone_idx])
									max_step=maxf(max_step,delta)
									if frame<180: motion_step=maxf(motion_step,delta)
									else: reset_step=maxf(reset_step,delta)
									if frame>=300: settling_step=maxf(settling_step,delta)
								previous[joint.bone_idx]=joint.current_tail
				if frame%12==0:
					var baseline:Dictionary=samplers[0].sample(avatars[0])
					var contacts:Dictionary=samplers[1].sample(avatars[1])
					max_vertices=baseline.points.size()
					for i in baseline.points.size(): displacements.append(baseline.points[i].distance_to(contacts.points[i]))
					for i in baseline.edges.size():
						if baseline.edges[i]>.001: strains.append(absf(contacts.edges[i]/baseline.edges[i]-1))
					for i in baseline.normals.size():
						if baseline.normals[i].length_squared()<1e-12: continue
						normals_total+=1
						if baseline.normals[i].dot(contacts.normals[i])<0: normal_reversed+=1
					for visible_side in 2:
						avatars[0].visible=visible_side==0
						avatars[1].visible=visible_side==1
						await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(subdir.path_join(("baseline-" if visible_side==0 else "physics-")+"%03d.png" % (frame/12)))
			displacements.sort()
			strains.sort()
			rows.append({"character":character,"motion":motion,"baseline":"no authored spring physics" if mini else "existing springs without added hand proxies","sampled_vertices":max_vertices,"displacement_max_m":displacements[-1] if not displacements.is_empty() else 0,"displacement_p95_m":displacements[int(displacements.size()*.95)] if not displacements.is_empty() else 0,"relative_edge_change_max":strains[-1] if not strains.is_empty() else 0,"relative_edge_change_p95":strains[int(strains.size()*.95)] if not strains.is_empty() else 0,"normal_reversed_samples":normal_reversed,"normal_samples":normals_total,"max_tail_step_m":max_step,"max_motion_tail_step_m":motion_step,"max_pose_reset_tail_step_m":reset_step,"last_second_settling_tail_step_m":settling_step,"bone_length_error_m":max_length_error})
			for avatar in avatars: avatar.free()
	var report:={"scope":"sparse spring-influenced triangles every17th triangle;30sampledframes/cell;first3seconds source motion then3seconds relaxed pose stresssettling;same physics origin; sequential baseline/physics captures. Boneposesresetallbeforeeachfixedtick. Mini baseline no newlyauthored springphysics.","rows":rows}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
