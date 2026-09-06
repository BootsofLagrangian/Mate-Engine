extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var player := MotionPlayer.new()
		root.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json"))))
		for alias in ["uma_home_idle","uma_cheval_idle","uma_rice_idle","uma_eishin_idle"]:
			if not player.load_vrma(alias,ProjectSettings.globalize_path("res://../assets/research/uma/candidates/"+alias+".vrma")):
				failures += 1
				continue
			player.set_ambient_loop(alias)
			var maximum_error := 0.0
			var maximum_hip_offset := 0.0
			for frame in 720:
				player._process(1.0/60)
				if player.is_gesture_active():
					failures += 1
				for side in ["left","right"]:
					var foot: int = avatar.bone_index[side+"Foot"]
					maximum_error = maxf(maximum_error,avatar.skeleton.get_bone_global_pose(foot).origin.distance_to(avatar.skeleton.get_bone_global_rest(foot).origin))
				maximum_hip_offset = maxf(maximum_hip_offset,player.authored_ambient._hip_offset.length())
				for idx in avatar.bone_index.values():
					if not avatar.skeleton.get_bone_global_pose(idx).is_finite():
						failures += 1
			if maximum_error > 0.001 or maximum_hip_offset < 0.0001:
				failures += 1
			player.set_ambient_attention_override(true)
			# Bounded ownership pursuit takes ~2.4s for a complete handoff.
			for frame in 180:
				player._process(1.0/60)
			if player.authored_ambient.head_weight > 0.001:
				failures += 1
			player.set_ambient_attention_override(false)
			player.play_gesture("wave")
			player._process(1.0/60)
			if player.authored_ambient.owns_head():
				failures += 1
			player.stop_gesture()
			print("AUTHORED_AMBIENT ",character," ",alias," foot_error_m=",maximum_error," hips_motion_m=",maximum_hip_offset)
		player.set_ambient_loop("uma_home_idle")
		for action in ["uma_cheval_idle_action","uma_rice_idle_action","uma_eishin_idle_action"]:
			player.load_vrma(action,ProjectSettings.globalize_path("res://../assets/motions/"+action+".vrma"),"foot")
			if not player.play_ambient_action(action):
				failures += 1
			var error := 0.0
			for frame in 360:
				player._process(1.0/60)
				for side in ["left","right"]:
					var foot: int = avatar.bone_index[side+"Foot"]
					error = maxf(error,avatar.skeleton.get_bone_global_pose(foot).origin.distance_to(avatar.skeleton.get_bone_global_rest(foot).origin))
			if error > 0.001 or player.is_gesture_active() or not player.authored_ambient.action_name.is_empty():
				failures += 1
			print("AMBIENT_ACTION ",character," ",action," foot_error_m=",error)
		player.play_gesture("uma_cheval_idle_action","",1,1,1,true)
		var preview_error := 0.0
		for frame in 120:
			player._process(1.0/60)
			for side in ["left","right"]:
				var foot: int = avatar.bone_index[side+"Foot"]
				preview_error = maxf(preview_error,avatar.skeleton.get_bone_global_pose(foot).origin.distance_to(avatar.skeleton.get_bone_global_rest(foot).origin))
		if preview_error > 0.001 or not player._preview or not player.is_gesture_active() or player.authored_ambient.owns_head():
			failures += 1
		player.stop_gesture()
		player.load_vrma("idle_talking",ProjectSettings.globalize_path("res://../assets/motions/idle_talking.vrma"),"foot")
		player.play_vrma("idle_talking",1.0,true)
		var speech_error := 0.0
		for frame in 240:
			player._process(1.0/60)
			if frame >= 60:
				for side in ["left","right"]:
					var foot: int = avatar.bone_index[side+"Foot"]
					speech_error = maxf(speech_error,avatar.skeleton.get_bone_global_pose(foot).origin.distance_to(avatar.skeleton.get_bone_global_rest(foot).origin))
		if speech_error > 0.001:
			failures += 1
		print("STANDING_SPEECH ",character," foot_error_m=",speech_error)
		player.stop_gesture()
		var old_phase := player.authored_ambient.time
		player.set_ambient_suspended(true)
		for frame in 60:
			player._process(1.0/60)
		if player.authored_ambient.owns_head() or player.play_ambient_action("uma_cheval_idle_action") or player.authored_ambient.time <= old_phase:
			failures += 1
		player.set_ambient_suspended(false)
		player.idle_enabled = false
		player._process(1.0/60)
		if player.authored_ambient.owns_head():
			failures += 1
		player.free()
		avatar.free()
	print("AUTHORED_AMBIENT_FAILURES=",failures)
	quit(1 if failures else 0)
