extends RefCounted
## Positive evidence from explicit user placement only. The caller must never
## feed autonomous arrivals here. No screen content, negative inference, or
## reward from the policy's own choices. Coordinates are monitor-relative.
const MAX_EVENTS := 256
const MAX_CHARACTERS := 16
const MAX_FILE_BYTES := 131072
const HALF_LIFE_SECONDS := 2592000.0 # thirty days
const BANDWIDTH := 0.14
const MAX_BONUS := 0.25
const KINDS := ["window","taskbar","floor","surface","point","free","unknown"]
var _path := ""
var _events: Array[Dictionary] = []
var _save_error := ""
var _revision := 0

func configure(path: String = "user://placement-preferences.json") -> bool:
	_path = path
	_events.clear()
	_save_error = ""
	_revision = 0
	if path.is_empty() or not FileAccess.file_exists(path): return true
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: _save_error = "read_failed"; return false
	if file.get_length()>MAX_FILE_BYTES: file.close(); _save_error = "file_too_large"; return false
	var decoder := JSON.new()
	var error := decoder.parse(file.get_as_text())
	file.close()
	if error != OK or not decoder.data is Dictionary or decoder.data.get("version") != 1 or not decoder.data.get("events") is Array:
		_save_error = "invalid_document"
		return false
	var rows: Array = decoder.data.events
	if rows.size()>MAX_EVENTS or not rows.all(func(row): return _valid_event(row)):
		_save_error = "invalid_events"
		return false
	# Validate the character cap rather than silently discarding loaded history.
	var characters := {}
	for row in rows: characters[str(row.character)] = true
	if characters.size()>MAX_CHARACTERS: _save_error = "too_many_characters"; return false
	for row in rows: _events.append(_canonical(row))
	return true

func record_placement(character: String, point: Vector2, monitor: Rect2, surface_kind: String, now_unix: float) -> bool:
	if not _valid_character(character) or not _valid_context(point,monitor,now_unix) or surface_kind not in KINDS: return false
	var normalized := (point-monitor.position)/monitor.size
	var event := {"character":character,"x":normalized.x,"y":normalized.y,"surface_kind":surface_kind,"time":now_unix}
	_append(event)
	_revision += 1
	return _save()

## Pure read. Repeated scoring does not reinforce anything or write to disk.
func bonus(character: String, point: Vector2, monitor: Rect2, surface_kind: String, now_unix: float) -> float:
	if not _valid_character(character) or not _valid_context(point,monitor,now_unix) or surface_kind not in KINDS: return 0.0
	var normalized := (point-monitor.position)/monitor.size
	var evidence := 0.0
	for event in _events:
		if str(event.character)!=character: continue
		var age := maxf(0.0,now_unix-float(event.time))
		var recency := exp(-log(2.0)*age/HALF_LIFE_SECONDS)
		var distance_squared := normalized.distance_squared_to(Vector2(float(event.x),float(event.y)))
		var context := 1.0 if str(event.surface_kind)==surface_kind else 0.2
		evidence += exp(-distance_squared/(2.0*BANDWIDTH*BANDWIDTH))*recency*context
	return MAX_BONUS*(1.0-exp(-evidence/3.0))

## Replaying these normalized explicit events is the deterministic offline path.
## Invalid imports fail atomically; online and offline share the same eviction.
func rebuild(events: Array) -> bool:
	if events.size()>4096 or not events.all(func(row): return _valid_event(row)): return false
	_events.clear()
	for event in events: _append(_canonical(event))
	_revision += 1
	return _save()

func reset(character: String = "") -> bool:
	if not character.is_empty() and not _valid_character(character): return false
	if character.is_empty(): _events.clear()
	else: _events = _events.filter(func(event): return str(event.character)!=character)
	_revision += 1
	return _save()

func export_diagnostics() -> Dictionary:
	var counts := {}
	for event in _events:
		var character := str(event.character)
		counts[character] = int(counts.get(character,0))+1
	return {"version":1,"events":_events.duplicate(true),"event_count":_events.size(),"characters":counts,
		"revision":_revision,"save_error":_save_error,"learning_source":"explicit_user_placement_only",
		"mapping":"normalized_monitor_gaussian_recency_v1","max_bonus":MAX_BONUS}

func _append(event: Dictionary) -> void:
	var characters := {}
	for old in _events: characters[str(old.character)] = true
	if not characters.has(str(event.character)) and characters.size()>=MAX_CHARACTERS:
		# Evict the character with the oldest last recorded placement, not the
		# earliest first visit. Event order is the authoritative replay order.
		var recent := {}
		for i in _events.size(): recent[str(_events[i].character)] = i
		var oldest := str(_events[0].character)
		for id in recent:
			if int(recent[id])<int(recent[oldest]): oldest = str(id)
		_events = _events.filter(func(old): return str(old.character)!=oldest)
	_events.append(_canonical(event))
	while _events.size()>MAX_EVENTS: _events.pop_front()

func _valid_character(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>96: return false
	for i in value.length():
		if value.unicode_at(i)<32: return false
	return true

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_context(point: Vector2, monitor: Rect2, stamp: float) -> bool:
	return point.is_finite() and monitor.position.is_finite() and monitor.size.is_finite() and monitor.size.x>0 and monitor.size.y>0 and is_finite(stamp) and stamp>=0 and point.x>=monitor.position.x and point.y>=monitor.position.y and point.x<=monitor.end.x and point.y<=monitor.end.y

func _valid_event(value: Variant) -> bool:
	if not value is Dictionary or not _valid_character(value.get("character")): return false
	if not value.get("surface_kind") is String or value.surface_kind not in KINDS: return false
	for key in ["x","y","time"]:
		if not _finite_number(value.get(key)): return false
	return float(value.x)>=0 and float(value.x)<=1 and float(value.y)>=0 and float(value.y)<=1 and float(value.time)>=0

func _canonical(value: Dictionary) -> Dictionary:
	return {"character":str(value.character),"x":float(value.x),"y":float(value.y),"surface_kind":str(value.surface_kind),"time":float(value.time)}

func _save() -> bool:
	_save_error = ""
	if _path.is_empty(): return true # explicit in-memory mode for tests/imports
	var directory := _path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: _save_error = "directory_failed"; return false
	var temporary := _path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: _save_error = "write_failed"; return false
	file.store_string(JSON.stringify({"version":1,"events":_events}))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK: DirAccess.remove_absolute(temporary); _save_error = "write_failed"; return false
	# Same-directory rename atomically replaces the prior complete document.
	if DirAccess.rename_absolute(temporary,_path)!=OK:
		DirAccess.remove_absolute(temporary)
		_save_error = "replace_failed"
		return false
	return true
