extends SceneTree
const CLIPS := ["idle_natural","idle_talking","walk","walk_formal","dance","interact","pick_up","sit_idle"]
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var player := MotionPlayer.new()
		root.add_child(player)
		player.set_process(false)
		player.avatar = avatar
		player.set_bank(bank)
		for name in CLIPS:
			if not player.load_vrma(name, ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma")):
				failures += 1
				continue
			var clip: VrmaClip = player.vrma_clips[name]
			player.play_vrma(name,1.0,true)
			for frame in int(ceil(clip.duration*2.1*60)):
				player._process(1.0/60)
				for idx in avatar.bone_index.values():
					if not avatar.skeleton.get_bone_global_pose(idx).is_finite():
						failures += 1
			if player.current_gesture() != name:
				failures += 1
			var before := snapshot(avatar)
			player.play_gesture("nod")
			player._process(1.0/60)
			var jump := difference(before,snapshot(avatar))
			# Outgoing local velocity is preserved (runtime cap120deg/s),
			# so a moving joint may legitimately travel up to2deg at60FPS.
			if jump > 2.1:
				failures += 1
			for frame in 60:
				player._process(1.0/60)
			player.play_gesture(name)
			if player.current_gesture() != name:
				failures += 1
			for frame in int(ceil((clip.duration+0.1)*60)):
				player._process(1.0/60)
			if player.is_gesture_active():
				failures += 1
			print("ASSET ",character," ",name," tracks=",clip.tracks.size()," duration=",clip.duration," supersession_first_step_deg=",jump)
		player.free()
		avatar.free()
	print("MOTION_ASSET_FAILURES=",failures)
	quit(1 if failures else 0)
func snapshot(avatar: VrmAvatar) -> Dictionary:
	var result := {}
	for idx in avatar.bone_index.values():
		result[idx] = avatar.skeleton.get_bone_pose_rotation(idx)
	return result
func difference(a: Dictionary,b: Dictionary) -> float:
	var result := 0.0
	for idx in a:
		result = maxf(result, rad_to_deg(a[idx].angle_to(b[idx])))
	return result
