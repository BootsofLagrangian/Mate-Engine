extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var bank := MotionBank.parse(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json"))))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var avatar := VrmAvatar.new()
			root.add_child(avatar)
			avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
			var player := MotionPlayer.new()
			root.add_child(player)
			player.set_process(false)
			player.avatar = avatar
			player.set_bank(bank)
			for pair in [["wave","nod"],["nod","wave"],["wave","wave"]]:
				player.reset_all()
				for frame in fps: player._process(1.0/fps)
				var accepted := player.play_gesture_sequence(pair[0],pair[1],0.6,true)
				var overlap_frames := 0
				var incoming_start := -1.0
				var first_duration := float(bank.get_motion(pair[0]).duration)
				for frame in fps*10:
					player._process(1.0/fps)
					var state := player.overlap_diagnostics
					if not state.is_empty() and not state.incoming.is_empty():
						overlap_frames += 1
						if incoming_start < 0: incoming_start = (frame+1.0)/fps
						if not player._preview: failures += 1
				if not accepted.accepted or overlap_frames < fps*0.5 or incoming_start >= first_duration or player.is_gesture_active() or player._preview:
					failures += 1
				print("PAIR ",character," fps=",fps," ",pair," overlap_s=",float(overlap_frames)/fps," incoming=",incoming_start," nominal_end=",first_duration)
			player.free()
			avatar.free()
	print("SEQUENCE_FAILURES=",failures)
	quit(1 if failures else 0)
