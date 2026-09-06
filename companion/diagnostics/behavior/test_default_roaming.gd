extends SceneTree
func _initialize():
	var d:=BehaviorDirector.new()
	var moves:=0
	var next_arrival:=-1.0
	var target:=""
	var previous:=-100.0
	var minimum_gap:=INF
	for frame in 9600:
		var time:=float(frame)*.1
		if frame%100==0:
			d.observe_interest("support:left",Vector2(300,900),.5,30,"surface","왼쪽")
			d.observe_interest("support:right",Vector2(1300,900),.5,30,"surface","오른쪽")
		if next_arrival>=0 and time>=next_arrival:
			d.navigation_result(target,"arrived");next_arrival=-1
		var out:Dictionary=d.tick(.1,{"can_move":next_arrival<0,"autonomy_state":"walk" if next_arrival>=0 else "rest"})
		if out.action.get("type","")=="move_interest":
			moves+=1;minimum_gap=minf(minimum_gap,time-previous);previous=time
			target=out.action.target_id
			d.resolve_intent(out.action.id,"started")
			next_arrival=time+8
	var passed:=moves>=3 and moves<=25 and minimum_gap>=35
	print("Default support-only 16-minute roaming: moves=",moves," minimum_gap_s=",minimum_gap," pass=",passed)
	quit(0 if passed else 1)
