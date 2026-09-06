extends SceneTree
## Headless end-to-end protocol probe: drives the real BackendClient + CompanionSession
## + PcmQueue/AudioOutput against a running engine (stub provider + fake TTS + fake codex
## are enough; see tools/run_protocol_probe.sh). No display, no GPU, no microphone.
##   Godot --headless --path companion/native -s tools/probe_protocol.gd -- --backend http://127.0.0.1:8879
## Verifies: hello/catalog/motions/avatar over HTTP+WS, a full voiced chat turn (text,
## phrase, tts_start, audio sequence, tts_end, action, done.ok), explicit cancel (no events
## leak after cancel), server supersession, validation error tagging, job lifecycle with
## spoken ack/result adoption (gated by real playback reports), and job cancellation.

const STEP_TIMEOUT := 25.0

var client: BackendClient
var session: CompanionSession
var audio: AudioOutput
var _failures: Array[String] = []
var _passed := 0
var _accepted: Array = []
var _discarded: Array = []
var _finished: Array = [] # [turn_id, outcome]
var _jobs: Array = []
var _chars_ok := false
var _motions_ok := false
var _avatar := {}
var _health := ""
var _step := 0
var _step_started := 0.0
var _ran := false
var _turn := ""
var _cancel_sent_at_events := -1
var _playback_sent: Array = [] # [turn_id, playing]
var _selected := ""
var _assets := {} # {ok, entries, msg} from GET /motion-assets
var _asset_ready: Array = [] # [ok, name, path, msg] per fetch_motion_asset


func _init() -> void:
	# Autoloads are not instantiated in -s mode; BackendClient needs the Settings singleton.
	var s: Node = load("res://scripts/settings.gd").new()
	s.name = "Settings"
	root.add_child(s)


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(label)
		print("  FAIL: " + label)


func _backend_url() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i].begins_with("--backend="):
			return args[i].substr(10)
		if args[i] == "--backend" and i + 1 < args.size():
			return args[i + 1]
	return OS.get_environment("MATE_BACKEND_URL") if OS.has_environment("MATE_BACKEND_URL") else "http://127.0.0.1:8879"


func _setup() -> void:
	session = CompanionSession.new()
	client = BackendClient.new()
	root.add_child(client)
	audio = AudioOutput.new()
	root.add_child(audio)
	client.configure(_backend_url())
	print("probe backend %s (ws %s)" % [client.base_url, client.ws_url])
	client.event_received.connect(func(ev: Dictionary): session.handle(ev))
	session.event_accepted.connect(func(ev: Dictionary):
		_accepted.append(ev)
		if str(ev.get("type", "")) == "audio":
			audio.push_event(ev))
	session.event_discarded.connect(func(ev: Dictionary, reason: String): _discarded.append([ev, reason]))
	session.turn_started.connect(func(id: String): audio.begin_turn(id))
	audio.voice_active_changed.connect(func(active: bool): session.set_voice_active(active))
	audio.playback_changed.connect(func(turn: String, playing: bool):
		_playback_sent.append([turn, playing])
		client.send(session.make_playback(turn, playing)))
	session.event_accepted.connect(func(ev: Dictionary):
		if str(ev.get("type", "")) == "character_selected":
			_selected = str(ev.get("character", "")))
	session.turn_finished.connect(func(id: String, outcome: String):
		_finished.append([id, outcome])
		if outcome != "done":
			audio.cancel())
	session.job_changed.connect(func(job: Dictionary): _jobs.append(job.duplicate(true)))
	client.characters_loaded.connect(func(ok: bool, chars: Array, msg: String):
		_chars_ok = ok
		check(ok and not chars.is_empty(), "GET /characters: " + msg)
		if ok:
			session.characters = chars)
	client.motions_loaded.connect(func(ok: bool, bank: MotionBank, msg: String):
		_motions_ok = ok
		check(ok and bank != null and bank.has_motion("nod") and bank.has_motion("wave"), "GET /motions parses shared bank: " + msg))
	client.avatar_ready.connect(func(ok: bool, id: String, path: String, msg: String): _avatar = {"ok": ok, "id": id, "path": path, "msg": msg})
	client.health_checked.connect(func(ok: bool, msg: String): _health = ("ok " if ok else "fail ") + msg)
	client.motion_assets_loaded.connect(func(ok: bool, entries: Array[Dictionary], msg: String):
		_assets = {"ok": ok, "entries": entries, "msg": msg})
	client.motion_asset_ready.connect(func(ok: bool, name: String, path: String, msg: String):
		_asset_ready.append([ok, name, path, msg]))
	client.connect_ws()
	client.fetch_characters()
	client.fetch_motions()
	client.fetch_motion_assets()
	client.check_health()


func _types_for(turn: String) -> Array:
	var out: Array = []
	for ev in _accepted:
		if str(ev.get("turn_id", "")) == turn:
			out.append(str(ev.get("type", "")))
	return out


func _has_finished(turn: String) -> bool:
	for f in _finished:
		if f[0] == turn:
			return true
	return false


func _outcome(turn: String) -> String:
	for f in _finished:
		if f[0] == turn:
			return f[1]
	return ""


func _job_status() -> String:
	return str(_jobs[_jobs.size() - 1].get("status", "")) if not _jobs.is_empty() else ""


func _elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - _step_started


func _next() -> void:
	_step += 1
	_step_started = Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_setup()
		_next()
		return false
	if _elapsed() > STEP_TIMEOUT:
		check(false, "step %d timed out" % _step)
		_finish()
		return true
	match _step:
		1: # hello + catalog + motions + motion-assets + health
			if session.hello_received and _chars_ok and _motions_ok and not _health.is_empty() and not _assets.is_empty():
				_check_motion_assets()
				check(session.protocol == 1, "hello protocol 1")
				check(not session.character_id.is_empty(), "hello selects default character %s" % session.character_id)
				check(bool(session.capabilities.get("audio_input", false)), "capabilities.audio_input")
				check(session.capabilities.has("job_workspace") and session.capabilities.has("job_sandbox"), "capabilities carry job workspace/sandbox")
				check(_health.begins_with("ok"), "GET /health: " + _health)
				print("  hello: character=%s jobs=%s provider=%s" % [session.character_id, str(session.capabilities.get("jobs")), str(session.capabilities.get("provider"))])
				var info := session.character_by_id(session.character_id)
				client.fetch_avatar(session.character_id, str(info.get("avatar_url", "")), true)
				client.send(session.make_select_character(session.character_id))
				_next()
		2: # avatar download (latest-only path) + select_character echo + first VRMA clip, then a voiced chat
			if has_meta("asset_name") and _asset_ready.size() == 1 and not has_meta("cached_requested"):
				set_meta("cached_requested", true)
				client.fetch_motion_asset(get_meta("asset_entry"), false) # must be served from the verified cache
			if not _avatar.is_empty() and not _selected.is_empty() and (not has_meta("asset_name") or _asset_ready.size() >= 2):
				if has_meta("asset_name"):
					_check_motion_asset_download()
				check(_selected == session.character_id, "character_selected echoes the selection")
				check(bool(_avatar["ok"]), "avatar download: " + str(_avatar["msg"]))
				if bool(_avatar["ok"]):
					var f := FileAccess.open(str(_avatar["path"]), FileAccess.READ)
					check(f != null and f.get_length() > 100000, "avatar cached to user:// (%d bytes)" % (f.get_length() if f else 0))
				var msg := session.make_chat("こんにちは、調子はどう？")
				_turn = msg["turn_id"]
				check(client.send(msg), "chat sent")
				_next()
		3: # full turn
			if _has_finished(_turn):
				var types := _types_for(_turn)
				check(_outcome(_turn) == "done", "turn outcome done (got %s)" % _outcome(_turn))
				for t in ["start", "text", "phrase", "tts_start", "audio", "tts_end", "action", "done"]:
					check(types.has(t), "turn event %s received" % t)
				check(types.has("state"), "state events tagged with turn_id")
				var seqs: Array = []
				var rates := {}
				for ev in _accepted:
					if str(ev.get("turn_id", "")) == _turn and str(ev.get("type", "")) == "audio":
						seqs.append(int(ev.get("sequence", -1)))
						rates[int(ev.get("sample_rate", 0))] = true
				var monotonic := true
				for i in range(1, seqs.size()):
					if seqs[i] <= seqs[i - 1]:
						monotonic = false
				check(seqs.size() >= 2 and monotonic, "audio sequence monotonic (%d chunks)" % seqs.size())
				check(rates.has(32000) and rates.size() == 1, "audio sample_rate 32000")
				check(audio.queue.accepted_chunks == seqs.size() and audio.queue.stale_chunks == 0, "PcmQueue accepted every chunk (%d/%d stale %d)" % [audio.queue.accepted_chunks, seqs.size(), audio.queue.stale_chunks])
				check(audio.queue.total_pushed_frames > 32000 * 0.25, "decoded > 0.25 s of PCM (%d frames)" % audio.queue.total_pushed_frames)
				var done := {}
				for ev in _accepted:
					if str(ev.get("turn_id", "")) == _turn and str(ev.get("type", "")) == "done":
						done = ev
				check(bool(done.get("ok", false)) and not str(done.get("text", "")).is_empty(), "done.ok with text")
				check(session.text == str(done.get("text", "")), "session text equals done.text")
				check(done.get("timings") != null, "done.timings present")
				print("  turn: %d events, %d audio chunks, text='%s'" % [types.size(), seqs.size(), session.text.left(40)])
				print("  audio stats at done: %s" % str(audio.stats()))
				_next()
		4: # playback drains after done (headless audio driver permitting)
			var stats := audio.stats()
			if int(stats["capacity"]) <= 0:
				print("  no generator playback in this headless driver; skipping drain checks")
				check(_playback_sent.is_empty(), "no playback reports without real playback")
			elif audio.voice_active or _elapsed() < 0.5:
				if _elapsed() > 12.0:
					check(false, "audio did not drain within 12 s: %s" % str(stats))
				else:
					return false
			else:
				check(_playback_sent.has([_turn, true]) and _playback_sent.has([_turn, false]), "playback true/false reported for the turn (%s)" % str(_playback_sent))
				check(_playback_sent[0][1] == true and _playback_sent[_playback_sent.size() - 1][1] == false, "playback reports ordered start -> drain")
				check(session.activity == "idle", "activity idle after drain (got %s)" % session.activity)
				print("  drained in %.1f s; stats %s" % [_elapsed(), str(stats)])
			# explicit cancel: send a new turn and cancel it after the first text event
			var msg := session.make_chat("二つ目のメッセージです、長めに話してください")
			_turn = msg["turn_id"]
			client.send(msg)
			_cancel_sent_at_events = -1
			_playback_sent.clear()
			_next()
		5: # cancel mid-turn
			if _cancel_sent_at_events < 0:
				if _types_for(_turn).has("text"):
					var id := session.cancel_turn()
					check(id == _turn, "local cancel returns live turn")
					client.send(session.make_cancel(id))
					audio.cancel()
					_cancel_sent_at_events = _accepted.size()
					_step_started = Time.get_ticks_msec() / 1000.0
			elif _elapsed() > 2.5:
				var leaked := 0
				for i in range(_cancel_sent_at_events, _accepted.size()):
					if str(_accepted[i].get("turn_id", "")) == _turn:
						leaked += 1
				check(leaked == 0, "no events accepted after cancel (leaked %d)" % leaked)
				var server_cancelled := false
				for d in _discarded:
					if str(d[0].get("turn_id", "")) == _turn and str(d[0].get("type", "")) == "cancelled":
						server_cancelled = true
				check(server_cancelled, "server emitted cancelled for the cancelled turn (discarded as already cancelled)")
				check(audio.queue.pending_frames() == 0 and not audio.voice_active, "audio ring cleared by cancel")
				check(session.activity == "idle", "activity idle after cancel")
				var false_after_true := true
				for i in _playback_sent.size():
					if _playback_sent[i][1] == false and (i == 0 or _playback_sent[i - 1][1] != true):
						false_after_true = false
				check(false_after_true, "cancel playback report only follows a start (%s)" % str(_playback_sent))
				# supersession without explicit cancel
				var a := session.make_chat("A")
				client.send(a)
				var b := session.make_chat("B、こちらが有効です")
				client.send(b)
				_turn = b["turn_id"]
				set_meta("turn_a", a["turn_id"])
				_next()
		6: # supersession
			if _has_finished(_turn):
				var a: String = get_meta("turn_a")
				check(_outcome(_turn) == "done", "superseding turn B completes")
				check(_types_for(a).is_empty(), "no events accepted for superseded turn A")
				var a_cancelled := false
				for d in _discarded:
					if str(d[0].get("turn_id", "")) == a and str(d[0].get("type", "")) == "cancelled" and str(d[0].get("reason", "")) == "superseded":
						a_cancelled = true
				check(a_cancelled, "server cancelled A with reason superseded")
				# validation error: unknown character (tagged error, no done)
				var bad := session.make_chat("x")
				bad["character"] = "no-such-character"
				_turn = bad["turn_id"]
				client.send(bad)
				_next()
		7: # tagged validation error
			if _has_finished(_turn):
				check(_outcome(_turn) == "error", "validation error finishes the turn as error")
				check(session.activity == "idle", "activity idle after error")
				# server-side cancelled event handling: a turn cancelled by the server (not by us)
				# cannot be provoked here without a second connection; covered by selftest.
				var job := session.make_job("list the files in the workspace")
				set_meta("job_id", job["job_id"])
				client.send(job)
				_next()
		8: # job lifecycle with ack + result speech
			var jid: String = get_meta("job_id")
			var status := _job_status()
			if CompanionSession.JOB_TERMINAL.has(status):
				var ack := "job:%s:ack" % jid
				var res := "job:%s:result" % jid
				var ack_done := _has_finished(ack)
				var res_done := _has_finished(res)
				if status == "completed" and not res_done and _elapsed() < STEP_TIMEOUT - 1.0:
					return false # give the result line time to arrive
				check(status == "completed", "job completed (got %s: %s)" % [status, str(_jobs[_jobs.size() - 1].get("message", ""))])
				check(str(_jobs[_jobs.size() - 1].get("workspace", "")) != "", "job event carries workspace")
				check(str(_jobs[_jobs.size() - 1].get("sandbox", "")) != "", "job event carries sandbox")
				var statuses: Array = []
				for j in _jobs:
					statuses.append(str(j["status"]))
				check(statuses.has("starting") and statuses.has("running"), "job statuses %s" % str(statuses))
				check(ack_done and _outcome(ack) == "done", "job ack spoken as its own turn")
				check(res_done and _outcome(res) == "done", "job result spoken as its own turn")
				print("  job log: %s" % str(_jobs[_jobs.size() - 1].get("log", [])))
				check(_playback_sent.has([ack, true]) or int(audio.stats()["capacity"]) <= 0, "ack playback reported (%s)" % str(_playback_sent))
				if not (ack_done and res_done):
					print("  ack events: %s\n  result events: %s\n  discards: %s\n  session turn=%s generating=%s" % [str(_types_for(ack)), str(_types_for(res)), str(_discarded.map(func(d): return [d[0].get("type"), d[0].get("turn_id"), d[1]])), session.turn_id, str(session.turn_generating)])
				var slow := session.make_job("SLOW task")
				set_meta("job_id", slow["job_id"])
				client.send(slow)
				_next()
		9: # job cancel
			var status := _job_status()
			if status == "running" and not has_meta("cancel_sent"):
				set_meta("cancel_sent", true)
				var id := session.cancel_job_local()
				check(id == get_meta("job_id"), "local job cancel")
				client.send(session.make_cancel_job(id))
			elif status == "cancelled":
				check(true, "job cancelled by client")
				_finish()
				return true
			elif CompanionSession.JOB_TERMINAL.has(status):
				check(false, "slow job ended as %s instead of cancelled" % status)
				_finish()
				return true
	return false


## GET /motion-assets against the real engine. An engine without installed clips (or an older
## engine without the route) is a graceful skip, not a failure: the host keeps the built-in bank.
func _check_motion_assets() -> void:
	if not bool(_assets["ok"]):
		print("  motion-assets unavailable (%s): built-in bank only; skipping VRMA checks" % str(_assets["msg"]))
		check(true, "motion-assets unavailable is reported, not fatal")
		return
	var entries: Array = _assets["entries"]
	print("  motion-assets: %d clips (%s)" % [entries.size(), str(_assets["msg"])])
	if entries.is_empty():
		check(true, "empty motion-assets catalog tolerated")
		return
	var first: Dictionary = entries[0]
	check(first["kind"] == "vrma" and MotionBank.is_sha256_hex(first["sha256"]) and str(first["asset_url"]).begins_with("/motion-assets/"), "catalog entry shape (%s)" % str(first))
	# The advertised names must be what the server offers the LLM as gestures: bank names first.
	var bank_names := 0
	for e in entries:
		if e["name"] in ["idle", "nod", "wave"]:
			bank_names += 1
	check(bank_names == 0, "VRMA catalog does not duplicate built-in bank names")
	set_meta("asset_name", str(first["name"]))
	set_meta("asset_entry", first)
	# Fresh download, then a second request that must hit the verified cache.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BackendClient.motion_cache_path(str(first["name"]))))
	client.fetch_motion_asset(first, true)


func _check_motion_asset_download() -> void:
	var name: String = get_meta("asset_name")
	var entry: Dictionary = get_meta("asset_entry")
	var downloaded := {}
	var cached := {}
	for r in _asset_ready:
		if r[1] != name:
			continue
		if str(r[3]) == "downloaded":
			downloaded = {"ok": r[0], "path": r[2]}
		elif str(r[3]) == "cached":
			cached = {"ok": r[0], "path": r[2]}
		else:
			print("  motion asset %s: %s" % [name, str(r[3])])
	check(not downloaded.is_empty() and bool(downloaded["ok"]), "GET %s downloaded and checksum-verified" % str(entry["asset_url"]))
	check(not cached.is_empty() and bool(cached["ok"]), "second fetch served from the verified user:// cache")
	if downloaded.is_empty():
		return
	var path: String = downloaded["path"]
	check(BackendClient.verify_file_sha256(path, str(entry["sha256"])), "cached file sha256 equals catalog sha256")
	var mp := MotionPlayer.new()
	check(mp.load_vrma(name, path), "MotionPlayer.load_vrma accepts the downloaded clip")
	if mp.vrma_clips.has(name):
		var clip: VrmaClip = mp.vrma_clips[name]
		check(absf(clip.duration - float(entry["duration"])) < 0.05, "clip duration %.3f ~ catalog %.3f" % [clip.duration, float(entry["duration"])])
		check(mp.play_gesture(name), "play_gesture dispatches the VRMA name (LLM gesture path)")
	mp.free()


func _finish() -> void:
	print("\nprotocol probe: %d passed, %d failed (sent %d, received %d, discarded %d)" % [_passed, _failures.size(), client.sent_count, client.received_count, _discarded.size()])
	for f in _failures:
		print("  FAIL: " + f)
	client.disconnect_ws()
	quit(0 if _failures.is_empty() else 1)
