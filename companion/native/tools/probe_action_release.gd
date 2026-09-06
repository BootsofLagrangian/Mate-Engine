extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var avatar := VrmAvatar.new()
	root.add_child(avatar)
	avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	var player := MotionPlayer.new()
	root.add_child(player)
	player.set_process(false)
	player.avatar = avatar
	player.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json"))))
	for kind in ["single","pair"]:
		player.reset_all()
		for frame in 120: player._process(1.0/60)
		if kind == "single": player.play_gesture("wave")
		else: player.play_gesture_sequence("nod","wave",0.5)
		var previous := Quaternion.IDENTITY
		var end := 4.0 if kind == "single" else 6.5
		for frame in int((end+0.2)*60):
			player._process(1.0/60)
			var q := avatar.skeleton.get_bone_global_pose(avatar.bone_index.rightHand).basis.get_rotation_quaternion()
			var speed := rad_to_deg(previous.angle_to(q))*60
			if absf((frame+1.0)/60-end)<0.10: print(kind," time=",(frame+1.0)/60," hand_speed=",speed)
			previous=q
	quit()
