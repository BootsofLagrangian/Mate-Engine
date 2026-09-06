extends SceneTree
## Offline evaluation; -- render enables actual viewport snapshots.
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var render := "render" in OS.get_cmdline_user_args()
	var candidates := ["idle_once_lookaround","idle_once_headtilt","idle_once_slownod","idle_once_shiftheelpivot","idle_to_walk","settle_to_idle_small","turn_left","turn_right","sitting_enter","sitting_exit"]
	var candidate_root := ProjectSettings.globalize_path("res://../diagnostics/authored_idle/candidates")
	var user_args := OS.get_cmdline_user_args()
	if "uma" in user_args:
		candidates = ["uma-idle"]
		candidate_root = ProjectSettings.globalize_path("res://../assets/research/uma/candidates")
	root.size = Vector2i(480,600)
	var stage := Node3D.new()
	root.add_child(stage)
	if render:
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.15,0.18,0.23)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.65
		stage.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-25,-30,0)
		light.light_energy = 0.65
		stage.add_child(light)
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.position = Vector3(0,0.85,3)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.95
		camera.current = true
	var output := "/tmp/authored-candidate-renders"
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		for name in candidates:
			var clip := VrmaClip.new()
			if not clip.load_file(candidate_root.path_join(name+".vrma")):
				failures += 1
				continue
			var maximum_foot_shift := 0.0
			avatar.reset_pose()
			var first: Vector3 = avatar.contact_anchors().foot_current
			for frame in 121:
				avatar.reset_pose()
				avatar.apply_normalized_rotations(clip.sample(clip.duration*frame/120.0),1.0)
				maximum_foot_shift = maxf(maximum_foot_shift, first.distance_to(avatar.contact_anchors().foot_current))
				for idx in avatar.bone_index.values():
					if not avatar.skeleton.get_bone_global_pose(idx).is_finite():
						failures += 1
				if render and frame in [0,30,60,90,120]:
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output.path_join("%s-%s-%03d.png" % [character,name,frame]))
			print("CANDIDATE ",character," ",name," duration=",clip.duration," tracks=",clip.tracks.size()," full_body_foot_displacement_m=",maximum_foot_shift)
		avatar.free()
	print("CANDIDATE_FAILURES=",failures)
	quit(1 if failures else 0)
