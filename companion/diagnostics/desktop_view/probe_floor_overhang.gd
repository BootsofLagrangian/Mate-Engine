extends SceneTree
var failures:=[]
var cases:=0
var max_error:=0.0
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(680,760)
	await process_frame
	var settings:=root.get_node("Settings")
	var saved:Dictionary=settings.data.duplicate(true)
	var host_script:=GDScript.new()
	host_script.source_code="extends \"res://scripts/main.gd\"\nfunc _ready() -> void: set_process(false)\n"
	if host_script.reload()!=OK: quit(2); return
	var app=host_script.new()
	root.add_child(app)
	app.avatar=VrmAvatar.new();app.add_child(app.avatar)
	app.motion=MotionPlayer.new();app.add_child(app.motion);app.motion.set_process(false)
	app.motion.avatar=app.avatar
	app.camera=Camera3D.new();app.add_child(app.camera);app.camera.current=true
	var observations:=[]
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		app.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		app._frame_avatar()
		for pitch in [0.0,45.0]:
			settings.data.merge({"view_yaw_deg":45.0,"view_pitch_deg":pitch,"view_height":0.0,"view_zoom":1.0},true)
			app._pet_scale=0.6
			app._apply_view_settings()
			var foot:Vector2=app._projected_anchors().foot
			var bounds:Rect2=app._navigation_rect()
			var area:=Rect2(0,0,2560,1400)
			var origin:=Vector2(1800,area.end.y)-foot
			var a:=DesktopAutonomy.new()
			root.add_child(a);a.set_process(false)
			a.configure_simulation([area],origin,bounds)
			a.surface_mode=true
			var true_bottom:=-INF
			var sole_bottom:=-INF
			for mesh in app.avatar.model.find_children("*","MeshInstance3D",true,false):
				if not mesh.visible or mesh.mesh==null:continue
				for surface in mesh.mesh.get_surface_count():
					var arrays=mesh.mesh.surface_get_arrays(surface)
					if arrays.is_empty():continue
					for vertex in arrays[Mesh.ARRAY_VERTEX]:
						true_bottom=maxf(true_bottom,app.camera.unproject_position(mesh.global_transform*vertex).y)
			for point in app.avatar.sole_contact_points():sole_bottom=maxf(sole_bottom,app.camera.unproject_position(point).y)
			var safe:bool=a.is_origin_safe(origin)
			var nearest:Vector2=a._nearest_safe_origin(origin)
			observations.append({"rig":character,"view_pitch":pitch,"foot_px":str(foot),"bounds":str(bounds),"bottom_below_anchor_px":bounds.end.y-foot.y,"actual_mesh_below_anchor_px":true_bottom-foot.y,"actual_sole_below_anchor_px":sole_bottom-foot.y,"floor_placement_safe":safe,"safe_origin_shift":str(nearest-origin)})
			a.free()
	app._on_setting("view_reset",true)
	if app._view_settings.view_yaw_deg!=0 or app._view_settings.view_pitch_deg!=0 or app._view_settings.view_height!=0 or app._view_settings.view_zoom!=1:failures.append("reset")
	var client:=BackendClient.new()
	client.state="open"
	if client.send({"type":"ping"}):failures.append("closed actual WebSocket accepted")
	client.free()
	settings.data=saved
	settings.save_now()
	app.free()
	var hashes:={}
	for name in ["main","settings","backend_client","companion_panel_window","desktop_view"]:hashes[name]=FileAccess.get_sha256("res://scripts/"+name+".gd")
	var result:={"scope":"Actual main camera/frame/pivot methods with networking, UI, autonomy and props setup suppressed; three real rigs. No native panel-focus or seating contact claim.","observations":observations,"pivot_cases":cases,"max_pixel_error":max_error,"failures":failures,"source_hashes":hashes}
	FileAccess.open("res://../diagnostics/desktop_view/floor-current-heading-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(1 if not failures.is_empty() else 0)
