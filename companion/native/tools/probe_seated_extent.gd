extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	var clip:=VrmaClip.new()
	clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var avatar:=VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm"))
		var geometry:=avatar.calibrate_seated_pose(clip.sample(0))
		avatar.apply_pose({})
		avatar.apply_normalized_rotations(clip.sample(0),1)
		var meshes:=[]
		avatar._collect_meshes(avatar.model,meshes)
		var low_by_bone:={}
		for mesh in meshes:
			if mesh.skin==null: continue
			var transforms:=[]
			var names:=[]
			for bind in mesh.skin.get_bind_count():
				var idx:int=mesh.skin.get_bind_bone(bind)
				if not mesh.skin.get_bind_name(bind).is_empty(): idx=avatar.skeleton.find_bone(mesh.skin.get_bind_name(bind))
				transforms.append(avatar.skeleton.get_bone_global_pose(idx)*mesh.skin.get_bind_pose(bind))
				names.append(avatar.skeleton.get_bone_name(idx))
			for surface in mesh.mesh.get_surface_count():
				var arrays:Array=mesh.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var joints:Variant=arrays[Mesh.ARRAY_BONES]
				var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
				if joints==null: continue
				var count:int=joints.size()/vertices.size()
				for i in vertices.size():
					var p:=Vector3.ZERO
					var biggest:=0.0
					var dominant:=""
					for slot in count:
						var w:float=weights[i*count+slot]
						var bind:int=joints[i*count+slot]
						p+=(transforms[bind]*vertices[i])*w
						if w>biggest:
							biggest=w
							dominant=names[bind]
					if p.y<float(low_by_bone.get(dominant,INF)): low_by_bone[dominant]=p.y
		var sorted:=low_by_bone.keys()
		sorted.sort_custom(func(a,b):return low_by_bone[a]<low_by_bone[b])
		var lowest:={}
		for i in mini(12,sorted.size()): lowest[sorted[i]]=low_by_bone[sorted[i]]
		print("EXTENT ",name," seat=",geometry.anchor," bottom=",geometry.bounds.position.y," lowest=",lowest)
		avatar.free()
	quit()
