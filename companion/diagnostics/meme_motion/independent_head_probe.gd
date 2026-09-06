extends SceneTree
## Independent measurement amendment to the author probe: final world head derivatives.
## No derivative acceptance threshold; existing checks remain unchanged.
const MOTIONS := ["mambo_sway","hachimi_peek","playful_shrug"]
var checks := 0
var failures: Array[String]=[]
var cells: Array=[]

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
				var head_previous:=Quaternion.IDENTITY
				var head_velocity:=Vector3.ZERO
				var max_head_speed:=0.0
				var max_head_accel:=0.0
				var head_peak_frame:=0
				var max_head_difference:=0.0
				var head_difference_peak:={}
				for frame in fps*7:
					if frame==fps and not name.is_empty(): check(player.play_upper_body_gesture(name),character+" "+name+" upper start")
					player._process(1.0/fps)
					player.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
					var sk:=player.avatar.skeleton
					var head_now:Quaternion=(sk.global_transform*sk.get_bone_global_pose(player.avatar.bone_index.head)).basis.orthonormalized().get_rotation_quaternion()
					var q:Quaternion=(head_now*head_previous.inverse()).normalized()
					if q.w<0:q=Quaternion(-q.x,-q.y,-q.z,-q.w)
					var vector:=Vector3(q.x,q.y,q.z)
					var velocity:Vector3=vector.normalized()*rad_to_deg(2*atan2(vector.length(),q.w))*fps if vector.length()>0.00000001 else Vector3.ZERO
					if frame>fps:
						max_head_speed=maxf(max_head_speed,velocity.length())
						var accel:float=(velocity-head_velocity).length()*fps
						if accel>max_head_accel:head_peak_frame=frame
						max_head_accel=maxf(max_head_accel,accel)
					head_previous=head_now
					head_velocity=velocity
					var points:={}
					for bone in ["hips","leftFoot","rightFoot","leftHand","rightHand","head"]:
						points[bone]=player.avatar.bone_global_position(bone)
						finite=finite and points[bone].is_finite()
					points.head_rotation=head_now
					if name.is_empty():baseline.append(points)
					else:
						var difference:=rad_to_deg(head_now.angle_to(baseline[frame].head_rotation))
						if difference>max_head_difference:
							max_head_difference=difference
							var rest:Quaternion=(sk.global_transform.basis*sk.get_bone_global_rest(player.avatar.bone_index.head).basis).orthonormalized().get_rotation_quaternion()
							var euler:Vector3=(head_now*rest.inverse()).get_euler()*180/PI
							var base_euler:Vector3=(Quaternion(baseline[frame].head_rotation)*rest.inverse()).get_euler()*180/PI
							head_difference_peak={"frame":frame,"time_s":float(frame)/fps,"world_rest_relative_euler_yxz_deg":[euler.x,euler.y,euler.z],"baseline_world_rest_relative_euler_yxz_deg":[base_euler.x,base_euler.y,base_euler.z]}
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
					cells.append({"character":character,"motion":name,"fps":fps,"scope":"walking overlay","max_leg_error_m":max_leg_error,"max_upper_change_m":max_upper_change,"head_speed_deg_s":max_head_speed,"head_accel_deg_s2":max_head_accel,"head_accel_peak_frame":head_peak_frame,"max_head_vs_baseline_deg":max_head_difference,"head_difference_peak":head_difference_peak})
				if name.is_empty():cells.append({"character":character,"fps":fps,"scope":"walking baseline","head_speed_deg_s":max_head_speed,"head_accel_deg_s2":max_head_accel})
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
	var report:={"checks":checks,"failures":failures,"cells":cells,"characters":Array(characters),"scope":"Deterministic real-rig source harness; not packaged Windows visual acceptance"}
	var output:=OS.get_environment("MEME_MOTION_REPORT")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../diagnostics/meme_motion/validation.json")
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("MEME_MOTION_CHECKS=",checks," FAILURES=",failures.size())
	quit(1 if not failures.is_empty() else 0)
