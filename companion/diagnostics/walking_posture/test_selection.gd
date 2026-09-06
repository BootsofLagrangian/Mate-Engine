extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void:
	var clips := {"walk":{},"walk_formal":{}}
	check(AutonomyBridge.pick_walk_clip(clips)=="walk","legacy catalog retains available fallback")
	clips["new_walk"]={"locomotion":true,"loop":true,"locomotion_priority":50}
	check(AutonomyBridge.pick_walk_clip(clips)=="new_walk","new declared source wins without a hardcoded name")
	clips["showpiece"]={"locomotion":true,"loop":false,"locomotion_priority":100}
	clips["dance"]={"loop":true,"locomotion_priority":100}
	check(AutonomyBridge.pick_walk_clip(clips)=="new_walk","nonloops and unclassified loops cannot take walking ownership")
	clips["another_walk"]={"locomotion":true,"loop":true,"locomotion_priority":50}
	check(AutonomyBridge.pick_walk_clip(clips)=="another_walk","equal priorities resolve by stable name ordering")
	clips.erase("another_walk")
	clips.erase("new_walk")
	check(AutonomyBridge.pick_walk_clip(clips)=="walk","removing selected capability falls back safely")
	check(AutonomyBridge.pick_walk_clip({"dance":{"loop":true}}).is_empty(),"unclassified assets do not invent locomotion")
	print("Locomotion selection: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
