extends SceneTree
## Supply externally to an exported executable: tools are excluded from its PCK.
var failures := 0
var rows := []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scripts/desktop_object_contact_scene.gd").new()
	root.add_child(scene)
	for type in ["chair", "sofa", "computer"]:
		var path: String = "res://assets/desktop_objects/premium/" + ("workstation" if type == "computer" else type) + ".glb"
		var ok: bool = scene.configure(type)
		rows.append({"type":type,"physical_file":FileAccess.file_exists(path),
			"resource_exists":ResourceLoader.exists(path),"configured":ok,"error":scene.error})
		if not ok: failures += 1
		print("PACKAGED_CONTACT_ASSET ", JSON.stringify(rows.back()))
	scene.free()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--output" and i + 1 < args.size():
			var file := FileAccess.open(args[i+1],FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify({"assets":rows,"failures":failures},"  "))
	print("PACKAGED_CONTACT_ASSET_FAILURES=",failures)
	quit(0 if failures == 0 else 1)
