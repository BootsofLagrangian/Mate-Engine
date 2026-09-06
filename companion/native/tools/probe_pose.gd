extends SceneTree
## Numeric probe for the world-aligned additive pose math on a real VRM.

var _ran := false


func _process(_d: float) -> bool:
	if _ran:
		return false
	_ran = true
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/cheval-grand.vrm").simplify_path()
	var scene := VrmAvatar.load_vrm(path)
	var av := VrmAvatar.new()
	root.add_child(av)
	av.set_model(scene)
	var sk := av.skeleton
	for bone in ["rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand", "head"]:
		var idx: int = av.bone_index[bone]
		var g := sk.get_bone_global_rest(idx)
		print("%s idx=%d parent=%s rest_local_euler=%s global_rest_basis=%s origin=%s" % [bone, idx, sk.get_bone_name(sk.get_bone_parent(idx)), sk.get_bone_rest(idx).basis.get_euler() * 57.3, g.basis, g.origin])
	var idx: int = av.bone_index["rightUpperArm"]
	var g: Basis = sk.get_bone_global_rest(idx).basis
	var r := VrmAvatar.canonical_to_basis(Vector3(0, 0, -60))
	print("R = ", r, " euler=", r.get_euler() * 57.3)
	print("expected global = R*G = ", r * g)
	av.apply_pose({"rightUpperArm": Vector3(0, 0, -60)})
	print("actual global pose basis = ", sk.get_bone_global_pose(idx).basis)
	print("pose local = ", sk.get_bone_pose_rotation(idx).get_euler() * 57.3, " rest local = ", sk.get_bone_rest(idx).basis.get_euler() * 57.3)
	var hand: int = av.bone_index["rightHand"]
	print("hand global origin = ", sk.get_bone_global_pose(hand).origin, " upperArm origin = ", sk.get_bone_global_pose(idx).origin)
	quit(0)
	return true
