extends SceneTree
class CaptureIK extends LegIK:
 var requested:Dictionary={}
 func solve(_a:VrmAvatar,side:String,target:Vector3,_weight:float,_basis:Basis=Basis.IDENTITY,_foot:bool=false):
  requested[side]=target
func _init():call_deferred("run")
func run():
 var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
 var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.idle_enabled=false;p.gaze_enabled=false
 for name in ["sit_enter","sit_idle"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
 p.register_seated_transition("enter","sit_enter")
 for frame in 60:p._process(1.0/60)
 p.set_seated_floor(.48);a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
 p.start_seated_transition("enter",Vector3(0,-.3,-.3))
 var states:Dictionary={};var error:=0.0
 for t in [.1,.4,.8,.2,.8,.4,.1]:
  a.apply_pose({});p.seated_transition.time=t;p.seated_transition.apply(p,0)
  var feet:=p.authored_seated_feet.live_local()
  if states.has(t):
   for key in feet:error=maxf(error,Vector3(feet[key]).distance_to(states[t][key]))
  else:states[t]=feet.duplicate(true)
 var diagnostics_before:=p.authored_seated_feet.diagnostics.duplicate(true)
 var preparation_before:=p.seated_transition.preparation.duplicate(true)
 var rejected:=not p.start_seated_transition("enter",Vector3.ZERO)
 var rejected_preserved:=p.seated_transition.preparation==preparation_before
 p.seated_transition._bounds_cache.clear();p.seated_transition._build_bounds(p)
 var diagnostics_restored:=p.authored_seated_feet.diagnostics==diagnostics_before
 a.apply_pose({});p.seated_transition.time=.4;p.seated_transition.apply(p,0)
 for key in states[.4]:error=maxf(error,Vector3(p.authored_seated_feet.live_local()[key]).distance_to(states[.4][key]))
 p.cancel_seated_transition()
 var clip:VrmaClip=p.vrma_clips.sit_idle;var rotations:=clip.sample(0);var hips:=clip.sample_hips_offset(0)
 a.apply_pose({});a.apply_normalized_rotations(rotations,1);a.set_hips_offset(hips*a.skeleton.get_bone_global_rest(a.bone_index.hips).origin.y)
 var feet:=p.authored_seated_feet;feet.prepare(a);feet.begin_reference(rotations,hips,Vector3(2,0,0))
 var sk:=a.skeleton;var u:=sk.get_bone_global_rest(a.bone_index.leftUpperLeg).origin;var k:=sk.get_bone_global_rest(a.bone_index.leftLowerLeg).origin;var f:=sk.get_bone_global_rest(a.bone_index.leftFoot).origin
 var limit:=.2*(u.distance_to(k)+k.distance_to(f));var floor_y:=feet._support_min("left")+limit
 var spy:=CaptureIK.new();feet.leg_ik=spy
 var before:=sk.get_bone_global_pose(a.bone_index.leftFoot).origin
 feet.apply_contact(rotations,hips,1,floor_y)
 var displacement:Vector3=spy.requested.left-before
 var result:Dictionary={"query_order_max_error_m":error,"bounds_restored_contact_diagnostics":diagnostics_restored,"rejected_begin_preserved_preparation":rejected and rejected_preserved,"requested_delta_length_m":displacement.length(),"configured_limit_m":limit,"bounded":displacement.length()<=limit+.000001,"limited_flag":feet.diagnostics.left.limited,"scope":"Deterministic fixed-reference phase queries and deliberately oversized diagonal contact request; no hostgeometryacceptance"}
 FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/authored_foot_contacts/review-order-bounds.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
 print(JSON.stringify(result));p.free();a.free();quit()
