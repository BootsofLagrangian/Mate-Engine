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
			for index in 6:
				d.observe_interest("scene:ground:"+str(index),Vector2(300+index*140,800-(index%2)*60),.55,30,"floor","Scene ground")
		if next_arrival>=0 and time>=next_arrival:
			d.navigation_result(target,"arrived");next_arrival=-1
		var out:Dictionary=d.tick(.1,{"can_move":next_arrival<0,"autonomy_state":"walk" if next_arrival>=0 else "rest"})
		if out.action.get("type","")=="move_interest":
			moves+=1;minimum_gap=minf(minimum_gap,time-previous);previous=time
			target=out.action.target_id
			d.resolve_intent(out.action.id,"started")
			next_arrival=time+8
	var passed:=moves>=3 and moves<=25 and minimum_gap>=35
	print("Default scene-ground 16-minute roaming: moves=",moves," minimum_gap_s=",minimum_gap," pass=",passed)
	quit(0 if passed else 1)
