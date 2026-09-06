extends SceneTree
var failures:=0
## Visual probe: run with a real display (not --headless). Saves rendered poses.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(480,600)
	var stage := Node3D.new()
	root.add_child(stage)
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
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	var output := OS.get_environment("MOTION_RENDER_DIR")
	if output.is_empty():
		output = "/tmp/uma-seated-renders"
	DirAccess.make_dir_recursive_absolute(output)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var player := MotionPlayer.new()
		stage.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(bank)
		avatar.scale=Vector3.ONE*float(OS.get_environment("SEAT_TEST_SCALE") if not OS.get_environment("SEAT_TEST_SCALE").is_empty() else "1.0")
		player.idle_enabled = false
		player.gaze_enabled = false
		player.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
		player.start_contact_pose("sit")
		player.set_seated_floor(float(OS.get_environment("SEAT_TEST_HEIGHT") if not OS.get_environment("SEAT_TEST_HEIGHT").is_empty() else "0.428"))
		var geometry := avatar.calibrate_seated_pose(player.vrma_clips.sit_idle.sample(0))
		avatar.rotation.y=PI/2
		for i in 60:
			player._process(1.0/60)
			await process_frame
			await RenderingServer.frame_post_draw
		print("FLOOR_SECONDARY ",avatar.seated_floor.secondary," active=",avatar.seated_floor.active," colliders=",avatar.seated_floor._colliders.size())
		print("CACHE_READY ",character," samples=",avatar._secondary_pose_samples," bounds=",avatar.seated_geometry.bounds)
		var observed:=[]
		for sample in 4:
			for child in avatar.skeleton.get_children(true):
				if child.name == "VRM_internal_skeleton_modifier":
					child.modification_processed.connect(func():
						var live:=preload("res://tools/seated_snapshot.gd").measure(avatar,{})
						observed.append(live.bounds.position.y)
					,CONNECT_ONE_SHOT)
			for frame in 10:
				player._process(1.0/60)
				await process_frame
				await RenderingServer.frame_post_draw
		var cached_bottom:float=avatar.seated_geometry.bounds.position.y
		var worst:=0.0
		for bottom in observed: worst=maxf(worst,cached_bottom-float(bottom))
		print("FLOOR_MATCH ",character," floor=",avatar.seated_floor.floor_y," actual_seat_drop=",avatar.seated_geometry.anchor.y-cached_bottom," calibration=",avatar.seated_geometry.diagnostics," cached_bottom=",cached_bottom," observed=",observed," undershoot_m=",worst)
		if avatar._secondary_pose_samples<30 or observed.size()!=4: failures+=1
		for bottom in observed:
			if float(bottom)<float(avatar.seated_geometry.anchor.y)-avatar.seated_floor.clearance-0.001: failures+=1
		root.get_texture().get_image().save_png(output.path_join(character+"-cached-seat.png"))
		var original_lengths:=[]
		for entry in avatar.seated_floor._extended_joints: original_lengths.append([entry[1],entry[2]])
		var states:Array=avatar.seated_floor.secondary.spring_bones_internal.duplicate()
		player.stop_contact_pose()
		for entry in original_lengths:
			if not is_equal_approx(entry[0].length,entry[1]): failures+=1
		for state in states:
			for collider in state.colliders:
				if collider is SeatedFloorConstraint.FloorCollider: failures+=1
		for frame in 10:
			player._process(1.0/60)
			await process_frame
			await RenderingServer.frame_post_draw
		if is_finite(avatar.seated_floor.clearance) or avatar.seated_floor.active: failures+=1
		player.free()
		avatar.free()
	print("RENDERS=",output)
	print("SEATED_FLOOR_FAILURES=",failures)
	quit(1 if failures else 0)
