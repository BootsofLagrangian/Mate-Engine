extends SceneTree
## Headless probe: load a VRM at runtime through the addon and print skeleton facts.
## Usage: Godot --headless --path companion/native -s tools/probe_vrm.gd -- /abs/path/model.vrm

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "../assets/cheval-grand.vrm" if args.is_empty() else args[0]
	path = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var gltf := GLTFDocument.new()
	var ext: GLTFDocumentExtension = load("res://addons/vrm/vrm_extension.gd").new()
	gltf.register_gltf_document_extension(ext, true)
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state, 8)
	print("append_from_file: ", error_string(err))
	if err != OK:
		quit(1)
		return
	var scene: Node = gltf.generate_scene(state)
	gltf.unregister_gltf_document_extension(ext)
	print("root: ", scene, " script=", scene.get_script())
	var skel: Skeleton3D = scene.find_child("*", true, false) as Skeleton3D if false else _find_skel(scene)
	print("skeleton: ", skel, " bones=", skel.get_bone_count() if skel else -1)
	if skel:
		for n in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftEye", "RightEye", "LeftHand"]:
			var i := skel.find_bone(n)
			if i < 0:
				print("  missing bone ", n)
				continue
			var g := skel.get_bone_global_rest(i)
			print("  %s idx=%d parent=%d rest_local_rot=%s global_pos=%s global_basis_is_identity=%s" % [n, i, skel.get_bone_parent(i), skel.get_bone_rest(i).basis.get_euler() * 57.2958, g.origin, g.basis.is_equal_approx(Basis.IDENTITY)])
		print("  all bone names: ", Array(range(skel.get_bone_count())).map(func(i): return skel.get_bone_name(i)))
		print("  skeleton global transform: ", skel.global_transform if skel.is_inside_tree() else skel.transform)
		var p := skel.get_parent()
		while p:
			print("  ancestor ", p.name, " transform ", p.transform if p is Node3D else "")
			p = p.get_parent()
	var ap: AnimationPlayer = scene.get_node_or_null("AnimationPlayer")
	if ap:
		var names := ap.get_animation_list()
		print("animations: ", names)
		for a in ["blink", "aa", "happy", "sad", "relaxed", "surprised", "angry", "neutral", "lookLeft"]:
			if ap.has_animation(a):
				var anim := ap.get_animation(a)
				var tracks := []
				for t in anim.get_track_count():
					tracks.append([anim.track_get_type(t), anim.track_get_path(t), anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)])
				print("  ", a, " tracks=", tracks)
	var meta = scene.get("vrm_meta")
	if meta:
		print("meta: ", meta.get("title"), " version=", meta.get("spec_version"), " keys=", meta.get_property_list().map(func(p): return p.name).slice(0, 40))
		var bm: BoneMap = meta.get("humanoid_bone_mapping")
		if bm:
			print("bonemap Head->", bm.get_skeleton_bone_name("Head"), " LeftEye->", bm.get_skeleton_bone_name("LeftEye"))
	var meshes := []
	_collect(scene, meshes)
	for m in meshes:
		print("mesh ", m.name, " blendshapes=", m.mesh.get_blend_shape_count() if m.mesh else 0)
	quit(0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
