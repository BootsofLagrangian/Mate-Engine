extends RefCounted
## Offline diagnostic only: deterministic sparse triangles influenced by spring bones.
var surfaces:=[]
func configure(avatar: VrmAvatar, bone_contains:String="") -> void:
	var springs:={}
	var secondary=avatar.spring_contacts.secondary
	if secondary:
		for state in secondary.spring_bones_internal:
			for joint in state.verlets:
				if bone_contains.is_empty() or bone_contains in avatar.skeleton.get_bone_name(joint.bone_idx): springs[joint.bone_idx]=true
	var meshes:=[]
	avatar._collect_meshes(avatar.model,meshes)
	for mesh in meshes:
		if mesh.skin==null: continue
		var ids:=[]
		for bind in mesh.skin.get_bind_count():
			var idx:int=mesh.skin.get_bind_bone(bind)
			if not mesh.skin.get_bind_name(bind).is_empty(): idx=avatar.skeleton.find_bone(mesh.skin.get_bind_name(bind))
			ids.append(idx)
		for surface in mesh.mesh.get_surface_count():
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var joints:Variant=arrays[Mesh.ARRAY_BONES]
			var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if joints==null or weights==null or indices.is_empty(): continue
			var influences:int=joints.size()/vertices.size()
			var selected:={}
			var edges:=[]
			for triangle in range(0,indices.size()/3,17):
				var tri:=[indices[triangle*3],indices[triangle*3+1],indices[triangle*3+2]]
				var relevant:=false
				for vertex in tri:
					for slot in influences:
						if weights[vertex*influences+slot]>.25 and springs.has(ids[joints[vertex*influences+slot]]): relevant=true
				if not relevant: continue
				for vertex in tri: selected[vertex]=true
				edges.append(tri)
			if selected.is_empty(): continue
			surfaces.append({"mesh":mesh,"ids":ids,"vertices":vertices,"joints":joints,"weights":weights,"influences":influences,"selected":selected.keys(),"triangles":edges})
func sample(avatar: VrmAvatar) -> Dictionary:
	var points:=[]
	var edges:=[]
	var triangles:=[]
	for surface in surfaces:
		var transforms:=[]
		for bind in surface.ids.size(): transforms.append(avatar.skeleton.get_bone_global_pose(surface.ids[bind])*surface.mesh.skin.get_bind_pose(bind))
		var offsets:={}
		for vertex in surface.selected:
			var point:=Vector3.ZERO
			var total:=0.0
			for slot in surface.influences:
				var at:int=vertex*surface.influences+slot
				var weight:float=surface.weights[at]
				point+=(transforms[surface.joints[at]]*surface.vertices[vertex])*weight
				total+=weight
			offsets[vertex]=points.size()
			points.append(point/maxf(total,.0001))
		for tri in surface.triangles:
			var a:Vector3=points[offsets[tri[0]]]
			var b:Vector3=points[offsets[tri[1]]]
			var c:Vector3=points[offsets[tri[2]]]
			edges.append_array([a.distance_to(b),b.distance_to(c),c.distance_to(a)])
			triangles.append((b-a).cross(c-a))
	return {"points":points,"edges":edges,"normals":triangles}
