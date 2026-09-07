class_name AudioOutput
extends Node
## Streams server PCM (signed16 LE mono, default 32000 Hz) through an
## AudioStreamGenerator. The generator buffer is drained every frame from a
## bounded PcmQueue; playback continues after the server "done" event until the
## ring and generator run dry; cancel clears both immediately.
## Also exposes a playback-aligned RMS envelope for lip sync and reports real
## playback start/drain per turn id (playback_changed) for the backend's
## {type:playback} accounting. The id is captured before cancel clears it.

signal voice_active_changed(active: bool)
signal playback_changed(turn_id: String, playing: bool)
signal overflow(turn_id: String, pending_seconds: float) # bound reached: playback was flushed, owner must cancel the turn
signal stats_changed(stats: Dictionary)

const GENERATOR_BUFFER_SECONDS := 0.25
const MAX_PENDING_SECONDS := 120.0
const ENVELOPE_CHUNK := 320 # 10 ms at 32 kHz

var rate: int = 32000
var queue := PcmQueue.new()
var envelope: float = 0.0
var voice_active := false
var turn_id: String = ""
var playing_turn: String = "" # turn id the last playback:true was reported for

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _generator: AudioStreamGenerator
var _envelope_schedule: Array = [] # [[time_sec, rms], ...]
var _capacity: int = 0 # generator ring capacity, measured once per (re)start of the player
var _drained_since_done := false


func _ready() -> void:
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = rate
	_generator.buffer_length = GENERATOR_BUFFER_SECONDS
	_player = AudioStreamPlayer.new()
	_player.name = "VoicePlayer"
	_player.stream = _generator
	_player.bus = "Master"
	add_child(_player)
	queue.rate = rate
	queue.max_pending_frames = int(rate * MAX_PENDING_SECONDS)
	_ensure_playing()


## Makes sure the player runs. Capacity is measured only when the player is (re)started,
## i.e. when the generator ring is empty; re-measuring on every chunk would undercount
## buffered frames (and break voice-active / lip-sync timing) once audio is queued.
func _ensure_playing() -> void:
	if _player == null:
		return
	var restarted := false
	if not _player.playing:
		_player.play()
		restarted = true
	var pb := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb != _playback:
		_playback = pb
		restarted = true
	if _playback and (restarted or _capacity <= 0):
		_capacity = _playback.get_frames_available()


func set_volume_db(db: float) -> void:
	_player.volume_db = db


## Begin accepting audio for [id]; anything from other turns is rejected until the next begin_turn.
## If a previous turn was still audible, its playback is reported as ended (the ring is reset).
func begin_turn(id: String) -> void:
	if voice_active and not playing_turn.is_empty() and playing_turn != id:
		_report_playback(playing_turn, false)
	turn_id = id
	queue.begin_turn(id)
	_drained_since_done = false


## Contract audio event: {type:audio, pcm:<base64 s16le mono>, sequence, phrase, turn_id, sample_rate?}
func push_event(event: Dictionary) -> bool:
	var ev_turn := str(event.get("turn_id", ""))
	var seq := int(event.get("sequence", -1))
	var ev_rate := int(event.get("sample_rate", rate))
	if ev_rate != rate and ev_rate > 0:
		_set_rate(ev_rate)
	var b64 := str(event.get("pcm", event.get("audio", "")))
	if b64.is_empty():
		return false
	var bytes := Marshalls.base64_to_raw(b64)
	if bytes.size() % 2 != 0:
		push_warning("audio chunk has odd byte length; dropping last byte")
		bytes = bytes.slice(0, bytes.size() - 1)
	var ok := queue.push(ev_turn, seq, bytes)
	if ok:
		_ensure_playing()
	elif queue.overflowed:
		_overflow(ev_turn)
	return ok


func _overflow(turn: String) -> void:
	var seconds := queue.pending_seconds()
	push_warning("audio ring overflow for %s (%.1f s pending); flushing" % [turn, seconds])
	cancel()
	overflow.emit(turn, seconds)


func push_raw(turn: String, seq: int, bytes: PackedByteArray) -> bool:
	var ok := queue.push(turn, seq, bytes)
	if ok:
		_ensure_playing()
	elif queue.overflowed:
		_overflow(turn)
	return ok


func _set_rate(new_rate: int) -> void:
	rate = new_rate
	queue.rate = new_rate
	queue.max_pending_frames = int(new_rate * MAX_PENDING_SECONDS)
	_player.stop()
	_playback = null
	_capacity = 0
	_generator.mix_rate = new_rate
	_ensure_playing()


## Hard stop: clears the pending ring and the generator buffer, drops the envelope.
## AudioStreamGeneratorPlayback.clear_buffer() refuses while active, so restart the player instead.
## The turn id is captured first so the playback:false report names the right turn.
func cancel() -> void:
	var ended := playing_turn if not playing_turn.is_empty() else turn_id
	queue.clear()
	queue.turn_id = ""
	turn_id = ""
	if _player.playing:
		_player.stop()
	_playback = null
	_capacity = 0
	_ensure_playing()
	_envelope_schedule.clear()
	envelope = 0.0
	_set_voice_active(false, ended)


func buffered_frames() -> int:
	if _playback == null:
		return 0
	return maxi(_capacity - _playback.get_frames_available(), 0)


func is_voice_active() -> bool:
	return voice_active


func stats() -> Dictionary:
	return {
		"pending_seconds": queue.pending_seconds(),
		"buffered_ms": int(1000.0 * buffered_frames() / maxi(rate, 1)),
		"accepted": queue.accepted_chunks,
		"stale": queue.stale_chunks,
		"dropped_frames": queue.dropped_frames,
		"rate": rate,
		"capacity": _capacity,
	}


func _process(_delta: float) -> void:
	if _playback == null:
		_ensure_playing()
		if _playback == null:
			return
	var now := Time.get_ticks_usec() / 1000000.0
	# Drain: fill whatever room the generator has from the pending ring.
	var room := _playback.get_frames_available()
	if room > 0 and queue.pending_frames() > 0:
		var chunk := queue.take(room)
		var already := _capacity - room
		var frames := PackedVector2Array()
		frames.resize(chunk.size())
		var offset := 0
		while offset < chunk.size():
			var n := mini(ENVELOPE_CHUNK, chunk.size() - offset)
			var sub := chunk.slice(offset, offset + n)
			var start_time := now + float(already + offset) / float(rate)
			_envelope_schedule.append([start_time, PcmQueue.rms(sub)])
			for i in n:
				var s := sub[i]
				frames[offset + i] = Vector2(s, s)
			offset += n
		_playback.push_buffer(frames)
	# Envelope aligned to the scheduled playback time of each 10 ms block.
	var target := 0.0
	var consumed := 0
	for entry in _envelope_schedule:
		if entry[0] <= now:
			target = entry[1]
			consumed += 1
		else:
			break
	if consumed > 0:
		_envelope_schedule = _envelope_schedule.slice(consumed)
		envelope = clampf(target * 5.5, 0.0, 1.0)
	elif _envelope_schedule.is_empty():
		envelope = lerpf(envelope, 0.0, 0.3)
	var active := queue.pending_frames() > 0 or buffered_frames() > 64
	_set_voice_active(active, turn_id)


func _set_voice_active(active: bool, id: String) -> void:
	if active == voice_active:
		return
	voice_active = active
	if active:
		_report_playback(id, true)
	else:
		_report_playback(id if not id.is_empty() else playing_turn, false)
	voice_active_changed.emit(active)


func _report_playback(id: String, playing: bool) -> void:
	if playing:
		playing_turn = id
		if not id.is_empty():
			playback_changed.emit(id, true)
	else:
		var ended := id if not id.is_empty() else playing_turn
		playing_turn = ""
		if not ended.is_empty():
			playback_changed.emit(ended, false)
