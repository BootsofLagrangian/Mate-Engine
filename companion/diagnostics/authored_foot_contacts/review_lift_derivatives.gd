extends SceneTree
const CarrierLiftEnvelope=preload("res://scripts/carrier_lift_envelope.gd")
var failures:=0
var accepted:=0
var rejected:=0
var maximum_overflow:=0.0
func _init()->void:call_deferred("run")
func run()->void:
 var a:=VrmAvatar.new();root.add_child(a)
 var sk:=Skeleton3D.new();a.add_child(sk);a.skeleton=sk
 for name in ["upper","lower","foot"]:sk.add_bone(name)
 sk.set_bone_parent(1,0);sk.set_bone_parent(2,1)
 a.bone_index={"leftUpperLeg":0,"leftLowerLeg":1,"leftFoot":2}
 var solver:=LegIK.new()
 for lengths in [Vector2(.4,.35),Vector2(.2,.45),Vector2(.12,.1)]:
  var u:float=lengths.x;var l:float=lengths.y
  sk.set_bone_rest(0,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
  sk.set_bone_rest(1,Transform3D(Basis.IDENTITY,Vector3(0,-u,0)))
  sk.set_bone_rest(2,Transform3D(Basis.IDENTITY,Vector3(0,-l,0)))
  for direction in [Vector3(.2,-1,.3),Vector3(.2,1,.3),Vector3(.01,-.01,1),Vector3(.3,-.4,.7)]:
   for distance_factor in [.35,.7,.999]:
    sk.reset_bone_poses()
    var hip:=sk.get_bone_global_pose(0).origin
    solver.solve(a,"left",hip+direction.normalized()*(u+l)*distance_factor,1,Basis.IDENTITY,true)
    var q:=sk.get_bone_global_pose(2).origin-hip
    var initial:Array=[]
    for idx in 3:initial.append(sk.get_bone_pose(idx))
    # Deliberately independent clearance, not .04 * posed segment sum.
    var c:float=(u+l)*.07
    for interval in 16:
     var lo:=float(interval)/16;var hi:=float(interval+1)/16
     var bounds:=CarrierLiftEnvelope._interval(q,u,l,c,lo,hi)
     if bounds.is_empty():rejected+=1;continue
     accepted+=1
     var middle:=CarrierLiftEnvelope._pose(q,u,l,c,(lo+hi)*.5)
     for sample in 17:
      var t:=lerpf(lo,hi,float(sample)/16)
      for idx in 3:sk.set_bone_pose(idx,initial[idx])
      solver.solve(a,"left",hip+q+Vector3.UP*c*t,1,Basis.IDENTITY,true)
      var knee:=sk.get_bone_global_pose(1).origin-hip
      var ankle:=sk.get_bone_global_pose(2).origin-hip
      var margin_k:float=bounds.knee_speed*(hi-lo)*.5
      var margin_a:float=bounds.ankle_speed*(hi-lo)*.5
      var overflow:=maxf(knee.distance_to(middle.knee)-margin_k,ankle.distance_to(middle.ankle)-margin_a)
      maximum_overflow=maxf(maximum_overflow,overflow)
      if overflow>(u+l)*.00001:failures+=1
 # Pole fallback and zero-length direction must fail closed.
 if not CarrierLiftEnvelope._interval(Vector3(0,0,.7),.4,.35,.01,0,1).is_empty():failures+=1
 if not CarrierLiftEnvelope._interval(Vector3.ZERO,.4,.35,.01,0,1).is_empty():failures+=1
 var result:={"failures":failures,"accepted_intervals":accepted,"rejected_intervals":rejected,"samples_per_interval":17,"maximum_raw_numeric_overflow_m":maximum_overflow,"guard_fraction_of_leg_length":.00001}
 FileAccess.open("/tmp/lift-derivative-review.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("LIFT_DERIVATIVE_REVIEW=",result)
 a.free();quit(failures)
