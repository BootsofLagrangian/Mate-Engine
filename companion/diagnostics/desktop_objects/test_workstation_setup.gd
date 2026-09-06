extends "test_host_objects.gd"
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	h.avatar.present=true
	var rig_path:=ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm")
	h.avatar.load_from_file(rig_path)
	var old_motion=h.motion;h.motion=MotionPlayer.new();h.add_child(h.motion);old_motion.free()
	h.motion.set_process(false);h.motion.avatar=h.avatar;h.motion.idle_enabled=false;h.motion.gaze_enabled=false
	var prefix=ProjectSettings.globalize_path("res://../assets/research/seating-candidates/uma-canonical/")
	for pair in [["sit_enter","s"],["sit_idle","loop"],["sit_exit","e"]]:h.motion.load_vrma(pair[0],prefix+"uma_sitdown01_"+pair[1]+".vrma")
	h.motion.register_seated_transition("enter","sit_enter");h.motion.register_seated_transition("exit","sit_exit")
	h.camera=Camera3D.new();h.add_child(h.camera);h.camera.current=true;root.size=Vector2i(1920,1760)
	var panel=h.panel;h.panel=null;h._pet_scale=1.0;h._frame_avatar();h.panel=panel
	h.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;h.camera.size=1760.0/332.48
	h._pivot_kind="foot";h._pivot_px=Vector2(960,1200);h._pivot_px_target=h._pivot_px
	h._update_avatar_transform(0)
	h.motion.set_seated_floor(.48);h._ensure_seated_geometry()

	for rig in ["cheval-grand","rice-shower","eishin-flash"]:
		h.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+rig+".vrm"))
		h.avatar.rotation=Vector3.ZERO;h.avatar.scale=Vector3.ONE;h.avatar.position=Vector3.ZERO
		h._pet_scale=.6;h._pivot_local=h.avatar.contact_anchors()
		var req:Dictionary=h.motion.seated_transition_requirements("enter")
		var ratio:float=clampf(float(req.source_seat_clearance_local)/.48,.5,1.25)
		h.motion.set_seated_floor(.48*ratio);h._ensure_seated_geometry()
		var scene:=DesktopObjectContactScene.new();h.add_child(scene);scene.configure("computer")
		scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
		scene.set_seat_scale(ratio)
		var basis:=Basis(Vector3.UP,deg_to_rad(215)).scaled(Vector3.ONE*.6)
		var offset:Vector3=h._pivot_local.sit-h._pivot_local.foot
		var source:Vector3=req.source_root_delta_local
		var solids:Array=[];DesktopObjectsHost._append_scene_solids(scene,solids)
		var start:=Vector3(-1,0,1)
		var radius:=.072
		var height:float=h.avatar.compute_aabb().size.y*.6
		print("RIG ",rig," ratio=",ratio," source=",source," offset=",offset," seat=",scene.socket_world("seat")," parts=",solids.size()," radius=",radius," height=",height)
		for factor in [1.0,1.25]:
			var adjusted:=source;adjusted.x*=factor;adjusted.z*=factor
			var target:=DesktopObjectsHost.authored_staging_foot(scene.socket_world("seat"),basis,offset,adjusted,0)
			var nav:=DesktopSceneNavigation.new()
			var ready:=nav.configure(Rect2(-2,-2,4,4),0,solids,radius,height,DesktopSceneNavigationHost.navigation_cell_size(Vector2(4,4)))
			var plan:=nav.plan("audit",start,target) if ready.get("ok",false) else {}
			print("  FACTOR ",factor," target_local=",scene.to_local(target)," configure=",ready," plan=",plan.get("reason")," nav=",nav.diagnostics)
			nav.dispose()
		var selected:=DesktopObjectsHost.select_authored_staging(start,scene.socket_world("seat"),basis,offset,source,solids,radius,height)
		print("  SELECTED ",selected)
		var setup=load("res://scripts/desktop_workstation_setup.gd").plan(scene,start,.6,offset,source,radius,height,[])
		var summary:Dictionary=setup.duplicate();summary.erase("setup_parts_local");print("  SETUP_PLAN ",summary)
		check(setup.get("accepted",false),"actual "+rig+" has collision-checked entry setup")
		check(scene.seat_setup().pullout_local_m==0.0 and scene.seat_setup().yaw_delta_deg==0.0,"planner restores actual scene after success")
		var keyboard:Vector3=scene.socket_world("keyboard_left")
		var initial_vertices:PackedVector3Array=scene.geometry_points_local()
		if setup.get("accepted",false):
			check(scene.set_seat_setup(setup.pullout_local_m,setup.yaw_delta_deg),"selected setup applies to actual chair")
			check(scene.socket_world("seat").distance_to(scene.seat_node().to_global(Vector3(0,.48,.08)))<.000001,"socket follows actual transformed cushion")
			check(scene.socket_world("keyboard_left")==keyboard,"keyboard remains fixed during chair setup")
			var facing:Vector3=scene.facing_direction_world()
			check(absf(angle_difference(atan2(facing.x,facing.z),setup.entry_facing_yaw))<.000001,"authored entry facing follows actual chair")
			var moved_vertices:PackedVector3Array=scene.geometry_points_local()
			check(moved_vertices.size()==initial_vertices.size() and moved_vertices!=initial_vertices,"exact vertex cache follows movable geometry")
			check(absf(scene.get_local_bounds().position.y)<.00001,"chair movement preserves physical floor")
			check(not scene.set_seat_setup(1.3,0) and not scene.set_seat_setup(.1,NAN),"invalid setup cannot mutate geometry")
			var rejected:Dictionary=DesktopWorkstationSetup.plan(scene,start,.6,offset,source,radius,height,[])
			check(scene.seat_setup().pullout_local_m==setup.pullout_local_m and scene.seat_setup().yaw_delta_deg==setup.yaw_delta_deg,"planning starts and restores actual displaced setup without reset")
			var reverse:Dictionary=DesktopWorkstationSetup.validate_setup_sweep(scene,setup.pullout_local_m,0,start,radius,height,[])
			check(reverse.get("clear",false) and scene.seat_setup().yaw_delta_deg==setup.yaw_delta_deg,"reverse swivel validation restores current geometry")
			var blocked_actor:=scene.socket_world("seat");blocked_actor.y=0
			var blocked:Dictionary=DesktopWorkstationSetup.validate_setup_sweep(scene,setup.pullout_local_m,0,blocked_actor,radius,height,[])
			check(not blocked.get("clear",true) and blocked.reason=="chair_sweep_hits_actor" and scene.seat_setup().yaw_delta_deg==setup.yaw_delta_deg,"actor at exit sweep blocks restoration without snapping chair")
			var clearance:Dictionary=DesktopWorkstationSetup.find_restore_clearance(scene,setup.target_world,radius,height,[],Callable(),func(_point):return true,.5)
			var clearance_summary:=clearance.duplicate();clearance_summary.erase("swivel");clearance_summary.erase("roll");print("  RESTORE_CLEARANCE ",clearance_summary)
			check(clearance.get("accepted",false),"actual "+rig+" has navigable exit clearance before empty restore")
			check(scene.seat_setup().pullout_local_m==setup.pullout_local_m and scene.seat_setup().yaw_delta_deg==setup.yaw_delta_deg,"clearance search restores actual chair pose")
			if clearance.get("accepted",false):
				check(absf(Vector3(clearance.target_world).y-Vector3(setup.target_world).y)<.000001 and Vector3(clearance.target_world).distance_to(setup.target_world)<=.500001,"clearance is bounded and preserves floorY")
				check(clearance.swivel.accepted and clearance.roll.accepted and not clearance.path.is_empty(),"both empty restore phases and actual route accepted")
			var view_rejected:Dictionary=DesktopWorkstationSetup.find_restore_clearance(scene,setup.target_world,radius,height,[],Callable(),func(_point):return false,.1)
			check(not view_rejected.accepted and view_rejected.reason=="restore_actor_view_blocked","ground view rejection prevents clearance route")
			check(scene.seat_setup().pullout_local_m==setup.pullout_local_m and scene.seat_setup().yaw_delta_deg==setup.yaw_delta_deg,"failed clearance search preserves chair")
			scene.set_seat_setup(0,0)
			check(scene.socket_world("keyboard_left")==keyboard and scene.geometry_points_local()==initial_vertices,"setup round-trip restores exact keyboard and vertices")
			var envelope:AABB=AABB(setup.setup_bounds_local).grow(.000001)
			var contained:=true
			for sample in 13:
				scene.set_seat_setup(setup.pullout_local_m,setup.yaw_delta_deg*float(sample)/12)
				for vertex in scene.geometry_points_local():
					if not envelope.has_point(vertex):contained=false;break
			check(contained,"returned continuous setup envelope contains intermediate actual imported vertices")
			scene.set_seat_setup(0,0)
			var position_before:Vector3=scene.global_position
			var proposal:Dictionary=DesktopWorkstationSetup.reposition(scene,setup,h.camera,Vector2.ZERO,[Rect2(-10000,-10000,20000,20000)],start,radius,height,[],.9)
			check(proposal.get("ok",false) and absf(Vector3(proposal.point).y-position_before.y)<.000001,"full setup envelope re-placement preserves physical groundY")
			check(scene.global_position==position_before and scene.seat_setup().pullout_local_m==0.0,"re-placement only proposes and never commits geometry")
		if rig=="cheval-grand":
			var hidden:Dictionary=DesktopWorkstationSetup.plan(scene,start,.6,offset,source,radius,height,[],func(_scene,_envelope):return false)
			check(not hidden.accepted and hidden.reason=="setup_view_blocked" and not hidden.geometric_candidate.is_empty(),"view failure retains geometric candidate for honest bounded reposition")
			check(scene.seat_setup().pullout_local_m==0.0 and scene.seat_setup().yaw_delta_deg==0.0,"view failure restores geometry")
		print("  RESTORED ",scene.seat_setup())
		scene.free()
	h.free();print("Workstation setup: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func print_blockers(node:Node,target:Vector3,radius:float,height:float):
	if node is MeshInstance3D and node.mesh!=null:
		for box in DesktopSceneSolids.local_parts(node.mesh):
			var world:AABB=node.global_transform*AABB(box)
			if world.end.y<=0 or world.position.y>=height:continue
			var rect:=Rect2(Vector2(world.position.x,world.position.z),Vector2(world.size.x,world.size.z)).grow(radius)
			if rect.has_point(Vector2(target.x,target.z)) and "keycap" not in node.name:print("    BLOCKER ",node.get_path()," aabb=",world)
	for child in node.get_children():print_blockers(child,target,radius,height)
