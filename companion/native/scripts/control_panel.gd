class_name ControlPanel
extends Control
## Compact control panel (Korean labels) built in code: status header, chat with
## push-to-talk / VAD, motion editor (presets, params, sequence + keyframe
## composer with preview/save), background Work log and settings.

signal send_text(text: String)
signal ptt_pressed
signal ptt_released
signal vad_toggled(enabled: bool)
signal cancel_requested
signal character_selected(id: String)
signal avatar_variant_selected(id: String)
signal refresh_requested
signal reload_avatar_requested
signal preview_gesture(name: String, emotion: String, intensity: float, speed: float, repeat: int)
signal preview_motion(motion: Dictionary)
## "두 동작 이어보기": play two finite built-in bank gestures back to back; the second starts
## `lead` seconds before the first ends (0..1). The host forwards to the motion owner's preview
## sequence API; the panel never composes or plays anything itself.
signal preview_sequence(first: String, second: String, lead: float)
signal save_motion(motion: Dictionary)
signal job_start(prompt: String)
signal job_cancel
signal setting_changed(key: String, value: Variant)
signal backend_changed(url: String)
signal collapse_requested
## Manual sit (true) / stand (false) on the current desktop support (surface mode only).
signal sit_requested(sit: bool)
## Behavior tab ("행동"): the user asked the pet to walk over to / look at a saved interest point.
## The host closes the panel after an explicit go and queues the intention; nothing moves here.
signal point_go(id: String)
signal point_inspect(id: String)
## Interest point edits. With bind_interest_points() these are also applied to the manager directly;
## without it the host applies them and calls set_interest_points().
signal point_add_requested(label: String)
signal point_rename_requested(id: String, label: String)
signal point_remove_requested(id: String)
## "표식 보기": show/hide the draggable marker windows (editing aid, not persisted).
signal markers_toggled(on: bool)

const PANEL_WIDTH := 340.0
## Static helpers only; the Settings autoload is looked up at runtime so this script compiles
## in `-s` tool/test mode where autoload globals are not registered yet (same as backend_client.gd).
const SettingsScript := preload("res://scripts/settings.gd")
const EMOTIONS := ["neutral", "happy", "relaxed", "sad", "surprised", "angry"]
const KEYFRAME_MAX := 64
## View (camera) settings: key -> default. Ranges live in _build_view_tab.
const VIEW_DEFAULTS := {"view_projection": "perspective", "view_yaw_deg": 0.0, "view_pitch_deg": 0.0, "view_height": 0.0, "view_zoom": 1.0, "view_fov_deg": 45.0, "view_distance_m": 3.6}
## Bank names that are contact/support poses rather than one-shot gestures (never chained).
const SEQUENCE_EXCLUDED_WORDS := ["sit", "seat", "prop", "support", "hold", "contact", "lean"]
const SEQUENCE_LEAD_DEFAULT := 0.35

var bank: MotionBank = MotionBank.new()
## Imported VRMA clips (GET /motion-assets) that MotionPlayer has loaded: name -> catalog entry.
## Read-only: they appear in the preset list for preview/LLM dispatch, never in the composers.
var vrma_clips: Dictionary = {}
var _settings: Node # /root/Settings when present (app or test harness); DEFAULTS otherwise
var _sequence: Array = []
var _keyframes: Array = []

# widgets referenced later
var _conn_dot: ColorRect
var _conn_label: Label
var _activity_label: Label
var _mode_label: Label
var _level_bar: ProgressBar
var _status_line: Label
var _character_option: OptionButton
var _avatar_variant_option: OptionButton
var _avatar_variant_note: Label
var _avatar_variant_rows: Array = []
var _avatar_variant_id := "default"
var _transcript: RichTextLabel
var _input: LineEdit
var _mic_button: Button
var _vad_check: CheckButton
var _cancel_button: Button
var _preset_option: OptionButton
var _emotion_option: OptionButton
var _intensity: HSlider
var _speed: HSlider
var _repeat: SpinBox
var _sequence_list: ItemList
var _chain_first: OptionButton
var _chain_second: OptionButton
var _chain_lead: HSlider
var _chain_lead_value: Label
var _chain_button: Button
var _sequence_name: LineEdit
var _kf_bone: OptionButton
var _kf_time: SpinBox
var _kf_x: SpinBox
var _kf_y: SpinBox
var _kf_z: SpinBox
var _kf_duration: SpinBox
var _kf_list: ItemList
var _kf_name: LineEdit
var _motion_result: Label
var _job_prompt: TextEdit
var _job_start: Button
var _job_cancel: Button
var _job_status: Label
var _job_workspace: Label
var _job_log: RichTextLabel
var _backend_edit: LineEdit
var _backend_source: Label
var _vad_threshold: HSlider
var _vad_threshold_value: Label
var _mic_device: OptionButton
var _mic_rate: OptionButton
var _scale_slider: HSlider
var _volume_slider: HSlider
var _avatar_label: Label
var _audio_stats: Label
var _autonomy_check: CheckButton
var _autonomy_speed: HSlider
var _autonomy_state: Label
var _surface_check: CheckButton
var _surface_status: Label
var _sit_button: Button
var _sitting := false
var _idle_clip_option: OptionButton
# view tab
var _view_projection: OptionButton
var _view_projection_note: Label
var _view_fov: HSlider
var _view_distance: HSlider
var _view_yaw: HSlider
var _view_pitch: HSlider
var _view_height: HSlider
var _view_zoom: HSlider
var _view_reset: Button
## Saved/mirrored idle_clip value: "auto", "" (procedural breathing only) or an imported clip name.
var _idle_choice := "auto"
## Current character's profile ambient_loop (from the character catalogue) shown under "자동".
var _idle_profile_loop := ""
var _tabs: TabContainer
# behavior tab
var _behavior_check: CheckButton
var _behavior_state: Label
var _point_list: ItemList
var _point_name: LineEdit
var _point_add: Button
var _point_rename: Button
var _point_remove: Button
var _point_go: Button
var _point_inspect: Button
var _markers_check: CheckButton
var _point_hint: Label
var _point_rows: Array[Dictionary] = [] # last set_interest_points() rows (id,label,status,...)
var _points_manager: Node # InterestPoints bound via bind_interest_points(), or null
# desktop living-space tab (experimental)
var _obj_catalogue: OptionButton
var _obj_add: Button
var _obj_list: ItemList
var _obj_name: LineEdit
var _obj_rename: Button
var _obj_scale: HSlider
var _obj_scale_value: Label
var _obj_visible: CheckButton
var _obj_remove: Button
var _obj_edit: CheckButton
var _obj_verbs: HBoxContainer
var _obj_cancel: Button
var _obj_status: Label
var _obj_hint: Label
var _obj_rows: Array[Dictionary] = []
var _obj_catalogue_data: Array = []
var _objects: Node # desktop objects host bound via bind_desktop_objects(), or null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The panel lives in its own modeless settings window (Astra's wrapper) and fills it; the host
	# may still place it as a sidebar by overriding the anchors after instantiation.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	clip_contents = true
	_settings = get_node_or_null("/root/Settings")
	_build()


func _setting(key: String, fallback: Variant) -> Variant:
	if _settings != null:
		return _settings.get_value(key, fallback)
	return SettingsScript.DEFAULTS.get(key, fallback)


## Widest minimum size any child asks for; must stay <= PANEL_WIDTH or the panel grows over the pet.
func content_min_width() -> float:
	return float(widest_child()["width"])


## {width, path} of the child with the largest combined minimum width (for the selftest report).
func widest_child() -> Dictionary:
	var widest := {"width": 0.0, "path": ""}
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and n != self: # the panel itself carries PANEL_WIDTH as its own minimum
			var w := (n as Control).get_combined_minimum_size().x
			if w >= float(widest["width"]) and w > 0.0: # >= so the deepest offender is named
				widest = {"width": w, "path": str(get_path_to(n))}
		for c in n.get_children():
			stack.append(c)
	return widest


func _style(bg: Color, radius: int = 10, border: Color = Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _build() -> void:
	var root := PanelContainer.new()
	root.name = "Panel"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_stylebox_override("panel", _style(Color(0.09, 0.08, 0.12, 0.94), 14))
	add_child(root)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	# --- header: title + collapse
	var head := HBoxContainer.new()
	vbox.add_child(head)
	var title := Label.new()
	title.text = "Mate Companion"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var collapse := Button.new()
	collapse.text = "닫기 (F8)"
	collapse.tooltip_text = "설정 창을 닫습니다. 캐릭터는 바탕화면에 그대로 남습니다."
	collapse.pressed.connect(func(): collapse_requested.emit())
	head.add_child(collapse)

	# --- status row
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 8)
	vbox.add_child(status)
	_conn_dot = ColorRect.new()
	_conn_dot.custom_minimum_size = Vector2(10, 10)
	_conn_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_conn_dot.color = Color(0.6, 0.6, 0.6)
	status.add_child(_conn_dot)
	_conn_label = Label.new()
	_conn_label.text = "연결 안 됨"
	_conn_label.clip_text = true # long close reasons must not widen the panel past PANEL_WIDTH
	_conn_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_child(_conn_label)
	_activity_label = Label.new()
	_activity_label.text = "· 대기"
	status.add_child(_activity_label)
	_mode_label = Label.new()
	_mode_label.text = "· 텍스트"
	_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_label.clip_text = true # the mode string ("VAD 대기 · 마이크 켜짐 · noAEC") is the widest item
	_mode_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_child(_mode_label)
	_level_bar = ProgressBar.new()
	_level_bar.custom_minimum_size = Vector2(60, 8)
	_level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_level_bar.show_percentage = false
	_level_bar.max_value = 1.0
	_level_bar.tooltip_text = "마이크 입력 레벨"
	status.add_child(_level_bar)
	_status_line = Label.new()
	_status_line.text = ""
	_status_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_line.add_theme_font_size_override("font_size", 11)
	_status_line.modulate = Color(0.85, 0.85, 0.9)
	vbox.add_child(_status_line)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)
	_build_chat_tab()
	_build_behavior_tab()
	_build_space_tab()
	_build_view_tab()
	_build_motion_tab()
	_build_work_tab()
	_build_settings_tab()


func _tab(name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = name
	v.add_theme_constant_override("separation", 6)
	_tabs.add_child(v)
	return v


func _build_chat_tab() -> void:
	var v := _tab("대화")
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_label("캐릭터"))
	_character_option = OptionButton.new()
	_character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_option.item_selected.connect(func(i: int): character_selected.emit(str(_character_option.get_item_metadata(i))))
	row.add_child(_character_option)
	var refresh := Button.new()
	refresh.text = "새로고침"
	refresh.tooltip_text = "캐릭터 목록과 모션 뱅크를 다시 받습니다"
	refresh.pressed.connect(func(): refresh_requested.emit())
	row.add_child(refresh)
	var variant_row := HBoxContainer.new()
	v.add_child(variant_row)
	variant_row.add_child(_label("외형"))
	_avatar_variant_option = OptionButton.new()
	_avatar_variant_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_avatar_variant_option.item_selected.connect(func(i: int):
		_avatar_variant_id = str(_avatar_variant_option.get_item_metadata(i))
		_refresh_avatar_variant_note()
		avatar_variant_selected.emit(_avatar_variant_id))
	variant_row.add_child(_avatar_variant_option)
	_avatar_variant_note = Label.new()
	_avatar_variant_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_avatar_variant_note.add_theme_font_size_override("font_size",11)
	v.add_child(_avatar_variant_note)
	set_avatar_variants([],"default")

	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = true
	_transcript.scroll_following = true
	_transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transcript.custom_minimum_size = Vector2(0, 160)
	_transcript.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), 8))
	_transcript.selection_enabled = true
	v.add_child(_transcript)

	var input_row := HBoxContainer.new()
	v.add_child(input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "메시지 입력 후 Enter"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(t: String): _submit_text())
	input_row.add_child(_input)
	var send := Button.new()
	send.text = "보내기"
	send.pressed.connect(_submit_text)
	input_row.add_child(send)

	var mic_row := HBoxContainer.new()
	mic_row.add_theme_constant_override("separation", 6)
	v.add_child(mic_row)
	_mic_button = Button.new()
	_mic_button.text = "🎤 말하기 (F9)"
	_mic_button.tooltip_text = "누르고 있는 동안 녹음 (최대 30초). 말하는 중에도 끼어들기 가능."
	_mic_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_button.button_down.connect(func(): ptt_pressed.emit())
	_mic_button.button_up.connect(func(): ptt_released.emit())
	mic_row.add_child(_mic_button)
	_cancel_button = Button.new()
	_cancel_button.text = "중단 (Esc)"
	_cancel_button.tooltip_text = "현재 응답/음성을 취소합니다"
	_cancel_button.pressed.connect(func(): cancel_requested.emit())
	mic_row.add_child(_cancel_button)
	_vad_check = CheckButton.new()
	_vad_check.text = "자동 감지 VAD (F10)"
	_vad_check.tooltip_text = "에너지 기반 음성 감지. 에코 제거 없음: 캐릭터가 말하는 동안은 감지를 멈춥니다. 스피커 사용 시 헤드셋 권장."
	_vad_check.toggled.connect(func(on: bool): vad_toggled.emit(on))
	v.add_child(_vad_check)
	var hint := Label.new()
	hint.text = "단축키: F8 패널 · F9 누르고 말하기 · F10 VAD · Esc 중단 · 펫 드래그로 이동, 클릭하면 반응, 휠로 크기 조절"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.7, 0.7, 0.78)
	v.add_child(hint)


## "행동": may the pet act on its own, what it is doing now, and the user's named interest points
## (add near the pet, drag the marker, then "가보기" / "살펴보기"). Plain product wording only.
func _build_behavior_tab() -> void:
	var v := _tab("행동")
	_behavior_check = CheckButton.new()
	_behavior_check.text = "스스로 행동하기"
	_behavior_check.tooltip_text = "켜면 대화 중에 어울릴 때 저장한 지점으로 가거나 살펴보고, 가끔 쉽니다. 화면 내용은 읽지 않습니다. 꺼도 산책 설정은 그대로입니다."
	_behavior_check.button_pressed = bool(_setting("behavior_enabled", true))
	_behavior_check.toggled.connect(func(on: bool): setting_changed.emit("behavior_enabled", on))
	v.add_child(_behavior_check)
	_behavior_state = Label.new()
	_behavior_state.text = "지금: " + behavior_state_text("", "", bool(_setting("behavior_enabled", true)))
	_behavior_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_behavior_state.add_theme_font_size_override("font_size", 11)
	_behavior_state.modulate = Color(0.7, 0.7, 0.78)
	v.add_child(_behavior_state)

	v.add_child(_section("관심 지점 (최대 %d개)" % InterestPoints.MAX_POINTS))
	_point_list = ItemList.new()
	_point_list.custom_minimum_size = Vector2(0, 120)
	_point_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_point_list.select_mode = ItemList.SELECT_SINGLE
	_point_list.item_selected.connect(func(_i: int): _refresh_point_buttons())
	_point_list.empty_clicked.connect(func(_p: Vector2, _b: int):
		_point_list.deselect_all()
		_refresh_point_buttons())
	v.add_child(_point_list)
	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	_point_name = LineEdit.new()
	_point_name.placeholder_text = "이름 (예: 모니터 왼쪽 아래)"
	_point_name.max_length = InterestPoints.LABEL_MAX
	_point_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_name.text_submitted.connect(func(_t: String): _request_add_point())
	name_row.add_child(_point_name)
	_point_add = Button.new()
	_point_add.text = "추가"
	_point_add.tooltip_text = "펫 옆에 표식을 만듭니다. 표식을 원하는 자리로 끌어다 놓으면 그 끝점이 저장됩니다."
	_point_add.pressed.connect(_request_add_point)
	name_row.add_child(_point_add)
	var edit_row := HBoxContainer.new()
	v.add_child(edit_row)
	_point_rename = Button.new()
	_point_rename.text = "이름 바꾸기"
	_point_rename.tooltip_text = "선택한 지점의 이름을 위 입력칸의 내용으로 바꿉니다"
	_point_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_rename.pressed.connect(_request_rename_point)
	edit_row.add_child(_point_rename)
	_point_remove = Button.new()
	_point_remove.text = "삭제"
	_point_remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_remove.pressed.connect(_request_remove_point)
	edit_row.add_child(_point_remove)
	_markers_check = CheckButton.new()
	_markers_check.text = "표식 보기"
	_markers_check.tooltip_text = "저장한 지점 위에 작은 표식 창을 띄웁니다. 끌어서 옮길 수 있고, 편집이 끝나면 숨기세요."
	_markers_check.toggled.connect(_on_markers_toggled)
	edit_row.add_child(_markers_check)
	var act_row := HBoxContainer.new()
	v.add_child(act_row)
	_point_go = Button.new()
	_point_go.text = "가보기"
	_point_go.tooltip_text = "패널을 닫고 선택한 지점까지 걸어갑니다 (자리를 옮김)"
	_point_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_go.pressed.connect(func():
		var id := selected_point_id()
		if not id.is_empty():
			point_go.emit(id))
	act_row.add_child(_point_go)
	_point_inspect = Button.new()
	_point_inspect.text = "살펴보기"
	_point_inspect.tooltip_text = "패널을 닫고 제자리에 선 채 선택한 지점을 바라보며 살펴봅니다 (걸어가지 않음)"
	_point_inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_point_inspect.pressed.connect(func():
		var id := selected_point_id()
		if not id.is_empty():
			point_inspect.emit(id))
	act_row.add_child(_point_inspect)
	_point_hint = Label.new()
	_point_hint.text = "지점이 없습니다. 이름을 적고 추가한 뒤 표식을 끌어 놓으세요."
	_point_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_point_hint.add_theme_font_size_override("font_size", 11)
	_point_hint.modulate = Color(0.7, 0.7, 0.78)
	v.add_child(_point_hint)
	_refresh_point_buttons()


## "공간": experimental desktop living-space objects (chair / sofa / computer desk). The panel only
## drives the objects host through bind_desktop_objects(); it never persists, moves or poses
## anything itself. Interactions are geometry + pose only.
func _build_space_tab() -> void:
	var v := _tab("공간")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	var beta := Label.new()
	beta.text = "대화로 가구를 놓거나 사용해 달라고 요청하세요. 아래에서 직접 조절할 수도 있습니다."
	beta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	beta.add_theme_font_size_override("font_size", 11)
	beta.modulate = Color(0.95, 0.8, 0.55)
	inner.add_child(beta)

	inner.add_child(_section("직접 배치 · 선택 사항"))
	var add_row := HBoxContainer.new()
	inner.add_child(add_row)
	_obj_catalogue = OptionButton.new()
	_obj_catalogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_catalogue.fit_to_longest_item = false
	_obj_catalogue.clip_text = true
	_obj_catalogue.tooltip_text = "놓을 가구 종류"
	add_row.add_child(_obj_catalogue)
	_obj_add = Button.new()
	_obj_add.text = "추가"
	_obj_add.tooltip_text = "선택한 가구를 펫 근처에 놓습니다. 배치 편집을 켜면 끌어서 옮길 수 있습니다."
	_obj_add.pressed.connect(_request_add_object)
	add_row.add_child(_obj_add)
	_obj_list = ItemList.new()
	_obj_list.custom_minimum_size = Vector2(0, 96)
	_obj_list.select_mode = ItemList.SELECT_SINGLE
	_obj_list.item_selected.connect(func(_i: int): _refresh_object_controls())
	_obj_list.empty_clicked.connect(func(_p: Vector2, _b: int):
		_obj_list.deselect_all()
		_refresh_object_controls())
	inner.add_child(_obj_list)
	var name_row := HBoxContainer.new()
	inner.add_child(name_row)
	_obj_name = LineEdit.new()
	_obj_name.placeholder_text = "이름 (예: 창가 의자)"
	_obj_name.max_length = 40
	_obj_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_name.text_submitted.connect(func(_t: String): _request_rename_object())
	name_row.add_child(_obj_name)
	_obj_rename = Button.new()
	_obj_rename.text = "이름 바꾸기"
	_obj_rename.pressed.connect(_request_rename_object)
	name_row.add_child(_obj_rename)
	var scale_row := HBoxContainer.new()
	inner.add_child(scale_row)
	var scale_label := _label("크기")
	scale_label.custom_minimum_size = Vector2(70, 0)
	scale_row.add_child(scale_label)
	_obj_scale = HSlider.new()
	_obj_scale.min_value = 0.5
	_obj_scale.max_value = 1.8
	_obj_scale.step = 0.05
	_obj_scale.value = 1.0
	_obj_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_scale.value_changed.connect(_on_object_scale)
	scale_row.add_child(_obj_scale)
	_obj_scale_value = Label.new()
	_obj_scale_value.text = "1.00"
	_obj_scale_value.custom_minimum_size = Vector2(44, 0)
	scale_row.add_child(_obj_scale_value)
	var tog_row := HBoxContainer.new()
	inner.add_child(tog_row)
	_obj_visible = CheckButton.new()
	_obj_visible.text = "보이기"
	_obj_visible.tooltip_text = "끄면 이 가구를 바탕화면에서 숨깁니다 (삭제되지 않음)"
	_obj_visible.toggled.connect(_on_object_visible)
	tog_row.add_child(_obj_visible)
	_obj_remove = Button.new()
	_obj_remove.text = "삭제"
	_obj_remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_remove.pressed.connect(_request_remove_object)
	tog_row.add_child(_obj_remove)
	_obj_edit = CheckButton.new()
	_obj_edit.text = "배치 편집 (가구 창을 끌어 이동)"
	_obj_edit.tooltip_text = "켜져 있는 동안 바탕화면의 가구를 마우스로 끌어 옮길 수 있습니다. 배치가 끝나면 끄세요."
	_obj_edit.toggled.connect(_on_object_edit)
	inner.add_child(_obj_edit)

	inner.add_child(_section("펫에게 시키기"))
	_obj_verbs = HBoxContainer.new()
	_obj_verbs.add_theme_constant_override("separation", 6)
	inner.add_child(_obj_verbs)
	_obj_cancel = Button.new()
	_obj_cancel.text = "그만하기"
	_obj_cancel.tooltip_text = "진행 중인 가구 동작을 멈춥니다"
	_obj_cancel.pressed.connect(_request_cancel_interaction)
	inner.add_child(_obj_cancel)
	_obj_status = Label.new()
	_obj_status.text = "상태: 준비 안 됨"
	_obj_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_status.add_theme_font_size_override("font_size", 11)
	_obj_status.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(_obj_status)
	_obj_hint = Label.new()
	_obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_hint.add_theme_font_size_override("font_size", 11)
	_obj_hint.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(_obj_hint)
	var future := Label.new()
	future.text = "앞으로 (아직 없음): 물건 들기·도구 꽂이. 모든 가구 동작은 자세와 위치만 다룹니다. 화면·파일을 읽거나 다른 프로그램을 조작하지 않습니다."
	future.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	future.add_theme_font_size_override("font_size", 10)
	future.modulate = Color(0.6, 0.6, 0.66)
	inner.add_child(future)
	_refresh_objects()


## "시점": how the character is viewed (camera yaw/pitch, eye-height offset, zoom). These change the
## viewing angle only, never where the character stands on the desktop. Values go through the
## existing setting_changed channel; set_view_settings() mirrors host values without emitting.
func _build_view_tab() -> void:
	var v := _tab("시점")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	var note := Label.new()
	note.text = "캐릭터를 바라보는 각도와 거리만 바꿉니다. 바탕화면에서 캐릭터가 서 있는 자리는 그대로입니다."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(note)
	inner.add_child(_section("카메라"))
	var projection_row := HBoxContainer.new()
	inner.add_child(projection_row)
	var projection_label := _label("투영 방식")
	projection_label.custom_minimum_size.x = 70
	projection_row.add_child(projection_label)
	_view_projection = OptionButton.new()
	_view_projection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_projection.add_item("직교 · 일정한 크기")
	_view_projection.set_item_metadata(0, "orthographic")
	_view_projection.add_item("원근 · 가까울수록 크게")
	_view_projection.set_item_metadata(1, "perspective")
	_view_projection.select(1 if str(_setting("view_projection", "perspective")) == "perspective" else 0)
	projection_row.add_child(_view_projection)
	_view_projection_note = Label.new()
	_view_projection_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_view_projection_note.add_theme_font_size_override("font_size", 11)
	inner.add_child(_view_projection_note)
	_view_yaw = _view_row(inner, "좌우 회전", "view_yaw_deg", -180.0, 180.0, 1.0, "%.0f°", "캐릭터를 왼쪽/오른쪽에서 봅니다 (도)")
	_view_pitch = _view_row(inner, "위아래 각도", "view_pitch_deg", -60.0, 70.0, 1.0, "%.0f°", "위에서 내려다보거나 아래에서 올려다봅니다 (도)")
	_view_height = _view_row(inner, "눈높이", "view_height", -0.5, 0.5, 0.01, "%+.2f m", "카메라 눈높이를 위아래로 옮깁니다 (미터). 캐릭터 위치는 바뀌지 않습니다.")
	_view_zoom = _view_row(inner, "확대", "view_zoom", 0.6, 1.6, 0.05, "×%.2f", "1.00이 기본 크기입니다")
	_view_fov = _view_row(inner, "화각", "view_fov_deg", 20.0, 80.0, 1.0, "%.0f°", "원근 시점의 세로 화각입니다. 넓힐수록 더 많은 공간이 보입니다. 확대 1.00 기준입니다.")
	_view_distance = _view_row(inner, "카메라 거리", "view_distance_m", 1.0, 12.0, 0.1, "%.1f m", "원근 시점에서 카메라와 기준점 사이의 실제 거리입니다. 가구 위치나 크기는 바꾸지 않습니다.")
	_view_projection.item_selected.connect(func(_index: int):
		_refresh_view_projection()
		setting_changed.emit("view_projection", _view_projection.get_selected_metadata()))
	_refresh_view_projection()
	_view_reset = Button.new()
	_view_reset.text = "기본 시점"
	_view_reset.tooltip_text = "직교 · 회전 0° · 각도 0° · 눈높이 0 · 확대 1.00 · 화각 45° · 거리 3.6 m로 되돌립니다"
	_view_reset.pressed.connect(reset_view_settings)
	inner.add_child(_view_reset)


func _view_row(parent: Control, text: String, key: String, minv: float, maxv: float, step: float, fmt: String, tip: String) -> HSlider:
	var default_value := float(VIEW_DEFAULTS[key])
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(text)
	l.custom_minimum_size = Vector2(70, 0)
	l.tooltip_text = tip
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = clampf(float(_setting(key, default_value)), minv, maxv)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.tooltip_text = tip
	row.add_child(s)
	var val := Label.new()
	val.text = fmt % s.value
	val.custom_minimum_size = Vector2(56, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.set_meta("value_label", val)
	s.set_meta("value_format", fmt)
	s.set_meta("setting_key", key)
	s.value_changed.connect(func(nv: float):
		val.text = fmt % nv
		setting_changed.emit(key, nv))
	return s


func _build_motion_tab() -> void:
	var v := _tab("모션")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)

	inner.add_child(_section("프리셋 미리보기"))
	var row := HBoxContainer.new()
	inner.add_child(row)
	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_option)
	_emotion_option = OptionButton.new()
	for e in EMOTIONS:
		_emotion_option.add_item(e)
	row.add_child(_emotion_option)
	_intensity = _slider_row(inner, "강도", 0.0, 1.5, 0.05, float(_setting("motion_intensity", 1.0)), "motion_intensity")
	_speed = _slider_row(inner, "속도", 0.5, 2.0, 0.05, float(_setting("motion_speed", 1.0)), "motion_speed")
	var rep_row := HBoxContainer.new()
	inner.add_child(rep_row)
	rep_row.add_child(_label("반복"))
	_repeat = SpinBox.new()
	_repeat.min_value = 1
	_repeat.max_value = 3
	_repeat.value = int(_setting("motion_repeat", 1))
	_repeat.value_changed.connect(func(val: float): setting_changed.emit("motion_repeat", int(val)))
	rep_row.add_child(_repeat)
	var preview := Button.new()
	preview.text = "미리보기"
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.pressed.connect(func():
		preview_gesture.emit(_selected_preset(), _emotion_option.get_item_text(_emotion_option.selected), _intensity.value, _speed.value, int(_repeat.value)))
	rep_row.add_child(preview)

	inner.add_child(_section("두 동작 이어보기"))
	var chain_row := HBoxContainer.new()
	inner.add_child(chain_row)
	_chain_first = OptionButton.new()
	_chain_first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chain_first.fit_to_longest_item = false
	_chain_first.clip_text = true
	_chain_first.tooltip_text = "먼저 할 동작 (내장 제스처만)"
	chain_row.add_child(_chain_first)
	chain_row.add_child(_label("→"))
	_chain_second = OptionButton.new()
	_chain_second.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chain_second.fit_to_longest_item = false
	_chain_second.clip_text = true
	_chain_second.tooltip_text = "이어서 할 동작 (내장 제스처만)"
	chain_row.add_child(_chain_second)
	var lead_row := HBoxContainer.new()
	inner.add_child(lead_row)
	var lead_label := _label("겹침(초)")
	lead_label.custom_minimum_size = Vector2(70, 0)
	lead_label.tooltip_text = "첫 동작이 끝나기 몇 초 전에 두 번째 동작을 시작할지"
	lead_row.add_child(lead_label)
	_chain_lead = HSlider.new()
	_chain_lead.min_value = 0.0
	_chain_lead.max_value = 1.0
	_chain_lead.step = 0.05
	_chain_lead.value = SEQUENCE_LEAD_DEFAULT
	_chain_lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead_row.add_child(_chain_lead)
	_chain_lead_value = Label.new()
	_chain_lead_value.text = "%.2f" % SEQUENCE_LEAD_DEFAULT
	_chain_lead_value.custom_minimum_size = Vector2(44, 0)
	lead_row.add_child(_chain_lead_value)
	_chain_lead.value_changed.connect(func(v: float): _chain_lead_value.text = "%.2f" % v)
	_chain_button = Button.new()
	_chain_button.text = "두 동작 이어보기"
	_chain_button.tooltip_text = "두 내장 제스처를 이어서 미리 봅니다. 저장되지 않습니다."
	_chain_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chain_button.pressed.connect(_request_preview_sequence)
	lead_row.add_child(_chain_button)
	_refresh_sequence_options()

	inner.add_child(_section("시퀀스 만들기 (프리셋 조합)"))
	var seq_btns := HBoxContainer.new()
	inner.add_child(seq_btns)
	var add := Button.new()
	add.text = "+ 현재 설정 추가"
	add.pressed.connect(_add_sequence_step)
	seq_btns.add_child(add)
	var remove := Button.new()
	remove.text = "선택 삭제"
	remove.pressed.connect(func():
		for idx in _sequence_list.get_selected_items():
			_sequence.remove_at(idx)
			break
		_refresh_sequence_list())
	seq_btns.add_child(remove)
	var clear := Button.new()
	clear.text = "비우기"
	clear.pressed.connect(func():
		_sequence.clear()
		_refresh_sequence_list())
	seq_btns.add_child(clear)
	_sequence_list = ItemList.new()
	_sequence_list.custom_minimum_size = Vector2(0, 70)
	inner.add_child(_sequence_list)
	var seq_save := HBoxContainer.new()
	inner.add_child(seq_save)
	_sequence_name = LineEdit.new()
	_sequence_name.placeholder_text = "이름 (영문/숫자/_)"
	_sequence_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seq_save.add_child(_sequence_name)
	var seq_prev := Button.new()
	seq_prev.text = "미리보기"
	seq_prev.pressed.connect(func():
		var m := _compose_sequence()
		if not m.is_empty():
			preview_motion.emit(m))
	seq_save.add_child(seq_prev)
	var seq_put := Button.new()
	seq_put.text = "저장"
	seq_put.tooltip_text = "PUT /motions/{id} 로 저장되어 다음부터 프리셋과 서버 제스처로 사용됩니다"
	seq_put.pressed.connect(func():
		var m := _compose_sequence()
		if not m.is_empty():
			save_motion.emit(m))
	seq_save.add_child(seq_put)

	inner.add_child(_section("키프레임 편집 (본 · 시간 · 각도°)"))
	var kf_row1 := HBoxContainer.new()
	inner.add_child(kf_row1)
	_kf_bone = OptionButton.new()
	for b in MotionBank.EDITOR_BONES:
		_kf_bone.add_item(b)
	_kf_bone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kf_row1.add_child(_kf_bone)
	kf_row1.add_child(_label("t"))
	_kf_time = _spin(0.0, 20.0, 0.05, 0.5)
	kf_row1.add_child(_kf_time)
	# x/y/z share one row and stretch; the add button lives on the next row so the three
	# spin boxes (each ~90 px with arrows) never push the panel past PANEL_WIDTH.
	var kf_row2 := HBoxContainer.new()
	inner.add_child(kf_row2)
	_kf_x = _spin(-90, 90, 1, 0)
	_kf_x.prefix = "x"
	kf_row2.add_child(_kf_x)
	_kf_y = _spin(-90, 90, 1, 0)
	_kf_y.prefix = "y"
	kf_row2.add_child(_kf_y)
	_kf_z = _spin(-90, 90, 1, 0)
	_kf_z.prefix = "z"
	kf_row2.add_child(_kf_z)
	_kf_list = ItemList.new()
	_kf_list.custom_minimum_size = Vector2(0, 70)
	inner.add_child(_kf_list)
	var kf_row3 := HBoxContainer.new()
	inner.add_child(kf_row3)
	var kf_add := Button.new()
	kf_add.text = "+ 키"
	kf_add.pressed.connect(_add_keyframe)
	kf_row3.add_child(kf_add)
	var kf_del := Button.new()
	kf_del.text = "선택 삭제"
	kf_del.pressed.connect(func():
		for idx in _kf_list.get_selected_items():
			_keyframes.remove_at(idx)
			break
		_refresh_keyframe_list())
	kf_row3.add_child(kf_del)
	kf_row3.add_child(_label("길이(초)"))
	_kf_duration = _spin(0.5, 20.0, 0.1, 3.0)
	kf_row3.add_child(_kf_duration)
	var kf_save := HBoxContainer.new()
	inner.add_child(kf_save)
	_kf_name = LineEdit.new()
	_kf_name.placeholder_text = "이름 (영문/숫자/_)"
	_kf_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kf_save.add_child(_kf_name)
	var kf_prev := Button.new()
	kf_prev.text = "미리보기"
	kf_prev.pressed.connect(func():
		var m := _compose_keyframes()
		if not m.is_empty():
			preview_motion.emit(m))
	kf_save.add_child(kf_prev)
	var kf_put := Button.new()
	kf_put.text = "저장"
	kf_put.pressed.connect(func():
		var m := _compose_keyframes()
		if not m.is_empty():
			save_motion.emit(m))
	kf_save.add_child(kf_put)
	_motion_result = Label.new()
	_motion_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motion_result.add_theme_font_size_override("font_size", 11)
	inner.add_child(_motion_result)


func _build_work_tab() -> void:
	var v := _tab("작업")
	_job_workspace = Label.new()
	_job_workspace.text = "작업 폴더/모드: 서버 정보 대기"
	_job_workspace.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_workspace.add_theme_font_size_override("font_size", 11)
	v.add_child(_job_workspace)
	_job_prompt = TextEdit.new()
	_job_prompt.placeholder_text = "백그라운드 작업 지시 (codex exec). 대화와 별개로 명시적으로 실행됩니다."
	_job_prompt.custom_minimum_size = Vector2(0, 70)
	_job_prompt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	v.add_child(_job_prompt)
	var row := HBoxContainer.new()
	v.add_child(row)
	_job_start = Button.new()
	_job_start.text = "작업 시작"
	_job_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_start.pressed.connect(func():
		var p := _job_prompt.text.strip_edges()
		if not p.is_empty():
			job_start.emit(p))
	row.add_child(_job_start)
	_job_cancel = Button.new()
	_job_cancel.text = "취소"
	_job_cancel.disabled = true
	_job_cancel.pressed.connect(func(): job_cancel.emit())
	row.add_child(_job_cancel)
	_job_status = Label.new()
	_job_status.text = "작업 없음"
	v.add_child(_job_status)
	_job_log = RichTextLabel.new()
	_job_log.scroll_following = true
	_job_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_job_log.custom_minimum_size = Vector2(0, 120)
	_job_log.selection_enabled = true
	_job_log.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), 8))
	_job_log.add_theme_font_size_override("normal_font_size", 11)
	v.add_child(_job_log)


func _build_settings_tab() -> void:
	var v := _tab("설정")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)

	inner.add_child(_section("백엔드"))
	var row := HBoxContainer.new()
	inner.add_child(row)
	_backend_edit = LineEdit.new()
	_backend_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backend_edit.text_submitted.connect(func(t: String): backend_changed.emit(t))
	row.add_child(_backend_edit)
	var apply := Button.new()
	apply.text = "적용"
	apply.pressed.connect(func(): backend_changed.emit(_backend_edit.text))
	row.add_child(apply)
	_backend_source = Label.new()
	_backend_source.add_theme_font_size_override("font_size", 11)
	inner.add_child(_backend_source)

	inner.add_child(_section("마이크 (noAEC)"))
	var th_row := HBoxContainer.new()
	inner.add_child(th_row)
	th_row.add_child(_label("VAD 임계값"))
	_vad_threshold = HSlider.new()
	_vad_threshold.min_value = 0.005
	_vad_threshold.max_value = 0.2
	_vad_threshold.step = 0.005
	_vad_threshold.value = float(_setting("vad_threshold", 0.035))
	_vad_threshold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vad_threshold.value_changed.connect(func(val: float):
		_vad_threshold_value.text = "%.3f" % val
		setting_changed.emit("vad_threshold", val))
	th_row.add_child(_vad_threshold)
	_vad_threshold_value = Label.new()
	_vad_threshold_value.text = "%.3f" % _vad_threshold.value
	th_row.add_child(_vad_threshold_value)
	var dev_row := HBoxContainer.new()
	inner.add_child(dev_row)
	dev_row.add_child(_label("입력 장치"))
	_mic_device = OptionButton.new()
	_mic_device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mic_device.item_selected.connect(func(i: int): setting_changed.emit("mic_device", _mic_device.get_item_text(i)))
	dev_row.add_child(_mic_device)
	var rate_row := HBoxContainer.new()
	inner.add_child(rate_row)
	rate_row.add_child(_label("전송 샘플레이트"))
	_mic_rate = OptionButton.new()
	_mic_rate.add_item("원본 (믹스 레이트)", 0)
	_mic_rate.add_item("16000 Hz 다운샘플", 16000)
	_mic_rate.add_item("24000 Hz 다운샘플", 24000)
	_mic_rate.tooltip_text = "백엔드가 레이트를 처리하므로 다운샘플은 선택 사항입니다"
	_mic_rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var saved_rate := int(_setting("mic_target_rate", 0))
	for i in _mic_rate.item_count:
		if _mic_rate.get_item_id(i) == saved_rate:
			_mic_rate.select(i)
	_mic_rate.item_selected.connect(func(i: int): setting_changed.emit("mic_target_rate", _mic_rate.get_item_id(i)))
	rate_row.add_child(_mic_rate)

	inner.add_child(_section("표시"))
	_scale_slider = _slider_row(inner, "펫 크기", AutonomyBridge.SCALE_MIN, AutonomyBridge.SCALE_MAX, AutonomyBridge.SCALE_WHEEL_STEP,
		AutonomyBridge.clamp_scale(float(_setting("pet_scale", AutonomyBridge.SCALE_DEFAULT))), "pet_scale")
	_scale_slider.tooltip_text = "펫 위에서 마우스 휠로도 조절됩니다 (드래그 중에는 무시). 발/엉덩이 접점을 기준으로 커지므로 지지면에서 미끄러지지 않습니다."
	_volume_slider = _slider_row(inner, "음량(dB)", -30.0, 6.0, 1.0, float(_setting("volume_db", 0.0)), "volume_db")
	var gaze := CheckButton.new()
	gaze.text = "마우스 시선 추적"
	gaze.button_pressed = bool(_setting("idle_gaze", true))
	gaze.toggled.connect(func(on: bool): setting_changed.emit("idle_gaze", on))
	inner.add_child(gaze)
	var subs := CheckButton.new()
	subs.text = "펫 모드 자막 표시"
	subs.button_pressed = bool(_setting("show_subtitles", true))
	subs.toggled.connect(func(on: bool): setting_changed.emit("show_subtitles", on))
	inner.add_child(subs)
	inner.add_child(_section("자율 이동 (펫 모드)"))
	_autonomy_check = CheckButton.new()
	_autonomy_check.text = "자율 산책 (패널 닫힘 시)"
	_autonomy_check.tooltip_text = "펫 모드에서만 화면 안을 천천히 돌아다닙니다. 패널이 열려 있거나 녹음/말하기/드래그/대화 중이면 항상 멈춥니다. 화면 내용을 읽지 않습니다."
	_autonomy_check.button_pressed = bool(_setting("autonomy_enabled", true))
	_autonomy_check.toggled.connect(func(on: bool): setting_changed.emit("autonomy_enabled", on))
	inner.add_child(_autonomy_check)
	_autonomy_speed = _slider_row(inner, "이동 속도", 20.0, 160.0, 5.0, float(_setting("autonomy_speed", 75.0)), "autonomy_speed")
	_autonomy_state = Label.new()
	_autonomy_state.text = "상태: 일시정지"
	_autonomy_state.add_theme_font_size_override("font_size", 11)
	_autonomy_state.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(_autonomy_state)
	_surface_check = CheckButton.new()
	_surface_check.text = "표면 걷기 (창 위 · 작업 표시줄)"
	_surface_check.tooltip_text = "보이는 창의 윗변과 작업 표시줄 바닥 위를 가로로 걷고 가장자리에 앉습니다. 창의 위치/크기만 읽고 내용은 읽지 않습니다 (Windows). 끄면 화면 안을 자유롭게 떠다닙니다."
	_surface_check.button_pressed = bool(_setting("surface_roam", true))
	_surface_check.toggled.connect(func(on: bool): setting_changed.emit("surface_roam", on))
	inner.add_child(_surface_check)
	var sit_row := HBoxContainer.new()
	inner.add_child(sit_row)
	_sit_button = Button.new()
	_sit_button.text = "앉기 · 펫 모드"
	_sit_button.tooltip_text = "패널을 닫고, 마우스가 멀어지면 현재 지지면에 앉습니다. 앉아 있는 동안 산책은 멈추고 일어서면 다시 움직입니다."
	_sit_button.disabled = true
	_sit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sit_button.pressed.connect(func(): sit_requested.emit(not _sitting))
	sit_row.add_child(_sit_button)
	_surface_status = Label.new()
	_surface_status.text = "표면 걷기: 대기"
	_surface_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_surface_status.add_theme_font_size_override("font_size", 11)
	_surface_status.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(_surface_status)
	var idle_row := HBoxContainer.new()
	inner.add_child(idle_row)
	idle_row.add_child(_label("대기 동작"))
	_idle_clip_option = OptionButton.new()
	_idle_clip_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_idle_clip_option.fit_to_longest_item = false # long clip descriptions must not widen the panel
	_idle_clip_option.clip_text = true
	_idle_clip_option.tooltip_text = "가만히 있을 때 몸이 어떻게 숨 쉬고 움직일지 고릅니다. 자동은 캐릭터에 맞는 동작을 씁니다. 시선·제스처는 그 위에 겹쳐집니다. 모든 동작은 모션 탭에서 미리 볼 수 있습니다."
	_idle_choice = str(_setting("idle_clip", "auto"))
	_idle_clip_option.item_selected.connect(func(i: int):
		_idle_choice = str(_idle_clip_option.get_item_metadata(i))
		setting_changed.emit("idle_clip", _idle_choice))
	idle_row.add_child(_idle_clip_option)
	_refresh_idle_clip_option()
	var btn_row := HBoxContainer.new()
	inner.add_child(btn_row)
	var reset_pos := Button.new()
	reset_pos.text = "창 위치 초기화"
	reset_pos.pressed.connect(func(): setting_changed.emit("reset_window", true))
	btn_row.add_child(reset_pos)
	var reload := Button.new()
	reload.text = "아바타 다시 받기"
	reload.tooltip_text = "캐시를 무시하고 백엔드에서 VRM을 다시 내려받습니다"
	reload.pressed.connect(func(): reload_avatar_requested.emit())
	btn_row.add_child(reload)
	_avatar_label = Label.new()
	_avatar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_avatar_label.add_theme_font_size_override("font_size", 11)
	inner.add_child(_avatar_label)
	_audio_stats = Label.new()
	_audio_stats.add_theme_font_size_override("font_size", 11)
	_audio_stats.modulate = Color(0.7, 0.7, 0.78)
	inner.add_child(_audio_stats)
	var about := Label.new()
	about.text = "설정 저장 위치: " + ProjectSettings.globalize_path("user://")
	about.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	about.add_theme_font_size_override("font_size", 10)
	about.modulate = Color(0.6, 0.6, 0.66)
	inner.add_child(about)


# ------------------------------------------------------------- small helpers

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.modulate = Color(0.78, 0.7, 0.95)
	return l


func _spin(minv: float, maxv: float, step: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL # share the row instead of demanding 64 px each
	return s


func _slider_row(parent: Control, text: String, minv: float, maxv: float, step: float, val: float, key: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(text)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := Label.new()
	v.text = "%.2f" % val
	v.custom_minimum_size = Vector2(44, 0)
	row.add_child(v)
	s.set_meta("value_label", v)
	s.value_changed.connect(func(nv: float):
		v.text = "%.2f" % nv
		setting_changed.emit(key, nv))
	return s


func _submit_text() -> void:
	var t := _input.text.strip_edges()
	if t.is_empty():
		return
	_input.clear()
	send_text.emit(t)


func _selected_preset() -> String:
	if _preset_option.item_count == 0 or _preset_option.selected < 0:
		return "idle"
	var meta: Variant = _preset_option.get_item_metadata(_preset_option.selected)
	return str(meta) if typeof(meta) == TYPE_STRING and not str(meta).is_empty() else _preset_option.get_item_text(_preset_option.selected)


func is_vrma_selected() -> bool:
	return vrma_clips.has(_selected_preset()) and not bank.has_motion(_selected_preset())


func _add_sequence_step() -> void:
	if is_vrma_selected():
		# VRMA data is a read-only clip: it has no Euler tracks to splice, so the composers
		# refuse it instead of inventing empty keyframes.
		set_motion_result("VRMA 클립 '%s' 은 읽기 전용입니다: 미리보기/속도만 가능, 시퀀스·키프레임 편집 불가" % _selected_preset(), false)
		return
	if _sequence.size() >= MotionBank.MAX_STEPS:
		set_motion_result("시퀀스는 최대 %d단계" % MotionBank.MAX_STEPS, false)
		return
	_sequence.append({"name": _selected_preset(), "intensity": _intensity.value, "speed": _speed.value, "repeat": int(_repeat.value)})
	_refresh_sequence_list()


func _refresh_sequence_list() -> void:
	_sequence_list.clear()
	for s in _sequence:
		_sequence_list.add_item("%s  ×%.2f  v%.2f  r%d" % [s["name"], s["intensity"], s["speed"], s["repeat"]])


func _compose_sequence() -> Dictionary:
	var name := _sequence_name.text.strip_edges()
	if name.is_empty() or not name.is_valid_ascii_identifier():
		set_motion_result("이름은 영문/숫자/_ 로 시작 (예: greet_combo)", false)
		return {}
	var errs: Array[String] = []
	var m := bank.compose_sequence(name, _sequence, errs)
	if m.is_empty():
		set_motion_result("시퀀스 오류: " + ", ".join(errs), false)
		return {}
	set_motion_result("시퀀스 %s: %.1f초, %d 트랙" % [name, m["duration"], m["tracks"].size()], true)
	return m


func _add_keyframe() -> void:
	if _keyframes.size() >= KEYFRAME_MAX:
		set_motion_result("키프레임은 최대 %d개" % KEYFRAME_MAX, false)
		return
	_keyframes.append({"bone": _kf_bone.get_item_text(_kf_bone.selected), "time": _kf_time.value, "x": _kf_x.value, "y": _kf_y.value, "z": _kf_z.value})
	_keyframes.sort_custom(func(a, b): return a["time"] < b["time"] if a["bone"] == b["bone"] else a["bone"] < b["bone"])
	_refresh_keyframe_list()


func _refresh_keyframe_list() -> void:
	_kf_list.clear()
	for k in _keyframes:
		_kf_list.add_item("%s  t=%.2f  (%d, %d, %d)" % [k["bone"], k["time"], int(k["x"]), int(k["y"]), int(k["z"])])


func _compose_keyframes() -> Dictionary:
	var name := _kf_name.text.strip_edges()
	if name.is_empty() or not name.is_valid_ascii_identifier():
		set_motion_result("이름은 영문/숫자/_ 로 시작 (예: my_wave)", false)
		return {}
	var errs: Array[String] = []
	var m := MotionBank.from_keyframes(name, _kf_duration.value, _keyframes, errs)
	if m.is_empty():
		set_motion_result("키프레임 오류: " + ", ".join(errs), false)
		return {}
	set_motion_result("키프레임 %s: %.1f초, %d 트랙 (시작/끝은 자동으로 0)" % [name, m["duration"], m["tracks"].size()], true)
	return m


# ------------------------------------------------------------- host-facing API

func set_connection(state: String, detail: String = "") -> void:
	match state:
		"open":
			_conn_dot.color = Color(0.35, 0.85, 0.45)
			_conn_label.text = "연결됨"
		"connecting":
			_conn_dot.color = Color(0.95, 0.75, 0.3)
			_conn_label.text = "연결 중…"
		_:
			_conn_dot.color = Color(0.85, 0.35, 0.35)
			_conn_label.text = "연결 끊김" if detail.is_empty() else "연결 끊김 (%s)" % detail


func set_activity(activity: String) -> void:
	var names := {"idle": "대기", "listening": "듣는 중", "thinking": "생각 중", "speaking": "말하는 중"}
	_activity_label.text = "· " + str(names.get(activity, activity))
	_cancel_button.disabled = activity == "idle"


func set_input_mode(mode: String) -> void:
	_mode_label.text = "· " + mode


func set_mic_level(level: float) -> void:
	_level_bar.value = clampf(level * 6.0, 0.0, 1.0)


func set_recording(active: bool, source: String) -> void:
	_mic_button.text = ("● 녹음 중 (%s)" % ("PTT" if source == "ptt" else "VAD")) if active else "🎤 말하기 (F9)"
	_mic_button.modulate = Color(1.0, 0.6, 0.6) if active else Color.WHITE


func set_vad_enabled(enabled: bool) -> void:
	_vad_check.set_pressed_no_signal(enabled)


func set_status_message(text: String) -> void:
	_status_line.text = text


func set_characters(characters: Array, current: String) -> void:
	_character_option.clear()
	var profile_loop := ""
	for c in characters:
		var id := str(c.get("id", ""))
		_character_option.add_item(str(c.get("name", id)))
		_character_option.set_item_metadata(_character_option.item_count - 1, id)
		if id == current:
			_character_option.select(_character_option.item_count - 1)
			profile_loop = str(c.get("ambient_loop", "")) if typeof(c.get("ambient_loop", "")) == TYPE_STRING else ""
	set_idle_profile(profile_loop)
	for character in characters:
		if str(character.get("id","")) == current:
			set_avatar_variants(character.get("avatar_variants",[]),_avatar_variant_id)
			break


## Selection changes this character's model only; mood tags describe variants,
## never trigger automatic identity, voice or arbitrary behavior changes.
func set_avatar_variants(entries: Array, current: String = "default") -> void:
	_avatar_variant_rows = entries.duplicate(true)
	if _avatar_variant_rows.is_empty():
		_avatar_variant_rows = [{"id":"default","label":"기본 외형","avatar_available":true}]
	_avatar_variant_option.clear()
	var selected := 0
	for row in _avatar_variant_rows:
		var id := str(row.get("id","default"))
		var label := str(row.get("label",id))
		if id == "default" and label == "Default": label = "기본 외형"
		_avatar_variant_option.add_item(label)
		var index := _avatar_variant_option.item_count-1
		_avatar_variant_option.set_item_metadata(index,id)
		_avatar_variant_option.set_item_disabled(index,not bool(row.get("avatar_available",true)))
		_avatar_variant_option.set_item_tooltip(index,str(row.get("description","")))
		if id == current: selected = index
	_avatar_variant_option.select(selected)
	_avatar_variant_id = str(_avatar_variant_option.get_selected_metadata())
	_avatar_variant_option.disabled = _avatar_variant_rows.size() <= 1
	_refresh_avatar_variant_note()


func _refresh_avatar_variant_note() -> void:
	var description := "외형을 바꿔도 대화와 목소리는 유지됩니다."
	for row in _avatar_variant_rows:
		if str(row.get("id","")) != _avatar_variant_id: continue
		var detail := str(row.get("description",""))
		var moods: Array = row.get("mood_tags",[])
		if not detail.is_empty(): description = detail
		if not moods.is_empty(): description += " · " + ", ".join(PackedStringArray(moods))
	_avatar_variant_note.text = description


func set_bank(new_bank: MotionBank) -> void:
	bank = new_bank if new_bank != null else MotionBank.new()
	_refresh_preset_option()
	_refresh_sequence_options()


## Built-in bank gestures that can be chained: finite duration, real tracks, not the procedural
## idle, not custom/saved motions, not contact/support poses (sit/seat/prop/...), never VRMA clips.
func sequence_candidates() -> Array[String]:
	var out: Array[String] = []
	if bank == null:
		return out
	for n in bank.names():
		var name := str(n)
		var m := bank.get_motion(name)
		if name == "idle" or bool(m.get("custom", false)) or bool(m.get("loop", false)):
			continue
		var d := float(m.get("duration", 0.0))
		if not is_finite(d) or d <= 0.0:
			continue
		var tracks: Variant = m.get("tracks", [])
		if typeof(tracks) != TYPE_ARRAY or tracks.is_empty():
			continue
		var lower := name.to_lower()
		var excluded := false
		for w in SEQUENCE_EXCLUDED_WORDS:
			if lower.contains(w):
				excluded = true
		if excluded:
			continue
		out.append(name)
	return out


func _refresh_sequence_options() -> void:
	if _chain_first == null:
		return
	var prev_first := _chain_selected(_chain_first)
	var prev_second := _chain_selected(_chain_second)
	var names := sequence_candidates()
	for opt in [_chain_first, _chain_second]:
		opt.clear()
		for n in names:
			opt.add_item(n)
			opt.set_item_metadata(opt.item_count - 1, n)
			opt.set_item_tooltip(opt.item_count - 1, "%.1f초" % float(bank.get_motion(n).get("duration", 0.0)))
	_chain_select(_chain_first, prev_first, 0)
	_chain_select(_chain_second, prev_second, mini(1, names.size() - 1))
	var usable := names.size() >= 1
	_chain_first.disabled = not usable
	_chain_second.disabled = not usable
	_chain_lead.editable = usable
	_chain_button.disabled = not usable
	_chain_button.tooltip_text = "두 내장 제스처를 이어서 미리 봅니다. 저장되지 않습니다." if usable else "이어볼 내장 제스처가 없습니다 (뱅크를 새로고침하세요)"


static func _chain_selected(opt: OptionButton) -> String:
	if opt == null or opt.item_count == 0 or opt.selected < 0:
		return ""
	return str(opt.get_item_metadata(opt.selected))


static func _chain_select(opt: OptionButton, wanted: String, fallback_index: int) -> void:
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == wanted:
			opt.select(i)
			return
	if opt.item_count > 0:
		opt.select(clampi(fallback_index, 0, opt.item_count - 1))


func sequence_selection() -> Dictionary:
	return {"first": _chain_selected(_chain_first), "second": _chain_selected(_chain_second), "lead": snappedf(clampf(_chain_lead.value, 0.0, 1.0), 0.01)}


func _request_preview_sequence() -> void:
	var sel := sequence_selection()
	var first := str(sel["first"])
	var second := str(sel["second"])
	var allowed := sequence_candidates()
	if first.is_empty() or second.is_empty() or not allowed.has(first) or not allowed.has(second):
		set_motion_result("이어볼 두 동작을 고르세요 (내장 제스처만 가능)", false)
		return
	set_motion_result("이어보기: %s → %s (겹침 %.2f초)" % [first, second, float(sel["lead"])], true)
	preview_sequence.emit(first, second, float(sel["lead"]))


## Imported VRMA clips that MotionPlayer accepted (name -> catalog entry with duration/loop/
## description). They join the preset list after the bank entries; bank names win duplicates
## (same rule as the backend's LLM allow-list).
func set_vrma_clips(clips: Dictionary) -> void:
	vrma_clips = clips.duplicate()
	_refresh_preset_option()
	_refresh_idle_clip_option()


func preset_names() -> Array[String]:
	var names: Array[String] = bank.names()
	for n in vrma_clips.keys():
		if not bank.has_motion(str(n)) and not _contextual_clip(str(n)):
			names.append(str(n))
	return names


## These assets remain loaded for seating/navigation owners. Starting them as
## standalone gestures would bypass their contact and travel prerequisites.
func _contextual_clip(name: String) -> bool:
	var entry: Dictionary = vrma_clips.get(name,{})
	return name in ["sit_enter","sit_exit","sit_idle"] or not str(entry.get("seated_transition","")).is_empty() \
		or not entry.get("locomotion_style",{}).is_empty()


func _refresh_preset_option() -> void:
	var prev := _selected_preset()
	_preset_option.clear()
	for n in preset_names():
		var i := _preset_option.item_count
		if bank.has_motion(n):
			var m := bank.get_motion(n)
			_preset_option.add_item(n + (" ★" if m.get("custom", false) else ""))
			_preset_option.set_item_tooltip(i, "뱅크 프리셋 (편집 가능)" if not m.get("custom", false) else "저장된 커스텀 모션")
		else:
			var e: Dictionary = vrma_clips[n]
			_preset_option.add_item("%s  ⟐ VRMA %.1fs%s" % [n, float(e.get("duration", 0.0)), " ↻" if bool(e.get("loop", false)) else ""])
			# Manifest wording only; the panel never relabels a clip.
			_preset_option.set_item_tooltip(i, str(e.get("description", "")) + "\n읽기 전용 클립 · 미리보기/속도만")
		_preset_option.set_item_metadata(i, n)
	for i in _preset_option.item_count:
		if str(_preset_option.get_item_metadata(i)) == prev:
			_preset_option.select(i)


## Imported clips that may serve as a calm ambient idle: catalogue entries flagged ambient AND
## loop, the legacy idle_natural clip, and the current character's declared ambient_loop. A walk,
## dance or prop clip is never advertised as an idle just because it loops. Sorted by name.
func idle_candidates() -> Array[String]:
	var out: Array[String] = []
	for n in vrma_clips.keys():
		var name := str(n)
		if _contextual_clip(name): continue
		var e: Dictionary = vrma_clips[n] if typeof(vrma_clips[n]) == TYPE_DICTIONARY else {}
		var flagged := bool(e.get("ambient", false)) and bool(e.get("loop", false))
		if flagged or AutonomyBridge.AMBIENT_IDLE_CLIPS.has(name) or (not _idle_profile_loop.is_empty() and name == _idle_profile_loop):
			out.append(name)
	out.sort()
	return out


## Friendly label for a clip: manifest description (never relabelled) with the name for lookup.
static func idle_clip_label(name: String, entry: Dictionary) -> String:
	var desc := str(entry.get("description", "")).strip_edges()
	if desc.is_empty():
		return name
	if desc.length() > 28:
		desc = desc.left(27).strip_edges() + "…"
	return "%s (%s)" % [desc, name]


## Rebuild the "대기 동작" dropdown around the saved choice without emitting. Items: 자동, 기본 호흡만,
## every eligible imported clip; a saved clip that is not loaded (yet / any more) stays selected as a
## placeholder so a catalogue refresh or missing download never changes the user's setting.
func _refresh_idle_clip_option() -> void:
	if _idle_clip_option == null:
		return
	_idle_clip_option.clear()
	var auto_text := "자동 (캐릭터에 맞게)"
	var profile_loaded := not _idle_profile_loop.is_empty() and vrma_clips.has(_idle_profile_loop)
	if profile_loaded:
		auto_text = "자동 · " + idle_clip_label(_idle_profile_loop, vrma_clips[_idle_profile_loop])
	elif not _idle_profile_loop.is_empty():
		auto_text = "자동 (캐릭터 동작 준비 중)"
	_idle_clip_option.add_item(auto_text)
	_idle_clip_option.set_item_metadata(0, "auto")
	_idle_clip_option.set_item_tooltip(0, ("이 캐릭터의 기본 대기 동작 '%s' 을 씁니다" % _idle_profile_loop) if profile_loaded else "캐릭터 기본 동작이 준비되면 자동으로 씁니다. 그때까지는 기본 호흡만 합니다.")
	_idle_clip_option.add_item("기본 호흡만 (클립 없음)")
	_idle_clip_option.set_item_metadata(1, "")
	_idle_clip_option.set_item_tooltip(1, "가져온 동작 없이 잔잔한 호흡·시선만 합니다")
	var candidates := idle_candidates()
	for name in candidates:
		var i := _idle_clip_option.item_count
		var e: Dictionary = vrma_clips[name]
		_idle_clip_option.add_item(idle_clip_label(name, e))
		_idle_clip_option.set_item_metadata(i, name)
		_idle_clip_option.set_item_tooltip(i, "%s\n%.1f초 반복 · 시선/제스처와 겹쳐 재생" % [str(e.get("description", "")), float(e.get("duration", 0.0))])
	var selected := -1
	for i in _idle_clip_option.item_count:
		if str(_idle_clip_option.get_item_metadata(i)) == _idle_choice:
			selected = i
	if selected < 0:
		# Saved clip not loaded: keep the choice visible and selected, never silently switch.
		selected = _idle_clip_option.item_count
		_idle_clip_option.add_item("%s (아직 없음)" % _idle_choice)
		_idle_clip_option.set_item_metadata(selected, _idle_choice)
		_idle_clip_option.set_item_tooltip(selected, "저장된 대기 동작이 아직 내려받아지지 않았거나 목록에서 빠졌습니다. 준비되면 자동으로 쓰입니다.")
	_idle_clip_option.select(selected)
	_idle_clip_option.disabled = false


## Mirror the idle_clip setting from the host (e.g. after a reset) without emitting.
func set_idle_clip(value: String) -> void:
	_idle_choice = value
	_refresh_idle_clip_option()


func idle_clip() -> String:
	return _idle_choice


## Current character's declared ambient_loop (character catalogue); "" when none. Drives the
## "자동" label only; the host resolves the actual loop.
func set_idle_profile(loop_name: String) -> void:
	if loop_name == _idle_profile_loop:
		return
	_idle_profile_loop = loop_name
	_refresh_idle_clip_option()


func idle_profile() -> String:
	return _idle_profile_loop


## Readable roaming state for the settings tab ("산책 중", "살펴보는 중", "쉬는 중", ...).
func set_autonomy_state(text: String) -> void:
	_autonomy_state.text = "상태: " + text


## Surface-mode status (world source availability, window count). Geometry only, never contents.
func set_surface_status(text: String) -> void:
	_surface_status.text = text


## Sit/stand button: enabled only when the host says a sit is possible (attached support + clip)
## or the pet is already seated (standing up is always allowed).
func set_sit_state(can_sit: bool, sitting: bool) -> void:
	_sitting = sitting
	_sit_button.disabled = not can_sit
	_sit_button.text = "일어서기" if sitting else "앉기 · 펫 모드"


func is_sitting() -> bool:
	return _sitting


## Scale changed outside the slider (mouse wheel over the pet): mirror it without re-emitting.
func set_pet_scale(value: float) -> void:
	_scale_slider.set_value_no_signal(value)
	var label := _scale_slider.get_meta("value_label") as Label
	if label:
		label.text = "%.2f" % _scale_slider.value


func pet_scale() -> float:
	return _scale_slider.value


func set_motion_result(text: String, ok: bool) -> void:
	_motion_result.text = text
	_motion_result.modulate = Color(0.6, 0.95, 0.65) if ok else Color(1.0, 0.6, 0.6)


func append_transcript(role: String, text: String) -> void:
	var color := "#9fd3ff" if role == "user" else ("#ffd3a0" if role == "system" else "#f4e3ff")
	var who: String = {"user": "트레이너", "assistant": "캐릭터", "system": "시스템"}.get(role, role)
	_transcript.append_text("[color=%s][b]%s[/b][/color] %s\n" % [color, who, text.replace("[", "[lb]")])


var _live_line_open := false
func update_live_reply(text: String, final: bool) -> void:
	if _live_line_open:
		_transcript.remove_paragraph(_transcript.get_paragraph_count() - 1)
		_transcript.remove_paragraph(_transcript.get_paragraph_count() - 1)
	_transcript.append_text("[color=#f4e3ff][b]캐릭터[/b][/color] %s%s\n" % [text.replace("[", "[lb]"), "" if final else " ▌"])
	_live_line_open = not final


func set_job(job: Dictionary) -> void:
	if job.is_empty():
		_job_status.text = "작업 없음"
		_job_cancel.disabled = true
		_job_start.disabled = false
		return
	var status := str(job.get("status", ""))
	var names := {"starting": "시작 중", "running": "실행 중", "completed": "완료", "failed": "실패", "cancelled": "취소됨", "cancelling": "취소 중"}
	_job_status.text = "%s · %s" % [names.get(status, status), str(job.get("message", ""))]
	if job.has("workspace") or job.has("sandbox"):
		_job_workspace.text = "작업 폴더/모드: 폴더 %s · 모드 %s" % [str(job.get("workspace", "?")), str(job.get("sandbox", "?"))]
	var active := not CompanionSession.JOB_TERMINAL.has(status)
	_job_cancel.disabled = not active
	_job_start.disabled = active
	_job_log.clear()
	_job_log.append_text("[color=#9fd3ff]지시:[/color] %s\n" % str(job.get("prompt", "")).replace("[", "[lb]"))
	for line in job.get("log", []):
		_job_log.append_text(str(line).replace("[", "[lb]") + "\n")


func set_job_workspace(text: String) -> void:
	_job_workspace.text = text


func set_backend(url: String, source: String) -> void:
	_backend_edit.text = url
	_backend_source.text = "출처: %s · WebSocket %s" % [source, SettingsScript.ws_url_for(url)]


func set_input_devices(devices: PackedStringArray, current: String) -> void:
	_mic_device.clear()
	for d in devices:
		_mic_device.add_item(d)
		if d == current:
			_mic_device.select(_mic_device.item_count - 1)


func set_avatar_info(text: String) -> void:
	_avatar_label.text = text


func set_audio_stats(stats: Dictionary) -> void:
	_audio_stats.text = "오디오 대기 %.1fs · 버퍼 %dms · 수신 %d · 무시 %d · 드롭 %d · %dHz" % [stats.get("pending_seconds", 0.0), stats.get("buffered_ms", 0), stats.get("accepted", 0), stats.get("stale", 0), stats.get("dropped_frames", 0), stats.get("rate", 0)]


# ------------------------------------------------------------- view tab API

func _view_sliders() -> Dictionary:
	return {"view_yaw_deg": _view_yaw, "view_pitch_deg": _view_pitch, "view_height": _view_height, "view_zoom": _view_zoom, "view_fov_deg": _view_fov, "view_distance_m": _view_distance}


func _refresh_view_projection() -> void:
	var perspective := str(_view_projection.get_selected_metadata()) == "perspective"
	for slider: HSlider in [_view_fov, _view_distance]:
		slider.editable = perspective
		slider.get_parent().modulate.a = 1.0 if perspective else 0.45
	_view_projection_note.text = "실제 거리와 깊이에 따라 크기와 겹침이 달라집니다." if perspective else "깊이가 달라도 같은 크기로 보입니다. 화각과 거리는 원근에서 조절합니다."


## Mirror host/saved view values without emitting (unknown keys ignored, values clamped to the
## slider range). Partial dictionaries only touch the keys given.
func set_view_settings(values: Dictionary) -> void:
	if values.get("view_projection", "") in ["orthographic", "perspective"]:
		_view_projection.select(1 if values["view_projection"] == "perspective" else 0)
		_refresh_view_projection()
	var sliders := _view_sliders()
	for key in values.keys():
		var s: HSlider = sliders.get(str(key), null)
		if s == null:
			continue
		var raw: Variant = values[key]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			continue
		var v := clampf(float(raw), s.min_value, s.max_value)
		if not is_finite(v):
			continue
		s.set_value_no_signal(v)
		(s.get_meta("value_label") as Label).text = str(s.get_meta("value_format")) % s.value


## Current view values: projection string and numeric camera controls.
func view_settings() -> Dictionary:
	var out := {"view_projection": str(_view_projection.get_selected_metadata())}
	for key in _view_sliders():
		out[key] = float((_view_sliders()[key] as HSlider).value)
	return out


## Reset is atomic: the host restores all seven defaults before projecting again,
## avoiding intermediate camera states that could invalidate an occupied seat.
func reset_view_settings() -> void:
	set_view_settings(VIEW_DEFAULTS)
	setting_changed.emit("view_reset", true)


# ------------------------------------------------------------- behavior tab API

## Readable "지금:" line for a queued/active intention. kind: "move_to" | "inspect" | "rest" | ""
## (free), label = the point's name. Product wording only; no protocol names.
static func behavior_state_text(kind: String, label: String, enabled: bool = true) -> String:
	if not enabled:
		return "스스로 행동 끔 · 산책만"
	match kind:
		"move_to":
			return ("'%s' 쪽으로 가는 중" % label) if not label.is_empty() else "어딘가로 가는 중"
		"inspect":
			return ("제자리에서 '%s' 살펴보는 중" % label) if not label.is_empty() else "제자리에서 살펴보는 중"
		"rest":
			return "쉬는 중"
	return "자유롭게 지내는 중"


## Host-supplied readable state (use behavior_state_text or any short sentence).
func set_behavior_state(text: String) -> void:
	_behavior_state.text = "지금: " + text


## Mirror the behavior_enabled setting without re-emitting.
func set_behavior_enabled(on: bool) -> void:
	_behavior_check.set_pressed_no_signal(on)
	if _behavior_state.text.begins_with("지금: 스스로 행동 끔") or not on:
		set_behavior_state(behavior_state_text("", "", on))


func behavior_enabled() -> bool:
	return _behavior_check.button_pressed


## Wire an InterestPoints manager: the list follows its changed signal, and add/rename/remove/
## marker toggles are applied to it directly (the *_requested signals still fire so the host can
## log or persist). point_go / point_inspect stay host decisions.
func bind_interest_points(manager: Node) -> void:
	if _points_manager != null and is_instance_valid(_points_manager):
		if _points_manager.changed.is_connected(_on_manager_changed):
			_points_manager.changed.disconnect(_on_manager_changed)
		if _points_manager.markers_changed.is_connected(_on_manager_markers_changed):
			_points_manager.markers_changed.disconnect(_on_manager_markers_changed)
	_points_manager = manager
	if manager != null:
		manager.changed.connect(_on_manager_changed)
		manager.markers_changed.connect(_on_manager_markers_changed)
		_on_manager_changed()
		_on_manager_markers_changed()


func _on_manager_changed() -> void:
	if _points_manager != null and is_instance_valid(_points_manager):
		set_interest_points(_points_manager.rows())


func _on_manager_markers_changed() -> void:
	if _points_manager == null or not is_instance_valid(_points_manager):
		return
	_markers_check.set_pressed_no_signal(_points_manager.markers_shown)
	_refresh_point_buttons()


## Rows [{id,label,status,status_text?,x?,y?}]; status "ready" | "parked" | anything else. Keeps
## the current selection by id. Without a bound manager this is the host's way to fill the list.
func set_interest_points(rows: Array) -> void:
	var prev := selected_point_id()
	_point_rows.clear()
	_point_list.clear()
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY or not r.has("id"):
			continue
		var row: Dictionary = r.duplicate()
		var status := str(row.get("status", "ready"))
		var status_text := str(row.get("status_text", InterestPoints.status_text(status)))
		_point_rows.append(row)
		var i := _point_list.item_count
		_point_list.add_item("%d. %s · %s" % [i + 1, str(row.get("label", row["id"])), status_text])
		_point_list.set_item_metadata(i, str(row["id"]))
		if status != "ready":
			_point_list.set_item_custom_fg_color(i, Color(0.8, 0.7, 0.5))
			_point_list.set_item_tooltip(i, "저장은 되어 있지만 지금 화면에 없는 자리입니다. 그 화면이 돌아오면 다시 갈 수 있습니다.")
		if str(row["id"]) == prev:
			_point_list.select(i)
	_refresh_point_buttons()


func interest_point_rows() -> Array[Dictionary]:
	return _point_rows.duplicate()


func selected_point_id() -> String:
	var sel := _point_list.get_selected_items()
	if sel.is_empty():
		return ""
	return str(_point_list.get_item_metadata(sel[0]))


func select_point(id: String) -> void:
	for i in _point_list.item_count:
		if str(_point_list.get_item_metadata(i)) == id:
			_point_list.select(i)
	_refresh_point_buttons()


func _selected_row() -> Dictionary:
	var id := selected_point_id()
	for r in _point_rows:
		if str(r["id"]) == id:
			return r
	return {}


func _refresh_point_buttons() -> void:
	var row := _selected_row()
	var has := not row.is_empty()
	var ready := has and str(row.get("status", "ready")) == "ready"
	_point_rename.disabled = not has
	_point_remove.disabled = not has
	_point_go.disabled = not ready
	_point_inspect.disabled = not ready
	_point_add.disabled = _point_rows.size() >= InterestPoints.MAX_POINTS
	var n := _point_rows.size()
	if n == 0:
		_point_hint.text = "지점이 없습니다. 이름을 적고 추가한 뒤 표식을 끌어 놓으세요."
	elif has and not ready:
		_point_hint.text = "'%s' 은(는) 지금 화면 밖에 있어 갈 수 없습니다. 표식을 다시 놓거나 그 화면을 연결하세요." % str(row.get("label", ""))
	elif n >= InterestPoints.MAX_POINTS:
		_point_hint.text = "지점이 가득 찼습니다 (%d개). 하나를 삭제하면 추가할 수 있습니다." % n
	elif _markers_check.button_pressed:
		var st: Dictionary = _points_manager.marker_status() if _points_manager != null and is_instance_valid(_points_manager) else {"ok": true}
		if bool(st.get("ok", false)):
			_point_hint.text = "표식을 끌어 놓으면 끝점 자리가 저장됩니다. 편집이 끝나면 '표식 보기'를 끄세요."
		else:
			_point_hint.text = "표식 창 사용 불가: " + str(st.get("reason", ""))
	else:
		_point_hint.text = "%d개 저장됨. 가보기는 그 자리까지 걸어가고, 살펴보기는 제자리에서 바라만 봅니다 (둘 다 패널이 닫힘)." % n


func _request_add_point() -> void:
	if _point_rows.size() >= InterestPoints.MAX_POINTS:
		_point_hint.text = "지점이 가득 찼습니다 (%d개)." % InterestPoints.MAX_POINTS
		return
	var label := _point_name.text.strip_edges()
	point_add_requested.emit(label)
	if _points_manager != null and is_instance_valid(_points_manager):
		var id: String = _points_manager.add_point(label)
		if id.is_empty():
			_point_hint.text = "지점을 추가할 수 없습니다."
			return
		_point_name.clear()
		select_point(id)
		# Adding is the start of editing: show the markers so the new pin can be dragged into place.
		if not _markers_check.button_pressed:
			_markers_check.button_pressed = true
		else:
			_points_manager.set_markers_visible(true)
	else:
		_point_name.clear()


func _request_rename_point() -> void:
	var id := selected_point_id()
	var label := _point_name.text.strip_edges()
	if id.is_empty() or label.is_empty():
		_point_hint.text = "바꿀 이름을 위 입력칸에 적은 뒤 누르세요."
		return
	point_rename_requested.emit(id, label)
	if _points_manager != null and is_instance_valid(_points_manager):
		_points_manager.rename_point(id, label)
	_point_name.clear()


func _request_remove_point() -> void:
	var id := selected_point_id()
	if id.is_empty():
		return
	point_remove_requested.emit(id)
	if _points_manager != null and is_instance_valid(_points_manager):
		_points_manager.remove_point(id)


func _on_markers_toggled(on: bool) -> void:
	markers_toggled.emit(on)
	if _points_manager != null and is_instance_valid(_points_manager):
		_points_manager.set_markers_visible(on)
	_refresh_point_buttons()


func markers_shown() -> bool:
	return _markers_check.button_pressed


# ------------------------------------------------------------- desktop living-space tab API

const OBJECT_VERB_LABELS := {"inspect": "살펴보기", "sit": "앉기", "use": "사용하기"}
const OBJECT_VERB_TIPS := {
	"inspect": "가구 옆으로 가서 바라봅니다",
	"sit": "가구 위에 앉는 자세를 취합니다",
	"use": "책상 앞에 앉아 사용하는 자세만 취합니다. 화면이나 파일을 읽지 않고 다른 프로그램을 조작하지 않습니다.",
}
const OBJECT_TYPE_LABELS := {"chair": "의자", "sofa": "소파", "computer": "컴퓨터 책상"}
const OBJECT_STATUS_TEXT := {
	"ready": "준비됨", "ok": "준비됨", "offscreen": "화면 밖", "parked": "화면 밖", "unreachable": "갈 수 없음",
	"unsupported": "아직 지원 안 함", "hidden": "숨김", "busy": "동작 중", "editing": "배치 편집 중",
}
const OBJECT_REASON_TEXT := {
	"offscreen": "가구가 화면 밖에 있습니다", "unreachable": "지금 자리에서 갈 수 없습니다",
	"unsupported": "이 가구에는 아직 지원되지 않는 동작입니다", "busy": "다른 동작이 진행 중입니다",
	"unknown_object": "그 가구가 없습니다", "unknown_verb": "알 수 없는 동작입니다", "hidden": "숨긴 가구입니다",
	"editing": "배치 편집 중에는 할 수 없습니다", "disabled": "스스로 행동이 꺼져 있습니다", "invalid": "요청이 올바르지 않습니다",
}


static func object_verb_label(verb: String) -> String:
	return str(OBJECT_VERB_LABELS.get(verb, verb))


static func object_type_label(type: String, catalogue: Array = []) -> String:
	for c in catalogue:
		if typeof(c) == TYPE_DICTIONARY and str(c.get("type", "")) == type and not str(c.get("label", "")).is_empty():
			return str(c["label"])
	return str(OBJECT_TYPE_LABELS.get(type, type))


static func object_status_text(status: String, fallback: String = "") -> String:
	if not fallback.is_empty():
		return fallback
	return str(OBJECT_STATUS_TEXT.get(status, status if not status.is_empty() else "준비됨"))


static func object_reason_text(reason: String) -> String:
	return str(OBJECT_REASON_TEXT.get(reason, reason))


## Wire the desktop objects host (Astra's DesktopObjects node; any Node with the same methods and
## `changed` / `status_changed` signals). The tab follows `changed`, and every control calls the
## host directly; nothing is persisted or moved by the panel. null unbinds and disables the tab.
func bind_desktop_objects(objects: Node) -> void:
	if _objects != null and is_instance_valid(_objects):
		if _objects.has_signal("changed") and _objects.changed.is_connected(_refresh_objects):
			_objects.changed.disconnect(_refresh_objects)
		if _objects.has_signal("status_changed") and _objects.status_changed.is_connected(set_desktop_object_status):
			_objects.status_changed.disconnect(set_desktop_object_status)
	_objects = objects
	if objects != null:
		if objects.has_signal("changed"):
			objects.changed.connect(_refresh_objects)
		if objects.has_signal("status_changed"):
			objects.status_changed.connect(set_desktop_object_status)
		set_desktop_object_status("준비됨")
	else:
		set_desktop_object_status("준비 안 됨")
	_refresh_objects()


func _objects_ok() -> bool:
	return _objects != null and is_instance_valid(_objects)


func desktop_object_rows() -> Array[Dictionary]:
	return _obj_rows.duplicate()


func desktop_object_catalogue() -> Array:
	return _obj_catalogue_data.duplicate()


func selected_object_id() -> String:
	var sel := _obj_list.get_selected_items()
	if sel.is_empty():
		return ""
	return str(_obj_list.get_item_metadata(sel[0]))


func select_object(id: String) -> void:
	for i in _obj_list.item_count:
		if str(_obj_list.get_item_metadata(i)) == id:
			_obj_list.select(i)
	_refresh_object_controls()


func selected_object_type() -> String:
	if _obj_catalogue.item_count == 0 or _obj_catalogue.selected < 0:
		return ""
	return str(_obj_catalogue.get_item_metadata(_obj_catalogue.selected))


## Concise host status ("status_changed" or an interaction result). Shown as "상태: …".
func set_desktop_object_status(text: String) -> void:
	_obj_status.text = "상태: " + text


func _selected_object_row() -> Dictionary:
	var id := selected_object_id()
	for r in _obj_rows:
		if str(r.get("id", "")) == id:
			return r
	return {}


## Rebuild catalogue + list from the host, keeping the selection by id and never re-emitting.
func _refresh_objects() -> void:
	if _obj_list == null:
		return
	var prev := selected_object_id()
	var prev_type := selected_object_type()
	_obj_rows.clear()
	_obj_catalogue_data.clear()
	_obj_catalogue.clear()
	_obj_list.clear()
	if _objects_ok():
		var cat: Variant = _objects.catalogue()
		if typeof(cat) == TYPE_ARRAY:
			for c in cat:
				if typeof(c) != TYPE_DICTIONARY or str(c.get("type", "")).is_empty():
					continue
				_obj_catalogue_data.append(c)
				var i := _obj_catalogue.item_count
				_obj_catalogue.add_item(object_type_label(str(c["type"]), [c]))
				_obj_catalogue.set_item_metadata(i, str(c["type"]))
				_obj_catalogue.set_item_tooltip(i, str(c.get("description", "")))
				if str(c["type"]) == prev_type:
					_obj_catalogue.select(i)
		var rows: Variant = _objects.rows()
		if typeof(rows) == TYPE_ARRAY:
			for r in rows:
				if typeof(r) != TYPE_DICTIONARY or not r.has("id"):
					continue
				var row: Dictionary = r.duplicate()
				_obj_rows.append(row)
				var i := _obj_list.item_count
				var status := str(row.get("status", ""))
				var status_text := object_status_text(status, str(row.get("status_text", "")))
				var shown := bool(row.get("visible", true))
				_obj_list.add_item("%d. %s · %s · %s%s" % [i + 1, str(row.get("label", row["id"])), object_type_label(str(row.get("type", "")), _obj_catalogue_data), status_text, "" if shown else " · 숨김"])
				_obj_list.set_item_metadata(i, str(row["id"]))
				if not shown or (not status.is_empty() and status not in ["ready", "ok", "editing", "busy"]):
					_obj_list.set_item_custom_fg_color(i, Color(0.8, 0.7, 0.5))
				if str(row["id"]) == prev:
					_obj_list.select(i)
		if _objects.get("edit_enabled") != null:
			_obj_edit.set_pressed_no_signal(bool(_objects.get("edit_enabled")))
	_refresh_object_controls()


func _refresh_object_controls() -> void:
	var bound := _objects_ok()
	var row := _selected_object_row()
	var has := not row.is_empty()
	_obj_catalogue.disabled = not bound or _obj_catalogue.item_count == 0
	_obj_add.disabled = not bound or _obj_catalogue.item_count == 0
	_obj_rename.disabled = not has
	_obj_remove.disabled = not has
	_obj_visible.disabled = not has
	_obj_scale.editable = has
	_obj_edit.disabled = not bound
	_obj_cancel.disabled = not bound or not _objects.has_method("cancel_interaction")
	if has:
		var sc := clampf(float(row.get("scale", 1.0)), _obj_scale.min_value, _obj_scale.max_value)
		_obj_scale.set_value_no_signal(sc)
		_obj_scale_value.text = "%.2f" % sc
		_obj_visible.set_pressed_no_signal(bool(row.get("visible", true)))
	else:
		_obj_scale.set_value_no_signal(1.0)
		_obj_scale_value.text = "1.00"
		_obj_visible.set_pressed_no_signal(false)
	for c in _obj_verbs.get_children():
		_obj_verbs.remove_child(c)
		c.queue_free()
	var verbs: Array = []
	if has and typeof(row.get("verbs", null)) == TYPE_ARRAY:
		verbs = row["verbs"]
	elif has:
		for c in _obj_catalogue_data:
			if str(c.get("type", "")) == str(row.get("type", "")) and typeof(c.get("verbs", null)) == TYPE_ARRAY:
				verbs = c["verbs"]
	var status := str(row.get("status", "")) if has else ""
	var actionable := has and bool(row.get("visible", true)) and status in ["", "ready", "ok", "busy"]
	for v in verbs:
		var verb := str(v)
		var b := Button.new()
		b.text = object_verb_label(verb)
		b.tooltip_text = str(OBJECT_VERB_TIPS.get(verb, ""))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not actionable
		b.pressed.connect(func(): _request_interaction(verb))
		_obj_verbs.add_child(b)
	if not bound:
		_obj_hint.text = "가구 기능이 아직 켜지지 않았습니다."
	elif _obj_catalogue.item_count == 0:
		_obj_hint.text = "놓을 수 있는 가구 목록이 비어 있습니다."
	elif _obj_rows.is_empty():
		_obj_hint.text = "가구가 없습니다. 종류를 고르고 추가한 뒤, 배치 편집을 켜고 끌어 놓으세요."
	elif has and not bool(row.get("visible", true)):
		_obj_hint.text = "'%s' 은(는) 숨겨져 있습니다. 보이기를 켜면 다시 쓸 수 있습니다." % str(row.get("label", ""))
	elif has and not actionable:
		_obj_hint.text = "'%s': %s" % [str(row.get("label", "")), object_status_text(status, str(row.get("status_text", "")))]
	elif has and verbs.is_empty():
		_obj_hint.text = "이 가구에는 아직 시킬 수 있는 동작이 없습니다."
	elif _obj_edit.button_pressed:
		_obj_hint.text = "배치 편집 중: 바탕화면의 가구를 끌어 옮기세요. 끝나면 배치 편집을 끄세요."
	else:
		_obj_hint.text = "%d개 놓임. 가구를 고르고 동작 버튼을 누르면 펫이 그 가구로 갑니다." % _obj_rows.size()


func _request_add_object() -> void:
	if not _objects_ok():
		return
	var type := selected_object_type()
	if type.is_empty():
		set_desktop_object_status("가구 종류를 먼저 고르세요")
		return
	var id: Variant = _objects.add_object(type)
	if typeof(id) != TYPE_STRING or str(id).is_empty():
		set_desktop_object_status("가구를 추가할 수 없습니다")
		return
	_refresh_objects()
	select_object(str(id))
	_obj_name.clear()


func _request_rename_object() -> void:
	var id := selected_object_id()
	var label := _obj_name.text.strip_edges()
	if not _objects_ok() or id.is_empty():
		return
	if label.is_empty():
		set_desktop_object_status("바꿀 이름을 위 입력칸에 적은 뒤 누르세요")
		return
	if not bool(_objects.rename_object(id, label)):
		set_desktop_object_status("이름을 바꿀 수 없습니다")
		return
	_obj_name.clear()
	_refresh_objects()


func _on_object_scale(value: float) -> void:
	_obj_scale_value.text = "%.2f" % value
	var id := selected_object_id()
	if not _objects_ok() or id.is_empty():
		return
	if not bool(_objects.resize_object(id, value)):
		set_desktop_object_status("크기를 바꿀 수 없습니다")
		_refresh_object_controls()


func _on_object_visible(on: bool) -> void:
	var id := selected_object_id()
	if not _objects_ok() or id.is_empty():
		return
	if not bool(_objects.set_object_visible(id, on)):
		set_desktop_object_status("표시 상태를 바꿀 수 없습니다")
		_refresh_object_controls()


func _request_remove_object() -> void:
	var id := selected_object_id()
	if not _objects_ok() or id.is_empty():
		return
	if not bool(_objects.remove_object(id)):
		set_desktop_object_status("삭제할 수 없습니다")
		return
	_refresh_objects()


func _on_object_edit(on: bool) -> void:
	if _objects_ok():
		_objects.set_edit_enabled(on)
	_refresh_objects()


func _request_interaction(verb: String) -> void:
	var id := selected_object_id()
	if not _objects_ok() or id.is_empty():
		return
	var result: Variant = _objects.interact(id, verb)
	var accepted := typeof(result) == TYPE_DICTIONARY and bool(result.get("accepted", false))
	var reason := str(result.get("reason", "")) if typeof(result) == TYPE_DICTIONARY else ""
	var label := str(_selected_object_row().get("label", id))
	if accepted:
		set_desktop_object_status("'%s' %s 요청됨" % [label, object_verb_label(verb)])
	else:
		set_desktop_object_status("%s 할 수 없음: %s" % [object_verb_label(verb), object_reason_text(reason) if not reason.is_empty() else "이유 없음"])


func _request_cancel_interaction() -> void:
	if _objects_ok() and _objects.has_method("cancel_interaction"):
		_objects.cancel_interaction()
		set_desktop_object_status("가구 동작을 멈췄습니다")


func desktop_objects_edit_enabled() -> bool:
	return _obj_edit.button_pressed


func focus_input() -> void:
	_input.grab_focus()


func is_text_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
