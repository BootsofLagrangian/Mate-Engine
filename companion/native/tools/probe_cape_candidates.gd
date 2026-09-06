extends SceneTree
## Compare actual enabled SkeletonModifier with authored pose/no-secondary, same origin.
var avatars:=[]
var captured:={}
var captured_baseline:={}
var output:="/tmp/cape-candidates-effective"
var rows:=[]
var sample_requested:=false
var callback_count:=0
var profile:Dictionary
var variant:=""
var original_parameters:={}
func parameters(avatar:VrmAvatar)->Dictionary:
	var result:={}
	for state in avatar.spring_contacts.secondary.spring_bones_internal:
		var sb:VRMSpringBone=state.springbone
		result[state.joint_nodes[0]]={"stiffness_scale":sb.stiffness_scale,"gravity_scale":sb.gravity_scale,"drag_scale":sb.drag_force_scale,"radius_scale":sb.hit_radius_scale,"stiffness":Array(sb.stiffness_force),"gravity":Array(sb.gravity_power),"drag":Array(sb.drag_force),"radius":Array(sb.hit_radius),"collider_ids":sb.collider_groups.map(func(c):return c.get_instance_id())}
	return result


func apply_candidate(avatar:VrmAvatar, gravity_anchor:float)->void:
	for chain in profile.chains:
		for state in avatar.spring_contacts.secondary.spring_bones_internal:
			if state.joint_nodes[0]!=chain.root: continue
			print("CANDIDATE_CHAIN ", chain.root, " gravity ",gravity_anchor)
			# Isolate resource: other chains can share the imported group.
			state.springbone=state.springbone.duplicate(false)
			var stiffness:=PackedFloat64Array();var gravity:=PackedFloat64Array()
			for name in state.joint_nodes:
				var source:Dictionary={}
				for joint in chain.joints:
					if joint._boneName==name: source=joint;break
				if source.is_empty(): source=chain.joints[-1]
				stiffness.append(2.5*float(source._stiffnessForce)/float(chain.joints[0]._stiffnessForce))
				gravity.append(gravity_anchor*float(source._gravity)/float(chain.joints[0]._gravity))
			state.springbone.stiffness_force=stiffness;state.springbone.gravity_power=gravity
			state.springbone.stiffness_scale=1.0;state.springbone.gravity_scale=1.0
			# Preserve imported drag/radii/colliders: source unit/basis mapping is unresolved.

func _init() -> void: call_deferred("run")
func pose_snapshot(avatar:VrmAvatar)->Dictionary:
	var bones:={}
	for i in avatar.skeleton.get_bone_count():
		if "Mantle" in avatar.skeleton.get_bone_name(i):
			var pose:=avatar.skeleton.get_bone_global_pose(i)
			bones[avatar.skeleton.get_bone_name(i)]={"origin":[pose.origin.x,pose.origin.y,pose.origin.z],"scale":[pose.basis.get_scale().x,pose.basis.get_scale().y,pose.basis.get_scale().z],"rotation":[pose.basis.get_rotation_quaternion().x,pose.basis.get_rotation_quaternion().y,pose.basis.get_rotation_quaternion().z,pose.basis.get_rotation_quaternion().w]}
	return bones
func capture_baseline()->void:
	if sample_requested: captured_baseline=pose_snapshot(avatars[0])
func capture_live()->void:
	callback_count+=1
	if sample_requested:
		captured=pose_snapshot(avatars[1])
func run()->void:
	profile=JSON.parse_string(FileAccess.get_file_as_string("res://../assets/research/cape-candidates/cyspring-cloth00.json"))
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(800,800)
	var stage:=Node3D.new();root.add_child(stage)
	var camera:=Camera3D.new();stage.add_child(camera)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-30,0);stage.add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.10,.13,.18);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;stage.add_child(env)
	for side in 2:
		var avatar:=VrmAvatar.new();stage.add_child(avatar)
		avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
		avatar.spring_contacts.secondary.internal_modifier_node.active=true
		avatars.append(avatar)
	original_parameters=parameters(avatars[1])
	avatars[0].spring_contacts.secondary.internal_modifier_node.modification_processed.connect(capture_baseline)
	avatars[1].spring_contacts.secondary.internal_modifier_node.modification_processed.connect(capture_live)
	for gravity_anchor in [.6,1.2,5.0,12.5]:
		variant="sourcecurve-g"+str(gravity_anchor)
		apply_candidate(avatars[1],gravity_anchor)
		var projection:="perspective"
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL if projection=="orthographic" else Camera3D.PROJECTION_PERSPECTIVE
		camera.size=2.5;camera.fov=35
		camera.position=Vector3(0,.9,4) if projection=="orthographic" else Vector3(2.45,2.9,2.45)
		camera.look_at(Vector3(0,.9,0))
		for motion in ["rest","authored_overhead_stretch","authored_stretch"]:
			var clip:=VrmaClip.new()
			if motion!="rest": clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/"+motion+".vrma"))
			for avatar in avatars:
				avatar.skeleton.reset_bone_poses();avatar.apply_pose({});avatar.rebase_secondary_physics()
			for frame in 180:
				for avatar in avatars: avatar.visible=true
				for avatar in avatars:
					avatar.apply_pose({})
					if motion!="rest": avatar.apply_normalized_rotations(clip.sample(frame/60.0),1.0)
				sample_requested=frame in [0,30,60,90,120,150,179]
				await process_frame
				if sample_requested:
					var baseline:=captured_baseline.duplicate(true)
					rows.append({"runtime_parameters":parameters(avatars[1]),"variant":variant,"projection":projection,"motion":motion,"time_s":frame/60.0,"baseline":baseline,"physics":captured.duplicate(true),"callbacks":callback_count})
					for visible_side in 2:
						avatars[0].visible=visible_side==0;avatars[1].visible=visible_side==1
						await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(output.path_join("%s-%s-%03d-%s.png"%[variant,motion,frame,"baseline" if visible_side==0 else "candidate"]))
	var report:={"original_parameters":original_parameters,"scope":"actual modifier both sides; original vs source-relative stiffness/gravity curve candidate; unknown native units deliberately not inferred; no imported limits/connections; same origin; source held during paired readback", "callbacks":callback_count,"rows":rows}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("CAPE_CALLBACKS ",callback_count);quit()
