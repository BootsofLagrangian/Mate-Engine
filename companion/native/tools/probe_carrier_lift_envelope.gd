extends SceneTree
var failures:=0
var capsule_reference:Dictionary={}
var capsule_error:=0.0
var pose_read_error:=0.0
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
 var shear:=Basis(Vector3(.001,0,0),Vector3(.0005,.001,0),Vector3(0,0,.001))
 if RigBodyCapsules.scale_bound(shear)<.0012807764:failures+=1
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
  var overflow:=0.0;var mutation:=0.0;var margin:=0.0;var max_query_us:=0
  var envelope:Dictionary={}
  for frame in 483:
   var lift:=float(frame)/241 if frame<=241 else float(482-frame)/241
   p.set_seated_carrier(lift,0);p._process(1.0/60)
   var poses:Array=[]
   for idx in a.skeleton.get_bone_count():poses.append(a.skeleton.get_bone_pose(idx))
   var before_diag:=p.seated_carrier.diagnostics.duplicate(true)
   var before_elapsed:=p.elapsed;var before_start:=p._seated_idle_start
   var started:=Time.get_ticks_usec()
   envelope=p.seated_carrier_lift_envelope()
   max_query_us=maxi(max_query_us,Time.get_ticks_usec()-started)
   if envelope.is_empty():failures+=1;continue
   margin=maxf(margin,envelope.maximum_margin_m)
   var actual:=a.body_capsule_snapshot()
   for capsule in actual.capsules:
    var best:=INF
    for bound in envelope.capsules:
     if bound.id!=capsule.id:continue
     if bound.has("interval") and (lift<bound.interval[0] or lift>bound.interval[1]):continue
     var extra:float=maxf(Vector3(capsule.a).distance_to(bound.a),Vector3(capsule.b).distance_to(bound.b))+capsule.radius-bound.radius
     best=minf(best,extra)
    overflow=maxf(overflow,best)
   for idx in poses.size():
    var current:=a.skeleton.get_bone_pose(idx)
    mutation=maxf(mutation,current.origin.distance_to(poses[idx].origin))
    for axis in 3:mutation=maxf(mutation,current.basis[axis].distance_to(poses[idx].basis[axis]))
   if before_diag!=p.seated_carrier.diagnostics or before_elapsed!=p.elapsed or before_start!=p._seated_idle_start:failures+=1
  if overflow>0 or mutation>0:failures+=1
  rows.append({"character":character,"overflow_m":overflow,"pose_mutation":mutation,"maximum_margin_m":margin,"numeric_guard_m":envelope.get("numeric_guard_m",0),"max_query_us":max_query_us,"samples":483,"capsules":envelope.get("capsules",[]).size()})
  p.free();a.free()
 FileAccess.open("/tmp/lift-envelope.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 print("LIFT_ENVELOPE_FAILURES=",failures);quit(failures)
