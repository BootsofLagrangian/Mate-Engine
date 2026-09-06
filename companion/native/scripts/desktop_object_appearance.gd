extends RefCounted
## Declarative material presets. Resources are duplicated per instance; never edit imports.
const IDS := ["default", "warm", "cool", "porcelain", "flat"]
static func apply(root: Node, preset: String) -> bool:
	if preset not in IDS: return false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		if not mesh.has_meta("object_original_materials"):
			var originals: Array = []
			for index in mesh.mesh.get_surface_count(): originals.append(mesh.get_active_material(index))
			mesh.set_meta("object_original_materials", originals)
		var originals: Array = mesh.get_meta("object_original_materials")
		for index in mesh.mesh.get_surface_count():
			var original: Material = originals[index]
			if preset == "default": mesh.set_surface_override_material(index,original); continue
			var material := original.duplicate() as StandardMaterial3D if original is StandardMaterial3D else StandardMaterial3D.new()
			if preset == "flat":
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			elif preset == "porcelain":
				material = StandardMaterial3D.new()
				material.albedo_color = Color(.91,.89,.82)
				material.roughness = .22
			else:
				material.albedo_color *= Color(1.0,.86,.73) if preset == "warm" else Color(.76,.89,1.0)
			mesh.set_surface_override_material(index,material)
	return true
