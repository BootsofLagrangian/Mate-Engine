class_name VrmAvatar
extends Node3D
## Runtime VRM loading (godot-vrm addon, GLTFDocument path from the upstream
## load_at_runtime sample) plus normalized-bone mapping, world-aligned additive
## posing and expression (blend shape) control.
##
## Coordinate notes (verified with tools/probe_vrm.gd on the installed addon 2.0.1):
##  * VRM 0.x files are rotated 180deg by the addon and retargeted onto Godot's
##    SkeletonProfileHumanoid: the model faces +Z, its left arm is at +X, torso
##    bone rests are identity in skeleton space. Arm/eye rests are NOT identity,
##    so offsets are applied in each bone's world-aligned rest frame:
##        local_pose = rest * (G^-1 * R * G)   with G = global rest basis.
##  * Bank angles are Unity/VRM-authored (left-handed): Godot basis is built from
##    (x, -y, -z) in Y-X-Z order, which keeps "+x = nod forward", "+y = look right",
##    "+z = tilt left" identical to the Unity/web hosts.

signal model_changed(ok: bool, message: String)

const VRM_EXTENSION_PATH := "res://addons/vrm/vrm_extension.gd"
const IMPORT_GENERATE_TANGENT_ARRAYS := 8

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var bone_index: Dictionary = {} # normalized name -> bone idx
var bone_rest_global: Dictionary = {} # idx -> Basis
var bone_rest_local: Dictionary = {} # idx -> Quaternion
var expressions: Dictionary = {} # name -> Array[[MeshInstance3D, shape_idx, weight]]
var expression_weights: Dictionary = {}
var model_path: String = ""
var meta_title: String = ""
var spec_version: String = ""
var arm_ik := ArmIK.new()
var _posed_bones: Dictionary = {}
var _blend_targets: Dictionary = {} # "mesh_id:idx" -> [mesh, idx]


static func load_vrm(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		push_error("VRM missing: " + path)
		return null
	var gltf := GLTFDocument.new()
	var ext_script: GDScript = load(VRM_EXTENSION_PATH)
	if ext_script == null:
		push_error("VRM addon not installed at " + VRM_EXTENSION_PATH)
		return null
	var ext: GLTFDocumentExtension = ext_script.new()
	gltf.register_gltf_document_extension(ext, true)
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state, IMPORT_GENERATE_TANGENT_ARRAYS)
	if err != OK:
		gltf.unregister_gltf_document_extension(ext)
		push_error("VRM append_from_file failed: " + error_string(err))
		return null
	var scene := gltf.generate_scene(state)
	gltf.unregister_gltf_document_extension(ext)
	return scene


func clear_model() -> void:
	if model:
		model.queue_free()
	model = null
	skeleton = null
	anim_player = null
	bone_index.clear()
	bone_rest_global.clear()
	bone_rest_local.clear()
	expressions.clear()
	expression_weights.clear()
	_posed_bones.clear()
	_blend_targets.clear()
	model_path = ""


func load_from_file(path: String) -> bool:
	var scene := load_vrm(path)
	if scene == null:
		model_changed.emit(false, "load failed: " + path.get_file())
		return false
	set_model(scene)
	model_path = path
	model_changed.emit(true, meta_title if not meta_title.is_empty() else path.get_file())
	return true


func set_model(scene: Node3D) -> void:
	clear_model()
	model = scene
	add_child(model)
	skeleton = _find_skeleton(model)
	if skeleton:
		# The runtime retarget rewrites bone rests but leaves poses untouched; without this,
		# posing one bone re-evaluates its ancestors from identity instead of their rests.
		skeleton.reset_bone_poses()
	anim_player = model.get_node_or_null("AnimationPlayer")
	var meta: Resource = model.get("vrm_meta") if model.has_method("get") else null
	if meta:
		meta_title = str(meta.get("title")) if meta.get("title") != null else ""
		spec_version = str(meta.get("spec_version")) if meta.get("spec_version") != null else ""
	_resolve_bones(meta)
	_resolve_expressions()
	apply_pose({})


func has_model() -> bool:
	return model != null and skeleton != null


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null


func _resolve_bones(meta: Resource) -> void:
	if skeleton == null:
		return
	var bone_map: BoneMap = meta.get("humanoid_bone_mapping") if meta else null
	var lower_names := {}
	for i in skeleton.get_bone_count():
		lower_names[skeleton.get_bone_name(i).to_lower()] = i
	for normalized in MotionBank.ALLOWED_BONES:
		var profile_name := normalized[0].to_upper() + normalized.substr(1)
		var idx := skeleton.find_bone(profile_name)
		if idx < 0 and bone_map:
			# Rename can fail when the source rig already used a humanoid name; fall back to the mapped source bone.
			var src := bone_map.get_skeleton_bone_name(profile_name)
			if src != StringName():
				idx = skeleton.find_bone(src)
		if idx < 0 and lower_names.has(normalized.to_lower()):
			idx = lower_names[normalized.to_lower()]
		if idx >= 0:
			bone_index[normalized] = idx
			bone_rest_global[idx] = skeleton.get_bone_global_rest(idx).basis
			bone_rest_local[idx] = skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	# The VRM 0.x "chest" often lands on upperChest after conversion; alias so bank tracks still move something.
	if not bone_index.has("chest") and bone_index.has("upperChest"):
		bone_index["chest"] = bone_index["upperChest"]
	if not bone_index.has("upperChest") and bone_index.has("chest"):
		bone_index["upperChest"] = bone_index["chest"]


func _resolve_expressions() -> void:
	if anim_player == null:
		return
	var root: Node = anim_player.get_node_or_null(anim_player.root_node)
	if root == null:
		root = model
	for anim_name in anim_player.get_animation_list():
		if anim_name == "RESET":
			continue
		var anim := anim_player.get_animation(anim_name)
		var binds: Array = []
		for t in anim.get_track_count():
			if anim.track_get_type(t) != Animation.TYPE_BLEND_SHAPE:
				continue
			var path := anim.track_get_path(t)
			var node_path := NodePath(String(path).get_slice(":", 0))
			var mesh := root.get_node_or_null(node_path) as MeshInstance3D
			if mesh == null or mesh.mesh == null or path.get_subname_count() == 0:
				continue
			var shape_idx := mesh.find_blend_shape_by_name(path.get_subname(0))
			if shape_idx < 0:
				continue
			var key_count := anim.track_get_key_count(t)
			var weight := float(anim.track_get_key_value(t, key_count - 1)) if key_count > 0 else 1.0
			binds.append([mesh, shape_idx, weight])
			_blend_targets["%d:%d" % [mesh.get_instance_id(), shape_idx]] = [mesh, shape_idx]
		if not binds.is_empty():
			expressions[anim_name] = binds


func has_expression(name: String) -> bool:
	return expressions.has(name)


func expression_names() -> Array:
	return expressions.keys()


func set_expression(name: String, weight: float) -> void:
	if not expressions.has(name):
		return
	weight = clampf(weight, 0.0, 1.0)
	if is_zero_approx(weight):
		expression_weights.erase(name)
	else:
		expression_weights[name] = weight


func clear_expressions() -> void:
	expression_weights.clear()


## Push accumulated expression weights into the meshes (call once per frame).
func apply_expressions() -> void:
	var sums := {}
	for name in expression_weights.keys():
		var w: float = expression_weights[name]
		for bind in expressions[name]:
			var key := "%d:%d" % [bind[0].get_instance_id(), bind[1]]
			sums[key] = clampf(sums.get(key, 0.0) + w * bind[2], 0.0, 1.0)
	for key in _blend_targets.keys():
		var target: Array = _blend_targets[key]
		var mesh: MeshInstance3D = target[0]
		if is_instance_valid(mesh):
			mesh.set_blend_shape_value(target[1], sums.get(key, 0.0))


## Convert canonical bank degrees (Unity semantics) into a Godot world-aligned basis.
static func canonical_to_basis(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(-deg.y), deg_to_rad(-deg.z)), EULER_ORDER_YXZ)


## Apply additive offsets {normalized bone: Vector3 degrees}. Bones absent this frame return to rest.
func apply_pose(offsets: Dictionary) -> void:
	if skeleton == null:
		return
	# Always establish a relaxed base; the imported humanoid rest is a T-pose.
	# Clear last-frame IK before applying hierarchical offsets.
	for idx in bone_rest_local.keys():
		skeleton.set_bone_pose_rotation(idx, bone_rest_local[idx])
	var pose := offsets.duplicate()
	for side in ["left", "right"]:
		var sign_side := 1.0 if side == "left" else -1.0
		pose[side + "UpperArm"] = pose.get(side + "UpperArm", Vector3.ZERO) + Vector3(0, 0, 72.0 * sign_side)
		pose[side + "LowerArm"] = pose.get(side + "LowerArm", Vector3.ZERO) + Vector3(0, -12.0 * sign_side, 0)
	var touched := {}
	for bone in pose.keys():
		if not bone_index.has(bone):
			continue
		var idx: int = bone_index[bone]
		var deg: Vector3 = pose[bone]
		if deg.is_zero_approx():
			continue
		var g: Basis = bone_rest_global[idx]
		var r := canonical_to_basis(deg)
		var local_delta := g.inverse() * r * g
		var rest: Quaternion = bone_rest_local[idx]
		skeleton.set_bone_pose_rotation(idx, (rest * local_delta.get_rotation_quaternion()).normalized())
		touched[idx] = true
	for idx in _posed_bones.keys():
		if not touched.has(idx):
			skeleton.set_bone_pose_rotation(idx, bone_rest_local[idx])
	_posed_bones = touched


func reset_pose() -> void:
	apply_pose({})


## Skeleton-space bounding box of all visible meshes (for framing and the pet hit region).
func compute_aabb() -> AABB:
	var meshes: Array = []
	_collect_meshes(model, meshes)
	var box := AABB()
	var first := true
	for m in meshes:
		var mi: MeshInstance3D = m
		var local := mi.get_aabb()
		var xf: Transform3D = global_transform.affine_inverse() * mi.global_transform
		var b := xf * local
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		return AABB(Vector3(-0.4, 0.0, -0.3), Vector3(0.8, 1.6, 0.6))
	return box


func _collect_meshes(n: Node, out: Array) -> void:
	if n == null:
		return
	if n is MeshInstance3D and n.visible:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func bone_global_position(normalized: String) -> Vector3:
	if skeleton == null or not bone_index.has(normalized):
		return global_position + Vector3(0, 1.3, 0)
	var idx: int = bone_index[normalized]
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin


## Goals are relative to each shoulder, measured in total arm lengths.
## +X is avatar left, +Y up, +Z forward, rotated with the posed chest.
func apply_hand_goals(goals: Dictionary) -> void:
	if skeleton == null:
		return
	for side in goals:
		if not bone_index.has(side + "UpperArm") or not bone_index.has(side + "Hand"):
			continue
		var upper: int = bone_index[side + "UpperArm"]
		var lower: int = bone_index[side + "LowerArm"]
		var hand: int = bone_index[side + "Hand"]
		var origin := skeleton.get_bone_global_pose(upper).origin
		var length := skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(lower).origin) + skeleton.get_bone_global_rest(lower).origin.distance_to(skeleton.get_bone_global_rest(hand).origin)
		var side_sign := 1.0 if side == "left" else -1.0
		var goal: Vector3 = goals[side]
		# Keep procedural requests in a shoulder workspace: limited cross-body
		# reach, no deep backwards extension, and at most 160 degrees elevation.
		goal.x = clampf(goal.x * side_sign, -0.35, 1.0) * side_sign
		goal.z = maxf(goal.z, -0.15)
		if goal.y > 0.0:
			var horizontal := Vector2(goal.x, goal.z)
			var minimum := goal.y * tan(deg_to_rad(20.0))
			if horizontal.length() < minimum:
				horizontal = (horizontal.normalized() if horizontal.length() > 0.00001 else Vector2(side_sign,0)) * minimum
				goal.x = horizontal.x
				goal.z = horizontal.y
		var torso := Basis.IDENTITY
		if bone_index.has("chest"):
			var chest: int = bone_index["chest"]
			torso = skeleton.get_bone_global_pose(chest).basis.orthonormalized() * skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse()
		arm_ik.solve(self, side, origin + torso * goal * length, origin + torso * Vector3(side_sign * 0.8, -0.4, -0.5) * length)
		for idx in [upper, lower, hand]:
			_posed_bones[idx] = true


## Blend normalized VRMA rest-frame deltas over the current procedural pose.
func apply_normalized_rotations(rotations: Dictionary, weight: float) -> void:
	if skeleton == null:
		return
	for bone in rotations:
		if not bone_index.has(bone):
			continue
		var idx: int = bone_index[bone]
		var g: Basis = bone_rest_global[idx]
		var delta := (g.inverse() * Basis(rotations[bone]) * g).get_rotation_quaternion()
		var wanted: Quaternion = (bone_rest_local[idx] * delta).normalized()
		skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx).slerp(wanted,clampf(weight,0,1)))
		_posed_bones[idx] = true


func add_wrist_rotation(side: String, degrees: Vector3) -> void:
	if skeleton == null or not bone_index.has(side + "Hand"):
		return
	var idx: int = bone_index[side + "Hand"]
	var g: Basis = bone_rest_global[idx]
	var delta := (g.inverse() * canonical_to_basis(degrees) * g).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(idx, (skeleton.get_bone_pose_rotation(idx) * delta).normalized())
	_posed_bones[idx] = true


## Global-space points for host camera projection. Stable foot/seat anchors are
## rooted in the rest skeleton so the OS window never chases a swing foot.
## All points naturally follow avatar.scale and facing yaw.
func contact_anchors() -> Dictionary:
	if not has_model() or not bone_index.has("hips"):
		return {}
	var hips: int = bone_index["hips"]
	var hip_rest := skeleton.get_bone_global_rest(hips).origin
	var head_rest := skeleton.get_bone_global_rest(bone_index.get("head", hips)).origin
	var height := maxf(0.5,head_rest.y)
	var rest_feet: Array[Vector3] = []
	var live_feet: Array[Vector3] = []
	for side in ["left","right"]:
		if not bone_index.has(side+"Foot"):
			continue
		var idx: int = bone_index[side+"Foot"]
		var rest := skeleton.get_bone_global_rest(idx).origin
		var posed := skeleton.get_bone_global_pose(idx).origin
		var sole_y := rest.y - height*0.04
		if bone_index.has(side+"Toes"):
			sole_y = minf(rest.y,skeleton.get_bone_global_rest(bone_index[side+"Toes"]).origin.y) - height*0.012
		rest_feet.append(Vector3(rest.x,sole_y,rest.z))
		live_feet.append(posed-Vector3(0,rest.y-sole_y,0))
	var floor_y := 0.0
	var live := Vector3.ZERO
	if rest_feet.size() == 2:
		floor_y = minf(rest_feet[0].y,rest_feet[1].y)
		live = (live_feet[0]+live_feet[1])*0.5
		live.y = minf(live_feet[0].y,live_feet[1].y)
	var xf := skeleton.global_transform
	return {"foot": xf*Vector3(hip_rest.x,floor_y,hip_rest.z),
		"foot_current": xf*live,
		"sit": xf*(hip_rest-Vector3(0,height*0.06,0)),
		"hips_current": bone_global_position("hips"),
		"lean": bone_global_position("rightHand"),
		"left_hand": bone_global_position("leftHand"),
		"right_hand": bone_global_position("rightHand")}


## Solve a hand to an explicit world surface point, preserving the elbow pole.
## Returns false for unreachable contacts instead of promising hand attachment.
func apply_hand_contact(side: String, world_target: Vector3) -> bool:
	if not has_model() or not bone_index.has(side+"Hand") or not world_target.is_finite():
		return false
	var origin := skeleton.get_bone_global_pose(bone_index[side+"UpperArm"]).origin
	var target := skeleton.global_transform.affine_inverse()*world_target
	var torso := Basis.IDENTITY
	if bone_index.has("chest"):
		var chest: int = bone_index["chest"]
		torso = skeleton.get_bone_global_pose(chest).basis.orthonormalized()*skeleton.get_bone_global_rest(chest).basis.orthonormalized().inverse()
	var side_sign := 1.0 if side == "left" else -1.0
	arm_ik.solve(self,side,target,origin+torso*Vector3(side_sign*0.3,-0.2,-0.2))
	# Turn fingers down the surface instead of extending through it. The
	# shoulder/elbow solve controls reach; this independently controls the palm.
	var hand: int = bone_index[side+"Hand"]
	var finger_axis := Vector3(side_sign,0,0)
	if bone_index.has(side+"MiddleProximal"):
		finger_axis = (skeleton.get_bone_global_rest(bone_index[side+"MiddleProximal"]).origin-skeleton.get_bone_global_rest(hand).origin).normalized()
	var wanted_basis := Basis(Quaternion(finger_axis,Vector3.DOWN))*skeleton.get_bone_global_rest(hand).basis.orthonormalized()
	var parent := skeleton.get_bone_parent(hand)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var wrist_target := (parent_basis.inverse()*wanted_basis).get_rotation_quaternion().normalized()
	var wrist_rest: Quaternion = bone_rest_local[hand]
	var bend := wrist_rest.angle_to(wrist_target)
	if bend > deg_to_rad(75.0):
		wrist_target = wrist_rest.slerp(wrist_target,deg_to_rad(75.0)/bend)
	skeleton.set_bone_pose_rotation(hand,wrist_target)
	var diagnostic: Dictionary = arm_ik.diagnostics.get(side,{})
	return not diagnostic.is_empty() and float(diagnostic.clamped) < 0.015
