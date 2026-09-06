extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var failures:=0
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var a:=VrmAvatar.new();root.add_child(a)
			a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"));a.scale=Vector3.ONE*0.6
			var p:=MotionPlayer.new();root.add_child(p);p.avatar=a;p.set_process(false);p.idle_enabled=false;p.gaze_enabled=false
			p.load_vrma("uma_walk",ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma"));p.register_locomotion_clip("uma_walk",true)
			p.load_vrma("sit_enter",ProjectSettings.globalize_path("res://../assets/motions/sit_enter.vrma"));p.register_seated_transition("enter","sit_enter")
			if fps==30:print("SOURCE_DELTA ",character," ",p.seated_transition_requirements("enter"))
			p._process(1.0/fps)
			if not p.prepare_scene_locomotion(0):failures+=1
			p.play_vrma("uma_walk",1,true)
			var prior:={};var maximum:=0.0;var samples:=0
			for frame in fps*6:
				var heading:float=float(frame)/fps*0.2
				p.update_scene_heading(heading)
				p._process(1.0/fps)
				var velocity:=Basis(Vector3.UP,heading)*Vector3(0,0,0.25)
				var displacement:Vector3=velocity/fps
				a.global_position+=displacement
				p.set_scene_locomotion_sample(velocity,displacement,heading)
				for side in p.gait.diagnostics:
					var d:Dictionary=p.gait.diagnostics[side];var foot:=a.bone_global_position(side+"Foot")
					if frame>fps and d.stance and prior.has(side) and prior[side].stance and d.phase>=prior[side].phase:
						maximum=maxf(maximum,foot.distance_to(prior[side].point));samples+=1
					prior[side]={"point":foot,"stance":d.stance,"phase":d.phase}
			if maximum>0.005 or samples<fps or p.gait.phase_distance<1 or not p._travel_intent:failures+=1
			print("SCENE ",character," fps=",fps," plant_error_m=",maximum," samples=",samples," phase_distance=",p.gait.phase_distance)
			p.free();a.free()
	print("SCENE_MOTION_FAILURES=",failures)
	quit(1 if failures else 0)
