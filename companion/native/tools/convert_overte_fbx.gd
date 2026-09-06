extends SceneTree
## Offline FBX import/export probe; no runtime or installed manifest changes.
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- input.fbx output.glb")
		quit(2)
		return
	var document := FBXDocument.new()
	var state := FBXState.new()
	var error := document.append_from_file(args[0], state)
	if error != OK:
		push_error("FBX import error: %s" % error)
		quit(1)
		return
	var scene := document.generate_scene(state)
	root.add_child(scene)
	var output := GLTFDocument.new()
	var output_state := GLTFState.new()
	error = output.append_from_scene(scene, output_state)
	if error == OK:
		error = output.write_to_filesystem(output_state, args[1])
	print("FBX_CONVERSION_ERROR=", error)
	scene.free()
	quit(0 if error == OK else 1)
