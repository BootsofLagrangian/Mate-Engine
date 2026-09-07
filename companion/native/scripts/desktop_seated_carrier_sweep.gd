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

static func check(scene:DesktopObjectContactScene,snapshot:Dictionary,target_pull:float,target_yaw:float,solids:Array,expected_model_id:int,trajectory:Array=[])->Dictionary:
 if not is_instance_valid(scene) or not scene.supports_seat_setup():return {"accepted":false,"reason":"seat_setup_unsupported"}
 if snapshot.get("space","")!="avatar_local" or int(snapshot.get("model_id",-1))!=expected_model_id or not snapshot.get("transform") is Transform3D or not snapshot.get("capsules") is Array or snapshot.capsules.is_empty():return {"accepted":false,"reason":"invalid_body_snapshot"}
 if not is_finite(target_pull) or not is_finite(target_yaw) or absf(target_yaw)>180.0:return {"accepted":false,"reason":"invalid_setup_target"}
 var path:=_validate_trajectory(trajectory)
 if path.is_empty():return {"accepted":false,"reason":"invalid_carrier_trajectory"}
 var original:=scene.seat_setup()
 var stationary:=is_equal_approx(target_pull,float(original.pullout_local_m)) and absf(angle_difference(deg_to_rad(target_yaw),deg_to_rad(float(original.yaw_delta_deg))))<.000001
 if not bool(snapshot.get("articulation_frozen",false)) and not (stationary and bool(snapshot.get("articulation_enclosed",false))):return {"accepted":false,"reason":"body_articulation_not_frozen"}
 var from:Transform3D=scene.seat_node().global_transform
 var body:Transform3D=snapshot.transform
 if not body.is_finite() or not from.is_finite() or absf(from.basis.determinant())<.0000001:return {"accepted":false,"reason":"nonfinite_body_transform"}
 var sampled:=_sample_setup_path(scene,original,target_pull,target_yaw,path)
 # Sampling is the only mutation; restore before any collision or snapshot exit.
 scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
 if not sampled.get("accepted",false):return sampled
 var transforms:Array=sampled.transforms
 var segment_angles:Array=sampled.angles
 var count:int=segment_angles.size()
 var to:Transform3D=transforms[-1]
 var attachment:=from.affine_inverse()*body
 var obstacles:Array=[]
 for value in solids:
  var box:AABB
  var transform:=Transform3D.IDENTITY
  var id:=""
  if value is AABB:box=value
  elif value is Dictionary and value.get("bounds") is AABB and value.get("transform") is Transform3D:
   box=value.bounds;transform=value.transform;id=str(value.get("id",""))
  else:return {"accepted":false,"reason":"invalid_carrier_obstacle"}
  if not box.position.is_finite() or not box.size.is_finite() or box.size.x<0 or box.size.y<0 or box.size.z<0 or not transform.is_finite() or absf(transform.basis.determinant())<.0000001:return {"accepted":false,"reason":"invalid_carrier_obstacle"}
  obstacles.append({"box":box,"inverse":transform.affine_inverse(),"world_bounds":transform*box,"id":id})
 var body_scale:=RigCapsules.scale_bound(body.basis)
 var seat_parent:Node3D=scene.seat_node().get_parent()
 var parent_scale:=RigCapsules.scale_bound(seat_parent.global_basis)
 var support_scale:=parent_scale*RigCapsules.scale_bound(scene.seat_node().basis)
 body_scale=maxf(body_scale,parent_scale*RigCapsules.scale_bound(scene.seat_node().basis*attachment.basis))
 var result_bounds:=AABB()
 var first:=true
 var started:=Time.get_ticks_usec()
 for capsule in snapshot.capsules:
  if not capsule is Dictionary or not capsule.get("a") is Vector3 or not capsule.get("b") is Vector3 or not Vector3(capsule.a).is_finite() or not Vector3(capsule.b).is_finite() or not is_finite(float(capsule.get("radius",NAN))) or float(capsule.radius)<=0:return {"accepted":false,"reason":"invalid_body_capsule"}
  var a:Vector3=attachment*Vector3(capsule.a)
  var b:Vector3=attachment*Vector3(capsule.b)
  var radius:=float(capsule.radius)*body_scale
  var before_a:=from*a;var before_b:=from*b
  for step in count:
   var next:Transform3D=transforms[step+1]
   var arc_pad:=maxf(a.length(),b.length())*support_scale*(1-cos(float(segment_angles[step])*.5))+.000001
   var after_a:=next*a;var after_b:=next*b
   var points:Array[Vector3]=[before_a,before_b,after_a,after_b]
   var segment_bounds:=AABB(before_a,Vector3.ZERO)
   for p in points:segment_bounds=segment_bounds.expand(p)
   segment_bounds=segment_bounds.grow(radius+arc_pad)
   result_bounds=segment_bounds if first else result_bounds.merge(segment_bounds);first=false
   for index in obstacles.size():
    var obstacle:Dictionary=obstacles[index]
    if not segment_bounds.grow(.000001).intersects(obstacle.world_bounds):continue
    var inverse:Transform3D=obstacle.inverse
    var local_points:Array[Vector3]=[]
    for p in points:local_points.append(inverse*p)
    var expanded:AABB=AABB(obstacle.box).grow((radius+arc_pad)*RigCapsules.scale_bound(inverse.basis))
    if _hull_intersects_box(local_points,expanded):return {"accepted":false,"reason":"occupied_sweep_blocked","blocked_body_id":str(capsule.get("id","")),"obstacle_index":index,"obstacle_id":obstacle.id,"sweep_segment":step,"body_bounds_world":result_bounds,"validation_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":snapshot.get("scope","")}
   before_a=after_a;before_b=after_b
 var seat_check:=_check_seat_geometry(scene,transforms,segment_angles,obstacles,support_scale)
 if not seat_check.accepted:
  seat_check["body_bounds_world"]=result_bounds
  seat_check["validation_ms"]=(Time.get_ticks_usec()-started)/1000.0
  return seat_check
 return {"accepted":true,"reason":"clear","body_bounds_world":result_bounds,"chair_bounds_world":seat_check.bounds,"target_avatar_transform":to*attachment,"segments":count,"validation_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":snapshot.get("scope","")}

static func _seat_parts(node:Node,to_seat:Transform3D,result:Array)->void:
 if node is MeshInstance3D and node.mesh!=null:
  var local:Transform3D=to_seat*node.global_transform
  for box in Parts.local_parts(node.mesh):
   var points:Array[Vector3]=[]
   var radius:=0.0
   for i in 8:
    var point:Vector3=local*AABB(box).get_endpoint(i)
    points.append(point);radius=maxf(radius,point.length())
   result.append({"points":points,"radius":radius,"id":str(node.get_path())})
 for child in node.get_children():_seat_parts(child,to_seat,result)

## The physical moving chair is also swept against fixed furniture. End-point
## convex hulls plus per-segment angular padding enclose each mesh-part path.
## In each obstacle's own frame an enclosing AABB is deliberately conservative.
static func _check_seat_geometry(scene:DesktopObjectContactScene,transforms:Array,angles:Array,obstacles:Array,support_scale:float)->Dictionary:
 var parts:Array=[]
 _seat_parts(scene.seat_node(),scene.seat_node().global_transform.affine_inverse(),parts)
 if parts.is_empty():return {"accepted":false,"reason":"missing_carrier_geometry"}
 var total:=AABB();var first:=true
 for part in parts:
  for step in angles.size():
   var points:Array[Vector3]=[]
   for p in part.points:
    points.append(Transform3D(transforms[step])*Vector3(p))
    points.append(Transform3D(transforms[step+1])*Vector3(p))
   var padding:=float(part.radius)*support_scale*(1-cos(float(angles[step])*.5))+.000001
   var world:=AABB(points[0],Vector3.ZERO)
   for p in points:world=world.expand(p)
   world=world.grow(padding)
   total=world if first else total.merge(world);first=false
   for index in obstacles.size():
    var obstacle:Dictionary=obstacles[index]
    if not world.grow(.000001).intersects(obstacle.world_bounds):continue
    var inverse:Transform3D=obstacle.inverse
    var local:=AABB(inverse*points[0],Vector3.ZERO)
    for p in points:local=local.expand(inverse*p)
    local=local.grow(padding*RigCapsules.scale_bound(inverse.basis))
    if local.grow(.000001).intersects(obstacle.box):return {"accepted":false,"reason":"carrier_geometry_blocked","blocked_chair_part":part.id,"obstacle_index":index,"obstacle_id":obstacle.id,"sweep_segment":step,"chair_bounds_world":total}
 return {"accepted":true,"bounds":total}


## Runtime interpolates these progress coordinates on one monotone master clock.
## Pull may make a purposeful excursion (normalized x in [-16,16]); actual
## chair capability bounds are checked for every sample. Yaw remains monotone.
static func _validate_trajectory(trajectory:Array)->Array:
 if trajectory.is_empty():return [Vector2.ZERO,Vector2.ONE]
 if trajectory.size()<2 or trajectory.size()>65:return []
 var previous:=Vector2.ZERO
 for point in trajectory:
  if not point is Vector2 or not point.is_finite() or point.x < -16 or point.x>16 or point.y<0 or point.y>1 or point.y<previous.y:return []
  previous=point
 if trajectory[0]!=Vector2.ZERO or trajectory[-1]!=Vector2.ONE:return []
 return trajectory.duplicate()

## Sample the actual setup API, not endpoint Transform3D interpolation: pull and
## swivel follow independently specified timing and the runtime shortest yaw arc.
static func _sample_setup_path(scene:DesktopObjectContactScene,original:Dictionary,target_pull:float,target_yaw:float,path:Array)->Dictionary:
 var transforms:Array=[scene.seat_node().global_transform]
 var angles:Array=[]
 var previous:Vector2=path[0]
 var pull0:=float(original.pullout_local_m)
 var yaw0:=float(original.yaw_delta_deg)
 var yaw_delta:=angle_difference(deg_to_rad(yaw0),deg_to_rad(target_yaw))
 for index in range(1,path.size()):
  var point:Vector2=path[index]
  var before:Transform3D=transforms[-1]
  var pull:=lerpf(pull0,target_pull,point.x)
  var yaw:=_path_yaw(yaw0,target_yaw,point.y)
  if not scene.set_seat_setup(pull,yaw):return {"accepted":false,"reason":"invalid_setup_target"}
  var endpoint:Transform3D=scene.seat_node().global_transform
  if not endpoint.is_finite():return {"accepted":false,"reason":"nonfinite_body_transform"}
  var angle:=absf(yaw_delta*(point.y-previous.y))
  var count:=maxi(1,maxi(ceili(angle/deg_to_rad(5)),ceili(before.origin.distance_to(endpoint.origin)/.025)))
  if angles.size()+count>256:return {"accepted":false,"reason":"carrier_path_too_large"}
  for step in count:
   var progress:=previous.lerp(point,float(step+1)/count)
   if not scene.set_seat_setup(lerpf(pull0,target_pull,progress.x),_path_yaw(yaw0,target_yaw,progress.y)):return {"accepted":false,"reason":"invalid_setup_target"}
   transforms.append(scene.seat_node().global_transform)
   angles.append(angle/count)
  previous=point
 return {"accepted":true,"transforms":transforms,"angles":angles}

static func _path_yaw(from:float,to:float,weight:float)->float:
 return wrapf(rad_to_deg(lerp_angle(deg_to_rad(from),deg_to_rad(to),weight)),-180.0,180.0)

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
