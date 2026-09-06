extends SceneTree

const Autonomy = preload("res://scripts/desktop_autonomy.gd")
var failures := 0
var checks := 0
const BOUNDS := Rect2(400, 120, 220, 560)

func _initialize() -> void:
	geometry_tests()
	motion_tests()
	interest_tests()
	state_tests()
	print("Desktop autonomy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures or checks < 3636 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func make_pet(areas: Array[Rect2], origin: Vector2 = Vector2(0, 0)) -> Node:
	var pet = Autonomy.new()
	pet.configure_simulation(areas, origin, BOUNDS)
	pet.update_context(false, false, false, false, false)
	pet._next_decision = 100000.0
	pet.advance(2.6)
	return pet

func geometry_tests() -> void:
	var pet = make_pet([Rect2(-1920, 0, 1920, 1040), Rect2(0, 0, 1920, 1040)])
	check(pet.is_origin_safe(Vector2(-1920 + 4 - 400, -116)), "negative origin safe")
	check(pet.is_origin_safe(Vector2(-510, 0)), "adjacent monitor seam is traversable")
	check(not pet.is_origin_safe(Vector2(0, 361)), "taskbar excluded")
	check(pet._path_safe(Vector2(-1800, 0), Vector2(800, 0)), "continuous dual-monitor path")
	pet.set_workareas([Rect2(-1920, 0, 1920, 1040), Rect2(100, 0, 1920, 1040)])
	check(not pet._path_safe(Vector2(-1800, 0), Vector2(800, 0)), "monitor gap cannot be crossed")
	pet.free()
	pet = make_pet([Rect2(0, 0, 160, 300)])
	check(pet.state == "no_space", "pet larger than workarea pauses")
	check(pet.position == Vector2.ZERO, "no impossible tiny-screen relocation")
	pet.free()
	pet = make_pet([Rect2(0, 0, 240, 600)], Vector2(1000, 1000))
	check(pet.is_origin_safe(pet.position), "small fitting workarea clamps safely")
	pet.free()

func motion_tests() -> void:
	var areas: Array[Rect2] = [Rect2(-1920, 0, 3840, 1040)]
	var pet = make_pet(areas)
	pet.observe_interest("destination", Vector2(1300, 400), 1.0, 120.0)
	check(pet.move_to_interest("destination"), "explicit target accepted")
	var previous_velocity: Vector2 = pet.velocity
	var previous_position: Vector2 = pet.position
	for i in 900:
		var dt: float = [1.0 / 30.0, 1.0 / 144.0, 0.024, 1.0 / 60.0][i % 4]
		pet.advance(dt)
		check(pet.velocity.length() <= pet.speed + 0.01, "speed cap")
		check(pet.velocity.distance_to(previous_velocity) <= pet.acceleration * dt + 0.05, "acceleration cap")
		check(pet.position.distance_to(previous_position) <= pet.speed * dt + 0.01, "frame independent displacement cap")
		check(pet.is_origin_safe(pet.position), "moving pet remains on usable desktop")
		previous_velocity = pet.velocity
		previous_position = pet.position
	pet.update_context(true, false, false, false, false)
	var stopped: Vector2 = pet.position
	pet.advance(5.0)
	check(pet.position == stopped and pet.state == "paused", "panel pauses movement")
	pet.update_context(false, false, false, false, false)
	pet.advance(1.0)
	check(pet.position == stopped, "resumption settles")
	pet.set_enabled(false)
	pet.advance(10.0)
	check(pet.position == stopped, "disabled freezes")
	pet.set_enabled(true)
	pet.advance(1.0)
	check(pet.position == stopped, "toggle on settles")
	pet.advance(2.0)
	pet.observe_interest("again", Vector2(-1000, 400), 1.0, 120.0)
	check(pet.move_to_interest("again"), "resumed movement allowed")
	pet.advance(0.5)
	check(pet.position.distance_to(stopped) <= pet.speed * 0.1 + 0.01, "long frame cannot jump")
	pet.set_pointer_interaction(true)
	stopped = pet.position
	pet.advance(5.0)
	check(pet.position == stopped, "pointer interaction pauses")
	pet.set_pointer_interaction(false)
	for context in [[false,true,false,false,false], [false,false,true,false,false], [false,false,false,true,false], [false,false,false,false,true]]:
		pet.update_context(context[0], context[1], context[2], context[3], context[4])
		pet.advance(3.0)
		check(pet.position == stopped, "foreground context pauses")
	pet.update_context(false, false, false, false, false)
	pet.set_workareas([Rect2(2000, 0, 1920, 1040)])
	pet.advance(3.0)
	check(pet.is_origin_safe(pet.position), "monitor reconfiguration recovers")
	pet.free()
	var a = make_pet(areas)
	var b = make_pet(areas)
	for p in [a,b]:
		p.observe_interest("same", Vector2(1300, 400), 1.0, 120.0)
		p.move_to_interest("same")
	for i in 120:
		a.advance(1.0/60.0)
	for i in 240:
		b.advance(1.0/120.0)
	check(a.position.distance_to(b.position) < 0.01, "60 and 120 Hz trajectories match")
	a.free()
	b.free()

func interest_tests() -> void:
	var pet = make_pet([Rect2(0, 0, 1920, 1040)])
	pet.observe_interest("expired", Vector2(1300, 400), 1.0, 0.1, "future_vlm")
	pet.advance(0.2)
	check(not pet.move_to_interest("expired"), "future interest TTL enforced")
	pet.observe_interest("fresh", Vector2(1300, 400), 1.0, 10.0, "future_vlm")
	check(pet.move_to_interest("fresh"), "fresh future interest accepted")
	check(not pet._interests.has("fresh"), "interest consumed once")
	for i in 100:
		pet.observe_interest(str(i), Vector2(1000,400), 0.5, 20.0)
	check(pet._interests.size() == pet.MAX_INTERESTS, "interest queue bounded")
	pet.observe_interest("invalid", Vector2.INF, 1.0, 20.0)
	check(not pet._interests.has("invalid"), "nonfinite point rejected")
	pet.free()

func state_tests() -> void:
	var pet = make_pet([Rect2(0, 0, 1920, 1040)])
	pet.set_speed(500.0)
	check(pet.speed == 160.0, "maximum configured speed bounded")
	pet.set_speed(0.0)
	check(pet.speed == 20.0, "minimum configured speed bounded")
	pet.set_speed(75.0)
	pet.observe_interest("nearby", pet.position + BOUNDS.get_center() + Vector2(150, 0), 1.0, 20.0)
	check(pet.move_to_interest("nearby"), "nearby curiosity target accepted")
	var saw_inspect := false
	for i in 600:
		pet.advance(1.0 / 120.0)
		if pet.state == "inspect":
			saw_inspect = true
			break
	check(saw_inspect, "walk arrives and enters inspect")
	var stopped: Vector2 = pet.position
	pet.advance(1.0)
	check(pet.position == stopped and pet.state == "inspect", "inspection holds still")
	pet.advance(2.1)
	check(pet.state == "rest" and pet.position == stopped, "inspection proceeds to rest")
	pet.advance(6.0)
	check(pet.state == "rest" and pet.position == stopped, "rest prevents random jitter")
	pet.advance(1.1)
	check(pet.state == "walk", "rest resumes autonomous landmark choice")
	pet._travel_until = pet._time + 0.1
	pet.advance(0.2)
	check(pet.state == "rest" and pet.velocity == Vector2.ZERO, "travel watchdog stops stale movement")
	pet.free()
