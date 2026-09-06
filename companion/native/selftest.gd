extends SceneTree
## Headless self-test for the native host logic (Linux/Windows, no display needed):
##   Godot --headless --path companion/native -s selftest.gd
## Covers motion bank parse/sample/compose/validation, coordinate conversion,
## bounded PCM ring + sequence guard + cancel, WAV encoding, session/protocol
## state machine, and (when companion/assets/cheval-grand.vrm exists) runtime
## VRM import + bone/expression resolution through the installed addon.
## It does NOT prove Windows transparency, passthrough, or real audio devices.

var _failures: Array[String] = []
var _passed := 0


var _ran := false


func _process(_delta: float) -> bool:
	# Run once the root is inside the tree (needed for global transforms in the VRM test).
	if _ran:
		return false
	_ran = true
	var t0 := Time.get_ticks_msec()
	_test_scripts_compile()
	_test_control_panel_fit()
	_test_motion_bank()
	_test_coordinates()
	_test_pcm_queue()
	_test_wav()
	_test_session()
	_test_settings_urls()
	_test_audio_output()
	_test_microphone()
	_test_asset_catalog()
	_test_motion_asset_cache()
	_test_vrma_local_clip()
	_test_autonomy_bridge()
	_test_autonomy_wiring()
	_test_pet_scale()
	_test_surface_wiring()
	_test_panel_vrma_and_autonomy()
	_test_vrm_runtime()
	print("\nselftest: %d passed, %d failed (%d ms)" % [_passed, _failures.size(), Time.get_ticks_msec() - t0])
	for f in _failures:
		print("  FAIL: " + f)
	quit(0 if _failures.is_empty() else 1)
	return true


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(label)
		print("  FAIL: " + label)


## Every host script (including main.gd / control_panel.gd, which no other test instantiates)
## must load and compile; a parse error in any of them is a hard failure, not a log line.
func _test_scripts_compile() -> void:
	print("[scripts compile]")
	var dir := DirAccess.open("res://scripts")
	check(dir != null, "res://scripts is readable")
	if dir == null:
		return
	var names: Array = []
	for f in dir.get_files():
		if f.ends_with(".gd"):
			names.append("res://scripts/" + f)
	names.append("res://selftest.gd")
	names.sort()
	for path in names:
		var script: GDScript = load(path)
		var ok := script != null and script.can_instantiate()
		check(ok, "script compiles: " + path)
	var scene: PackedScene = load("res://main.tscn")
	check(scene != null and scene.can_instantiate(), "main.tscn loads with its script")
	var autoload := str(ProjectSettings.get_setting("autoload/Settings", ""))
	check(autoload.ends_with("res://scripts/settings.gd"), "Settings autoload points at scripts/settings.gd (got %s)" % autoload)


func _ensure_settings_singleton() -> void:
	if root.has_node("Settings"):
		return
	var s: Node = load("res://scripts/settings.gd").new()
	s.name = "Settings"
	root.add_child(s)


## The panel was rendering ~400 px wide on Windows because a status label demanded more than
## PANEL_WIDTH; the pet zone starts right after the panel, so any wider child covers the pet.
func _test_control_panel_fit() -> void:
	print("[control panel fit]")
	_ensure_settings_singleton()
	var panel := ControlPanel.new()
	root.add_child(panel)
	panel.set_connection("closed", "1013 server closed: client too slow, queue overflowed after 256 events")
	panel.set_input_mode("VAD 일시정지(자기 음성) · 마이크 켜짐 · noAEC")
	panel.set_activity("speaking")
	panel.set_status_message("hello · protocol 1 · 캐릭터 3 · " + "x".repeat(120))
	# Headless Linux measures Korean text with a narrow fallback font; Windows renders real CJK
	# glyphs noticeably wider (that is how the 340 px panel came out ~400 px in the captures),
	# so every child, including hidden tabs, must leave headroom below PANEL_WIDTH.
	var budget := ControlPanel.PANEL_WIDTH - 30.0
	var widest := panel.widest_child()
	var w := float(widest["width"])
	check(w <= budget, "widest child min width %.0f within %.0f (PANEL_WIDTH %.0f minus CJK headroom) (%s)" % [w, budget, ControlPanel.PANEL_WIDTH, str(widest["path"])])
	check(panel.get_combined_minimum_size().x <= ControlPanel.PANEL_WIDTH, "panel min width %.0f <= PANEL_WIDTH" % panel.get_combined_minimum_size().x)
	var main_script: GDScript = load("res://scripts/main.gd")
	var zone: float = main_script.PET_ZONE_WIDTH
	var win: Vector2i = main_script.WINDOW_SIZE
	check(is_equal_approx(zone + ControlPanel.PANEL_WIDTH + 2.0 * main_script.PANEL_MARGIN, float(win.x)), "pet zone (%.0f) + panel + margins == window width %d" % [zone, win.x])
	check(zone >= 300.0, "pet zone at least 300 px wide (%.0f)" % zone)
	check(main_script.SUN_ENERGY + main_script.FILL_ENERGY <= 1.2 and main_script.AMBIENT_ENERGY <= 0.6 and main_script.TONEMAP_EXPOSURE < 1.0, "lighting budget lowered vs the blown-out Windows capture (sun %.2f fill %.2f ambient %.2f exposure %.2f)" % [main_script.SUN_ENERGY, main_script.FILL_ENERGY, main_script.AMBIENT_ENERGY, main_script.TONEMAP_EXPOSURE])
	panel.queue_free()


func _bank_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../Assets/StreamingAssets/cheval-motions.json").simplify_path()


func _test_motion_bank() -> void:
	print("[motion bank]")
	var path := _bank_path()
	check(FileAccess.file_exists(path), "shared bank exists at " + path)
	if not FileAccess.file_exists(path):
		return
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(path))
	check(bank.errors.is_empty(), "bank parses without errors: " + ", ".join(bank.errors))
	check(bank.has_motion("nod") and bank.has_motion("wave") and bank.has_motion("idle"), "bank has idle/nod/wave")
	var nod := bank.get_motion("nod")
	var s0 := MotionBank.sample_motion(nod, 0.0)
	check(s0.has("head") and s0["head"].is_zero_approx(), "nod starts at zero")
	var s08 := MotionBank.sample_motion(nod, 0.8)
	check(s08.has("head") and is_equal_approx(s08["head"].x, 10.0), "nod head.x==10 at t=0.8 (got %s)" % str(s08.get("head")))
	var mid := MotionBank.sample_motion(nod, 0.6)
	check(mid["head"].x > 0.0 and mid["head"].x < 10.0, "smoothstep interpolation between keys")
	check(MotionBank.sample_motion(nod, 3.0).is_empty(), "sampling at duration returns empty (finished)")
	check(MotionBank.sample_motion(nod, -0.1).is_empty(), "negative time returns empty")
	# performance parameters
	var perf := MotionBank.sample_performed(nod, 0.4, 0.5, 2.0, 1) # t*speed = 0.8
	check(is_equal_approx(perf["head"].x, 5.0), "intensity 0.5 / speed 2 sample (got %s)" % str(perf.get("head")))
	check(is_equal_approx(MotionBank.performed_duration(nod, 2.0, 3), 4.5), "performed duration = 3.0/2*3")
	check(MotionBank.sample_performed(nod, 4.6, 1.0, 2.0, 3).is_empty(), "performance ends after repeats")
	check(not MotionBank.sample_performed(nod, 3.1, 1.0, 2.0, 3).is_empty(), "second repeat still active")
	check(is_equal_approx(MotionBank.sample_performed(nod, 0.8, 5.0, 1.0, 1)["head"].x, 15.0), "intensity clamped to 1.5")
	# validation
	var bad := {"name": "bad", "duration": 2.0, "tracks": [{"bone": "tail", "keys": [{"time": 0}]}]}
	check(not MotionBank.validate_motion(bad).is_empty(), "unknown bone rejected")
	var bad2 := {"name": "bad2", "duration": 2.0, "tracks": [{"bone": "head", "keys": [{"time": 0, "x": 0}, {"time": 1, "x": 5}, {"time": 2, "x": 3}]}]}
	check(not MotionBank.validate_motion(bad2).is_empty(), "non-zero end rejected")
	var bad3 := {"name": "bad3", "duration": 2.0, "tracks": [{"bone": "head", "keys": [{"time": 0}, {"time": 1.5, "x": 5}, {"time": 1.0}, {"time": 2}]}]}
	check(not MotionBank.validate_motion(bad3).is_empty(), "non-monotonic keys rejected")
	var bad4 := {"name": "bad4", "duration": 2.0, "tracks": [{"bone": "head", "keys": [{"time": 0}, {"time": 1, "x": 400}, {"time": 2}]}]}
	check(not MotionBank.validate_motion(bad4).is_empty(), "angle > 180 rejected")
	var bad5 := {"name": "spaces in name", "duration": 2.0, "tracks": []}
	check(not MotionBank.validate_motion(bad5).is_empty(), "invalid name rejected")
	var mixed := MotionBank.parse({"version": 1, "motions": [bank.get_motion("nod"), bad]})
	check(mixed.has_motion("nod") and not mixed.has_motion("bad") and mixed.errors.size() == 1, "bad entries skipped, good kept")
	# sequence composition
	var errs: Array[String] = []
	var seq := bank.compose_sequence("greet_combo", [
		{"name": "wave", "intensity": 0.8, "speed": 1.0, "repeat": 1},
		{"name": "nod", "intensity": 1.0, "speed": 2.0, "repeat": 2},
	], errs)
	check(not seq.is_empty(), "sequence composes: " + ", ".join(errs))
	if not seq.is_empty():
		check(is_equal_approx(seq["duration"], 4.0 + 3.0), "sequence duration 4 + 1.5*2 (got %s)" % str(seq["duration"]))
		check(MotionBank.validate_motion(seq).is_empty(), "composed sequence valid in bank format")
		var head_at_wave: float = MotionBank.sample_motion(seq, 4.0 + 0.4)["head"].x # nod at local 0.8
		check(is_equal_approx(head_at_wave, 10.0), "second step samples nod peak (got %f)" % head_at_wave)
		var arm_at_nod: Vector3 = MotionBank.sample_motion(seq, 5.0)["rightUpperArm"]
		check(arm_at_nod.is_zero_approx(), "wave arm at rest during nod step")
		check(bool(seq.get("custom", false)), "custom flag set")
		var reparsed := MotionBank.parse({"version": 1, "motions": [seq]})
		check(reparsed.has_motion("greet_combo"), "sequence round-trips through parser")
	var errs2: Array[String] = []
	check(bank.compose_sequence("x", [{"name": "nope"}], errs2).is_empty() and not errs2.is_empty(), "unknown preset in sequence rejected")
	# keyframes
	var errs3: Array[String] = []
	var kf := MotionBank.from_keyframes("tilt_test", 2.0, [
		{"bone": "head", "time": 1.0, "x": 0, "y": 0, "z": 12},
		{"bone": "head", "time": 0.5, "x": 4, "y": 0, "z": 0},
		{"bone": "chest", "time": 1.2, "x": 3},
	], errs3)
	check(not kf.is_empty(), "keyframes compile: " + ", ".join(errs3))
	if not kf.is_empty():
		check(MotionBank.validate_motion(kf).is_empty(), "keyframe motion valid (zero ends inserted)")
		check(is_equal_approx(MotionBank.sample_motion(kf, 1.0)["head"].z, 12.0), "keyframe sorted + sampled")
		check(MotionBank.sample_motion(kf, 0.0)["chest"].is_zero_approx(), "keyframe chest starts at zero")


func _test_coordinates() -> void:
	print("[coordinates]")
	# +x (nod down) must move the top of the head toward +Z (the model faces +Z in Godot).
	var b := VrmAvatar.canonical_to_basis(Vector3(10, 0, 0))
	var up := b * Vector3.UP
	check(up.z > 0.05, "canonical +x tilts head forward (+Z), up->%s" % str(up))
	# +y (turn right): forward (+Z) should move toward -X (character's right is -X when facing +Z).
	var fwd := VrmAvatar.canonical_to_basis(Vector3(0, 20, 0)) * Vector3.FORWARD * -1.0
	check(fwd.x < -0.1, "canonical +y turns toward character's right (-X), fwd->%s" % str(fwd))
	# +z (tilt toward character's left = +X): the up vector leans toward +X.
	var tilt := VrmAvatar.canonical_to_basis(Vector3(0, 0, 15)) * Vector3.UP
	check(tilt.x > 0.1, "canonical +z tilts toward character's left (+X), up->%s" % str(tilt))
	check(VrmAvatar.canonical_to_basis(Vector3.ZERO).is_equal_approx(Basis.IDENTITY), "zero offset is identity")


func _test_pcm_queue() -> void:
	print("[pcm queue]")
	var q := PcmQueue.new()
	q.rate = 32000
	q.max_pending_frames = 1000
	var chunk := PackedByteArray()
	chunk.resize(400) # 200 frames
	for i in 200:
		chunk.encode_s16(i * 2, 16384 if i % 2 == 0 else -16384)
	check(not q.push("t1", 0, chunk), "chunk rejected before begin_turn")
	q.begin_turn("t1")
	check(q.push("t1", 0, chunk), "seq 0 accepted")
	check(q.push("t1", 1, chunk), "seq 1 accepted")
	check(not q.push("t1", 1, chunk), "duplicate seq rejected")
	check(not q.push("t1", 0, chunk), "older seq rejected")
	check(not q.push("t0", 5, chunk), "stale turn rejected")
	check(q.push("t1", 7, chunk), "gap in seq still accepted (monotonic)")
	check(q.pending_frames() == 600, "600 frames pending (got %d)" % q.pending_frames())
	var taken := q.take(250)
	check(taken.size() == 250 and q.pending_frames() == 350, "take drains from the front")
	check(is_equal_approx(taken[0], 0.5) and is_equal_approx(taken[1], -0.5), "int16 decoded to floats")
	check(is_equal_approx(PcmQueue.rms(taken), 0.5), "rms of +-0.5 square = 0.5")
	# bound: 350 pending, room 650; push 4 chunks (200 frames each) => 3 accepted, 4th rejected whole
	var results: Array = []
	for i in 4:
		results.append(q.push("t1", 10 + i, chunk))
	check(results == [true, true, true, false], "overflowing chunk rejected whole, never clipped (%s)" % str(results))
	check(q.pending_frames() == 950, "pending stays within bound without partial chunks (got %d)" % q.pending_frames())
	check(q.dropped_frames == 200 and q.overflowed, "overflow flagged with dropped frames counted (got %d)" % q.dropped_frames)
	check(q.stale_chunks == 3, "stale chunks counted (got %d)" % q.stale_chunks)
	q.clear()
	check(q.pending_frames() == 0 and q.take(10).is_empty() and not q.overflowed, "cancel clears ring and overflow flag")
	check(q.push("t1", 20, chunk), "accepts after clear within same turn")
	q.begin_turn("t2")
	check(q.pending_frames() == 0 and q.last_sequence == -1, "new turn resets ring and sequence")
	check(q.push("t2", 0, chunk) and not q.push("t1", 21, chunk), "guard follows the new turn")
	var odd := PackedByteArray([1, 2, 3])
	check(PcmQueue.decode_int16(odd).size() == 1, "odd byte length decodes floor(n/2) frames")
	# base64 round trip like the wire format
	var b64 := Marshalls.raw_to_base64(chunk)
	check(Marshalls.base64_to_raw(b64) == chunk, "base64 round trip")


func _test_wav() -> void:
	print("[wav]")
	var samples := PackedFloat32Array()
	samples.resize(4800)
	for i in samples.size():
		samples[i] = sin(float(i) * TAU * 440.0 / 48000.0) * 0.5
	var wav := WavEncoder.encode(samples, 48000)
	var head := WavEncoder.parse_header(wav)
	check(wav.size() == 44 + 4800 * 2, "wav size = header + pcm")
	check(head.get("rate") == 48000 and head.get("channels") == 1 and head.get("bits") == 16 and head.get("frames") == 4800, "wav header fields (got %s)" % str(head))
	var down := WavEncoder.encode(samples, 48000, 16000)
	var dh := WavEncoder.parse_header(down)
	check(dh.get("rate") == 16000 and dh.get("frames") == 1600, "downsample 48k->16k frames (got %s)" % str(dh))
	var clip := PackedFloat32Array([2.0, -2.0])
	var cw := WavEncoder.encode(clip, 8000)
	check(cw.decode_s16(44) == 32767 and cw.decode_s16(46) == -32767, "clipping to int16 range")
	check(WavEncoder.parse_header(PackedByteArray([1, 2, 3])).is_empty(), "garbage header rejected")
	var thirty := PackedFloat32Array()
	thirty.resize(48000 * 30)
	var big := WavEncoder.encode(thirty, 48000, 16000)
	check(WavEncoder.parse_header(big).get("frames") == 16000 * 30, "30 s bound encodes at target rate")


func _test_session() -> void:
	print("[session]")
	var s := CompanionSession.new()
	var accepted: Array = []
	var discarded: Array = []
	s.event_accepted.connect(func(e): accepted.append(e))
	s.event_discarded.connect(func(e, r): discarded.append([e, r]))
	var activities: Array = []
	s.activity_changed.connect(func(a): activities.append(a))
	check(s.handle({"type": "hello", "protocol": 1, "characters": [{"id": "cheval-grand", "name": "シュヴァルグラン"}, {"id": "other", "name": "O"}], "character": "cheval-grand", "capabilities": {"audio_input": true, "jobs": true}}), "hello accepted")
	check(s.character_id == "cheval-grand" and s.hello_received and s.protocol == 1, "hello sets default character")
	var chat := s.make_chat("안녕")
	var t1: String = chat["turn_id"]
	check(chat["type"] == "chat" and chat["voice"] == true and chat["character"] == "cheval-grand" and not t1.is_empty(), "chat wire shape")
	check(s.activity == "thinking", "new turn -> thinking")
	check(s.handle({"type": "start", "turn_id": t1, "character": "cheval-grand"}), "start accepted")
	check(s.handle({"type": "text", "turn_id": t1, "character": "cheval-grand", "text": "こんにちは", "delta": "こんにちは"}), "text accepted")
	check(s.text == "こんにちは", "text accumulates full text")
	check(not s.handle({"type": "text", "turn_id": "t-old", "character": "cheval-grand", "text": "stale"}), "stale turn discarded")
	check(s.text == "こんにちは", "stale text did not overwrite")
	check(not s.handle({"type": "audio", "turn_id": t1, "character": "other", "pcm": "AAA=", "sequence": 0}), "other character discarded")
	check(s.handle({"type": "audio", "turn_id": t1, "character": "cheval-grand", "pcm": "AAA=", "sequence": 0}), "audio for live turn accepted")
	check(s.handle({"type": "tts_start", "turn_id": t1, "character": "cheval-grand"}), "tts_start accepted")
	check(s.activity == "speaking", "tts_start -> speaking")
	check(s.handle({"type": "action", "turn_id": t1, "character": "cheval-grand", "gesture": "nod", "emotion": "happy", "intensity": 0.8}), "action accepted")
	check(s.last_gesture == "nod" and s.last_emotion == "happy", "action recorded")
	s.set_voice_active(true) # PCM started playing locally before generation finished
	check(s.handle({"type": "done", "turn_id": t1, "character": "cheval-grand", "text": "こんにちは。", "gesture": "nod", "emotion": "happy", "timings": {}}), "done accepted")
	check(not s.turn_generating and s.activity == "speaking", "done ends generation but stays speaking while PCM drains")
	s.set_voice_active(false)
	check(s.activity == "idle", "drain -> idle")
	# playback continues after done and still owns the activity
	s.set_voice_active(true)
	check(s.activity == "speaking", "voice active after done -> speaking")
	s.set_voice_active(false)
	check(s.activity == "idle", "voice ends -> idle")
	check(s.make_playback(t1, true) == {"type": "playback", "turn_id": t1, "playing": true}, "playback wire shape")
	check(s.make_select_character("other") == {"type": "select_character", "character": "other"}, "select_character wire shape")
	check(s.handle({"type": "character_selected", "character": "cheval-grand"}), "character_selected accepted")
	check(s.handle({"type": "audio", "turn_id": t1, "character": "cheval-grand", "pcm": "AAA=", "sequence": 1}), "late audio for finished-but-current turn still accepted")
	# cancel: superseding chat
	var chat2 := s.make_chat("두 번째")
	var t2: String = chat2["turn_id"]
	var cancelled := s.cancel_turn()
	check(cancelled == t2 and s.make_cancel(cancelled) == {"type": "cancel", "turn_id": t2}, "cancel wire shape")
	check(not s.handle({"type": "text", "turn_id": t2, "character": "cheval-grand", "text": "late"}), "events for cancelled turn discarded")
	check(s.activity == "idle", "cancel -> idle")
	# job ack conversation adopted only when foreground idle
	var job := s.make_job("정리해줘")
	var jid: String = job["job_id"]
	check(job["type"] == "job" and job["character"] == "cheval-grand" and not jid.is_empty(), "job wire shape")
	check(s.handle({"type": "job", "job_id": jid, "status": "running", "message": "codex exec"}), "owned job event accepted")
	check(not s.handle({"type": "job", "job_id": "someone-else", "status": "running"}), "foreign job event discarded")
	check(s.handle({"type": "start", "turn_id": "job:%s:ack" % jid, "character": "cheval-grand"}), "job ack conversation adopted while idle")
	check(s.turn_id == "job:%s:ack" % jid, "ack turn becomes current")
	check(s.handle({"type": "done", "turn_id": "job:%s:ack" % jid, "character": "cheval-grand", "text": "ok"}), "ack done accepted")
	var chat3 := s.make_chat("세 번째")
	check(not s.handle({"type": "start", "turn_id": "job:%s:result" % jid, "character": "cheval-grand"}), "job result not adopted while foreground busy")
	check(s.turn_id == chat3["turn_id"], "foreground turn kept")
	check(s.handle({"type": "job", "job_id": jid, "status": "completed", "message": "exit 0"}), "job completion accepted")
	check(s.job["status"] == "completed" and s.job["log"].size() == 2, "job log accumulates")
	check(s.cancel_job_local().is_empty(), "cannot cancel finished job")
	check(s.handle({"type": "job", "job_id": jid, "status": "completed", "message": "x", "workspace": "/w", "sandbox": "read-only"}) and s.job.get("workspace") == "/w" and s.job.get("sandbox") == "read-only", "job workspace/sandbox recorded")
	# job result: not adopted while foreground PCM still plays; only owned job ids; adopted after drain
	s.set_voice_active(true)
	check(s.handle({"type": "done", "turn_id": chat3["turn_id"], "character": "cheval-grand", "text": "ok", "timings": {}}), "foreground done while playing")
	check(not s.handle({"type": "start", "turn_id": "job:%s:result" % jid, "character": "cheval-grand"}), "job result not adopted while foreground PCM plays")
	s.set_voice_active(false)
	check(not s.handle({"type": "start", "turn_id": "job:someone-else:result", "character": "cheval-grand"}), "unowned job speech never adopted")
	check(s.handle({"type": "start", "turn_id": "job:%s:result" % jid, "character": "cheval-grand"}), "job result adopted after drain")
	check(s.handle({"type": "done", "turn_id": "job:%s:result" % jid, "character": "cheval-grand", "text": "ok", "timings": {}}), "job result done")
	# server-initiated cancelled (not by us): ends the live turn, later events discarded
	var finished: Array = []
	s.turn_finished.connect(func(id, outcome): finished.append([id, outcome]))
	var chat3b := s.make_chat("세 번째-b")
	var t3: String = chat3b["turn_id"]
	check(s.handle({"type": "cancelled", "turn_id": t3, "character": "cheval-grand", "reason": "disconnect"}), "server cancelled accepted for live turn")
	check(s.turn_id.is_empty() and s.activity == "idle" and finished == [[t3, "cancelled"]], "server cancelled finishes the turn")
	check(not s.handle({"type": "text", "turn_id": t3, "character": "cheval-grand", "text": "late"}), "events after server cancel discarded")
	# error followed by done{ok:false}: one finish as error, done not stale
	var chat4 := s.make_chat("네 번째")
	var t4: String = chat4["turn_id"]
	finished.clear()
	check(s.handle({"type": "error", "turn_id": t4, "character": "cheval-grand", "message": "boom"}), "tagged error accepted")
	check(s.handle({"type": "done", "turn_id": t4, "character": "cheval-grand", "ok": false, "timings": {}}), "done{ok:false} after error still accepted")
	check(finished == [[t4, "error"]], "error + done{ok:false} finishes once as error (got %s)" % str(finished))
	check(s.handle({"type": "error", "message": "invalid JSON"}), "connection-level error without turn_id accepted")
	var chat5 := s.make_chat("bad")
	check(s.handle({"type": "error", "turn_id": chat5["turn_id"], "character": "no-such-character", "message": "unknown character"}), "validation error tagged with the requested (unknown) character accepted")
	check(not s.turn_generating and s.activity == "idle", "validation error ends generation")
	check(not s.handle({"type": "text", "text": "x"}), "conversation event without turn_id discarded")
	# character switch + disconnect
	check(s.set_character("other"), "character switch")
	check(not s.handle({"type": "text", "turn_id": chat3["turn_id"], "character": "cheval-grand", "text": "x"}), "old character events discarded after switch")
	s.reset_connection()
	check(s.turn_id.is_empty() and not s.hello_received and s.activity == "idle", "disconnect resets turn/hello")
	check(not s.handle({"type": "weird"}), "unknown type discarded")
	check(activities.has("thinking") and activities.has("speaking") and activities.has("idle"), "activity transitions emitted")
	check(discarded.size() >= 7, "discards were reported (%d)" % discarded.size())


func _test_settings_urls() -> void:
	print("[settings]")
	var settings_script: GDScript = load("res://scripts/settings.gd")
	check(settings_script.ws_url_for("http://127.0.0.1:8876") == "ws://127.0.0.1:8876/ws", "ws url derivation")
	check(settings_script.ws_url_for("https://host/") == "wss://host/ws", "wss url derivation")
	check(settings_script._clean_url("localhost:8876/") == "http://localhost:8876", "url cleaning adds scheme")


func _test_audio_output() -> void:
	print("[audio output]")
	var ao := AudioOutput.new()
	root.add_child(ao)
	var reports: Array = []
	ao.playback_changed.connect(func(id: String, playing: bool): reports.append([id, playing]))
	var overflows: Array = []
	ao.overflow.connect(func(id: String, _sec: float): overflows.append(id))
	var chunk := PackedByteArray()
	chunk.resize(3200 * 2) # 0.1 s at 32 kHz
	for i in 3200:
		chunk.encode_s16(i * 2, int(12000.0 * sin(float(i) * 0.05)))
	check(not ao.push_raw("a1", 0, chunk), "chunk before begin_turn rejected")
	ao.begin_turn("a1")
	check(ao.push_raw("a1", 0, chunk), "chunk accepted for live turn")
	ao._process(0.016)
	var cap: int = ao.stats()["capacity"]
	print("  generator capacity=%d frames, buffered=%d, pending=%d (headless audio driver: %s)" % [cap, ao.buffered_frames(), ao.queue.pending_frames(), AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?"])
	if cap > 0:
		check(ao.buffered_frames() > 0 or ao.queue.pending_frames() > 0, "audio queued into generator/ring")
		ao.push_raw("a1", 1, chunk)
		ao._process(0.016)
		ao.push_raw("a1", 2, chunk)
		ao._process(0.016)
		check(ao.stats()["capacity"] == cap, "capacity not re-measured per chunk (regression: got %d vs %d)" % [ao.stats()["capacity"], cap])
		check(ao.buffered_frames() + ao.queue.pending_frames() >= 3200, "buffered frames counted against the fixed capacity (%d + %d)" % [ao.buffered_frames(), ao.queue.pending_frames()])
		check(ao.voice_active and reports == [["a1", true]], "playback:true reported once with the turn id (%s)" % str(reports))
	else:
		print("  skipped generator checks: no audio playback in this headless driver")
		ao.voice_active = true
		ao.playing_turn = "a1"
	ao.cancel()
	check(not ao.voice_active and reports.size() > 0 and reports[reports.size() - 1] == ["a1", false], "cancel reports playback:false with the id captured before clearing (%s)" % str(reports))
	check(ao.turn_id.is_empty() and ao.queue.pending_frames() == 0 and ao.buffered_frames() == 0, "cancel clears ring and generator")
	# overflow: bound reached -> whole flush + visible signal, never clipped playback
	ao.queue.max_pending_frames = 3200 * 3
	ao.begin_turn("a2")
	var accepted := 0
	for i in 5:
		if ao.push_raw("a2", i, chunk):
			accepted += 1
	check(accepted <= 4 and overflows == ["a2"], "overflow flushes and reports the turn (accepted %d, overflows %s)" % [accepted, str(overflows)])
	check(ao.queue.pending_frames() == 0 and ao.turn_id.is_empty(), "overflow left nothing queued")
	# begin_turn while previous audio still audible ends the old report
	ao.queue.max_pending_frames = 32000 * 120
	if cap > 0:
		reports.clear()
		ao.begin_turn("a3")
		ao.push_raw("a3", 0, chunk)
		ao._process(0.016)
		ao.begin_turn("a4")
		check(reports.has(["a3", true]) and reports.has(["a3", false]), "new turn ends the previous playback report (%s)" % str(reports))
	ao.queue_free()


func _test_microphone() -> void:
	print("[microphone]")
	var m := Microphone.new()
	root.add_child(m)
	var captures: Array = []
	m.capture_changed.connect(func(on: bool): captures.append(on))
	check(not m.is_capturing(), "microphone hardware closed by default (nothing records)")
	if not m.available:
		print("  skipped: audio input disabled in this build")
		m.queue_free()
		return
	m.set_vad_enabled(true)
	check(m.is_capturing() and m.vad_enabled, "VAD on opens capture")
	m.set_vad_enabled(false)
	check(not m.is_capturing() and captures == [true, false], "VAD off closes capture (%s)" % str(captures))
	m.start_push_to_talk()
	check(m.is_capturing() and m.is_recording(), "PTT opens capture")
	m.stop_push_to_talk()
	check(not m.is_capturing() and not m.is_recording(), "PTT release closes capture")
	m.queue_free()


func _manifest_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../motion-assets.json").simplify_path()


## GET /motion-assets shape as the backend publishes it (engine/motion_assets.py), built from the
## root manifest so the test follows the real clip list. Pure parsing; no network.
func _test_asset_catalog() -> void:
	print("[motion asset catalog] (headless, parser only)")
	var path := _manifest_path()
	check(FileAccess.file_exists(path), "root manifest exists at " + path)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var published: Array = []
	if typeof(manifest) == TYPE_DICTIONARY:
		for m in manifest.get("motions", []):
			published.append({"name": m["name"], "kind": "vrma", "duration": m["duration"], "asset_url": "/motion-assets/" + str(m["name"]), "sha256": m["sha256"], "loop": m.get("loop", false), "description": m.get("description", "")})
	var errs: Array[String] = []
	var entries := MotionBank.parse_asset_catalog({"motions": published}, errs)
	check(errs.is_empty() and entries.size() == published.size(), "every manifest clip parses (%d, errors: %s)" % [entries.size(), ", ".join(errs)])
	var names: Array = []
	for e in entries:
		names.append(e["name"])
	for expected in ["idle_natural", "idle_talking", "walk", "walk_formal", "dance", "interact", "pick_up", "sit_idle"]:
		check(names.has(expected), "catalog lists %s" % expected)
	var by_name := {}
	for e in entries:
		by_name[e["name"]] = e
	if by_name.has("walk") and by_name.has("dance"):
		check(bool(by_name["walk"]["loop"]) and not bool(by_name["dance"]["loop"]), "loop flags carried (walk loop, dance one-shot)")
		check(str(by_name["dance"]["description"]).to_lower().contains("dance") and not str(by_name["dance"]["description"]).to_lower().contains("greet"), "dance keeps its manifest wording (never relabelled a greeting)")
		check(by_name["walk"]["asset_url"] == "/motion-assets/walk", "asset_url kept")
		check(is_equal_approx(float(by_name["walk"]["duration"]), 1.33333), "duration parsed")
	# invalid / hostile entries are skipped, valid ones kept
	var errs2: Array[String] = []
	var good := {"name": "ok_clip", "kind": "vrma", "duration": 2.0, "asset_url": "/motion-assets/ok_clip", "sha256": "a".repeat(64)}
	var mixed := MotionBank.parse_asset_catalog({"motions": [
		good,
		{"name": "bad sha", "kind": "vrma", "duration": 1.0, "sha256": "zz"},
		{"name": "neg", "kind": "vrma", "duration": -1.0, "sha256": "b".repeat(64)},
		{"name": "fbx_clip", "kind": "fbx", "duration": 1.0, "sha256": "c".repeat(64)},
		{"name": "ok_clip", "kind": "vrma", "duration": 2.0, "sha256": "d".repeat(64)},
		{"name": "loopy", "kind": "vrma", "duration": 1.0, "sha256": "e".repeat(64), "loop": "yes"},
		"not an object",
	]}, errs2)
	check(mixed.size() == 1 and mixed[0]["name"] == "ok_clip" and mixed[0]["loop"] == false, "invalid entries skipped, first valid kept, loop defaults false (%d kept)" % mixed.size())
	check(errs2.size() == 6, "six problems reported (%s)" % ", ".join(errs2))
	check(mixed[0]["sha256"] == "a".repeat(64) and mixed[0]["description"] == "", "sha lower-cased, description defaults empty")
	var errs3: Array[String] = []
	check(MotionBank.parse_asset_catalog([], errs3).is_empty() and not errs3.is_empty(), "non-object catalog rejected")
	check(MotionBank.is_sha256_hex("AbCdEf".repeat(10) + "1234") and not MotionBank.is_sha256_hex("g".repeat(64)) and not MotionBank.is_sha256_hex("a".repeat(63)), "sha256 hex validation")


## Cache path + checksum verification as used by BackendClient.fetch_motion_asset (files only).
func _test_motion_asset_cache() -> void:
	print("[motion asset cache] (headless, user:// files only)")
	check(BackendClient.motion_cache_path("walk") == "user://motions/walk.vrma", "cache path under user://motions")
	var hostile := BackendClient.motion_cache_path("../evil")
	check(hostile.get_base_dir() == "user://motions" and not hostile.get_file().contains("/"), "cache filename stays a flat file under user://motions (%s)" % hostile)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://selftest"))
	var path := "user://selftest/sha.bin"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("mate companion vrma cache test")
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("mate companion vrma cache test".to_utf8_buffer())
	var expected := ctx.finish().hex_encode()
	check(BackendClient.verify_file_sha256(path, expected), "matching sha verifies")
	check(BackendClient.verify_file_sha256(path, expected.to_upper()), "sha comparison is case-insensitive")
	check(not BackendClient.verify_file_sha256(path, "0".repeat(64)), "mismatching sha rejected")
	check(not BackendClient.verify_file_sha256(path, "nothex"), "malformed sha rejected")
	check(not BackendClient.verify_file_sha256("user://selftest/missing.bin", expected), "missing file rejected")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Real installed clip (companion/assets/motions/walk.vrma, CC0) parsed through the Astra-owned
## VrmaClip via MotionPlayer.load_vrma, and its checksum against the root manifest. No avatar,
## no rendering: proves the file/manifest pair and the load path, not the on-screen walk.
func _test_vrma_local_clip() -> void:
	print("[vrma local clip] (headless, file parse only)")
	var dir := ProjectSettings.globalize_path("res://").path_join("../assets/motions").simplify_path()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(_manifest_path())) if FileAccess.file_exists(_manifest_path()) else null
	if typeof(manifest) != TYPE_DICTIONARY or not FileAccess.file_exists(dir.path_join("walk.vrma")):
		print("  skipped: no installed clips at " + dir)
		return
	var mp := MotionPlayer.new()
	var loaded := 0
	var checked := 0
	for m in manifest.get("motions", []):
		var clip_path := dir.path_join(str(m["name"]) + ".vrma")
		if not FileAccess.file_exists(clip_path):
			continue
		checked += 1
		check(BackendClient.verify_file_sha256(clip_path, str(m["sha256"])), "installed %s matches manifest sha256" % str(m["name"]))
		if mp.load_vrma(str(m["name"]), clip_path):
			loaded += 1
			var clip: VrmaClip = mp.vrma_clips[str(m["name"])]
			check(absf(clip.duration - float(m["duration"])) < 0.05, "%s duration %.3f ~ manifest %.3f" % [str(m["name"]), clip.duration, float(m["duration"])])
		else:
			check(false, "MotionPlayer.load_vrma accepts %s" % str(m["name"]))
	check(checked > 0 and loaded == checked, "all %d installed clips load (%d)" % [checked, loaded])
	check(mp.vrma_clips.has("walk") and (mp.vrma_clips["walk"] as VrmaClip).tracks.has("leftUpperLeg"), "walk clip drives leg bones (not a glide)")
	check(AutonomyBridge.pick_walk_clip(mp.vrma_clips) == "walk", "walk clip exposed for autonomy")
	mp.free()


func _test_autonomy_bridge() -> void:
	print("[autonomy bridge] (pure policy)")
	var b := AutonomyBridge.new()
	var idle := b.context(false, false, false, false, "idle", false, false, 100.0)
	check(not AutonomyBridge.is_blocked(idle), "collapsed pet, idle: not blocked")
	check(AutonomyBridge.is_blocked(b.context(true, false, false, false, "idle", false, false, 100.0)), "panel open blocks")
	check(AutonomyBridge.is_blocked(b.context(false, true, false, false, "idle", false, false, 100.0)), "recording blocks")
	check(AutonomyBridge.is_blocked(b.context(false, false, true, false, "idle", false, false, 100.0)), "speaking (PCM) blocks")
	check(AutonomyBridge.is_blocked(b.context(false, false, false, true, "idle", false, false, 100.0)), "dragging blocks")
	check(AutonomyBridge.is_blocked(b.context(false, false, false, false, "thinking", true, false, 100.0)), "live turn blocks")
	check(AutonomyBridge.is_blocked(b.context(false, false, false, false, "idle", false, true, 100.0)), "foreground playback blocks")
	b.note_dialogue(100.0)
	check(AutonomyBridge.is_blocked(b.context(false, false, false, false, "idle", false, false, 100.0 + AutonomyBridge.DIALOGUE_HOLD - 0.1)), "dialogue hold keeps blocking after the reply")
	check(not AutonomyBridge.is_blocked(b.context(false, false, false, false, "idle", false, false, 100.0 + AutonomyBridge.DIALOGUE_HOLD + 0.1)), "hold expires -> may resume (module settles on top)")
	var pet := Rect2(400, 120, 220, 560)
	check(AutonomyBridge.pointer_near(Vector2(390, 300), pet, Rect2(), false), "pointer just outside the pet counts as near")
	check(not AutonomyBridge.pointer_near(Vector2(100, 100), pet, Rect2(), false), "far pointer not near")
	check(AutonomyBridge.pointer_near(Vector2(100, 100), pet, Rect2(), true), "dragging always near")
	check(AutonomyBridge.pointer_near(Vector2(505, 90), pet, Rect2(495, 80, 30, 30), false), "handle hover counts as near")
	check(not AutonomyBridge.pointer_near(Vector2(INF, 0), pet, Rect2(), false), "non-finite pointer ignored")
	check(AutonomyBridge.state_label("walk", true, false) == "산책 중" and AutonomyBridge.state_label("inspect", true, false) == "살펴보는 중" and AutonomyBridge.state_label("rest", true, false) == "쉬는 중", "Korean state labels")
	check(AutonomyBridge.state_label("walk", false, false) == "꺼짐" and AutonomyBridge.state_label("walk", true, true).contains("패널"), "disabled / panel-open labels")
	# locomotion presentation
	var clips := {"walk": {"loop": true}, "idle_natural": {"loop": true}}
	var plan := AutonomyBridge.locomotion_plan(true, clips, false, 75.0)
	check(plan["action"] == "walk" and plan["clip"] == "walk" and is_equal_approx(float(plan["speed"]), 1.0), "moving + walk clip -> walk loop at 1x (%s)" % str(plan))
	check(is_equal_approx(float(AutonomyBridge.locomotion_plan(true, clips, false, 160.0)["speed"]), 1.6) and is_equal_approx(float(AutonomyBridge.locomotion_plan(true, clips, false, 20.0)["speed"]), 0.6), "walk speed follows the configured speed, clamped")
	check(AutonomyBridge.locomotion_plan(true, {"walk_formal": {}}, false, 75.0)["clip"] == "walk_formal", "walk_formal used when walk missing")
	check(AutonomyBridge.locomotion_plan(true, {}, false, 75.0)["action"] == "float", "no walk clip -> float (never a gliding walk pose)")
	check(AutonomyBridge.locomotion_plan(true, clips, true, 75.0)["action"] == "none", "dialogue gesture active -> never preempted by locomotion")
	check(AutonomyBridge.locomotion_plan(false, clips, false, 75.0)["action"] == "stop", "stop on halt")
	check(absf(AutonomyBridge.float_offset(0.0, 1.0)) < 0.0001 and absf(AutonomyBridge.float_offset(AutonomyBridge.FLOAT_PERIOD * 0.25, 1.0) - AutonomyBridge.FLOAT_AMPLITUDE) < 0.0001 and AutonomyBridge.float_offset(1.0, 0.0) == 0.0, "float offset bounded and fades with blend")
	# ambient idle policy
	check(AutonomyBridge.ambient_idle_choice("auto", clips, false) == "", "no ambient API -> procedural idle only (a raw loop would override gaze/gestures)")
	check(AutonomyBridge.ambient_idle_choice("auto", clips, true) == "idle_natural", "auto + API -> idle_natural")
	check(AutonomyBridge.ambient_idle_choice("auto", {"walk": {"loop": true}}, true) == "", "auto without idle_natural -> none")
	check(AutonomyBridge.ambient_idle_choice("", clips, true) == "", "off stays off")
	check(AutonomyBridge.ambient_idle_choice("idle_natural", clips, true) == "idle_natural" and AutonomyBridge.ambient_idle_choice("dance", clips, true) == "", "explicit choice only when loaded")
	# window restore with negative global origins
	var size := Vector2i(680, 760)
	var screens: Array = [Rect2i(0, 0, 1920, 1040), Rect2i(-2560, -200, 2560, 1400)]
	var fallback := Rect2i(0, 0, 1920, 1040)
	check(AutonomyBridge.restore_position(true, -1500, 300, size, screens, fallback) == Vector2i(-1500, 300), "negative saved origin on the left monitor restored")
	check(AutonomyBridge.restore_position(true, -1500, 300, size, [Rect2i(0, 0, 1920, 1040)], fallback) == Vector2i(1920 - 680 - 16, 1040 - 760 - 8), "monitor gone -> fallback bottom-right")
	check(AutonomyBridge.restore_position(false, -1, -1, size, screens, fallback) == Vector2i(1920 - 680 - 16, 1040 - 760 - 8), "nothing saved -> fallback")
	check(AutonomyBridge.restore_position(true, 5000, 5000, size, screens, fallback) == Vector2i(1920 - 680 - 16, 1040 - 760 - 8), "off-screen saved origin -> fallback")
	check(AutonomyBridge.restore_position(true, -20, -20, size, screens, fallback) == Vector2i(-20, -20), "slightly negative origin still touching the primary restored")


## Host wiring against the real (Astra-owned) DesktopAutonomy in simulation mode: the context the
## host pushes must freeze it instantly, and the locomotion signal must map to the walk plan.
func _test_autonomy_wiring() -> void:
	print("[autonomy wiring] (simulated monitors, no window)")
	var a := DesktopAutonomy.new()
	root.add_child(a)
	var areas: Array[Rect2] = [Rect2(-1920, -100, 1920, 1000), Rect2(0, 0, 1920, 1040)]
	a.configure_simulation(areas, Vector2(-1400, 200), Rect2(400, 120, 220, 560))
	var states: Array = []
	var locomotion: Array = []
	a.state_changed.connect(func(s: String): states.append(s))
	a.locomotion_changed.connect(func(m: bool, v: Vector2): locomotion.append([m, v.length()]))
	var b := AutonomyBridge.new()
	var t := 0.0
	# 1. Panel open (initial app state): blocked forever, never moves.
	var start := a.position
	for i in 600:
		var ctx := b.context(true, false, false, false, "idle", false, false, t)
		a.update_context(ctx["panel_open"], ctx["listening"], ctx["speaking"], ctx["dragging"], ctx["foreground_busy"])
		a.advance(1.0 / 60.0)
		t += 1.0 / 60.0
	check(a.state == "paused" and a.position == start and locomotion.is_empty(), "panel open: paused, no movement after 10 s (state %s)" % a.state)
	# 2. Collapse to pet mode: settle, then walk toward a landmark.
	var walked := false
	var walk_at := -1.0
	for i in 60 * 40:
		var ctx := b.context(false, false, false, false, "idle", false, false, t)
		a.update_context(ctx["panel_open"], ctx["listening"], ctx["speaking"], ctx["dragging"], ctx["foreground_busy"])
		a.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		if a.state == "walk" and not walked:
			walked = true
			walk_at = t
		if walked and a.position.distance_to(start) > 40.0:
			break
	check(walked and walk_at >= DesktopAutonomy.SETTLE_SECONDS - 0.05, "pet mode: walks only after settle (%.2f s)" % walk_at)
	check(a.position != start and not locomotion.is_empty() and locomotion[0][0] == true, "locomotion_changed(true) emitted while travelling")
	check(a.is_origin_safe(a.position), "position stays inside the usable union with negative origins")
	var plan := AutonomyBridge.locomotion_plan(true, {"walk": {"loop": true}}, false, a.speed)
	check(plan["action"] == "walk" and plan["clip"] == "walk", "walk signal -> imported walk loop plan")
	check(AutonomyBridge.locomotion_plan(true, {}, false, a.speed)["action"] == "float", "walk signal without clip -> float plan")
	# 3. User opens the panel mid-walk: frozen the same frame, no further drift.
	var mid := a.position
	var ctx_open := b.context(true, false, false, false, "idle", false, false, t)
	a.update_context(ctx_open["panel_open"], ctx_open["listening"], ctx_open["speaking"], ctx_open["dragging"], ctx_open["foreground_busy"])
	check(a.state == "paused" and locomotion[locomotion.size() - 1][0] == false, "panel open mid-walk: paused immediately with locomotion false")
	for i in 120:
		a.update_context(true, false, false, false, false)
		a.advance(1.0 / 60.0)
		t += 1.0 / 60.0
	check(a.position == mid, "no drift while the panel stays open")
	# 4. Dialogue: user sends a chat (hold window) -> blocked, and resumes only after hold + settle.
	b.note_dialogue(t)
	var resumed_at := -1.0
	for i in 60 * 20:
		var ctx := b.context(false, false, false, false, "idle", false, false, t)
		a.update_context(ctx["panel_open"], ctx["listening"], ctx["speaking"], ctx["dragging"], ctx["foreground_busy"])
		a.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		if a.state == "walk" and resumed_at < 0.0:
			resumed_at = t
	check(resumed_at < 0.0 or resumed_at - (t - 20.0) >= AutonomyBridge.DIALOGUE_HOLD + DesktopAutonomy.SETTLE_SECONDS - 0.1, "after dialogue: no walk before hold + settle (%.2f s)" % (resumed_at - (t - 20.0)))
	# 5. Pointer near the pet pauses; leaving resumes after settle.
	a.set_pointer_interaction(true)
	a.advance(1.0 / 60.0)
	check(a.state == "paused", "pointer near pet -> paused")
	a.set_pointer_interaction(false)
	a.advance(1.0 / 60.0)
	check(a.state == "settle", "pointer left -> settling before any movement")
	check(states.has("paused") and states.has("settle") and states.has("walk"), "state signal covered paused/settle/walk (%s)" % str(states))
	# 6. Disable from settings: stays paused whatever the context.
	a.set_enabled(false)
	for i in 300:
		a.update_context(false, false, false, false, false)
		a.advance(1.0 / 60.0)
	check(a.state == "paused", "disabled -> paused regardless of context")
	a.queue_free()


## Pet size: bounded wheel/slider scale, Unity-style smoothing, and the framing math that keeps a
## chosen window pixel (foot or seat) fixed under scale and facing yaw. The camera part is checked
## against a real Camera3D in a 680x760 SubViewport (projection only, nothing rendered).
func _test_pet_scale() -> void:
	print("[pet scale] (pure math + Camera3D projection, no rendering)")
	var settings_script: GDScript = load("res://scripts/settings.gd")
	check(is_equal_approx(float(settings_script.DEFAULTS["pet_scale"]), AutonomyBridge.SCALE_DEFAULT) and AutonomyBridge.SCALE_DEFAULT >= AutonomyBridge.SCALE_MIN and AutonomyBridge.SCALE_DEFAULT <= AutonomyBridge.SCALE_MAX, "default pet_scale %.2f is the small-pet default inside %.2f..%.2f" % [float(settings_script.DEFAULTS["pet_scale"]), AutonomyBridge.SCALE_MIN, AutonomyBridge.SCALE_MAX])
	check(bool(settings_script.DEFAULTS["surface_roam"]) == true, "surface_roam defaults on")
	check(is_equal_approx(AutonomyBridge.clamp_scale(2.0), 1.25) and is_equal_approx(AutonomyBridge.clamp_scale(0.1), 0.35) and is_equal_approx(AutonomyBridge.clamp_scale(NAN), 0.6) and is_equal_approx(AutonomyBridge.clamp_scale(0.8), 0.8), "clamp_scale bounds and NaN fallback")
	check(is_equal_approx(AutonomyBridge.wheel_scale(0.6, 1, false, true), 0.65) and is_equal_approx(AutonomyBridge.wheel_scale(0.6, -1, false, true), 0.55), "wheel notch = ±0.05")
	check(is_equal_approx(AutonomyBridge.wheel_scale(0.6, 1, true, true), 0.6) and is_equal_approx(AutonomyBridge.wheel_scale(0.6, 1, false, false), 0.6), "wheel ignored while dragging / off the pet")
	check(is_equal_approx(AutonomyBridge.wheel_scale(1.25, 3, false, true), 1.25) and is_equal_approx(AutonomyBridge.wheel_scale(0.35, -3, false, true), 0.35), "wheel bounded at both ends")
	var s := 0.6
	var monotonic := true
	for i in 60:
		var n := AutonomyBridge.smooth_scale(s, 1.0, 1.0 / 60.0)
		if n < s or n > 1.0:
			monotonic = false
		s = n
	check(monotonic and absf(s - 1.0) < 0.01, "smoothing approaches the target monotonically within 1 s (%.4f)" % s)
	check(is_equal_approx(AutonomyBridge.smooth_scale(0.9996, 1.0, 1.0 / 60.0), 1.0) and is_equal_approx(AutonomyBridge.smooth_scale(0.6, 1.0, 5.0), 1.0) and is_equal_approx(AutonomyBridge.smooth_scale(NAN, 0.7, 0.016), 0.7), "smoothing snaps when close, after long frames, and from an invalid current")
	var main_script: GDScript = load("res://scripts/main.gd")
	var win := Vector2(main_script.WINDOW_SIZE)
	var zone: float = main_script.PET_ZONE_WIDTH
	var ref := AutonomyBridge.reference_height_px(win.y)
	check(is_equal_approx(ref * AutonomyBridge.SCALE_MAX + AutonomyBridge.FOOT_MARGIN_PX + AutonomyBridge.HEAD_MARGIN_PX, win.y), "reference height %.0f px: SCALE_MAX fills the window minus margins" % ref)
	var foot_px := AutonomyBridge.foot_pivot_px(win, zone)
	check(foot_px.x > win.x - zone and foot_px.x < win.x and is_equal_approx(foot_px.y, win.y - AutonomyBridge.FOOT_MARGIN_PX), "foot pivot inside the pet zone near the bottom (%s)" % str(foot_px))
	var cam := AutonomyBridge.pet_camera(1.6, 28.0, win, foot_px, ref)
	var ppm := float(cam["px_per_m"])
	var cam_pos: Vector3 = cam["position"]
	check(is_equal_approx(ppm, ref / 1.6) and cam_pos.z > 0.0, "px/m from reference height (%.1f), camera in front of z=0" % ppm)
	check(AutonomyBridge.pixel_to_world(foot_px, cam_pos, ppm, win).is_equal_approx(Vector3.ZERO), "foot pixel maps to the world origin")
	check(AutonomyBridge.pixel_to_world(foot_px - Vector2(0, ppm), cam_pos, ppm, win).is_equal_approx(Vector3(0, 1, 0)), "one metre up = px_per_m pixels up")
	# Real Camera3D agreement (unproject is the inverse of pixel_to_world on the z=0 plane).
	var vp := SubViewport.new()
	vp.size = Vector2i(win)
	root.add_child(vp)
	var camera := Camera3D.new()
	camera.fov = 28.0
	camera.near = 0.05
	camera.far = 50.0
	vp.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(cam["size"])
	camera.transform = Transform3D(Basis.IDENTITY, cam_pos)
	var origin_px := camera.unproject_position(Vector3.ZERO)
	check(origin_px.distance_to(foot_px) < 0.5, "Camera3D projects the origin onto the foot pixel (%s vs %s)" % [str(origin_px), str(foot_px)])
	var top_px := camera.unproject_position(Vector3(0, 1.6, 0))
	check(absf((foot_px.y - top_px.y) - ref) < 0.5, "1.6 m model spans the reference height (%.1f px)" % (foot_px.y - top_px.y))
	var probe := Vector2(120, 333)
	check(camera.unproject_position(AutonomyBridge.pixel_to_world(probe, cam_pos, ppm, win)).distance_to(probe) < 0.5, "pixel_to_world round-trips through Camera3D")
	# Pivot transform: the pivot point stays put under yaw and scale; the body scales around it.
	var pivot_local := Vector3(0.02, 0.0, 0.05)
	var pivot_world := Vector3(1.0, 2.0, 0.0)
	for yaw in [0.0, deg_to_rad(82.0), deg_to_rad(-60.0)]:
		for scale in [0.35, 0.6, 1.25]:
			var basis := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3.ONE * scale)
			var xf := AutonomyBridge.pivot_transform(basis, pivot_world, pivot_local)
			check((xf * pivot_local).is_equal_approx(pivot_world), "pivot fixed at yaw %.0f scale %.2f" % [rad_to_deg(yaw), scale])
			check(is_equal_approx((xf * (pivot_local + Vector3.UP)).y, pivot_world.y + scale), "height scales about the pivot (yaw %.0f scale %.2f)" % [rad_to_deg(yaw), scale])
	check(AutonomyBridge.fit_shift(Rect2(300, 100, 200, 400), win) == Vector2.ZERO, "rect inside the window needs no shift")
	check(AutonomyBridge.fit_shift(Rect2(300, 500, 200, 400), win) == Vector2(0, -140), "legs past the bottom shift the pivot up")
	check(AutonomyBridge.fit_shift(Rect2(300, -20, 200, 400), win) == Vector2(0, 20), "head past the top shifts the pivot down")
	check(AutonomyBridge.fit_shift(Rect2(600, 100, 200, 400), win) == Vector2(-120, 0), "right overflow shifts left")
	check(AutonomyBridge.fit_shift(Rect2(), win) == Vector2.ZERO, "empty rect ignored")
	vp.queue_free()


func _surface_world(windows: Array) -> Dictionary:
	return {"version": 1, "timestamp_msec": 1000, "monitors": [
		{"id": "primary", "x": 0, "y": 0, "width": 1920, "height": 1080, "work_x": 0, "work_y": 0, "work_width": 1920, "work_height": 1040}],
		"windows": windows}


## Host policy against the real (Astra-owned) DesktopAutonomy in surface mode: approach never
## walks, grounded walk only when attached, drag releases, a character change (new bounds and
## anchors) re-seats smoothly, the manual sit lifecycle (seat anchor lowers the window, hold pauses
## roaming, stand restores foot contact) and lost support while seated. Fake world snapshot; no
## window, no Windows helper.
func _test_surface_wiring() -> void:
	print("[surface wiring] (simulated monitor + fake window geometry)")
	var a := DesktopAutonomy.new()
	root.add_child(a)
	var bounds := Rect2(400, 120, 220, 560)
	# Origin (600, 100): the shelf top (y=700) is 80 px away for the foot anchor, the floor 260 px.
	a.configure_simulation([Rect2(0, 0, 1920, 1040)], Vector2(600, 100), bounds)
	var shelf := {"id": "shelf", "x": 300, "y": 700, "width": 1000, "height": 300, "z": 0}
	var b := AutonomyBridge.new()
	# Lambdas capture locals by value: mutable test state lives in one holder dictionary.
	var S := {"contact": {"attached": false, "pose": "foot"}, "t": 0.0, "world": _surface_world([shelf]),
		"anchors": {"foot": Vector2(510, 680), "sit": Vector2(510, 500), "lean": Vector2(560, 420)}}
	var states: Array = []
	var plans: Array = []
	var approach_plans: Array = []
	var clips := {"walk": {"loop": true}, "sit_idle": {"loop": true}}
	a.support_changed.connect(func(c: Dictionary): S["contact"] = c)
	a.state_changed.connect(func(st: String): states.append(st))
	a.locomotion_changed.connect(func(moving: bool, v: Vector2):
		var grounded := AutonomyBridge.grounded(a.surface_mode, a.state, S["contact"])
		var plan := AutonomyBridge.locomotion_plan(moving, clips, false, a.speed, grounded, false)
		plans.append([a.state, plan["action"], AutonomyBridge.facing_velocity(moving, grounded, false, v)])
		if a.state == "approach":
			approach_plans.append(plan["action"]))
	var tick := func(hold: bool, dragging: bool = false) -> void:
		var ctx := b.context(false, false, false, dragging, "idle", false, false, float(S["t"]), hold)
		a.update_context(ctx["panel_open"], ctx["listening"], ctx["speaking"], ctx["dragging"], ctx["foreground_busy"])
		a.set_contact_anchors(S["anchors"])
		a.set_world_snapshot(S["world"]) # the source refreshes at 1 Hz; here every tick keeps it fresh
		a.advance(1.0 / 60.0)
		S["t"] = float(S["t"]) + 1.0 / 60.0
	var run_until_attached := func(max_seconds: float) -> bool:
		for i in int(max_seconds * 60.0):
			tick.call(false)
			if bool(S["contact"].get("attached", false)):
				return true
		return false
	var contact_y := func() -> float:
		return float(S["contact"].get("screen_point", Vector2.INF).y)
	a.set_world_snapshot(S["world"])
	a.set_surface_mode(true)
	check(a.surface_mode and not bool(a.get_support_contact().get("attached", false)), "surface mode on, detached at start")
	check(not AutonomyBridge.grounded(true, "approach", S["contact"]) and not AutonomyBridge.grounded(true, "walk", S["contact"]) and AutonomyBridge.grounded(false, "walk", S["contact"]), "grounded only with attached contact in surface mode; free roam unchanged")
	# 1. Approach: the module glides to the shelf; the host never plays the walk loop meanwhile.
	check(run_until_attached.call(30.0), "attaches to a support within 30 s")
	check(states.has("approach"), "approach state was reported before contact (%s)" % str(states))
	check(not approach_plans.is_empty() and not approach_plans.has("walk"), "approach never planned a grounded walk (%s)" % str(approach_plans.slice(0, 3)))
	check(approach_plans.has("float"), "approach presented as float/idle")
	check(S["contact"].get("kind") == "window" and S["contact"].get("pose") == "foot" and absf(contact_y.call() - 700.0) < 0.01, "nearest support: foot anchor on the window top y=700 (%s)" % str(S["contact"]))
	check(is_equal_approx(a.position.y, 700.0 - S["anchors"]["foot"].y), "window origin places the projected foot on the shelf")
	check(AutonomyBridge.can_sit(true, S["contact"], true, false) and not AutonomyBridge.can_sit(true, S["contact"], false, false) and not AutonomyBridge.can_sit(false, S["contact"], true, false) and AutonomyBridge.can_sit(false, {}, false, true), "sit offered only attached + clip; standing up always allowed")
	# 2. Grounded walk on the shelf: horizontal, walk plan, facing follows the direction.
	for i in 60 * 12:
		tick.call(false)
		if a.state == "walk":
			break
	if a.state != "walk":
		a.observe_interest("shelf_walk", Vector2(1100, 700), 1.0, 20.0)
		check(a.move_to_interest("shelf_walk"), "lateral target accepted on the attached support")
	var y0 := a.position.y
	var walked := false
	var horizontal := true
	var x_start := a.position.x
	for i in 120:
		tick.call(false)
		if a.state != "walk":
			break
		walked = true
		if absf(a.position.y - y0) > 0.001:
			horizontal = false
	check(walked and horizontal and bool(S["contact"].get("attached", false)), "grounded walk stays horizontal and attached")
	var walk_plans := plans.filter(func(p: Array) -> bool: return p[0] == "walk")
	var walk_actions: Array = walk_plans.map(func(p: Array) -> String: return str(p[1]))
	check(walk_actions.has("walk") and not walk_actions.has("float"), "state walk + attached -> walk loop plan, never float (%s)" % str(walk_actions.slice(0, 4)))
	var faced := walk_plans.filter(func(p: Array) -> bool: return (p[2] as Vector2).length() > 0.01)
	check(not faced.is_empty() and signf((faced[0][2] as Vector2).x) == signf(a.position.x - x_start), "facing velocity points along the travel direction")
	check(AutonomyBridge.facing_velocity(false, true, false, Vector2(50, 0)) == Vector2.ZERO and AutonomyBridge.facing_velocity(true, false, false, Vector2(50, 0)) == Vector2.ZERO and AutonomyBridge.facing_velocity(true, true, true, Vector2(50, 0)) == Vector2.ZERO, "stop / approach / seated face the front")
	# 3. Manual drag releases the support; nothing moves while dragging; reattach afterwards.
	tick.call(false, true)
	check(not bool(S["contact"].get("attached", false)) and a.state == "paused", "drag detaches and pauses")
	a.position += Vector2(-150, -30)
	var dragged := a.position
	for i in 120:
		tick.call(false, true)
	check(a.position == dragged, "window position authoritative during drag")
	check(run_until_attached.call(30.0) and S["contact"].get("kind") == "window", "reattaches to the shelf after the drag ends")
	# 4. Character change: a shorter rig = smaller projected bounds + new anchors (> 24 px) ->
	#    detach without moving, then a smooth re-seat with the new foot on the same shelf.
	var before := a.position
	a.set_visible_bounds(Rect2(400, 150, 200, 500))
	S["anchors"] = {"foot": Vector2(500, 650), "sit": Vector2(500, 490), "lean": Vector2(550, 420)}
	tick.call(false)
	check(not bool(S["contact"].get("attached", false)) and a.position == before, "anchor change > 24 px detaches without moving the window")
	check(run_until_attached.call(30.0) and S["contact"].get("kind") == "window" and is_equal_approx(a.position.y, 700.0 - 650.0), "re-seated with the new foot anchor on the shelf (%s)" % str(S["contact"]))
	var standing_origin_y := a.position.y
	# 5. Sit lifecycle. Host: start_contact_pose('sit') then set_contact_pose('sit'); the module
	#    detaches (expected, _sit_attached still false), re-seats the same surface with the seat
	#    anchor, then the host holds it there until stand.
	var surface_before := str(S["contact"].get("surface_id", ""))
	a.set_contact_pose("sit")
	check(not bool(S["contact"].get("attached", false)), "pose change detaches first (host must not treat this as lost support)")
	check(run_until_attached.call(30.0) and S["contact"].get("pose") == "sit", "re-seats with the seat anchor (%s)" % str(S["contact"]))
	check(str(S["contact"].get("surface_id", "")) == surface_before, "same support preferred for sitting")
	check(absf(contact_y.call() - 700.0) < 0.01 and is_equal_approx(a.position.y, 700.0 - S["anchors"]["sit"].y), "seat rests on the window top: window lowered by the seat height")
	check(a.position.y - standing_origin_y > 100.0, "seated window origin is well below the standing one (%.0f px)" % (a.position.y - standing_origin_y))
	var seated := a.position
	var sit_states: Array = []
	for i in 60 * 25:
		tick.call(true) # host hold while seated
		if not sit_states.has(a.state):
			sit_states.append(a.state)
	check(bool(S["contact"].get("attached", false)) and S["contact"].get("pose") == "sit" and a.position == seated, "hold keeps the seated contact for 25 s without walking off (%s)" % str(sit_states))
	check(not sit_states.has("walk") and not sit_states.has("approach"), "no walk/approach while seated")
	check(AutonomyBridge.state_label("paused", true, false, true) == "앉아 있음" and AutonomyBridge.state_label("approach", true, false, true).contains("앉을"), "seated labels")
	# Scaling around the seat keeps the seat anchor still (feet move): no detach.
	S["anchors"] = {"foot": Vector2(500, 690), "sit": Vector2(500, 490), "lean": Vector2(550, 420)}
	tick.call(true)
	check(bool(S["contact"].get("attached", false)), "seat-pivot scale (foot moved, seat fixed) keeps the contact")
	# Stand: pose foot -> detach -> re-seat with foot contact, roaming resumes afterwards.
	a.set_contact_pose("foot")
	check(run_until_attached.call(30.0) and S["contact"].get("pose") == "foot", "stand restores foot contact")
	check(is_equal_approx(a.position.y, 700.0 - S["anchors"]["foot"].y), "window rises back for the standing foot")
	var resumed := false
	for i in 60 * 40:
		tick.call(false)
		if a.state == "walk":
			resumed = true
			break
	check(resumed, "roaming resumes after standing")
	# 6. Lost support while seated: the host stands up on detach (bridge condition), module refloors.
	a.set_contact_pose("sit")
	check(run_until_attached.call(30.0) and S["contact"].get("pose") == "sit", "seated again for the lost-support case")
	S["world"] = _surface_world([])
	tick.call(true)
	check(not bool(S["contact"].get("attached", false)), "closing the window under a seated pet detaches (host stands up)")
	a.set_contact_pose("foot")
	check(run_until_attached.call(40.0) and S["contact"].get("kind") == "floor" and S["contact"].get("pose") == "foot", "after standing the pet settles on the work-area floor (%s)" % str(S["contact"]))
	check(absf(contact_y.call() - 1040.0) < 0.01 and is_equal_approx(a.position.y, 1040.0 - S["anchors"]["foot"].y), "floor contact at the usable-area bottom (taskbar top)")
	# 7. Surface mode off -> free roam, no contact; status lines.
	a.set_surface_mode(false)
	check(not bool(a.get_support_contact().get("attached", false)), "surface mode off clears the contact")
	check(AutonomyBridge.surface_status(false, "Windows", false, "", {}).contains("자유"), "status: surface roam off")
	check(AutonomyBridge.surface_status(true, "Linux", false, "", {}).contains("Windows"), "status: non-Windows says the window source is Windows-only")
	check(AutonomyBridge.surface_status(true, "Windows", true, "", S["world"]).contains("창 0개") and AutonomyBridge.surface_status(true, "Windows", true, "", S["world"]).contains("내용"), "status: window count + no-content-reading note")
	check(AutonomyBridge.surface_status(true, "Windows", false, "helper exited", {}).contains("helper exited"), "status: source error surfaced")
	a.queue_free()


func _test_panel_vrma_and_autonomy() -> void:
	print("[panel: vrma presets + roaming controls]")
	_ensure_settings_singleton()
	var panel := ControlPanel.new()
	root.add_child(panel)
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(_bank_path()))
	panel.set_bank(bank)
	var before := panel.preset_names().size()
	panel.set_vrma_clips({"walk": {"duration": 1.333, "loop": true, "description": "Walking"}, "dance": {"duration": 1.0, "loop": false, "description": "Celebratory dance"}, "nod": {"duration": 2.0}})
	var names := panel.preset_names()
	check(names.size() == before + 2 and names.has("walk") and names.has("dance"), "VRMA clips join the preset list; bank name 'nod' wins the duplicate (%d -> %d)" % [before, names.size()])
	check(names.find("walk") > names.find("wave"), "bank presets listed before VRMA clips")
	var opt: OptionButton = panel._preset_option
	var dance_idx := -1
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == "dance":
			dance_idx = i
	check(dance_idx >= 0 and opt.get_item_text(dance_idx).begins_with("dance") and opt.get_item_text(dance_idx).contains("VRMA") and not opt.get_item_text(dance_idx).to_lower().contains("greet"), "dance shown as a VRMA clip with its own name")
	check(opt.get_item_tooltip(dance_idx).begins_with("Celebratory dance"), "tooltip is the manifest description")
	opt.select(dance_idx)
	check(panel._selected_preset() == "dance" and panel.is_vrma_selected(), "selection resolves to the clip name")
	panel._add_sequence_step()
	check(panel._sequence.is_empty() and panel._motion_result.text.contains("읽기 전용"), "read-only clip refused by the sequence composer (%s)" % panel._motion_result.text)
	var errs: Array[String] = []
	check(panel.bank.compose_sequence("x", [{"name": "dance"}], errs).is_empty(), "bank composer never sees VRMA names")
	var idle_opt: OptionButton = panel._idle_clip_option
	var idle_choices: Array = []
	for i in idle_opt.item_count:
		idle_choices.append(str(idle_opt.get_item_metadata(i)))
	check(idle_choices == [""] and idle_opt.disabled, "unsupported ambient selector offers only the disabled built-in idle (%s)" % str(idle_choices))
	check(idle_opt.get_item_text(idle_opt.selected) == "기본 대기 동작 사용", "idle setting uses plain product language")
	panel.set_autonomy_state("산책 중")
	check(panel._autonomy_state.text == "상태: 산책 중", "roaming state label")
	var got: Array = []
	panel.setting_changed.connect(func(k: String, v: Variant): got.append([k, v]))
	panel._autonomy_check.button_pressed = false
	panel._autonomy_speed.value = 120.0
	check(got.has(["autonomy_enabled", false]) and got.has(["autonomy_speed", 120.0]), "toggle/speed emit settings (%s)" % str(got))
	# Pet size + desktop surface controls.
	var slider: HSlider = panel._scale_slider
	var saved_scale := AutonomyBridge.clamp_scale(float(panel._setting("pet_scale", AutonomyBridge.SCALE_DEFAULT)))
	check(is_equal_approx(slider.min_value, AutonomyBridge.SCALE_MIN) and is_equal_approx(slider.max_value, AutonomyBridge.SCALE_MAX) and is_equal_approx(slider.value, saved_scale), "scale slider spans %.2f..%.2f, starts at the clamped saved value %.2f" % [slider.min_value, slider.max_value, slider.value])
	got.clear()
	panel.set_pet_scale(0.9)
	check(is_equal_approx(panel.pet_scale(), 0.9) and (slider.get_meta("value_label") as Label).text == "0.90" and got.is_empty(), "wheel sync updates slider + label without re-emitting")
	slider.value = 1.1
	check(got.has(["pet_scale", 1.1]), "slider emits pet_scale")
	panel.set_pet_scale(3.0)
	check(is_equal_approx(panel.pet_scale(), AutonomyBridge.SCALE_MAX), "slider clamps out-of-range sync")
	var surface: CheckButton = panel._surface_check
	check(surface.button_pressed, "surface roam defaults on")
	got.clear()
	surface.button_pressed = false
	check(got.has(["surface_roam", false]), "surface toggle emits surface_roam")
	var sit: Button = panel._sit_button
	var sits: Array = []
	panel.sit_requested.connect(func(v: bool): sits.append(v))
	check(sit.disabled and sit.text == "앉기 · 펫 모드" and not panel.is_sitting(), "sit button disabled until the host allows it")
	panel.set_sit_state(true, false)
	check(not sit.disabled, "sit enabled when attached + clip")
	sit.pressed.emit()
	panel.set_sit_state(true, true)
	sit.pressed.emit()
	check(sits == [true, false] and sit.text == "일어서기" and panel.is_sitting(), "button toggles sit/stand requests (%s)" % str(sits))
	panel.set_sit_state(false, false)
	check(sit.disabled and sit.text == "앉기 · 펫 모드", "detached -> sit disabled again")
	panel.set_surface_status("표면 걷기: 창 3개")
	check(panel._surface_status.text == "표면 걷기: 창 3개", "surface status label")
	var budget := ControlPanel.PANEL_WIDTH - 30.0
	check(panel.widest_child()["width"] <= budget, "new roaming/surface section keeps the panel within the CJK budget (%s)" % str(panel.widest_child()))
	panel.queue_free()


func _test_vrm_runtime() -> void:
	print("[vrm runtime]")
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/cheval-grand.vrm").simplify_path()
	if not FileAccess.file_exists(path):
		print("  skipped: no VRM at " + path)
		return
	var t0 := Time.get_ticks_msec()
	var scene := VrmAvatar.load_vrm(path)
	check(scene != null, "runtime VRM import through addon")
	if scene == null:
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var av := VrmAvatar.new()
	holder.add_child(av)
	av.set_model(scene)
	print("  loaded '%s' spec %s in %d ms, bones=%d expressions=%s" % [av.meta_title, av.spec_version, Time.get_ticks_msec() - t0, av.bone_index.size(), str(av.expression_names())])
	for b in ["head", "neck", "spine", "chest", "leftUpperArm", "rightUpperArm", "leftLowerArm", "rightLowerArm", "hips"]:
		check(av.bone_index.has(b), "normalized bone resolved: " + b)
	check(av.has_expression("blink") and av.has_expression("aa") and av.has_expression("happy"), "blink/aa/happy expressions resolved")
	# Facing check: left arm should be at +X (model faces +Z after addon conversion).
	var l := av.bone_global_position("leftUpperArm")
	var r := av.bone_global_position("rightUpperArm")
	check(l.x > r.x, "left arm at +X (faces +Z): L=%s R=%s" % [str(l), str(r)])
	# Apply a nod and verify the head bone's global pose tilts forward (+Z) rather than sideways.
	av.apply_pose({"head": Vector3(15, 0, 0)})
	var idx: int = av.bone_index["head"]
	var posed := av.skeleton.get_bone_global_pose(idx).basis
	var rest := av.skeleton.get_bone_global_rest(idx).basis
	var up_posed := posed * Vector3.UP
	var up_rest := rest * Vector3.UP
	check(up_posed.z - up_rest.z > 0.1 and absf(up_posed.x - up_rest.x) < 0.02, "nod tilts head forward in world space (d=%s)" % str(up_posed - up_rest))
	# Arm bones: the avatar (Astra-owned) composes a relaxed base (upper arms ~72° down, elbows
	# slightly bent) UNDER the additive bank offsets, because the imported humanoid rest is a
	# T-pose. Frontend contract checked here: apply_pose({}) is NOT a T-pose (hands well below
	# the shoulders), canonical +z on the right upper arm still raises the hand outward from
	# that rest, the arm's own origin never moves, and the motion stays in the frontal plane.
	av.apply_pose({})
	var hand_rest := av.bone_global_position("rightHand")
	var shoulder := av.bone_global_position("rightUpperArm")
	var t_hand := av.skeleton.global_transform * av.skeleton.get_bone_global_rest(av.bone_index["rightHand"]).origin
	print("  right hand T-pose=%s relaxed=%s shoulder=%s" % [str(t_hand), str(hand_rest), str(shoulder)])
	check(shoulder.y - hand_rest.y > 0.3, "relaxed base pose drops the hand well below the shoulder (dy=%.2f)" % (shoulder.y - hand_rest.y))
	check(t_hand.y - hand_rest.y > 0.3, "relaxed base pose is not the imported T-pose (hand fell %.2f)" % (t_hand.y - hand_rest.y))
	av.apply_pose({"rightUpperArm": Vector3(0, 0, 60)})
	var hand_after := av.bone_global_position("rightHand")
	print("  right hand after(z=+60)=%s" % str(hand_after))
	check(hand_after.y - hand_rest.y > 0.2, "canonical +z raises the right hand from the relaxed base (wave)")
	check(av.bone_global_position("rightUpperArm").is_equal_approx(shoulder), "posing the arm does not move its own origin (ancestors stay at rest)")
	check(hand_after.x < hand_rest.x - 0.05 and absf(hand_after.z - hand_rest.z) < 0.08, "arm swings outward in the frontal plane (dx=%.2f dz=%.2f)" % [hand_after.x - hand_rest.x, hand_after.z - hand_rest.z])
	av.apply_pose({})
	check(av.skeleton.get_bone_pose_rotation(idx).is_equal_approx(av.skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()), "reset returns head to rest")
	# Expressions write blend shapes
	av.set_expression("aa", 0.7)
	av.apply_expressions()
	var bind: Array = av.expressions["aa"][0]
	check(is_equal_approx((bind[0] as MeshInstance3D).get_blend_shape_value(bind[1]), 0.7 * bind[2]), "expression weight applied to blend shape")
	av.set_expression("aa", 0.0)
	av.apply_expressions()
	check(is_zero_approx((bind[0] as MeshInstance3D).get_blend_shape_value(bind[1])), "expression cleared")
	# Motion player drives the avatar without a display
	var mp := MotionPlayer.new()
	mp.avatar = av
	holder.add_child(mp)
	var bank := MotionBank.parse_json_text(FileAccess.get_file_as_string(_bank_path()))
	mp.set_bank(bank)
	check(mp.play_gesture("wave", "happy", 1.0, 1.0, 1), "gesture starts")
	check(not mp.play_gesture("not_in_bank"), "unknown gesture rejected -> idle")
	mp.play_gesture("nod")
	mp._process(0.016)
	mp._process(0.8)
	check(mp.is_gesture_active(), "gesture active mid-clip")
	mp.stop_gesture()
	check(not mp.is_gesture_active() and mp.current_gesture() == "idle", "stop returns to idle")
	var aabb := av.compute_aabb()
	check(aabb.size.y > 1.0 and aabb.size.y < 2.5, "model AABB height plausible: %s" % str(aabb))
	_test_scale_with_avatar(av, aabb)
	holder.queue_free()


## Main's framing applied to the real rig: the stable foot anchor projects onto the foot pixel at
## every scale and facing yaw, the body fits the window at SCALE_MAX, and switching the pivot to
## the seat keeps the seat pixel fixed while scaling (legs move instead).
func _test_scale_with_avatar(av: VrmAvatar, aabb: AABB) -> void:
	print("[pet scale on rig] (projection only)")
	var main_script: GDScript = load("res://scripts/main.gd")
	var win := Vector2(main_script.WINDOW_SIZE)
	var zone: float = main_script.PET_ZONE_WIDTH
	av.transform = Transform3D.IDENTITY
	av.apply_pose({})
	var rest := av.contact_anchors()
	check(rest.has("foot") and rest.has("sit"), "rig exposes stable foot/sit anchors")
	if not rest.has("foot"):
		return
	var foot_local: Vector3 = rest["foot"]
	var sit_local: Vector3 = rest["sit"]
	check(sit_local.y - foot_local.y > 0.3 * aabb.size.y, "seat anchor well above the sole (%.2f m)" % (sit_local.y - foot_local.y))
	var foot_px := AutonomyBridge.foot_pivot_px(win, zone)
	var cam := AutonomyBridge.pet_camera(aabb.size.y, 28.0, win, foot_px, AutonomyBridge.reference_height_px(win.y))
	var ppm := float(cam["px_per_m"])
	var cam_pos: Vector3 = cam["position"]
	var vp := SubViewport.new()
	vp.size = Vector2i(win)
	root.add_child(vp)
	var camera := Camera3D.new()
	camera.fov = 28.0
	camera.near = 0.05
	camera.far = 50.0
	vp.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(cam["size"])
	camera.transform = Transform3D(Basis.IDENTITY, cam_pos)
	# Same projection + body trim as Main._update_pet_rect (the mesh AABB is the wide T-pose box).
	var project_rect := func() -> Rect2:
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		for i in 8:
			var p := camera.unproject_position(av.global_transform * aabb.get_endpoint(i))
			min_p = min_p.min(p)
			max_p = max_p.max(p)
		return AutonomyBridge.body_rect(Rect2(min_p, max_p - min_p))
	var heights := {}
	for scale in [AutonomyBridge.SCALE_MIN, AutonomyBridge.SCALE_DEFAULT, AutonomyBridge.SCALE_MAX]:
		for yaw in [0.0, deg_to_rad(82.0)]:
			var basis := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3.ONE * scale)
			av.transform = AutonomyBridge.pivot_transform(basis, AutonomyBridge.pixel_to_world(foot_px, cam_pos, ppm, win), foot_local)
			var anchors := av.contact_anchors()
			var px := camera.unproject_position(anchors["foot"])
			check(px.distance_to(foot_px) < 1.0, "foot anchor on the foot pixel at scale %.2f yaw %.0f (%s)" % [scale, rad_to_deg(yaw), str(px)])
			var rect: Rect2 = project_rect.call()
			if yaw == 0.0:
				heights[scale] = rect.size.y
				check(rect.position.y >= 0.0 and rect.end.y <= win.y and rect.end.y >= foot_px.y - 2.0, "body fits the window vertically at scale %.2f (rect %s)" % [scale, str(rect)])
				# Horizontally the trimmed body must fit the window; above ~1.0 the wide T-pose box
				# may need the pivot nudged left (fit_shift), which the host applies to the pivot.
				var shift := AutonomyBridge.fit_shift(rect, win)
				var shifted := Rect2(rect.position + shift, rect.size)
				check(shifted.position.x >= -0.01 and shifted.end.x <= win.x + 0.01 and is_zero_approx(shift.y), "body inside the window horizontally after fit_shift at scale %.2f (shift %s)" % [scale, str(shift)])
				if scale <= AutonomyBridge.SCALE_DEFAULT:
					check(shift == Vector2.ZERO and rect.position.x >= win.x - zone, "small/default pet stays inside the pet zone without any shift (rect %s)" % str(rect))
	var ratio: float = heights[AutonomyBridge.SCALE_MAX] / heights[AutonomyBridge.SCALE_DEFAULT]
	check(absf(ratio - AutonomyBridge.SCALE_MAX / AutonomyBridge.SCALE_DEFAULT) < 0.2, "projected height scales with the pet scale (ratio %.2f, small perspective tolerance)" % ratio)
	check(heights[AutonomyBridge.SCALE_DEFAULT] < win.y * 0.55, "default pet is a small pet (%.0f px tall)" % heights[AutonomyBridge.SCALE_DEFAULT])
	# Seat pivot: switch at 0.6 (seat pixel taken from the current pose), scale to 1.25.
	var basis6 := Basis.IDENTITY.scaled(Vector3.ONE * AutonomyBridge.SCALE_DEFAULT)
	av.transform = AutonomyBridge.pivot_transform(basis6, AutonomyBridge.pixel_to_world(foot_px, cam_pos, ppm, win), foot_local)
	var seat_px := camera.unproject_position(av.contact_anchors()["sit"])
	var foot_before := camera.unproject_position(av.contact_anchors()["foot"])
	var basis_max := Basis.IDENTITY.scaled(Vector3.ONE * AutonomyBridge.SCALE_MAX)
	av.transform = AutonomyBridge.pivot_transform(basis_max, AutonomyBridge.pixel_to_world(seat_px, cam_pos, ppm, win), sit_local)
	var seat_after := camera.unproject_position(av.contact_anchors()["sit"])
	var foot_after := camera.unproject_position(av.contact_anchors()["foot"])
	check(seat_after.distance_to(seat_px) < 1.0, "seat pixel fixed while scaling around the seat (%s -> %s)" % [str(seat_px), str(seat_after)])
	check(foot_after.y > foot_before.y + 50.0, "feet drop below the seat when the seated pet grows (%.0f -> %.0f)" % [foot_before.y, foot_after.y])
	var rect_max: Rect2 = project_rect.call()
	var shift := AutonomyBridge.fit_shift(rect_max, win)
	check(shift.y < 0.0 and rect_max.end.y > win.y and is_equal_approx(rect_max.end.y + shift.y, win.y), "seated max scale overflows the bottom; fit_shift lifts the pivot exactly as far as needed (%s)" % str(shift))
	av.transform = Transform3D.IDENTITY
	vp.queue_free()
