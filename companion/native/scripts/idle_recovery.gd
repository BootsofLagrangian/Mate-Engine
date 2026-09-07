extends RefCounted
## One-shot return to the viewer after an interaction. Heading is requested once;
## the existing motion owner performs the grounded turn and idle cross-fade.
const MAX_AGE := 16.0
var phase := ""
var elapsed := 0.0
var age := 0.0
var reason := ""
var owns_heading := false

func queue(source: String) -> void:
	phase = "waiting"
	elapsed = 0.0
	age = 0.0
	reason = source
	owns_heading = false

func clear() -> void:
	phase = ""
	elapsed = 0.0
	age = 0.0
	reason = ""
	owns_heading = false

func active() -> bool:
	return not phase.is_empty()

func tick(delta: float, context: Dictionary) -> Dictionary:
	if not active(): return {}
	var dt := maxf(delta,0.0) if is_finite(delta) else 0.0
	age += dt
	# A new body owner always wins. Never brake its newly installed heading.
	if bool(context.get("superseded",false)):
		clear()
		return {"cancelled":true}
	if age >= MAX_AGE:
		var brake := owns_heading
		clear()
		return {"cancelled":true,"brake":brake}
	if bool(context.get("busy",false)):
		var brake := owns_heading
		phase = "waiting"
		elapsed = 0.0
		owns_heading = false
		return {"brake":brake}
	elapsed += dt
	match phase:
		"waiting":
			if elapsed >= 0.65:
				phase = "look"
				elapsed = 0.0
		"look":
			if elapsed >= 0.45:
				phase = "turn"
				elapsed = 0.0
				owns_heading = true
				return {"look":true,"turn":true}
		"turn":
			if bool(context.get("heading_ready",false)):
				phase = "settle"
				elapsed = 0.0
				owns_heading = false
		"settle":
			if elapsed >= 1.4:
				clear()
				return {"completed":true}
	return {"look":phase in ["look","turn"],"settle":phase == "settle"}
