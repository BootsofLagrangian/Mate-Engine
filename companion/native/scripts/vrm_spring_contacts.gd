extends RefCounted
## Extra hand/forearm collision proxies for authored VRM secondary bones.
## This does not collide humanoid skin, simulate cloth triangles, or add springs.
## Imported springs retain their authored stiffness, gravity and drag.

class HandSphere extends VRMCollider.VrmRuntimeCollider:
	var host: WeakRef
	var center_index := 0
	var from_bone := -1
	var to_bone := -1
	var blend := 0.0
	var radius_m := 0.035
	var contacts := 0
	var shape_limited := 0
	func collision(origin: Vector3, bone_radius: float, bone_length: float, tail: Vector3, _offset: Vector3 = Vector3.ZERO) -> Vector3:
		var owner = host.get_ref() if host != null else null
		if owner == null or not is_instance_valid(owner.secondary) or not is_instance_valid(owner.avatar): return tail
		var sk: Skeleton3D = owner.avatar.skeleton
		var xf: Transform3D = owner.secondary.center_transforms[center_index]
		var point := sk.get_bone_global_pose(from_bone).origin.lerp(sk.get_bone_global_pose(to_bone).origin, blend)
		var sphere := xf * point
		var scale3 := xf.basis.get_scale().abs()
		var r := radius_m * maxf(scale3.x, maxf(scale3.y, scale3.z)) + bone_radius
		if tail.distance_squared_to(sphere) >= r * r: return tail
		contacts += 1
		var corrected: Vector3 = owner.project_sphere(origin, tail, bone_length, sphere, r)
		var incoming := (tail - origin).normalized()
		var wanted := (corrected - origin).normalized()
		var angle := incoming.angle_to(wanted)
		# A sparse proxy is not a garment shell: deep correction can turn a skirt
		# panel inside out. Yield progressively instead of forcing a large impulse.
		# Existing authored spring stiffness/drag retains the costume's shape.
		var response := 1.0 - smoothstep(deg_to_rad(2.0), deg_to_rad(10.0), angle)
		if response < 1.0: shape_limited += 1
		if response <= 0.0: return tail
		return origin + incoming.slerp(wanted, response).normalized() * bone_length

var avatar: VrmAvatar
var secondary: Node
var entries: Array = []
var diagnostics := {}

static func project_sphere(origin: Vector3, tail: Vector3, length: float, center: Vector3, radius: float) -> Vector3:
	# Project onto the intersection of the fixed-length sphere and collider exterior.
	# A plain radial push followed by length normalization can re-enter the collider.
	var axis := center - origin
	var distance := axis.length()
	if distance < 0.000001 or length < 0.000001: return tail
	axis /= distance
	var limit := (length * length + distance * distance - radius * radius) / (2.0 * length * distance)
	if limit >= 1.0: return tail
	if limit <= -1.0: return origin - axis * length # impossible overlap; furthest reachable endpoint
	var direction := (tail - origin).normalized()
	var tangent := direction - axis * direction.dot(axis)
	if tangent.length_squared() < 0.00000001:
		tangent = axis.cross(Vector3.UP)
		if tangent.length_squared() < 0.00000001: tangent = axis.cross(Vector3.RIGHT)
	return origin + length * (axis * limit + tangent.normalized() * sqrt(maxf(0.0, 1.0 - limit * limit)))

func configure(target: VrmAvatar, enable_extra_contacts: bool = false) -> Dictionary:
	clear()
	avatar = target
	secondary = find_secondary(target.model)
	diagnostics = {"supported": secondary != null, "extra_contacts_enabled": enable_extra_contacts, "states": 0, "proxies": 0, "scope": "shape_preserving_shallow_secondary_contacts", "deep_overlap_policy": "yield_to_authored_shape", "response_full_deg": 2.0, "response_zero_deg": 10.0}
	if secondary == null or not enable_extra_contacts: return diagnostics
	for i in secondary.spring_bones_internal.size():
		var state: Variant = secondary.spring_bones_internal[i]
		if state.verlets.is_empty(): continue
		# Never make a humanoid animation bone dynamic through collision correction.
		var humanoid := false
		for joint in state.verlets:
			if avatar.bone_rest_local.has(joint.bone_idx): humanoid = true
		if humanoid: continue
		var root_bone: int = state.verlets[0].bone_idx
		for side in ["left", "right"]:
			var hand: int = avatar.bone_index.get(side + "Hand", -1)
			var arm: int = avatar.bone_index.get(side + "LowerArm", -1)
			var upper: int = avatar.bone_index.get(side + "UpperArm", -1)
			if hand < 0 or arm < 0 or upper < 0: continue
			if is_descendant(avatar.skeleton, root_bone, upper): continue # sleeve must not hit its own arm
			var length := avatar.skeleton.get_bone_global_rest(hand).origin.distance_to(avatar.skeleton.get_bone_global_rest(arm).origin)
			for fraction in [0.45, 0.75, 1.0]:
				var collider := HandSphere.new(VRMCollider.new(), -1, null)
				collider.host = weakref(self)
				collider.center_index = secondary.springs_centers[i]
				collider.from_bone = arm
				collider.to_bone = hand
				collider.blend = fraction
				collider.radius_m = clampf(length * (0.18 if fraction < 1.0 else 0.20), 0.018, 0.05)
				state.colliders.append(collider)
				entries.append([state, collider])
		diagnostics.states += 1
	diagnostics.proxies = entries.size()
	return diagnostics

static func is_descendant(sk: Skeleton3D, bone: int, ancestor: int) -> bool:
	while bone >= 0:
		if bone == ancestor: return true
		bone = sk.get_bone_parent(bone)
	return false

static func find_secondary(node: Node) -> Node:
	if node == null: return null
	var script: Script = node.get_script()
	if script and script.resource_path.ends_with("/vrm_secondary.gd"): return node
	for child in node.get_children(true):
		var found := find_secondary(child)
		if found: return found
	return null

func clear() -> void:
	for entry in entries:
		entry[0].colliders.erase(entry[1])
		entry[1].host = null
	entries.clear()
	secondary = null
	avatar = null
