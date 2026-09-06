extends SceneTree
## External production Windows probe. Root launches exclusively; own viewports only.
const View = preload("res://scripts/desktop_view.gd")
var app
var settings_node
var original := {}
var output := ""
var closing := false
var reference_view: SubViewport
var reference_camera: Camera3D
var report := {"checks":[],"captures":[],"scope":"Production Windows native object viewport readbacks and common World3D reference; no desktop pixels/input. Opaque depth/crop consistency; partial-alpha OS overdraw excluded. No seated choreography claim."}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok":ok,"label":label})
	print("PERSPECTIVE_CHECK ",label," ",ok)
	return ok
func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not closing and Time.get_ticks_msec()<deadline:
		await process_frame
		await RenderingServer.frame_post_draw
		if predicate.call(): return true
	return false
func vector(value: Vector3) -> Dictionary: return {"x":value.x,"y":value.y,"z":value.z}
func point(record: Dictionary) -> Vector3:
	return Vector3(record.position_m.x,record.position_m.y,record.position_m.z)
func sync_reference() -> void:
	var camera: Camera3D = app.spatial_camera()
	reference_camera.global_transform=camera.global_transform
	reference_camera.keep_aspect=camera.keep_aspect
	reference_camera.near=camera.near
	reference_camera.far=camera.far
	reference_camera.projection=camera.projection
	reference_camera.fov=camera.fov
	reference_camera.size=camera.size
func capture(label: String, ids: Array) -> void:
	sync_reference()
	await wait_for(func(): return false,.15)
	var full:=reference_view.get_texture().get_image()
	check(full.save_png(output.path_join(label+"-reference.png"))==OK,label+" reference image retained")
	var metrics:=[]
	for id in ids:
		var window=app.objects.windows[id]
		var image: Image=window.get_texture().get_image()
		check(image.save_png(output.path_join(label+"-"+id+".png"))==OK,label+" native crop retained "+id)
		var offset:=Vector2i(Vector2(window.position)-app.spatial_desktop_origin())
		var count:=0
		var raw_mismatch:=0
		var interior:=0
		var interior_mismatch:=0
		for y in range(2,image.get_height()-2):
			for x in range(2,image.get_width()-2):
				var px:=x+offset.x
				var py:=y+offset.y
				if px<1 or py<1 or px>=full.get_width()-1 or py>=full.get_height()-1: continue
				var expected:=full.get_pixel(px,py)
				if expected.a<.999: continue
				var actual:=image.get_pixel(x,y)
				var mismatch:=color_delta(expected,actual)>.02
				count+=1
				if mismatch: raw_mismatch+=1
				var flat:=true
				for dy in range(-1,2):
					for dx in range(-1,2):
						if color_delta(expected,full.get_pixel(px+dx,py+dy))>.02: flat=false
				if flat:
					interior+=1
					if mismatch: interior_mismatch+=1
		metrics.append({"id":id,"opaque_samples":count,"raw_mismatches":raw_mismatch,"flat_interior_samples":interior,"interior_mismatches":interior_mismatch,"crop_origin":[offset.x,offset.y],"native_size":[window.size.x,window.size.y]})
		check(window.visible and window.world_3d==root.world_3d and not window.is_embedded(),label+" native window shares actual world "+id)
		check(count>500 and interior>100 and interior_mismatch==0,label+" opaque interior depth/crop agreement "+id)
		var record:Dictionary=app.objects.store.get_object(id)
		var scene_point:Vector3=window._scene.to_global(window._sockets.seat)
		var expected_pixel:Vector2=app.spatial_desktop_origin()+app.spatial_camera().unproject_position(scene_point)
		check(window.socket_point("seat").distance_to(expected_pixel)<.02,label+" actual socket agrees with common projection "+id)
	report.captures.append({"label":label,"metrics":metrics})
func color_delta(a: Color,b: Color) -> float:
	return maxf(absf(a.a-b.a),maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
func run() -> void:
	if OS.get_name()!="Windows": print("PERSPECTIVE_NOT_RUN Windows required"); quit(2); return
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]=="--output": output=args[i+1]
	if output.is_empty(): quit(2); return
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	settings_node=root.get_node("Settings")
	original=settings_node.data.duplicate(true)
	create_timer(120).timeout.connect(func():
		if not closing: check(false,"120second watchdog"); finish())
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":"cheval-grand","pet_scale":.6,"behavior_enabled":false,"autonomy_enabled":false,"view_projection":"perspective","view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0,"view_fov_deg":45.0,"view_distance_m":3.6,"desktop_objects":{"version":1,"next_id":1,"objects":[]}},true)
	app=load("res://main.tscn").instantiate();root.add_child(app);current_scene=app
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() and app._vrma_pending==0,45),"production avatar/backend ready"):
		await finish();return
	if not check(app.spatial_camera()!=null,"production virtual perspective camera active"):
		await finish();return
	report["renderer"]=RenderingServer.get_current_rendering_driver_name()
	report["model"]=app.avatar.model_path
	reference_view=SubViewport.new();reference_view.size=Vector2i(680,760);reference_view.transparent_bg=true;reference_view.world_3d=root.world_3d;reference_view.msaa_3d=root.msaa_3d;reference_view.screen_space_aa=root.screen_space_aa;reference_view.use_taa=root.use_taa;reference_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(reference_view)
	reference_camera=Camera3D.new();reference_view.add_child(reference_camera);reference_camera.current=true
	var ids:=[]
	for appearance in ["warm","cool"]:
		var id:String=app.objects.add_object("chair")
		if not check(not id.is_empty(),"production chair created "+appearance): await finish();return
		ids.append(id)
		check(app.objects.configure_object(id,0.0,appearance),"production appearance configured "+appearance)
	app.objects.set_edit_enabled(false)
	var center:=View.screen_to_world_at_depth(app.spatial_camera(),Vector2(340,520),3.6)
	var positions:=[center+Vector3(-.08,0,-.25),center+Vector3(.08,0,.15)]
	for i in ids.size():
		if not check(app.objects.configure_spatial_position(ids[i],positions[i]),"explicit canonical position accepted "+ids[i]): await finish();return
	var saved:Dictionary=app.objects.store.data().duplicate(true)
	var overlap:=Rect2(app.objects.windows[ids[0]].position,app.objects.windows[ids[0]].size).intersection(Rect2(app.objects.windows[ids[1]].position,app.objects.windows[ids[1]].size))
	check(overlap.get_area()>1000,"two actual native prop crops overlap")
	await capture("front",ids)
	var before_size:Vector2i=app.objects.windows[ids[1]].size
	var before_basis:Basis=app.objects.windows[ids[1]]._scene.global_basis
	check(app.objects.configure_spatial_position(ids[1],positions[1]+Vector3(0,0,-.5)),"depth-only translation accepted")
	var after_size:Vector2i=app.objects.windows[ids[1]].size
	check(after_size.y<before_size.y and app.objects.windows[ids[1]]._scene.global_basis.is_equal_approx(before_basis),"greater optical depth shrinks projection without scaling mesh")
	await capture("depth-reversed",ids)
	check(app.objects.configure_spatial_position(ids[1],positions[1]),"depth position restored")
	var camera_before:Transform3D=app.spatial_camera().global_transform
	app.panel.setting_changed.emit("view_yaw_deg",20.0)
	app.panel.setting_changed.emit("view_pitch_deg",15.0)
	app.panel.setting_changed.emit("view_fov_deg",55.0)
	app.panel.setting_changed.emit("view_distance_m",4.0)
	var actual_camera:Camera3D=app.spatial_camera()
	report["camera_edit"]={"before_transform":str(camera_before),"after_transform":str(actual_camera.global_transform),"fov_deg":actual_camera.fov,"optical_origin_z_m":(actual_camera.global_basis.inverse()*actual_camera.global_position).z}
	check(actual_camera.global_basis.is_equal_approx(View.orbit_basis(20.0,15.0,0.0,4.0)) and not actual_camera.global_transform.is_equal_approx(camera_before),"UI orbit changes actual canonical camera to expected basis")
	check(is_equal_approx(actual_camera.fov,55.0) and is_equal_approx((actual_camera.global_basis.inverse()*actual_camera.global_position).z,4.0),"UI lens and distance change actual canonical projection")
	for id in ids:
		var record:Dictionary=app.objects.store.get_object(id)
		var old:Dictionary={}
		for item in saved.objects:
			if item.id==id: old=item
		check(record.position_m==old.position_m and record.scale==old.scale and record.spatial_unit_scale==old.spatial_unit_scale,"camera edit preserves world pose and physical scale "+id)
	await capture("orbit",ids)
	app.panel.setting_changed.emit("view_projection","orthographic")
	await wait_for(func():return false,.2)
	check(app.spatial_camera()==null and app.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"orthographic switch changes actual production camera")
	for id in ids:
		check(app.objects.windows[id].world_3d!=root.world_3d and app.objects.windows[id]._shared_camera==null,"orthographic switch restores private world "+id)
	await finish()
func finish() -> void:
	if closing:return
	closing=true
	if reference_view!=null:reference_view.queue_free()
	if app!=null:
		app.objects.shutdown();app.mic.cancel_recording();app.audio.cancel();app.world_source.stop();app.client.disconnect_ws();app.queue_free()
		await process_frame;await process_frame
	if settings_node!=null:
		settings_node.data=original.duplicate(true);settings_node.save_now()
		var persisted:Variant=JSON.parse_string(FileAccess.get_file_as_string(settings_node.PATH))
		var expected:Variant=JSON.parse_string(JSON.stringify(original))
		check(persisted==expected,"original settings restored and read back from disk")
	report["failures"]=report.checks.filter(func(row):return not row.ok).size()
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"  "))
	print("PERSPECTIVE_REPORT ",output," failures=",report.failures)
	quit(0 if report.failures==0 else 1)
