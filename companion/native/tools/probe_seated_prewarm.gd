extends SceneTree
var failures:=0
var rows:Array=[]
func _init()->void:call_deferred("run")
func register(p:MotionPlayer)->void:
 for name in ["sit_enter","sit_idle","sit_exit"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
 p.register_seated_transition("enter","sit_enter");p.register_seated_transition("exit","sit_exit")
func run()->void:
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  for order in ["clips_first","model_first","replacement"]:
   var a:=VrmAvatar.new();root.add_child(a)
   var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a
   if order=="clips_first":register(p)
   a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
   if order!="clips_first":
    p._check_model_identity();register(p)
   if order=="replacement":a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
   var poses:Array=[]
   for idx in a.skeleton.get_bone_count():poses.append(a.skeleton.get_bone_pose(idx))
   var start:=Time.get_ticks_usec();p._check_model_identity();var warm_us:=Time.get_ticks_usec()-start
   var pose_error:=0.0
   for idx in poses.size():
    var now:=a.skeleton.get_bone_pose(idx)
    pose_error=maxf(pose_error,now.origin.distance_to(poses[idx].origin))
    for axis in 3:pose_error=maxf(pose_error,now.basis[axis].distance_to(poses[idx].basis[axis]))
   var id:=a.model.get_instance_id()
   var ready:=p.authored_seated_feet.model_id==id and p.authored_seated_feet.markers.size()==4 and TransitionBoundsMeasure._cache.has(id)
   if not ready or pose_error>.000001:failures+=1
   p.idle_enabled=false;p.gaze_enabled=false
   for frame in 2:p._process(1.0/60)
   p.set_seated_floor(.48);var geometry:=a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
   var delta:=Vector3(0,.48+float(a.sole_calibration.floor_y)-Vector3(geometry.anchor).y,0)
   var started:=p.start_seated_transition("enter",delta)
   if not started:failures+=1
   var preparation:Dictionary=p.seated_transition_state().get("preparation",{})
   rows.append({"character":character,"order":order,"warm_us":warm_us,"ready_before_sit":ready,"pose_error":pose_error,"preparation":preparation})
   p.reset_all();p.free();a.free()
 var out:=FileAccess.open("/tmp/seated-prewarm.json",FileAccess.WRITE);out.store_string(JSON.stringify({"failures":failures,"rows":rows},"  "))
 print("SEATED_PREWARM_FAILURES=",failures);quit(failures)
