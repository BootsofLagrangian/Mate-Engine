class_name DesktopObjectWindow
extends Window
## One non-focus-stealing native furniture viewport. All interactions are on our own window.
signal drag_started(id: String)
signal drag_finished(id: String, position: Vector2i)
const Store = preload("desktop_object_store.gd")
var _reference_ppm := 100.0
var _object_scale := 1.0
var _projection_zoom := 1.0
var _record: Dictionary = {}
var _native_alpha_id := -1
const Appearance = preload("desktop_object_appearance.gd")
const ContactScene = preload("desktop_object_contact_scene.gd")
var _computer_assembly: DesktopObjectContactScene
var _shared_world_active := false
var _private_environment: Environment
var _shared_camera: Camera3D
var _shared_desktop_origin := Vector2.ZERO
var _shared_transform := Transform3D.IDENTITY
var _shared_crop := Rect2()
var _shared_projection_key: Array = []
var _geometry_revision := 0
var projection_profile: Dictionary = {"fits":0,"cache_hits":0,"geometry_collections":0,"last_fit_us":0,"last_collect_us":0,"last_lookup_us":0,"last_request_at_us":0,"last_fit_at_us":0,"timestamp_msec":0,"last_call_us":0,"last_call_succeeded":false}
var _model_nodes: Array[Node3D] = []
var _base_sockets: Dictionary = {}
var _yaw := INF
var _appearance := ""
var _view_basis := Basis.IDENTITY
var _view_configured := false
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
	force_native = true
	minimize_disabled = true
	maximize_disabled = true
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
	visibility_changed.connect(_sync_shared_visibility)

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
	var all_definitions: Dictionary = {}
	if FileAccess.file_exists(definitions_path):
		var definitions = JSON.parse_string(FileAccess.get_file_as_string(definitions_path))
		if definitions is Dictionary:
			all_definitions = definitions
			definition = definitions.get(object_type,{})
	if not definition.is_empty():
		if object_type == "computer":
			_computer_assembly = ContactScene.new()
			_scene.add_child(_computer_assembly)
			loaded = _computer_assembly.configure("computer")
			if loaded: loaded = _computer_assembly.set_seat_scale(float(record.get("seat_scale",1.0)))
			error = _computer_assembly.error
			_computer_assembly.set_meta("object_rest_transform",Transform3D.IDENTITY)
			_model_nodes.append(_computer_assembly)
			_sockets = _computer_assembly.socket_catalogue(false)
			_seat_width = float(all_definitions.get("chair",{}).get("seat_width",0.0))
		else:
			loaded = _mesh(PACK+"premium/"+str(definition.asset),Vector3.ZERO)
			for socket in definition.get("sockets",{}):
				var xyz: Array = definition.sockets[socket]
				if xyz.size() == 3: _sockets[socket] = Vector3(float(xyz[0]),float(xyz[1]),float(xyz[2]))
			_seat_width = float(definition.get("seat_width",0.0))
	else:
		_load_legacy()
	_collect_geometry()
	var reference := _bounds()
	var base := Store.base_size(object_type)
	_reference_ppm = float(base.y)/maxf(reference.size.y,reference.size.x/(float(base.x)/base.y))/1.14
	_record = record.duplicate(true)
	_object_scale = float(record.get("scale",float(dimensions.y)/base.y))
	_base_sockets = _sockets.duplicate(true)
	_apply_visual(record)
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
	_position_from_record()
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
	node.set_meta("object_rest_transform",node.transform)
	_model_nodes.append(node)
	return true

func _collect_geometry() -> void:
	var started := Time.get_ticks_usec()
	_geometry_revision += 1
	_shared_projection_key.clear()
	_geometry_points.clear()
	for mesh in _scene.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		if not mesh.mesh.changed.is_connected(_invalidate_projection_geometry): mesh.mesh.changed.connect(_invalidate_projection_geometry)
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]: _geometry_points.append(mesh.global_transform*vertex)
	projection_profile.geometry_collections += 1
	projection_profile.last_collect_us = Time.get_ticks_usec()-started

func _invalidate_projection_geometry() -> void:
	_geometry_revision += 1
	_shared_projection_key.clear()

## Imported props are static apart from the declared setup/scale setters. Node
## and resource identity/transform checks also catch replacement or reparenting;
## Mesh.changed invalidates in-place resource edits without reading vertex arrays.
func _projection_fit_key() -> Array:
	var geometry: Array = []
	for mesh in _scene.find_children("*","MeshInstance3D",true,false):
		geometry.append([mesh.get_instance_id(),mesh.global_transform,mesh.mesh.get_instance_id() if mesh.mesh != null else 0])
	return [_shared_camera.get_instance_id(),_shared_camera.get_camera_transform(),_shared_camera.get_camera_projection(),_shared_camera.get_viewport().get_visible_rect().size,_shared_desktop_origin,_shared_transform,_geometry_revision,geometry,size,position,_camera.get_camera_transform(),_camera.get_camera_projection()]

func pixels_per_metre() -> float:
	if _camera == null: return 0.0
	return _camera.unproject_position(_camera.global_basis.x).distance_to(_camera.unproject_position(Vector3.ZERO))

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
	if is_instance_valid(_shared_camera):
		_fit_shared_projection()
		return
	var box := _bounds()
	var center := box.get_center()
	_camera.position = center+Vector3(0.0,0.55,3.0)
	_camera.look_at(center,Vector3.UP)
	if _view_configured:
		_camera.transform = Transform3D(_view_basis,center+_view_basis.z*3.0)
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for point in _geometry_points:
		var local := _camera.to_local(point)
		low = low.min(Vector2(local.x,local.y))
		high = high.max(Vector2(local.x,local.y))
	var fixed_ppm := maxf(1.0,_reference_ppm*_object_scale*_projection_zoom)
	size = Vector2i(maxi(32,ceili((high.x-low.x)*fixed_ppm*1.14)),maxi(32,ceili((high.y-low.y)*fixed_ppm*1.14)))
	_camera.size = float(size.y)/fixed_ppm
	_camera.position += _camera.basis.x*((low.x+high.x)*.5)
	_camera.near = 0.01
	_camera.far = 20.0
	# Ground the actual mesh envelope rather than the transparent viewport margin.
	# Projection is affine, so one camera translation aligns every scale exactly.
	var bottom := -INF
	for point in _geometry_points: bottom = maxf(bottom,_camera.unproject_position(point).y)
	if is_finite(bottom):
		var ppm := absf(_camera.unproject_position(center+_camera.basis.y).y-_camera.unproject_position(center).y)
		if ppm > 0.001: _camera.position += _camera.basis.y*((float(size.y)-1.0-bottom)/ppm)

func apply_record(record: Dictionary, _dimensions: Vector2i) -> void:
	_record = record.duplicate(true)
	var visual_changed := _apply_visual(record)
	var next_scale := float(record.get("scale",1.0))
	if visual_changed: _collect_geometry()
	if visual_changed or not is_equal_approx(next_scale,_object_scale):
		_object_scale = next_scale
		_refit()
	_position_from_record()
	if _label != null: _label.text = str(record.label)+" · 끌어서 배치"

func _position_from_record() -> void:
	if is_instance_valid(_shared_camera): return
	if dragging or _record.is_empty(): return
	var base := Vector2(Store.base_size(object_type))*_object_scale
	position = Vector2i(roundi(float(_record.x)+base.x*.5-float(size.x)*.5),roundi(float(_record.y)+base.y-float(size.y)))

func set_projection_zoom(value: float) -> void:
	_projection_zoom = clampf(value,.6,1.6)
	_refit()
	_position_from_record()

## Preserve the real chair's final/interrupted setup when the shared occupied
## scene hands rendering back to this native viewport. Camera fitting uses the
## same actual vertices and sockets; no duplicate or decorative chair is added.
func set_seat_setup(pullout_local_m: float, yaw_delta_deg: float) -> bool:
	if not is_instance_valid(_computer_assembly) or not _computer_assembly.set_seat_setup(pullout_local_m,yaw_delta_deg): return false
	_base_sockets = _computer_assembly.socket_catalogue(false)
	_yaw = INF
	_apply_visual(_record)
	_collect_geometry()
	_refit()
	_position_from_record()
	return true

func seat_setup() -> Dictionary:
	return _computer_assembly.seat_setup() if is_instance_valid(_computer_assembly) else {}

func set_seat_scale(value: float) -> bool:
	if not is_instance_valid(_computer_assembly) or not _computer_assembly.set_seat_scale(value): return false
	_record["seat_scale"] = value
	_base_sockets = _computer_assembly.socket_catalogue(false)
	_yaw = INF
	_apply_visual(_record)
	_collect_geometry()
	_refit()
	_position_from_record()
	return true

func set_editable(value: bool) -> void:
	editable = value
	mouse_passthrough = not value
	if _label != null: _label.visible = value
	if _overlay != null: _overlay.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if not value: _end_drag()

func socket_point(name: String) -> Vector2:
	if _camera == null or not _sockets.has(name): return Vector2.INF
	return Vector2(position)+_camera.unproject_position(_scene.global_transform*_sockets[name] if is_instance_valid(_shared_camera) else _sockets[name])

func socket_catalogue() -> Dictionary:
	var out := {}
	for name in _sockets: out[name] = socket_point(name)
	return out

func seat_surface() -> Dictionary:
	if not _sockets.has("seat") or _camera == null: return {}
	var seat: Vector3 = _sockets.seat
	if is_instance_valid(_shared_camera):
		var center := socket_point("seat")
		return {"id":"object:"+object_id+":seat","x1":center.x-12.0,"x2":center.x+12.0,"y":center.y}
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

func _apply_visual(record: Dictionary) -> bool:
	var yaw := float(record.get("yaw_deg",0.0))
	var preset := str(record.get("appearance","default"))
	var seat_changed := false
	if is_instance_valid(_computer_assembly):
		var next_seat_scale := float(record.get("seat_scale",1.0))
		if not is_equal_approx(next_seat_scale,float(_computer_assembly.seat_setup().seat_scale)):
			seat_changed = _computer_assembly.set_seat_scale(next_seat_scale)
			if seat_changed: _base_sockets = _computer_assembly.socket_catalogue(false)
	if is_equal_approx(yaw,_yaw) and preset == _appearance and not seat_changed: return false
	_yaw = yaw
	_appearance = preset
	var rotation := Basis(Vector3.UP,deg_to_rad(yaw+(35.0 if object_type == "computer" else 0.0)))
	for model in _model_nodes:
		model.transform = Transform3D(rotation,Vector3.ZERO)*Transform3D(model.get_meta("object_rest_transform"))
	_sockets.clear()
	for socket in _base_sockets: _sockets[socket] = rotation*Vector3(_base_sockets[socket])
	Appearance.apply(_scene,preset)
	return true

func set_view_basis(value: Basis) -> void:
	_view_basis = value.orthonormalized()
	_view_configured = true
	if _camera != null:
		_refit()
		_position_from_record()

func show_native() -> void:
	show()
	if DisplayServer.get_name() == "headless": return
	var id := get_window_id()
	if id == _native_alpha_id or id < 0: return
	_native_alpha_id = id
	# Window properties set before HWND creation do not always update the
	# compositor swapchain. Reassert on this owned native window after show.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT,false,id)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT,true,id)

## Both scenes use identical world axes/metres. Record yaw is already applied
## to model roots; object_world_transform supplies physical scale + translation.
## reference_desktop_origin anchors the fixed virtual viewport on the desktop.
func set_shared_projection(reference: Camera3D, reference_desktop_origin: Vector2, object_world_transform: Transform3D) -> bool:
	if not is_instance_valid(reference) or not reference.is_inside_tree() or not reference_desktop_origin.is_finite() or not object_world_transform.is_finite(): return false
	_shared_camera = reference
	_shared_desktop_origin = reference_desktop_origin
	_shared_transform = object_world_transform
	return _fit_shared_projection()

func clear_shared_projection() -> void:
	set_shared_world(null)
	_shared_camera = null
	_shared_crop = Rect2()
	_shared_projection_key.clear()
	if is_instance_valid(_scene): _scene.transform = Transform3D.IDENTITY
	_collect_geometry()
	_refit()
	_position_from_record()

func _fit_shared_projection() -> bool:
	var started := Time.get_ticks_usec()
	var result := _compute_shared_projection()
	projection_profile.last_call_us = Time.get_ticks_usec()-started
	projection_profile.timestamp_msec = Time.get_ticks_msec()
	projection_profile.last_call_succeeded = result
	return result

func _compute_shared_projection() -> bool:
	if not is_instance_valid(_shared_camera) or _camera == null or _scene == null: return false
	var started := Time.get_ticks_usec()
	projection_profile.last_request_at_us = started
	var key := _projection_fit_key()
	projection_profile.last_lookup_us = Time.get_ticks_usec()-started
	if not _shared_projection_key.is_empty() and key == _shared_projection_key:
		projection_profile.cache_hits += 1
		return true
	_shared_projection_key.clear()
	projection_profile.fits += 1
	_scene.transform = _shared_transform
	# Reproject actual imported vertices, not synthetic cross-corners of an AABB.
	_collect_geometry()
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for point in _geometry_points:
		var depth := DesktopView.depth(_shared_camera,point)
		if not is_finite(depth) or depth <= _shared_camera.near or depth >= _shared_camera.far:
			error = "spatial_geometry_outside_clip_range"
			return false
		var pixel := _shared_camera.unproject_position(point)
		low = low.min(pixel)
		high = high.max(pixel)
	if not low.is_finite() or not high.is_finite(): return false
	var start := (low-Vector2(8,8)).floor()
	var finish := (high+Vector2(8,8)).ceil()
	var dimensions := Vector2i(finish-start)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 4096 or dimensions.y > 4096:
		error = "spatial_viewport_too_large"
		return false
	size = dimensions
	_shared_crop = Rect2(start,Vector2(dimensions))
	position = Vector2i((_shared_desktop_origin+start).round())
	if not DesktopView.configure_crop(_camera,_shared_camera,_shared_crop):
		error = "spatial_crop_failed"
		return false
	# Both the model and socket coordinates must enter the same world transform.
	error = ""
	_shared_projection_key = _projection_fit_key()
	projection_profile.last_fit_us = Time.get_ticks_usec()-started
	projection_profile.last_fit_at_us = started
	return true

func spatial_geometry_bounds() -> Rect2:
	return Rect2(Vector2(position),Vector2(size)) if is_instance_valid(_shared_camera) else Rect2()

## Every perspective camera renders one shared World3D. Thus avatar/prop and
## prop/prop depth tests use the same scene, even where native crops overlap.
## Native alpha compositing remains a separate edge-coverage consideration.
func set_shared_world(shared_world: World3D, reference_viewport: Viewport = null) -> void:
	var enabled := shared_world != null
	if enabled and reference_viewport != null:
		msaa_3d = reference_viewport.msaa_3d
		screen_space_aa = reference_viewport.screen_space_aa
		use_taa = reference_viewport.use_taa
	if enabled == _shared_world_active and (not enabled or world_3d == shared_world): return
	var previous_world := world_3d # Keep old scenario alive until the viewport detaches.
	_shared_world_active = enabled
	if not enabled: world_3d = World3D.new()
	if _scene == null:
		if enabled: world_3d = shared_world
		return
	for light in _scene.find_children("*","Light3D",true,false): light.visible = not enabled
	for node in _scene.find_children("*","WorldEnvironment",true,false):
		if enabled:
			_private_environment = node.environment
			node.environment = null
		else: node.environment = _private_environment
	if enabled: world_3d = shared_world
	_sync_shared_visibility()
	previous_world = null

func _sync_shared_visibility() -> void:
	for model in _model_nodes:
		model.visible = visible if _shared_world_active else true
