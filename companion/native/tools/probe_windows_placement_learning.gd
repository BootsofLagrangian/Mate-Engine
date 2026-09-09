extends "probe_windows_space_skills.gd"
## Actual owned input handlers train only an isolated, disposable preference file.
var learning_path := ""

func write_report() -> void:
	if closing:super.write_report()

func run() -> void:
	if OS.get_name()!="Windows":quit(2);return
	output=argument("--output")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	started=Time.get_ticks_msec()
	create_timer(100).timeout.connect(func():
		if not closing:check(false,"placement learning watchdog exceeded");finish())
	learning_path="user://probe-placement-%d.json" % OS.get_process_id()
	if FileAccess.file_exists(learning_path):
		check(false,"isolated PID preference path unexpectedly exists");learning_path="";await finish();return
	settings_node=root.get_node("Settings");original=settings_node.data.duplicate(true)
	var fixture:={"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":0.6,
		"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,"curiosity_enabled":false,
		"fly_curiosity_mode":"off","fly_curiosity_enabled":false,"placement_learning_enabled":true,
		"placement_learning_path":learning_path,"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,
		"desktop_objects":{"version":1,"next_id":1,"objects":[]}}
	settings_node.data.merge(fixture,true)
	report["fixture_settings"]=fixture
	report["scope"]="One real owned-app press/release placement; isolated PID preference file; real native monitor geometry; no OS cursor/input or autonomous target injection. Replay and scoring run on CPU."
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not check(await wait_for(func():return app.avatar.has_model() and app.world_source.available and app._vrma_pending==0 and not app.session.character_id.is_empty(),40),"actual VRM session and native monitor geometry ready"):
		await finish();return
	area=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if not check(await choose_floor_corridor(),"normal supported placement ready"):
		await finish();return
	var preferences=app.living.placement_preferences
	var before:Dictionary=preferences.export_diagnostics()
	check(before.event_count==0 and preferences._path==learning_path,"runtime uses empty isolated preference store")
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=app.pet_rect.get_center()
	app._unhandled_input(press)
	check(app._drag_active and not app.autonomy.get_support_contact().get("attached",false),"actual press enters drag and detaches support")
	await process_frame
	root.position+=Vector2i(2,0);app._drag_moved=true
	var release:=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=app.pet_rect.get_center()
	var hook_started:=Time.get_ticks_usec()
	app._input(release)
	var release_hook_us:=Time.get_ticks_usec()-hook_started
	var after:Dictionary=preferences.export_diagnostics()
	report["before"]=before;report["after_release"]=after
	report["release_hook_total_us"]=release_hook_us
	report["timing_scope"]="Release handler includes placement, settings persistence, affinity recording and action selection; isolated replay latency below measures CPU rebuild only."
	if not check(not app._drag_active and after.event_count==before.event_count+1,"actual released drag records exactly one placement event"):
		await finish();return
	var event:Dictionary=after.events[-1]
	var foot:Vector2=Vector2(root.position)+app.camera.unproject_position(app.avatar.contact_anchors().foot)
	var monitor:Rect2=app.living._preference_monitor(foot)
	var expected:Dictionary=app.living.drop_affordance.nearest(app.world_source.snapshot,foot,Rect2(Vector2(root.position)+app.pet_rect.position,app.pet_rect.size),int(Time.get_unix_time_from_system()*1000.0),float(DisplayServer.screen_get_dpi(root.current_screen))/96.0)
	var kind:String="window" if expected.get("kind","")=="window_wall" else str(expected.get("kind","free"))
	var normalized:Vector2=(foot-monitor.position)/monitor.size if monitor.has_area() else Vector2.INF
	report["placement_context"]={"foot_xy":[foot.x,foot.y],"monitor_xywh":[monitor.position.x,monitor.position.y,monitor.size.x,monitor.size.y],"expected_kind":kind,"expected_normalized":[normalized.x,normalized.y] if normalized.is_finite() else null}
	check(monitor.has_area() and normalized.distance_to(Vector2(float(event.x),float(event.y)))<0.00001 and event.character==app.session.character_id and event.surface_kind==kind,"event matches actual normalized monitor point and context")
	check(FileAccess.file_exists(learning_path) and str(after.save_error).is_empty(),"isolated event persisted without save error")
	var library=load("res://scripts/placement_preferences.gd")
	var loaded=library.new()
	check(loaded.configure(learning_path),"persisted preference file reloads")
	var rebuilt=library.new();rebuilt.configure("")
	var rebuild_started:=Time.get_ticks_usec()
	var replay_ok:bool=rebuilt.rebuild(after.events)
	report["cpu_rebuild_us"]=Time.get_ticks_usec()-rebuild_started
	check(replay_ok,"offline in-memory rebuild accepts actual placement event")
	var stamp:float=Time.get_unix_time_from_system()
	var exact_bonus:float=preferences.bonus(str(event.character),foot,monitor,str(event.surface_kind),stamp)
	report["recorded_location_bonus"]=exact_bonus
	var max_error:=0.0
	var scoring_started:=Time.get_ticks_usec()
	for i in 100:
		var point:=monitor.position+monitor.size*Vector2(float(i%10)/9.0,float(i/10)/9.0)
		var online:float=preferences.bonus(str(event.character),point,monitor,str(event.surface_kind),stamp)
		var restored:float=loaded.bonus(str(event.character),point,monitor,str(event.surface_kind),stamp)
		var replay:float=rebuilt.bonus(str(event.character),point,monitor,str(event.surface_kind),stamp)
		max_error=maxf(max_error,maxf(absf(online-restored),absf(online-replay)))
	report["three_stores_100_candidates_us"]=Time.get_ticks_usec()-scoring_started
	report["max_replay_bonus_error"]=max_error
	check(exact_bonus>0.0 and max_error<0.000000001,"reload and replay preserve bonus across 100 monitor candidates")
	var idle_until:=Time.get_ticks_msec()+2500
	await wait_for(func():return Time.get_ticks_msec()>=idle_until,3.0)
	var final:Dictionary=preferences.export_diagnostics()
	check(final.event_count==after.event_count and final.revision==after.revision,"idle and repeated scoring create no extra learning events")
	report["final_preferences"]=final
	check(app.panel._placement_memory_status.text.contains("1회") and not app.panel._placement_memory_reset.disabled,"live panel displays learned placement count")
	app.panel._placement_learning_check.button_pressed=false
	await process_frame
	check(not bool(settings_node.get_value("placement_learning_enabled",true)),"panel can disable collecting and using preferences")
	app.panel._placement_learning_check.button_pressed=true
	await process_frame
	app.panel._placement_memory_reset.pressed.emit()
	check(preferences.export_diagnostics().event_count==0 and app.panel._placement_memory_reset.disabled,"panel resets current character memory through live handler")
	await shot("placement-learned")
	await finish()

func finish() -> void:
	if closing:return
	# Detach the live store first so cleanup frames cannot recreate the file.
	if app!=null:app.living.placement_preferences.configure("")
	if not learning_path.is_empty():
		for path in [learning_path,learning_path+".tmp"]:
			if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
		check(not FileAccess.file_exists(learning_path) and not FileAccess.file_exists(learning_path+".tmp"),"isolated preference files removed")
	await super.finish()
