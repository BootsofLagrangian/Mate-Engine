extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var failures:=0
	var report:=[]
	var bank:=MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			for mode in ["clip_clip","clip_idle","walk_upper_gesture","clip_end"]:
				var a:=VrmAvatar.new();root.add_child(a)
				a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.set_bank(bank)
				p.idle_enabled=false;p.gaze_enabled=false
				for name in ["authored_wave","authored_bow","uma_walk"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
				p.register_locomotion_clip("uma_walk",true)
				for frame in fps:p._process(1.0/fps)
				p.play_vrma("uma_walk",1,true) if mode=="walk_upper_gesture" else p.play_vrma("authored_wave")
				var event_frame:int=fps*2 if mode=="walk_upper_gesture" else int(fps*0.8)
				if mode=="clip_end":event_frame=int(ceil(p.vrma_clips.authored_wave.duration*fps))
				var prior:={};var previous_speed:={};var rows:=[]
				for frame in fps*4:
					if frame==fps and mode=="walk_upper_gesture":p.play_upper_body_gesture("wave")
					if frame==event_frame:
						if mode=="clip_end":pass
						elif mode=="clip_clip":p.play_vrma("authored_bow")
						elif mode=="clip_idle":p.stop_gesture()
						else:
							p.finish_locomotion();p.play_gesture("bow")
					p._process(1.0/fps)
					if mode=="walk_upper_gesture" and frame<fps*2:p.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
					var row:={"time":float(frame)/fps,"upper_active":p.is_upper_body_active(),"gesture":p.current_gesture()}
					for bone in ["head","rightHand","leftLowerLeg"]:
						var q:=a.skeleton.get_bone_global_pose(a.bone_index[bone]).basis.orthonormalized().get_rotation_quaternion()
						if prior.has(bone):
							var change:Quaternion=(prior[bone].inverse()*q).normalized()
							var speed:float=rad_to_deg(2*atan2(Vector3(change.x,change.y,change.z).length(),absf(change.w)))*fps
							row[bone+"_speed"]=speed
							row[bone+"_speed_change"]=absf(speed-float(previous_speed.get(bone,speed)))
							previous_speed[bone]=speed
						prior[bone]=q
					if frame>=event_frame-3 and frame<=event_frame+fps:rows.append(row)
				# Regression guards for these selected source edges, not universal
				# human-motion limits. The old arm cap lost >25% on first frame.
				if mode != "clip_end":
					var outgoing:float=rows[2].get("rightHand_speed",0)
					var incoming:float=rows[3].get("rightHand_speed",0)
					if outgoing>50 and (incoming<outgoing*0.85 or incoming>outgoing*1.2):failures+=1
					if rows[3].upper_active:failures+=1
				else:
					var last_source:Dictionary={}
					for row in rows:
						if row.gesture=="authored_wave":last_source=row
					if last_source.is_empty() or float(last_source.get("rightHand_speed",INF))>(30 if fps==30 else 12):failures+=1
				print("SEAM ",character," ",fps," ",mode," boundary=",rows.slice(0,7)," final_upper=",p.is_upper_body_active())
				report.append({"character":character,"fps":fps,"mode":mode,"frames":rows})
				p.free();a.free()
	var path:=OS.get_environment("SEAM_REPORT")
	if not path.is_empty():FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report))
	print("MOTION_SEAM_FAILURES=",failures)
	quit(1 if failures else 0)
