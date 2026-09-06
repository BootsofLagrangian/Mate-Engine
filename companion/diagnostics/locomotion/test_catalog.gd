extends SceneTree
const Bank = preload("res://scripts/motion_bank.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func entry() -> Dictionary:
	return {"name":"any_walk", "kind":"vrma", "duration":1.0, "sha256":"a".repeat(64)}
func _initialize() -> void:
	var errors: Array[String] = []
	var parsed := Bank.parse_asset_catalog({"motions":[entry()]}, errors)
	check(errors.is_empty() and parsed.size()==1 and not parsed[0].locomotion and parsed[0].locomotion_priority==0 and not parsed[0].locomotion_preserve_hips,"old catalog defaults")
	for priority in [0, 5, 50, 100]:
		var item := entry()
		item.merge({"locomotion":true,"locomotion_priority":priority,"locomotion_preserve_hips":true})
		# Exercise the actual JSON boundary, which converts integer tokens to floats.
		parsed = Bank.parse_asset_catalog(JSON.parse_string(JSON.stringify({"motions":[item]})), errors)
		check(parsed.size()==1 and parsed[0].locomotion and parsed[0].locomotion_priority==priority and parsed[0].locomotion_preserve_hips,"JSON capability preservation")
	for field in ["locomotion", "locomotion_preserve_hips", "locomotion_priority"]:
		var invalid: Array = [1, 0, "true", null, [], {}] if field!="locomotion_priority" else [-1, 101, true, false, 1.5, "50", null, [], {}, NAN, INF]
		for value in invalid:
			var item := entry()
			item[field] = value
			errors.clear()
			parsed = Bank.parse_asset_catalog({"motions":[item]}, errors)
			check(parsed.is_empty() and not errors.is_empty(),"invalid " + field + " rejected: " + str(value))
	print("LOCOMOTION_CATALOG checks=",checks," failures=",failures)
	quit(1 if failures else 0)
