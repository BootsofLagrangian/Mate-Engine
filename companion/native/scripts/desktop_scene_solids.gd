class_name DesktopSceneSolids
extends RefCounted
## Imported meshes may batch disconnected furniture pieces by material. Their
## whole AABB is not a solid. Keep one conservative AABB per connected piece.
static var _cache:Dictionary={}
static func local_parts(mesh:Mesh)->Array:
	var key:=mesh.get_instance_id()
	if _cache.has(key):return _cache[key]
	var points:Array[Vector3]=[]
	var parents:Array[int]=[]
	var welded:Dictionary={}
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
		var arrays:=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var ids:Array[int]=[]
		for point in vertices:
			var location:=point.snapped(Vector3.ONE*.00001)
			if not welded.has(location):
				welded[location]=points.size();parents.append(points.size());points.append(point)
			ids.append(int(welded[location]))
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var count:=indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0,count-2,3):
			var a:=ids[indices[index] if not indices.is_empty() else index]
			for offset in [1,2]:
				var b:=ids[indices[index+offset] if not indices.is_empty() else index+offset]
				var ra:=_root(parents,a);var rb:=_root(parents,b)
				if ra!=rb:parents[rb]=ra
	var groups:Dictionary={}
	for index in points.size():
		var id:=_root(parents,index)
		groups[id]=AABB(points[index],Vector3.ZERO) if not groups.has(id) else AABB(groups[id]).expand(points[index])
	var result:Array=[]
	for box in groups.values():
		if AABB(box).size.length_squared()>0:result.append(box)
	_cache[key]=result
	return result
static func _root(parents:Array[int],index:int)->int:
	var current:=index
	while parents[current]!=current:
		parents[current]=parents[parents[current]]
		current=parents[current]
	return current
