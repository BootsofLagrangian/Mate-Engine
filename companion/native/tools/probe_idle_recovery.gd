extends SceneTree
const Recovery = preload("../scripts/idle_recovery.gd")
class FakeMotion:
	extends RefCounted
	var brakes := 0
	func cancel_heading() -> void: brakes += 1
class FakeHost:
	extends RefCounted
	var motion := FakeMotion.new()
var passed := 0
var failed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1
	print("%s %s" % ["PASS" if value else "FAIL",label])
func _initialize() -> void:
	var r = Recovery.new()
	check(r.tick(1.0,{}).is_empty(),"No unsolicited return while idle")
	r.queue("work_completed")
	check(r.tick(0.6,{}).get("turn",false)==false,"Pause before returning")
	r.tick(0.1,{})
	check(r.phase=="look","Gaze precedes body")
	check(not r.tick(0.3,{}).get("turn",false),"Gaze anticipation is not immediate swivel")
	check(r.tick(0.2,{}).get("turn",false),"One grounded heading request")
	check(not r.tick(0.1,{}).get("turn",false),"Heading is not reset every frame")
	check(r.tick(0.1,{"heading_ready":true}).get("settle",false),"Waits for turn completion before settled idle")
	check(r.tick(1.5,{}).get("completed",false) and not r.active(),"One-shot releases back to normal idle")
	r.queue("work_completed")
	r.tick(0.8,{})
	r.tick(0.5,{})
	var result: Dictionary = r.tick(0.1,{"superseded":true})
	check(not r.active() and not result.get("brake",false),"New action owns heading; recovery never brakes it")
	r.queue("work_completed")
	r.tick(0.8,{})
	r.tick(0.5,{})
	result = r.tick(0.1,{"busy":true})
	check(result.get("brake",false) and r.phase=="waiting","Speech brakes only the owned return and defers it")
	check(not r.tick(0.5,{"busy":true}).get("brake",false),"Speech does not repeatedly brake")
	check(not r.tick(0.3,{}).get("look",false),"Fresh anticipation after speech")
	r.tick(0.4,{})
	check(r.phase=="look","Pending return resumes after speech")
	r.queue("work_completed")
	r.tick(17.0,{"busy":true})
	check(not r.active(),"Stale returns expire during long conversation")
	r.queue("work_completed")
	r.clear()
	check(not r.active() and r.tick(10.0,{}).is_empty(),"Cancel clears deferred work")
	r.queue("work_completed")
	r.tick(NAN,{})
	check(is_zero_approx(r.age),"Invalid frame time cannot corrupt state")
	var living = preload("../scripts/living_behavior.gd").new()
	living.host = FakeHost.new()
	living.queue_idle_recovery("completed")
	living.director._queue.append({"id":"local:1","source":"local"})
	living._yield_recovery_to_explicit()
	check(living.idle_recovery.active(),"Local curiosity waits for recovery")
	living.director._queue.append({"id":"user:1","source":"user"})
	living._yield_recovery_to_explicit()
	check(not living.idle_recovery.active(),"Queued explicit intent revokes recovery before dispatch")
	living.queue_idle_recovery("completed")
	living.idle_recovery.owns_heading = true
	living._yield_recovery_to_explicit()
	check(living.host.motion.brakes==1,"Queued replacement brakes stale heading before dispatch")
	living.queue_idle_recovery("completed")
	living.idle_recovery.owns_heading = true
	living.director._active = {"id":"user:active","source":"user"}
	living._yield_recovery_to_explicit()
	check(living.host.motion.brakes==1,"Already active replacement retains its new heading")
	check(living.recovery_diagnostics.last_outcome=="cancelled","Cancellation is observable")
	living.free()
	print("Idle recovery: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
