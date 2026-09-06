class_name DesktopObjectContactScene
extends Node3D
## Owned furniture geometry for the avatar's existing World3D/camera.
## Host owns positioning, uniform scale, yaw, visibility and native-window lifecycle.
## This node never moves the avatar, creates a camera/light/window, or starts a pose.

const PACK := "res://assets/desktop_objects/premium/"
const DEFINITIONS := PACK + "objects.json"
const COMPUTER_CHAIR_POSITION := Vector3(0.0, 0.0, 0.60)
const COMPUTER_PRESENTATION_YAW_DEGREES := 35.0

var loaded := false
var error := ""
var object_type := ""
var recommended_yaw_degrees := 0.0
var _content: Node3D
var _sockets: Dictionary = {}
var _geometry_points := PackedVector3Array()
var _local_bounds := AABB()
var _facing_local := Vector3.FORWARD
var _seat_node: Node3D
var _seat_native_anchor := Vector3.ZERO
var _seat_rest_transform := Transform3D.IDENTITY
var _seat_rest_points := PackedVector3Array()
var _stationary_points := PackedVector3Array()
var _seat_rest_bounds := AABB()
var _stationary_bounds := AABB()
var _setup_capability: Dictionary = {}
var _seat_pullout := 0.0
var _seat_yaw_delta := 0.0
var _seat_scale := 1.0

func configure(type: String) -> bool:
	clear()
	object_type = type
	if type not in ["chair", "sofa", "computer"]:
		return _fail("Unsupported contact furniture type: " + type)
	if not FileAccess.file_exists(DEFINITIONS):
		return _fail("Premium furniture definitions are missing")
	var definitions: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFINITIONS))
	if not definitions is Dictionary or not definitions.get(type) is Dictionary:
		return _fail("Premium furniture definition is invalid: " + type)
	_content = Node3D.new()
	_content.name = "ContactFurnitureGeometry"
	add_child(_content)
	var definition: Dictionary = definitions[type]
	var primary := _load_asset(str(definition.get("asset", "")))
	if primary == null:
		return _fail("Cannot load premium furniture: " + type)
	primary.name = "Workstation" if type == "computer" else "SeatFurniture"
	_content.add_child(primary)
	if not _read_sockets(definition, Transform3D.IDENTITY):
		return _fail("Premium furniture sockets are invalid: " + type)
	# Seating props retain their authored +Z front. A computer user faces -Z,
	# toward the display, with a real chair behind the pelvis and under the body.
	_facing_local = Vector3.BACK
	if type == "computer":
		var chair_definition: Variant = definitions.get("chair")
		if not chair_definition is Dictionary:
			return _fail("Computer contact requires the premium chair definition")
		var chair := _load_asset(str(chair_definition.get("asset", "")))
		if chair == null:
			return _fail("Computer contact chair cannot be loaded")
		chair.name = "ComputerSeat"
		chair.transform = Transform3D(Basis(Vector3.UP, PI), COMPUTER_CHAIR_POSITION)
		_content.add_child(chair)
		_seat_node = chair
		_seat_rest_transform = chair.transform
		var chair_sockets: Variant = chair_definition.get("sockets", {})
		if not chair_sockets is Dictionary or not _valid_xyz(chair_sockets.get("seat")):
			return _fail("Computer contact chair has no valid seat")
		_sockets["seat"] = chair.transform * _xyz(chair_sockets["seat"])
		_seat_native_anchor = _xyz(chair_sockets["seat"])
		var capability: Variant = definition.get("seat_setup",{})
		if capability is Dictionary and capability.get("kind","") == "swivel_chair":
			_setup_capability = capability.duplicate(true)
		# Keep actual keyboard names in user-side left/right coordinates. Facing
		# -Z means a user's left hand is at negative local X, right at positive X.
		for required in ["use", "keyboard_left", "keyboard_right", "inspect"]:
			if not _sockets.has(required):
				return _fail("Computer contact socket is missing: " + required)
		_facing_local = Vector3.FORWARD
		recommended_yaw_degrees = COMPUTER_PRESENTATION_YAW_DEGREES
	elif not _sockets.has("seat"):
		return _fail("Seating furniture has no seat socket")
	_collect_geometry(_content, Transform3D.IDENTITY)
	if _geometry_points.is_empty():
		return _fail("Contact furniture contains no mesh geometry")
	_local_bounds = AABB(_geometry_points[0], Vector3.ZERO)
	for point in _geometry_points:
		_local_bounds = _local_bounds.expand(point)
	if is_instance_valid(_seat_node):
		_geometry_points.clear()
		_collect_geometry(primary,Transform3D.IDENTITY)
		_stationary_points = _geometry_points.duplicate()
		_stationary_bounds = _points_bounds(_stationary_points)
		_geometry_points.clear()
		_collect_geometry(_seat_node,Transform3D.IDENTITY)
		_seat_rest_points = _geometry_points.duplicate()
		_seat_rest_bounds = _points_bounds(_seat_rest_points)
		_geometry_points = _stationary_points.duplicate()
		_geometry_points.append_array(_seat_rest_points)
	loaded = true
	return true

func clear() -> void:
	if is_instance_valid(_content):
		remove_child(_content)
		_content.free()
	_content = null
	loaded = false
	error = ""
	object_type = ""
	recommended_yaw_degrees = 0.0
	_sockets.clear()
	_geometry_points.clear()
	_local_bounds = AABB()
	_facing_local = Vector3.FORWARD
	_seat_node = null
	_seat_native_anchor = Vector3.ZERO
	_seat_rest_transform = Transform3D.IDENTITY
	_seat_rest_points.clear()
	_stationary_points.clear()
	_seat_rest_bounds = AABB()
	_stationary_bounds = AABB()
	_setup_capability.clear()
	_seat_pullout = 0.0
	_seat_yaw_delta = 0.0
	_seat_scale = 1.0

func _fail(message: String) -> bool:
	clear()
	error = message
	return false

func _load_asset(filename: String) -> Node3D:
	if filename.is_empty() or filename.get_file() != filename or not filename.ends_with(".glb"):
		return null
	var path := PACK + filename
	# Exported GLBs are imported PackedScenes with remapped resource paths.
	# FileAccess tests only physical files; ResourceLoader follows the remap.
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return null
	var resource: Resource = load(path)
	if resource is PackedScene:
		var instance: Node = resource.instantiate()
		if instance is Node3D:
			return instance
		instance.free()
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	return document.generate_scene(state)

func _valid_xyz(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	return true

func _xyz(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _read_sockets(definition: Dictionary, socket_transform: Transform3D) -> bool:
	var sockets: Variant = definition.get("sockets", {})
	if not sockets is Dictionary:
		return false
	for key in sockets:
		if not _valid_xyz(sockets[key]):
			return false
		_sockets[str(key)] = socket_transform * _xyz(sockets[key])
	return not _sockets.is_empty()

func _collect_geometry(node: Node, parent_transform: Transform3D) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				_geometry_points.append(local_transform * vertex)
	for child in node.get_children():
		_collect_geometry(child, local_transform)

func has_socket(name: String) -> bool:
	return loaded and _sockets.has(name)

func socket_local(name: String) -> Vector3:
	return _sockets.get(name, Vector3.INF) if loaded else Vector3.INF

func socket_world(name: String) -> Vector3:
	return global_transform * Vector3(_sockets[name]) if has_socket(name) else Vector3.INF

func socket_catalogue(world_space: bool = true) -> Dictionary:
	var result := {}
	if not loaded:
		return result
	for name in _sockets:
		result[name] = socket_world(name) if world_space else socket_local(name)
	return result

func facing_direction_world() -> Vector3:
	return (global_basis * _facing_local).normalized()

func get_local_bounds() -> AABB:
	return _local_bounds

func get_world_bounds() -> AABB:
	# Conservative transformed AABB; actual points are available for exact camera
	# projection fitting. This inexpensive bound is safe after host yaw/scale.
	return global_transform * _local_bounds if loaded else AABB()

func geometry_points_local() -> PackedVector3Array:
	if supports_seat_setup():
		var result := _stationary_points.duplicate()
		var delta := _seat_node.transform*_seat_rest_transform.affine_inverse()
		for point in _seat_rest_points: result.append(delta*point)
		return result
	return _geometry_points.duplicate()

static func _points_bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty(): return AABB()
	var result := AABB(points[0],Vector3.ZERO)
	for point in points: result = result.expand(point)
	return result

func supports_seat_setup() -> bool:
	return loaded and is_instance_valid(_seat_node) and _setup_capability.get("kind","") == "swivel_chair"

func seat_setup() -> Dictionary:
	return {"pullout_local_m":_seat_pullout,"yaw_delta_deg":_seat_yaw_delta,"seat_scale":_seat_scale,"capability":_setup_capability.duplicate(true)}

## Relative adjustable-seat geometry; desk dimensions and the host's global
## furniture scale remain independent. The physical cushion moves with its mesh.
func set_seat_scale(value: float) -> bool:
	var limits: Variant = _setup_capability.get("adjustable_scale",{})
	if not supports_seat_setup() or not limits is Dictionary or limits.is_empty() or not is_finite(value): return false
	if value < float(limits.get("min",1.0)) or value > float(limits.get("max",1.0)): return false
	_seat_scale = value
	return set_seat_setup(_seat_pullout,_seat_yaw_delta)

## The chair mesh, support socket and facing all share this real transform.
## Workstation/keyboard geometry never follows chair setup or seated rolling.
func set_seat_setup(pullout_local_m: float, yaw_delta_deg: float) -> bool:
	if not supports_seat_setup() or not is_finite(pullout_local_m) or not is_finite(yaw_delta_deg): return false
	var maximum: float = _setup_capability.get("max_pullout_m",0.0)
	if pullout_local_m < 0.0 or pullout_local_m > maximum or absf(yaw_delta_deg) > 180.0: return false
	_seat_pullout = pullout_local_m
	_seat_yaw_delta = yaw_delta_deg
	_seat_node.transform = Transform3D(Basis(Vector3.UP,PI+deg_to_rad(yaw_delta_deg)).scaled(Vector3.ONE*_seat_scale),COMPUTER_CHAIR_POSITION+Vector3(0,0,pullout_local_m))
	_sockets["seat"] = _seat_node.transform*_seat_native_anchor
	_facing_local = (_seat_node.basis*Vector3.BACK).normalized()
	var delta := _seat_node.transform*_seat_rest_transform.affine_inverse()
	_local_bounds = _stationary_bounds.merge(delta*_seat_rest_bounds)
	return true

func seat_node() -> Node3D:
	return _seat_node if supports_seat_setup() else null
