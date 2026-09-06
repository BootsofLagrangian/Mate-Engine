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
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		app.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		app._frame_avatar()
		for yaw in [-180.0,-90.0,-45.0,0.0,45.0,90.0,180.0]:
			for pitch in [-60.0,0.0,70.0]:
				for zoom in [0.6,1.0,1.6]:
					for scale in [0.6,1.0]:
						settings.data.merge({"view_yaw_deg":yaw,"view_pitch_deg":pitch,"view_height":0.5,"view_zoom":zoom},true)
						app._pet_scale=scale
						app._apply_view_settings()
						for anchor in ["foot","sit"]:
							app._pivot_kind=anchor
							app._update_avatar_transform(0)
							var actual:Vector2=app.camera.unproject_position(app.avatar.global_transform*Vector3(app._pivot_local[anchor]))
							var error:float=actual.distance_to(app._pivot_px)
							max_error=maxf(max_error,error)
							cases+=1
							if error>0.001 or not app.avatar.global_transform.is_finite():failures.append({"rig":character,"yaw":yaw,"pitch":pitch,"zoom":zoom,"scale":scale,"pivot":anchor,"error":error})
						app._pivot_kind="foot"
	app._on_setting("view_reset",true)
	if app._view_settings!={"view_yaw_deg":0.0,"view_pitch_deg":0.0,"view_height":0.0,"view_zoom":1.0}:failures.append("reset")
	var client:=BackendClient.new()
	client.state="open"
	if client.send({"type":"ping"}):failures.append("closed actual WebSocket accepted")
	client.free()
	settings.data=saved
	settings.save_now()
	app.free()
	var hashes:={}
	for name in ["main","settings","backend_client","companion_panel_window","desktop_view"]:hashes[name]=FileAccess.get_sha256("res://scripts/"+name+".gd")
	var result:={"scope":"Actual main camera/frame/pivot methods with networking, UI, autonomy and props setup suppressed; three real rigs. No native panel-focus or seating contact claim.","pivot_cases":cases,"max_pixel_error":max_error,"failures":failures,"source_hashes":hashes}
	FileAccess.open("res://../diagnostics/desktop_view/main-projection-results.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(1 if not failures.is_empty() else 0)
