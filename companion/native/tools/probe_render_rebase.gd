extends SceneTree

var failures: Array[String] = []
var passed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := DesktopAutonomy.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.configure_simulation([Rect2(-2000,-2000,8000,8000)],Vector2(100,200),Rect2(800,900,200,400))
	actor._anchors = {"foot":Vector2(900,1300), "sit":Vector2(900,1100)}
	actor._locked_anchor = actor._anchors.foot
	actor._support = {"id":"desk", "x1":0.0,"x2":3000.0,"y":1500.0}
	actor._pending_support = {"id":"other", "x1":0.0,"x2":3000.0,"y":1500.0}
	actor._interests = {"interest":{"point":Vector2(1700,1500)}}
	actor.target = Vector2(500,200)
	actor._last_frame_position = actor.position
	actor.velocity = Vector2(24,0)
	actor.state = "walk"
	actor._active_target_id = "interest"
	var origin := actor.position
	var global_foot: Vector2 = actor.position+actor._locked_anchor
	var global_destination: Vector2 = actor.target+actor._locked_anchor
	var global_bounds := Rect2(actor.position+actor.visible_bounds.position,actor.visible_bounds.size)
	var support: Dictionary = actor._support.duplicate(true)
	var pending: Dictionary = actor._pending_support.duplicate(true)
	var interests: Dictionary = actor._interests.duplicate(true)
	var shift := Vector2(320,520)
	actor.rebase_render_origin(shift)
	check(actor.position == origin+shift, "origin translated")
	check(actor.position+actor._locked_anchor == global_foot, "global foot preserved")
	check(actor.target+actor._locked_anchor == global_destination, "global destination preserved")
	check(Rect2(actor.position+actor.visible_bounds.position,actor.visible_bounds.size) == global_bounds, "global bounds preserved")
	check(actor._last_frame_position == actor.position, "no false native frame displacement")
	check(actor._anchors.foot == actor._locked_anchor, "local anchor cache rebased")
	check(actor._support == support and actor._pending_support == pending and actor._interests == interests, "desktop records unchanged")
	check(actor.state == "walk" and actor._active_target_id == "interest" and actor.velocity == Vector2(24,0), "motion owner and momentum preserved")
	actor.rebase_render_origin(Vector2.INF)
	check(actor.position == origin+shift, "invalid shift ignored")
	actor.rebase_render_origin(-shift)
	check(actor.position == origin and actor._last_frame_position == origin, "roundtrip origin exact")
	# Resize in a projection commit callback must not masquerade as actor travel.
	actor.state = "paused"
	actor._active_target_id = ""
	var observed: Array[Vector2] = []
	actor.frame_moved.connect(func(delta: Vector2, _velocity: Vector2): observed.append(delta))
	actor.projection_commit_callback = func(): actor.rebase_render_origin(shift)
	actor.advance(0.0)
	check(observed.size() == 1 and observed[0] == Vector2.ZERO, "mid-frame simulated rebase has zero travel")
	print("render rebase: %d passed, %d failed" % [passed,failures.size()])
	for failure in failures: print("FAIL: "+failure)
	actor.queue_free()
	quit(0 if failures.is_empty() else 1)
