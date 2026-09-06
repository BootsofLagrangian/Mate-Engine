class_name CompanionSession
extends RefCounted
## Protocol state machine for the companion v1 WebSocket contract.
## Pure logic: decides which server events belong to the live turn / owned job,
## tracks activity, and never touches nodes so it can be tested headless.

signal event_accepted(event: Dictionary)
signal event_discarded(event: Dictionary, reason: String)
signal turn_started(turn_id: String)
signal turn_finished(turn_id: String, outcome: String)
signal activity_changed(activity: String)
signal characters_changed(characters: Array)
signal character_changed(character_id: String)
signal job_changed(job: Dictionary)

const PROTOCOL := 1
const CONVERSATION_EVENTS := ["start", "text", "phrase", "tts_start", "audio", "tts_end", "action", "done", "error", "voice_error", "state", "cancelled"]
const JOB_TERMINAL := ["completed", "failed", "cancelled"]

var protocol: int = 0
var hello_received: bool = false
var capabilities: Dictionary = {}
var server_info: Dictionary = {}
var characters: Array = []
var character_id: String = ""
var turn_id: String = "" # active foreground (or adopted job:ack/result) turn
var turn_generating: bool = false
var turn_counter: int = 0
var cancelled_turns: Dictionary = {}
var activity: String = "idle" # idle | listening | thinking | speaking
var voice_active: bool = false # real local PCM playback (independent of generation)
var server_state: String = "idle"
var text: String = ""
var last_emotion: String = "neutral"
var last_gesture: String = "idle"
var job: Dictionary = {} # {job_id,status,message,log:[...]}


func reset_connection() -> void:
	hello_received = false
	voice_active = false
	if not turn_id.is_empty():
		var old := turn_id
		turn_id = ""
		turn_generating = false
		turn_finished.emit(old, "disconnected")
	if not job.is_empty() and not JOB_TERMINAL.has(job.get("status", "")):
		job["status"] = "cancelled"
		job["message"] = "disconnected"
		job_changed.emit(job)
	_set_activity("idle")


func new_turn() -> String:
	turn_counter += 1
	turn_id = "t%d-%d" % [turn_counter, Time.get_ticks_msec()]
	turn_generating = true
	text = ""
	turn_started.emit(turn_id)
	_set_activity("thinking")
	return turn_id


## Marks the active turn cancelled locally (caller sends {type:cancel}). Returns cancelled id.
func cancel_turn() -> String:
	var old := turn_id
	if old.is_empty():
		return ""
	cancelled_turns[old] = true
	turn_id = ""
	turn_generating = false
	turn_finished.emit(old, "cancelled")
	_set_activity("idle")
	return old


func is_foreground_busy() -> bool:
	return not turn_id.is_empty() and not turn_id.begins_with("job:") and turn_generating


## Foreground speech still audible locally (generation may already be done).
func is_foreground_playing() -> bool:
	return voice_active and not turn_id.is_empty() and not turn_id.begins_with("job:")


## Only ack/result turns of the job this connection owns may be adopted as speech.
func is_owned_job_turn(ev_turn: String) -> bool:
	if job.is_empty() or not ev_turn.begins_with("job:"):
		return false
	var jid := str(job.get("job_id", ""))
	return not jid.is_empty() and (ev_turn == "job:%s:ack" % jid or ev_turn == "job:%s:result" % jid)


func set_character(id: String) -> bool:
	if id == character_id:
		return false
	character_id = id
	character_changed.emit(id)
	return true


func character_by_id(id: String) -> Dictionary:
	for c in characters:
		if str(c.get("id", "")) == id:
			return c
	return {}


func new_job_id() -> String:
	return "job-%d-%d" % [Time.get_ticks_msec(), randi() % 10000]


func start_job(job_id: String, prompt: String) -> void:
	job = {"job_id": job_id, "status": "starting", "message": "요청 전송", "prompt": prompt, "log": [], "started_ms": Time.get_ticks_msec()}
	job_changed.emit(job)


func cancel_job_local() -> String:
	if job.is_empty() or JOB_TERMINAL.has(job.get("status", "")):
		return ""
	job["status"] = "cancelling"
	job["message"] = "취소 요청"
	job_changed.emit(job)
	return str(job["job_id"])


## Feed one server event. Returns true when accepted (also emitted as event_accepted).
func handle(event: Dictionary) -> bool:
	var type := str(event.get("type", ""))
	match type:
		"hello":
			hello_received = true
			protocol = int(event.get("protocol", 0))
			capabilities = event.get("capabilities", {})
			server_info = event.duplicate()
			characters = event.get("characters", [])
			characters_changed.emit(characters)
			var default_char := str(event.get("character", ""))
			if character_id.is_empty() or character_by_id(character_id).is_empty():
				if not default_char.is_empty():
					set_character(default_char)
				elif not characters.is_empty():
					set_character(str(characters[0].get("id", "")))
			return _accept(event)
		"job":
			return _handle_job(event)
		"pong", "ping", "reset", "character_selected":
			return _accept(event)
		"error":
			if str(event.get("turn_id", "")).is_empty():
				# Connection-level error (invalid JSON, unknown message type): not tied to a turn.
				return _accept(event)
	if CONVERSATION_EVENTS.has(type):
		return _handle_conversation(event)
	event_discarded.emit(event, "unknown type")
	return false


func _handle_job(event: Dictionary) -> bool:
	var id := str(event.get("job_id", ""))
	if job.is_empty() or id != str(job.get("job_id", "")):
		event_discarded.emit(event, "job not owned")
		return false
	var status := str(event.get("status", job.get("status", "")))
	job["status"] = status
	job["message"] = str(event.get("message", ""))
	if event.has("detail"):
		job["detail"] = event["detail"]
	for key in ["workspace", "sandbox"]:
		if event.has(key) and event[key] != null:
			job[key] = str(event[key])
	var line := "[%s] %s" % [status, job["message"]]
	if event.has("detail") and typeof(event["detail"]) == TYPE_STRING and not str(event["detail"]).is_empty():
		line += "\n" + str(event["detail"])
	job["log"].append(line)
	if JOB_TERMINAL.has(status):
		job["finished_ms"] = Time.get_ticks_msec()
	job_changed.emit(job)
	return _accept(event)


func _handle_conversation(event: Dictionary) -> bool:
	var type := str(event.get("type", ""))
	var ev_turn := str(event.get("turn_id", ""))
	var ev_char := str(event.get("character", ""))
	if type == "state" and ev_turn.is_empty():
		server_state = str(event.get("state", "idle"))
		return _accept(event)
	# Validation errors are tagged with the character the client asked for (possibly unknown);
	# the turn id is authoritative for them so the user sees the reason.
	if not ev_char.is_empty() and not character_id.is_empty() and ev_char != character_id and not (type == "error" and ev_turn == turn_id):
		event_discarded.emit(event, "other character")
		return false
	if ev_turn.is_empty():
		event_discarded.emit(event, "missing turn_id")
		return false
	if cancelled_turns.has(ev_turn):
		event_discarded.emit(event, "cancelled turn")
		return false
	if ev_turn != turn_id:
		if is_owned_job_turn(ev_turn) and not is_foreground_busy() and not is_foreground_playing():
			# Quick job acknowledgement / result spoken as its own short conversation.
			turn_id = ev_turn
			turn_generating = true
			text = ""
			turn_started.emit(ev_turn)
		else:
			event_discarded.emit(event, "stale turn" if not ev_turn.begins_with("job:") else "job speech not adoptable")
			return false
	match type:
		"start":
			text = ""
			_set_activity("thinking")
		"text":
			text = str(event.get("text", text))
		"tts_start":
			_set_activity("speaking")
		"action":
			last_gesture = str(event.get("gesture", last_gesture))
			last_emotion = str(event.get("emotion", last_emotion))
		"state":
			server_state = str(event.get("state", server_state))
		"done":
			text = str(event.get("text", text))
			last_gesture = str(event.get("gesture", last_gesture))
			last_emotion = str(event.get("emotion", last_emotion))
			var was_generating := turn_generating
			turn_generating = false
			if was_generating:
				turn_finished.emit(ev_turn, "done" if bool(event.get("ok", true)) else "error")
			# done = generation complete, not playback complete: stay "speaking" while PCM drains.
			_set_activity("speaking" if voice_active else "idle")
		"error":
			# The turn stays current (the server may follow with done{ok:false}); generation is over.
			var was_generating := turn_generating
			turn_generating = false
			if was_generating:
				turn_finished.emit(ev_turn, "error")
			_set_activity("idle")
		"cancelled":
			# Server-side cancellation of the live turn (superseded/client/disconnect). Our own
			# cancels are already in cancelled_turns, so this is only reached for server-initiated ones.
			cancelled_turns[ev_turn] = true
			turn_id = ""
			turn_generating = false
			turn_finished.emit(ev_turn, "cancelled")
			_set_activity("idle")
	return _accept(event)


## Called by the host when real audio playback state changes; activity reflects playback
## independently of generation completion.
func set_voice_active(active: bool) -> void:
	voice_active = active
	if active:
		_set_activity("speaking")
	elif turn_generating:
		_set_activity("thinking")
	else:
		_set_activity("idle")


func set_listening(active: bool) -> void:
	if active:
		_set_activity("listening")
	elif activity == "listening":
		_set_activity("thinking" if turn_generating else "idle")


func _set_activity(a: String) -> void:
	if a == activity:
		return
	activity = a
	activity_changed.emit(a)


func _accept(event: Dictionary) -> bool:
	event_accepted.emit(event)
	return true


## Build outbound messages (kept here so tests can check the wire shape).
func make_chat(text_value: String) -> Dictionary:
	return {"type": "chat", "text": text_value, "character": character_id, "turn_id": new_turn(), "voice": true}


func make_audio(wav_base64: String) -> Dictionary:
	return {"type": "audio", "wav": wav_base64, "character": character_id, "turn_id": new_turn(), "voice": true}


func make_cancel(id: String) -> Dictionary:
	return {"type": "cancel", "turn_id": id}


func make_job(prompt: String) -> Dictionary:
	var id := new_job_id()
	start_job(id, prompt)
	return {"type": "job", "prompt": prompt, "character": character_id, "job_id": id}


func make_cancel_job(id: String) -> Dictionary:
	return {"type": "cancel_job", "job_id": id}


## Announce the selected character (also before any chat); the server cancels generation and
## clears its playback accounting, then replies character_selected.
func make_select_character(id: String) -> Dictionary:
	return {"type": "select_character", "character": id}


## Real playback report: playing=true when PCM of [turn] actually starts, false when it drains
## or is flushed. Never derived from done (done is generation-complete, not playback-complete).
func make_playback(turn: String, playing: bool) -> Dictionary:
	return {"type": "playback", "turn_id": turn, "playing": playing}
