class_name CompanionPanelWindow
extends Window
## Independent modeless settings viewport. Host owns settings and camera updates.
## Geometry arguments are global desktop pixels on the selected usable monitor.

signal closed
signal hotkey(action: String, pressed: bool)
signal panel_focus_lost

const PREFERRED_SIZE := Vector2i(380, 720)
const PANEL_GAP := 16
var panel: Control
var _workarea := Rect2i()
var _dragging := false
var _drag_offset := Vector2i.ZERO

func _init() -> void:
	name = "CompanionSettingsWindow"
	title = "Mate Companion 설정"
	visible = false
	force_native = true
	borderless = true
	unresizable = true
	minimize_disabled = true
	maximize_disabled = true
	transient = false
	exclusive = false
	always_on_top = true
	unfocusable = false
	transparent = false
	transparent_bg = false
	wrap_controls = false
	close_requested.connect(close_panel)
	focus_exited.connect(_on_focus_exited)

func configure(content: Control, pet_global_rect: Rect2i, workarea: Rect2i) -> bool:
	if content == null or not is_instance_valid(content):
		return false
	if is_instance_valid(panel) and panel != content:
		return false # An existing panel remains owned; no implicit destruction.
	panel = content
	if panel.get_parent() == null:
		add_child(panel)
	elif panel.get_parent() != self:
		panel.reparent(self, false)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.show()
	_workarea = workarea
	var placement := placement_rect(pet_global_rect, workarea)
	if placement.size.x <= 0 or placement.size.y <= 0:
		return false
	size = placement.size
	position = placement.position
	return true

func open_next_to(pet_global_rect: Rect2i, workarea: Rect2i) -> bool:
	if not is_instance_valid(panel):
		return false
	var placement := placement_rect(pet_global_rect, workarea)
	if placement.size.x <= 0 or placement.size.y <= 0:
		return false
	_workarea = workarea
	size = placement.size
	position = placement.position
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show()
	grab_focus()
	return true

func close_panel() -> void:
	_dragging = false
	if not visible:
		return
	hide()
	panel_focus_lost.emit() # Release any push-to-talk held when the window closes.
	closed.emit()

func _on_focus_exited() -> void:
	_dragging = false
	panel_focus_lost.emit()

static func placement_rect(pet: Rect2i, usable: Rect2i, preferred: Vector2i = PREFERRED_SIZE) -> Rect2i:
	if usable.size.x <= 0 or usable.size.y <= 0 or preferred.x <= 0 or preferred.y <= 0:
		return Rect2i()
	var dimensions := Vector2i(mini(preferred.x, usable.size.x), mini(preferred.y, usable.size.y))
	var centered_y := pet.position.y + (pet.size.y-dimensions.y)/2
	var centered_x := pet.position.x + (pet.size.x-dimensions.x)/2
	var candidates: Array[Vector2i] = [
		Vector2i(pet.end.x + PANEL_GAP, centered_y),
		Vector2i(pet.position.x - PANEL_GAP - dimensions.x, centered_y),
		Vector2i(centered_x, pet.position.y - PANEL_GAP - dimensions.y),
		Vector2i(centered_x, pet.end.y + PANEL_GAP),
	]
	# Prefer beside the character. Vertical placement is used only when neither
	# side can fit. Clamping the orthogonal axis handles monitor/taskbar edges.
	for candidate in candidates:
		var rect := Rect2i(_clamped_position(candidate, dimensions, usable), dimensions)
		if not rect.intersects(pet):
			return rect
	# On a constrained monitor overlapping may be unavoidable. Select the safe
	# rectangle with the smallest intersection, keeping the whole window usable.
	candidates.append_array([
		usable.position,
		Vector2i(usable.end.x-dimensions.x, usable.position.y),
		Vector2i(usable.position.x, usable.end.y-dimensions.y),
		usable.end-dimensions,
	])
	var best := Rect2i(_clamped_position(candidates[0], dimensions, usable), dimensions)
	var best_overlap := _overlap_area(best, pet)
	for candidate in candidates:
		var rect := Rect2i(_clamped_position(candidate, dimensions, usable), dimensions)
		var overlap := _overlap_area(rect, pet)
		if overlap < best_overlap:
			best = rect
			best_overlap = overlap
	return best

static func _clamped_position(candidate: Vector2i, dimensions: Vector2i, usable: Rect2i) -> Vector2i:
	return Vector2i(
		clampi(candidate.x, usable.position.x, usable.end.x-dimensions.x),
		clampi(candidate.y, usable.position.y, usable.end.y-dimensions.y))

static func _overlap_area(a: Rect2i, b: Rect2i) -> int:
	var intersection := a.intersection(b)
	return maxi(0, intersection.size.x)*maxi(0, intersection.size.y)

static func hotkey_action(event: InputEventKey) -> String:
	if event == null or event.echo:
		return ""
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match code:
		KEY_F8: return "toggle_panel" if event.pressed else ""
		KEY_F9: return "push_to_talk"
		KEY_F10: return "toggle_vad" if event.pressed else ""
		KEY_ESCAPE: return "cancel" if event.pressed else ""
	return ""

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var action := hotkey_action(event)
		if not action.is_empty():
			hotkey.emit(action, event.pressed)
			set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_dragging = false
		elif event.position.y < 38 and event.position.x < 200:
			# Only the unused title area drags. The close button and panel controls
			# remain normal interactive widgets in this independent viewport.
			_dragging = true
			_drag_offset = DisplayServer.mouse_get_position()-position
	elif event is InputEventMouseMotion and _dragging:
		position = _clamped_position(DisplayServer.mouse_get_position()-_drag_offset, size, _workarea)

func _process(_delta: float) -> void:
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
