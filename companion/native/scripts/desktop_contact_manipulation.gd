class_name DesktopContactManipulation
extends RefCounted
## The furniture frame owns both hands and the standing actor's target. No
## independent tween may advance furniture while reach or collision is invalid.
const GripPose=preload("desktop_grip_pose.gd")
const Setup = preload("desktop_workstation_setup.gd")
const Navigation = preload("desktop_scene_navigation_host.gd")

static func target(scene: DesktopObjectContactScene, ground_y: float, stance_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var anchors: Dictionary = scene.interaction_anchor_catalogue(true)
	for key in ["manipulate_approach","grip_left","grip_right"]:
		if not anchors.has(key):return {}
	var foot:Vector3=anchors.manipulate_approach.position+scene.seat_node().global_basis*stance_offset
	foot.y=ground_y
	var facing:Vector3=anchors.manipulate_approach.facing
	return {"foot":foot,"yaw":atan2(facing.x,facing.z),"left":anchors.grip_left.position,"right":anchors.grip_right.position}

static func admit(scene: DesktopObjectContactScene, pull: float, yaw: float, ground_y: float, radius: float, height: float, others: Array, fit: Callable, ground_fit: Callable, stance_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var initial:=scene.seat_setup()
	if not is_finite(pull) or not is_finite(yaw) or not is_finite(ground_y) or not is_finite(radius) or radius<=0 or not is_finite(height) or height<=0:return {"accepted":false,"reason":"invalid_manipulation_geometry"}
	if not scene.set_seat_setup(pull,yaw):return {"accepted":false,"reason":"invalid_manipulation_target"}
	scene.set_seat_setup(initial.pullout_local_m,initial.yaw_delta_deg)
	var start:=target(scene,ground_y,stance_offset)
	if start.is_empty():return {"accepted":false,"reason":"missing_grip_anchors"}
	var angle:=angle_difference(deg_to_rad(float(initial.yaw_delta_deg)),deg_to_rad(yaw))
	var count:=maxi(1,maxi(int(ceil(absf(pull-float(initial.pullout_local_m))/.015)),int(ceil(absf(angle)/deg_to_rad(3)))))
	var pivot:Vector3=scene.seat_node().global_position
	var orbital_radius:=Vector2(start.foot.x-pivot.x,start.foot.z-pivot.z).length()
	var body_radius:=radius+orbital_radius*(1.0-cos(absf(angle)/count*.5))+.00001
	var result:Dictionary={"accepted":true,"reason":"clear","samples":count+1}
	var seat_parts:Array=[]
	Setup._collect_parts(scene.seat_node(),scene.seat_node().global_transform.affine_inverse(),seat_parts)
	var fixed_parts:Array=[]
	for child in scene._content.get_children():
		if child!=scene.seat_node():Setup._collect_parts(child,scene.global_transform.affine_inverse(),fixed_parts)
	var fixed_world:Array=others.duplicate()
	for box in others:
		if not box is AABB or not box.position.is_finite() or not box.size.is_finite():return {"accepted":false,"reason":"invalid_manipulation_obstacle"}
	for box in fixed_parts:fixed_world.append(scene.global_transform*AABB(box))
	var before:Dictionary=start
	var maximum_radius:=0.0
	for part in seat_parts:
		for vertex in 8:
			var point:Vector3=AABB(part).get_endpoint(vertex)
			maximum_radius=maxf(maximum_radius,Vector2(point.x,point.z).length())
	for i in range(1,count+1):
		var t:=float(i)/count
		var next_pull:=lerpf(float(initial.pullout_local_m),pull,t)
		var next_yaw:=wrapf(rad_to_deg(deg_to_rad(float(initial.yaw_delta_deg))+angle*t),-180,180)
		var previous_transform:Transform3D=scene.seat_node().transform
		if not scene.set_seat_setup(next_pull,next_yaw):result={"accepted":false,"reason":"invalid_manipulation_target"};break
		var after:=target(scene,ground_y,stance_offset)
		# The actor follows a fixed chair-local stance. Testing the rotated
		# chair's WORLD AABB would falsely collide with its empty corner space.
		# Own-chair clearance is exact in that frame; the actual curved actor
		# path is independently swept against fixed/world obstacles below.
		var chair_scale:float=scene.seat_node().global_basis.x.length()
		var local_foot:Vector3=scene.seat_node().to_local(after.foot)
		if not Navigation.placement_is_clear(local_foot,local_foot,seat_parts,radius/chair_scale,height/chair_scale):
			result={"accepted":false,"reason":"manipulation_actor_hits_chair"};break
		if not Navigation.placement_is_clear(before.foot,after.foot,fixed_world,body_radius,height) or (ground_fit.is_valid() and not ground_fit.call(after.foot)):
			result={"accepted":false,"reason":"manipulation_actor_blocked"};break
		var current_transform:Transform3D=scene.seat_node().transform
		var arc_pad:=maximum_radius*current_transform.basis.x.length()*(1.0-cos(absf(angle)/count*.5))+.00001
		var envelope:=scene.get_local_bounds()
		var clear:=true
		for part in seat_parts:
			var swept:AABB=(previous_transform*AABB(part)).merge(current_transform*AABB(part)).grow(arc_pad)
			envelope=envelope.merge(swept)
			for obstacle in fixed_parts:
				if Setup._positive_overlap(swept,obstacle):clear=false
			var world_swept:AABB=scene.global_transform*swept
			for obstacle in others:
				if Setup._positive_overlap(world_swept,obstacle):clear=false
		if not clear:result={"accepted":false,"reason":"manipulation_chair_sweep_blocked"};break
		if fit.is_valid() and not fit.call(scene,envelope):result={"accepted":false,"reason":"manipulation_view_blocked"};break
		before=after
	scene.set_seat_setup(initial.pullout_local_m,initial.yaw_delta_deg)
	result.validation_ms=(Time.get_ticks_usec()-started)/1000.0
	return result

static func _collect(scene: DesktopObjectContactScene, output: Array) -> void:
	_collect_world_parts(scene,output)

static func _collect_world_parts(node:Node,output:Array)->void:
	# Transform each authored part directly into world space. Boxing first in
	# the assembly frame and then boxing again in world space falsely inflates
	# a swivelled chair and disagrees with the runtime navigation obstacles.
	if node is MeshInstance3D and node.mesh!=null:
		for box in Setup.Solids.local_parts(node.mesh):output.append(node.global_transform*AABB(box))
	for child in node.get_children():_collect_world_parts(child,output)

static func press_offset(elapsed: float, side: String, scale: float) -> Vector3:
	# Independent finite downstrokes remain above the hard keyboard plane.
	var phase:=fposmod(elapsed*2.1+(0.5 if side=="right" else 0.0),1.0)
	return Vector3.UP*(.004*scale*(.5+.5*cos(TAU*phase)))

static func articulation_clear(avatar: VrmAvatar, solids: Array) -> Dictionary:
	var pairs:Array=[["hips","spine",.075],["spine","chest",.075],["chest","neck",.07],["neck","head",.065]]
	for side in ["left","right"]:
		pairs.append([side+"UpperArm",side+"LowerArm",.025])
		pairs.append([side+"LowerArm",side+"Hand",.018])
		pairs.append([side+"UpperLeg",side+"LowerLeg",.04])
		pairs.append([side+"LowerLeg",side+"Foot",.035])
	var scale:float=avatar.skeleton.global_basis.x.length()
	for pair in pairs:
		if not avatar.bone_index.has(pair[0]) or not avatar.bone_index.has(pair[1]):continue
		var a:Vector3=avatar.bone_global_position(pair[0]);var b:Vector3=avatar.bone_global_position(pair[1])
		# The final wrist/palm is the declared contact feature. The remaining
		# forearm, shoulder, torso and legs must stay outside furniture solids.
		if str(pair[1]).ends_with("Hand"):b=b.move_toward(a,.07*scale)
		for box in solids:
			var start:=a;var end:=b
			var radius:float=float(pair[2])*scale
			var bounds:AABB
			if box is Dictionary:
				start=Transform3D(box.inverse)*a;end=Transform3D(box.inverse)*b
				radius/=float(box.scale);bounds=box.bounds
			else:bounds=box
			var expanded:AABB=bounds.grow(radius)
			if expanded.has_point(start) or expanded.has_point(end) or expanded.intersects_segment(start,end)!=null:return {"clear":false,"bone":pair[0],"reason":"grip_body_collision"}
	return {"clear":true}

static func grip_reach_admission(avatar: VrmAvatar, scene: DesktopObjectContactScene, ground_y: float, stance_offset: Vector3, lean: Vector2 = Vector2(25,15), others: Array = []) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var saved_transform:=avatar.global_transform
	var sk:=avatar.skeleton
	var positions:Array=[];var rotations:Array=[];var scales:Array=[]
	for index in sk.get_bone_count():
		positions.append(sk.get_bone_pose_position(index));rotations.append(sk.get_bone_pose_rotation(index));scales.append(sk.get_bone_pose_scale(index))
	var posed:Dictionary=avatar._posed_bones.duplicate()
	var diagnostics:Dictionary=avatar.arm_ik.diagnostics.duplicate(true)
	var grip:=target(scene,ground_y,stance_offset)
	var result:Dictionary={"accepted":true,"reason":"clear","stance_offset":stance_offset,"maximum_hand_error_m":0.0}
	var solids:Array=others.duplicate()
	for child in scene._content.get_children():
		var parts:Array=[]
		Setup._collect_parts(child,child.global_transform.affine_inverse(),parts)
		var inverse:Transform3D=child.global_transform.affine_inverse()
		var child_scale:float=child.global_basis.x.length()
		for box in parts:solids.append({"bounds":box,"inverse":inverse,"scale":child_scale})
	avatar.global_basis=Basis(Vector3.UP,float(grip.yaw)).scaled(saved_transform.basis.get_scale())
	avatar.reset_pose()
	avatar.global_position+=Vector3(grip.foot)-Vector3(avatar.contact_anchors().foot)
	var actor_scale:float=avatar.skeleton.global_basis.x.length()
	# Reject unreachable endpoints before sampling acquisition. This keeps the
	# bounded posture search cheap without dropping any successful-path sample.
	var samples:Array=[20]
	for index in 20:samples.append(index)
	for sample in samples:
		var weight:=float(sample)/20.0
		avatar.reset_pose()
		avatar.add_pose_offsets({"spine":Vector3(lean.x*weight,0,0),"chest":Vector3(lean.y*weight,0,0)})
		for side in ["left","right"]:
			var contact:Dictionary=GripPose.solve(avatar,side,grip[side],Vector3(sin(float(grip.yaw)),0,cos(float(grip.yaw))),weight,.3*actor_scale*sin(PI*weight))
			var reachable:bool=contact.get("reached",false)
			if sample==20:
				var error:float=contact.get("contact_error_m",INF)
				result.maximum_hand_error_m=maxf(float(result.maximum_hand_error_m),error)
				if not reachable or error>.008:result.accepted=false;result.reason="grip_unreachable"
		var body:=articulation_clear(avatar,solids)
		if not body.get("clear",false):result.accepted=false;result.reason="grip_body_collision";result.body=body;result.weight=weight
		if not result.accepted:break
	avatar.global_transform=saved_transform
	for index in sk.get_bone_count():
		sk.set_bone_pose_position(index,positions[index]);sk.set_bone_pose_rotation(index,rotations[index]);sk.set_bone_pose_scale(index,scales[index])
	avatar._posed_bones=posed
	avatar.arm_ik.diagnostics=diagnostics
	result.validation_ms=(Time.get_ticks_usec()-started)/1000.0
	return result

static func select_approach(avatar: VrmAvatar, scene: DesktopObjectContactScene, actor: Vector3, radius: float, height: float, others: Array = [], route_fit: Callable = Callable(), navigation_geometry:Dictionary={}, preferred_stance:Variant=null, stance_validator:Callable=Callable()) -> Dictionary:
	var nominal:=target(scene,actor.y)
	if nominal.is_empty():return {"accepted":false,"reason":"missing_grip_anchors"}
	var obstacles:Array=others.duplicate()
	_collect(scene,obstacles)
	var low:=Vector2(minf(actor.x,nominal.foot.x),minf(actor.z,nominal.foot.z))-Vector2.ONE*1.5
	var high:=Vector2(maxf(actor.x,nominal.foot.x),maxf(actor.z,nominal.foot.z))+Vector2.ONE*1.5
	var area:Rect2=navigation_geometry.get("area",Rect2(low,high-low))
	var cell:float=float(navigation_geometry.get("cell_size",Navigation.navigation_cell_size(high-low)))
	var nav:=DesktopSceneNavigation.new()
	var configured:=nav.configure(area,actor.y,obstacles,radius,height,cell)
	if not configured.get("ok",false):nav.dispose();return {"accepted":false,"reason":configured.get("reason","invalid_grip_navigation")}
	if not nav.is_navigable(actor):
		var nearest:Vector3=NavigationServer3D.map_get_closest_point(nav._map,actor)
		var rejected:Dictionary={"accepted":false,"reason":"grip_start_outside_navigation","start_world":actor,"nearest_mesh_point":nearest,"mesh_distance_m":nearest.distance_to(actor),"actor_capsule_clear":Navigation.placement_is_clear(actor,actor,obstacles,radius,height),"navigation_geometry":{"area":area,"cell_size":cell},"navigation_diagnostics":nav.diagnostics.duplicate()}
		nav.dispose();return rejected
	var attempts:Array=[]
	var offsets:Array[Vector3]=[]
	if preferred_stance is Vector3 and preferred_stance.is_finite() and preferred_stance.length()<=.3:offsets.append(preferred_stance)
	for retreat in [0.0,.025,.05,.075,.1,.125,.15,.175,.2,.225,.25]:
		for side in [0.0,-.05,.05]:
			var offset:=Vector3(side,0,-retreat)
			if not offsets.has(offset):offsets.append(offset)
	for offset in offsets:
		var grip:=target(scene,actor.y,offset)
		if not nav.is_navigable(grip.foot):attempts.append({"offset":offset,"reason":"blocked_grip_endpoint"});continue
		var route:=nav.plan("grip_admission",actor,grip.foot,.35*avatar.global_basis.x.length())
		if not route.get("accepted",false):attempts.append({"offset":offset,"reason":route.get("reason","")});continue
		if route_fit.is_valid() and not route_fit.call(route.path):attempts.append({"offset":offset,"reason":"grip_approach_outside_workarea"});continue
		if stance_validator.is_valid():
			var admission:Dictionary=stance_validator.call(offset)
			if not admission.get("accepted",false):attempts.append({"offset":offset,"reason":admission.get("reason","unsafe_manipulation_handoff")});continue
		for lean in [Vector2.ZERO,Vector2(10,5),Vector2(20,10),Vector2(25,15),Vector2(30,15),Vector2(30,20),Vector2(35,20)]:
			var pose:=grip_reach_admission(avatar,scene,actor.y,offset,lean,others)
			if not pose.get("accepted",false):attempts.append({"offset":offset,"lean":lean,"reason":pose.reason});continue
			route.stance_offset=offset;route.lean=lean;route.pose_admission=pose
			route.navigation_geometry={"area":area,"cell_size":cell};route.attempts=attempts
			nav.dispose();return route
	nav.dispose()
	return {"accepted":false,"reason":"no_reachable_grip_stance","attempts":attempts}
