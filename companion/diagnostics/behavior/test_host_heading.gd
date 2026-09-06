extends "res://tools/probe_host_lifecycle.gd"
## Exercises actual main._wire callbacks, independent of the turn renderer.
func _run() -> void:
	host_script = GDScript.new()
	host_script.source_code = 'extends "res://scripts/main.gd"\nfunc _ready() -> void:\n\tset_process(false)\nfunc _update_passthrough(_force: bool) -> void:\n\tpass\nfunc _save_window_position() -> void:\n\tpass\n'
	if host_script.reload() != OK:
		quit(1)
		return
	var host := make_host()
	host.motion.avatar = host.avatar
	host.world_source = DesktopWorldSource.new()
	host.add_child(host.world_source)
	host.autonomy.support_changed.disconnect(host._on_support_changed)
	host._wire()
	host.autonomy.set_heading_ready_provider(func(): return host.motion.heading_ready())
	host.autonomy.set_external_decisions(false) # legacy navigation still uses main heading ownership
	host.autonomy.update_context(false,false,false,false,false)
	host.autonomy.advance(3.0)
	host.autonomy.observe_interest("right",Vector2(1300,400),1,120)
	host.autonomy.move_to_interest("right")
	check(host.motion._facing_target > 1.0,"main anticipation assigns right heading without LivingBehavior")
	var origin: Vector2 = host.autonomy.position
	host.autonomy.advance(2.0)
	check(host.autonomy.state == "anticipate" and host.autonomy.position == origin,"real readiness closure blocks translation before heading")
	host.avatar.rotation.y = 0.8
	host._set_panel_open(true,false)
	check(host.autonomy.state == "paused" and host.motion._facing_target == 0.0,"panel pause happens before explicit front-facing request")
	host.autonomy.advance(0.1)
	check(host.motion._facing_target == 0.0,"stable paused frame does not cancel front request")
	host._set_panel_open(false,false)
	host._push_autonomy_context() # normal next main frame clears the collapsed panel block
	host.autonomy.set_pointer_interaction(false)
	host.autonomy.advance(3.0)
	host.autonomy.observe_interest("again",Vector2(1300,400),1,120)
	check(host.autonomy.move_to_interest("again"),"fresh destination accepted after panel settle")
	host.autonomy.update_context(false,false,false,true,false)
	check(is_equal_approx(host.motion._facing_target,host.avatar.rotation.y),"manual drag cancels pending destination heading")
	var living := LivingBehavior.new()
	host.add_child(living)
	living.host = host
	host.motion.set_heading_intent(Vector2.RIGHT)
	living._navigation_finished("timeout","heading_timeout")
	check(is_equal_approx(host.motion._facing_target,host.avatar.rotation.y),"heading timeout cancels remaining turn intent")
	host.free()
	print("Host heading: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
