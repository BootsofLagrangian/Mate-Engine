extends SceneTree
var app
var original: Dictionary
var output := ""
var checks: Array = []
var evidence := {}
func _initialize(): call_deferred("run")
func arg(key: String) -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i] == key: return args[i+1]
	return ""
func check(ok: bool, label: String):
	checks.append({"ok":ok,"label":label})
	print("PRESENTATION ",label," ",ok)
func wait_for(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call(): return true
		await process_frame
	return false
func settle(seconds: float): await create_timer(seconds).timeout
func run():
	output = arg("--output")
	if OS.get_name() != "Windows" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var settings = root.get_node("Settings")
	original = settings.data.duplicate(true)
	settings.data.merge({"vad_enabled":false,"autonomy_enabled":false,"behavior_enabled":false,
		"panel_open":true,"pet_scale":0.6,"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0},true)
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	check(await wait_for(func():return app.avatar.has_model() and app.session.hello_received and app._vrma_pending==0,50),"actual backend avatar and motions ready")
	check(not app.panel_open and not app.panel_window.visible,"startup pet mode ignores stale open-panel preference")
	check(root.borderless and root.transparent and root.transparent_bg and root.minimize_disabled and root.maximize_disabled,"root transparent borderless non-minimizable non-maximizable")
	app._set_panel_open(true,false)
	await settle(0.5)
	check(app.panel.get_window()==app.panel_window and app.panel.get_viewport()!=root,"settings use independent native viewport")
	check(app.panel_window.visible and not app.panel_window.is_embedded(),"settings window is visible native window")
	var panel_rect := Rect2i(app.panel_window.position,app.panel_window.size)
	check(not panel_rect.intersects(app._global_pet_rect()),"settings do not overlap rendered character")
	evidence.panel={"panel":str(panel_rect),"pet":str(app._global_pet_rect()),"root_size":str(root.size)}
	app.panel_window.close_panel()
	check(not app.panel_open and is_instance_valid(app.avatar),"settings close keeps pet alive")
	var views := [{"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0},
		{"view_yaw_deg":45.0,"view_pitch_deg":45.0,"view_height":0.0,"view_zoom":1.0},
		{"view_yaw_deg":90.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0},
		{"view_yaw_deg":-45.0,"view_pitch_deg":-30.0,"view_height":0.25,"view_zoom":1.2}]
	evidence.views=[]
	for i in views.size():
		for key in views[i]:settings.set_value(key,views[i][key])
		app._apply_view_settings()
		await settle(1.0)
		await RenderingServer.frame_post_draw
		var anchors: Dictionary = app._projected_anchors()
		var error: float = Vector2(anchors.foot).distance_to(app._pivot_px)
		check(error<0.01,"view %d exact projected foot pivot" % i)
		check(app.avatar.global_transform.is_finite() and app._unclipped_pet_rect.has_area(),"view %d finite visible geometry" % i)
		var im: Image = root.get_texture().get_image()
		check(im.get_pixel(2,2).a<0.001 and im.get_pixel(im.get_width()-3,2).a<0.001,"view %d viewport alpha corners clear" % i)
		im.save_png(output.path_join("view-%d.png" % i))
		evidence.views.append({"settings":views[i],"basis":str(app.camera.basis),"foot_error_px":error,"bounds":str(app._unclipped_pet_rect)})
	app._on_setting("view_reset",true)
	app.client.disconnect_ws();app.world_source.stop();app.objects.shutdown();app.autonomy.set_enabled(false)
	settings.data=original;settings.save_now()
	var report={"checks":checks,"evidence":evidence,"renderer":RenderingServer.get_video_adapter_name(),"failures":checks.filter(func(c):return not c.ok).size()}
	var f:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	quit(0 if report.failures==0 else 1)
