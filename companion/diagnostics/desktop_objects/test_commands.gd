extends "test_host_objects.gd"
class Commands:
	extends Objects
	var creations := 0
	func add_object(type: String) -> String:
		creations += 1
		return store.add_object(type,Vector2i(200,300),screen_rects())
	func interact(id: String, verb: String) -> Dictionary:
		_interaction={"id":id,"verb":verb,"stage":"waiting","expires":_clock+65,"character":host.session.character_id}
		return {"accepted":true}
func command_fixture():
	var h = fixture()
	var old = h.objects
	var c := Commands.new()
	h.add_child(c)
	c.host=h
	c._settings=old._settings
	old.remove_child(c._settings)
	c.add_child(c._settings)
	c._last_character=h.session.character_id
	c._screen_provider=func(): return [Rect2i(-1920,0,1920,1040),Rect2i(0,0,1920,1040)]
	old.host=null
	old.free()
	h.objects=c
	return h
func _run() -> void:
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\nfunc _projected_anchors()->Dictionary:\n\treturn {"foot":Vector2(510,680),"sit":Vector2(510,500)}\n'
	if host_script.reload()!=OK: quit(1);return
	var h=command_fixture()
	var use={"kind":"furniture","object_type":"computer","verb":"use"}
	check(h.objects.request_intent(use,"llm","turn:intent").accepted,"fresh computer request queues without any furniture")
	check(not h.objects.request_intent(use,"llm","turn:intent").accepted,"action/done duplicate never creates twice")
	h.audio.voice_active=true
	h.objects._tick_command()
	check(h.objects.creations==0,"speaking defers all creation and placement")
	h.audio.voice_active=false
	h.objects._tick_command()
	check(h.objects.creations==1 and h.objects._interaction.verb=="use","quiet dispatch ensures computer and starts real host interaction entry")
	h.objects.cancel_commands("cancelled")
	check(h.objects._interaction.is_empty(),"explicit cancellation clears started furniture command")
	h.objects.request_intent(use,"llm","again:intent")
	h.objects._tick_command()
	check(h.objects.creations==1,"subsequent use reuses compatible existing furniture")
	h.objects.cancel_commands()
	var configure={"kind":"furniture","object_type":"computer","verb":"configure","target_id":"object:obj_1","yaw_deg":45.0,"appearance":"cool"}
	var before: Vector2i=h.objects.store.rect_for(h.objects.store.get_object("obj_1")).position
	check(h.objects.request_intent(configure,"llm","config:intent").accepted,"validated appearance/yaw configuration accepted")
	h.objects._tick_command()
	var record: Dictionary=h.objects.store.get_object("obj_1")
	check(record.yaw_deg==45 and record.appearance=="cool" and Vector2i(record.x,record.y)==before,"configuration persists fields without repositioning")
	var restored=DesktopObjectsHost.Store.new()
	restored.set_data(JSON.parse_string(JSON.stringify(h.objects.store.data())))
	check(restored.get_object("obj_1").yaw_deg==45 and restored.get_object("obj_1").appearance=="cool","yaw and preset survive JSON persistence")
	for bad in [{"verb":"hide"},{"verb":"configure","target_id":"object:obj_1","yaw_deg":INF},{"verb":"appearance","target_id":"object:obj_1","appearance":"arbitrary_shader"},{"verb":"use","target_id":"object:missing"}]:
		var request={"kind":"furniture","object_type":"computer"};request.merge(bad,true)
		check(not h.objects.request_intent(request,"llm","bad"+str(checks)).accepted,"malformed or unowned command rejected")
	h.objects.request_intent(use,"llm","expiry:intent")
	h.objects._clock+=31
	h.objects._tick_command()
	check(h.objects._pending_command.is_empty() and h.objects.command_outcomes.back().outcome=="expired","queued freshness is bounded while blocked")
	h.objects.request_intent(use,"user","user:intent")
	check(not h.objects.request_intent(use,"llm","low:intent").accepted,"model cannot replace pending user request")
	h.objects.cancel_commands("cancelled")
	h.objects.request_intent(use,"llm","switch:intent")
	h.session.character_id="other"
	h.objects._tick_command()
	check(h.objects.command_outcomes.back().outcome=="character_changed","character switch invalidates queued plan")
	h.free()
	h=command_fixture()
	var director: BehaviorDirector=h.living.director
	director.observe_interest("user-destination",Vector2(900,700),1,120,"surface","User destination")
	for active in [false,true]:
		director=BehaviorDirector.new();h.living.director=director
		director.observe_interest("user-destination",Vector2(900,700),1,120,"surface","User destination")
		director.request_intent("user-move-"+str(active),"move_to","user-destination","user")
		if active:
			var out: Dictionary=director.tick(.5,{"can_move":true})
			director.resolve_intent(out.action.id,"started")
			check(director._active.get("source","")=="user","active priority case owns a started user move")
		check(not h.objects.request_intent(use,"llm","blocked-"+str(active)).accepted,"queued/active user navigation rejects model furniture")
		check(director.has_user_intent() and h.objects.creations==0,"rejection preserves explicit user move and creates nothing")
		director.cancel_all("test_reset")
	h.objects.request_intent(use,"llm","first-model:intent")
	director.request_intent("later-user","move_to","user-destination","user")
	h.objects._tick_command()
	check(h.objects._pending_command.is_empty() and h.objects.creations==0 and director.has_user_intent(),"dispatch rechecks newer user priority without mutating furniture")
	director.cancel_all()
	check(not h.objects.request_intent(use,"untrusted","bad-source").accepted,"unknown request source rejected")
	var extra: Dictionary=use.duplicate();extra["script"]="ignored code"
	check(not h.objects.request_intent(extra,"llm","bad-field").accepted,"undeclared fields rejected at native boundary")
	h.session.turn_id="speech-owner"
	h.audio.voice_active=true
	check(h.objects.request_intent(use,"llm","speech-owner:intent").accepted,"current reply furniture queues during its own speech")
	h.objects._tick_command()
	check(h.objects.creations==1 and h.objects.owns_foreground_speech(),"current reply dispatches and owns speech overlap")
	h.objects._interaction.stage="ready_contact"
	h._push_autonomy_context()
	check(not h.autonomy._blocked,"same reply seat admission clears only conversation ownership block")
	h.panel_open=true;h._push_autonomy_context()
	check(h.autonomy._blocked,"panel still blocks same reply contact")
	h.panel_open=false;h._drag_active=true;h._push_autonomy_context()
	check(h.autonomy._blocked,"drag still blocks same reply contact")
	h._drag_active=false
	h.session.turn_id="other-turn";h._push_autonomy_context()
	check(h.autonomy._blocked,"different turn speech blocks contact admission")
	h.session.turn_id="speech-owner"
	h.objects.cancel_commands("cancelled")
	h.objects.request_intent(use,"llm","unrelated:intent")
	h.objects._tick_command()
	check(not h.objects._pending_command.is_empty() and h.objects._interaction.is_empty(),"unrelated speech still blocks queued furniture")
	h.objects.cancel_commands("cancelled")
	h.audio.voice_active=false
	h.free()
	print("Furniture commands: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
