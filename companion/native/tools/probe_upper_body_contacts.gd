extends SceneTree
var failures:=0
func _init() -> void: call_deferred("run")
func run() -> void:
	var bank:=MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for mode in ["authored_walk","seated_wave","locked_wave"]:
			var baseline:=[]
			for enabled in [false,true]:
				var avatar:=VrmAvatar.new()
				root.add_child(avatar)
				avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				var p:=MotionPlayer.new()
				root.add_child(p)
				p.set_process(false)
				p.avatar=avatar
				p.set_bank(bank)
				p.idle_enabled=false
				p.gaze_enabled=false
				p.load_vrma("uma_walk",ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma"))
				p.load_vrma("authored",ProjectSettings.globalize_path("res://../assets/motions/uma_cheval_idle_action.vrma"))
				p.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
				p.register_locomotion_clip("uma_walk",true)
				if mode=="authored_walk":
					avatar.rotation.y=deg_to_rad(82)
					p.play_vrma("uma_walk",1,true)
				else:p.start_contact_pose("sit")
				var leg_error:=0.0
				var arm_change:=0.0
				for frame in 360:
					if frame==60 and enabled:
						p.set_upper_body_contact_lock(mode=="locked_wave")
						if not p.play_upper_body_gesture("authored" if mode=="authored_walk" else "wave"):failures+=1
					p._process(1.0/60)
					if mode=="authored_walk":p.set_locomotion_sample(Vector2(80,0),Vector2(80.0/60,0),300,true)
					var poses:={}
					for bone in ["hips","leftUpperLeg","leftLowerLeg","leftFoot","rightUpperLeg","rightLowerLeg","rightFoot","rightUpperArm","rightLowerArm","rightHand"]:
						poses[bone]=avatar.skeleton.get_bone_pose_rotation(avatar.bone_index[bone])
					if enabled:
						for bone in poses:
							var error:float=Vector3(poses[bone].x,poses[bone].y,poses[bone].z).distance_to(Vector3(baseline[frame][bone].x,baseline[frame][bone].y,baseline[frame][bone].z))
							if p._bone_channel(bone) in ["legs","root"]:leg_error=maxf(leg_error,error)
							else:arm_change=maxf(arm_change,error)
					else:baseline.append(poses)
				if enabled:
					if leg_error>0.00001 or (mode=="locked_wave" and arm_change>0.00001) or (mode!="locked_wave" and arm_change<0.02):failures+=1
					print("CONTACT ",character," ",mode," leg_error=",leg_error," arm_change=",arm_change)
					p.reset_all()
					p.play_upper_body_gesture("wave",1,1,1,["arms"])
					p._process(0.1)
					p.set_upper_body_contact_lock(true)
					p.set_upper_body_contact_lock(false)
					for step in 40:p._process(1.0/60)
					if p.is_upper_body_active():failures+=1
					p.reset_all()
					if p.is_upper_body_active() or p.upper_body.contact_locked:failures+=1
				p.free()
				avatar.free()
	print("UPPER_CONTACT_FAILURES=",failures)
	quit(1 if failures else 0)
