extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var selected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var report: Array = []
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		for item in selected.motions:
			var entry: Dictionary = item.entry
			if not str(entry.name).begins_with("authored_"): continue
			var p := MotionPlayer.new()
			root.add_child(p)
			p.set_process(false)
			p.avatar=avatar
			p.set_bank(bank)
			p.idle_enabled=false
			p.gaze_enabled=false
			var path := ProjectSettings.globalize_path("res://../"+str(item.source_path))
			if not p.load_vrma(entry.name,path,entry.get("contact_mode","")):
				failures+=1
				continue
			p.play_vrma(entry.name,1.0,bool(entry.loop))
			var max_error := 0.0
			var nonfinite := 0
			var duration := float(entry.duration)*(2.0 if bool(entry.loop) else 1.0)+0.6
			for frame in int(ceil(duration*60.0)):
				p._process(1.0/60.0)
				for bone in avatar.bone_index:
					var pose := avatar.skeleton.get_bone_global_pose(avatar.bone_index[bone])
					if not pose.origin.is_finite() or not pose.basis.is_finite(): nonfinite+=1
				var diagnostics: Dictionary = p.authored_ambient.diagnostics.get("feet",{})
				for side in diagnostics:
					var value: Dictionary = diagnostics[side]
					max_error=maxf(max_error,float(value.get("error",value.get("residual",0.0))))
			if nonfinite>0 or max_error>0.015: failures+=1
			report.append({"character":character,"name":entry.name,"duration":duration,"nonfinite_poses":nonfinite,"max_solver_reported_error_m":max_error,"contact_mode":entry.get("contact_mode","")})
			print("EVERYDAY ",character," ",entry.name," nonfinite=",nonfinite," solver_error=",max_error)
			p.free()
		avatar.free()
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"cases":report},"  ")+"\n")
	print("EVERYDAY_FAILURES=",failures)
	quit(1 if failures else 0)
