extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		for size in ([0.6] if OS.get_environment("WALK_QUICK") == "1" else [0.6,1.0]):
			for speed in ([80.0] if OS.get_environment("WALK_QUICK") == "1" else [40.0,80.0,140.0]):
				avatar.scale = Vector3.ONE*size
				avatar.rotation.y = deg_to_rad(82)
				var motion := MotionPlayer.new()
				root.add_child(motion)
				motion.set_process(false)
				motion.avatar = avatar
				motion.idle_enabled = false
				motion.gaze_enabled = false
				motion.load_vrma("walk",OS.get_environment("WALK_CANDIDATE") if not OS.get_environment("WALK_CANDIDATE").is_empty() else ProjectSettings.globalize_path("res://../assets/research/walking-candidates/uma_homewalk_direct.vrma"))
				motion.register_locomotion_clip("walk",true)
				motion.play_vrma("walk",1,true)
				motion.set_locomotion_direction(Vector2(speed,0))
				var desktop_x := 0.0
				var prior := {}
				var max_slide := 0.0
				var max_clamp := 0.0
				var lower_sum := 0.0
				var lower_max := 0.0
				var measured := 0
				for frame in 720:
					motion._process(1.0/60)
					var travel: float = speed/60
					desktop_x += travel
					motion.set_locomotion_sample(Vector2(speed,0),Vector2(travel,0),300*size,true)
					for side in motion.gait.diagnostics:
						var d: Dictionary = motion.gait.diagnostics[side]
						var foot := avatar.bone_global_position(side+"Foot")
						var screen := Vector2(desktop_x+foot.x*300,-foot.y*300)
						if frame > 120 and d.stance and prior.has(side) and bool(prior[side].stance) and float(d.phase) >= float(prior[side].phase):
							max_slide = maxf(max_slide,screen.distance_to(prior[side].point))
							max_clamp = maxf(max_clamp,float(d.reach_clamp))
							lower_sum += float(d.pelvis_lowering)
							lower_max = maxf(lower_max,float(d.pelvis_lowering))
							measured += 1
						prior[side] = {"point":screen,"stance":d.stance,"phase":d.phase}
				print("GAIT ",character," scale=",size," speed=",speed," measured=",measured," max_desktop_slide_px=",max_slide," max_reach_clamp_m=",max_clamp," stride=",motion.gait.stride," mean_pelvis_lower_m=",lower_sum/maxi(1,measured)," max_pelvis_lower_m=",lower_max)
				if measured < 100 or max_slide > 1.0:
					failures += 1
				motion.free()
		avatar.free()
	print("GAIT_FAILURES=",failures)
	quit(1 if failures else 0)
