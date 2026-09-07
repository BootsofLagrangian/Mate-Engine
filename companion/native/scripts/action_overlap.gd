class_name ActionOverlap
extends RefCounted
## Two finite live action timelines; sampling and pose/IK application belong to
## MotionPlayer. Duration/time are performed wall seconds, already speed-scaled.
## Channel weights blend shared channels; disjoint outgoing channels stay live.
## Leg/root actions and support changes queue at the boundary without overlap.

const CHANNELS := ["head", "arms", "torso", "legs", "root"]
const SUPPORTS := ["foot", "sit", "lean"]
const MAX_DURATION := 120.0
const MAX_LEAD := 1.0

var clock := 0.0
var _current: Dictionary = {}
var _queued: Dictionary = {}


func reset() -> void:
	_current.clear()
	_queued.clear()
	clock = 0.0


func is_active() -> bool:
	return not _current.is_empty()


func start(name: String, duration: float, channels: Array, support: String = "foot", start_time: float = 0.0) -> bool:
	if not _valid(name, duration, channels, support) or not is_finite(start_time):
		return false
	reset()
	clock = start_time
	_current = _action(name, duration, channels, support, start_time)
	return true


func queue(name: String, duration: float, lead_seconds: float = 0.35,
		channels: Array = ["head", "arms", "torso"], support: String = "foot") -> Dictionary:
	if not _valid(name, duration, channels, support) or not is_finite(lead_seconds) or lead_seconds < 0.0:
		return {"accepted": false, "gated": false, "reason": "invalid_action"}
	if not _queued.is_empty():
		return {"accepted": false, "gated": false, "reason": "queue_full"}
	if _current.is_empty():
		_current = _action(name, duration, channels, support, clock)
		return {"accepted": true, "gated": false, "reason": "started"}
	var gated: bool = support != _current.support or _full_body(channels) or _full_body(_current.channels)
	var lead := 0.0 if gated else minf(MAX_LEAD, minf(lead_seconds, duration * 0.5))
	var end: float = _current.start_time + _current.duration
	_queued = _action(name, duration, channels, support, maxf(clock, end - lead))
	return {"accepted": true, "gated": gated, "reason": "support_boundary" if gated else "queued"}


func advance(delta: float) -> Dictionary:
	var promoted := false
	var finished: Array[String] = []
	if is_finite(delta) and delta >= 0.0:
		clock += delta
	if not _current.is_empty() and clock >= float(_current.start_time) + float(_current.duration):
		finished.append(str(_current.name))
		_current = _queued
		_queued = {}
		promoted = not _current.is_empty()
		# A long frame may also cross the incoming action's own end. Never
		# restart or extend it merely because promotion happened this frame.
		if not _current.is_empty() and clock >= float(_current.start_time) + float(_current.duration):
			finished.append(str(_current.name))
			_current = {}
	var result := {"time": clock, "current": "" if _current.is_empty() else _current.name,
		"queued": "" if _queued.is_empty() else _queued.name,
		"outgoing": {}, "incoming": {}, "promoted": promoted, "finished": finished}
	if _current.is_empty():
		return result
	var weights := {}
	for channel in _current.channels:
		weights[channel] = 1.0
	if not _queued.is_empty() and clock >= float(_queued.start_time):
		var end: float = _current.start_time + _current.duration
		var span := end - float(_queued.start_time)
		var blend := smoothstep(0.0, span, clock - float(_queued.start_time)) if span > 0.0 else 1.0
		var incoming_weights := {}
		for channel in _queued.channels:
			incoming_weights[channel] = blend
			if weights.has(channel):
				weights[channel] = 1.0 - blend
		result.incoming = _sample(_queued, incoming_weights)
	result.outgoing = _sample(_current, weights)
	return result


static func _valid(name: String, duration: float, channels: Array, support: String) -> bool:
	if name.is_empty() or name.length() > 128 or not is_finite(duration) or duration <= 0.0 or duration > MAX_DURATION or support not in SUPPORTS:
		return false
	if channels.is_empty() or channels.size() > CHANNELS.size():
		return false
	for channel in channels:
		if channel not in CHANNELS:
			return false
	return true


static func _full_body(channels: Array) -> bool:
	return "legs" in channels or "root" in channels


static func _action(name: String, duration: float, channels: Array, support: String, started: float) -> Dictionary:
	return {"name": name, "duration": duration, "channels": channels.duplicate(), "support": support, "start_time": started}


func _sample(action: Dictionary, weights: Dictionary) -> Dictionary:
	return {"name": action.name, "time": maxf(0.0, clock - float(action.start_time)),
		"start_time": action.start_time, "duration": action.duration,
		"support": action.support, "weight_by_channel": weights}
