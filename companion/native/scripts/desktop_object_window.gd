class_name DesktopObjectWindow
extends Window
## One non-focus-stealing native furniture viewport. All interactions are on our own window.
signal drag_started(id: String)
signal drag_finished(id: String, position: Vector2i)
var object_id := ""
var object_type := ""
var dragging := false
var editable := false
var loaded := false
var error := ""
var _grab := Vector2i.ZERO
var _scene: Node3D
var _camera: Camera3D
var _overlay: Control
var _label: Label
var _sockets: Dictionary = {}
var _seat_width := 0.0
var _geometry_points: Array[Vector3] = []
const PACK := "res://assets/desktop_objects/"
const PARTS := {
	"chairDesk":Vector3(-0.167475,0,0.15715), "loungeSofa":Vector3(-0.49,0,0.205),
	"desk":Vector3(-0.357238,0,0.18385), "computerScreen":Vector3(-0.196344,0,0.052002),
	"computerKeyboard":Vector3(-0.1411,0,0.059096)}

func _init() -> void:
	visible = false
	borderless = true
	always_on_top = true
	transparent = true
	transparent_bg = true
	unresizable = true
	unfocusable = true
	popup_window = false
	world_3d = World3D.new()
	msaa_3d = Viewport.MSAA_4X
	focus_exited.connect(_end_drag)
	close_requested.connect(_end_drag)

func configure(record: Dictionary, dimensions: Vector2i) -> bool:
	object_id = str(record.id)
	object_type = str(record.type)
	title = "Mate object " + object_id
	name = "DesktopObject_" + object_id
	size = dimensions
	position = Vector2i(int(record.x),int(record.y))
	_scene = Node3D.new()
	add_child(_scene)
	var definitions_path := PACK+"premium/objects.json"
	var definition: Dictionary = {}
	if FileAccess.file_exists(definitions_path):
		var definitions = JSON.parse_string(FileAccess.get_file_as_string(definitions_path))
		if definitions is Dictionary: definition = definitions.get(object_type,{})
	if not definition.is_empty():
		loaded = _mesh(PACK+"premium/"+str(definition.asset),Vector3.ZERO)
		for socket in definition.get("sockets",{}):
			var xyz: Array = definition.sockets[socket]
			if xyz.size() == 3: _sockets[socket] = Vector3(float(xyz[0]),float(xyz[1]),float(xyz[2]))
		_seat_width = float(definition.get("seat_width",0.0))
	else:
		_load_legacy()
	_collect_geometry()
	_camera = Camera3D.new()
	_scene.add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 0.8
	_scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	_scene.add_child(environment)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(_input_object)
	add_child(_overlay)
	_label = Label.new()
	_label.text = str(record.label)+" · 끌어서 배치"
	_label.position = Vector2(8,6)
	_label.add_theme_color_override("font_color",Color.WHITE)
	_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x",1)
	_label.add_theme_constant_override("shadow_offset_y",1)
	_overlay.add_child(_label)
	_refit()
	set_editable(false)
	return loaded

func _load_legacy() -> void:
	match object_type:
		"chair":
			loaded = _part("chairDesk",Vector3.ZERO)
			_sockets = {"seat":Vector3(0,0.247394,-0.02285),"inspect":Vector3(0,0.4,0)}
			_seat_width = 0.27
		"sofa":
			loaded = _part("loungeSofa",Vector3.ZERO)
			_sockets = {"seat":Vector3(0,0.23,0.035),"inspect":Vector3(0,0.3,0)}
			_seat_width = 0.76
		"computer":
			loaded = _part("desk",Vector3.ZERO)
			loaded = _part("computerScreen",Vector3(0,0.384408,-0.075)) and loaded
			loaded = _part("computerKeyboard",Vector3(0,0.386,0.105)) and loaded
			_sockets = {"use":Vector3(0,0.413556,0.105),"inspect":Vector3(0,0.554408,-0.078)}
		_:
			error = "알 수 없는 물건입니다"
			loaded = false

func _part(id: String, offset: Vector3) -> bool:
	return _mesh(PACK+id+".glb",Vector3(PARTS[id])+offset)

func _mesh(path: String, offset: Vector3) -> bool:
	var packed = load(path)
	var node: Node3D
	if packed is PackedScene:
		node = packed.instantiate()
	else:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path,state) != OK:
			error = "물건 모델을 불러오지 못했습니다: "+path
			return false
		node = document.generate_scene(state)
	if node == null: return false
	node.position = offset
	_scene.add_child(node)
	return true

func _collect_geometry() -> void:
	_geometry_points.clear()
	for mesh in _scene.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]: _geometry_points.append(mesh.global_transform*vertex)

func pixels_per_metre() -> float:
	if _camera == null: return 0.0
	return _camera.unproject_position(Vector3.RIGHT).distance_to(_camera.unproject_position(Vector3.ZERO))

func seat_clearance() -> float:
	return socket_clearance("seat")

func socket_clearance(socket: String) -> float:
	return float(size.y)-(socket_point(socket).y-float(position.y)) if _sockets.has(socket) else 0.0

func _bounds() -> AABB:
	var result := AABB()
	var first := true
	for mesh in _scene.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var box: AABB = mesh.mesh.get_aabb()
		for i in 8:
			var point: Vector3 = mesh.global_transform*box.get_endpoint(i)
			if first: result = AABB(point,Vector3.ZERO); first = false
			else: result = result.expand(point)
	return result

func _refit() -> void:
	if _camera == null: return
	var box := _bounds()
	var center := box.get_center()
	_camera.position = center+Vector3(0.0,0.55,3.0)
	_camera.look_at(center,Vector3.UP)
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for i in 8:
		var local := _camera.to_local(box.get_endpoint(i))
		low = low.min(Vector2(local.x,local.y))
		high = high.max(Vector2(local.x,local.y))
	var ratio := float(size.x)/maxf(size.y,1)
	_camera.size = maxf(high.y-low.y,(high.x-low.x)/ratio)*1.14
	_camera.near = 0.01
	_camera.far = 20.0
	# Ground the actual mesh envelope rather than the transparent viewport margin.
	# Projection is affine, so one camera translation aligns every scale exactly.
	var bottom := -INF
	for point in _geometry_points: bottom = maxf(bottom,_camera.unproject_position(point).y)
	if is_finite(bottom):
		var ppm := absf(_camera.unproject_position(center+_camera.basis.y).y-_camera.unproject_position(center).y)
		if ppm > 0.001: _camera.position += _camera.basis.y*((float(size.y)-1.0-bottom)/ppm)

func apply_record(record: Dictionary, dimensions: Vector2i) -> void:
	if not dragging: position = Vector2i(int(record.x),int(record.y))
	if size != dimensions:
		size = dimensions
		_refit()
	if _label != null: _label.text = str(record.label)+" · 끌어서 배치"

func set_editable(value: bool) -> void:
	editable = value
	mouse_passthrough = not value
	if _label != null: _label.visible = value
	if _overlay != null: _overlay.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if not value: _end_drag()

func socket_point(name: String) -> Vector2:
	if _camera == null or not _sockets.has(name): return Vector2.INF
	return Vector2(position)+_camera.unproject_position(_sockets[name])

func socket_catalogue() -> Dictionary:
	var out := {}
	for name in _sockets: out[name] = socket_point(name)
	return out

func seat_surface() -> Dictionary:
	if not _sockets.has("seat") or _camera == null: return {}
	var seat: Vector3 = _sockets.seat
	var left := Vector2(position)+_camera.unproject_position(seat-Vector3(_seat_width*0.5,0,0))
	var right := Vector2(position)+_camera.unproject_position(seat+Vector3(_seat_width*0.5,0,0))
	return {"id":"object:"+object_id+":seat","x1":minf(left.x,right.x),"x2":maxf(left.x,right.x),"y":socket_point("seat").y}

func _input_object(event: InputEvent) -> void:
	if not editable: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			_grab = DisplayServer.mouse_get_position()-position
			drag_started.emit(object_id)
		else: _end_drag()
	elif event is InputEventMouseMotion and dragging:
		position = DisplayServer.mouse_get_position()-_grab

func _process(_delta: float) -> void:
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _end_drag()

func _end_drag() -> void:
	if not dragging: return
	dragging = false
	drag_finished.emit(object_id,position)
