extends "probe_windows_presence.gd"
func run()->void:
	if OS.get_name()!="Windows":quit(2);return
	output=argument("--output")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	started=Time.get_ticks_msec()
	settings_node=root.get_node("Settings");original=settings_node.data.duplicate(true)
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":.6,"behavior_enabled":true,"autonomy_enabled":true,"surface_roam":true,"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	report["scope"]="Actual shell taskbar and authored floor rest; idle cooldown made immediately eligible, stable support and full source timings unchanged. No synthetic native source or mouse input."
	if not check(await wait_for(func():return app.avatar.has_model() and app.motion.floor_rest_available() and app._vrma_pending==0 and not app.world_source.snapshot.get("taskbars",[]).is_empty(),40),"actual rig floor sources and native taskbar metadata ready"):
		await finish();return
	area=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if not check(await choose_floor_corridor(),"normal attached desktop support ready"):
		await finish();return
	check(app.autonomy.get_support_contact().get("kind","")=="taskbar","support is positively identified taskbar")
	app.living.director._phase_until=app.living.director._time+120
	app.living.director._next_move=app.living.director._time+120
	app.living.surface_rest.next_rest=app.living.surface_rest.clock
	var started_rest:=await wait_for(func():return app._floor_rest_owned and app.motion.floor_rest.phase=="idle",15)
	report["floor_admission"]=app.floor_rest_admission.duplicate(true)
	report["rest_policy"]=app.living.surface_rest_diagnostics.duplicate(true)
	if not check(started_rest,"rule-based taskbar rest enters authored folded-leg idle"):
		await finish();return
	check(app.autonomy.get_support_contact().get("attached",false) and app._sit_attached,"floor rest retains physical taskbar support")
	await shot("taskbar-rest")
	var im:=root.get_texture().get_image()
	var used:Rect2=Rect2(im.get_used_rect())
	var visible:=Rect2(Vector2(root.position)+used.position,used.size)
	var fits:=false
	for i in DisplayServer.get_screen_count():
		if Rect2(Vector2(DisplayServer.screen_get_position(i)),Vector2(DisplayServer.screen_get_size(i))).encloses(visible):fits=true;break
	check(fits,"all nontransparent owned pixels fit a physical monitor")
	report["visible_pixels"]=str(visible)
	check(await wait_for(func():return not app._floor_rest_owned and not app.is_sitting(),20),"timed idle rest performs authored exit and releases body")
	await shot("taskbar-standing")
	await wait_for(func():return app.motion.heading_ready() and app.autonomy.get_support_contact().get("attached",false),5)
	app._request_sit()
	if check(await wait_for(func():return app._floor_rest_owned and app.motion.floor_rest.active,6),"second floor rest begins for hard reset check"):
		app.motion.reset_all()
		check(not app._floor_rest_owned and not app.is_sitting() and not app._floor_navigation_rect.has_area() and app.motion.current_contact_pose()=="foot","hard reset releases native floor owner synchronously")
	await wait_for(func():return app.motion.heading_ready() and app.autonomy.get_support_contact().get("attached",false),5)
	app._request_sit()
	if check(await wait_for(func():return app._floor_rest_owned and app.motion.floor_rest.phase=="idle",6),"floor rest begins for queued view and scale edits"):
		var old_scale:float=app._pet_scale_target
		var old_view:Dictionary=app._view_settings.duplicate(true)
		app._set_scale_target(.7)
		app._set_scale_target(.75)
		settings_node.set_value("view_yaw_deg",15.0)
		app._apply_view_settings()
		check(app.motion.floor_rest.active and app._pet_scale_target==old_scale and app._view_settings==old_view,"view and scale remain within admitted bounds during authored exit")
		check(await wait_for(func():return not app._floor_rest_owned and is_equal_approx(app._pet_scale_target,.75) and is_equal_approx(float(app._view_settings.view_yaw_deg),15),6),"latest queued scale and view apply after authored exit")
	await finish()
