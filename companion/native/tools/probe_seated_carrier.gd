extends SceneTree
var failures:=0
var rows:Array=[]
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
 for character in ["cheval-grand","rice-shower","eishin-flash","mambo","hachimi"]:
  var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"));a.set_process(false)
  var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.idle_enabled=false;p.gaze_enabled=false
  for name in ["sit_enter","sit_idle","sit_exit"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
  p.register_seated_transition("enter","sit_enter");p.register_seated_transition("exit","sit_exit")
  p._process(1.0/60)
  if p.set_seated_carrier(1,0):failures+=1
  var clearance:float=p.seated_transition_requirements("enter").source_seat_clearance_local
  p.set_seated_floor(clearance);var geometry:=a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
  var floor_y:float=a.sole_calibration.floor_y
  var entry_delta:Vector3=p.seated_transition_requirements("enter").source_full_endpoint_hips_local*1.2
  entry_delta.y=clearance+floor_y-Vector3(geometry.anchor).y
  p.start_seated_transition("enter",entry_delta)
  for frame in 84:
   p._process(1.0/60)
   a.position=entry_delta*float(p.seated_transition_state().root_progress)
  p.finish_seated_transition()
  var seated_origin:=a.position
  for frame in 60:p._process(1.0/60)
  var minimum:=INF;var carried_min:=INF;var maximum_error:=0.0;var maximum_hip_motion:=0.0;var peak_step:=0.0;var ready_frames:=0;var reference_hips:=a.get_hips_offset();var previous:Dictionary={}
  for frame in 156:
   var lift:=1.0
   if frame<36:lift=MotionPlayer._blend_weight(float(frame)/35)
   if frame>=120:lift=1-MotionPlayer._blend_weight(float(frame-120)/35)
   var travel:=clampf(float(frame-36)/83,0,1)
   var yaw:=travel*PI/2
   if not p.set_seated_carrier(lift,yaw):failures+=1
   a.position.z=seated_origin.z+travel*.3
   p._process(1.0/60)
   var state:=p.seated_carrier_state()
   var bottom:=mesh_min(p)-floor_y
   minimum=minf(minimum,bottom)
   maximum_error=maxf(maximum_error,float(state.reach_error_local))
   maximum_hip_motion=maxf(maximum_hip_motion,a.get_hips_offset().distance_to(reference_hips))
   var points:=p.authored_seated_feet.live_world()
   if not previous.is_empty():
    for name in points:peak_step=maxf(peak_step,points[name].distance_to(previous[name]))
   previous=points
   if frame>=36 and frame<120:
    carried_min=minf(carried_min,bottom)
    if state.ready:ready_frames+=1
    if state.limited or not state.ready or bottom<float(state.clearance_local)*.85:failures+=1
  var before:=p.authored_seated_feet.live_world();p.clear_seated_carrier();p._process(1.0/60);var after:=p.authored_seated_feet.live_world();var handoff:=0.0
  for name in before:handoff=maxf(handoff,before[name].distance_to(after[name]))
  if minimum<-.001 or maximum_hip_motion>.00001 or handoff>.002:failures+=1
  p.reset_all()
  if p.seated_carrier.active:failures+=1
  rows.append({"character":character,"minimum_sole_gap":minimum,"carried_minimum_gap":carried_min,"reach_error":maximum_error,"hips_local_motion":maximum_hip_motion,"max_marker_step":peak_step,"lowered_handoff":handoff,"ready_frames":ready_frames})
  p.free();a.free()
 FileAccess.open("/tmp/seated-carrier.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 print("SEATED_CARRIER_FAILURES=",failures);quit(failures)
