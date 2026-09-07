class_name DesktopSeatedCarrierSweep
extends RefCounted
## Conservative continuous sweep of a frozen, rig-derived capsule approximation.
## Own-seat support is excluded only by fixed_solids; the real desk stays solid.
const Parts = preload("desktop_scene_solids.gd")
const RigCapsules = preload("rig_body_capsules.gd")

static func fixed_solids(scene:DesktopObjectContactScene,other_world_boxes:Array=[])->Array:
 var result:Array=other_world_boxes.duplicate()
 if not is_instance_valid(scene) or not scene.supports_seat_setup():return result
 for child in scene._content.get_children():
  if child!=scene.seat_node():_append_fixed(child,result)
 return result

static func _append_fixed(node:Node,output:Array)->void:
 if node is MeshInstance3D and node.mesh!=null:
  for box in Parts.local_parts(node.mesh):output.append({"bounds":box,"transform":node.global_transform,"id":str(node.get_path())})
 for child in node.get_children():_append_fixed(child,output)

static func check(scene:DesktopObjectContactScene,snapshot:Dictionary,target_pull:float,target_yaw:float,solids:Array,expected_model_id:int)->Dictionary:
 if not is_instance_valid(scene) or not scene.supports_seat_setup():return {"accepted":false,"reason":"seat_setup_unsupported"}
 if snapshot.get("space","")!="avatar_local" or int(snapshot.get("model_id",-1))!=expected_model_id or not snapshot.get("transform") is Transform3D or not snapshot.get("capsules") is Array or snapshot.capsules.is_empty():return {"accepted":false,"reason":"invalid_body_snapshot"}
 var original:=scene.seat_setup()
 var stationary:=is_equal_approx(target_pull,float(original.pullout_local_m)) and absf(angle_difference(deg_to_rad(target_yaw),deg_to_rad(float(original.yaw_delta_deg))))<.000001
 if not bool(snapshot.get("articulation_frozen",false)) and not (stationary and bool(snapshot.get("articulation_enclosed",false))):return {"accepted":false,"reason":"body_articulation_not_frozen"}
 var from:Transform3D=scene.seat_node().global_transform
 if not scene.set_seat_setup(target_pull,target_yaw):return {"accepted":false,"reason":"invalid_setup_target"}
 var to:Transform3D=scene.seat_node().global_transform
 scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
 var body:Transform3D=snapshot.transform
 if not body.is_finite() or not from.is_finite() or not to.is_finite():return {"accepted":false,"reason":"nonfinite_body_transform"}
 var attachment:=from.affine_inverse()*body
 var angle:=from.basis.orthonormalized().get_rotation_quaternion().angle_to(to.basis.orthonormalized().get_rotation_quaternion())
 var count:=maxi(1,maxi(ceili(angle/deg_to_rad(5)),ceili(from.origin.distance_to(to.origin)/.025)))
 if count>256:return {"accepted":false,"reason":"carrier_path_too_large"}
 var obstacles:Array=[]
 for value in solids:
  var box:AABB
  var transform:=Transform3D.IDENTITY
  var id:=""
  if value is AABB:box=value
  elif value is Dictionary and value.get("bounds") is AABB and value.get("transform") is Transform3D:
   box=value.bounds;transform=value.transform;id=str(value.get("id",""))
  else:return {"accepted":false,"reason":"invalid_carrier_obstacle"}
  if not box.position.is_finite() or not box.size.is_finite() or not transform.is_finite() or absf(transform.basis.determinant())<.0000001:return {"accepted":false,"reason":"invalid_carrier_obstacle"}
  obstacles.append({"box":box,"inverse":transform.affine_inverse(),"id":id})
 var body_scale:=RigCapsules.scale_bound(body.basis)
 var support_scale:=RigCapsules.scale_bound(from.basis)
 var result_bounds:=AABB()
 var first:=true
 var started:=Time.get_ticks_usec()
 for capsule in snapshot.capsules:
  if not capsule is Dictionary or not capsule.get("a") is Vector3 or not capsule.get("b") is Vector3 or not Vector3(capsule.a).is_finite() or not Vector3(capsule.b).is_finite() or not is_finite(float(capsule.get("radius",NAN))) or float(capsule.radius)<=0:return {"accepted":false,"reason":"invalid_body_capsule"}
  var a:Vector3=attachment*Vector3(capsule.a)
  var b:Vector3=attachment*Vector3(capsule.b)
  var radius:=float(capsule.radius)*body_scale
  var arc_pad:=maxf(a.length(),b.length())*support_scale*(1-cos(angle/count*.5))+.000001
  var before_a:=from*a;var before_b:=from*b
  for step in count:
   var next:=from.interpolate_with(to,float(step+1)/count)
   var after_a:=next*a;var after_b:=next*b
   var points:Array[Vector3]=[before_a,before_b,after_a,after_b]
   var segment_bounds:=AABB(before_a,Vector3.ZERO)
   for p in points:segment_bounds=segment_bounds.expand(p)
   segment_bounds=segment_bounds.grow(radius+arc_pad)
   result_bounds=segment_bounds if first else result_bounds.merge(segment_bounds);first=false
   for index in obstacles.size():
    var obstacle:Dictionary=obstacles[index]
    var inverse:Transform3D=obstacle.inverse
    var local_points:Array[Vector3]=[]
    for p in points:local_points.append(inverse*p)
    var expanded:AABB=AABB(obstacle.box).grow((radius+arc_pad)*RigCapsules.scale_bound(inverse.basis))
    if _hull_intersects_box(local_points,expanded):return {"accepted":false,"reason":"occupied_sweep_blocked","blocked_body_id":str(capsule.get("id","")),"obstacle_index":index,"obstacle_id":obstacle.id,"sweep_segment":step,"body_bounds_world":result_bounds,"validation_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":snapshot.get("scope","")}
   before_a=after_a;before_b=after_b
 return {"accepted":true,"reason":"clear","body_bounds_world":result_bounds,"target_avatar_transform":to*attachment,"segments":count,"validation_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":snapshot.get("scope","")}

static func check_stationary_envelope(scene:DesktopObjectContactScene,envelope:Dictionary,solids:Array,expected_model_id:int)->Dictionary:
 if not is_instance_valid(scene):return {"accepted":false,"reason":"seat_setup_unsupported"}
 var setup:=scene.seat_setup()
 return check(scene,envelope,float(setup.pullout_local_m),float(setup.yaw_delta_deg),solids,expected_model_id)

## SAT for the convex hull of four centerline endpoints against an expanded box.
## This encloses all interpolated capsule centerlines, including nonplanar ones.
static func _hull_intersects_box(points:Array[Vector3],box:AABB)->bool:
 var center:=box.get_center();var extent:=box.size*.5
 var axes:Array[Vector3]=[Vector3.RIGHT,Vector3.UP,Vector3.BACK]
 for i in 4:
  for j in range(i+1,4):
   var edge:=points[j]-points[i]
   for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:axes.append(edge.cross(axis))
 for face in [[0,1,2],[0,1,3],[0,2,3],[1,2,3]]:axes.append((points[face[1]]-points[face[0]]).cross(points[face[2]]-points[face[0]]))
 for axis in axes:
  if axis.length_squared()<1e-16:continue
  var low:=INF;var high:=-INF
  for point in points:
   var projected:float=axis.dot(point-center)
   low=minf(low,projected);high=maxf(high,projected)
  var radius:=absf(axis.x)*extent.x+absf(axis.y)*extent.y+absf(axis.z)*extent.z
  if low>radius or high < -radius:return false
 return true
