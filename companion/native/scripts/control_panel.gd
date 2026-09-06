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
signal refresh_requested
signal reload_avatar_requested
signal preview_gesture(name: String, emotion: String, intensity: float, speed: float, repeat: int)
signal preview_motion(motion: Dictionary)
signal save_motion(motion: Dictionary)
signal job_start(prompt: String)
signal job_cancel
signal setting_changed(key: String, value: Variant)
signal backend_changed(url: String)
signal collapse_requested
## Manual sit (true) / stand (false) on the current desktop support (surface mode only).
signal sit_requested(sit: bool)

const PANEL_WIDTH := 340.0
## Static helpers only; the Settings autoload is looked up at runtime so this script compiles
## in `-s` tool/test mode where autoload globals are not registered yet (same as backend_client.gd).
const SettingsScript := preload("res://scripts/settings.gd")
const EMOTIONS := ["neutral", "happy", "relaxed", "sad", "surprised", "angry"]
const KEYFRAME_MAX := 64

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
var _tabs: TabContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
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
	collapse.text = "펫 모드 (F8)"
	collapse.tooltip_text = "패널을 숨기고 투명 펫 모드로 전환합니다. F8로 다시 엽니다."
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
	_idle_clip_option.tooltip_text = "기본 대기 동작을 사용합니다. 다른 동작은 모션 탭에서 미리 볼 수 있습니다."
	_idle_clip_option.item_selected.connect(func(i: int): setting_changed.emit("idle_clip", str(_idle_clip_option.get_item_metadata(i))))
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
	for c in characters:
		var id := str(c.get("id", ""))
		_character_option.add_item(str(c.get("name", id)))
		_character_option.set_item_metadata(_character_option.item_count - 1, id)
		if id == current:
			_character_option.select(_character_option.item_count - 1)


func set_bank(new_bank: MotionBank) -> void:
	bank = new_bank
	_refresh_preset_option()


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
		if not bank.has_motion(str(n)):
			names.append(str(n))
	return names


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


func _refresh_idle_clip_option() -> void:
	if _idle_clip_option == null:
		return
	_idle_clip_option.clear()
	_idle_clip_option.add_item("기본 대기 동작 사용")
	_idle_clip_option.set_item_metadata(0, "")
	_idle_clip_option.select(0)
	_idle_clip_option.disabled = true


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


func focus_input() -> void:
	_input.grab_focus()


func is_text_focused() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit
