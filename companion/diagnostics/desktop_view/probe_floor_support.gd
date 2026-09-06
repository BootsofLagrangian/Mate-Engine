extends SceneTree
var failures:=[]
var results:=[]
func _init() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(680,760)
	await process_frame
	var settings:=root.get_node("Settings")
	var saved:Dictionary=settings.data.duplicate(true)
	var script:=GDScript.new()
	script.source_code="extends \"res://scripts/main.gd\"\nfunc _ready() -> void: set_process(false)\n"
	if script.reload()!=OK:quit(2);return
	var app=script.new();root.add_child(app)
	app._setup_scene()
	app.avatar=VrmAvatar.new();app.add_child(app.avatar)
	app.motion=MotionPlayer.new();app.add_child(app.motion);app.motion.set_process(false);app.motion.avatar=app.avatar
	var area:=Rect2(0,0,2560,1440)
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		app.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		app._frame_avatar()
		for yaw in [0.0,45.0,90.0]:
			for pitch in [0.0,45.0,70.0]:
				for scale in [0.6,1.0]:
					settings.data.merge({"view_projection":"orthographic","view_yaw_deg":yaw,"view_pitch_deg":pitch,"view_height":0.0,"view_zoom":1.0},true)
					app._pet_scale=scale
					app.avatar.rotation.y=deg_to_rad(-82)
					app._apply_view_settings()
					app._projection_follow_state.clear()
					var anchor:Vector2=app._projected_anchors().foot
					var a:=DesktopAutonomy.new();root.add_child(a);a.set_process(false);app.autonomy=a
					a.projection_commit_callback=app._finalize_projection_placement
					a.configure_simulation([area],Vector2(1100,1440)-anchor,app._navigation_rect())
					a.update_context(false,false,false,false,false)
					a.surface_mode=true;a.enabled=true;a._time=10;a._settle_until=0;a._state_until=10000;a._next_decision=10000;a.state="rest";a._needs_clamp=false
					a.set_world_snapshot({"monitors":[{"id":"test","work_x":0,"work_y":0,"work_width":2560,"work_height":1440}],"windows":[]})
					a._support=a._surfaces.get_surfaces(1)[0].duplicate()
					a._locked_anchor=anchor;a._anchors={"foot":anchor};a.target=a.position
					var frame_delta:=[Vector2.ZERO]
					a.frame_moved.connect(func(displacement:Vector2,_velocity:Vector2):frame_delta[0]=displacement)
					var max_gap:=0.0
					var max_contact_error:=0.0
					var max_signal_error:=0.0
					var max_world_delta_error:=0.0
					var duplicate_samples:=0
					var unsafe:=0
					var detached:=0
					for frame in 121:
						var before:=a.position.round()
						app.avatar.rotation.y=deg_to_rad(-82+164*float(frame)/120)
						app._update_avatar_transform(0)
						var world_before:Vector3=app.avatar.global_transform*Vector3(app._pivot_local.foot)
						app._projection_world_before=world_before
						app._update_pet_rect()
						app._follow_standing_projection()
						a.set_visible_bounds(app._navigation_rect())
						a.set_contact_anchors(app._projected_anchors())
						a.advance(1.0/60)
						var measured_delta:Variant=app.take_projection_world_delta()
						max_world_delta_error=maxf(max_world_delta_error,Vector3(measured_delta).distance_to(app.avatar.global_transform*Vector3(app._pivot_local.foot)-world_before))
						if app.take_projection_world_delta()!=null:duplicate_samples+=1
						var body:Rect2=app._projection_geometry.body_rect(app.camera,app.avatar.global_transform)
						max_gap=maxf(max_gap,absf(area.end.y-(a.position.round().y+body.end.y)))
						max_contact_error=maxf(max_contact_error,absf((a.position.round()+Vector2(app._projected_anchors().foot)).y-area.end.y))
						max_signal_error=maxf(max_signal_error,Vector2(frame_delta[0]).distance_to(a.position.round()-before))
						if not a.is_origin_safe(a.position.round()):unsafe+=1
						if not bool(a.get_support_contact().attached):detached+=1
					var before_block:=a.position
					a._blocked=true
					var rejected:=not a.refresh_foot_projection(a.visible_bounds,Vector2(a._locked_anchor)+Vector2(0,2)) and a.position==before_block
					var cell:={"rig":character,"view_yaw":yaw,"view_pitch":pitch,"scale":scale,"heading_frames":121,"max_rest_outline_gap_px":max_gap,"max_floor_reference_error_px":max_contact_error,"max_committed_signal_error_px":max_signal_error,"world_delta_error_m":max_world_delta_error,"duplicate_samples":duplicate_samples,"unsafe_frames":unsafe,"detached_frames":detached,"blocked_follow_rejected":rejected,"hull_points":app._projection_geometry.points.size(),"source_vertices":app._projection_geometry.source_vertex_count}
					results.append(cell)
					if max_world_delta_error>0.000001 or duplicate_samples>0 or max_gap>1.01 or max_contact_error>0.001 or max_signal_error>0.001 or unsafe>0 or detached>0 or not rejected:failures.append(cell)
					a.free();app.autonomy=null
	settings.data=saved;settings.save_now();app.free()
	var hashes:={}
	for name in ["main","projected_avatar_geometry","desktop_autonomy","desktop_view"]:hashes[name]=FileAccess.get_sha256("res://scripts/"+name+".gd")
	var report:={"scope":"Actual main restmesh projection plus explicit standing-support follow, simulated rounded OS origin, three rigs; no live gait or animated soles/Windows rendering claim.","cells":results,"failures":failures,"source_hashes":hashes}
	FileAccess.open("res://../diagnostics/desktop_view/floor-support-commit-results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FLOOR_SUPPORT cells=",results.size()," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
