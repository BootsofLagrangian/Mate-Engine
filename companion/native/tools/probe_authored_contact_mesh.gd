extends SceneTree
var failures:=0
func _init() -> void:call_deferred("run")
func run() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var a:=VrmAvatar.new()
			root.add_child(a)
			a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
			var p:=MotionPlayer.new()
			root.add_child(p)
			p.set_process(false)
			p.avatar=a
			p.idle_enabled=false
			p.gaze_enabled=false
			var prefix:=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/")
			p.load_vrma("sit_enter",prefix+("uma-canonical/uma_sitdown01_s.vrma" if OS.get_environment("SEAT_UMA")=="1" else "quaternius_sit_down.vrma"))
			p.load_vrma("sit_exit",prefix+("uma-canonical/uma_sitdown01_e.vrma" if OS.get_environment("SEAT_UMA")=="1" else "quaternius_stand_up.vrma"))
			p.load_vrma("sit_idle",prefix+("uma-canonical/uma_sitdown01_loop.vrma" if OS.get_environment("SEAT_UMA")=="1" else "quaternius_seated_idle.vrma"))
			p.register_seated_transition("enter","sit_enter")
			p.register_seated_transition("exit","sit_exit")
			for frame in 60:p._process(1.0/fps)
			p.set_seated_floor(0.48)
			var geometry:=a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
			var delta:=Vector3(0,0.48-Vector3(geometry.anchor).y,0)
			for kind in ["enter","exit"]:
				var origin:=a.position
				var displacement:=delta if kind=="enter" else -delta
				var start_usec:=Time.get_ticks_usec()
				if not p.start_seated_transition(kind,displacement):failures+=1;continue
				var prep_ms:float=(Time.get_ticks_usec()-start_usec)/1000.0
				var angles:=[]
				var min_foot:=INF
				var min_mesh:=INF
				var worst:Dictionary={}
				for frame in int(ceil(p.seated_transition.duration*fps))+1:
					p._process(1.0/fps)
					var state:=p.seated_transition_state()
					a.position=origin+displacement*float(state.root_progress)
					var sk:=a.skeleton
					var hip:=a.bone_global_position("leftUpperLeg")
					var knee:=a.bone_global_position("leftLowerLeg")
					var foot:=a.bone_global_position("leftFoot")
					for candidate in p.authored_seated_feet.foot_vertices.left:
						var point:=Vector3.ZERO
						for bind in candidate.influences:point+=(sk.get_bone_global_pose(bind[0])*bind[1]*candidate.vertex)*bind[2]
						var actual_y:float=(sk.global_transform*(point/candidate.total)).y
						if actual_y<min_mesh:
							min_mesh=actual_y;worst={"time":state.time,"contact":p.authored_seated_feet.diagnostics.duplicate(true)}
					angles.append(rad_to_deg((knee-hip).angle_to(foot-knee)))
					var ankle_offset:=sk.get_bone_global_rest(a.bone_index.leftFoot).origin.y-float(a.sole_calibration.floor_y)
					min_foot=minf(min_foot,foot.y-ankle_offset)
					if not state.transition_bounds.size.is_finite():failures+=1
				if not p.seated_transition_state().finished:failures+=1
				if not p.finish_seated_transition():failures+=1
				for frame in 30:p._process(1.0/fps)
				var spread:float=angles.max()-angles.min()
				if spread<30:failures+=1
				if min_foot < -0.005:failures+=1
				print("SEAT ",character," fps=",fps," ",kind," knee_range=",spread," worst=",worst," min_mesh=",min_mesh," min_sole=",min_foot," prep_ms=",prep_ms," contact=",p.current_contact_pose())
			p.reset_all()
			if p.seated_transition.active:failures+=1
			p.free()
			a.free()
	print("AUTHORED_SEAT_FAILURES=",failures)
	quit(1 if failures else 0)
