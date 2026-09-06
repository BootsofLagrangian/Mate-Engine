extends SceneTree
func _initialize():
	var probe=load("res://tools/probe_windows_scene_navigation.gd")
	var events:Array=[{"id":"wanted","intent":{},"result":{"accepted":true}},{"record_type":"terminal","id":"other","outcome":"blocked_endpoint"}]
	assert(probe.terminal_event(events,"wanted").is_empty())
	events.append({"record_type":"terminal","id":"wanted","outcome":null})
	assert(probe.terminal_event(events,"wanted").is_empty())
	events.append({"record_type":"terminal","id":"wanted","outcome":"unreachable"})
	assert(probe.terminal_event(events,"wanted").outcome=="unreachable")
	assert(probe.terminal_event(events,"missing").is_empty())
	print("Scene probe terminal selection: 4 checks, 0 failures")
	quit()
