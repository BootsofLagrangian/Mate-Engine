extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func run() -> void:
	for character in ["cheval-grand", "rice-shower", "eishin-flash"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		if not avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + character + ".vrm")):
			failures += 1
			continue
		for pose in [Vector3(0.2,-0.94,0.08), Vector3(0.57,0.32,0.32), Vector3(0.42,0.85,0.06), Vector3(0,0,0),Vector3(2,2,2)]:
			avatar.apply_pose({})
			avatar.apply_hand_goals({"left": pose, "right": Vector3(-pose.x,pose.y,pose.z)})
			for side in avatar.arm_ik.diagnostics:
				var d: Dictionary = avatar.arm_ik.diagnostics[side]
				print("IK ",character," ",side," goal=",pose," ",d)
				if float(d.error) > 0.002 or float(d.elbow_degrees) < 7.9 or float(d.elbow_degrees) > 145.1:
					failures += 1
		avatar.free()
	print("ARM_IK_FAILURES=",failures)
	quit(1 if failures else 0)
