extends SceneTree
const Overlap = preload("res://scripts/action_overlap.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var overlap := Overlap.new()
	check(overlap.start("wave", 2.0, ["arms", "head", "torso"]), "start wave")
	check(overlap.queue("nod", 1.0, 0.35, ["head"]).accepted, "queue nod")
	var frame: Dictionary = overlap.advance(1.7)
	check(frame.outgoing.name == "wave" and frame.incoming.name == "nod", "nod starts before wave ends")
	check(frame.incoming.time > 0.0 and frame.outgoing.time == 1.7, "both actions sampled live")
	check(frame.outgoing.weight_by_channel.arms == 1.0, "wave arms retained")
	check(frame.incoming.weight_by_channel.head > 0.0, "nod head already moving")
	var previous := float(frame.incoming.weight_by_channel.head)
	for i in 29:
		frame = overlap.advance(0.01)
		var incoming := float(frame.incoming.weight_by_channel.head)
		check(incoming >= previous and incoming <= 1.0, "bounded monotonic shared blend")
		check(is_equal_approx(incoming + float(frame.outgoing.weight_by_channel.head), 1.0), "shared channels never reset to zero")
		check(frame.outgoing.weight_by_channel.arms == 1.0, "disjoint live arms survive entire overlap")
		previous = incoming
	frame = overlap.advance(0.01)
	check(frame.promoted and frame.current == "nod" and frame.finished == ["wave"], "promote nod")
	check(is_equal_approx(frame.outgoing.time, 0.35), "promotion preserves original incoming time")
	check(is_equal_approx(frame.outgoing.start_time, 1.65), "promotion preserves original start")
	frame = overlap.advance(0.65)
	check(not overlap.is_active() and frame.finished == ["nod"], "nod ends at original deadline")
	for support in ["sit", "lean"]:
		overlap.start("wave", 2.0, ["arms"])
		check(overlap.queue("support_change", 1.0, 0.35, ["torso"], support).gated, "support change gated")
		check(overlap.advance(1.9).incoming.is_empty(), "support action cannot start early")
		frame = overlap.advance(0.1)
		check(frame.promoted and frame.outgoing.time == 0.0, "support action starts at boundary")
	for channel in ["legs", "root"]:
		overlap.start("wave", 2.0, ["arms"])
		check(overlap.queue("full_body", 1.0, 0.35, [channel]).gated, "full-body incoming gated")
		overlap.start("full_body", 2.0, [channel])
		check(overlap.queue("nod", 1.0, 0.35, ["head"]).gated, "full-body outgoing gated")
		overlap.reset()
		check(not overlap.is_active() and overlap.advance(4.0).incoming.is_empty(), "reset cancels pending and primary")
	overlap.start("a", 2.0, ["arms"])
	overlap.queue("b", 1.0, 0.35, ["head"])
	check(not overlap.queue("c", 1.0).accepted, "bounded one-item queue")
	frame = overlap.advance(10.0)
	check(frame.finished == ["a", "b"] and not overlap.is_active(), "large delta never restarts expired incoming")
	check(not overlap.start("bad", NAN, ["head"]), "reject NaN duration")
	check(not overlap.queue("bad", 1.0, 0.3, ["unknown"]).accepted, "reject unknown channel")
	check(not overlap.queue("bad", 1.0, INF).accepted, "reject infinite lead")
	check(not overlap.queue("bad", 1.0, .3, ["head"], "flying").accepted, "reject unsupported support")
	overlap.start("late_a", 2.0, ["head"], "foot", 10.0)
	overlap.advance(1.9)
	overlap.queue("late_b", 1.0, .35, ["head"])
	frame = overlap.advance(.05)
	check(is_equal_approx(frame.incoming.time, .05), "late queue does not backdate incoming playback")
	# Pose consumer samples the outgoing action at its advancing time, rather
	# than blending from a frozen last-pose snapshot.
	overlap.start("wave", 2.0, ["arms", "head"])
	overlap.queue("nod", 1.0, .35, ["head"])
	frame = overlap.advance(1.75)
	var arm_before := sin(float(frame.outgoing.time) * 4.0) * float(frame.outgoing.weight_by_channel.arms)
	var head_mix := (10.0 + float(frame.outgoing.time)) * float(frame.outgoing.weight_by_channel.head) + (20.0 + float(frame.incoming.time)) * float(frame.incoming.weight_by_channel.head)
	check(head_mix > 10.0 and head_mix < 21.0, "same-channel samples blend without base-pose reset")
	frame = overlap.advance(.05)
	var arm_after := sin(float(frame.outgoing.time) * 4.0) * float(frame.outgoing.weight_by_channel.arms)
	check(not is_equal_approx(arm_before, arm_after), "outgoing arms remain live during incoming nod")
	overlap.reset()
	frame = overlap.advance(.1)
	check(frame.outgoing.is_empty() and frame.incoming.is_empty() and frame.queued == "", "cancel active overlap clears both samples")
	for rate in [30, 60, 120]:
		overlap.start("a", 2.0, ["head"])
		overlap.queue("b", 1.0, .35, ["head"])
		for step in rate * 2:
			overlap.advance(1.0 / float(rate))
		frame = overlap.advance(.1)
		check(frame.current == "b" and is_equal_approx(frame.outgoing.time, .45), "promotion is frame-rate independent")
	overlap.start("a", 2.0, ["head"])
	overlap.queue("brief", .1, 10.0, ["head"])
	frame = overlap.advance(1.96)
	check(is_equal_approx(frame.incoming.start_time, 1.95), "lead bounded by incoming half-duration")
	check(not overlap.start("bad", -1.0, ["head"]), "invalid replacement rejected")
	check(overlap.advance(0.0).outgoing.name == "a", "invalid replacement preserves current action")
	print("Action overlap: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
