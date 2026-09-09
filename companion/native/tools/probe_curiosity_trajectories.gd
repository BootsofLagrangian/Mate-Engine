extends SceneTree
## Paired policy-only kinematic experiment. Does NOT validate native animation,
## collision or monitor APIs. Native trajectory probe supplies that evidence.
func arg(key:String)->String:
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]==key:return args[i+1]
	return ""
func _initialize()->void:
	var destination:=arg("--output")
	if destination.is_empty():quit(2);return
	var circuit_path:=arg("--circuit")
	var runs:Array=[]
	for trial in 12:
		for mode in ["baseline","curiosity","fly","zero_edges"]:
			var d:=BehaviorDirector.new()
			d.set_character("experiment")
			d.curiosity.seed=173+trial
			d.curiosity_enabled=mode!="baseline"
			d.fly_async=false # deterministic policy-only simulation, no real-time scheduling
			d.fly_enabled=mode in ["fly","zero_edges"]
			if d.fly_enabled and not d.fly_circuit.load_file(circuit_path):push_error("actual circuit unavailable");quit(2);return
			if mode=="zero_edges":
				for edge in d.fly_circuit.edges:edge[2]=0.0
			var position:=Vector2(1120+trial*17,1392)
			var target:=Vector2.INF
			var active_id:=""
			var samples:Array=[]
			var decisions:Array=[]
			var outcomes:Array=[]
			var director_ref:WeakRef=weakref(d)
			d.intent_outcome.connect(func(id:String,outcome:String):outcomes.append({"id":id,"outcome":outcome,"time":director_ref.get_ref()._time}))
			var last_decision_time:=-1.0
			var timings:Array=[]
			for frame in 6000:
				var t:=frame*.1
				for i in 7:
					d.observe_interest("surface:%d"%i,Vector2(180+i*330,1392),.65,30,"surface")
				if target.is_finite():
					position=position.move_toward(target,7.5)
					if position.distance_to(target)<.001:
						target=Vector2.INF
						d.resolve_intent(active_id,"arrived")
				var before:=Time.get_ticks_usec()
				var result:Dictionary=d.tick(.1,{"character_id":"experiment","can_move":not target.is_finite(),"actor_point":position,"autonomy_state":"walk" if target.is_finite() else "rest"})
				timings.append(Time.get_ticks_usec()-before)
				var action:Dictionary=result.action
				if action.get("type","")=="move_interest":
					target=action.point;active_id=action.id;d.resolve_intent(active_id,"started")
				if action.get("type","")=="cancel_move":target=Vector2.INF
				if not d.curiosity_decisions.is_empty() and float(d.curiosity_decisions[-1].time)>last_decision_time:
					var decision:Dictionary=d.curiosity_decisions[-1].duplicate(true)
					last_decision_time=decision.time;decisions.append(decision)
				if frame%5==0:samples.append({"t_s":t,"foot_px":[position.x,position.y],"moving":target.is_finite()})
			timings.sort()
			runs.append({"trial":trial,"mode":mode,"duration_s":600,"trajectory":samples,"decisions":decisions,"outcomes":outcomes,"tick_us_p99":timings[int(timings.size()*.99)],"tick_us_max":timings[-1],"circuit":d.fly_circuit.diagnostics.duplicate(true)})
	var f:=FileAccess.open(destination,FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"paired policy-only deterministic kinematics; fixed 75px/s, no animation/collision/native window simulation","runs":runs},"  "))
	print("CURIOSITY_TRAJECTORIES runs=",runs.size())
	quit()
