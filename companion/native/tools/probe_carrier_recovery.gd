extends SceneTree
var failures:=0
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print(label," ",value)
	if not value:failures+=1
func run()->void:
	var scene:=DesktopObjectContactScene.new();root.add_child(scene)
	if not scene.configure("computer"):quit(2);return
	scene.set_seat_setup(.2,145)
	var objects:=DesktopObjectsHost.new()
	objects._contact_scene=scene
	objects._interaction={"chair_exit":false,"setup_plan":scene.seat_setup().duplicate(true),"chair_lift":1.0,"chair_steps":[{"kind":"roll_in"}],"chair_step":{}}
	check(objects._unwind_incoming_carrier("occupied_sweep_blocked"),"unchanged entry setup permits authored recovery")
	check(objects._interaction.chair_exit and objects._interaction.abort_reason=="occupied_sweep_blocked" and objects._interaction.chair_steps.size()==1 and objects._interaction.chair_steps[0].kind=="lower" and objects._interaction.chair_steps[0].lift==0,"recovery lowers feet before authored exit and retains failure outcome")
	check(not objects._unwind_incoming_carrier("again"),"recovery cannot recursively restart itself")
	objects._interaction.chair_exit=false
	scene.set_seat_setup(.3,145)
	check(not objects._unwind_incoming_carrier("blocked"),"changed chair position cannot reuse original exit")
	var path:=DesktopObjectsHost.chair_clearance_path(-4,.4)
	var slopes:=DesktopObjectsHost.chair_path_slopes(path)
	var bounded:=true
	for i in path.size()-1:
		var velocity:Vector2=(path[i+1]-path[i])*64
		bounded=bounded and absf(velocity.x)<=slopes.x+.0001 and absf(velocity.y)<=slopes.y+.0001
	check(bounded and slopes.x>1,"duration accounts for outward as well as inward velocity")
	objects._contact_scene=null
	objects.free();scene.free()
	quit(1 if failures else 0)
