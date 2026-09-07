class_name SeatedFloorConstraint
extends RefCounted
## Explicit seating floor, in unscaled skeleton metres. Uses the imported
## Verlet collision interface; no replacement spring integrator or bone scaling.
class FloorCollider extends VRMCollider.VrmRuntimeCollider:
	var owner_constraint: SeatedFloorConstraint
	var center_index := 0
	var spring_state: Variant
	func collision(origin: Vector3, bone_radius: float, bone_length: float, tail_point: Vector3, _offset: Vector3 = Vector3.ZERO) -> Vector3:
		if owner_constraint == null or not owner_constraint.active: return tail_point
		var secondary: Node = owner_constraint.secondary
		if center_index>=secondary.center_transforms.size(): return tail_point
		var xf: Transform3D = secondary.center_transforms[center_index]
		var padding_value := maxf(bone_radius,owner_constraint.padding)
		for joint in spring_state.verlets:
			if absf(joint.length-bone_length)<0.00001 and owner_constraint._terminal_lengths.has(joint.bone_idx):
				padding_value=maxf(padding_value,float(owner_constraint._terminal_lengths[joint.bone_idx].radius))
		# Verlet's center may carry avatar scale. Solve the plane in unscaled
		# skeleton metres, then return to that center; no double-scaled radius.
		var inverse:=xf.affine_inverse()
		var corrected:=SeatedFloorConstraint.project(inverse*origin,inverse*tail_point,bone_length,Vector3.UP,Vector3(0,owner_constraint.floor_y,0),padding_value)
		return xf*corrected


var avatar: VrmAvatar
var secondary: Node
var clearance := INF
var floor_y := -INF
var active := false
var padding := 0.035
var _colliders: Array = []
var leg_ik := LegIK.new()
var _terminal_joints: Array = []
var _extended_joints: Array = []
var _terminal_lengths: Dictionary = {}

static func project(origin: Vector3, tail_point: Vector3, length: float, normal: Vector3, point: Vector3, padding_value: float) -> Vector3:
	if normal.dot(tail_point-point)>=padding_value: return tail_point
	var vertical := clampf(padding_value-normal.dot(origin-point),-length,length)
	var direction := tail_point-origin
	var tangent := direction-normal*normal.dot(direction)
	if tangent.length_squared()<0.000001:
		tangent=Vector3.BACK-normal*normal.dot(Vector3.BACK)
		if tangent.length_squared()<0.000001: tangent=Vector3.RIGHT
	return origin+normal*vertical+tangent.normalized()*sqrt(maxf(0,length*length-vertical*vertical))

func configure(target: VrmAvatar, seat_clearance: float) -> void:
	avatar=target
	clearance=seat_clearance
	secondary=_find_secondary(avatar.model)
	_prepare_terminal_lengths()

func _find_secondary(node: Node) -> Node:
	var script: Script=node.get_script()
	if script and script.resource_path.ends_with("/vrm_secondary.gd"): return node
	for child in node.get_children(true):
		var found:=_find_secondary(child)
		if found: return found
	return null

func _prepare_terminal_lengths() -> void:
	if secondary==null: return
	var sk:=avatar.skeleton
	for state in secondary.spring_bones_internal:
		if state.joint_nodes.is_empty(): continue
		var idx:=sk.find_bone(state.joint_nodes[-2] if state.joint_nodes[-1].is_empty() and state.joint_nodes.size()>1 else state.joint_nodes[-1])
		if idx<0 or avatar.bone_rest_local.has(idx): continue
		var parent:=sk.get_bone_parent(idx)
		if parent<0: continue
		var rest:=sk.get_bone_global_rest(idx)
		var axis:Vector3=rest.basis.inverse()*(rest.origin-sk.get_bone_global_rest(parent).origin)
		_terminal_lengths[idx]={"axis":axis.normalized(),"length":0.07,"radius":0.035}
	var meshes:=[]
	avatar._collect_meshes(avatar.model,meshes)
	for mesh in meshes:
		if mesh.skin==null: continue
		var ids:=[]
		for bind in mesh.skin.get_bind_count():
			var idx:int=mesh.skin.get_bind_bone(bind)
			if not mesh.skin.get_bind_name(bind).is_empty(): idx=sk.find_bone(mesh.skin.get_bind_name(bind))
			ids.append(idx)
		for surface in mesh.mesh.get_surface_count():
			var arrays:Array=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var joints:Variant=arrays[Mesh.ARRAY_BONES]
			var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
			if joints==null or vertices.is_empty(): continue
			var count:int=joints.size()/vertices.size()
			for i in vertices.size():
				for slot in count:
					var bind:int=joints[i*count+slot]
					var idx:int=ids[bind]
					if weights[i*count+slot]<0.5 or not _terminal_lengths.has(idx): continue
					var point:Vector3=mesh.skin.get_bind_pose(bind)*vertices[i]
					_terminal_lengths[idx].length=maxf(_terminal_lengths[idx].length,minf(0.35,point.dot(_terminal_lengths[idx].axis)))
					var axis:Vector3=_terminal_lengths[idx].axis
					_terminal_lengths[idx].radius=maxf(_terminal_lengths[idx].radius,(point-axis*point.dot(axis)).length())

func _state_reaches_floor(state: Variant) -> bool:
	if state.verlets.is_empty() or not is_finite(floor_y): return false
	var reach:=0.0
	var margin:=padding
	for joint in state.verlets:
		var info:Dictionary=_terminal_lengths.get(joint.bone_idx,{})
		reach+=maxf(joint.length,float(info.get("length",joint.length)))
		margin=maxf(margin,float(info.get("radius",joint.radius)))
	var origin:=avatar.skeleton.get_bone_global_pose(state.verlets[0].bone_idx).origin
	return origin.y-reach-margin<=floor_y

func _ensure_terminal_joints() -> void:
	if secondary==null: return
	for i in secondary.spring_bones_internal.size():
		var state:Variant=secondary.spring_bones_internal[i]
		if not _state_reaches_floor(state): continue
		if state.joint_nodes.is_empty(): continue
		var idx:=avatar.skeleton.find_bone(state.joint_nodes[-2] if state.joint_nodes[-1].is_empty() and state.joint_nodes.size()>1 else state.joint_nodes[-1])
		if not _terminal_lengths.has(idx): continue
		var exists:=false
		var info:Dictionary=_terminal_lengths[idx]
		for joint in state.verlets:
			if joint.bone_idx!=idx: continue
			exists=true
			if info.length>joint.length+0.001:
				_extended_joints.append([state,joint,joint.length])
				var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[i]]
				var origin:Vector3=xf*avatar.skeleton.get_bone_global_pose(idx).origin
				joint.current_tail=origin+(joint.current_tail-origin).normalized()*info.length
				joint.prev_tail=joint.current_tail
				joint.length=info.length
		if exists: continue
		var logic:=preload("res://addons/vrm/vrm_spring_bone_logic.gd").new(avatar.skeleton,idx,secondary.center_transforms_inv[secondary.springs_centers[i]],info.axis*info.length,avatar.skeleton.get_bone_global_pose(idx))
		state.verlets.append(logic)
		_terminal_joints.append([state,logic])

func set_active(value: bool) -> void:
	active=value and is_finite(clearance)
	if not active:
		_remove_colliders()
		return
	if secondary==null: secondary=_find_secondary(avatar.model)
	if secondary==null: return
	_ensure_terminal_joints()
	for i in secondary.spring_bones_internal.size():
		var state: Variant=secondary.spring_bones_internal[i]
		if not _state_reaches_floor(state): continue
		var found:=false
		for collider in state.colliders:
			if collider is FloorCollider and collider.owner_constraint==self: found=true
		if found: continue
		var collider:=FloorCollider.new(VRMCollider.new(),-1,null)
		collider.owner_constraint=self
		collider.center_index=secondary.springs_centers[i]
		collider.spring_state=state
		state.colliders.append(collider)
		_colliders.append(collider)

func _remove_colliders() -> void:
	if is_instance_valid(secondary):
		for state in secondary.spring_bones_internal:
			for collider in _colliders: state.colliders.erase(collider)
	for collider in _colliders: collider.owner_constraint=null
	_colliders.clear()
	for pair in _terminal_joints: pair[0].verlets.erase(pair[1])
	_terminal_joints.clear()
	for entry in _extended_joints:
		var joint:Variant=entry[1]
		var i:int=secondary.spring_bones_internal.find(entry[0]) if is_instance_valid(secondary) else -1
		if i>=0 and is_instance_valid(avatar):
			var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[i]]
			var origin:Vector3=xf*avatar.skeleton.get_bone_global_pose(joint.bone_idx).origin
			var velocity:Vector3=(joint.current_tail-joint.prev_tail)*(float(entry[2])/maxf(joint.length,0.001))
			joint.current_tail=origin+(joint.current_tail-origin).normalized()*float(entry[2])
			joint.prev_tail=joint.current_tail-velocity
		joint.length=entry[2]
	_extended_joints.clear()

func clear() -> void:
	set_active(false)
	_terminal_lengths.clear()
	clearance=INF
	floor_y=-INF
	secondary=null
	avatar=null

func solve_legs(weight: float = 1.0, penetration_only: bool = false) -> void:
	if avatar==null or not is_finite(floor_y): return
	var sk:=avatar.skeleton
	for side in ["left","right"]:
		if not avatar.bone_index.has(side+"Foot") or not avatar.bone_index.has(side+"LowerLeg") or not avatar.bone_index.has(side+"UpperLeg"): continue
		var ankle:int=avatar.bone_index[side+"Foot"]
		var knee:int=avatar.bone_index[side+"LowerLeg"]
		var foot:=sk.get_bone_global_pose(ankle)
		var rest:=sk.get_bone_global_rest(ankle)
		var sole_offset:=rest.origin.y-float(avatar.sole_calibration.get("floor_y",0.0))
		var target:=foot.origin
		var lift:=maxf(0,floor_y+sole_offset-target.y)
		if penetration_only and lift <= 0.00001: continue
		var shin:=sk.get_bone_global_rest(knee).origin.distance_to(rest.origin)
		target.y=floor_y+sole_offset
		# Relax shins forward for low seats while keeping the pelvis attached.
		target.z+=minf(0.22,sqrt(maxf(0,2*shin*lift)))
		leg_ik.solve(avatar,side,target,weight,rest.basis.orthonormalized(),true)

## Same plane projection for the temporary canonical measurement. No Verlet
## history mutation: runtime uses FloorCollider inside the existing integrator.
func snapshot_springs() -> Dictionary:
	var records:=[]
	if secondary!=null:
		for state in secondary.spring_bones_internal:
			var joints:=[]
			for joint in state.verlets: joints.append([joint,joint.length,joint.current_tail,joint.prev_tail])
			records.append([state,joints])
	return {"records":records,"added":_terminal_joints.duplicate(),"extended":_extended_joints.duplicate()}

func restore_springs(snapshot: Dictionary) -> void:
	for record in snapshot.records:
		var state:Variant=record[0]
		state.verlets.clear()
		for entry in record[1]:
			entry[0].length=entry[1]
			entry[0].current_tail=entry[2]
			entry[0].prev_tail=entry[3]
			state.verlets.append(entry[0])
	_terminal_joints=snapshot.added
	_extended_joints=snapshot.extended

func solve_secondary_pose() -> void:
	if secondary==null or not is_finite(floor_y): return
	_ensure_terminal_joints()
	var sk:=avatar.skeleton
	for state in secondary.spring_bones_internal:
		if not _state_reaches_floor(state): continue
		for joint in state.verlets:
			if avatar.bone_rest_local.has(joint.bone_idx): continue
			var pose:=sk.get_bone_global_pose(joint.bone_idx)
			var axis:Vector3=pose.basis*joint.bone_axis
			var length:float=joint.length
			var endpoint:=pose.origin+axis.normalized()*length
			var radius:=maxf(padding,float(_terminal_lengths.get(joint.bone_idx,{}).get("radius",joint.radius)))
			var wanted:=project(pose.origin,endpoint,length,Vector3.UP,Vector3(0,floor_y,0),radius)
			if wanted.distance_squared_to(endpoint)<0.00000001: continue
			var rotation:=Quaternion(axis.normalized(),(wanted-pose.origin).normalized())
			pose.basis=Basis(rotation)*pose.basis
			sk.set_bone_global_pose(joint.bone_idx,pose)
