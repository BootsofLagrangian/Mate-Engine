extends SceneTree
## Matched authored VRMA clip, fixed spring timestep; collision proxies are the sole A/B difference.
var output := "/tmp/spring-contact-motion-corrected"
func _init() -> void: call_deferred("run")
func overlap(avatar: VrmAvatar) -> Dictionary:
	var count := 0
	var maximum := 0.0
	var total := 0.0
	for entry in avatar.spring_contacts.entries:
		var state = entry[0]
		var collider = entry[1]
		var xf: Transform3D = avatar.spring_contacts.secondary.center_transforms[collider.center_index]
		var sk := avatar.skeleton
		var center := xf * sk.get_bone_global_pose(collider.from_bone).origin.lerp(sk.get_bone_global_pose(collider.to_bone).origin,collider.blend)
		var scale3 := xf.basis.get_scale().abs()
		for joint in state.verlets:
			var radius: float = collider.radius_m * maxf(scale3.x,maxf(scale3.y,scale3.z)) + joint.radius
			var depth := maxf(0,radius - joint.current_tail.distance_to(center))
			if depth > 0.00001: count += 1
			maximum = maxf(maximum,depth)
			total += depth
	return {"count":count,"max":maximum,"sum":total}
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(640,650)
	var stage:=Node3D.new()
	root.add_child(stage)
	var camera:=Camera3D.new()
	camera.position=Vector3(0,.85,3)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.9
	stage.add_child(camera)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-25,-30,0)
	stage.add_child(light)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.10,.13,.18)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE
	env.environment.ambient_light_energy=.7
	stage.add_child(env)
	var rows:=[]
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for motion in ["uma_walk","sit_idle"]:
			var clip:=VrmaClip.new()
			clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/"+motion+".vrma"))
			var row:={"character":character,"motion":motion,"clip_duration":clip.duration,"frames":360,"timestep":1.0/60.0}
			for enabled in [false,true]:
				var avatar:=VrmAvatar.new()
				stage.add_child(avatar)
				avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				avatar.spring_contacts.configure(avatar, true) # explicit experimental contacts; default runtime is off
				var secondary=avatar.spring_contacts.secondary
				secondary.internal_modifier_node.active=false
				if not enabled:
					for entry in avatar.spring_contacts.entries: entry[0].colliders.erase(entry[1])
				var sum_depth:=0.0
				var max_depth:=0.0
				var count:=0
				var max_step:=0.0
				var previous:={}
				var elapsed:=0
				var worst_frame:=0
				for frame in 360:
					avatar.skeleton.reset_bone_poses() # emulate modifier restoring authored pose; retain Verlet history
					avatar.apply_pose({})
					avatar.apply_normalized_rotations(clip.sample(fmod(frame/60.0,clip.duration)),1.0)
					var start:=Time.get_ticks_usec()
					secondary.do_process(1.0/60.0)
					elapsed+=Time.get_ticks_usec()-start
					if frame>59:
						var sample:=overlap(avatar)
						sum_depth+=sample.sum
						count+=sample.count
						if sample.max>max_depth:
							max_depth=sample.max
							worst_frame=frame
						for state in secondary.spring_bones_internal:
							for joint in state.verlets:
								if previous.has(joint.bone_idx): max_step=maxf(max_step,joint.current_tail.distance_to(previous[joint.bone_idx]))
								previous[joint.bone_idx]=joint.current_tail
					if frame==180:
						await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(output.path_join(character+"-"+motion+("-contacts" if enabled else "-baseline")+".png"))
				row["contacts" if enabled else "baseline"]={"penetrating_proxy_samples":count,"sum_depth_m":sum_depth,"max_depth_m":max_depth,"max_tail_step_m":max_step,"spring_tick_ms_mean":elapsed/360000.0,"worst_frame":worst_frame}
				avatar.free()
			rows.append(row)
	var report:={"scope":"300 measured frames after60warmup percell; endpoint-vs-handproxy overlap, not skin mesh intersection. ImportedVRM springs/authoredVRMA identical; ownproxiesdisabledonly inbaseline. Fixed1/60manualspringtick, renderer modifierinactive.","rows":rows}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit()
