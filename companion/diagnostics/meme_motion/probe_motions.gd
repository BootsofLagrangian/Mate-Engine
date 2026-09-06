extends SceneTree
const MOTIONS := ["mambo_sway","hachimi_peek","playful_shrug"]
var checks := 0
var failures: Array[String]=[]
var cells: Array=[]
var initial_hashes: Dictionary={}

func input_hashes(characters: PackedStringArray) -> Dictionary:
	var result:={}
	for name in characters:
		var path: String=ProjectSettings.globalize_path("res://../assets/"+name+".vrm")
		result["assets/"+name+".vrm"]=FileAccess.get_sha256(path)
	for name in MOTIONS+["uma_home_idle","uma_walk"]:
		var path: String=ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma")
		result["assets/motions/"+name+".vrma"]=FileAccess.get_sha256(path)
	return result

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func make_player(character: String) -> MotionPlayer:
	var avatar:=VrmAvatar.new()
	root.add_child(avatar)
	check(avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm")),character+" VRM loaded")
	var player:=MotionPlayer.new()
	root.add_child(player)
	player.set_process(false)
	player.avatar=avatar
	player.gaze_enabled=false
	player.idle_enabled=false
	player.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json"))))
	for name in MOTIONS+["uma_home_idle","uma_walk"]:
		check(player.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"),"foot" if name!="uma_walk" else ""),character+" "+name+" loaded")
	player.register_locomotion_clip("uma_walk",true)
	return player

func remove_player(player: MotionPlayer) -> void:
	var avatar:=player.avatar
	player.free()
	avatar.free()

func run() -> void:
	var characters:=OS.get_cmdline_user_args()
	if characters.is_empty(): characters=PackedStringArray(["cheval-grand","rice-shower","eishin-flash"])
	initial_hashes=input_hashes(characters)
	for name in MOTIONS:
		var clip:=VrmaClip.new()
		check(clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma")),name+" parse")
		check(clip.hips_translation.is_empty(),name+" no root translation")
		var forbidden:=false
		var finite:=true
		var maximum_step:=0.0
		var endpoint:=0.0
		for bone in clip.tracks:
			if bone in ["hips","leftUpperLeg","leftLowerLeg","leftFoot","leftToes","rightUpperLeg","rightLowerLeg","rightFoot","rightToes","leftEye","rightEye","jaw"]: forbidden=true
			var track: Dictionary=clip.tracks[bone]
			endpoint=maxf(endpoint,track.rotations[0].angle_to(track.rotations[-1]))
			for index in track.rotations.size():
				finite=finite and track.rotations[index].is_finite()
				if index>0: maximum_step=maxf(maximum_step,rad_to_deg(track.rotations[index-1].angle_to(track.rotations[index])))
		check(not forbidden,name+" no leg/root/face ownership")
		check(finite and endpoint<0.001,name+" finite closed rotation curves")
		check(maximum_step<2.0,name+" authored 60 Hz rotation step below 2 degrees")
		cells.append({"motion":name,"scope":"asset","max_step_deg_60hz":maximum_step,"endpoint_rad":endpoint})
	for character in characters:
		for fps in [30,60]:
			var baseline: Array=[]
			for name in [""]+MOTIONS:
				var player:=make_player(character)
				player.play_vrma("uma_walk",1,true)
				var max_leg_error:=0.0
				var max_upper_change:=0.0
				var finite:=true
				var remained_walking:=true
				for frame in fps*7:
					if frame==fps and not name.is_empty(): check(player.play_upper_body_gesture(name),character+" "+name+" upper start")
					player._process(1.0/fps)
					player.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
					var points:={}
					for bone in ["hips","leftFoot","rightFoot","leftHand","rightHand","head"]:
						points[bone]=player.avatar.bone_global_position(bone)
						finite=finite and points[bone].is_finite()
					if name.is_empty():baseline.append(points)
					else:
						for bone in ["hips","leftFoot","rightFoot"]:max_leg_error=maxf(max_leg_error,points[bone].distance_to(baseline[frame][bone]))
						for bone in ["leftHand","rightHand","head"]:max_upper_change=maxf(max_upper_change,points[bone].distance_to(baseline[frame][bone]))
					remained_walking=remained_walking and player.current_gesture()=="uma_walk"
				if not name.is_empty():
					var label:String=character+" "+name+" @"+str(fps)
					check(finite,label+" finite pose")
					check(remained_walking,label+" UMA walk retained")
					check(max_leg_error<0.00001,label+" lower-body baseline unchanged")
					check(max_upper_change>0.015,label+" upper articulation visible")
					check(not player.is_upper_body_active(),label+" finite completion")
					player.set_upper_body_contact_lock(true)
					check(not player.play_upper_body_gesture(name,1,1,1,["arms","torso"]),label+" contact-owned arms reserved")
					check(player.play_upper_body_gesture(name,1,1,1,["head"]),label+" head remains independent")
					player.reset_all()
					check(not player.is_upper_body_active(),label+" reset clears layer")
					cells.append({"character":character,"motion":name,"fps":fps,"scope":"walking overlay","max_leg_error_m":max_leg_error,"max_upper_change_m":max_upper_change})
				remove_player(player)
		var player:=make_player(character)
		player.idle_enabled=true
		player.set_ambient_loop("uma_home_idle")
		for frame in 120:player._process(1.0/60)
		for name in MOTIONS:
			check(player.play_ambient_action(name),character+" "+name+" ambient start")
			var max_foot_error:=0.0
			for frame in 360:
				player._process(1.0/60)
				for bone in ["leftFoot","rightFoot"]:
					var idx:int=player.avatar.bone_index[bone]
					max_foot_error=maxf(max_foot_error,player.avatar.skeleton.get_bone_global_pose(idx).origin.distance_to(player.avatar.skeleton.get_bone_global_rest(idx).origin))
			check(max_foot_error<0.001,character+" "+name+" planted idle feet")
			check(player.authored_ambient.action_name.is_empty(),character+" "+name+" ambient completes")
			cells.append({"character":character,"motion":name,"scope":"ambient action","max_foot_error_m":max_foot_error})
		remove_player(player)
	var final_hashes:=input_hashes(characters)
	check(initial_hashes==final_hashes,"input assets stable during harness")
	var report:={"checks":checks,"failures":failures,"cells":cells,"characters":Array(characters),"input_sha256":initial_hashes,"input_sha256_after":final_hashes,"scope":"Deterministic real-rig source harness; not packaged Windows visual acceptance"}
	var output:=OS.get_environment("MEME_MOTION_REPORT")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../diagnostics/meme_motion/validation.json")
	elif not output.is_absolute_path():output=ProjectSettings.globalize_path("res://../"+output)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write report: "+output)
		quit(1)
		return
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("MEME_MOTION_CHECKS=",checks," FAILURES=",failures.size())
	quit(1 if not failures.is_empty() else 0)
