extends SceneTree
## Actual native viewport readbacks; never reads other desktop windows.
var app
var settings
var original := {}
var output := ""
var closing := false
var character := "cheval-grand"
var pet_scale := 1.0
var report := {"checks":[],"samples":[],"scope":"Actual exported Windows viewport alpha bounds during authored motion, two camera projections. Finite sampled coverage, not all possible poses/scales or OS compositor alpha proof."}

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	report.checks.append({"ok":ok,"label":label})
	print("RENDER_ROOM ",label," ",ok)
func wait_for(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while not closing and Time.get_ticks_msec()<end:
		await process_frame
		if predicate.call(): return true
	return false
func run():
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]=="--output": output=args[i+1]
		if args[i]=="--character": character=args[i+1]
		if args[i]=="--scale": pet_scale=clampf(float(args[i+1]),.35,1.25)
	if OS.get_name()!="Windows" or output.is_empty(): quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	settings=root.get_node("Settings");original=settings.data.duplicate(true)
	create_timer(100).timeout.connect(func():
		if not closing: check(false,"watchdog");finish())
	settings.data.merge({"vad_enabled":false,"autonomy_enabled":false,"behavior_enabled":false,"panel_open":false,"character":character,"pet_scale":pet_scale,"show_subtitles":false,"view_projection":"orthographic","view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not await wait_for(func():return app.avatar.has_model() and app.session.hello_received and app._vrma_pending==0,45):
		check(false,"backend avatar motions ready");finish();return
	check(root.size==Vector2i(1920,1760),"expanded production native render canvas")
	report["driver"]=RenderingServer.get_current_rendering_driver_name()
	report["root_size"]=[root.size.x,root.size.y]
	report["character"]=character
	report["pet_scale"]=pet_scale
	for projection in ["orthographic","perspective"]:
		settings.data.view_projection=projection
		settings.data.view_yaw_deg=45.0 if projection=="perspective" else 0.0
		settings.data.view_pitch_deg=30.0 if projection=="perspective" else 0.0
		app._apply_view_settings()
		await wait_for(func():return false,.5)
		for clip in ["authored_wave","authored_overhead_stretch","authored_stretch"]:
			if not app.motion.vrma_clips.has(clip):
				check(false,"required authored motion loaded "+clip);continue
			check(app.motion.play_gesture(clip),"start "+projection+" "+clip)
			var minimum:=1e10
			var visible:=0
			for sample in 16:
				await wait_for(func():return false,.12)
				await RenderingServer.frame_post_draw
				var im:Image=root.get_texture().get_image()
				var used:=im.get_used_rect()
				var margin:=mini(mini(used.position.x,used.position.y),mini(im.get_width()-used.end.x,im.get_height()-used.end.y))
				if used.has_area():visible+=1
				minimum=minf(minimum,margin)
				report.samples.append({"projection":projection,"motion":clip,"sample":sample,"alpha_bounds":str(used),"margin_px":margin,"frame_delta_s":app.get_process_delta_time()})
				if sample in [3,8,13]: im.save_png(output.path_join("%s-%s-%02d.png" %[projection,clip,sample]))
			check(visible==16 and minimum>4,"sampled motion remains inside render canvas "+projection+" "+clip+" margin="+str(minimum))
			app.motion.stop_gesture()
	finish()
func finish():
	if closing:return
	closing=true
	if is_instance_valid(app):
		app.client.disconnect_ws();app.world_source.stop();app.objects.shutdown();app.autonomy.set_enabled(false)
	settings.data=original;settings.save_now()
	report["failures"]=report.checks.filter(func(row):return not row.ok).size()
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))
	quit(1 if report.failures else 0)
