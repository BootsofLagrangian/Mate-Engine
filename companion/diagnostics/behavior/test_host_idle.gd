extends "res://tools/probe_host_lifecycle.gd"
class Values:
	extends Node
	var values := {"behavior_enabled":true,"idle_clip":"auto"}
	func get_value(key: String, fallback: Variant = null) -> Variant:
		return values.get(key,fallback)
func _run() -> void:
	host_script = GDScript.new()
	host_script.source_code = 'extends "res://scripts/main.gd"\nfunc _ready() -> void:\n\tset_process(false)\nfunc _update_passthrough(_force: bool) -> void:\n\tpass\nfunc _save_window_position() -> void:\n\tpass\n'
	if host_script.reload() != OK: quit(1); return
	var host := make_host()
	host.motion.avatar = host.avatar
	host.panel._behavior_check = CheckButton.new()
	host.panel.add_child(host.panel._behavior_check)
	host.panel._behavior_state = Label.new()
	host.panel.add_child(host.panel._behavior_state)
	var living := LivingBehavior.new()
	host.add_child(living)
	living.host = host
	living.points = InterestPoints.new()
	living.add_child(living.points)
	var values := Values.new()
	living.add_child(values)
	living._settings = values
	host.session.character_id = "one"
	host.session.characters = [{"id":"one","ambient_loop":"home","idle_actions":["special"]}]
	for name in ["home","special"]:
		host._vrma_loaded[name] = {"ambient":name=="home","loop":name=="home"}
		var clip := VrmaClip.new()
		clip.duration = 4.0
		host.motion.vrma_clips[name] = clip
	living._refresh_targets()
	check(host.motion.authored_ambient.loop_name == "home","profile chooses authored home loop")
	host.autonomy.state = "rest"
	living._clock = 100.0
	living._idle_action_next = 0.0
	living._maybe_idle_action("rest")
	check(host.motion.authored_ambient.action_name == "special","auto schedules loaded finite character action")
	var next: float = living._idle_action_next
	living._clock += 1.0
	host.motion.authored_ambient.action_time = 1.0
	living._maybe_idle_action("rest")
	check(host.motion.authored_ambient.action_time == 1.0 and next == living._idle_action_next,"quiet cooldown does not restart authored action")
	for choice in ["", "home"]:
		values.values.idle_clip = choice
		living._idle_action_next = 0.0
		host.motion.authored_ambient.action_name = ""
		living._maybe_idle_action("rest")
		check(host.motion.authored_ambient.action_name.is_empty(),"explicit idle choice disables intermittent actions")
	values.values.behavior_enabled = false
	living._set_enabled(false)
	living._refresh_at = INF
	host.panel_open = false
	host.motion.set_ambient_attention_override(true)
	living.tick(0.1)
	check(not host.motion._ambient_attention_override,"behavior-off clears stale autonomous attention override")
	for flag in ["voice", "microphone", "busy", "drag", "preview", "navigation", "job"]:
		host.audio.voice_active = flag == "voice"
		host.mic._recording = flag == "microphone"
		host.session.turn_generating = flag == "busy"
		host.session.turn_id = "busy-turn" if flag == "busy" else ""
		host._drag_active = flag == "drag"
		host.motion._preview = flag == "preview"
		host.autonomy.state = "walk" if flag == "navigation" else "rest"
		host.session.job = {"status":"running"} if flag == "job" else {}
		living.tick(0.1)
		check(host.motion._ambient_suspended,"behavior-off still suspends authored idle for " + flag)
	host.audio.voice_active = false
	host.mic._recording = false
	host.session.turn_generating = false
	host.session.turn_id = ""
	host._drag_active = false
	host.motion._preview = false
	host.autonomy.state = "rest"
	host.session.job = {}
	living.tick(0.1)
	check(not host.motion._ambient_suspended,"idle suspension clears after foreground ends")
	var panel := ControlPanel.new()
	panel.vrma_clips = {"home":{"ambient":true,"loop":true},"special":{"ambient":false,"loop":false},"walk":{"loop":true},"idle_natural":{"loop":true}}
	panel.set_idle_profile("home")
	check(panel.idle_candidates() == ["home","idle_natural"],"idle selector excludes finite actions and ordinary walking loops")
	panel._idle_clip_option = OptionButton.new()
	panel.add_child(panel._idle_clip_option)
	panel.set_idle_clip("missing_saved")
	check(panel._idle_clip_option.get_item_metadata(panel._idle_clip_option.selected) == "missing_saved","missing imported idle remains visibly selected")
	panel.set_idle_clip("")
	check(panel._idle_clip_option.get_item_metadata(panel._idle_clip_option.selected) == "","breathing-only choice preserves empty setting")
	panel.set_idle_clip("auto")
	check(panel._idle_clip_option.get_item_metadata(panel._idle_clip_option.selected) == "auto","automatic choice preserves auto setting")
	panel.free()
	var settings := root.get_node("Settings")
	settings.set_value("idle_clip", "")
	host._apply_ambient_idle()
	check(host.motion.authored_ambient.loop_name.is_empty(),"main clears authored loop for breathing-only setting")
	settings.set_value("idle_clip", "auto")
	host._apply_ambient_idle()
	check(host.motion.authored_ambient.loop_name == "home","main restores character loop for automatic setting")
	var replacement := VrmaClip.new()
	replacement.duration = 3.0
	host.motion.vrma_clips["new_home"] = replacement
	host._vrma_loaded["new_home"] = {"ambient":true,"loop":true}
	host.session.characters[0].ambient_loop = "new_home"
	living._refresh_targets()
	check(host.motion.authored_ambient.loop_name == "new_home","same-ID profile update replaces ambient loop")
	host.free()
	print("Host idle: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
