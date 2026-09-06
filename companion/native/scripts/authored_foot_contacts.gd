class_name AuthoredFootContacts
extends RefCounted
## Source-relative foot contact retargeting. Authored lift/placement remains live;
## only planned contact compensates a different seat height or root path.
var avatar:VrmAvatar
var markers:Dictionary={}
# Immutable diagnostic input; never skinned in the runtime contact loop.
var foot_vertices:Dictionary={}
var support_vertices:Dictionary={}
var reference_live:Dictionary={}
var reference_source:Dictionary={}
var root_delta_sk:=Vector3.ZERO
var reference_epoch:=0
var active:=false
var model_id:=0
var diagnostics:Dictionary={}
var leg_ik:=LegIK.new()
func prepare(model:VrmAvatar) -> void:
 if model_id==model.model.get_instance_id() and not markers.is_empty():return
 avatar=model;markers.clear();support_vertices.clear();clear_reference()
 model_id=model.model.get_instance_id()
 var sk:=avatar.skeleton
 var side_bones:Dictionary={}
 for side in ["left","right"]:
  var ankle:int=avatar.bone_index.get(side+"Foot",-1)
  for idx in sk.get_bone_count():
   var parent:=idx
   while parent>=0:
    if parent==ankle:side_bones[idx]=side;break
    parent=sk.get_bone_parent(parent)
 var candidates:Dictionary={"left":[],"right":[]}
 var meshes:Array=[];avatar._collect_meshes(avatar.model,meshes)
 for item in meshes:
  var mesh:MeshInstance3D=item
  if mesh.mesh==null or mesh.skin==null or not mesh.is_visible_in_tree():continue
  var bindings:Array=[]
  for bind in mesh.skin.get_bind_count():
   var idx:=mesh.skin.get_bind_bone(bind)
   if not mesh.skin.get_bind_name(bind).is_empty():idx=sk.find_bone(mesh.skin.get_bind_name(bind))
   bindings.append([idx,mesh.skin.get_bind_pose(bind)])
  for surface in mesh.mesh.get_surface_count():
   var arrays:=mesh.mesh.surface_get_arrays(surface)
   var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
   var joints:Variant=arrays[Mesh.ARRAY_BONES];var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
   if joints==null or weights==null or vertices.is_empty():continue
   var count:int=joints.size()/vertices.size()
   for i in vertices.size():
    var influences:Array=[];var total:=0.0;var sides:Dictionary={"left":0.0,"right":0.0};var rest:=Vector3.ZERO
    for slot in count:
     var at:=i*count+slot;var bind:=int(joints[at]);var weight:=float(weights[at])
     if weight<=0 or bind<0 or bind>=bindings.size() or bindings[bind][0]<0:continue
     var idx:int=bindings[bind][0]
     influences.append([idx,bindings[bind][1],weight]);total+=weight
     rest+=(sk.get_bone_global_rest(idx)*bindings[bind][1]*vertices[i])*weight
     if side_bones.has(idx):sides[side_bones[idx]]+=weight
    if total<=.00001:continue
    rest/=total
    for side in sides:
     if float(sides[side])/total>=.5:candidates[side].append({"vertex":vertices[i],"influences":influences,"total":total,"rest":rest})
 foot_vertices=candidates
 for side in candidates:
  # Bounded directional support set, including lateral sole corners. Whole
  # foot vertices remain probe-only: runtime skins at most 26 points per foot.
  var selected:Array=[]
  for x in [-1,0,1]:
   for y in [-1,0,1]:
    for z in [-1,0,1]:
     var direction:=Vector3(x,y,z)
     if direction==Vector3.ZERO:continue
     var extreme:Dictionary={};var best:float=-INF
     for candidate in candidates[side]:
      var value:float=Vector3(candidate.rest).dot(direction)
      if value>best:best=value;extreme=candidate
     if not extreme.is_empty() and not selected.has(extreme):selected.append(extreme)
  support_vertices[side]=selected
  var lowest:=INF
  for candidate in candidates[side]:lowest=minf(lowest,candidate.rest.y)
  var band:Array=candidates[side].filter(func(c):return c.rest.y<=lowest+maxf(.0001,sk.get_bone_global_rest(avatar.bone_index.hips).origin.y*.009))
  band.sort_custom(func(a,b):return a.rest.z<b.rest.z)
  if not band.is_empty():markers[side+"Heel"]=band[0];markers[side+"Toe"]=band[-1]
func live_world() -> Dictionary:
 var result:Dictionary={};var sk:=avatar.skeleton
 for name in markers:
  var marker:Dictionary=markers[name];var point:=Vector3.ZERO
  for bind in marker.influences:point+=(sk.get_bone_global_pose(bind[0])*bind[1]*marker.vertex)*bind[2]
  result[name]=sk.global_transform*(point/marker.total)
 return result
func source_local(rotations:Dictionary,hips:Vector3) -> Dictionary:
 var globals:Dictionary={};var result:Dictionary={}
 for name in markers:
  var marker:Dictionary=markers[name];var point:=Vector3.ZERO
  for bind in marker.influences:point+=(_source_pose(bind[0],rotations,hips,globals)*bind[1]*marker.vertex)*bind[2]
  result[name]=point/marker.total
 return result
func _source_pose(idx:int,rotations:Dictionary,hips:Vector3,cache:Dictionary) -> Transform3D:
 if cache.has(idx):return cache[idx]
 var sk:=avatar.skeleton;var local:=sk.get_bone_rest(idx)
 for name in avatar.bone_index:
  if avatar.bone_index[name]!=idx or not rotations.has(name):continue
  var g:Basis=avatar.bone_rest_global[idx]
  var rotation:Quaternion=(avatar.bone_rest_local[idx]*(g.inverse()*Basis(rotations[name])*g).get_rotation_quaternion()).normalized()
  local.basis=Basis(rotation).scaled(local.basis.get_scale())
 if idx==avatar.bone_index.hips:local.origin+=hips*sk.get_bone_global_rest(idx).origin.y
 var parent:=sk.get_bone_parent(idx)
 var value:Transform3D=_source_pose(parent,rotations,hips,cache)*local if parent>=0 else local
 cache[idx]=value
 return value

func clear_reference() -> void:
 active=false;reference_live.clear();reference_source.clear();diagnostics.clear()

func live_local() -> Dictionary:
 var points:=live_world();var inverse:=avatar.skeleton.global_transform.affine_inverse()
 for name in points:points[name]=inverse*points[name]
 return points

func begin_reference(rotations:Dictionary,hips:Vector3,delta_avatar:Vector3=Vector3.ZERO) -> bool:
 if markers.size()!=4:return false
 reference_epoch+=1
 reference_live=live_local()
 reference_source=source_local(rotations,hips)
 root_delta_sk=(avatar.skeleton.global_transform.affine_inverse()*avatar.global_transform).basis*delta_avatar
 active=true
 return true

func _support_min(side:String,rotations:Dictionary={},hips:Vector3=Vector3.ZERO,source:bool=false) -> float:
 var lowest:=INF;var cache:Dictionary={}
 for marker in support_vertices.get(side,[]):
  var point:=Vector3.ZERO
  for bind in marker.influences:
   var pose:Transform3D=_source_pose(bind[0],rotations,hips,cache) if source else avatar.skeleton.get_bone_global_pose(bind[0])
   point+=(pose*bind[1]*marker.vertex)*bind[2]
  lowest=minf(lowest,(point/marker.total).y)
 return lowest

func apply_contact(rotations:Dictionary,hips:Vector3,progress:float,floor_y:float,ownership:float=1.0) -> void:
 diagnostics.clear()
 if not active or not is_finite(floor_y):return
 var sk:=avatar.skeleton
 var source:=source_local(rotations,hips)
 var live:=live_local()
 for side in ["left","right"]:
  var heel:String=side+"Heel";var toe:String=side+"Toe"
  if not source.has(heel) or not source.has(toe):continue
  var upper:int=avatar.bone_index.get(side+"UpperLeg",-1)
  var knee:int=avatar.bone_index.get(side+"LowerLeg",-1)
  var ankle:int=avatar.bone_index.get(side+"Foot",-1)
  if mini(upper,mini(knee,ankle))<0:continue
  var length:=sk.get_bone_global_rest(upper).origin.distance_to(sk.get_bone_global_rest(knee).origin)+sk.get_bone_global_rest(knee).origin.distance_to(sk.get_bone_global_rest(ankle).origin)
  var source_floor:float=INF
  for marker in support_vertices[side]:source_floor=minf(source_floor,marker.rest.y)
  var source_height:=_support_min(side,rotations,hips,true)-source_floor
  var near:=length*.015;var far:=length*.04
  var planned:=1.0-_ease((source_height-near)/maxf(.00001,far-near))
  var source_center:Vector3=(source[heel]+source[toe])*.5
  var source_initial:Vector3=(reference_source[heel]+reference_source[toe])*.5
  var live_initial:Vector3=(reference_live[heel]+reference_live[toe])*.5
  var live_center:Vector3=(live[heel]+live[toe])*.5
  var live_min:=_support_min(side)
  var desired:=live_initial+source_center-source_initial-root_delta_sk*progress
  desired.y=floor_y+maxf(source_height,0.0)+(live_center.y-live_min)
  var correction:=desired-live_center
  var limit:=length*.20
  var limited:=correction.length()>limit
  var weight:=clampf(ownership,0,1)*planned
  if weight>0:
   var foot:=sk.get_bone_global_pose(ankle)
   var applied:=correction.limit_length(limit)*weight
   # Acquisition fades XZ/contact correction, but never intentionally fades
   # through the floor. Preserve source pitch/roll rather than flattening feet.
   applied.y=clampf(maxf(applied.y,minf(limit,floor_y-live_min)),-limit,limit)
   var planar:=Vector2(applied.x,applied.z).limit_length(sqrt(maxf(0,limit*limit-applied.y*applied.y)))
   applied.x=planar.x;applied.z=planar.y
   leg_ik.solve(avatar,side,foot.origin+applied,1.0,foot.basis.orthonormalized(),true)
  var result:=live_local()
  var result_center:Vector3=(result[heel]+result[toe])*.5
  diagnostics[side]={"planned_weight":planned,"ownership":ownership,"source_height_local":source_height,"requested_correction_local":correction,"correction_limit_local":limit,"limited":limited,"target_center_local":desired,"residual_local":result_center-desired,"floor_gap_local":_support_min(side)-floor_y,"reach_error_local":float(leg_ik.diagnostics.get(side,{}).get("error",0))}

static func _ease(value:float)->float:
 var x:=clampf(value,0,1)
 return x*x*x*(x*(x*6-15)+10)
