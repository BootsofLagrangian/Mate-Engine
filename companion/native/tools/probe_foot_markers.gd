extends RefCounted
## Four fixed base-mesh vertices (heel/toe), skinned exactly per frame.
## Diagnostic markers, not a claim that all sole vertices are on the floor.
var avatar:VrmAvatar
var markers:Dictionary={}
func prepare(model:VrmAvatar) -> void:
 avatar=model;markers.clear()
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
 for side in candidates:
  var lowest:=INF
  for candidate in candidates[side]:lowest=minf(lowest,candidate.rest.y)
  var band:Array=candidates[side].filter(func(c):return c.rest.y<=lowest+.008)
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
