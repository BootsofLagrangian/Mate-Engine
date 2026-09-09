extends SceneTree
var failures:Array[String]=[]
var passed:=0
func check(ok:bool,label:String)->void:
	if ok:passed+=1
	else:failures.append(label)
func _initialize()->void:
	var model=load("res://scripts/fly_curiosity_circuit.gd").new()
	var fixture:={"nodes":[{},{},{},{}],"edges":[[0,2,5],[1,3,5]],"inputs":{"left":[0],"right":[1]},"outputs":{"left":[2],"right":[3]},"provenance":{"scope":"synthetic validation fixture only"}}
	check(model.configure(fixture),"valid signed sparse circuit")
	var left:Dictionary=model.step({"left":1.0,"right":0.0})
	check(float(left.turn)<-.9 and float(left.readout.left)>0.0,"actual edges carry left input to output")
	model.reset()
	var right:Dictionary=model.step({"left":0.0,"right":1.0})
	check(float(right.turn)>.9,"bilateral stimulation changes direction")
	model.reset()
	var silent:Dictionary=model.step({"left":0.0,"right":0.0})
	check(float(silent.forward)==0.0 and float(silent.turn)==0.0,"no stimulation does not invent motor output")
	fixture.edges=[[0,2,-5],[1,3,5]]
	check(model.configure(fixture),"inhibitory edge accepted")
	check(float(model.step({"left":1.0}).readout.left)==0.0,"inhibitory sign is retained")
	fixture.edges=[[0,8,1]]
	check(not model.configure(fixture) and not model.ready,"invalid index rejects circuit")
	fixture.edges=[[0,2,NAN]]
	check(not model.configure(fixture),"nonfinite weights rejected")
	print("FLY_CIRCUIT ",passed," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
