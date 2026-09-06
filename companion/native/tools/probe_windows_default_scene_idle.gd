extends SceneTree
## Root-only external Windows observation. No chat, model or movement requests.
## --output ABS_DIR [--character cheval-grand|eishin-flash] [--seconds 150]
var app
var settings_node
var original:Dictionary={}
var output:=""
var started:=0
var closing:=false
var stream:FileAccess
var report:Dictionary={"checks":[],"trips":[],"images":[],"conversation_events":[],"outcomes":[]}
func _initialize():call_deferred("run")
func arg(key:String,fallback:String="")->String:
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]==key:return args[i+1]
	return fallback
func safe(value:Variant)->Variant:
	if value is Vector3:return safe([value.x,value.y,value.z])
	if value is Vector2 or value is Vector2i:return safe([value.x,value.y])
	if value is float:return value if is_finite(value) else null
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=safe(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(safe(item))
		return result
	if typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING]:return value
	return str(value)
func ms()->int:return Time.get_ticks_msec()-started
func check(ok:bool,label:String):
	report.checks.append({"ok":ok,"label":label,"ms":ms()})
	print("DEFAULT_SCENE_IDLE ",label," ",ok)
func frame():
	await process_frame
	await RenderingServer.frame_post_draw
func wait_for(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not closing and Time.get_ticks_msec()<deadline:
		await frame()
		if closing:return false
		if predicate.call():return true
	return false
func run():
	if OS.get_name()!="Windows":print("DEFAULT_SCENE_IDLE_NOT_RUN: Windows required");quit(2);return
	output=arg("--output")
	var character:=arg("--character","cheval-grand")
	var seconds:=clampf(float(arg("--seconds","150")),30,240)
	if output.is_empty() or character not in ["cheval-grand","eishin-flash"]:quit(2);return
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	started=Time.get_ticks_msec()
	settings_node=root.get_node("Settings")
	original=settings_node.data.duplicate(true)
	settings_node.data=settings_node.DEFAULTS.duplicate(true)
	settings_node.data.character=character
	settings_node.data.backend_url=original.get("backend_url","")
	report["declared_defaults"]=settings_node.data.duplicate(true)
	create_timer(seconds+100).timeout.connect(func():
		if not closing:check(false,"watchdog");finish())
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	app.client.event_received.connect(func(event:Dictionary):
		if str(event.get("type","")) in ["start","text","phrase","action","tts_start","audio"]:
			report.conversation_events.append({"ms":ms(),"type":event.get("type"),"turn_id":event.get("turn_id","")}))
	app.living.director.intent_outcome.connect(func(id:String,outcome:String):report.outcomes.append({"id":id,"outcome":outcome,"ms":ms()}))
	if not await wait_for(func():return app.session.hello_received and app.avatar.has_model() and app._vrma_pending==0 and not app.loading_label.visible,45):
		check(false,"production ready");await finish();return
	check(app.session.character_id==character and app.avatar.model_path.get_file()==BackendClient.avatar_cache_path(character).get_file(),"actual requested rig loaded")
	report["identity"]={"character":app.session.character_id,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_current_rendering_method()}
	check(app.spatial_camera()!=null and app.spatial_camera().projection==Camera3D.PROJECTION_PERSPECTIVE,"actual product-default camera is perspective")
	check(app.living.enabled and app.autonomy.enabled and app.autonomy.surface_mode and not app.panel_open,"actual default local behavior enabled in collapsed mode")
	var area:=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var cursor:=DisplayServer.mouse_get_position()
	var fraction:=.65 if cursor.x<area.position.x+area.size.x*.5 else .25
	var foot:=Vector2(area.position.x+area.size.x*fraction,area.end.y)
	app.scene_navigation.cancel("dragged")
	app.autonomy.cancel_target("dragged")
	root.position=Vector2i(foot-Vector2(app._projected_anchors().foot))
	report["corridor"]={"area":area,"cursor":cursor,"foot":foot,"policy":"own window placement with normal drag-release ownership/settle; pointer policy unchanged"}
	check(await wait_for(func():return app.scene_navigation.ground_latched or (app.autonomy.can_request_move() and str(app.autonomy.get_support_contact().get("surface_id","")).begins_with("floor:")),12),"normal floor policy settles")
	check(await wait_for(func():return app.scene_navigation.ground_latched and app.scene_navigation.diagnostics.has("initial_placement"),5),"Living automatically admits measured scene placement")
	var placement:Dictionary=app.scene_navigation.diagnostics.get("initial_placement",{})
	report.corridor["scene_placement"]=placement
	check(placement.get("ok",false),"production measured scene ground placement admitted")
	check(await wait_for(func():return app.living._scene_exploration_enabled() and app.living.scene_interests.targets.size()>0,5),"actual stable scene interests are available by default")
	report["behavior_style"]=app.living.director.style.duplicate()
	report["observe_start_ms"]=ms();report["seconds"]=seconds
	stream=FileAccess.open(output.path_join("frames.jsonl"),FileAccess.WRITE)
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	var next_image:=0
	var trip:Dictionary={}
	var hold:Dictionary={}
	var holds:Array=[]
	while not closing and Time.get_ticks_msec()<deadline:
		await frame()
		if closing:return
		var world:Vector3=app.avatar.contact_anchors().foot
		var active:bool=app.scene_navigation.navigation.active
		var latched:bool=app.scene_navigation.ground_latched
		var row:Dictionary={"ms":ms(),"foot_world":world,"yaw":app.avatar.rotation.y,"navigation_active":active,"ground_latched":latched,"completion_owner":app.scene_navigation.has_completion_owner(),"director_state":app.living.director.state,"native_state":app.autonomy.state,"window":root.position,"targets":app.living.scene_interests.targets,"navigation":app.scene_navigation.diagnostics,"pointer_block":app.autonomy._pointer_interaction}
		stream.store_line(JSON.stringify(safe(row)))
		if ms()>=next_image:
			var path:="frames/%07d.png"%ms()
			var error:=root.get_texture().get_image().save_png(output.path_join(path))
			report.images.append({"ms":ms(),"path":path,"error":error});next_image=ms()+1000;stream.flush()
		if active and trip.is_empty():trip={"start":world,"start_ms":ms(),"owned":app.scene_navigation.has_completion_owner(),"id":app.scene_navigation.navigation.request_id,"director_id":str(app.living.director._active.get("id",""))}
		if not active and not trip.is_empty():
			trip.end=world;trip.end_ms=ms();trip.depth_m=absf(world.z-Vector3(trip.start).z)
			report.trips.append(trip.duplicate(true))
			hold={"start":world,"start_ms":ms(),"max_drift_m":0.0,"always_latched":latched,"trip_index":report.trips.size()-1}
			trip.clear()
		if not hold.is_empty():
			hold.max_drift_m=maxf(float(hold.max_drift_m),world.distance_to(Vector3(hold.start)))
			hold.always_latched=bool(hold.always_latched) and latched
			if active:hold.clear()
			elif ms()-int(hold.start_ms)>=5000:
				hold.end_ms=ms();holds.append(hold.duplicate(true));hold.clear()
	report["holds"]=holds
	var depth_trips:Array=report.trips.filter(func(t):return qualified_trip(t))
	check(depth_trips.size()>0,"at least one unprompted autonomous scene-depth trip")
	check(depth_trips.size()>0,"depth trip has matching local director arrival terminal")
	check(holds.any(func(h):return bool(h.always_latched) and float(h.max_drift_m)<=.005 and qualified_trip(report.trips[int(h.trip_index)])),"five-second XYZ hold after depth trip without taskbar reclamation")
	check(app.session.turn_counter==0 and report.conversation_events.is_empty(),"no chat turns or model conversation events observed")
	check(report.images.size()>0 and report.images.all(func(row):return row.error==OK),"periodic owned viewport captures saved")
	report["scope"]="No chat/model/direct-move request is issued by this probe. Conversation event/turn counters observed; HTTP/WS capability and asset traffic is expected. Outbound network packets are not independently intercepted."
	await finish()
func finish():
	if closing:return
	closing=true
	if stream!=null:stream.flush();stream=null
	if app!=null:
		app.cancel_scene_approach("shutdown");app.objects.shutdown();app.mic.cancel_recording();app.audio.cancel();app.world_source.stop();app.client.disconnect_ws();app.queue_free()
		await process_frame;await process_frame
	if settings_node!=null:
		settings_node.data=original.duplicate(true);settings_node.save_now()
		var restored:Variant=JSON.parse_string(FileAccess.get_file_as_string(settings_node.PATH))
		var expected:Variant=JSON.parse_string(JSON.stringify(original))
		check(restored is Dictionary and restored==expected,"original settings restored on disk")
	report["failures"]=report.checks.filter(func(row):return not row.ok).size()
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(safe(report),"  "))
	print("DEFAULT_SCENE_IDLE_REPORT ",output.path_join("report.json")," failures=",report.failures)
	quit(0 if report.failures==0 else 1)

func qualified_trip(trip:Dictionary)->bool:
	var id:=str(trip.get("director_id",""))
	return bool(trip.get("owned",false)) and float(trip.get("depth_m",0))>=.05 and id.begins_with("local:") and report.outcomes.any(func(event):return event.id==id and event.outcome=="arrived")
