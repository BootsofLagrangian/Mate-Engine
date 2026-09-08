extends RefCounted
## Occasional rests use only an already attached, verified desktop support.
## This policy neither finds windows nor changes their geometry/contact rules.
const COOLDOWN := 75.0
const STABLE_SECONDS := 6.0
const REST_SECONDS := 12.0
var clock := 0.0
var next_rest := COOLDOWN
var stable := 0.0
var observed_support := ""
var owned_support := ""
var rest_until := 0.0
var admitted_at := 0.0

func owns_rest() -> bool:
	return not owned_support.is_empty()

func admitted(support_id: String) -> void:
	owned_support = support_id
	admitted_at = clock
	rest_until = clock + REST_SECONDS
	next_rest = clock + COOLDOWN
	stable = 0.0

func reset() -> void:
	owned_support = ""
	observed_support = ""
	stable = 0.0
	next_rest = clock + COOLDOWN

func tick(delta: float, context: Dictionary) -> String:
	var dt := maxf(delta,0.0) if is_finite(delta) else 0.0
	clock += dt
	var support: Dictionary = context.get("support",{})
	var id := str(support.get("surface_id",""))
	var kind := str(support.get("kind",""))
	# Taskbar identity comes from the native shell geometry source, never an
	# inferred monitor work-area floor. Actual seat fitting stays in the host.
	var verified: bool = bool(support.get("attached",false)) and ((kind == "window" and id.begins_with("window:")) or (kind == "taskbar" and id.begins_with("taskbar:")))
	var busy := bool(context.get("busy",true))
	if owns_rest():
		# Native foot→seat anchor exchange briefly detaches by design. Give only
		# that admitted transition a short grace; ordinary support loss still yields.
		if not busy and not bool(support.get("attached",false)) and bool(context.get("rebinding",false)) and clock-admitted_at < 2.0:
			return ""
		if busy or not verified or id != owned_support or clock >= rest_until or not bool(context.get("sitting_or_pending",false)):
			reset()
			return "stand"
		return ""
	if not verified or busy or not bool(context.get("can_sit",false)):
		stable = 0.0
		observed_support = ""
		return ""
	if observed_support != id:
		observed_support = id
		stable = 0.0
	stable += dt
	if clock >= next_rest and stable >= STABLE_SECONDS:
		# Failed admission retries only after a full cooldown, not each frame.
		next_rest = clock + COOLDOWN
		stable = 0.0
		return "sit"
	return ""
