extends SceneTree
## Isolated headless UI test for the modeless-window layout of ControlPanel and the "시점" tab:
##   companion/tools/Godot_v4.5.2-stable_linux.x86_64 --headless --path companion/native \
##     --script /abs/path/companion/diagnostics/panel_window/test_control_panel_view.gd
## Exit 0 only when every check passes. Instantiates ControlPanel alone (Settings autoload stub).

var _failures: Array[String] = []
var _passed := 0
var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	print("\npanel window: %d passed, %d failed" % [_passed, _failures.size()])
	for f in _failures:
		print("  FAIL: " + f)
	quit(0 if _failures.is_empty() else 1)
	return true


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(label)
		print("  FAIL: " + label)


func _run() -> void:
	print("[panel window layout + 시점 tab]")
	if not root.has_node("Settings"):
		var s: Node = load("res://scripts/settings.gd").new()
		s.name = "Settings"
		root.add_child(s)
	# Host window the size Astra's wrapper uses (380x720): the panel must fill it entirely.
	var host := Control.new()
	host.size = Vector2(380, 720)
	root.add_child(host)
	var panel := ControlPanel.new()
	host.add_child(panel)
	check(panel.anchor_left == 0.0 and panel.anchor_top == 0.0 and panel.anchor_right == 1.0 and panel.anchor_bottom == 1.0, "anchors are FULL_RECT")
	check(panel.offset_left == 0.0 and panel.offset_top == 0.0 and panel.offset_right == 0.0 and panel.offset_bottom == 0.0, "offsets are zero (no sidebar inset)")
	check(panel.size == Vector2(380, 720), "panel fills a 380x720 host (%s)" % str(panel.size))
	check(is_equal_approx(ControlPanel.PANEL_WIDTH, 340.0) and panel.custom_minimum_size.x == 340.0, "PANEL_WIDTH 340 minimum kept")
	check(panel.get_combined_minimum_size().x <= 380.0, "minimum width fits the 380 px window (%.0f)" % panel.get_combined_minimum_size().x)
	check(panel.widest_child()["width"] <= ControlPanel.PANEL_WIDTH - 30.0, "widest child within the CJK budget (%s)" % str(panel.widest_child()))
	# Header wording.
	var close_btn: Button = null
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.contains("F8"):
			close_btn = n
		for c in n.get_children():
			stack.append(c)
	check(close_btn != null and close_btn.text == "닫기 (F8)" and close_btn.tooltip_text == "설정 창을 닫습니다. 캐릭터는 바탕화면에 그대로 남습니다.", "header button is 닫기 (F8) with the window tooltip")
	var collapsed: Array = []
	panel.collapse_requested.connect(func(): collapsed.append(true))
	close_btn.pressed.emit()
	check(collapsed.size() == 1, "닫기 still emits collapse_requested")
	# Tabs: 시점 visible at top level, existing tabs preserved.
	var tabs: Array = []
	for i in panel._tabs.get_tab_count():
		tabs.append(panel._tabs.get_tab_title(i))
	check(tabs == ["대화", "행동", "공간", "시점", "모션", "작업", "설정"], "시점 is its own tab (%s)" % str(tabs))
	check(panel._point_list != null and panel._idle_clip_option != null and panel._obj_list != null and panel._chain_button != null and panel._scale_slider != null, "existing widgets/bindings intact")
	# 시점 controls.
	var got: Array = []
	panel.setting_changed.connect(func(k: String, v: Variant): got.append([k, v]))
	var yaw: HSlider = panel._view_yaw
	var pitch: HSlider = panel._view_pitch
	var height: HSlider = panel._view_height
	var zoom: HSlider = panel._view_zoom
	check(yaw.min_value == -180.0 and yaw.max_value == 180.0 and yaw.step == 1.0 and yaw.value == 0.0, "yaw -180..180 step 1 default 0")
	check(pitch.min_value == -60.0 and pitch.max_value == 70.0 and pitch.step == 1.0 and pitch.value == 0.0, "pitch -60..70 step 1 default 0")
	check(is_equal_approx(height.min_value, -0.5) and is_equal_approx(height.max_value, 0.5) and is_equal_approx(height.step, 0.01) and height.value == 0.0, "height -0.5..0.5 step 0.01 default 0")
	check(is_equal_approx(zoom.min_value, 0.6) and is_equal_approx(zoom.max_value, 1.6) and is_equal_approx(zoom.step, 0.05) and is_equal_approx(zoom.value, 1.0), "zoom 0.6..1.6 step 0.05 default 1")
	check((yaw.get_meta("value_label") as Label).text == "0°" and (zoom.get_meta("value_label") as Label).text == "×1.00" and (height.get_meta("value_label") as Label).text == "+0.00 m", "readable degree / zoom / metre labels")
	check(panel._view_projection.get_selected_metadata() == "orthographic", "orthographic remains default")
	check(panel._view_fov.min_value == 20.0 and panel._view_fov.max_value == 80.0 and panel._view_fov.value == 45.0, "vertical FOV 20..80 default45")
	check(panel._view_distance.min_value == 1.0 and panel._view_distance.max_value == 12.0 and is_equal_approx(panel._view_distance.value, 3.6), "camera distance 1..12m default3.6")
	check(not panel._view_fov.editable and not panel._view_distance.editable, "perspective-only controls disabled in orthographic")
	check(got.is_empty(), "building the tab emits nothing")
	yaw.value = 45.0
	pitch.value = -20.0
	height.value = 0.25
	zoom.value = 1.3
	check(got.size() == 4 and got[0] == ["view_yaw_deg", 45.0] and got[1] == ["view_pitch_deg", -20.0] and got[2] == ["view_height", 0.25] and is_equal_approx(float(got[3][1]), 1.3) and got[3][0] == "view_zoom", "each control emits setting_changed(key, value) (%s)" % str(got))
	check((yaw.get_meta("value_label") as Label).text == "45°" and (pitch.get_meta("value_label") as Label).text == "-20°" and (height.get_meta("value_label") as Label).text == "+0.25 m" and (zoom.get_meta("value_label") as Label).text == "×1.30", "value labels follow")
	got.clear()
	panel.set_view_settings({"view_yaw_deg": -90, "view_zoom": 2.5, "view_height": "junk", "unknown": 1.0, "view_pitch_deg": NAN})
	check(got.is_empty(), "set_view_settings never emits")
	check(yaw.value == -90.0 and is_equal_approx(zoom.value, 1.6) and is_equal_approx(height.value, 0.25) and pitch.value == -20.0, "host sync: int accepted, out-of-range clamped, junk/NaN/unknown ignored (%s)" % str(panel.view_settings()))
	check((yaw.get_meta("value_label") as Label).text == "-90°" and (zoom.get_meta("value_label") as Label).text == "×1.60", "labels updated by host sync")
	panel._view_projection.select(1)
	panel._view_projection.item_selected.emit(1)
	check(got == [["view_projection", "perspective"]] and panel._view_fov.editable and panel._view_distance.editable, "mode selection emits perspective and enables camera controls")
	got.clear()
	panel._view_fov.value = 60.0
	panel._view_distance.value = 4.2
	check(got.size() == 2 and got[0] == ["view_fov_deg", 60.0] and got[1][0] == "view_distance_m" and is_equal_approx(got[1][1], 4.2), "FOV and actual distance emit distinct camera keys")
	got.clear()
	panel.set_view_settings({"view_projection": "orthographic"})
	check(not panel._view_fov.editable and not panel._view_distance.editable and panel._view_fov.value == 60.0 and is_equal_approx(panel._view_distance.value, 4.2), "orthographic preserves inactive perspective values")
	panel.set_view_settings({"view_projection": "invalid", "view_fov_deg": -100.0, "view_distance_m": 99.0})
	check(panel.view_settings()["view_projection"] == "orthographic" and panel._view_fov.value == 20.0 and panel._view_distance.value == 12.0 and got.is_empty(), "invalid projection ignored; camera sync clamps silently")
	panel.set_view_settings({"view_projection": "perspective", "view_fov_deg": 53.0, "view_distance_m": 5.1})
	check(panel._view_fov.editable and panel._view_distance.editable and panel.view_settings()["view_projection"] == "perspective" and got.is_empty(), "host perspective sync enables controls without emission")
	panel._view_reset.pressed.emit()
	check(got == [["view_reset", true]], "reset emits one atomic host reset (%s)" % str(got))
	check(panel.view_settings() == {"view_projection": "orthographic", "view_yaw_deg": 0.0, "view_pitch_deg": 0.0, "view_height": 0.0, "view_zoom": 1.0, "view_fov_deg": 45.0, "view_distance_m": 3.6}, "controls back at defaults")
	check(not panel._view_fov.editable and not panel._view_distance.editable, "reset restores orthographic control availability")
	got.clear()
	panel._view_reset.pressed.emit()
	check(got == [["view_reset", true]], "reset at defaults still emits one atomic host reset")
	var view_text := ""
	stack = [panel._tabs.get_tab_control(3)]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			view_text += (n as Label).text + "\n"
		for c in n.get_children():
			stack.append(c)
	check(view_text.contains("서 있는 자리는 그대로") and view_text.contains("좌우 회전") and view_text.contains("눈높이") and view_text.contains("확대"), "시점 tab explains view-only and uses Korean labels")
	# Space tab wording.
	var space_text := ""
	stack = [panel._tabs.get_tab_control(2)]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			space_text += (n as Label).text + "\n"
		for c in n.get_children():
			stack.append(c)
	check(space_text.contains("대화로 가구를 놓거나 사용해 달라고 요청하세요. 아래에서 직접 조절할 수도 있습니다.") and space_text.contains("직접 배치 · 선택 사항"), "space tab: conversation first, manual section optional")
	check(not space_text.contains("Windows에서 확인 중") and not space_text.contains("모든 백엔드"), "no stale Windows-verification warning, no claim about every backend")
	# Small-width readability: a 340 px host still fits without horizontal overflow.
	host.size = Vector2(340, 600)
	check(panel.size.x == 340.0 and panel.get_combined_minimum_size().x <= 340.0, "340 px host still fits (%s)" % str(panel.size))
	panel.queue_free()
	host.queue_free()
