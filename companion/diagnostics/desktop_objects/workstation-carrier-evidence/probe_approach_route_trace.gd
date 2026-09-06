extends SceneTree
const DESKTOP_ORIGIN:=Vector2(940,316)
func _init()->void:call_deferred("run")
func project(camera:Camera3D,points:Array)->Rect2:
 var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
 for point in points:
  var pixel:=camera.unproject_position(point)+DESKTOP_ORIGIN;low=low.min(pixel);high=high.max(pixel)
 return Rect2(low,high-low)
func corners(box:AABB,transform:Transform3D=Transform3D.IDENTITY)->Array:
 var out:Array=[]
 for i in 8:out.append(transform*box.get_endpoint(i))
 return out
func run()->void:
 root.size=Vector2i(680,760)
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(-.698495,1.334204,3.6);camera.fov=45;camera.near=.01;camera.far=100
 var avatar:=VrmAvatar.new();root.add_child(avatar);avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"));avatar.set_process(false)
 var motion:=MotionPlayer.new();root.add_child(motion);motion.avatar=avatar;motion.set_process(false);motion.idle_enabled=false;motion.gaze_enabled=false
 for name in ["sit_enter","sit_idle","sit_exit"]:motion.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
 motion.register_seated_transition("enter","sit_enter");motion.register_seated_transition("exit","sit_exit");motion._process(1.0/60)
 var req:=motion.seated_transition_requirements("enter");motion.set_seated_floor(req.source_seat_clearance_local)
 avatar.calibrate_seated_pose(motion.vrma_clips.sit_idle.sample(0))
 var anchors:=avatar.contact_anchors();var delta:Vector3=req.source_root_delta_local;delta.x*=1.1;delta.z*=1.1
 var target:=Vector3(4.248171,-1.314583,-.102366)
 var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer");scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6);scene.set_seat_scale(float(req.source_seat_clearance_local)/.48);scene.set_seat_setup(.1,144.999995010116)
 var seat:=target+Basis.IDENTITY.scaled(Vector3.ONE*.6)*(Vector3(anchors.sit)-Vector3(anchors.foot)+delta)
 scene.position=seat-scene.socket_world("seat");scene.position.y=target.y
 var setup_box:=AABB(Vector3(-.65,-.000344,-.325),Vector3(1.3,1.189844,1.441179))
 var local_envelope:=project(camera,corners(setup_box,scene.global_transform)).grow(2)
 var world_envelope:=project(camera,corners(scene.global_transform*setup_box)).grow(2)
 scene.set_seat_setup(0,0)
 var runtime_bounds:=project(camera,corners(scene.get_world_bounds()))
 print("PRODUCT_VIEW_REPRO position=",scene.position," anchors=",anchors," workarea=",Rect2(0,0,2560,1392)," local_setup_envelope=",local_envelope," world_setup_envelope=",world_envelope," runtime_rest_bounds=",runtime_bounds)
 var fit_local:=Rect2(0,0,2560,1392).encloses(local_envelope)
 var fit_runtime:=Rect2(0,0,2560,1392).encloses(runtime_bounds)
 print("PRODUCT_VIEW_REPRO local_plan_fit=",fit_local," actual_runtime_fit=",fit_runtime," exact_position_scope=derived_from_recorded_target_plus_current_installed_calibration")
 # Exact object pose from the later product-envelope terminal snapshot.
 scene.global_position=Vector3(3.69327878952026,-1.31458330154419,-.850129127502441)
 scene.set_seat_setup(0,0)
 var actor_geometry:=ProjectedAvatarGeometry.new();actor_geometry.capture(avatar,anchors.foot)
 var areas:Array=[Rect2(0,0,2560,1392),Rect2(2560,0,1920,1032)]
 var query:=func(point:Vector3):return actor_geometry.nearest_safe_ground(camera,point,.6,DESKTOP_ORIGIN,areas,.25)
 var raw_actor:Vector3=DesktopView.solve_screen_at_world_y(camera,Vector2(2382,1392)-DESKTOP_ORIGIN,target.y).point
 var normalized:Dictionary=query.call(raw_actor)
 print("APPROACH_INITIAL_GROUND ",normalized)
 var actor:Vector3=normalized.point
 var fitting:=func(candidate_scene:DesktopObjectContactScene,envelope:AABB):return Rect2(0,0,2560,1392).encloses(project(camera,corners(candidate_scene.get_world_bounds().merge(candidate_scene.global_transform*envelope))).grow(2))
 var route_fitting:=func(path:PackedVector3Array):
  var admission:=DesktopSceneNavigationHost.route_view_admission(path,query,areas)
  var endpoint:Dictionary=query.call(path[-1])
  print("ROUTE_COST_CLASS endpoint_fits=",endpoint.get("ok",false) and not endpoint.get("changed",true)," route_fits=",admission.accepted," target=",path[-1])
  return bool(admission.accepted)
 var source:Vector3=req.source_root_delta_local
 var offset:Vector3=Vector3(anchors.sit)-Vector3(anchors.foot)
 var old_plan:=DesktopWorkstationSetup.plan(scene,actor,.6,offset,source,.072,avatar.compute_aabb().size.y*.6,[],fitting)
 var old_route:=DesktopSceneNavigationHost.route_view_admission(old_plan.approach_path,query,areas) if old_plan.get("accepted",false) else {}
 print("APPROACH_OLD_PLAN ",old_plan.get("accepted")," target=",old_plan.get("target_world")," route=",old_route)
 var plan:=DesktopWorkstationSetup.plan(scene,actor,.6,offset,source,.072,avatar.compute_aabb().size.y*.6,[],fitting,route_fitting,actor_geometry.swept)
 var summary:=plan.duplicate();summary.erase("geometric_candidate");print("APPROACH_ALIGNED_PLAN ",summary)
 var okay:bool=not plan.get("accepted",false) and plan.get("reason")=="setup_view_blocked"
 if okay:
  var original:=scene.global_transform
  var validation_count:Array=[0]
  var proposed_fit:=func(point:Vector3):
   validation_count[0]+=1
   var previous:=scene.global_position;scene.global_position=point
   var candidate:=DesktopWorkstationSetup.plan(scene,actor,.6,offset,source,.072,avatar.compute_aabb().size.y*.6,[],fitting,route_fitting,actor_geometry.swept)
   var geometric:Dictionary=candidate if candidate.get("accepted",false) else candidate.get("geometric_candidate",{})
   print("CANDIDATE_TRACE point=",point," result=",candidate.get("accepted")," factor=",geometric.get("root_distance_factor")," yaw=",geometric.get("entry_facing_yaw")," target=",geometric.get("target_world")," ground=",query.call(geometric.target_world) if geometric.has("target_world") else {})
   scene.global_position=previous
   return bool(candidate.get("accepted",false))
  var reposition_started:=Time.get_ticks_usec()
  var proposal:=DesktopWorkstationSetup.reposition(scene,plan.geometric_candidate,camera,DESKTOP_ORIGIN,areas,actor,.072,avatar.compute_aabb().size.y*.6,[],.9,proposed_fit)
  print("APPROACH_REPOSITION ",proposal," actor=",actor," planning_ms=",(Time.get_ticks_usec()-reposition_started)/1000.0," fresh_candidates=",validation_count[0])
  okay=proposal.get("ok",false) and scene.global_transform==original and absf(Vector3(proposal.point).y-original.origin.y)<.000001
  if okay:
   scene.global_position=proposal.point
   var final_plan:=DesktopWorkstationSetup.plan(scene,actor,.6,offset,source,.072,avatar.compute_aabb().size.y*.6,[],fitting,route_fitting,actor_geometry.swept)
   summary=final_plan.duplicate();summary.erase("setup_parts_local");summary.erase("actor_placement_vertices_local");print("APPROACH_FRESH_PLAN ",summary)
   okay=final_plan.get("accepted",false)
   if okay:
    var continuous_fits:=true
    for phase in 2:
     for sample in 31:
      var t:=float(sample)/30
      scene.set_seat_setup(float(final_plan.pullout_local_m)*t if phase==0 else final_plan.pullout_local_m,0 if phase==0 else float(final_plan.yaw_delta_deg)*t)
      if not Rect2(0,0,2560,1392).encloses(project(camera,corners(scene.get_world_bounds()))):continuous_fits=false
    okay=continuous_fits and route_fitting.call(final_plan.approach_path);print("APPROACH_RUNTIME_62_SETUP_AND_FULL_ROUTE_FIT=",okay)
    # Actual entry measurement for this fixture's live initial pose. It cannot
    # certify the future Windows outgoing walk/secondary pose.
    var heading:float=final_plan.entry_facing_yaw
    avatar.basis=Basis(Vector3.UP,heading).scaled(Vector3.ONE*.6)
    avatar.position=Vector3(final_plan.target_world)-avatar.basis*Vector3(anchors.foot)
    var local_delta:Vector3=avatar.basis.inverse()*(scene.socket_world("seat")-(avatar.position+avatar.basis*Vector3(anchors.sit)))
    motion.start_seated_transition("enter",local_delta)
    var entry:Dictionary=motion.seated_transition_state()
    var entry_rect:=project(camera,corners(entry.transition_bounds,avatar.global_transform)).merge(project(camera,corners(scene.get_world_bounds())))
    var entry_fit:bool=Rect2(0,0,2560,1392).encloses(entry_rect)
    print("APPROACH_FIXTURE_LIVE_ENTRY_BOUNDS ",entry_rect," fit=",entry_fit," scope=current_fixture_outgoing_pose_not_future_windows_boundary")
    okay=okay and entry_fit
    motion.cancel_seated_transition()
 print("APPROACH_FIXED_PASS=",okay)
 scene.free();motion.free();avatar.free();quit(0 if okay else 1)
