extends SceneTree
class Director extends RefCounted:
	func has_user_intent()->bool:return false
class Mic extends RefCounted:
	func is_recording()->bool:return false
class Host extends RefCounted:
	var session:Dictionary={"character_id":"fixture"}
	var living:Dictionary={"enabled":true,"director":Director.new()}
	var autonomy:Dictionary={"enabled":true,"surface_mode":true}
	var motion:Dictionary={"_preview":false,"_custom_motion":false,"floor_rest":{"active":true,"phase":"idle"}}
	var mic:=Mic.new()
	var _drag_active:=false
	var stand_requests:=0
	func body_action_can_continue()->bool:return false
	func body_dialogue_busy(_hold:bool=false)->bool:return false
	func _stand_up(_message:String)->void:
		stand_requests+=1
		motion.floor_rest.phase="exit"
class Objects extends DesktopObjectsHost:
	var dispatches:Array=[]
	func is_dragging()->bool:return false
	func _spatial_enabled()->bool:return false
	func _execute_command(command:Dictionary)->void:dispatches.append(command)
var failures:=0
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print(label," ",value)
	if not value:failures+=1
func run()->void:
	for verb in ["use","sit","inspect","place"]:
		var host:=Host.new()
		var objects:=Objects.new();objects.host=host
		var command:Dictionary={"id":"fixture:"+verb,"character":"fixture","source":"user","expires":30.0,"intent":{"kind":"furniture","verb":verb,"object_type":"computer"}}
		objects._pending_command=command.duplicate(true)
		objects._tick_command()
		if verb=="place":check(objects.dispatches.size()==1 and host.stand_requests==0,"placing furniture does not force floor-rest exit")
		else:
			check(objects.dispatches.is_empty() and objects._pending_command==command and host.motion.floor_rest.phase=="exit","physical action waits without dropping command: "+verb)
			objects._tick_command()
			check(objects.dispatches.is_empty() and objects._pending_command==command,"in-flight authored exit remains uninterrupted: "+verb)
			host.motion.floor_rest.active=false
			objects._tick_command()
			check(objects.dispatches.size()==1 and objects.dispatches[0]==command and objects._pending_command.is_empty(),"exact pending command dispatches once after exit: "+verb)
		objects.free()
	print("floor-rest command handoff failures=",failures)
	quit(1 if failures else 0)
