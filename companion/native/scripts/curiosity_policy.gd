extends RefCounted
## Local exploration heuristic, not a biological model. Candidates must already
## be reachable/admitted by the host; this policy never changes navigation rules.
## drive.forward and drive.turn are normalized [-1,1]. With drive.heading as a
## Vector2, forward sets directional interest and turn rotates it by up to 90°.
const MAX_MEMORY := 128 # target and spatial entries share this total budget
const MAX_CANDIDATES := 128
const CELL_SIZE := 120.0
const MIN_TRAVEL := 40.0
const REST_SECONDS := 12.0
const REVISIT_SECONDS := 90.0
const RECOVERY_SECONDS := 120.0
const FAILURE_SECONDS := 60.0
const MIN_SCORE := 0.18
var seed := 173
var diagnostics: Dictionary = {}
var _memory: Dictionary = {}
var _origin := Vector2.INF
var _arrivals: Array[Dictionary] = []
var _last_arrival := -INF
var _time := -INF

func reset() -> void:
	_memory.clear()
	_arrivals.clear()
	_origin = Vector2.INF
	_last_arrival = -INF
	_time = -INF
	diagnostics.clear()

func choose(candidates: Array, position: Vector2, now: float, drive: Dictionary = {}) -> Dictionary:
	if not position.is_finite() or not is_finite(now): return _rest("invalid_context",[])
	_time = maxf(_time,now)
	now = _time
	if not _origin.is_finite(): _origin = position
	if now - _last_arrival < REST_SECONDS: return _rest("settling_after_arrival",[])
	var scores: Array[Dictionary] = []
	var best: Dictionary = {}
	var seen := {}
	for candidate in candidates.slice(0,MAX_CANDIDATES):
		if not candidate is Dictionary: continue
		var id := str(candidate.get("id",""))
		var point: Variant = candidate.get("point",null)
		if id.is_empty() or id.length()>160 or seen.has(id) or not point is Vector2 or not point.is_finite(): continue
		seen[id] = true
		var distance: float = position.distance_to(point)
		if distance < MIN_TRAVEL: continue
		var target: Dictionary = _target_entry(id,point)
		if float(target.get("blocked_until",-INF)) > now: continue
		# The previous destination stays unavailable briefly after A→B so a
		# two-point catalogue does not produce incessant A→B→A shuttling.
		if _arrivals.size() >= 2 and _same_arrival(_arrivals[-2],id,point) and now-_last_arrival < REVISIT_SECONDS: continue
		if not _arrivals.is_empty() and _same_arrival(_arrivals[-1],id,point) and now-_last_arrival < REVISIT_SECONDS: continue
		var cell: Dictionary = _memory.get(_cell_key(point),{})
		var habituation := maxf(_habituation(target,now),_habituation(cell,now))
		var confidence := _number(candidate.get("confidence",0.65),0.65,0.0,1.0)
		var travel_cost := 0.7 * distance / (distance+300.0)
		var direction_bonus := _drive_bonus(point-position,drive)
		var score := 1.0 + confidence*0.25 - habituation*1.1 - travel_cost + direction_bonus
		var entry := {"target_id":id,"point":point,"score":score,"distance":distance,
			"novelty":1.0-habituation,"travel_cost":travel_cost,"drive_bonus":direction_bonus,
			"tie":_tie(id),"kind":str(candidate.get("kind","point"))}
		scores.append(entry)
		if best.is_empty() or score>float(best.score)+0.000001 or (absf(score-float(best.score))<=0.000001 and (int(entry.tie)<int(best.tie) or (int(entry.tie)==int(best.tie) and id<str(best.target_id)))):
			best = entry
	scores.sort_custom(func(a,b): return float(a.score)>float(b.score) if absf(float(a.score)-float(b.score))>0.000001 else (int(a.tie)<int(b.tie) or (int(a.tie)==int(b.tie) and str(a.target_id)<str(b.target_id))))
	if best.is_empty(): return _rest("no_fresh_reachable_target",scores)
	if float(best.score)<MIN_SCORE: return _rest("low_interest",scores)
	var result := {"target_id":best.target_id,"point":best.point,"reason":"explore_unvisited" if float(best.novelty)>0.85 else "revisit_recovered_interest","score":best.score,"scores":scores}
	diagnostics = {"decision":result.duplicate(true),"memory_entries":_memory.size(),"arrival_count":_arrivals.size(),"time":now}
	return result

## Engineered bilateral novelty signals for an external controller. This is a
## read-only projection of real candidate geometry/history, never a visit or a
## policy decision. Screen-left/right are explicit axes, not biological senses.
func sensory(candidates: Array, position: Vector2, now: float) -> Dictionary:
	var output := {"left":0.0,"right":0.0,"candidate_count":0,"mapping":"screen_x_novelty_v1"}
	if not position.is_finite() or not is_finite(now): return output
	now = maxf(now,_time)
	var anchor := _origin if _origin.is_finite() else position
	var seen := {}
	for candidate in candidates.slice(0,MAX_CANDIDATES):
		if not candidate is Dictionary: continue
		var id := str(candidate.get("id",""))
		var point: Variant = candidate.get("point",null)
		if id.is_empty() or id.length()>160 or seen.has(id) or not point is Vector2 or not point.is_finite(): continue
		seen[id] = true
		var offset: Vector2 = point-position
		if offset.length()<MIN_TRAVEL: continue
		var target: Dictionary = _target_entry(id,point)
		if float(target.get("blocked_until",-INF))>now: continue
		var relative: Vector2 = (point-anchor)/CELL_SIZE
		var cell: Dictionary = _memory.get("cell:%d:%d" % [floori(relative.x),floori(relative.y)],{})
		var novelty := 1.0-maxf(_habituation(target,now),_habituation(cell,now))
		var salience := novelty*_number(candidate.get("confidence",0.65),0.65,0.0,1.0)/(1.0+offset.length()/600.0)
		var horizontal := offset.normalized().x
		output.left = maxf(float(output.left),salience*(1.0-horizontal)*0.5)
		output.right = maxf(float(output.right),salience*(1.0+horizontal)*0.5)
		output.candidate_count += 1
	return output

func observe_arrival(id: String, point: Vector2, now: float, outcome: String) -> void:
	if id.is_empty() or id.length()>160 or not point.is_finite() or not is_finite(now): return
	_time = maxf(_time,now)
	now = _time
	if not _origin.is_finite(): _origin = point
	if outcome in ["arrived","completed"]:
		for key in ["target:"+id,_cell_key(point)]:
			var old: Dictionary = _target_entry(id,point) if key.begins_with("target:") else _memory.get(key,{})
			_store(key,{"updated":now,"visited":now,"point":point,"strength":minf(1.0,_habituation(old,now)+0.75)},now)
		_arrivals.append({"id":id,"point":point,"time":now})
		if _arrivals.size()>2: _arrivals.pop_front()
		_last_arrival = now
	elif outcome not in ["cancelled","superseded","preempted","interrupted","character_changed","disabled"]:
		var key := "target:"+id
		var entry: Dictionary = _target_entry(id,point).duplicate()
		var failures := mini(int(entry.get("failures",0))+1,4)
		entry.merge({"updated":now,"point":point,"failures":failures,"blocked_until":now+FAILURE_SECONDS*failures},true)
		_store(key,entry,now)
	diagnostics["memory_entries"] = _memory.size()
	diagnostics["last_outcome"] = {"target_id":id,"outcome":outcome,"time":now}

func _rest(reason: String, scores: Array) -> Dictionary:
	var result := {"target_id":"","reason":reason,"scores":scores}
	diagnostics = {"decision":result.duplicate(true),"memory_entries":_memory.size(),"arrival_count":_arrivals.size(),"time":_time}
	return result

func _target_entry(id: String, point: Vector2) -> Dictionary:
	var entry: Dictionary = _memory.get("target:"+id,{})
	var previous: Variant = entry.get("point",null)
	if not previous is Vector2 or previous.distance_to(point)>=CELL_SIZE*0.5: return {}
	return entry

func _same_arrival(arrival: Dictionary, id: String, point: Vector2) -> bool:
	return id == str(arrival.id) and Vector2(arrival.point).distance_to(point)<CELL_SIZE*0.5

func _cell_key(point: Vector2) -> String:
	var relative := (point-_origin)/CELL_SIZE
	return "cell:%d:%d" % [floori(relative.x),floori(relative.y)]

func _habituation(entry: Dictionary, now: float) -> float:
	if not entry.has("visited"): return 0.0
	return float(entry.get("strength",0.75))*exp(-maxf(0.0,now-float(entry.visited))/RECOVERY_SECONDS)

func _store(key: String, entry: Dictionary, _now: float) -> void:
	if not _memory.has(key) and _memory.size()>=MAX_MEMORY:
		var oldest := ""
		var stamp := INF
		for known in _memory:
			var updated := float(_memory[known].get("updated",-INF))
			if updated<stamp or (updated==stamp and (oldest.is_empty() or str(known)<oldest)):
				oldest = str(known)
				stamp = updated
		_memory.erase(oldest)
	_memory[key] = entry

func _tie(id: String) -> int:
	var value := seed & 0x7fffffff
	for byte in id.to_utf8_buffer(): value = (value*33+int(byte)) & 0x7fffffff
	return value

func _number(value: Variant, fallback: float, low: float, high: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)): return fallback
	return clampf(float(value),low,high)

func _drive_bonus(offset: Vector2, drive: Dictionary) -> float:
	var heading: Variant = drive.get("heading",Vector2.ZERO)
	if not heading is Vector2 or not heading.is_finite() or heading.length_squared()<0.0001: return 0.0
	var forward := _number(drive.get("forward",0.0),0.0,-1.0,1.0)
	var turn := _number(drive.get("turn",0.0),0.0,-1.0,1.0)
	var preferred: Vector2 = heading.normalized().rotated(turn*PI*0.5)
	if forward<0: preferred = -preferred
	return offset.normalized().dot(preferred)*0.25*maxf(absf(forward),absf(turn))
