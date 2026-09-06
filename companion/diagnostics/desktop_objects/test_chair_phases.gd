extends "test_host_objects.gd"
class CarrierMotion:
	extends FacingMotion
	var lift := 0.0
	var pose_ready := false
	var clears := 0
	func clear_seated_carrier(): lift=0.0;pose_ready=false;clears+=1
	func set_seated_carrier(value:float,_yaw:float)->bool:
		if value!=lift:pose_ready=false
		lift=value
		return true
	func seated_carrier_state()->Dictionary:return {"ready":pose_ready,"lift":lift}
	func render_pose():pose_ready=lift>=.999
	func seated_carrier_lift_envelope()->Dictionary:return {"fixture":true}
class PhaseObjects:
	extends Objects
	var committed := 0
	var exited := false
	func _fit_contact_view(_preserve=false)->bool:return true
	func _commit_carried_seat()->bool:committed+=1;return true
	func _admit_carrier_step(_step:Dictionary)->bool:return true
	func _admit_lift_envelope(_snapshot:Dictionary)->bool:return true
	func _carrier_step_valid(_step:Dictionary)->bool:return true
	func _refresh_adapters():pass
	func _start_authored_stand()->bool:exited=true;_interaction.stage="exiting";return true
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _push_autonomy_context():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	var old=h.motion;h.motion=CarrierMotion.new();h.add_child(h.motion);old.free()
	var objects=PhaseObjects.new();h.add_child(objects);h.objects.free();h.objects=objects;objects.host=h
	objects._contact_scene=DesktopObjectContactScene.new();h.add_child(objects._contact_scene)
	check(objects._contact_scene.configure("computer"),"real movable chair asset loads")
	objects._contact_id="obj_1";objects._contact_scale=.6
	var window=Furniture.new();objects.add_child(window);objects.windows.obj_1=window
	objects._interaction={"id":"obj_1","verb":"use","stage":"seating","setup_plan":{"pullout_local_m":.1,"yaw_delta_deg":-125.0}}
	objects._contact_scene.set_seat_setup(.1,-125)
	own_test_seat(h)
	h.motion.pose_ready=true;h.motion.lift=1
	objects._start_chair_steps(true,false)
	check(not h.motion.pose_ready and h.motion.clears==1,"carry phase clears stale prior readiness")
	var initial=objects._contact_scene.seat_setup()
	for i in 40:objects._tick_chair_steps(1.0/60)
	check(objects._contact_scene.seat_setup()==initial,"support cannot move before a fresh rendered lift pose")
	check(not objects._interaction.is_empty(),"one-frame readiness lag does not cancel")
	var moved:=false
	for i in 600:
		h.motion.render_pose()
		objects._tick_chair_steps(1.0/60)
		if objects._contact_scene.seat_setup()!=initial:moved=true
		if objects._interaction.get("stage")=="using":break
	check(moved and objects._interaction.stage=="using","lift swivel roll lower reaches finite working stage")
	check(objects._contact_scene.seat_setup().pullout_local_m==0 and objects._contact_scene.seat_setup().yaw_delta_deg==0,"working chair exactly returns to keyboard setup")
	check(objects.committed>100,"every carry frame commits shared seat attachment")
	check(h.motion.lift==0 and not h.motion.pose_ready,"lowered carrier ownership clears before keyboard use")
	check(objects.request_stand(),"normal stand queues reverse carrier phases")
	for i in 600:
		h.motion.render_pose();objects._tick_chair_steps(1.0/60)
		if objects.exited:break
	check(objects.exited,"reverse support motion completes before authored exit")
	check(absf(objects._contact_scene.seat_setup().pullout_local_m-.1)<.000001 and absf(objects._contact_scene.seat_setup().yaw_delta_deg+125)<.000001,"exit restores exact source staging chair configuration")
	check(DesktopObjectsHost.chair_ease(0)==0 and DesktopObjectsHost.chair_ease(1)==1,"finite interpolation has exact endpoints")
	objects._interaction.clear();objects._contact_scene.free();objects._contact_scene=null;objects._closed=true
	h.free()
	check(absf(absf(DesktopObjectsHost.chair_yaw(170,-170,.5))-180)<.00001,"chair crosses yaw boundary along admitted shortest path")
	print("Chair phases: %d checks, %d failures" %[checks,failures]);quit(1 if failures else 0)
