extends SceneTree
var failed := 0
var passed := 0
func check(value: bool, label: String) -> void:
	if value:passed+=1
	else:failed+=1;push_error(label)
func _initialize() -> void:
	var walking := Rect2(100,100,140,300)
	var idle := Rect2(110,100,120,300)
	var cursor := Vector2(65,200)
	var no_handle := Rect2()
	check(AutonomyBridge.pointer_near(cursor,walking,no_handle,false),"unchanged four-argument API enters hover")
	check(not AutonomyBridge.pointer_near(cursor,idle,no_handle,false),"fixture shrinks across old hover threshold")
	var near := true
	for frame in 120:
		var pose := walking if frame%2==0 else idle
		near=AutonomyBridge.pointer_near(cursor,pose,no_handle,false,near)
	check(near,"stationary cursor keeps local idle priority through pose jitter")
	check(not AutonomyBridge.pointer_near(Vector2(45,200),idle,no_handle,false,true),"cursor beyond wider exit releases hover")
	check(not AutonomyBridge.pointer_near(cursor,idle,no_handle,false,false),"wider exit does not enlarge fresh entry zone")
	check(AutonomyBridge.pointer_near(Vector2.INF,idle,no_handle,true,true),"manual drag always holds even without finite pointer")
	check(not AutonomyBridge.pointer_near(Vector2.INF,idle,no_handle,false,true),"invalid non-drag pointer cannot stick hover")
	var handle := Rect2(400,100,20,20)
	check(AutonomyBridge.pointer_near(Vector2(375,110),idle,handle,false,true),"handle uses matching exit hysteresis")
	check(not AutonomyBridge.pointer_near(Vector2(375,110),idle,handle,false,false),"handle original entry margin preserved")
	print(JSON.stringify({"passed":passed,"failed":failed,"scope":"hover geometry and backwards compatible API; native arbitration verified separately"}))
	quit(1 if failed else 0)
