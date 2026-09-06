extends SceneTree
const Contacts = preload("res://scripts/vrm_spring_contacts.gd")
var failures := []
var checks := 0
func _init(): call_deferred("run")
func check(ok: bool, why: String):
	checks += 1
	if not ok: failures.append(why)
func resources(secondary) -> Array:
	var rows := []
	for state in secondary.spring_bones_internal:
		var row := {}
		for prop in state.springbone.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_STORAGE:
				row[prop.name] = var_to_str(state.springbone.get(prop.name))
		rows.append(row)
	return rows
func run():
	var rows := []
	var avatar := VrmAvatar.new()
	root.add_child(avatar)
	for character in ["cheval-grand", "rice-shower", "eishin-flash", "mambo", "hachimi"]:
		check(avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + character + ".vrm")), "load " + character)
		check(avatar.spring_contacts.entries.is_empty() and not avatar.spring_contacts.diagnostics.extra_contacts_enabled, "default off " + character)
		var secondary = avatar.spring_contacts.secondary
		secondary.internal_modifier_node.active = false
		avatar.spring_contacts.clear()
		var before := resources(secondary)
		var base_counts := []
		for state in secondary.spring_bones_internal: base_counts.append(state.colliders.size())
		avatar.spring_contacts.configure(avatar, true)
		var count: int = avatar.spring_contacts.entries.size()
		avatar.spring_contacts.configure(avatar, true)
		check(avatar.spring_contacts.entries.size() == count, "configure idempotent " + character)
		for entry in avatar.spring_contacts.entries:
			for joint in entry[0].verlets:
				check(not avatar.bone_rest_local.has(joint.bone_idx), "humanoid excluded " + character)
		var max_error := 0.0
		for scale_value in [0.6, 1.0, 1.4]:
			avatar.scale = Vector3.ONE * scale_value
			avatar.rotation_degrees = Vector3(0, 45, 0)
			avatar.position = Vector3(.2,.1,-.3)
			secondary.update_centers(avatar.skeleton.global_transform)
			var collider = avatar.spring_contacts.entries[0][1]
			var xf: Transform3D = secondary.center_transforms[collider.center_index]
			var point := avatar.skeleton.get_bone_global_pose(collider.from_bone).origin.lerp(avatar.skeleton.get_bone_global_pose(collider.to_bone).origin, collider.blend)
			var center := xf * point
			var proxy_radius: float
			var sc := xf.basis.get_scale().abs()
			proxy_radius = collider.radius_m * maxf(sc.x,maxf(sc.y,sc.z))
			var length := proxy_radius * 3.0
			var origin := center - Vector3.UP * length
			var deep: Vector3 = collider.collision(origin, 0.005, length, center)
			check(deep == center, "deep overlap yields to authored shape " + character)
			var boundary := acos((2.0 * length * length - pow(proxy_radius + .005,2.0)) / (2.0 * length * length))
			var tail := origin + Vector3(sin(boundary-deg_to_rad(1.0)),cos(boundary-deg_to_rad(1.0)),0) * length
			var result: Vector3 = collider.collision(origin, 0.005, length, tail)
			max_error = maxf(max_error, absf(result.distance_to(origin) - length))
			check(result.is_finite() and result.distance_to(center) >= proxy_radius + .005 - .000002, "shallow actual callback scaled collision " + character)
			check(absf(result.distance_to(origin) - length) < .000002, "actual callback length " + character)
		check(resources(secondary) == before, "authored parameters preserved configure/callback " + character)
		var saved_entry = avatar.spring_contacts.entries[0]
		avatar.spring_contacts.clear()
		for i in base_counts.size(): check(secondary.spring_bones_internal[i].colliders.size() == base_counts[i], "clear exact original colliders " + character)
		check(saved_entry[1].host == null, "detached callback owner " + character)
		check(saved_entry[1].collision(Vector3.ZERO, .01, .1, Vector3.UP) == Vector3.UP, "detached safe no-op " + character)
		check(resources(secondary) == before, "authored parameters preserved clear " + character)
		avatar.spring_contacts.configure(avatar, true)
		saved_entry = avatar.spring_contacts.entries[0]
		avatar.clear_model()
		check(saved_entry[1].host == null and not saved_entry[0].colliders.has(saved_entry[1]), "model clear detaches " + character)
		check(avatar.spring_contacts.entries.is_empty() and avatar.spring_contacts.avatar == null and avatar.spring_contacts.secondary == null, "model clear no retained ownership " + character)
		rows.append({"character":character,"proxies":count,"max_length_error_m":max_error})
		avatar.scale = Vector3.ONE
		avatar.rotation = Vector3.ZERO
		avatar.position = Vector3.ZERO
		await process_frame
	avatar.free()
	var report := {"checks":checks,"failures":failures,"rows":rows,"scope":"Independent default-off, lifecycle/resource snapshots and explicit experimental callback at uniform scale 0.6/1/1.4, yaw45 and translation; shallow contact clears, deep overlap yields. Does not assert whole addon physics scale invariance."}
	FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/physics_cloth/review-lifecycle.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
