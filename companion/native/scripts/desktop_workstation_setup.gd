class_name DesktopWorkstationSetup
extends RefCounted
## Bounded, geometry-only preparation for an asset-declared movable swivel chair.
## It does not animate, move the actor or claim that the actor's hands pull it.
const Solids = preload("desktop_scene_solids.gd")
const PULL_STEP := .05
const ANGLE_STEP_DEG := 5.0

static func plan(scene: DesktopObjectContactScene, start_world: Vector3, avatar_scale: float, sit_minus_foot: Vector3, source_delta: Vector3, radius: float, height: float, other_solids: Array = [], fit_validator: Callable = Callable(), route_fit: Callable = Callable(), actor_swept: PackedVector3Array = PackedVector3Array()) -> Dictionary:
	if not is_instance_valid(scene) or not scene.supports_seat_setup():return {"accepted":false,"reason":"seat_setup_unsupported"}
	if not start_world.is_finite() or not sit_minus_foot.is_finite() or not source_delta.is_finite() or not is_finite(avatar_scale) or avatar_scale<=0 or not is_finite(radius) or radius<0 or not is_finite(height) or height<=0:return {"accepted":false,"reason":"invalid_setup_geometry"}
	for box in other_solids:
		if not box is AABB or not box.position.is_finite() or not box.size.is_finite():return {"accepted":false,"reason":"invalid_setup_obstacle"}
	if route_fit.is_valid() and actor_swept.is_empty():return {"accepted":false,"reason":"missing_actor_placement_geometry"}
	for point in actor_swept:
		if not point.is_finite():return {"accepted":false,"reason":"invalid_actor_placement_geometry"}
	var original := scene.seat_setup()
	var chair := scene.seat_node()
	var native_parts:Array=[]
	_collect_parts(chair,chair.global_transform.affine_inverse(),native_parts)
	var fixed_parts:Array=[]
	for child in scene._content.get_children():
		if child!=chair:_collect_parts(child,scene.global_transform.affine_inverse(),fixed_parts)
	var toward := start_world-scene.socket_world("seat")
	var preferred := atan2(toward.x,toward.z)
	var yaws:Array=[0.0,90.0,180.0,-90.0]
	yaws.sort_custom(func(a:float,b:float):return absf(angle_difference(preferred,deg_to_rad(a)))<absf(angle_difference(preferred,deg_to_rad(b))))
	var original_facing := scene.facing_direction_world()
	var working_yaw := atan2(original_facing.x,original_facing.z)-deg_to_rad(float(original.yaw_delta_deg))
	var maximum := minf(1.2,float(original.capability.get("max_pullout_m",0)))
	var reason := "no_safe_setup"
	var best_geometry:Dictionary={}
	var attempts := 0
	var started := Time.get_ticks_usec()
	for step in int(floor(maximum/PULL_STEP))+1:
		var pull := step*PULL_STEP
		for yaw in yaws:
			attempts+=1
			var turn := rad_to_deg(angle_difference(working_yaw,deg_to_rad(yaw)))
			var sweep := _setup_sweep(scene,pull,turn,native_parts,fixed_parts,start_world,radius,height,other_solids,fit_validator,original)
			if not sweep.get("clear",false):reason=str(sweep.reason);continue
			var all_solids:Array=other_solids.duplicate()
			DesktopObjectsHost._append_scene_solids(scene,all_solids)
			var entry_basis:=Basis(Vector3.UP,deg_to_rad(yaw)).scaled(Vector3.ONE*avatar_scale)
			var stage:=DesktopObjectsHost.select_authored_staging(start_world,scene.socket_world("seat"),entry_basis,sit_minus_foot,source_delta,all_solids,radius,height)
			if not stage.get("accepted",false):reason=str(stage.get("reason","blocked_endpoint"));continue
			var actor_placement:=PackedVector3Array()
			for point in actor_swept:actor_placement.append(scene.to_local(Vector3(stage.target_world)+point*avatar_scale))
			var path:PackedVector3Array=stage.get("path",PackedVector3Array())
			var route_ok:bool=not route_fit.is_valid() or (not path.is_empty() and bool(route_fit.call(path)))
			var candidate:Dictionary={"accepted":true,"reason":"ready","pullout_local_m":pull,"yaw_delta_deg":turn,"target_world":stage.target_world,"entry_facing_yaw":deg_to_rad(yaw),"root_distance_factor":stage.factor,"setup_bounds_local":sweep.bounds,"setup_parts_local":sweep.parts,"actor_placement_vertices_local":actor_placement,"approach_path":path,"navigation_geometry":stage.get("navigation_geometry",{}),"view_failure":"" if route_ok else "approach_route_outside_workarea","attempts":attempts,"planning_ms":(Time.get_ticks_usec()-started)/1000.0}
			if sweep.get("view_ok",false) and route_ok:
				scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
				return candidate
			if best_geometry.is_empty():best_geometry=candidate
			reason="setup_view_blocked"
		# Preserve the smallest geometric pullout. If its orientations cannot fit,
		# the host may reposition this bounded full envelope on the same floor.
		if not best_geometry.is_empty():break
	scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
	return {"accepted":false,"reason":"setup_view_blocked" if not best_geometry.is_empty() else reason,"geometric_candidate":best_geometry,"attempts":attempts,"planning_ms":(Time.get_ticks_usec()-started)/1000.0}

static func _collect_parts(node:Node, inverse_frame:Transform3D, result:Array) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		for part in Solids.local_parts(node.mesh):result.append(inverse_frame*node.global_transform*AABB(part))
	for child in node.get_children():_collect_parts(child,inverse_frame,result)

static func _setup_sweep(scene:DesktopObjectContactScene,pull:float,turn:float,parts:Array,fixed:Array,actor:Vector3,radius:float,height:float,others:Array,fit:Callable,initial:Dictionary)->Dictionary:
	var initial_pull:float=initial.pullout_local_m
	var initial_yaw:float=initial.yaw_delta_deg
	scene.set_seat_setup(initial_pull,initial_yaw)
	var previous:Transform3D=scene.seat_node().transform
	var bounds:=scene.get_local_bounds()
	var view_ok:bool=not fit.is_valid() or bool(fit.call(scene,bounds))
	var sweep_parts:Array=[]
	for part in parts:sweep_parts.append(previous*AABB(part))
	var maximum_radius:=0.0
	for box in parts:
		for i in 8:
			var p:Vector3=AABB(box).get_endpoint(i)
			maximum_radius=maxf(maximum_radius,Vector2(p.x,p.z).length())
	maximum_radius *= previous.basis.x.length() # declared seat adjustment is uniform
	for phase in 2:
		var yaw_distance:=rad_to_deg(angle_difference(deg_to_rad(initial_yaw),deg_to_rad(turn)))
		var count:=maxi(1,int(ceil(absf(pull-initial_pull)/.025))) if phase==0 else maxi(1,int(ceil(absf(yaw_distance)/ANGLE_STEP_DEG)))
		var angle_step:=0.0 if phase==0 else absf(deg_to_rad(yaw_distance))/count
		# The chord's outward sagitta bounds every point between angular samples.
		var arc_pad:=maximum_radius*(1.0-cos(angle_step*.5))+.00001
		for sample in count+1:
			var t:=float(sample)/count
			var next_yaw:=initial_yaw if phase==0 else wrapf(initial_yaw+yaw_distance*t,-180.0,180.0)
			scene.set_seat_setup(lerpf(initial_pull,pull,t) if phase==0 else pull,next_yaw)
			var current:Transform3D=scene.seat_node().transform
			for part_index in parts.size():
				var part:AABB=parts[part_index]
				var swept: AABB=(previous*AABB(part)).merge(current*AABB(part)).grow(arc_pad)
				sweep_parts[part_index]=AABB(sweep_parts[part_index]).merge(swept)
				bounds=bounds.merge(swept)
				for obstacle in fixed:
					if _positive_overlap(swept,obstacle):return {"clear":false,"reason":"chair_sweep_hits_desk"}
				var world:AABB=scene.global_transform*swept
				if _capsule_box(actor,radius,height,world):return {"clear":false,"reason":"chair_sweep_hits_actor"}
				for obstacle in others:
					if _positive_overlap(world,obstacle):return {"clear":false,"reason":"chair_sweep_hits_object"}
			bounds=bounds.merge(scene.get_local_bounds())
			if fit.is_valid() and not bool(fit.call(scene,bounds)):view_ok=false
			previous=current
	sweep_parts.append_array(fixed)
	return {"clear":true,"reason":"clear","view_ok":view_ok,"bounds":bounds,"parts":sweep_parts}

## Optional semantic-placement fallback. It proposes a new fixed-Y assembly
## position; the caller owns authorization, commit/rollback and a fresh plan.
static func reposition(scene:DesktopObjectContactScene,candidate:Dictionary,camera:Camera3D,desktop_origin:Vector2,areas:Array,actor:Vector3,radius:float,height:float,other_solids:Array,maximum_distance:float,candidate_validator:Callable=Callable())->Dictionary:
	if not is_instance_valid(scene) or not is_instance_valid(camera) or not candidate.get("setup_bounds_local") is AABB or not candidate.get("setup_parts_local") is Array:
		return {"ok":false,"reason":"missing_setup_envelope"}
	var bounds:AABB=candidate.setup_bounds_local
	var vertices:=PackedVector3Array()
	# Runtime contact_bounds projects the world-axis AABB. Preserve that same
	# conservative envelope here: transformed local corners alone are tighter
	# under perspective and could admit a crop that fails on the first frame.
	var world_offsets:AABB=Transform3D(scene.global_basis,Vector3.ZERO)*bounds
	var inverse_basis:=scene.global_basis.inverse()
	for i in 8:vertices.append(inverse_basis*world_offsets.get_endpoint(i))
	for point in candidate.get("actor_placement_vertices_local",PackedVector3Array()):vertices.append(point)
	var obstacles:Array=other_solids.duplicate()
	obstacles.append(AABB(actor-Vector3(radius,0,radius),Vector3(radius*2,height,radius*2)))
	return DesktopObjectPlacement.find(camera,desktop_origin,areas,scene.global_position,scene.global_basis,vertices,candidate.setup_parts_local,obstacles,maximum_distance,candidate_validator)

static func _positive_overlap(a:AABB,b:AABB)->bool:
	var overlap:=a.intersection(b)
	return overlap.size.x>.00002 and overlap.size.y>.00002 and overlap.size.z>.00002

static func _capsule_box(foot:Vector3,radius:float,height:float,box:AABB)->bool:
	if box.end.y<=foot.y or box.position.y>=foot.y+height:return false
	return Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(radius).has_point(Vector2(foot.x,foot.z))

## Check an empty-chair recovery from its actual interrupted pose. If both
## coordinates change, translation precedes rotation, exactly as the planner.
static func validate_setup_sweep(scene:DesktopObjectContactScene,pull:float,yaw:float,actor:Vector3,radius:float,height:float,others:Array=[],fit:Callable=Callable())->Dictionary:
	if not is_instance_valid(scene) or not scene.supports_seat_setup() or not actor.is_finite() or not is_finite(radius) or radius<0 or not is_finite(height) or height<=0:return {"clear":false,"accepted":false,"reason":"invalid_setup_geometry"}
	var original:=scene.seat_setup()
	if not scene.set_seat_setup(pull,yaw):return {"clear":false,"accepted":false,"reason":"invalid_setup_target"}
	scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
	var chair:=scene.seat_node()
	var parts:Array=[]
	_collect_parts(chair,chair.global_transform.affine_inverse(),parts)
	var fixed:Array=[]
	for child in scene._content.get_children():
		if child!=chair:_collect_parts(child,scene.global_transform.affine_inverse(),fixed)
	for box in others:
		if not box is AABB or not box.position.is_finite() or not box.size.is_finite():return {"clear":false,"accepted":false,"reason":"invalid_setup_obstacle"}
	var started:=Time.get_ticks_usec()
	var result:=_setup_sweep(scene,pull,yaw,parts,fixed,actor,radius,height,others,fit,original)
	scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
	if result.get("clear",false) and not result.get("view_ok",false):result["clear"]=false;result.reason="setup_view_blocked"
	result["accepted"]=result.get("clear",false)
	result["validation_ms"]=(Time.get_ticks_usec()-started)/1000.0
	return result

## Find a bounded real walking destination before restoring the empty chair.
## Both restoration phases and the complete current-solid route are checked.
## Callbacks are read-only: fit(scene, local_envelope), ground_fit(world_foot).
static func find_restore_clearance(scene:DesktopObjectContactScene,start:Vector3,radius:float,height:float,other_solids:Array=[],fit:Callable=Callable(),ground_fit:Callable=Callable(),maximum_distance:float=.5)->Dictionary:
	if not is_instance_valid(scene) or not scene.supports_seat_setup() or not start.is_finite() or not is_finite(radius) or radius<0 or not is_finite(height) or height<=0 or not is_finite(maximum_distance) or maximum_distance<=0 or maximum_distance>1.0:return {"accepted":false,"reason":"invalid_restore_geometry"}
	var original:=scene.seat_setup()
	var started:=Time.get_ticks_usec()
	var solids:Array=other_solids.duplicate()
	DesktopObjectsHost._append_scene_solids(scene,solids)
	var margin:=maximum_distance+maxf(.15,radius*2)
	var area:=Rect2(Vector2(start.x,start.z)-Vector2.ONE*margin,Vector2.ONE*margin*2)
	var navigation:=DesktopSceneNavigation.new()
	var ready:=navigation.configure(area,start.y,solids,radius,height,.02)
	if not ready.get("ok",false):navigation.dispose();return {"accepted":false,"reason":"restore_navigation_"+str(ready.get("reason","invalid"))}
	var away:=start-scene.socket_world("seat")
	var preferred:=atan2(away.x,away.z)
	var attempts:=0
	var reason:="no_safe_restore_clearance"
	var step:=minf(.05,maximum_distance)
	for ring in int(ceil(maximum_distance/step))+1:
		var distance:=minf(float(ring)*step,maximum_distance)
		var count:=1 if ring==0 else 16
		for direction in count:
			attempts+=1
			# Alternate clockwise/counterclockwise from directly away from chair.
			var index:=int(ceil(float(direction)/2))*(1 if direction%2 else -1)
			var angle:=preferred+float(index)*TAU/16
			var target:=start+Vector3(sin(angle),0,cos(angle))*distance
			if ground_fit.is_valid() and not bool(ground_fit.call(target)):reason="restore_actor_view_blocked";continue
			var route:=navigation.plan("restore-clearance",start,target)
			if not route.get("accepted",false):reason="restore_"+str(route.get("reason","unreachable"));continue
			var path:PackedVector3Array=route.path
			var route_fits:=true
			for at in path.size():
				var previous:Vector3=start if at==0 else path[at-1]
				var samples:=maxi(1,int(ceil(previous.distance_to(path[at])/.025)))
				for sample in samples+1:
					if ground_fit.is_valid() and not bool(ground_fit.call(previous.lerp(path[at],float(sample)/samples))):route_fits=false;break
				if not route_fits:break
			if not route_fits:reason="restore_route_view_blocked";continue
			var swivel:=validate_setup_sweep(scene,original.pullout_local_m,0,target,radius,height,other_solids,fit)
			if not swivel.get("accepted",false):reason=str(swivel.reason);continue
			scene.set_seat_setup(original.pullout_local_m,0)
			var roll:=validate_setup_sweep(scene,0,0,target,radius,height,other_solids,fit)
			scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
			if not roll.get("accepted",false):reason=str(roll.reason);continue
			navigation.dispose()
			return {"accepted":true,"reason":"ready","target_world":target,"path":path,"distance_m":route.distance_m,"offset_m":distance,"navigation_geometry":{"area":area,"cell_size":.02},"swivel":swivel,"roll":roll,"attempts":attempts,"planning_ms":(Time.get_ticks_usec()-started)/1000.0}
	navigation.dispose()
	scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
	return {"accepted":false,"reason":reason,"attempts":attempts,"planning_ms":(Time.get_ticks_usec()-started)/1000.0}
