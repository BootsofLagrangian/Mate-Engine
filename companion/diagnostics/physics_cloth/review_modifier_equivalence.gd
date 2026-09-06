extends SceneTree
var rows := []
var live: VrmAvatar
var manual: VrmAvatar
var sample_count := 0
var max_tail_error := 0.0
var max_pose_error := 0.0
var max_dt_error := 0.0
var failure := []
var rotations := {}
func _init(): call_deferred("run")
func capture():
	manual.skeleton.reset_bone_poses()
	manual.apply_pose({})
	manual.apply_normalized_rotations(rotations,1.0)
	var dt: float = live.spring_contacts.secondary.get_process_delta_time()
	max_dt_error = maxf(max_dt_error, absf(dt - 1.0/60.0))
	manual.spring_contacts.secondary.do_process(dt)
	var a = live.spring_contacts.secondary.spring_bones_internal
	var b = manual.spring_contacts.secondary.spring_bones_internal
	for i in a.size():
		for j in a[i].verlets.size():
			max_tail_error = maxf(max_tail_error, a[i].verlets[j].current_tail.distance_to(b[i].verlets[j].current_tail))
	for i in live.skeleton.get_bone_count():
		var x := live.skeleton.get_bone_global_pose(i)
		var y := manual.skeleton.get_bone_global_pose(i)
		max_pose_error = maxf(max_pose_error, x.origin.distance_to(y.origin))
		for axis in 3: max_pose_error = maxf(max_pose_error, x.basis[axis].distance_to(y.basis[axis]))
	sample_count += 1
func run():
	for character in ["rice-shower", "eishin-flash"]:
		for motion in ["uma_walk", "sit_idle"]:
			live = VrmAvatar.new()
			manual = VrmAvatar.new()
			root.add_child(live)
			root.add_child(manual)
			for avatar in [live,manual]:
				avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				avatar.spring_contacts.secondary.internal_modifier_node.active=false
			var clip := VrmaClip.new()
			clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/"+motion+".vrma"))
			sample_count=0
			max_tail_error=0.0
			max_pose_error=0.0
			max_dt_error=0.0
			live.spring_contacts.secondary.internal_modifier_node.modification_processed.connect(capture)
			live.spring_contacts.secondary.internal_modifier_node.active=true
			for frame in 180:
				rotations = clip.sample(fmod(frame/60.0,clip.duration))
				for avatar in [live,manual]:
					avatar.apply_pose({})
					avatar.apply_normalized_rotations(rotations,1.0)
				await process_frame
			live.spring_contacts.secondary.internal_modifier_node.active=false
			live.spring_contacts.secondary.internal_modifier_node.modification_processed.disconnect(capture)
			var row := {"character":character,"motion":motion,"samples":sample_count,"max_tail_error_m":max_tail_error,"max_pose_component_error":max_pose_error,"max_delta_error_s":max_dt_error}
			rows.append(row)
			if sample_count < 179 or max_tail_error > .00001 or max_pose_error > .00001 or max_dt_error > .000001: failure.append(row)
			live.free()
			manual.free()
	var result := {"rows":rows,"failures":failure,"scope":"Actual enabled SkeletonModifier callback versus restored-input manual tick; both imported rigs and identical clip input, same actual delta, sampled inside modification_processed after live physics. No rendering or garment acceptance inferred."}
	FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/physics_cloth/review-modifier-equivalence.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failure.is_empty() else 1)
