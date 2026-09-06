extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var avatar := VrmAvatar.new()
			root.add_child(avatar)
			avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
			avatar.rotation.y = deg_to_rad(82)
			var player := MotionPlayer.new()
			root.add_child(player)
			player.set_process(false)
			player.avatar = avatar
			player.idle_enabled = false
			player.gaze_enabled = false
			player.load_vrma("walk",ProjectSettings.globalize_path("res://../assets/motions/walk.vrma"))
			player.play_vrma("walk",1,true)
			var previous_x := 0.0
			var previous := Quaternion.IDENTITY
			var previous_speed := 0.0
			var max_jump := 0.0
			var moving_frames := 0
			for frame in fps*6:
				player._process(1.0/fps)
				var x := roundf((frame+1.0)/fps*6.0)
				player.set_locomotion_sample(Vector2(6,0),Vector2(x-previous_x,0),330,true)
				previous_x=x
				var q := avatar.skeleton.get_bone_global_pose(avatar.bone_index.leftUpperArm).basis.get_rotation_quaternion()
				var change := (previous.inverse()*q).normalized()
				var speed: float = rad_to_deg(2*atan2(Vector3(change.x,change.y,change.z).length(),absf(change.w)))*fps
				if frame>fps:
					max_jump=maxf(max_jump,absf(speed-previous_speed))
					if speed>0.05: moving_frames+=1
				previous=q
				previous_speed=speed
			# Six integer pixels/s formerly held most frames then stepped the clip.
			if moving_frames < fps*4 or max_jump>20: failures+=1
			print("QUANTIZED ",character," fps=",fps," continuous_arm_frames=",moving_frames," max_speed_delta=",max_jump)
			player.free()
			avatar.free()
	print("QUANTIZED_FAILURES=",failures)
	quit(1 if failures else 0)
