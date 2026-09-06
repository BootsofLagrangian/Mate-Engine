class_name TransitionBoundsMeasure
extends RefCounted
## Cached immutable mesh input; only current bone transforms are read per pose.
## No support patch, rest skinning, bone writes, or spring mutation.
static var _cache:Dictionary={}

static func measure(avatar:VrmAvatar, conservative:bool=false)->Dictionary:
 var model_id:=avatar.model.get_instance_id()
 if not _cache.has(model_id):
  if _cache.size()>=3:_cache.clear()
  var entries:Array=[]
  var meshes:Array=[]
  avatar._collect_meshes(avatar.model,meshes)
  for item in meshes:
   var mesh:MeshInstance3D=item
   if mesh.mesh==null:continue
   var binds:Array=[]
   if mesh.skin:
    for bind in mesh.skin.get_bind_count():
     var idx:=mesh.skin.get_bind_bone(bind)
     if not mesh.skin.get_bind_name(bind).is_empty():idx=avatar.skeleton.find_bone(mesh.skin.get_bind_name(bind))
     binds.append([idx,mesh.skin.get_bind_pose(bind)])
   for surface in mesh.mesh.get_surface_count():
    var arrays:=mesh.mesh.surface_get_arrays(surface)
    var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var joints:Variant=arrays[Mesh.ARRAY_BONES]
    var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
    var influences:=int(joints.size()/vertices.size()) if joints!=null and weights!=null and not vertices.is_empty() else 0
    var influence_bounds:Dictionary={}
    var slices:Dictionary={}
    for i in vertices.size():
     var included_weight:=0.0
     for slot in influences:
      var at:=i*influences+slot
      var bind:=int(joints[at])
      if float(weights[at])<=0 or bind<0 or bind>=binds.size():continue
      var slice_key:=str(bind)+":"+str(int(floor(vertices[i].y/0.05)))
      if not slices.has(slice_key):slices[slice_key]={"bind":bind,"bounds":AABB(vertices[i],Vector3.ZERO),"indices":PackedInt32Array()}
      slices[slice_key].bounds=slices[slice_key].bounds.expand(vertices[i])
      slices[slice_key].indices.append(i)
      influence_bounds[bind]=AABB(vertices[i],Vector3.ZERO) if not influence_bounds.has(bind) else influence_bounds[bind].expand(vertices[i])
      included_weight+=float(weights[at])
     if included_weight<=0.00001:influence_bounds[-1]=AABB(vertices[i],Vector3.ZERO) if not influence_bounds.has(-1) else influence_bounds[-1].expand(vertices[i])
    entries.append({"slices":slices.values(),"identity":entries.size(),"influence_bounds":influence_bounds,"mesh":weakref(mesh),"vertices":vertices,"joints":joints,"weights":weights,"influences":influences,"binds":binds})
  _cache[model_id]=entries
 var sk:=avatar.skeleton
 var to_avatar:=avatar.global_transform.affine_inverse()*sk.global_transform
 var bounds:=AABB()
 var first:=true
 var candidates:Array=[]
 var pose_transforms:Dictionary={}
 for entry in _cache[model_id]:
  var mesh:MeshInstance3D=entry.mesh.get_ref()
  if mesh==null or not mesh.is_visible_in_tree():continue
  var mesh_to_sk:=sk.global_transform.affine_inverse()*mesh.global_transform
  var mesh_id:=mesh.get_instance_id()
  if not pose_transforms.has(mesh_id):
   var raw:Array[Transform3D]=[]
   var local:Array[Transform3D]=[]
   for bind in entry.binds:
    var transform:Transform3D=sk.get_bone_global_pose(bind[0])*bind[1] if bind[0]>=0 else mesh_to_sk
    raw.append(transform)
    local.append(to_avatar*transform)
   pose_transforms[mesh_id]=[raw,local]
  var transforms:Array[Transform3D]=pose_transforms[mesh_id][0]
  var local_transforms:Array[Transform3D]=pose_transforms[mesh_id][1]
  if conservative:
   # Normalized nonnegative LBS is a convex combination of these
   # transformed contributions. Their union encloses every skinned vertex.
   for bind in entry.influence_bounds:
    var transform:Transform3D=local_transforms[bind] if bind>=0 else to_avatar*mesh_to_sk
    var bound:AABB=transform*entry.influence_bounds[bind]
    bounds=bound if first else bounds.merge(bound)
    first=false
    if bind<0:candidates.append({"minimum":bound.position.y,"bind":bind,"entry":entry,"transforms":transforms,"mesh_to_sk":mesh_to_sk})
   for slice in entry.slices:
    var bound:AABB=local_transforms[slice.bind]*slice.bounds
    candidates.append({"minimum":bound.position.y,"bind":slice.bind,"indices":slice.indices,"entry":entry,"transforms":transforms,"mesh_to_sk":mesh_to_sk})
   continue
  var vertices:PackedVector3Array=entry.vertices
  var joints:Variant=entry.joints
  var weights:Variant=entry.weights
  var influences:int=entry.influences
  for i in vertices.size():
   var point:=Vector3.ZERO
   var total:=0.0
   for slot in influences:
    var at:=i*influences+slot
    var bind:=int(joints[at])
    var weight:=float(weights[at])
    if weight<=0 or bind<0 or bind>=transforms.size():continue
    point+=(transforms[bind]*vertices[i])*weight
    total+=weight
   point=point/total if total>0.00001 else mesh_to_sk*vertices[i]
   var local:=to_avatar*point
   bounds=AABB(local,Vector3.ZERO) if first else bounds.expand(local)
   first=false
 if conservative and not first:
  candidates.sort_custom(func(a,b):return a.minimum<b.minimum)
  var minimum:=INF
  var visited:Dictionary={}
  for candidate in candidates:
   if candidate.minimum>=minimum:continue
   var entry:Dictionary=candidate.entry
   var vertices:PackedVector3Array=entry.vertices
   var indices:PackedInt32Array=candidate.get("indices",PackedInt32Array())
   if candidate.bind<0:
    indices=PackedInt32Array()
    for i in vertices.size():indices.append(i)
   var identity:int=entry.identity
   if not visited.has(identity):
    var flags:=PackedByteArray()
    flags.resize(vertices.size())
    visited[identity]=flags
   var flags:PackedByteArray=visited[identity]
   var joints:Variant=entry.joints
   var weights:Variant=entry.weights
   var influences:int=entry.influences
   var transforms:Array[Transform3D]=candidate.transforms
   var mesh_to_sk:Transform3D=candidate.mesh_to_sk
   for i in indices:
    if flags[i]:continue
    flags[i]=1
    var point:=Vector3.ZERO
    var total:=0.0
    for slot in influences:
     var at:=i*influences+slot
     var bind:=int(joints[at])
     var weight:=float(weights[at])
     if weight<=0 or bind<0 or bind>=transforms.size():continue
     point+=(transforms[bind]*vertices[i])*weight
     total+=weight
    point=point/total if total>0.00001 else mesh_to_sk*vertices[i]
    minimum=minf(minimum,(to_avatar*point).y)
  var previous_end:=bounds.end
  bounds.position.y=minimum
  bounds.size.y=previous_end.y-minimum
 return {} if first else {"bounds":bounds}
