class_name BehaviorDirector
extends RefCounted
## Deterministic, local-only behavior sequencing. No network/LLM, audio, OS or file access.
signal intent_outcome(id: String, outcome: String)

const MAX_INTERESTS := 16
const MAX_INTENTS := 16
const MAX_HISTORY := 64
const ATTENTION_COOLDOWN := 30.0
const MOVE_COOLDOWN := 35.0
const MAX_INTENT_TTL := 120.0
# Native heading wait <=6s + travel watchdog <=35s, with a small frame margin.
const NAVIGATION_COMPLETION_SECONDS := 45.0
const STYLE_DEFAULTS := {"idle_interval_s": 12.0, "gaze_hold_s": 2.0,
	"response_delay_s": 0.25, "curiosity": 0.5, "posture_strength": 0.5}

var curiosity = preload("curiosity_policy.gd").new()
var fly_circuit = preload("fly_curiosity_circuit.gd").new()
var fly_enabled := false
var fly_async := true
var _fly_request_point := Vector2.INF
var _fly_request_revision := -1
var _fly_request_time := -INF
var preference_provider: Callable
var curiosity_enabled := true
var curiosity_drive: Dictionary = {}
var curiosity_decisions: Array[Dictionary] = []
var _next_curiosity_check := 12.0
var character_id := ""
var interest_revision := 0
var state := "rest"
var style: Dictionary = STYLE_DEFAULTS.duplicate()
var _time := 0.0
var _handoff_queue_id := ""
var _phase_until := 12.0
var _next_dispatch := 0.0
var _next_move := 20.0
var _cycle := 0
var _interests: Dictionary = {}
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _history: Dictionary = {}
var _last_attention: Dictionary = {}
var _last_move_target := ""
var _attention := Vector2.INF
var _attention_id := ""
var _outcomes: Array[Dictionary] = []
var _preempted := false
var _pending_cancel: Dictionary = {}
var _posture_allowed := true
var _changing_character := false

func configure_curiosity(enabled: bool, use_fly: bool) -> void:
	if curiosity_enabled != enabled or fly_enabled != use_fly:
		fly_circuit.reset()
		_fly_request_revision = -1
	curiosity_enabled = enabled
	fly_enabled = use_fly
	if not enabled or not use_fly: fly_circuit.poll() # reap invalidated finished work

func configure_style(values: Dictionary) -> void:
	for key in STYLE_DEFAULTS:
		var value := float(values.get(key, STYLE_DEFAULTS[key]))
		if not is_finite(value):
			value = float(STYLE_DEFAULTS[key])
		match key:
			"idle_interval_s": value = clampf(value, 4.0, 120.0)
			"gaze_hold_s": value = clampf(value, 0.3, 8.0)
			"response_delay_s": value = clampf(value, 0.0, 2.0)
			_: value = clampf(value, 0.0, 1.0)
		style[key] = value

func set_character(value: String) -> void:
	if value == character_id or _changing_character:
		return
	_changing_character = true
	cancel_all("character_changed")
	_handoff_queue_id = ""
	character_id = value
	_interests.clear()
	_history.clear()
	_last_attention.clear()
	_last_move_target = ""
	curiosity.reset()
	fly_circuit.reset()
	curiosity_decisions.clear()
	_next_curiosity_check = _time + 12.0
	interest_revision += 1
	_attention = Vector2.INF
	_attention_id = ""
	_phase_until = _time + float(style.idle_interval_s)
	_next_move = _phase_until
	state = "rest"
	_changing_character = false

func observe_interest(id: String, point: Vector2, confidence: float = 0.5,
		ttl: float = 30.0, kind: String = "point", label: String = "") -> bool:
	if id.is_empty() or id.length() > 96 or not point.is_finite() or not is_finite(ttl) or ttl <= 0.0:
		return false
	if kind not in ["window", "floor", "surface", "point", "prop", "pointer"]:
		kind = "point"
	_expire()
	if not _interests.has(id) and _interests.size() >= MAX_INTERESTS:
		return false
	var entry := {"id": id, "point": point, "confidence": clampf(confidence, 0.0, 1.0),
		"expires": _time + minf(ttl, 120.0), "kind": kind, "label": label.left(80)}
	if not _interests.has(id) or _interests[id].point != point or _interests[id].kind != kind or _interests[id].label != entry.label:
		interest_revision += 1
	_interests[id] = entry
	return true

func interest_catalogue() -> Array[Dictionary]:
	_expire()
	var result: Array[Dictionary] = []
	for id: String in _interests:
		var entry: Dictionary = _interests[id]
		result.append({"id": id, "kind": entry.kind, "label": entry.label})
	return result

func request_intent(id: String, kind: String, target_id: String = "", source: String = "user",
		ttl: float = 30.0, duration_s: float = 6.0, for_character: String = "", locomotion_id: String = "") -> Dictionary:
	if _changing_character:
		return {"accepted": false, "reason": "stale_character"}
	_expire()
	if id.is_empty() or id.length() > 160 or kind not in ["move_to", "inspect", "rest"] or source not in ["user", "llm", "local"]:
		return {"accepted": false, "reason": "invalid"}
	if not locomotion_id.is_empty() and kind != "move_to":
		return {"accepted":false,"reason":"invalid_locomotion"}
	if not for_character.is_empty() and for_character != character_id:
		return {"accepted": false, "reason": "stale_character"}
	if not is_finite(ttl) or ttl <= 0.0 or not is_finite(duration_s):
		return {"accepted": false, "reason": "expired"}
	if _history.has(id) or (not _active.is_empty() and _active.id == id):
		return {"accepted": false, "reason": "duplicate"}
	for queued in _queue:
		if queued.id == id or (source == "llm" and queued.source == source and queued.kind == kind and queued.target_id == target_id):
			return {"accepted": false, "reason": "duplicate"}
	if kind != "rest" and not _interests.has(target_id):
		return {"accepted": false, "reason": "unknown_target"}
	if not _active.is_empty():
		if source == "llm" and _active.source == source and _active.kind == kind and _active.target_id == target_id:
			return {"accepted": false, "reason": "duplicate"}
		if _source_priority(source) > _source_priority(str(_active.source)) or (source == "user" and _active.source == "user"):
			cancel_intent(str(_active.id), "superseded")
	# Outcome listeners can synchronously cancel or enqueue other intentions.
	# Iterate a snapshot; cancel_intent detaches ownership before emitting.
	for queued in _queue.duplicate():
		if _source_priority(source) > _source_priority(str(queued.source)) or (source == "user" and queued.source == "user"):
			cancel_intent(str(queued.id), "superseded")
	# A supersession listener can itself submit this incoming ID.
	if _history.has(id) or (not _active.is_empty() and _active.id == id):
		return {"accepted": false, "reason": "duplicate"}
	for queued in _queue:
		if queued.id == id:
			return {"accepted": false, "reason": "duplicate"}
	if _queue.size() >= MAX_INTENTS:
		return {"accepted": false, "reason": "queue_full"}
	_queue.append({"id": id, "kind": kind, "target_id": target_id, "source": source,
		"expires": _time + minf(ttl, MAX_INTENT_TTL), "duration_s": clampf(duration_s, 1.0, 30.0),
		"character": character_id, "queued_at": _time, "locomotion_id":locomotion_id})
	return {"accepted": true, "reason": "queued"}

func cancel_intent(id: String, reason: String = "cancelled") -> bool:
	if not _active.is_empty() and _active.id == id:
		if _active.kind == "move_to":
			_pending_cancel = {"type": "cancel_move", "id": id, "reason": reason}
		_finish_active(reason)
		return true
	for i in _queue.size():
		if _queue[i].id == id:
			_queue.remove_at(i)
			_record_outcome(id, reason)
			return true
	return false

func cancel_all(reason: String = "cancelled") -> void:
	fly_circuit.reset()
	_fly_request_revision = -1
	var queued := _queue.duplicate()
	_queue.clear()
	# Retired IDs stay deduplicated even before their individual notifications.
	for intent in queued:
		_history[str(intent.id)] = _time + 180.0
	if not _active.is_empty():
		cancel_intent(str(_active.id), reason)
	for intent in queued:
		_record_outcome(str(intent.id), reason)

func resolve_intent(id: String, outcome: String) -> bool:
	_expire()
	if _active.is_empty() or _active.id != id:
		return false
	if outcome == "started":
		if _active.kind != "move_to":
			return false
		if not bool(_active.get("started", false)):
			_active["started"] = true
			_active["navigation_deadline"] = _time + NAVIGATION_COMPLETION_SECONDS
		return true
	if outcome == "blocked":
		if bool(_active.get("started", false)):
			return false # accepted navigation cannot restart its freshness clock
		var pending := _active.duplicate()
		_active.clear()
		_queue.push_front(pending)
		_next_dispatch = _time + 1.0
		return true
	_finish_active(outcome)
	return true

func navigation_result(target_id: String, outcome: String) -> bool:
	if _active.is_empty() or _active.kind != "move_to" or _active.target_id != target_id:
		return false
	return resolve_intent(str(_active.id), outcome)

func drain_outcomes() -> Array[Dictionary]:
	var result := _outcomes.duplicate(true)
	_outcomes.clear()
	return result

func tick(delta: float, context: Dictionary) -> Dictionary:
	if is_finite(delta) and delta > 0.0:
		_time += delta
	if context.has("character_id") and str(context.character_id) != character_id:
		set_character(str(context.character_id))
	_expire()
	_posture_allowed = not bool(context.get("preview_active", false)) and not bool(context.get("dialogue_gesture_active", false))
	if not _handoff_queue_id.is_empty() and not _queue.any(func(entry): return entry.id == _handoff_queue_id):
		_pending_cancel = {"type":"cancel_move", "id":_handoff_queue_id, "reason":"replacement_invalidated"}
		_handoff_queue_id = ""
	var action: Dictionary = _pending_cancel
	_pending_cancel = {}
	# Only a still-fresh queued replacement move can request the narrow native
	# handoff. Derive it at emission, after expiry/removal and user arbitration.
	if action.get("reason", "") == "superseded" and not _queue.is_empty():
		var replacement: Dictionary = _queue[0]
		for candidate in _queue:
			if _source_priority(str(candidate.source)) > _source_priority(str(replacement.source)):
				replacement = candidate
		if replacement.kind == "move_to" and _interests.has(replacement.target_id):
			action["replacement_point"] = _interests[replacement.target_id].point
			_handoff_queue_id = str(replacement.id)
	var priority := _priority_state(context)
	if not priority.is_empty():
		if not _preempted and not _active.is_empty():
			if _active.kind == "move_to":
				action = {"type": "cancel_move", "id": _active.id, "reason": "preempted"}
			_finish_active("preempted")
		_preempted = true
		state = priority
		var pointer: Variant = context.get("pointer_point", Vector2.INF)
		_attention = pointer if pointer is Vector2 and pointer.is_finite() and priority != "held" else Vector2.INF
		return _snapshot(action)
	if _preempted:
		_preempted = false
		_next_dispatch = _time + float(style.response_delay_s)
		_phase_until = _time + float(style.idle_interval_s)
		state = "rest"
	if not _active.is_empty():
		if _active.kind == "move_to":
			var movement := str(context.get("autonomy_state", "rest"))
			state = movement if movement in ["anticipate", "walk", "arrive", "approach"] else "attentive"
		elif _time >= float(_active.get("until", INF)):
			_finish_active("completed")
		else:
			state = "curious" if _active.kind == "inspect" else "rest"
		return _snapshot(action)
	if action.is_empty() and _time >= _next_dispatch and not _queue.is_empty():
		_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _source_priority(a.source) > _source_priority(b.source))
		var intent := _queue[0]
		if intent.kind != "move_to" or bool(context.get("can_move", false)):
			_queue.pop_front()
			_handoff_queue_id = ""
			_active = intent
			if intent.kind == "move_to":
				var interest: Dictionary = _interests[intent.target_id]
				_active["target_point"] = interest.point
				action = {"type": "move_interest", "id": intent.id, "target_id": intent.target_id,
					"point": interest.point, "kind": interest.kind, "locomotion_id":intent.get("locomotion_id",""), "ttl": maxf(0.1, float(intent.expires) - _time)}
				_attention = interest.point
				state = "anticipate"
				_next_move = _time + MOVE_COOLDOWN
				_last_move_target = str(intent.target_id)
			else:
				_active["until"] = _time + float(intent.duration_s)
				state = "curious" if intent.kind == "inspect" else "rest"
				_attention = _interests[intent.target_id].point if intent.kind == "inspect" else Vector2.INF
				action = {"type": str(intent.kind), "id": intent.id, "target_id": intent.target_id,
					"duration_s": intent.duration_s, "point": _attention}
			return _snapshot(action)
	# Autonomous movement remains observable while the director did not dispatch it.
	var movement := str(context.get("autonomy_state", "rest"))
	if movement in ["anticipate", "walk", "arrive", "approach"]:
		state = movement
		return _snapshot(action)
	# Work is an idle presentation, never an exclusive body owner.
	if bool(context.get("working", false)):
		state = "working"
		return _snapshot(action)
	if state == "working": state = "rest"
	if curiosity_enabled and float(style.curiosity) > 0.0 and _queue.is_empty() and bool(context.get("can_move", false)) and _time >= _next_curiosity_check:
		var position: Vector2 = context.get("actor_point", Vector2.INF)
		var candidates: Array = []
		for item in _interests.values():
			if item.kind not in ["surface","floor"]:continue
			var candidate: Dictionary = item.duplicate()
			if preference_provider.is_valid(): candidate["preference_bonus"] = preference_provider.call(candidate)
			candidates.append(candidate)
		curiosity_drive = {}
		if fly_enabled and fly_circuit.is_ready():
			if fly_async:
				curiosity_drive = fly_circuit.poll()
				if _fly_request_revision != interest_revision or position.distance_to(_fly_request_point) > 10.0 or _time-_fly_request_time > 5.0:
					if not curiosity_drive.is_empty(): fly_circuit.reset() # discard recurrent state as well as drive
					curiosity_drive = {}
				if curiosity_drive.is_empty():
					if not fly_circuit.pending():
						_fly_request_point = position; _fly_request_revision = interest_revision; _fly_request_time = _time
						fly_circuit.begin(curiosity.sensory(candidates, position, _time))
					return _snapshot(action)
			else: curiosity_drive = fly_circuit.step(curiosity.sensory(candidates, position, _time))
		_next_curiosity_check = _time + 5.0
		if not curiosity_drive.is_empty(): curiosity_drive["heading"] = Vector2.UP # explicit screen-left/right steering adapter
		var decision: Dictionary = curiosity.choose(candidates, position, _time, curiosity_drive)
		decision["drive"] = curiosity_drive.duplicate(true)
		decision["time"] = _time
		decision["position"] = position
		curiosity_decisions.append(decision.duplicate(true))
		if curiosity_decisions.size() > 64: curiosity_decisions.pop_front()
		var chosen := str(decision.get("target_id", ""))
		if not chosen.is_empty():
			_cycle += 1
			request_intent("local:curiosity:%d" % _cycle, "move_to", chosen, "local", 45.0)
			return _snapshot(action)
	if _time >= _phase_until:
		_cycle += 1
		if state == "curious" or state == "sleepy":
			state = "rest"
			_attention = Vector2.INF
			_attention_id = ""
			_phase_until = _time + float(style.idle_interval_s) * (1.0 + float(_cycle % 3) * 0.25)
		else:
			var target_id := _choose_attention()
			if not target_id.is_empty() and float(style.curiosity) > 0.0 and _cycle % 4 != 0 and _cycle % 5 != 0:
				state = "curious"
				_attention_id = target_id
				_attention = _interests[target_id].point
				_last_attention[target_id] = _time
				_phase_until = _time + float(style.gaze_hold_s)
				# Local exploration is intermittent and explicit, never an LLM call.
				if not curiosity_enabled and _cycle % 3 == 0 and _time >= _next_move and bool(context.get("can_move", false)) and _interests[target_id].kind in ["surface", "floor"]:
					var move_target := target_id
					if move_target == _last_move_target:
						var choices := _interests.keys();choices.sort()
						for candidate in choices:
							if candidate != _last_move_target and _interests[candidate].kind in ["surface","floor"]:
								move_target=candidate;break
					if move_target != _last_move_target:request_intent("local:%d" % _cycle, "move_to", move_target, "local", 30.0)
			else:
				state = "sleepy" if _cycle % 5 == 0 else "rest"
				_attention = Vector2.INF
				_phase_until = _time + float(style.idle_interval_s)
	return _snapshot(action)

## Accepted non-local actions retain their body while conversation uses attention.
func has_explicit_body_intent() -> bool:
	return not _active.is_empty() and _active.get("source", "local") != "local"


func _priority_state(context: Dictionary) -> String:
	for pair in [["dragging", "held"], ["speaking", "speaking"], ["listening", "listening"],
		["thinking", "thinking"], ["panel_open", "attentive"], ["pointer_interaction", "attentive"]]:
		if bool(context.get("body_continuing", false)) and pair[0] in ["speaking", "listening", "thinking", "pointer_interaction", "panel_open"]: continue
		if bool(context.get(pair[0], false)):
			return pair[1]
	return ""

func _snapshot(action: Dictionary) -> Dictionary:
	var ambient := state if state in ["rest", "curious", "anticipate", "sleepy", "attentive", "listening", "thinking", "working"] else "settle"
	if state in ["speaking", "held"]:
		ambient = "rest"
	return {"state": state, "ambient": ambient, "strength": float(style.posture_strength) if _posture_allowed else 0.0,
		"attention_point": _attention, "attention_strength": float(style.curiosity) if _attention.is_finite() else 0.0,
		"action": action, "intent_id": _active.get("id", ""), "interest_revision": interest_revision}

func _choose_attention() -> String:
	var ids := _interests.keys()
	ids.sort()
	for offset in ids.size():
		var id: String = ids[(_cycle + offset) % ids.size()]
		if _time - float(_last_attention.get(id, -INF)) >= ATTENTION_COOLDOWN:
			return id
	return ""

func _source_priority(source: String) -> int:
	return 3 if source == "user" else (2 if source == "llm" else 1)

func _finish_active(outcome: String) -> void:
	if _active.is_empty():
		return
	var id := str(_active.id)
	if id.begins_with("local:curiosity:"):
		curiosity.observe_arrival(str(_active.target_id), Vector2(_active.get("target_point", Vector2.INF)), _time, outcome)
	_active.clear()
	state = "rest"
	_attention = Vector2.INF
	_attention_id = ""
	_phase_until = _time + float(style.idle_interval_s)
	_next_dispatch = _time + float(style.response_delay_s)
	_record_outcome(id, outcome)

func _record_outcome(id: String, outcome: String) -> void:
	_history[id] = _time + 180.0
	if _history.size() > MAX_HISTORY:
		_history.erase(_history.keys()[0])
	_outcomes.append({"id": id, "outcome": outcome, "time": _time})
	if _outcomes.size() > MAX_HISTORY:
		_outcomes.pop_front()
	intent_outcome.emit(id, outcome)

func _expire() -> void:
	for id: String in _interests.keys():
		if float(_interests[id].expires) <= _time:
			_interests.erase(id)
			_last_attention.erase(id)
			interest_revision += 1
	for intent in _queue.duplicate():
		if float(intent.expires) <= _time or (intent.kind != "rest" and not _interests.has(intent.target_id)):
			cancel_intent(str(intent.id), "expired")
	if not _active.is_empty() and (float(_active.get("navigation_deadline", _active.expires)) <= _time or (_active.kind != "rest" and not _interests.has(_active.target_id))):
		cancel_intent(str(_active.id), "expired")
	for id: String in _history.keys():
		if float(_history[id]) <= _time:
			_history.erase(id)
	if not _attention_id.is_empty() and not _interests.has(_attention_id):
		_attention_id = ""
		_attention = Vector2.INF


func remove_interest(id: String) -> bool:
	if not _interests.has(id):
		return false
	_interests.erase(id)
	_last_attention.erase(id)
	interest_revision += 1
	if not _active.is_empty() and _active.target_id == id:
		cancel_intent(str(_active.id), "target_removed")
	for intent in _queue.duplicate():
		if intent.target_id == id:
			cancel_intent(str(intent.id), "target_removed")
	if _attention_id == id:
		_attention = Vector2.INF
		_attention_id = ""
	return true

## Cross-owner arbitration: furniture may not displace an explicit user intention.
func has_user_intent() -> bool:
	_expire()
	if not _active.is_empty() and _active.get("source","") == "user": return true
	for intent in _queue:
		if intent.get("source","") == "user": return true
	return false
