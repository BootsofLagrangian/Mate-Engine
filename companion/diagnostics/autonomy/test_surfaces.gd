extends SceneTree
const Geometry = preload("res://scripts/desktop_surfaces.gd")
const Autonomy = preload("res://scripts/desktop_autonomy.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	geometry_tests()
	contact_tests()
	print("Desktop surfaces: %d checks, %d failures" % [checks, failures])
	quit(1 if failures or checks < 769 else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func snapshot(windows: Array = []) -> Dictionary:
	return {"version": 1, "timestamp_msec": 1000, "monitors": [
		{"id": "left", "x": -1920, "y": 0, "width": 1920, "height": 1080,
		 "work_x": -1920, "work_y": 0, "work_width": 1920, "work_height": 1040},
		{"id": "right", "x": 0, "y": 0, "width": 1920, "height": 1080,
		 "work_x": 0, "work_y": 0, "work_width": 1920, "work_height": 1040}], "windows": windows}

func filtered(surfaces: Array, source: String) -> Array:
	return surfaces.filter(func(s: Dictionary) -> bool: return s.source_id == source)

func geometry_tests() -> void:
	var g = Geometry.new()
	var back := {"id": "back", "x": 100, "y": 700, "width": 1200, "height": 300, "z": 2}
	var front := {"id": "front", "x": 500, "y": 600, "width": 300, "height": 300, "z": 0}
	g.set_world_snapshot(snapshot([back, front]))
	var lines: Array = filtered(g.get_surfaces(220), "window:back")
	check(lines.size() == 2, "foreground window splits rear top edge")
	check(lines[0].x1 == 100.0 and lines[0].x2 == 500.0, "left visible segment exact")
	check(lines[1].x1 == 800.0 and lines[1].x2 == 1300.0, "right visible segment exact")
	check(filtered(g.get_surfaces(450), "window:back").size() == 1, "minimum pet width removes short segment")
	check(filtered(g.get_surfaces(600), "window:back").is_empty(), "scale excludes narrow supports")
	var initial_id: String = lines[0].id
	g.set_world_snapshot(snapshot([front, back]))
	check(filtered(g.get_surfaces(220), "window:back")[0].id == initial_id, "IDs independent of window input order")
	front.z = 4
	g.set_world_snapshot(snapshot([back, front]))
	check(filtered(g.get_surfaces(220), "window:back").size() == 1, "rear windows do not occlude front top edge")
	front.z = 0
	front.x = 0
	front.width = 1920
	g.set_world_snapshot(snapshot([back, front]))
	check(filtered(g.get_surfaces(220), "window:back").is_empty(), "fully occluded top removed")
	var cross := {"id": "cross", "x": -400, "y": 800, "width": 800, "height": 100, "z": 0}
	g.set_world_snapshot(snapshot([cross]))
	lines = filtered(g.get_surfaces(220), "window:cross")
	check(lines.size() == 2, "cross-monitor top clipped per monitor")
	check(lines[0].x1 == -400.0 and lines[0].x2 == 0.0, "negative monitor coordinates preserved")
	check(filtered(g.get_surfaces(220), "floor:left")[0].y == 1040.0, "floor follows usable edge above taskbar")
	g.set_authored_surfaces([{"id": "shelf", "x1": -3000, "x2": -1000, "y": 700}])
	lines = filtered(g.get_surfaces(220), "authored:shelf")
	check(lines.size() == 1 and lines[0].x1 == -1920.0, "authored line clipped to monitor")
	g.set_world_snapshot(snapshot([]))
	check(filtered(g.get_surfaces(220), "window:cross").is_empty(), "closed window edge removed")

func tick(pet: Node, world: Dictionary, count: int = 1) -> void:
	for i in count:
		pet.set_world_snapshot(world)
		pet.advance(1.0 / 60.0)

func attach(pet: Node, world: Dictionary) -> void:
	for i in 1200:
		tick(pet, world)
		if pet.get_support_contact().attached:
			return

func contact_tests() -> void:
	var window := {"id": "shelf", "x": 300, "y": 700, "width": 1000, "height": 300, "z": 0}
	var world := snapshot([window])
	var pet = Autonomy.new()
	pet.configure_simulation([Rect2(-1920, 0, 1920, 1040), Rect2(0, 0, 1920, 1040)], Vector2.ZERO, Rect2(400, 120, 220, 560))
	pet.set_world_snapshot(world)
	pet.set_surface_mode(true)
	pet.update_context(false, false, false, false, false)
	attach(pet, world)
	check(pet.get_support_contact().attached, "nearby window acquired smoothly")
	check(pet.get_support_contact().kind == "window", "nearest support selected")
	check(absf(pet.get_support_contact().screen_point.y - 700.0) < 0.01, "foot anchor contacts window top")
	pet.observe_interest("walk", Vector2(1100, 700), 1.0, 20.0)
	check(pet.move_to_interest("walk"), "lateral target on attached support accepted")
	var y: float = pet.position.y
	for i in 240:
		var previous: Vector2 = pet.position
		tick(pet, world)
		check(absf(pet.position.y - y) < 0.001, "ground walk strictly horizontal")
		check(pet.position.distance_to(previous) <= pet.speed / 60.0 + 0.01, "ground walk speed bounded")
		check(pet.is_origin_safe(pet.position), "ground walk remains visible")
	check(pet.get_support_contact().attached, "ground walk retains support")
	var before: Vector2 = pet.position
	window.y = 740
	world = snapshot([window])
	pet.set_world_snapshot(world)
	check(not pet.get_support_contact().attached, "moving window detaches")
	check(pet.position == before, "moving window never teleports pet")
	pet.advance(1.0)
	check(pet.position == before, "detached pet settles")
	attach(pet, world)
	check(pet.get_support_contact().attached, "moved support re-acquired smoothly")
	check(absf(pet.get_support_contact().screen_point.y - 740.0) < 0.01, "reacquired anchor follows new top")
	pet.update_context(false, false, false, true, false)
	check(not pet.get_support_contact().attached, "drag releases support")
	pet.position += Vector2(-100, -20)
	before = pet.position
	pet.advance(3.0)
	check(pet.position == before, "drag position authoritative")
	pet.update_context(false, false, false, false, false)
	attach(pet, world)
	check(pet.get_support_contact().attached, "drag release reacquires support")
	pet.set_contact_anchors({"foot": Vector2(510, 680), "sit": Vector2(510, 500)})
	pet.set_contact_pose("sit")
	before = pet.position
	check(not pet.get_support_contact().attached and pet.position == before, "pose transition detaches without jump")
	attach(pet, world)
	check(pet.get_support_contact().attached and pet.get_support_contact().pose == "sit", "sit anchor supported")
	check(absf(pet.get_support_contact().screen_point.y - 740.0) < 0.01, "sit anchor exact")
	pet.set_contact_pose("foot")
	attach(pet, world)
	pet.set_world_snapshot(snapshot([]))
	check(not pet.get_support_contact().attached, "closed window detaches support")
	attach(pet, snapshot([]))
	check(pet.get_support_contact().attached and pet.get_support_contact().kind == "floor", "closed window settles onto floor")
	check(absf(pet.get_support_contact().screen_point.y - 1040.0) < 0.01, "floor foot anchor exact")
	# A changing avatar scale releases the old anchor without chasing animation noise.
	before = pet.position
	pet.set_contact_anchors({"foot": Vector2(510, 720)})
	check(not pet.get_support_contact().attached and pet.position == before, "scale change detaches without teleport")
	attach(pet, snapshot([]))
	check(pet.get_support_contact().attached, "scaled anchor smoothly reattaches")
	pet.set_surface_mode(false)
	check(not pet.get_support_contact().attached, "surface mode off clears contact")
	pet.free()
	# Foreground interruption during an approach must not strand a pending target.
	pet = Autonomy.new()
	pet.configure_simulation([Rect2(0, 0, 1920, 1040)], Vector2.ZERO, Rect2(400, 120, 220, 560))
	pet.set_surface_mode(true)
	pet.update_context(false, false, false, false, false)
	pet.set_world_snapshot(snapshot([window]))
	for i in 160:
		tick(pet, snapshot([window]))
	check(pet.state == "approach", "approach begins after settling")
	pet.update_context(true, false, false, false, false)
	before = pet.position
	pet.advance(2.0)
	check(pet.position == before, "panel freezes approach")
	pet.update_context(false, false, false, false, false)
	attach(pet, snapshot([window]))
	check(pet.get_support_contact().attached, "interrupted approach resumes to support")
	var occluder := {"id": "front", "x": 0, "y": 600, "width": 1920, "height": 440, "z": -1}
	pet.set_world_snapshot(snapshot([window, occluder]))
	check(not pet.get_support_contact().attached, "new foreground occluder detaches support")
	check(pet.position.distance_to(before) < 200.0, "occlusion causes no teleport")
	pet.free()
	# Helper failure clears real window supports while retaining a floor fallback.
	pet = Autonomy.new()
	pet.configure_simulation([Rect2(0, 0, 1920, 1040)], Vector2.ZERO, Rect2(400, 120, 220, 560))
	pet.set_surface_mode(true)
	pet.update_context(false, false, false, false, false)
	pet.set_world_snapshot(snapshot([window]))
	attach(pet, snapshot([window]))
	pet.advance(6.0)
	check(not pet.get_support_contact().attached, "stale world window support expires")
	pet.set_world_snapshot({})
	check(not pet._surfaces.get_surfaces(220).is_empty(), "unavailable world keeps monitor floors")
	pet.set_workareas([Rect2(-1200, -800, 1200, 800)])
	var fallback_lines: Array = pet._surfaces.get_surfaces(220)
	check(fallback_lines.size() == 1 and fallback_lines[0].y == 0.0, "fallback floors follow monitor reconfiguration")
	pet.free()

	# A monitor resize while attached to an unavailable-source floor releases it.
	pet = Autonomy.new()
	pet.configure_simulation([Rect2(0, 0, 1920, 1040)], Vector2.ZERO, Rect2(400, 120, 220, 560))
	pet.set_surface_mode(true)
	pet.update_context(false, false, false, false, false)
	attach(pet, {})
	check(pet.get_support_contact().attached, "fallback floor initially attached")
	pet.set_workareas([Rect2(0, 0, 1920, 900)])
	check(not pet.get_support_contact().attached, "resized fallback floor releases obsolete support")
	attach(pet, {})
	check(pet.get_support_contact().attached and absf(pet.get_support_contact().screen_point.y - 900.0) < 0.01, "resized fallback floor reacquires exact new height")
	pet.free()
	pet = Autonomy.new()
	pet.configure_simulation([Rect2(0, 0, 1920, 1040)], Vector2.ZERO, Rect2(400, 120, 220, 560))
	pet.set_surface_mode(true)
	pet.update_context(false, false, false, false, false)
	for i in 160:
		tick(pet, {})
	check(pet.state == "approach", "scale regression starts during approach")
	pet.set_contact_anchors({"foot": Vector2(510, 720)})
	check(pet._pending_support.is_empty(), "scale during approach discards stale target")
	attach(pet, {})
	check(pet.get_support_contact().attached and pet.get_support_contact().local_anchor.y == 720.0, "approach resumes with current scale anchor")
	pet.free()
