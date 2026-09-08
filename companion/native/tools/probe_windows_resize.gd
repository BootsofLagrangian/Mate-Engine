extends "probe_windows_space_skills.gd"
class LateMove:
	extends Node
	var host
	func _process(_delta:float)->void:
		host.get_window().position+=Vector2i(31,0)
		host.autonomy.position=Vector2(host.get_window().position)
		host._update_avatar_transform(0.0)
		host._update_pet_rect()
		set_process(false)
func write_report()->void:
	if closing:super.write_report()
func settle()->void:
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw
func unit_pixels(point:Vector3)->Vector2:
	var c:Camera3D=app.camera
	var pixel:=c.unproject_position(point)
	return Vector2(pixel.distance_to(c.unproject_position(point+c.global_basis.x*.1)),pixel.distance_to(c.unproject_position(point+c.global_basis.y*.1)))
func run()->void:
	if OS.get_name()!="Windows":quit(2);return
	output=argument("--output")
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	started=Time.get_ticks_msec()
	settings_node=root.get_node("Settings")
	original=settings_node.data.duplicate(true)
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":.6,"behavior_enabled":false,"autonomy_enabled":false,"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not check(await wait_for(func():return app.avatar.has_model() and app._vrma_pending==0 and app.session.hello_received,40),"actual VRM and backend ready"):
		await finish();return
	app.motion.set_process(false)
	report["scope"]="Owned native window resolution/aspect changes; no system monitor mode switch. Fixed actual VRM pose, projection metrics and desktop anchor checks."
	report["resizes"]=[]
	for mode in ["perspective","orthographic"]:
		root.size=app.WINDOW_SIZE
		await settle()
		settings_node.set_value("view_projection",mode)
		app._apply_view_settings(false)
		await settle()
		var late:=LateMove.new();late.host=app;late.process_priority=100;root.add_child(late)
		await process_frame
		await RenderingServer.frame_post_draw
		check(app._last_render_origin==Vector2(root.position),mode+" records movement committed after main process")
		late.queue_free()
		var body_foot:Vector3=app.avatar.contact_anchors().foot
		var body_desktop:Vector2=Vector2(root.position)+app.camera.unproject_position(body_foot)
		var point:Vector3=body_foot+Vector3.UP*.25
		var basis_scale:Vector3=app.avatar.global_basis.get_scale()
		var baseline:=unit_pixels(point)
		var desktop:Vector2=Vector2(root.position)+app.camera.unproject_position(point)
		for extent in [Vector2i(1280,720),Vector2i(720,1280),Vector2i(2560,1440),Vector2i(1920,1760)]:
			root.size=extent
			await settle()
			var measured:=unit_pixels(point)
			var actual:Vector2=Vector2(root.position)+app.camera.unproject_position(point)
			var roundtrip:Vector3=DesktopView.screen_to_world_at_depth(app.camera,app.camera.unproject_position(point),DesktopView.depth(app.camera,point))
			check(measured.distance_to(baseline)<.03,mode+" maintains horizontal and vertical pixel density "+str(extent))
			check(absf(measured.x/measured.y-1)<.001,mode+" preserves aspect "+str(extent))
			check((Vector2(root.position)+app.camera.unproject_position(app.avatar.contact_anchors().foot)).distance_to(body_desktop)<1.0,mode+" preserves last committed actor travel "+str(extent))
			check(actual.distance_to(desktop)<1.0,mode+" preserves desktop projection anchor "+str(extent))
			check(roundtrip.distance_to(point)<.0001 and app.avatar.global_basis.get_scale().is_equal_approx(basis_scale),mode+" roundtrip and rig scale preserved "+str(extent))
			report.resizes.append({"mode":mode,"requested":str(extent),"actual":str(root.size),"visible":str(app.render_size()),"pixels":str(measured),"baseline":str(baseline),"anchor_error":actual.distance_to(desktop),"diagnostics":app.render_diagnostics.duplicate(true)})
			await shot(mode+"-"+str(extent.x)+"x"+str(extent.y))
	await finish()
