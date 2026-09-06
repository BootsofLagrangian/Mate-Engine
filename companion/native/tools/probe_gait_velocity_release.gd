extends SceneTree
## Reports actual first-frame handoff, including post-window-move IK.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var avatar := VrmAvatar.new()
			root.add_child(avatar)
			avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
			var player := MotionPlayer.new()
			root.add_child(player)
			player.set_process(false)
			player.avatar = avatar
			player.load_vrma("walk",ProjectSettings.globalize_path("res://../assets/motions/walk.vrma"))
			player.set_heading_intent(Vector2(100,0))
			for frame in fps*4:
				player._process(1.0/fps)
			player.play_vrma("walk",1,true)
			var previous := {}
			var last := {}
			for frame in int(fps*2.7):
				previous = last
				player._process(1.0/fps)
				player.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),360,true)
				last = snapshot(avatar)
			player.stop_gesture()
			player.set_locomotion_sample(Vector2.ZERO,Vector2.ZERO,360,true)
			player._process(1.0/fps)
			var next := snapshot(avatar)
			for name in ["hips","leftLowerLeg","rightLowerLeg","leftFoot","rightFoot"]:
				var outgoing: Vector3 = (last[name]-previous[name])*fps
				var incoming: Vector3 = (next[name]-last[name])*fps
				print("RELEASE ",character," fps=",fps," bone=",name," outgoing_m_s=",outgoing," incoming_m_s=",incoming," acceleration_m_s2=",(incoming-outgoing).length()*fps)
			player.free()
			avatar.free()
	quit()
func snapshot(avatar: VrmAvatar) -> Dictionary:
	var pose := {}
	for name in ["hips","leftLowerLeg","rightLowerLeg","leftFoot","rightFoot"]:
		pose[name] = avatar.skeleton.get_bone_global_pose(avatar.bone_index[name]).origin
	return pose
