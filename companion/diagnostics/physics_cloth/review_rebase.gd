extends SceneTree
var checks:=0
var failures:=[]
func _init():call_deferred("run")
func check(ok:bool,why:String):
	checks+=1
	if not ok:failures.append(why)
func snapshot(secondary)->Array:
	var rows:=[]
	for state in secondary.spring_bones_internal:
		var props:={}
		for p in state.springbone.get_property_list():
			if int(p.usage)&PROPERTY_USAGE_STORAGE:props[p.name]=var_to_str(state.springbone.get(p.name))
		var joints:=[]
		for j in state.verlets:joints.append([j,j.length,j.bone_axis,j.bone_idx])
		rows.append([state,props,state.colliders.duplicate(),joints])
	return rows
func run():
	var results:=[]
	for character in ["cheval-grand","rice-shower","eishin-flash","mambo","hachimi"]:
		var avatar:=VrmAvatar.new()
		root.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
		var secondary=avatar.spring_contacts.secondary
		secondary.internal_modifier_node.active=false
		var worst_length:=0.0
		var worst_alignment:=0.0
		var zero_velocity:=true
		for scale_value in [.6,1.0,1.4]:
			avatar.position=Vector3(.56,.25,-.3)
			avatar.rotation_degrees=Vector3(0,45,0)
			avatar.scale=Vector3.ONE*scale_value
			avatar.skeleton.reset_bone_poses()
			avatar.apply_pose({"head":Vector3(0,18,8)})
			var before:=snapshot(secondary)
			var count:=avatar.rebase_secondary_physics()
			check(count>0,"rebase has joints "+character)
			check(snapshot(secondary)==before,"resources/colliders/joint identity unchanged "+character)
			var tails:=[]
			for i in secondary.spring_bones_internal.size():
				var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[i]]
				for j in secondary.spring_bones_internal[i].verlets:
					var pose:=avatar.skeleton.get_bone_global_pose(j.bone_idx)
					var origin:=xf*pose.origin
					var actual:Vector3=j.current_tail-origin
					var expected:Vector3=xf.basis*pose.basis*j.bone_axis
					worst_length=maxf(worst_length,absf(actual.length()-j.length))
					worst_alignment=maxf(worst_alignment,actual.normalized().cross(expected.normalized()).length())
					zero_velocity=zero_velocity and j.current_tail==j.prev_tail
					tails.append(j.current_tail)
			avatar.rebase_secondary_physics()
			var k:=0
			for state in secondary.spring_bones_internal:
				for j in state.verlets:
					check(j.current_tail==tails[k] and j.prev_tail==tails[k],"rebase idempotent "+character)
					k+=1
		check(worst_length<.000002 and worst_alignment<.00002 and zero_velocity,"posed tip/length/zero velocity "+character)
		avatar.seated_floor.configure(avatar,.35)
		avatar.seated_floor.floor_y=.9
		avatar.seated_floor.set_active(true)
		var before_floor:=snapshot(secondary)
		var floor_count:int=avatar.seated_floor._colliders.size()
		check(floor_count>0,"actual seated floor fixture active "+character)
		avatar.rebase_secondary_physics()
		check(snapshot(secondary)==before_floor,"preserves actual seated colliders and terminal joints "+character)
		results.append({"character":character,"worst_length_error_m":worst_length,"worst_direction_cross":worst_alignment,"zero_initial_velocity":zero_velocity,"retained_floor_colliders":floor_count})
		avatar.clear_model()
		avatar.free()
	var report:={"checks":checks,"failures":failures,"rows":results,"scope":"Independent rebase check on five actual rigs at scale .6/1/1.4, yaw45 translation(.56,.25,-.3), posed head; runtime resource/state/collider identity retained, actual seated floor colliders/terminal joints retained. Not a garment appearance or continuous motion benchmark."}
	FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/physics_cloth/review-rebase.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
