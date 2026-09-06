extends SceneTree
const Store = preload("res://scripts/desktop_object_store.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var store = Store.new()
	var screens: Array = [Rect2i(-1920, -200, 1920, 1040), Rect2i(0, 0, 1920, 1040)]
	check(store.data().objects.is_empty(), "default empty")
	check(Store.catalogue().size() == 3, "three built-in types")
	check(Store.base_size("chair") == Vector2i(260, 300), "chair dimensions")
	check(Store.base_size("sofa") == Vector2i(500, 340), "sofa dimensions")
	check(Store.base_size("computer") == Vector2i(360, 300), "computer dimensions")
	check(store.add_object("unknown", Vector2i.ZERO, screens) == "", "reject unknown type")
	check(store.add_object("chair", Vector2i.ZERO, []) == "", "cannot add without monitors")
	check(store.add_object("chair", Vector2i.ZERO, [Rect2i(0, 0, 259, 300)]) == "", "full rectangle must fit")
	var first: String = store.add_object("chair", Vector2i(-1910, -300), screens)
	check(first == "obj_1", "failed adds do not consume IDs")
	check(store.rect_for(store.get_object(first)) == Rect2i(-1910, -200, 260, 300), "negative monitor placement")
	check(store.move_object(first, Vector2i(-40, 900), screens), "move clamps to nearest suitable monitor")
	check(store.rect_for(store.get_object(first)) == Rect2i(0, 740, 260, 300), "nearest screen clamp")
	var before: Dictionary = store.data()
	check(not store.move_object(first, Vector2i(100001, 0), screens), "out-of-range requested coordinates rejected")
	check(not store.resize_object(first, NAN, screens), "NaN scale rejected")
	check(not store.resize_object(first, INF, screens), "infinite scale rejected")
	check(not store.resize_object(first, 0.49, screens), "small scale rejected")
	check(not store.resize_object(first, 1.81, screens), "large scale rejected")
	check(not store.resize_object(first, 1.8, [Rect2i(0, 0, 300, 400)]), "no-fit resize rejected")
	check(not store.move_object(first, Vector2i.ZERO, []), "no-fit move rejected")
	check(store.data() == before, "failed mutations preserve all data")
	check(store.resize_object(first, 1.8, screens), "maximum scale accepted")
	check(store.rect_for(store.get_object(first)) == Rect2i(0, 500, 468, 540), "resize reclamps full rectangle")
	check(store.resize_object(first, 0.5, screens), "minimum scale accepted")
	check(store.rename_object(first, "\n  안녕\t세계 " + "가".repeat(60)), "Korean rename accepted")
	check(store.get_object(first).label.length() == 40 and store.get_object(first).label.begins_with("안녕세계"), "label removes controls and caps Unicode characters")
	var copy: Dictionary = store.get_object(first)
	copy.x = 222
	check(store.get_object(first).x == 0, "get_object returns copy")
	var saved: Dictionary = store.data()
	saved.objects[0].label = "changed"
	check(store.get_object(first).label != "changed", "data returns deep copy")
	var row: Dictionary = store.rows(screens)[0]
	check(row.status == "ready" and row.verbs == ["inspect", "sit"], "ready row has verbs")
	row.verbs.clear()
	check(store.rows(screens)[0].verbs.size() == 2, "row verbs do not alias catalogue")
	check(store.rows([])[0].status == "parked", "missing monitor parks object")
	before = store.data()
	store.rows([])
	check(store.data() == before, "monitor removal preserves persisted position")
	check(store.set_object_visible(first, false), "hide works")
	check(store.rows(screens)[0].status_text == "숨김", "hidden status")
	check(store.set_object_visible(first, true), "show works")
	check(store.remove_object(first), "remove works")
	check(not store.has_object(first) and not store.remove_object(first), "removed ID absent")
	check(store.add_object("sofa", Vector2i.ZERO, screens) == "obj_2", "removed ID never reused")
	var restored = Store.new()
	restored.set_data(JSON.parse_string(JSON.stringify(store.data())))
	check(restored.data() == store.data(), "JSON persistence roundtrip")
	check(restored.add_object("computer", Vector2i.ZERO, screens) == "obj_3", "counter survives persistence")
	for i in 10:
		restored.add_object("chair", Vector2i.ZERO, screens)
	check(restored.objects.size() == 8 and restored.next_id == 10, "eight object cap and counter")
	store.set_data({"version": 1, "next_id": 1, "objects": [
		{"id": "obj_8", "type": "chair", "label": "  한글  ", "x": -9000, "y": 100, "scale": 8},
		{"id": "obj_8", "type": "sofa", "x": 0, "y": 0},
		{"id": "obj_9", "type": "alien", "x": 0, "y": 0},
		{"id": "obj_10", "type": "chair", "x": NAN, "y": 0},
		{"id": "obj_11", "type": "chair", "x": 0, "y": 100001},
		{"id": "obj_12", "type": "chair", "x": 0, "y": 0, "scale": INF},
		{"id": "obj_01", "type": "chair", "x": 0, "y": 0}, null]})
	check(store.objects.size() == 1, "corrupt records and duplicate IDs rejected")
	check(store.next_id == 13, "counter advances past all seen valid IDs")
	check(store.objects[0].label == "한글" and store.objects[0].scale == 1.8, "loaded values sanitized")
	check(store.objects[0].x == -9000 and store.rows(screens)[0].status == "parked", "offscreen persisted object retained")
	check(store.rows([Rect2i(-10000, 0, 1920, 1040)])[0].status == "ready", "returning monitor restores readiness")
	check(store.clamp_position(Vector2i.ZERO, Vector2i(500, 300), [Rect2i(0, 0, 250, 500), Rect2i(250, 0, 250, 500)]) == null, "cannot span two undersized screens")
	check(store.clamp_position(Vector2i.ZERO, Vector2i(260, 300), [Rect2(0.5, 0.5, 260.5, 300.5)]) == Vector2i(1, 1), "fractional screens round inward")
	check(store.clamp_position(Vector2i.ZERO, Vector2i(260, 300), [null, {}, Rect2i(0, 0, -20, 300)]) == null, "invalid screens ignored")
	for malformed in [null, [], "bad", {"version": 2}, {"objects": "bad"}]:
		store.set_data(malformed)
		check(store.objects.is_empty() and store.next_id == 1, "malformed document resets safely")
	check(not store.rename_object("missing", "x") and not store.set_object_visible("missing", false), "missing mutations fail")
	print("Desktop object store: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
