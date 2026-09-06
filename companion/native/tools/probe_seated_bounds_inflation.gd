extends SceneTree
func _init():call_deferred("run")
func run():
 var rows:Array=[]
 for fps in [60]:
  for character in ["cheval-grand","rice-shower","eishin-flash"]:
   var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
   var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.idle_enabled=false;p.gaze_enabled=false
   for name in ["authored_wave","sit_enter","sit_idle"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
   p.register_seated_transition("enter","sit_enter")
   for frame in fps:p._process(1.0/fps)
   p.play_vrma("authored_wave")
   for frame in int(0.8*fps):p._process(1.0/fps)
   p.start_seated_transition("enter",Vector3(0,-0.3,-0.3))
   var maximum:=0.0
   var lower_extra:=Vector3.ZERO
   var upper_extra:=Vector3.ZERO
   for frame in int(ceil(p.seated_transition.duration*fps)):
    p._process(1.0/fps)
    var state:=p.seated_transition_state()
    var measured:=SeatedGeometryCalibrator.measure(a,{},true,false)
    var wanted:AABB=measured.bounds;var bounds:AABB=state.transition_bounds
    var under:Vector3=bounds.position-wanted.position;var over:Vector3=wanted.end-bounds.end
    var overflow:=maxf(maxf(under.x,maxf(under.y,under.z)),maxf(over.x,maxf(over.y,over.z)))
    maximum=maxf(maximum,overflow)
    lower_extra=lower_extra.max(wanted.position-bounds.position)
    upper_extra=upper_extra.max(bounds.end-wanted.end)
   rows.append({"extra_lower":str(lower_extra),"extra_upper":str(upper_extra),"character":character,"fps":fps,"duration_s":p.seated_transition.duration,"whole_clip_grid_interval_s":p.seated_transition.duration/12,"max_acquisition_bounds_overflow_m":maximum})
   p.free();a.free()
 FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/motion_seams/conservative-full-transition-containment.json"),FileAccess.WRITE).store_string(JSON.stringify(rows,"  ")+"\n")
 print(JSON.stringify(rows));quit()
