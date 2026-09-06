extends SceneTree
const Contacts = preload("res://scripts/vrm_spring_contacts.gd")
var failures := []
func _init() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	var output := ProjectSettings.globalize_path("res://../diagnostics/physics_cloth")
	var results := []
	# Geometric regression: radial push followed by bone length normalization must not re-penetrate.
	var worst_length := 0.0
	var worst_penetration := 0.0
	for i in 1000:
		var length := 0.07 + float(i % 17) * 0.008
		var radius := 0.02 + float(i % 11) * 0.002
		var direction := Vector3(sin(i * 0.371), cos(i * 0.511), sin(i * 0.711)).normalized()
		var center := direction * length
		var tail := center + Vector3.UP * radius * 0.1
		tail = tail.normalized() * length
		var corrected: Vector3 = Contacts.project_sphere(Vector3.ZERO, tail, length, center, radius)
		worst_length = maxf(worst_length, absf(corrected.length() - length))
		worst_penetration = maxf(worst_penetration, radius - corrected.distance_to(center))
	check(worst_length < 0.000002, "length conservation")
	check(worst_penetration < 0.000001, "sphere nonpenetration")
	for character in ["cheval-grand", "rice-shower", "eishin-flash", "mambo", "hachimi"]:
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		check(avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + character + ".vrm")), "load " + character)
		await process_frame
		avatar.spring_contacts.clear() # explicit lifecycle accounting below
		var contacts := Contacts.new()
		var secondary := Contacts.find_secondary(avatar.model)
		var old_counts := []
		if secondary:
			for state in secondary.spring_bones_internal: old_counts.append(state.colliders.size())
		var info: Dictionary = contacts.configure(avatar, true).duplicate()
		info.character = character
		info.runtime_springs = secondary.spring_bones_internal.size() if secondary else 0
		var start := Time.get_ticks_usec()
		for frame in 120:
			avatar.apply_pose({})
			await process_frame
		info.wall_ms_120_frames = (Time.get_ticks_usec() - start) / 1000.0
		var hit_count := 0
		for entry in contacts.entries: hit_count += entry[1].contacts
		info.contacts = hit_count
		check(info.proxies > 0, "expected imported spring support " + character)
		for i in avatar.skeleton.get_bone_count(): check(avatar.skeleton.get_bone_global_pose(i).origin.is_finite(), "finite " + character)
		contacts.clear()
		if secondary:
			for i in old_counts.size(): check(secondary.spring_bones_internal[i].colliders.size() == old_counts[i], "cleanup " + character)
		results.append(info)
		avatar.free()
	var report := {"engine": Engine.get_version_info(), "results": results, "sphere_cases": 1000, "worst_length_error_m": worst_length, "worst_penetration_m": worst_penetration, "failures": failures}
	FileAccess.open(output.path_join("spring-contacts.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
