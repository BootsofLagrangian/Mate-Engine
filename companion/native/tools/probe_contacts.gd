extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		var player := MotionPlayer.new()
		root.add_child(player)
		player.avatar = avatar
		player.set_process(false)
		player.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json"))))
		for clip in ["walk","sit_idle","idle_talking"]:
			player.load_vrma(clip,ProjectSettings.globalize_path("res://../assets/motions/"+clip+".vrma"))
		player.play_vrma("walk",1,true)
		player.set_locomotion_direction(Vector2(75,0))
		for i in 180:
			player._process(1.0/60)
		var anchor: Vector3 = avatar.contact_anchors().foot
		var drift := 0.0
		for i in 180:
			player._process(1.0/60)
			drift = maxf(drift,anchor.distance_to(avatar.contact_anchors().foot))
		if absf(rad_to_deg(avatar.rotation.y)-82) > 0.1 or drift > 0.001:
			failures += 1
		player.start_contact_pose("sit")
		for i in 180:
			player._process(1.0/60)
		var hip := avatar.bone_global_position("hips")
		var knee := avatar.bone_global_position("leftLowerLeg")
		var foot := avatar.bone_global_position("leftFoot")
		if knee.y < hip.y-0.22 or foot.y > knee.y-0.12:
			failures += 1
		player.play_gesture("wave")
		for i in 90:
			player._process(1.0/60)
		if avatar.bone_global_position("leftLowerLeg").y < avatar.bone_global_position("hips").y-0.22:
			failures += 1
		player.play_vrma("idle_talking",1.0,true)
		for i in 180:
			player._process(1.0/60)
			if avatar.bone_global_position("leftLowerLeg").y < avatar.bone_global_position("hips").y-0.22:
				failures += 1
		var before: Vector3 = avatar.contact_anchors().sit
		avatar.scale = Vector3.ONE*0.6
		if (avatar.contact_anchors().sit-before*0.6).length() > 0.001:
			failures += 1
		avatar.scale = Vector3.ONE
		player.stop_contact_pose()
		for i in 90:
			player._process(1.0/60)
		var target := avatar.bone_global_position("leftUpperArm")+Vector3(0.24,-0.12,0.12)
		player.start_contact_pose("lean",target)
		for i in 120:
			player._process(1.0/60)
			var actual_error := target.distance_to(avatar.bone_global_position("leftHand"))
			if player.contact_reachable and actual_error >= 0.015:
				failures += 1
			if i == 0 and player.contact_reachable:
				failures += 1
		var hand_error := target.distance_to(avatar.bone_global_position("leftHand"))
		if not player.contact_reachable or hand_error > 0.015:
			failures += 1
		print("CONTACT ",name," stable_foot_drift=",drift," sit_hip=",hip," knee=",knee," foot=",foot," lean_hand_error=",hand_error)
		player.free()
		avatar.free()
	print("CONTACT_FAILURES=",failures)
	quit(1 if failures else 0)
