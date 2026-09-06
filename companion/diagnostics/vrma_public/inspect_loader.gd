extends SceneTree
const Clip = preload("res://scripts/vrma_clip.gd")
func _initialize():
	var base = ProjectSettings.globalize_path("res://../assets/research/vrma-public-20260906/")
	var result = []
	for filename in DirAccess.get_files_at(base):
		if not filename.ends_with(".vrma"): continue
		var clip = Clip.new()
		var loaded = clip.load_file(base.path_join(filename))
		var row = {"file":filename,"loaded":loaded,"error":clip.error,"duration":clip.duration,"tracks":clip.tracks.size(),"bones":{}}
		for bone in ["head","hips","leftUpperArm","rightUpperArm"]:
			if not clip.tracks.has(bone): continue
			var tr = clip.tracks[bone]
			var peak = 0.0
			for i in range(1,tr.times.size()):
				var dt = tr.times[i]-tr.times[i-1]
				if dt > 0.00001: peak = max(peak,rad_to_deg(tr.rotations[i-1].angle_to(tr.rotations[i]))/dt)
			row.bones[bone] = {"peak_keyframe_speed_deg_s":peak,"loop_seam_deg":rad_to_deg(tr.rotations[0].angle_to(tr.rotations[-1]))}
		result.append(row)
	var out = FileAccess.open(base.path_join("loader-results.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit()
