extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	var script = load("res://scripts/companion_panel_window.gd")
	var area := Rect2i(0,0,1920,1040)
	for pet in [Rect2i(800,500,220,330), Rect2i(1600,690,220,330), Rect2i(0,0,220,330), Rect2i(900,0,220,330)]:
		var placed: Rect2i = script.placement_rect(pet,area)
		check(area.encloses(placed), "ordinary monitor placement fully contained")
		check(not placed.intersects(pet), "ordinary monitor settings do not cover character")
	check(script.placement_rect(Rect2i(1600,600,220,330),area).end.x < 1600, "right-edge pet opens panel to its left")
	check(script.placement_rect(Rect2i(0,600,220,330),area).position.x > 220, "left-edge pet opens panel to its right")
	var negative_area := Rect2i(-1920,-300,1920,1080)
	var negative_pet := Rect2i(-1700,350,200,330)
	var negative: Rect2i = script.placement_rect(negative_pet,negative_area)
	check(negative_area.encloses(negative) and not negative.intersects(negative_pet), "negative desktop origins preserve placement")
	var tall_area := Rect2i(0,0,500,1800)
	var tall_pet := Rect2i(140,1350,220,330)
	var above: Rect2i = script.placement_rect(tall_pet,tall_area)
	check(tall_area.encloses(above) and not above.intersects(tall_pet), "narrow tall monitor falls back above character")
	var tiny := Rect2i(-200,100,280,400)
	var fallback: Rect2i = script.placement_rect(tiny,tiny)
	check(tiny.encloses(fallback) and fallback.size == tiny.size, "unavoidable overlap still clamps entire window")
	check(script.placement_rect(Rect2i(),Rect2i()).size == Vector2i.ZERO, "invalid workarea cannot open window")
	for key in [KEY_F8,KEY_F9,KEY_F10,KEY_ESCAPE]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = true
		check(not script.hotkey_action(event).is_empty(), "focused native panel forwards required key")
		event.echo = true
		check(script.hotkey_action(event).is_empty(), "key repeat cannot duplicate command")
	var release := InputEventKey.new()
	release.keycode = KEY_F9
	release.pressed = false
	check(script.hotkey_action(release) == "push_to_talk", "F9 release is forwarded using keycode fallback")
	var normal := InputEventKey.new()
	normal.keycode = KEY_A
	normal.pressed = true
	check(script.hotkey_action(normal).is_empty(), "ordinary text is not intercepted")
	var window = script.new()
	root.add_child(window)
	var content := Control.new()
	root.add_child(content)
	var original_root_size := root.size
	check(window.configure(content,Rect2i(800,500,220,330),area), "existing panel reparents successfully")
	check(content.get_parent() == window and content.get_viewport() != root, "settings occupy separate viewport")
	check(not window.visible and not window.transient and not window.exclusive, "window starts closed and modeless")
	check(window.borderless and window.unresizable and window.force_native and window.minimize_disabled and window.maximize_disabled, "native settings disable minimize and maximize")
	check(content.anchor_right == 1.0 and content.anchor_bottom == 1.0, "panel fills its own viewport")
	check(root.size == original_root_size, "panel configuration does not resize avatar viewport")
	var close_count := [0]
	var lost_count := [0]
	window.closed.connect(func(): close_count[0] += 1)
	window.panel_focus_lost.connect(func(): lost_count[0] += 1)
	check(window.open_next_to(Rect2i(800,500,220,330),area), "configured window opens next to character")
	window.close_panel()
	window.close_panel()
	check(not window.visible and close_count[0] == 1, "closing hides only settings and is idempotent")
	check(lost_count[0] >= 1, "closing releases focused push-to-talk")
	check(root.size == original_root_size and is_instance_valid(content), "close preserves avatar viewport and panel state")
	window.free()
	print("Panel window: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
