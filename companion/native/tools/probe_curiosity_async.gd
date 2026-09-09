extends SceneTree
var failures:Array[String]=[]
var passed:=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1
	else:failures.append(label)
func fixture()->Dictionary:return {"nodes":[{},{},{},{}],"edges":[[0,2,5],[1,3,5]],"inputs":{"left":[0],"right":[1]},"outputs":{"left":[2],"right":[3]}}
func _initialize()->void:call_deferred("run")
func settle(model)->void:
	while model.pending() and not WorkerThreadPool.is_task_completed(model._task_id):await process_frame
func run()->void:
	var model=load("res://scripts/fly_curiosity_circuit.gd").new()
	model.configure(fixture());model.begin({"left":1.0})
	check(not model.configure(fixture()),"reconfiguration cannot mutate a pending worker graph")
	await settle(model)
	var drive:Dictionary=model.poll()
	check(float(drive.get("turn",0.0))<-.9 and not model.pending(),"completed worker transfers actual circuit output")
	model.begin({"right":1.0});model.reset();await settle(model)
	check(model.poll().is_empty() and model.state==PackedFloat64Array([0,0,0,0]),"reset invalidates both stale drive and recurrent state")
	var d:=BehaviorDirector.new();d.set_character("test");d.fly_circuit.configure(fixture());d.configure_curiosity(true,true)
	var context:={"character_id":"test","can_move":true,"actor_point":Vector2(400,500),"autonomy_state":"rest"}
	d.observe_interest("left",Vector2(100,500),.65,120,"surface");d.observe_interest("right",Vector2(700,500),.65,120,"surface")
	d.tick(12.1,context);check(d.fly_circuit.pending(),"director schedules asynchronous circuit decision")
	await settle(d.fly_circuit)
	context.panel_open=true;d.tick(8.0,context);context.panel_open=false
	d.tick(.1,context)
	check(d.curiosity_decisions.is_empty() and d.fly_circuit.pending(),"old result after foreground interruption is rejected and recomputed")
	await settle(d.fly_circuit)
	d.tick(.1,context)
	check(d.curiosity_decisions.size()==1 and not str(d.curiosity_decisions[0].target_id).is_empty(),"fresh resumed result selects a production target")
	d.cancel_all("cancelled");d.fly_circuit.begin({"left":1.0});d.configure_curiosity(false,false);await settle(d.fly_circuit);d.configure_curiosity(false,false)
	check(not d.fly_circuit.pending() and d.fly_circuit.state==PackedFloat64Array([0,0,0,0]),"mode switch discards optional worker state and reaps completion")
	print("CURIOSITY_ASYNC ",passed," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
