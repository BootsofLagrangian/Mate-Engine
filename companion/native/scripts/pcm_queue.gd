class_name PcmQueue
extends RefCounted
## Bounded pending-PCM ring with turn/sequence guarding. Pure logic (no audio nodes)
## so it can be verified headless; AudioOutput drains it into an AudioStreamGenerator.

var rate: int = 32000
var max_pending_frames: int = 32000 * 120
var pending := PackedFloat32Array()
var turn_id: String = ""
var last_sequence: int = -1
var accepted_chunks: int = 0
var stale_chunks: int = 0
var dropped_frames: int = 0
var total_pushed_frames: int = 0
var overflowed: bool = false # set when a chunk was rejected because the bound was reached


func begin_turn(id: String) -> void:
	turn_id = id
	last_sequence = -1
	accepted_chunks = 0
	stale_chunks = 0
	dropped_frames = 0
	total_pushed_frames = 0
	overflowed = false
	pending = PackedFloat32Array()


func clear() -> void:
	pending = PackedFloat32Array()
	overflowed = false


func pending_frames() -> int:
	return pending.size()


func pending_seconds() -> float:
	return float(pending.size()) / float(maxi(rate, 1))


## Accept a chunk for [turn] with [sequence]. Returns true when the PCM was queued.
## Stale turn IDs and out-of-order/duplicate sequences are rejected.
func push(turn: String, sequence: int, bytes: PackedByteArray) -> bool:
	if turn != turn_id or turn_id.is_empty():
		stale_chunks += 1
		return false
	if sequence >= 0:
		if sequence <= last_sequence:
			stale_chunks += 1
			return false
		last_sequence = sequence
	var frames := decode_int16(bytes)
	if frames.is_empty():
		return false
	var room := max_pending_frames - pending.size()
	if frames.size() > room:
		# Overflow is an error condition, not something to clip: partial chunks would play as
		# broken words. The whole chunk is rejected and the owner must cancel the turn visibly.
		dropped_frames += frames.size()
		overflowed = true
		return false
	pending.append_array(frames)
	accepted_chunks += 1
	total_pushed_frames += frames.size()
	return true


## Remove and return up to [max_frames] frames from the front of the ring.
func take(max_frames: int) -> PackedFloat32Array:
	if max_frames <= 0 or pending.is_empty():
		return PackedFloat32Array()
	var n := mini(max_frames, pending.size())
	var out := pending.slice(0, n)
	pending = pending.slice(n)
	return out


static func decode_int16(bytes: PackedByteArray) -> PackedFloat32Array:
	var count := bytes.size() / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var v := bytes.decode_s16(i * 2)
		out[i] = float(v) / 32768.0
	return out


static func rms(frames: PackedFloat32Array) -> float:
	if frames.is_empty():
		return 0.0
	var acc := 0.0
	for f in frames:
		acc += f * f
	return sqrt(acc / frames.size())
