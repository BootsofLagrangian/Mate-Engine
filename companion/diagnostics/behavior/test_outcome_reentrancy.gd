extends SceneTree
const Director=preload("res://scripts/behavior_director.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func dispose(d):
	for connection in d.intent_outcome.get_connections():d.intent_outcome.disconnect(connection.callable)
func _initialize():
	for operation in ["expire","cancel","cancel_all","supersede","active"]:
		var d=Director.new()
		d.request_intent("old","rest","","local",.1)
		if operation=="active":d.tick(.01,{})
		var events:Array=[]
		var entered:=[false]
		d.intent_outcome.connect(func(id:String,outcome:String):
			events.append([id,outcome])
			if not entered[0]:
				entered[0]=true
				d.cancel_intent(id,"callback_cancel"))
		match operation:
			"expire":d._time=1;d._expire()
			"cancel":d.cancel_intent("old")
			"cancel_all":d.cancel_all()
			"supersede":d.request_intent("new","rest","","user")
			"active":d.cancel_intent("old")
		check(events.size()==1,operation+" reentrant same-ID terminal emitted once")
		check(d._active.is_empty() and d._queue.all(func(row):return row.id!="old"),operation+" old ownership detached")
		dispose(d)
	# A callback may clear other queued entries, not only its own entry.
	var d=Director.new()
	for id in ["one","two","three"]:d.request_intent(id,"rest","","local",.1)
	var events:Array=[]
	var entered:=[false]
	d.intent_outcome.connect(func(id:String,outcome:String):
		events.append(id)
		if not entered[0]:entered[0]=true;d.cancel_all("callback_all"))
	d._time=1;d._expire()
	check(events.size()==3 and events.count("one")==1 and events.count("two")==1 and events.count("three")==1,"expiry callback can clear remaining queue exactly once")
	check(d._queue.is_empty(),"reentrant bulk expiry leaves no old queue")
	# Newly enqueued work belongs to the callback and must not be cleared later.
	dispose(d)
	d=Director.new();d.request_intent("old","rest","","local")
	d.intent_outcome.connect(func(id:String,_outcome:String):
		if id=="old":d.request_intent("callback-new","rest","","local"))
	d.cancel_all()
	check(d._queue.size()==1 and d._queue[0].id=="callback-new","bulk cancellation preserves callback-created work")
	# Active completion must not erase a replacement activated by a callback.
	dispose(d)
	d=Director.new();d.request_intent("old","rest","","local");d.tick(.01,{})
	d.intent_outcome.connect(func(id:String,_outcome:String):
		if id=="old":
			d.request_intent("callback-active","rest","","local")
			d.tick(1.0,{}))
	d.cancel_intent("old")
	check(d._active.get("id","")=="callback-active","active completion preserves callback-activated replacement")
	dispose(d)
	d=Director.new()
	for id in ["one","two"]:d.request_intent(id,"rest","","local")
	var readded:=[false]
	d.intent_outcome.connect(func(id:String,_outcome:String):
		if id=="one":readded[0]=d.request_intent("two","rest","","local").accepted)
	d.cancel_all()
	check(not readded[0] and d._queue.is_empty(),"bulk cancellation reserves all retiring IDs before callbacks")
	dispose(d)
	d=Director.new();d.request_intent("old","rest","","local")
	d.intent_outcome.connect(func(id:String,_outcome:String):
		if id=="old":d.request_intent("incoming","rest","","user"))
	d.request_intent("incoming","rest","","user")
	check(d._queue.filter(func(row):return row.id=="incoming").size()==1,"supersession callback cannot duplicate incoming ID")
	dispose(d)
	d=Director.new();d.set_character("old-character");d.request_intent("old","rest","","local")
	var switched_submission:=[true]
	d.intent_outcome.connect(func(id:String,_outcome:String):
		if id=="old":switched_submission[0]=d.request_intent("during-switch","rest","","local").accepted)
	d.set_character("new-character")
	check(not switched_submission[0] and d._queue.is_empty(),"character switch rejects reentrant request during cancellation")
	check(d.request_intent("after-switch","rest","","local",30,2,"new-character").accepted,"character switch releases admission guard after completion")
	dispose(d)
	print("Outcome reentrancy: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
