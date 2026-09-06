extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			for yaw in [0.0,0.8]:
				var baseline: Array = []
				for overlay in [false,true]:
					var avatar := VrmAvatar.new()
					root.add_child(avatar)
					avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
					avatar.rotation.y = yaw+deg_to_rad(82)
					var player := MotionPlayer.new()
					root.add_child(player)
					player.set_process(false)
					player.avatar=avatar
					player.set_bank(bank)
					player.view_yaw_radians=yaw
					player.idle_enabled=false
					player.gaze_enabled=false
					player.load_vrma("uma_walk",ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma"))
					player.register_locomotion_clip("uma_walk",true)
					player.play_vrma("uma_walk",1,true)
					var max_leg_error:=0.0
					var max_hand_change:=0.0
					var max_slide:=0.0
					var prior:={}
					var distance:=0.0
					for frame in fps*7:
						if frame==fps and overlay: check(player.play_upper_body_gesture("wave"),"wave accepted")
						player._process(1.0/fps)
						player.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
						distance+=80.0/fps
						var points:={}
						for bone in ["hips","leftFoot","rightFoot","rightHand"]:points[bone]=avatar.bone_global_position(bone)
						if overlay:
							for bone in ["hips","leftFoot","rightFoot"]:max_leg_error=maxf(max_leg_error,points[bone].distance_to(baseline[frame][bone]))
							max_hand_change=maxf(max_hand_change,points.rightHand.distance_to(baseline[frame].rightHand))
						else:baseline.append(points)
						for side in player.gait.diagnostics:
							var d:Dictionary=player.gait.diagnostics[side]
							var camera_point:Vector3=Basis(Vector3.UP,-yaw)*points[side+"Foot"]
							var screen:=Vector2(camera_point.x*300+distance,-camera_point.y*300)
							if frame>fps and d.stance and prior.has(side) and prior[side].stance and d.phase>=prior[side].phase:max_slide=maxf(max_slide,screen.distance_to(prior[side].point))
							prior[side]={"stance":d.stance,"phase":d.phase,"point":screen}
						check(player.current_gesture()=="uma_walk","overlay replaced locomotion")
					if overlay:
						check(max_leg_error<0.00001,"lower-body changed")
						check(max_hand_change>0.10,"wave did not articulate")
						check(not player.is_upper_body_active(),"finite layer leaked")
						player.set_upper_body_contact_lock(true)
						check(not player.play_upper_body_gesture("wave",1,1,1,["arms"]),"locked arms accepted")
						check(player.play_upper_body_gesture("nod",1,1,1,["head"]),"locked head rejected")
						player.reset_all()
						check(not player.is_upper_body_active(),"reset leaked layer")
					check(max_slide<1.0,"camera relative plant drift")
					print("OVERLAY ",character," fps=",fps," yaw=",yaw," enabled=",overlay," leg_error=",max_leg_error," hand_change=",max_hand_change," slide_px=",max_slide)
					player.free()
					avatar.free()
	print("OVERLAY_FAILURES=",failures)
	quit(1 if failures else 0)
