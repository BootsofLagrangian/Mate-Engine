class_name SeatedCachedCandidate
extends RefCounted
## One-time canonical-pose measurement. No live bounds chasing or rig mutation.
static func measure(avatar: VrmAvatar, rotations: Dictionary, secondary: Dictionary = {}) -> Dictionary:
	if not avatar.has_model() or not avatar.bone_index.has("hips"):
		return {}
	var sk := avatar.skeleton
	var saved := []
	for idx in sk.get_bone_count():
		saved.append([sk.get_bone_pose_position(idx),sk.get_bone_pose_rotation(idx),sk.get_bone_pose_scale(idx)])
	var ownership := avatar._posed_bones.duplicate()
	# Secondary/helper bones must also start from canonical rest; measuring a
	# transient spring pose would make calibration depend on load timing.
	for idx in sk.get_bone_count():
		var rest := sk.get_bone_rest(idx)
		sk.set_bone_pose_position(idx,rest.origin)
		sk.set_bone_pose_rotation(idx,rest.basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(idx,rest.basis.get_scale())
	for idx in secondary:
		if idx>=0 and idx<sk.get_bone_count() and not avatar.bone_rest_local.has(idx):
			sk.set_bone_pose_position(idx,secondary[idx][0])
			sk.set_bone_pose_rotation(idx,secondary[idx][1])
			sk.set_bone_pose_scale(idx,secondary[idx][2])
	avatar.apply_pose({})
	avatar.apply_normalized_rotations(rotations,1.0)
	var hip: int = avatar.bone_index.hips
	var hip_position := sk.get_bone_global_pose(hip).origin
	var height := maxf(sk.get_bone_global_rest(hip).origin.y,0.5)
	var support_bones := {hip:true}
	for side in ["left","right"]:
		var upper: int = avatar.bone_index.get(side+"UpperLeg",-1)
		var lower: int = avatar.bone_index.get(side+"LowerLeg",-1)
		for idx in sk.get_bone_count():
			var ancestor := idx
			while ancestor >= 0:
				if ancestor == lower: break
				if ancestor == upper:
					support_bones[idx]=true
					break
				ancestor=sk.get_bone_parent(ancestor)
	var meshes := []
	avatar._collect_meshes(avatar.model,meshes)
	var to_avatar := avatar.global_transform.affine_inverse()*sk.global_transform
	var bounds := AABB()
	var first := true
	var patch: Array[Vector3] = []
	var count := 0
	var rest_error := 0.0
	var mesh_extents := {}
	for item in meshes:
		var mesh: MeshInstance3D = item
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var mesh_to_sk := sk.global_transform.affine_inverse()*mesh.global_transform
		var transforms := []
		var rest_transforms := []
		var support := []
		if mesh.skin:
			for bind in mesh.skin.get_bind_count():
				var idx := mesh.skin.get_bind_bone(bind)
				if not mesh.skin.get_bind_name(bind).is_empty(): idx=sk.find_bone(mesh.skin.get_bind_name(bind))
				transforms.append(sk.get_bone_global_pose(idx)*mesh.skin.get_bind_pose(bind) if idx>=0 else mesh_to_sk)
				rest_transforms.append(sk.get_bone_global_rest(idx)*mesh.skin.get_bind_pose(bind) if idx>=0 else mesh_to_sk)
				support.append(support_bones.has(idx))
		var mesh_min := INF
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: Variant = arrays[Mesh.ARRAY_BONES]
			var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := int(joints.size()/vertices.size()) if joints != null and weights != null and not vertices.is_empty() else 0
			for i in vertices.size():
				var point := Vector3.ZERO
				var rest := Vector3.ZERO
				var total := 0.0
				var support_weight := 0.0
				for slot in influences:
					var at := i*influences+slot
					var bind := int(joints[at])
					var weight := float(weights[at])
					if weight <= 0 or bind<0 or bind>=transforms.size(): continue
					point += (transforms[bind]*vertices[i])*weight
					rest += (rest_transforms[bind]*vertices[i])*weight
					total += weight
					if support[bind]: support_weight += weight
				if total>0.00001:
					point/=total
					rest_error=maxf(rest_error,(rest/total).distance_to(mesh_to_sk*vertices[i]))
				else: point=mesh_to_sk*vertices[i]
				var local := to_avatar*point
				bounds=AABB(local,Vector3.ZERO) if first else bounds.expand(local)
				first=false
				count+=1
				mesh_min=minf(mesh_min,local.y)
				# Rear pelvis/proximal thigh underside, excluding hanging legs,
				# tail and long skirt tips even when partially weighted to hips.
				var relative := point-hip_position
				if support_weight>=0.65 and absf(relative.x)<height*0.22 and relative.z>=-height*0.22 and relative.z<=0.0 and relative.y<=0.02 and relative.y>=-height*0.14:
					patch.append(point)
		mesh_extents[str(mesh.name)] = mesh_min
	var minimum := INF
	for point in patch: minimum=minf(minimum,point.y)
	var anchor := hip_position-Vector3(0,height*0.1,0)
	var band := 0
	if not patch.is_empty():
		anchor=Vector3.ZERO
		for point in patch:
			if point.y<=minimum+0.008:
				anchor+=point
				band+=1
		anchor/=maxi(band,1)
		anchor.y=minimum
	# Restore exact state before returning, including helpers and pose ownership.
	for idx in saved.size():
		sk.set_bone_pose_position(idx,saved[idx][0])
		sk.set_bone_pose_rotation(idx,saved[idx][1])
		sk.set_bone_pose_scale(idx,saved[idx][2])
	avatar._posed_bones=ownership
	if first: return {}
	return {"anchor":to_avatar*anchor,"bounds":bounds,"diagnostics":{"vertices":count,"patch_vertices":patch.size(),"contact_band_vertices":band,"bind_rest_max_error_m":rest_error,"mesh_min_y":mesh_extents,"method":"skinned_pelvis_thigh" if band>0 else "hip_fallback"}}
