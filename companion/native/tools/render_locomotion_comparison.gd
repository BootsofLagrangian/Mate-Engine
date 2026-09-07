extends SceneTree
## Actual VRM rendering of source poses or displacement-driven runtime gait.
## --avatar PATH --clips JSON --bank PATH --output DIR [--runtime]
func arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i] == key: return args[i+1]
	return ""
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var output:=arg("--output")
	DirAccess.make_dir_recursive_absolute(output)
	var entries: Array=JSON.parse_string(FileAccess.get_file_as_string(arg("--clips")))
	var runtime:bool="--runtime" in OS.get_cmdline_user_args()
	var stage:=Node3D.new();root.add_child(stage)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color(.12,.15,.2)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy=.7;stage.add_child(env)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-25,0);light.light_energy=.7;stage.add_child(light)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(0,.9,4)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.2;camera.current=true
	var avatars:Array=[];var players:Array=[];var centers:Array=[]
	var bank:=MotionBank.parse_json_text(FileAccess.get_file_as_string(arg("--bank")))
	for i in entries.size():
		var avatar:=VrmAvatar.new();stage.add_child(avatar)
		if not avatar.load_from_file(arg("--avatar")):quit(2);return
		avatar.position.x=(i-(entries.size()-1)*.5)*1.1;avatar.rotation.y=deg_to_rad(55)
		var player:=MotionPlayer.new();stage.add_child(player);player.set_process(false)
		player.avatar=avatar;player.set_bank(bank);player.gaze_enabled=false;player.idle_enabled=false
		if not player.load_vrma("candidate",entries[i].path):quit(2);return
		player.register_locomotion_clip("candidate",true)
		if entries[i].has("style") and not player.register_locomotion_style("candidate",entries[i].style):quit(2);return
		if runtime:
			player.prepare_scene_locomotion(deg_to_rad(55));player.play_vrma("candidate",1,true)
		avatars.append(avatar);players.append(player)
		var center:=Vector3.ZERO
		for k in 120:center+=player.vrma_clips.candidate.sample_hips_offset(player.vrma_clips.candidate.duration*k/120.0)
		centers.append(center/120.0)
		var label:=Label.new();root.add_child(label);label.text=entries[i].name+ (" · runtime" if runtime else " · source")
		label.position=Vector2(60+i*420,35);label.add_theme_font_size_override("font_size",22)
	var dt:=1.0/60
	var heading:=deg_to_rad(55)
	for frame in 240:
		for i in avatars.size():
			var avatar:VrmAvatar=avatars[i];var player:MotionPlayer=players[i]
			if runtime:
				player._process(dt)
				var speed:=player.authored_locomotion_speed("candidate")
				if speed<=0:speed=.35
				var velocity:=Vector3(sin(heading),0,cos(heading))*speed
				player.set_scene_locomotion_sample(velocity,velocity*dt,heading,true)
			else:
				avatar.reset_pose()
				var clip:VrmaClip=player.vrma_clips.candidate
				var t:=fmod(frame*dt,clip.duration)
				avatar.apply_normalized_rotations(clip.sample(t),1)
				var hip:=clip.sample_hips_offset(t)-Vector3(centers[i])
				hip.y=clip.sample_hips_offset(t).y
				avatar.set_hips_offset(hip*avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame%3==0:root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % (frame/3)))
	print("LOCOMOTION_RENDER ",output)
	quit()
