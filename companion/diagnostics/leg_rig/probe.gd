extends SceneTree
func vec(v:Vector3)->Array: return [v.x,v.y,v.z]
func _initialize(): call_deferred("run")
func run():
	var rows=[]
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar=VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		var sk=avatar.skeleton
		var row={"character":name,"skeleton_scale":vec(sk.global_transform.basis.get_scale()),"skeleton_basis":[vec(sk.global_transform.basis.x),vec(sk.global_transform.basis.y),vec(sk.global_transform.basis.z)],"bones":{},"legs":{},"sole_calibration":avatar.sole_calibration,"ik":{}}
		for b in ["hips","leftUpperLeg","leftLowerLeg","leftFoot","leftToes","rightUpperLeg","rightLowerLeg","rightFoot","rightToes"]:
			var id=avatar.bone_index[b]
			var rest=sk.get_bone_global_rest(id)
			var parent=sk.get_bone_parent(id)
			row.bones[b]={"id":id,"name":sk.get_bone_name(id),"parent":sk.get_bone_name(parent) if parent>=0 else "","position":vec(rest.origin),"basis":[vec(rest.basis.x),vec(rest.basis.y),vec(rest.basis.z)],"local_scale":vec(sk.get_bone_rest(id).basis.get_scale())}
		for side in ["left","right"]:
			var hip=sk.get_bone_global_rest(avatar.bone_index[side+"UpperLeg"]).origin
			var knee=sk.get_bone_global_rest(avatar.bone_index[side+"LowerLeg"]).origin
			var ankle=sk.get_bone_global_rest(avatar.bone_index[side+"Foot"]).origin
			var toe=sk.get_bone_global_rest(avatar.bone_index[side+"Toes"]).origin
			var axis=(ankle-hip).normalized()
			row.legs[side]={"thigh_m":hip.distance_to(knee),"shin_m":knee.distance_to(ankle),"toe_vector":vec(toe-ankle),"knee_off_axis":vec(knee-hip-axis*(knee-hip).dot(axis))}
			avatar.reset_pose()
			avatar.set_hips_offset(Vector3(0,-0.04,0))
			var solver=LegIK.new()
			solver.solve(avatar,side,ankle,1.0)
			var posedhip=sk.get_bone_global_pose(avatar.bone_index[side+"UpperLeg"]).origin
			var posedknee=sk.get_bone_global_pose(avatar.bone_index[side+"LowerLeg"]).origin
			var posedankle=sk.get_bone_global_pose(avatar.bone_index[side+"Foot"]).origin
			axis=(posedankle-posedhip).normalized()
			row.ik[side]={"error_m":posedankle.distance_to(ankle),"knee_off_axis":vec(posedknee-posedhip-axis*(posedknee-posedhip).dot(axis)),"foot_rest_angle_deg":rad_to_deg(sk.get_bone_global_pose(avatar.bone_index[side+"Foot"]).basis.get_rotation_quaternion().angle_to(sk.get_bone_global_rest(avatar.bone_index[side+"Foot"]).basis.get_rotation_quaternion()))}
		var meshes=[]
		avatar._collect_meshes(avatar.model,meshes)
		row["low_vertex_weights"]={}
		for mesh in meshes:
			if not mesh.skin or not mesh.mesh: continue
			var to_sk=sk.global_transform.affine_inverse()*mesh.global_transform
			for surface in mesh.mesh.get_surface_count():
				var arrays=mesh.mesh.surface_get_arrays(surface)
				var verts=arrays[Mesh.ARRAY_VERTEX]
				var joints=arrays[Mesh.ARRAY_BONES]
				var weights=arrays[Mesh.ARRAY_WEIGHTS]
				if joints==null or weights==null: continue
				var influences=int(joints.size()/verts.size())
				for i in verts.size():
					if (to_sk*verts[i]).y>0.04: continue
					for k in influences:
						var offset=i*influences+k
						if weights[offset]<0.05: continue
						var bind=int(joints[offset])
						var bname=str(mesh.skin.get_bind_name(bind))
						if bname.is_empty(): bname=sk.get_bone_name(mesh.skin.get_bind_bone(bind))
						row.low_vertex_weights[bname]=float(row.low_vertex_weights.get(bname,0))+weights[offset]
		rows.append(row)
		avatar.free()
	var out=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/leg_rig/measurements.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(rows,"  "))
	print("RIG_AUDIT_ROWS=",rows.size())
	quit()
