extends SceneTree
const Director = preload("res://scripts/behavior_director.gd")
const Autonomy = preload("res://scripts/desktop_autonomy.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	idle_test()
	intent_test()
	arbitration_test()
	navigation_test()
	departure_easing_test()
	heading_gate_test()
	navigation_budget_test()
	supersession_handoff_test()
	braking_emergency_test()
	handoff_character_cleanup_test()
	print("Behavior director: %d checks, %d failures" % [checks, failures])
	quit(1 if failures or checks < 100 else 0)
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func make_director():
	var d = Director.new()
	d.set_character("test")
	d.observe_interest("left", Vector2(200, 700), 0.5, 120, "surface", "left")
	d.observe_interest("right", Vector2(900, 700), 0.5, 120, "surface", "right")
	return d
func idle_test() -> void:
	var a = make_director()
	var b = make_director()
	var states := {}
	var seen_attention := {}
	var previous_attention := Vector2.INF
	var action_count := 0
	for i in 9600: #16 minutes; heartbeat renews persistent native points.
		for d in [a,b]:
			d.observe_interest("left", Vector2(200,700), 0.5,120,"surface","left")
			d.observe_interest("right",Vector2(900,700),0.5,120,"surface","right")
		var out: Dictionary = a.tick(0.1,{"can_move":false})
		var other: Dictionary = b.tick(0.1,{"can_move":false})
		check(out == other,"deterministic identical context stream")
		states[out.state] = int(states.get(out.state,0)) + 1
		if not out.action.is_empty():
			action_count += 1
		var attention: Vector2 = out.attention_point
		if attention.is_finite() and attention != previous_attention:
			var key := str(attention)
			check(float(i)*0.1-float(seen_attention.get(key,-INF)) >= a.ATTENTION_COOLDOWN-0.11,"attention repetition cooldown")
			seen_attention[key] = float(i)*0.1
		previous_attention = attention
	check(int(states.get("rest",0)) > 6000,"majority of16minuteidle stays quiet")
	check(int(states.get("curious",0)) > 100 and int(states.get("sleepy",0)) > 0,"idle includes curious dwell and occasional sleepy rest")
	check(action_count == 0,"no idle model/network actions; no movement when can_movefalse")
	check(a.interest_revision == 3,"unchanged heartbeat never bumps catalogue revision")
	print("IDLE16min distribution=",states)
func intent_test() -> void:
	var d = make_director()
	check(not d.request_intent("bad","move_to","missing").accepted,"unknown target rejected")
	check(not d.request_intent("old","rest","","llm",30,2,"other").accepted,"old character rejected")
	check(d.request_intent("t1:intent","inspect","left","llm",30,2).accepted,"inspect intent accepted")
	check(not d.request_intent("t1:intent","inspect","left","llm").accepted,"action/done intent ID dedup")
	var out: Dictionary = d.tick(0.1,{"can_move":true})
	check(out.action.type == "inspect" and out.attention_point == Vector2(200,700),"inspect orients at exact point without move")
	check(d.tick(0.5,{"can_move":true}).action.is_empty(),"inspect dispatched once")
	d.tick(2.0,{"can_move":true})
	check(d.drain_outcomes().back().outcome == "completed","inspect completes after actual dwell")
	check(not d.request_intent("t1:intent","inspect","left","llm").accepted,"completed intent remains deduplicated")
	d.request_intent("localmove","move_to","left","local")
	out = d.tick(0.3,{"can_move":true})
	check(out.action.type == "move_interest","local movement dispatches")
	d.resolve_intent("localmove","started")
	check(d.request_intent("userrest","rest","","user",30,2).accepted,"user rest accepted during local move")
	out = d.tick(0.1,{"can_move":true})
	check(out.action.type == "cancel_move","user preempts lower priority movement first")
	out = d.tick(0.3,{"can_move":true})
	check(out.action.type == "rest","user rest starts after cancellation")
	d.request_intent("llmwait","inspect","right","llm")
	check(d._active.id == "userrest","LLM cannot override active user")
	d.request_intent("usernew","inspect","left","user")
	check(d._active.is_empty(),"new user supersedes old user")
	d.tick(0.4,{"can_move":true})
	d.remove_interest("left")
	check(d._active.is_empty(),"point removal cancels active inspect immediately")
	check(d.drain_outcomes().back().outcome == "target_removed","point removal outcome explicit")
	d.request_intent("expires","move_to","right","user",0.2)
	d.tick(0.3,{"can_move":false,"autonomy_state":"settle"})
	check(d.drain_outcomes().back().outcome == "expired","queued TTL expires while waiting honestly")
	d.request_intent("move","move_to","right","user")
	out = d.tick(0.4,{"can_move":true})
	d.resolve_intent("move","started")
	out = d.tick(0.1,{"speaking":true,"pointer_point":Vector2(800,300),"dialogue_gesture_active":true})
	check(out.action.type == "cancel_move" and out.state == "speaking","speech preempts movement within one tick")
	check(out.strength == 0.0 and out.attention_point == Vector2(800,300),"gesture suppresses posture but preserves responsive gaze")
	d.tick(0.1,{})
	d.request_intent("switch","rest","","user")
	d.set_character("new")
	check(d._queue.is_empty() and d.interest_catalogue().is_empty(),"character switch clears intents and interests")
	check(not d.resolve_intent("move","arrived"),"late navigation result cannot complete stale intent")
func navigation_test() -> void:
	var a := Autonomy.new()
	var areas: Array[Rect2] = [Rect2(0,0,1920,1040)]
	a.configure_simulation(areas,Vector2.ZERO,Rect2(400,120,220,560))
	a.set_surface_mode(true)
	a.set_external_decisions(true)
	a.update_context(false,false,false,false,false)
	var world := {"monitors":[{"id":"test","x":0,"y":0,"width":1920,"height":1040}],"windows":[{"id":"shelf","x":300,"y":700,"width":1000,"height":300,"z":0}]}
	for i in 1200:
		a.set_world_snapshot(world)
		a.advance(1.0/60.0)
		if a.get_support_contact().get("attached",false):break
	check(a.can_request_move(),"native standing support ready")
	var stationary := a.position
	for i in 60*60:
		a.set_world_snapshot(world)
		a.advance(1.0/60.0)
	check(a.position == stationary,"external decision policy prevents autonomous lateral wander")
	a.observe_interest("high",Vector2(900,400),1,30)
	check(not a.move_to_interest("high") and a.last_request_outcome == "unreachable","different-height target never silently projected")
	var outcomes: Array = []
	a.navigation_finished.connect(func(id: String,result: String): outcomes.append([id,result]))
	a.observe_interest("right",Vector2(1000,700),1,30)
	check(a.move_to_interest("right") and a.state == "anticipate","move begins with anticipation")
	for i in 60:
		a.set_world_snapshot(world)
		a.advance(1.0/60.0)
	check(a.position == stationary and a.velocity == Vector2.ZERO,"pre-move look interval never translates window")
	a.cancel_target()
	check(outcomes == [["right","cancelled"]],"cancellation emits explicit outcome once")
	a.advance(3.0)
	a.observe_interest("here",a.position+a._locked_anchor,1,30)
	check(a.move_to_interest("here") and outcomes.back()==["here","arrived"],"already-at-point reports arrived synchronously")
	a.free()

func arbitration_test() -> void:
	var d = make_director()
	for i in d.MAX_INTENTS:
		check(d.request_intent("local%d" % i,"rest","","local").accepted,"bounded local queue accepts capacity")
	check(d.request_intent("urgent","rest","","user").accepted,"user can replace full lower-priority queue")
	check(d._queue.size() == 1 and d._queue[0].id == "urgent","superseded queue remains bounded")
	d.request_intent("newest","rest","","user")
	check(d._queue.size() == 1 and d._queue[0].id == "newest","new user replaces queued user")
	for label in ["listening","thinking","working"]:
		var context := {label:true}
		var out: Dictionary = d.tick(0.1,context)
		check(out.ambient == label,"foreground state uses matching subtle posture")
		context.preview_active = true
		check(d.tick(0.1,context).strength == 0.0,"preview suppresses foreground posture")
	d.configure_style({"idle_interval_s":999,"gaze_hold_s":-2,"response_delay_s":999,"curiosity":-1,"posture_strength":2})
	check(d.style.idle_interval_s == 120 and d.style.gaze_hold_s == 0.3 and d.style.response_delay_s == 2 and d.style.curiosity == 0 and d.style.posture_strength == 1,"style remains bounded")

func departure_easing_test() -> void:
	var a := Autonomy.new()
	a.configure_simulation([Rect2(0,0,2400,1040)],Vector2.ZERO,Rect2(400,120,220,560))
	a.set_external_decisions(true)
	a.update_context(false,false,false,false,false)
	a.advance(3.0)
	a.observe_interest("first",Vector2(1800,400),1,120)
	check(a.move_to_interest("first"),"eased departure target accepted")
	a.advance(a.ANTICIPATION_SECONDS)
	var before := a.velocity
	a.advance(1.0/120.0)
	check(a.velocity.distance_to(before)*120.0 < 10.0,"first walking sample starts with gentle acceleration rather than full cap")
	for i in 60: a.advance(1.0/120.0)
	check(a.velocity.length() > 20.0,"gentle onset builds meaningful walking speed")
	a.cancel_target()
	a.advance(3.0)
	a.observe_interest("return",Vector2(550,400),1,120)
	check(a.move_to_interest("return"),"return target accepted after interruption")
	a.advance(a.ANTICIPATION_SECONDS)
	a.advance(1.0/120.0)
	check(a.velocity.length()*120.0 < 10.0,"each new departure resets ease after cancellation")
	a.free()

func heading_gate_test() -> void:
	var a := Autonomy.new()
	a.configure_simulation([Rect2(0,0,2400,1040)],Vector2.ZERO,Rect2(400,120,220,560))
	a.set_external_decisions(true)
	a.update_context(false,false,false,false,false)
	a.advance(3.0)
	var ready := [false]
	a.set_heading_ready_provider(func(): return ready[0])
	var outcomes: Array = []
	a.navigation_finished.connect(func(id,result): outcomes.append([id,result]))
	a.observe_interest("turn",Vector2(1800,400),1,120)
	a.move_to_interest("turn")
	var origin := a.position
	for i in 180: a.advance(1.0/60.0)
	check(a.state == "anticipate" and a.position == origin,"turn gate holds desktop beyond minimum anticipation")
	ready[0] = true
	a.advance(1.0/60.0)
	check(a.state == "walk" and a.position == origin,"readiness begins travel without catching up withheld translation")
	for i in 30: a.advance(1.0/60.0)
	check(a.position.distance_to(origin) > 1.0,"ready turn permits eased travel")
	a.cancel_target()
	a.advance(3.0)
	ready[0] = false
	a.observe_interest("never-ready",Vector2(1800,400),1,120)
	a.move_to_interest("never-ready")
	origin = a.position
	for i in 370: a.advance(1.0/60.0)
	check(a.position == origin and outcomes.back() == ["never-ready","heading_timeout"],"unready turn times out without sidestepping")
	a.advance(3.0)
	a.observe_interest("preempt-turn",Vector2(1800,400),1,120)
	a.move_to_interest("preempt-turn")
	a.advance(2.0)
	a.update_context(false,false,true,false,false)
	check(a.velocity == Vector2.ZERO and outcomes.back() == ["preempt-turn","interrupted"],"speech immediately preempts waiting turn")
	a.free()

func navigation_budget_test() -> void:
	var d = make_director()
	d.request_intent("cold-reply","move_to","right","llm",30.0)
	d.tick(28.0,{"can_move":false})
	var out: Dictionary = d.tick(0.1,{"can_move":true})
	check(out.action.type == "move_interest" and float(out.action.ttl) < 2.0,"queued freshness is preserved until late dispatch")
	check(d.resolve_intent("cold-reply","started"),"fresh accepted navigation starts once")
	var deadline: float = d._active.navigation_deadline
	d.tick(25.0,{"can_move":true,"autonomy_state":"walk"})
	check(d._active.get("id","") == "cold-reply","accepted travel survives original30s command freshness")
	check(d.resolve_intent("cold-reply","started") and d._active.navigation_deadline == deadline,"duplicate started acknowledgment cannot extend completion budget")
	check(not d.resolve_intent("cold-reply","blocked"),"started navigation cannot requeue and refresh its clock")
	check(d.navigation_result("right","arrived"),"late but bounded native arrival completes honestly")
	check(d.drain_outcomes().back().outcome == "arrived","arrival outcome retained after queue TTL passes")
	var stuck = make_director()
	stuck.request_intent("stuck","move_to","right","user",30.0)
	stuck.tick(0.1,{"can_move":true})
	stuck.resolve_intent("stuck","started")
	for i in 44:
		stuck.tick(1.0,{"autonomy_state":"walk"})
		stuck.resolve_intent("stuck","started")
	out = stuck.tick(1.1,{"autonomy_state":"walk"})
	check(stuck._active.is_empty() and out.action.get("type","") == "cancel_move","completion budget expires even under repeated started acknowledgments")
	check(stuck.drain_outcomes().back().outcome == "expired","unreported native completion has bounded expiry outcome")
	var removed = make_director()
	removed.observe_interest("short",Vector2(900,700),1,0.5)
	removed.request_intent("stale-target","move_to","short","user",30)
	removed.tick(0.1,{"can_move":true})
	removed.resolve_intent("stale-target","started")
	out = removed.tick(0.5,{"autonomy_state":"walk"})
	check(removed._active.is_empty() and out.action.get("type","") == "cancel_move","target freshness still preempts accepted navigation budget")
	var queued = make_director()
	queued.request_intent("never-dispatched","move_to","right","user",30)
	queued.tick(30.1,{"can_move":false})
	check(not queued.resolve_intent("never-dispatched","started") and queued._queue.is_empty(),"stale queued command cannot receive completion extension")

func supported_handoff_pet():
	var a := Autonomy.new()
	a.configure_simulation([Rect2(0,0,1920,1040)],Vector2.ZERO,Rect2(400,120,220,560))
	a.set_surface_mode(true)
	a.set_external_decisions(true)
	a.update_context(false,false,false,false,false)
	var snapshot := {"monitors":[{"id":"test","x":0,"y":0,"width":1920,"height":1040}],"windows":[{"id":"shelf","x":300,"y":700,"width":1000,"height":300,"z":0}]}
	for i in 1200:
		a.set_world_snapshot(snapshot)
		a.advance(1.0/60.0)
		if a.can_request_move(): break
	return a

func supersession_handoff_test() -> void:
	var a = supported_handoff_pet()
	a.observe_interest("old",Vector2(1000,700),1,30)
	check(a.move_to_interest("old"),"handoff starts with accepted supported navigation")
	a.advance(a.ANTICIPATION_SECONDS+0.1)
	var origin: Vector2 = a.position
	var before_velocity: Vector2 = a.velocity
	a.cancel_target("superseded",Vector2(700,700))
	check(a.is_handoff_braking() and not a.can_request_move() and a.velocity == before_velocity and a.position == origin,"nonurgent supported replacement retains velocity and enters bounded braking")
	var braking_safe := true
	for i in 120:
		var previous: Vector2 = a.velocity
		a.advance(1.0/120.0)
		braking_safe = braking_safe and a.velocity.distance_to(previous) <= a.acceleration/120.0+0.01 and a.is_origin_safe(a.position)
		if not a.is_handoff_braking(): break
	check(braking_safe and a.can_request_move() and a.velocity == Vector2.ZERO,"braking respects acceleration and safety then releases replacement without settle")
	origin = a.position
	a.set_heading_ready_provider(func(): return false)
	a.observe_interest("new",Vector2(700,700),1,30)
	check(a.move_to_interest("new") and a.state == "anticipate","replacement immediately enters its own anticipation")
	a.advance(1.5)
	check(a.position == origin and a.state == "anticipate","handoff preserves minimum anticipation and heading readiness")
	a.free()
	for mode in ["ordinary", "other_height", "off_surface", "pointer", "voice", "no_active"]:
		a = supported_handoff_pet()
		if mode != "no_active":
			a.observe_interest("old",Vector2(1000,700),1,30)
			a.move_to_interest("old")
		if mode == "pointer": a.set_pointer_interaction(true)
		if mode == "voice": a.update_context(false,false,true,false,false)
		var point := Vector2(700,400) if mode == "other_height" else (Vector2(1900,700) if mode == "off_surface" else Vector2(700,700))
		a.cancel_target("cancelled" if mode == "ordinary" else "superseded",point)
		check(a._settle_until > a._time and not a.can_request_move(),"normal settle retained for " + mode)
		a.free()
	var d = make_director()
	d.request_intent("old","move_to","right","user")
	d.tick(0.1,{"can_move":true})
	d.resolve_intent("old","started")
	d.request_intent("replacement","move_to","left","user")
	var out: Dictionary = d.tick(0.1,{"can_move":true})
	check(out.action.get("replacement_point",Vector2.INF) == Vector2(200,700),"director supplies current validated replacement point")
	d.tick(0.3,{"can_move":true})
	d.resolve_intent("replacement","started")
	d.request_intent("replace-again","move_to","right","user")
	d.request_intent("actually-rest","rest","","user")
	out = d.tick(0.1,{"can_move":true})
	check(not out.action.has("replacement_point"),"newer rest request removes superseded movement handoff")
	var expired = make_director()
	expired.request_intent("old","move_to","right","user")
	expired.tick(0.1,{"can_move":true})
	expired.resolve_intent("old","started")
	expired.request_intent("new","move_to","left","user",0.05)
	out = expired.tick(0.1,{"can_move":true})
	check(not out.action.has("replacement_point"),"expired replacement never bypasses cancellation settle")

func braking_emergency_test() -> void:
	for reason in ["stop","voice","pointer","drag"]:
		var a = supported_handoff_pet()
		a.observe_interest("old",Vector2(1000,700),1,30)
		a.move_to_interest("old")
		a.advance(a.ANTICIPATION_SECONDS)
		for i in 60: a.advance(1.0/60.0)
		a.cancel_target("superseded",Vector2(700,700))
		check(a.is_handoff_braking(),"emergency fixture is actually braking")
		var origin: Vector2 = a.position
		match reason:
			"stop": a.cancel_target()
			"voice": a.update_context(false,false,true,false,false)
			"pointer": a.set_pointer_interaction(true)
			"drag": a.update_context(false,false,false,true,false)
		a.advance(0.1)
		check(not a.is_handoff_braking() and a.velocity == Vector2.ZERO and a.position == origin,"urgent " + reason + " interrupts braking immediately")
		a.free()
	var edge = supported_handoff_pet()
	edge.observe_interest("old",Vector2(1000,700),1,30)
	edge.move_to_interest("old")
	var span: Vector2 = edge._surface_origin_span(edge._support,edge._locked_anchor)
	edge.position.x = span.y-0.1
	edge.velocity = Vector2(75,0)
	edge.cancel_target("superseded",Vector2(700,700))
	check(not edge.is_handoff_braking() and edge.velocity == Vector2.ZERO and not edge.can_request_move(),"unsafe stopping distance falls back to immediate stop and normal settle")
	edge.free()
	var d = make_director()
	d.request_intent("old","move_to","right","user")
	d.tick(0.1,{"can_move":true})
	d.resolve_intent("old","started")
	d.request_intent("new","move_to","left","user",0.2)
	var out: Dictionary = d.tick(0.1,{"can_move":false,"autonomy_state":"walk"})
	check(out.action.has("replacement_point"),"fresh queued move authorizes braking handoff")
	out = d.tick(0.2,{"can_move":false,"autonomy_state":"walk"})
	check(out.action.get("type","") == "cancel_move" and out.action.get("reason","") == "replacement_invalidated","queued replacement expiry aborts in-progress braking")

func handoff_character_cleanup_test() -> void:
	var d = make_director()
	d.request_intent("old","move_to","right","user")
	d.tick(0.1,{"can_move":true})
	d.resolve_intent("old","started")
	d.request_intent("new","move_to","left","user")
	d.tick(0.1,{"can_move":false,"autonomy_state":"walk"})
	check(d._handoff_queue_id == "new","character-switch fixture has pending braking handoff")
	d.set_character("other-character")
	var out: Dictionary = d.tick(0.1,{"can_move":false})
	check(d._handoff_queue_id.is_empty() and out.action.is_empty(),"new character never emits stale replacement cancellation")
