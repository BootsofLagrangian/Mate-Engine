extends "res://tools/probe_host_lifecycle.gd"
class QuietPanel:
	extends HostPanel
	func set_behavior_state(_text: String) -> void: pass
func _run() -> void:
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\n'
	if host_script.reload()!=OK: quit(1);return
	var h=make_host()
	h.panel.free();h.panel=QuietPanel.new();h.add_child(h.panel)
	var living:=LivingBehavior.new()
	h.add_child(living);h.living=living;living.host=h
	living._settings=root.get_node("Settings")
	living.points=InterestPoints.new();living.add_child(living.points)
	h.session.character_id="test-character"
	h.session.hello_received=true
	h.session.capabilities={"world_context":true}
	h._selection_announced=h.session.character_id
	h.autonomy.set_surface_mode(true)
	h.autonomy._support={"id":"floor:test","kind":"floor","x1":0.0,"x2":1920.0,"y":1040.0}
	h.autonomy._locked_anchor=Vector2(510,680)
	check(living.director.interest_catalogue().is_empty() and h.autonomy.available_surface_targets().size()==2,"regression begins with stale empty director and actual live floor targets")
	h.client.state="closed"
	living.publish_world(true)
	check(living.director.interest_catalogue().is_empty() and h.client.outbound.is_empty(),"offline force preserves guards before refreshing")
	h.client.state="open"
	living.publish_world(true)
	var sent:Dictionary=h.client.outbound.back()
	var ids:Array=[]
	for entry in sent.interests: ids.append(entry.id)
	check(ids.has("support:left") and ids.has("support:right"),"forced pre-chat publication includes latest actual support endpoints")
	var count:int=h.client.outbound.size()
	living.tick(.05)
	check(h.client.outbound.size()==count,"next unchanged host tick does not publish a second revision")
	living._refresh_targets();living.publish_world()
	check(h.client.outbound.size()==count,"later unchanged refresh preserves the same publication fingerprint")
	h.free()
	print("Forced world publication: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
