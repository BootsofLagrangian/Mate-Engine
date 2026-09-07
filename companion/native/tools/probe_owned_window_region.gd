extends RefCounted
## Checks the actual owned HWND region; a viewport PNG bypasses this Windows clip.
## The adjacent PowerShell helper reads only window metadata, never desktop pixels.

static func verify(app: Node, output: String, helper_path: String) -> Dictionary:
	if OS.get_name() != "Windows": return {"ok":false,"reason":"Windows required"}
	if not app.objects.contact_scene_active() or not app.objects._contact_scene.visible:
		return {"ok":false,"reason":"visible occupied furniture required"}
	app._update_passthrough(true)
	await RenderingServer.frame_post_draw
	var window: Window = app.get_window()
	var image: Image = window.get_texture().get_image()
	var old_region: Rect2 = app.pet_rect.grow(10)
	if app.handle_button.visible:
		old_region = old_region.merge(Rect2(app.handle_button.position,app.handle_button.size).grow(4))
	if app.subtitle.visible:
		old_region = old_region.merge(Rect2(app.subtitle.position,app.subtitle.size))
	var furniture: Rect2 = app.objects.contact_bounds().intersection(Rect2(Vector2.ZERO,Vector2(image.get_size())))
	var points: Array = []
	# Spread samples over the visible furniture, excluding the old region. Opaque
	# pixels establish that there is actual rendered content to preserve there.
	for y in range(ceili(furniture.position.y),floori(furniture.end.y),3):
		for x in range(ceili(furniture.position.x),floori(furniture.end.x),3):
			if old_region.grow(2).has_point(Vector2(x,y)): continue
			if image.get_pixel(x,y).a < 0.95: continue
			points.append({"x":x,"y":y})
	if points.is_empty(): return {"ok":false,"reason":"fixture has no opaque furniture outside original region"}
	var selected: Array = []
	for i in mini(points.size(),64):
		selected.append(points[floori(float(i)*points.size()/mini(points.size(),64))])
	var request := {"process_id":OS.get_process_id(),
		"hwnd":str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,window.get_window_id())),
		"points":selected,"candidate_pixels":points.size(),"old_region":str(old_region),
		"furniture_bounds":str(furniture),"window_position":str(window.position)}
	var request_path := output.path_join("owned-region-request.json")
	var result_path := output.path_join("owned-region-result.json")
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(result_path)
	var file := FileAccess.open(request_path,FileAccess.WRITE)
	if file == null: return {"ok":false,"reason":"cannot write region request"}
	file.store_string(JSON.stringify(request)); file.close()
	var child := OS.create_process("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",helper_path,"-RequestPath",request_path,"-ResultPath",result_path]))
	if child < 0: return {"ok":false,"reason":"cannot start region helper"}
	var deadline := Time.get_ticks_msec()+12000
	while OS.is_process_running(child) and Time.get_ticks_msec()<deadline:
		await app.get_tree().create_timer(0.05).timeout
	if OS.is_process_running(child):
		OS.kill(child)
		return {"ok":false,"reason":"region helper timeout"}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
	if not result is Dictionary: return {"ok":false,"reason":"region helper produced no valid result"}
	result["request"] = request
	return result
