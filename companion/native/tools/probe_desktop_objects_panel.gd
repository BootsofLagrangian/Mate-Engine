extends SceneTree
## Headless frontend test for the "공간" (desktop living-space) tab of ControlPanel, driven by a fake
## objects host that implements the agreed contract (no Astra module required, no OS windows):
##   Godot --headless --path companion/native --script tools/probe_desktop_objects_panel.gd
## Exit 0 only when every check passes.

var _failures: Array[String] = []
var _passed := 0
var _ran := false


## Minimal stand-in for Astra's DesktopObjects node: same signals/methods, in-memory state,
## scripted statuses and failure reasons so the panel's readable feedback can be asserted.
class FakeObjects:
	extends Node
	signal changed
	signal status_changed(message: String)
	var edit_enabled := false
	var next_id := 1
	var objects: Array[Dictionary] = []
	var forced_status: Dictionary = {} # id -> status
	var interact_log: Array = []
	var cancel_calls := 0
	var refuse_reason := ""

	func catalogue() -> Array[Dictionary]:
		return [
			{"type": "chair", "label": "의자", "verbs": ["inspect", "sit"], "description": "낮은 의자"},
			{"type": "sofa", "label": "소파", "verbs": ["inspect", "sit"], "description": "긴 소파"},
			{"type": "computer", "label": "컴퓨터 책상", "verbs": ["inspect", "sit", "use"], "description": "책상과 모니터 (자세만)"},
		]

	func rows() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for o in objects:
			var r := o.duplicate()
			var status := str(forced_status.get(o["id"], "ready"))
			r["status"] = status
			r["status_text"] = "" if status != "unsupported" else "접촉 검증 전"
			for c in catalogue():
				if c["type"] == o["type"]:
					r["verbs"] = c["verbs"]
			out.append(r)
		return out

	func add_object(type: String) -> String:
		var ok := false
		for c in catalogue():
			ok = ok or c["type"] == type
		if not ok or objects.size() >= 8:
			return ""
		var id := "obj_%d" % next_id
		next_id += 1
		objects.append({"id": id, "label": "%s %d" % [type, next_id - 1], "type": type, "x": 100, "y": 200, "scale": 1.0, "visible": true})
		changed.emit()
		return id

	func _find(id: String) -> int:
		for i in objects.size():
			if objects[i]["id"] == id:
				return i
		return -1

	func rename_object(id: String, label: String) -> bool:
		var i := _find(id)
		if i < 0 or label.strip_edges().is_empty():
			return false
		objects[i]["label"] = label.strip_edges()
		changed.emit()
		return true

	func resize_object(id: String, scale: float) -> bool:
		var i := _find(id)
		if i < 0 or scale < 0.5 or scale > 1.8:
			return false
		objects[i]["scale"] = scale
		changed.emit()
		return true

	func remove_object(id: String) -> bool:
		var i := _find(id)
		if i < 0:
			return false
		objects.remove_at(i)
		changed.emit()
		return true

	func set_object_visible(id: String, on: bool) -> bool:
		var i := _find(id)
		if i < 0:
			return false
		objects[i]["visible"] = on
		changed.emit()
		return true

	func set_edit_enabled(on: bool) -> void:
		edit_enabled = on
		status_changed.emit("배치 편집 켜짐" if on else "배치 편집 꺼짐")
		changed.emit()

	func interact(id: String, verb: String) -> Dictionary:
		interact_log.append([id, verb])
		if not refuse_reason.is_empty():
			return {"accepted": false, "reason": refuse_reason}
		if _find(id) < 0:
			return {"accepted": false, "reason": "unknown_object"}
		return {"accepted": true, "reason": "queued"}

	func cancel_interaction() -> void:
		cancel_calls += 1


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	print("\ndesktop objects panel: %d passed, %d failed" % [_passed, _failures.size()])
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


func _ensure_settings() -> void:
	if not root.has_node("Settings"):
		var s: Node = load("res://scripts/settings.gd").new()
		s.name = "Settings"
		root.add_child(s)


func _verb_buttons(panel: ControlPanel) -> Array:
	var out: Array = []
	for c in panel._obj_verbs.get_children():
		if c is Button:
			out.append(c)
	return out


func _verb_texts(panel: ControlPanel) -> Array:
	var out: Array = []
	for b in _verb_buttons(panel):
		out.append((b as Button).text)
	return out


func _run() -> void:
	print("[desktop objects panel] (headless, fake objects host)")
	_ensure_settings()
	var settings := root.get_node("Settings")
	var d: Dictionary = settings.get_value("desktop_objects", {})
	check(d.get("version") == 1 and d.get("next_id") == 1 and typeof(d.get("objects")) == TYPE_ARRAY and d["objects"].is_empty(), "settings default desktop_objects = {version 1, next_id 1, objects []}")
	var panel := ControlPanel.new()
	root.add_child(panel)
	var tabs: Array = []
	for i in panel._tabs.get_tab_count():
		tabs.append(panel._tabs.get_tab_title(i))
	check(tabs == ["대화", "행동", "공간", "시점", "모션", "작업", "설정"], "공간 tab present next to the existing tabs and 시점 (%s)" % str(tabs))
	# Inherited controls untouched.
	check(panel._point_list != null and panel._idle_clip_option != null and panel._idle_clip_option.item_count >= 2 and panel._markers_check != null, "interest-point and idle controls still present")
	var settings_got: Array = []
	panel.setting_changed.connect(func(k: String, v: Variant): settings_got.append([k, v]))

	# --- unbound: everything disabled with a readable reason
	check(panel._obj_add.disabled and panel._obj_catalogue.disabled and panel._obj_edit.disabled and panel._obj_cancel.disabled and panel._obj_rename.disabled and panel._obj_remove.disabled and not panel._obj_scale.editable, "unbound: all object controls disabled")
	check(panel._obj_hint.text.contains("아직 켜지지") and panel._obj_status.text == "상태: 준비 안 됨", "unbound hint/status are plain product wording")

	# --- bound to the fake host
	var fake := FakeObjects.new()
	root.add_child(fake)
	panel.bind_desktop_objects(fake)
	check(panel._obj_catalogue.item_count == 3 and not panel._obj_add.disabled and not panel._obj_catalogue.disabled and not panel._obj_edit.disabled and not panel._obj_cancel.disabled, "catalogue offered (3 types), add/edit/cancel enabled")
	var cat_texts: Array = []
	for i in panel._obj_catalogue.item_count:
		cat_texts.append(panel._obj_catalogue.get_item_text(i))
	check(cat_texts == ["의자", "소파", "컴퓨터 책상"] and panel._obj_catalogue.get_item_tooltip(2) == "책상과 모니터 (자세만)", "catalogue labels/descriptions come from the host (%s)" % str(cat_texts))
	check(panel._obj_hint.text.contains("가구가 없습니다") and panel._obj_status.text == "상태: 준비됨", "empty list hint")
	check(panel.desktop_object_rows().is_empty() and panel._obj_list.item_count == 0, "no objects until an explicit add")

	# add chair -> selected, verbs shown
	panel._obj_catalogue.select(0)
	panel._request_add_object()
	check(fake.objects.size() == 1 and panel.selected_object_id() == "obj_1" and panel._obj_list.item_count == 1, "add creates one object through the host and selects it")
	check(panel._obj_list.get_item_text(0).contains("chair 1") and panel._obj_list.get_item_text(0).contains("의자") and panel._obj_list.get_item_text(0).contains("준비됨"), "row shows name · type · readable status (%s)" % panel._obj_list.get_item_text(0))
	check(_verb_texts(panel) == ["살펴보기", "앉기"], "chair verbs: inspect + sit as Korean buttons (%s)" % str(_verb_texts(panel)))
	check(not panel._obj_rename.disabled and not panel._obj_remove.disabled and panel._obj_scale.editable and not panel._obj_visible.disabled and panel._obj_visible.button_pressed, "selection enables rename/remove/scale/visible")
	# computer desk -> use verb with an honest tooltip
	panel._obj_catalogue.select(2)
	panel._request_add_object()
	check(panel.selected_object_id() == "obj_2" and _verb_texts(panel) == ["살펴보기", "앉기", "사용하기"], "computer desk verbs include 사용하기 (%s)" % str(_verb_texts(panel)))
	var use_btn: Button = _verb_buttons(panel)[2]
	check(use_btn.tooltip_text.contains("자세만") and use_btn.tooltip_text.contains("읽지 않") and use_btn.tooltip_text.contains("조작하지"), "use tooltip: pose only, no screen/file reading, no app control")
	var space_text := ""
	var stack: Array = [panel._tabs.get_tab_control(2)]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			space_text += (n as Label).text + "\n"
		elif n is Button:
			space_text += (n as Button).text + "\n"
		for c in n.get_children():
			stack.append(c)
	check(space_text.contains("대화로 가구를 놓거나") and space_text.contains("직접 배치 · 선택 사항") and space_text.contains("앞으로 (아직 없음)") and space_text.contains("도구 꽂이") and not space_text.contains("Windows에서 확인 중"), "conversation-first wording, manual section optional; hold/tool socket described as future, not a button")
	for b in _verb_buttons(panel):
		check((b as Button).text != "들기" and (b as Button).text != "도구", "no hold/tool button exists")

	# rename / resize / visibility / remove through the host, selection stable by id
	panel._obj_name.text = "  창가 의자  "
	panel.select_object("obj_1")
	panel._request_rename_object()
	check(fake.objects[0]["label"] == "창가 의자" and panel.selected_object_id() == "obj_1" and panel._obj_list.get_item_text(0).contains("창가 의자") and panel._obj_name.text.is_empty(), "rename applied by host, list refreshed, selection kept")
	panel._request_rename_object()
	check(panel._obj_status.text.contains("바꿀 이름") and fake.objects[0]["label"] == "창가 의자", "empty rename refused with a hint, nothing changed")
	panel._obj_scale.value = 1.5
	check(is_equal_approx(float(fake.objects[0]["scale"]), 1.5) and panel._obj_scale_value.text == "1.50", "slider resizes through the host")
	check(is_equal_approx(panel._obj_scale.min_value, 0.5) and is_equal_approx(panel._obj_scale.max_value, 1.8), "scale range 0.5..1.8")
	panel.select_object("obj_2")
	check(is_equal_approx(panel._obj_scale.value, 1.0) and panel._obj_visible.button_pressed, "selecting another object mirrors its scale/visibility without calling the host")
	var log_before := fake.interact_log.size()
	panel._obj_visible.button_pressed = false
	check(fake.objects[1]["visible"] == false and panel._obj_list.get_item_text(1).contains("숨김") and panel._obj_hint.text.contains("숨겨져") and fake.interact_log.size() == log_before, "visibility toggle hides through the host; hint explains")
	check(_verb_buttons(panel).size() == 3 and (_verb_buttons(panel)[0] as Button).disabled, "hidden object: verbs shown but disabled")
	panel._obj_visible.button_pressed = true
	check(fake.objects[1]["visible"] == true and not (_verb_buttons(panel)[0] as Button).disabled, "visible again re-enables verbs")

	# interactions: accepted / refused with reason
	fake.interact_log.clear()
	(_verb_buttons(panel)[1] as Button).pressed.emit()
	check(fake.interact_log == [["obj_2", "sit"]] and panel._obj_status.text.contains("앉기 요청됨"), "sit calls interact(id, 'sit') and reports the request (%s)" % panel._obj_status.text)
	fake.refuse_reason = "unreachable"
	(_verb_buttons(panel)[2] as Button).pressed.emit()
	check(panel._obj_status.text == "상태: 사용하기 할 수 없음: 지금 자리에서 갈 수 없습니다", "refusal shows the readable reason (%s)" % panel._obj_status.text)
	fake.refuse_reason = "some_new_reason"
	(_verb_buttons(panel)[0] as Button).pressed.emit()
	check(panel._obj_status.text.ends_with("some_new_reason"), "unknown reason shown verbatim")
	fake.refuse_reason = ""
	panel._obj_cancel.pressed.emit()
	check(fake.cancel_calls == 1 and panel._obj_status.text.contains("멈췄"), "cancel button calls cancel_interaction")

	# status from the host rows: offscreen / unreachable / unsupported disable verbs with text
	fake.forced_status["obj_1"] = "offscreen"
	fake.forced_status["obj_2"] = "unsupported"
	fake.changed.emit()
	panel.select_object("obj_1")
	check(panel._obj_list.get_item_text(0).contains("화면 밖") and (_verb_buttons(panel)[0] as Button).disabled and panel._obj_hint.text.contains("화면 밖"), "offscreen row: readable status, verbs disabled")
	panel.select_object("obj_2")
	check(panel._obj_list.get_item_text(1).contains("접촉 검증 전") and (_verb_buttons(panel)[0] as Button).disabled, "host status_text wins over the fallback map; unsupported disables verbs")
	fake.forced_status.clear()
	fake.changed.emit()
	check(not (_verb_buttons(panel)[0] as Button).disabled and panel.selected_object_id() == "obj_2", "status recovery re-enables verbs, selection stable through refresh")

	# edit mode + host status message
	panel._obj_edit.button_pressed = true
	check(fake.edit_enabled and panel._obj_status.text == "상태: 배치 편집 켜짐" and panel._obj_hint.text.contains("끌어 옮기세요"), "edit toggle drives the host and shows its status")
	fake.edit_enabled = false
	fake.changed.emit()
	check(not panel._obj_edit.button_pressed, "host-side edit end mirrors into the toggle without re-calling")
	fake.set_edit_enabled(true)
	check(panel._obj_edit.button_pressed, "host-side edit start mirrors too")
	panel._obj_edit.button_pressed = false
	check(not fake.edit_enabled, "toggle off through the host")

	# remove without confirmation; add limit / host refusal
	panel.select_object("obj_1")
	panel._request_remove_object()
	check(fake.objects.size() == 1 and panel._obj_list.item_count == 1 and panel.selected_object_id().is_empty(), "delete removes immediately (reversible by re-adding), no confirmation")
	fake.objects.clear()
	fake.changed.emit()
	panel._obj_catalogue.select(1)
	while fake.objects.size() < 8:
		panel._request_add_object()
	var count_before := fake.objects.size()
	panel._request_add_object()
	check(fake.objects.size() == count_before and panel._obj_status.text.contains("추가할 수 없습니다"), "host refusing add shows a concise message")
	# Rebinding / unbinding
	panel.bind_desktop_objects(null)
	check(panel._obj_list.item_count == 0 and panel._obj_add.disabled and panel._obj_hint.text.contains("아직 켜지지"), "unbind clears and disables")
	fake.changed.emit()
	check(panel._obj_list.item_count == 0, "old host no longer followed after unbind")
	panel.bind_desktop_objects(fake)
	check(panel._obj_list.item_count == 8, "rebind reloads rows")
	check(settings_got.is_empty(), "panel never emitted a setting for objects (host owns persistence)")
	var budget := ControlPanel.PANEL_WIDTH - 30.0
	check(panel.widest_child()["width"] <= budget, "공간 tab keeps the panel within the CJK width budget (%s)" % str(panel.widest_child()))
	panel.queue_free()
	fake.queue_free()
