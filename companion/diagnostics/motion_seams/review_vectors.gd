extends SceneTree
var rows:Array=[]
var failures:=0
func _init():call_deferred("run")
func velocity(before:Quaternion,after:Quaternion,dt:float)->Vector3:
 var change:Quaternion=(after*before.inverse()).normalized()
 if change.w<0:change=Quaternion(-change.x,-change.y,-change.z,-change.w)
 var v:=Vector3(change.x,change.y,change.z)
 return v.normalized()*2*atan2(v.length(),change.w)/dt if v.length()>0.0000001 else Vector3.ZERO
func pose(a:VrmAvatar)->Quaternion:
 return a.skeleton.get_bone_global_pose(a.bone_index.rightHand).basis.orthonormalized().get_rotation_quaternion()
func run():
 var bank:=MotionBank.parse_json_text(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../Assets/StreamingAssets/cheval-motions.json")))
 for fps in [60,120,240]:
  for mode in ["clip_clip","clip_idle","walking_upper","seated_entry"]:
   var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
   var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.set_bank(bank);p.idle_enabled=false;p.gaze_enabled=false
   for name in ["authored_wave","authored_bow","uma_walk","sit_enter","sit_idle"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
   p.register_locomotion_clip("uma_walk",true);p.register_seated_transition("enter","sit_enter")
   for i in fps:p._process(1.0/fps)
   if mode=="walking_upper":p.play_vrma("uma_walk",1,true)
   else:p.play_vrma("authored_wave")
   var previous:=pose(a);var outgoing:=Vector3.ZERO
   var frames:int=2*fps if mode=="walking_upper" else int(0.8*fps)
   for i in frames:
    if mode=="walking_upper" and i==fps:p.play_upper_body_gesture("wave")
    p._process(1.0/fps)
    if mode=="walking_upper":p.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
    var current:=pose(a);outgoing=velocity(previous,current,1.0/fps);previous=current
   if mode=="clip_clip":p.play_vrma("authored_bow")
   elif mode=="clip_idle":p.stop_gesture()
   elif mode=="walking_upper":p.finish_locomotion();p.play_gesture("bow")
   else:
    if not p.start_seated_transition("enter",Vector3(0,-0.3,-0.3)):failures+=1
   p._process(1.0/fps)
   var incoming:=velocity(previous,pose(a),1.0/fps)
   var cosine:=outgoing.normalized().dot(incoming.normalized())
   var error:float=(incoming-outgoing).length()/maxf(outgoing.length(),0.00001)
   rows.append({"fps":fps,"mode":mode,"outgoing_deg_s":rad_to_deg(outgoing.length()),"incoming_deg_s":rad_to_deg(incoming.length()),"direction_cosine":cosine,"relative_vector_error":error,"upper_active":p.is_upper_body_active()})
   if cosine<0.97 or (fps==240 and error>0.04):failures+=1
   if mode in ["walking_upper","seated_entry"] and p.is_upper_body_active():failures+=1
   if mode=="seated_entry":
    p.cancel_seated_transition()
    if p.seated_transition.active or p.current_contact_pose()!="foot" or not p.seated_transition._from_velocity.is_empty():failures+=1
    p._process(1.0/fps)
    if not pose(a).is_finite():failures+=1
   p.free();a.free()
 var output:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/motion_seams/review-vectors.json"),FileAccess.WRITE)
 output.store_string(JSON.stringify({"failures":failures,"rows":rows},"  ")+"\n")
 print("INDEPENDENT_SEAM_VECTOR_FAILURES=",failures);quit(1 if failures else 0)
