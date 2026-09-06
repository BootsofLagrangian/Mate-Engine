extends SceneTree
var failures:=0
var reports:Array=[]
func _init()->void:call_deferred("run")
func mesh_min(p:MotionPlayer)->float:
 var lowest:=INF;var sk:=p.avatar.skeleton
 for side in p.authored_seated_feet.foot_vertices:
  for candidate in p.authored_seated_feet.foot_vertices[side]:
   var point:=Vector3.ZERO
   for bind in candidate.influences:point+=(sk.get_bone_global_pose(bind[0])*bind[1]*candidate.vertex)*bind[2]
   lowest=minf(lowest,(sk.global_transform*(point/candidate.total)).y)
 return lowest
func run()->void:
 for character in (["hachimi"] if OS.get_environment("CONTACT_MINI")=="1" else ["cheval-grand","rice-shower","eishin-flash"]):
  for fps in [30,60]:
   for sizing in ["source","fixed"]:
    if character=="hachimi" and sizing=="fixed":continue
    var a:=VrmAvatar.new();root.add_child(a)
    a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
    a.set_process(false)
    var pet_scale:float=float(OS.get_environment("CONTACT_SCALE")) if not OS.get_environment("CONTACT_SCALE").is_empty() else 1.0
    a.scale=Vector3.ONE*pet_scale
    a.rotation.y=deg_to_rad(float(OS.get_environment("CONTACT_YAW")))
    var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.idle_enabled=false;p.gaze_enabled=false
    for name in ["sit_enter","sit_idle","sit_exit"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
    p.register_seated_transition("enter","sit_enter");p.register_seated_transition("exit","sit_exit")
    for frame in 60:p._process(1.0/fps)
    var required:=p.seated_transition_requirements("enter")
    var clearance:float=required.source_seat_clearance_local if sizing=="source" else .48
    if not p.set_seated_floor(clearance):
     failures+=1;print("FLOOR_REJECTED ",character," ",clearance);p.free();a.free();continue
    var initial_floor:float=a.sole_calibration.floor_y
    var initial_floor_world:=initial_floor*pet_scale
    var geometry:=a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
    var endpoint:Vector3=required.source_full_endpoint_hips_local
    var delta:=Vector3(endpoint.x*1.2,clearance+initial_floor-Vector3(geometry.anchor).y,endpoint.z*1.2)
    var row:Dictionary={"character":character,"fps":fps,"sizing":sizing,"scale":pet_scale,"yaw":a.rotation.y,"clearance":clearance,"root_delta":delta,"stages":[]}
    for kind in ["enter","exit"]:
     var origin:=a.position;var displacement:=delta if kind=="enter" else -delta
     if not p.start_seated_transition(kind,displacement):failures+=1;continue
     var preparation:Dictionary=p.seated_transition_state().get("preparation",{}).duplicate()
     var minimum:=INF;var maximum_residual:=0.0;var limited_frames:=0;var peak_step:=0.0;var previous:Dictionary={};var peak_us:=0
     for frame in int(ceil(p.seated_transition.duration*fps))+1:
      var started:=Time.get_ticks_usec();p._process(1.0/fps);peak_us=maxi(peak_us,Time.get_ticks_usec()-started)
      var state:=p.seated_transition_state();a.position=origin+a.global_basis*displacement*float(state.root_progress)
      minimum=minf(minimum,mesh_min(p)-initial_floor_world)
      var points:=p.authored_seated_feet.live_world()
      if not previous.is_empty():
       for name in points:peak_step=maxf(peak_step,points[name].distance_to(previous[name]))
      previous=points
      for side in p.authored_seated_feet.diagnostics:
       var contact:Dictionary=p.authored_seated_feet.diagnostics[side]
       if contact.limited:limited_frames+=1
       if contact.ownership>=.999 and contact.planned_weight>=.999:maximum_residual=maxf(maximum_residual,Vector3(contact.residual_local).length())
     var before:=p.authored_seated_feet.live_world()
     p.finish_seated_transition();p._process(1.0/fps)
     var after:=p.authored_seated_feet.live_world();var handoff:=0.0
     for name in before:handoff=maxf(handoff,before[name].distance_to(after[name]))
     var hold_min:=INF
     for frame in fps:
      p._process(1.0/fps);hold_min=minf(hold_min,mesh_min(p)-initial_floor_world)
     var stage:Dictionary={"kind":kind,"preparation":preparation,"mesh_min":minimum,"hold_mesh_min":hold_min,"planned_residual":maximum_residual,"limited_frames":limited_frames,"max_marker_step":peak_step,"handoff_marker_step":handoff,"peak_motion_us":peak_us}
     row.stages.append(stage)
     # Full shoe geometry, not ankle-height proxy; floating/liftoff is reported separately.
     if minimum<-.001 or hold_min<-.001 or maximum_residual>.003 or limited_frames>0 or handoff>.003:failures+=1
    p.reset_all()
    if p.authored_seated_feet.active:failures+=1
    reports.append(row);print(JSON.stringify(row));p.free();a.free()
 var out:=FileAccess.open("/tmp/authored-contact-path-hachimi.json" if OS.get_environment("CONTACT_MINI")=="1" else "/tmp/authored-contact-path.json",FileAccess.WRITE);out.store_string(JSON.stringify({"failures":failures,"cases":reports},"  "))
 print("CONTACT_PATH_FAILURES=",failures);quit(1 if failures else 0)
