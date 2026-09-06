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
		var chair_sockets: Variant = chair_definition.get("sockets", {})
		if not chair_sockets is Dictionary or not _valid_xyz(chair_sockets.get("seat")):
			return _fail("Computer contact chair has no valid seat")
		_sockets["seat"] = chair.transform * _xyz(chair_sockets["seat"])
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
	return _geometry_points.duplicate()
