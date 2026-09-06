class_name BackendClient
extends Node
## WebSocket (JSON events) + HTTP (catalog / motions / avatar download) client
## for the companion engine. Avatar downloads are "latest only": a newer request
## invalidates the result of any older in-flight download.

signal connected
signal disconnected(reason: String)
signal connection_state_changed(state: String) # connecting | open | closed
signal event_received(event: Dictionary)
signal characters_loaded(ok: bool, characters: Array, message: String)
signal motions_loaded(ok: bool, bank: MotionBank, message: String)
signal avatar_ready(ok: bool, character_id: String, path: String, message: String)
signal motion_saved(ok: bool, motion_id: String, message: String)
signal health_checked(ok: bool, message: String)
## GET /motion-assets catalog (VRMA clips). ok=false covers "endpoint missing" (404) too: the
## host then keeps the built-in Euler bank only.
signal motion_assets_loaded(ok: bool, entries: Array[Dictionary], message: String)
## One VRMA clip cached (or reused) under user://motions with its sha256 verified.
signal motion_asset_ready(ok: bool, name: String, path: String, message: String)

const AVATAR_CACHE_DIR := "user://avatars"
const MOTION_CACHE_DIR := "user://motions"
const SettingsScript := preload("res://scripts/settings.gd") # static helpers; works without the autoload (-s tools)
const RECONNECT_MIN := 1.0
const RECONNECT_MAX := 6.0

var base_url: String = ""
var ws_url: String = ""
var state: String = "closed"
var last_error: String = ""
var sent_count := 0
var received_count := 0

var _ws := WebSocketPeer.new()
var _reconnect_in := 0.0
var _backoff := RECONNECT_MIN
var _want_connection := false
var _avatar_generation := 0
var _avatar_inflight: Dictionary = {} # generation -> HTTPRequest
var _motion_generation := 0


func configure(url: String) -> void:
	base_url = url.trim_suffix("/")
	ws_url = SettingsScript.ws_url_for(base_url)


func connect_ws() -> void:
	_want_connection = true
	_open()


func disconnect_ws() -> void:
	_want_connection = false
	if state != "closed":
		_ws.close(1000, "client closing")


func _open() -> void:
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 8 * 1024 * 1024
	_ws.outbound_buffer_size = 4 * 1024 * 1024
	_ws.max_queued_packets = 4096
	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		last_error = "connect error: " + error_string(err)
		_schedule_reconnect()
		return
	_set_state("connecting")


func _schedule_reconnect() -> void:
	_set_state("closed")
	_reconnect_in = _backoff
	_backoff = minf(_backoff * 1.7, RECONNECT_MAX)


func send(message: Dictionary) -> bool:
	if state != "open":
		return false
	var err := _ws.send_text(JSON.stringify(message))
	if err != OK:
		last_error = "send error: " + error_string(err)
		return false
	sent_count += 1
	return true


func _process(delta: float) -> void:
	if state == "closed":
		if _want_connection:
			_reconnect_in -= delta
			if _reconnect_in <= 0.0:
				_open()
		return
	_ws.poll()
	var ws_state := _ws.get_ready_state()
	match ws_state:
		WebSocketPeer.STATE_OPEN:
			if state != "open":
				_backoff = RECONNECT_MIN
				_set_state("open")
				connected.emit()
			while _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				var text := packet.get_string_from_utf8()
				var json := JSON.new()
				if json.parse(text) == OK and typeof(json.data) == TYPE_DICTIONARY:
					received_count += 1
					event_received.emit(json.data)
				else:
					push_warning("non-JSON ws packet ignored (%d bytes)" % packet.size())
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			var reason := _ws.get_close_reason()
			var was_open := state == "open"
			_schedule_reconnect()
			if was_open or code != -1:
				disconnected.emit("%d %s" % [code, reason])
			else:
				disconnected.emit("unreachable")
		_:
			pass


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	connection_state_changed.emit(s)


# ---------------------------------------------------------------- HTTP helpers

func _request(path: String, method: HTTPClient.Method, body: String, callback: Callable, download_to: String = "") -> void:
	var req := HTTPRequest.new()
	req.timeout = 30.0 if download_to.is_empty() else 300.0
	if not download_to.is_empty():
		req.download_file = download_to
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		req.queue_free()
		callback.call(result, code, data)
	)
	var headers := PackedStringArray(["Accept: application/json"])
	if not body.is_empty():
		headers.append("Content-Type: application/json")
	var err := req.request(base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		callback.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray())


static func _parse_json(data: PackedByteArray) -> Variant:
	var json := JSON.new()
	if json.parse(data.get_string_from_utf8()) != OK:
		return null
	return json.data


func check_health() -> void:
	_request("/health", HTTPClient.METHOD_GET, "", func(result: int, code: int, data: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			health_checked.emit(false, "health %d (%d)" % [code, result])
			return
		health_checked.emit(true, data.get_string_from_utf8().left(200))
	)


func fetch_characters() -> void:
	_request("/characters", HTTPClient.METHOD_GET, "", func(result: int, code: int, data: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			characters_loaded.emit(false, [], "GET /characters failed (%d/%d)" % [result, code])
			return
		var parsed = _parse_json(data)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("characters")) != TYPE_ARRAY:
			characters_loaded.emit(false, [], "GET /characters: invalid shape")
			return
		characters_loaded.emit(true, parsed["characters"], "ok")
	)


func fetch_motions() -> void:
	_request("/motions", HTTPClient.METHOD_GET, "", func(result: int, code: int, data: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			motions_loaded.emit(false, null, "GET /motions failed (%d/%d)" % [result, code])
			return
		var parsed = _parse_json(data)
		var bank := MotionBank.parse(parsed)
		var msg := "ok (%d motions)" % bank.motions.size()
		if not bank.errors.is_empty():
			msg += "; skipped: " + "; ".join(bank.errors)
		motions_loaded.emit(true, bank, msg)
	)


func save_motion(motion: Dictionary) -> void:
	var id := str(motion.get("name", ""))
	_request("/motions/" + id.uri_encode(), HTTPClient.METHOD_PUT, JSON.stringify(motion), func(result: int, code: int, data: PackedByteArray) -> void:
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			var detail := data.get_string_from_utf8().left(300)
			motion_saved.emit(false, id, "PUT /motions/%s failed (%d/%d) %s" % [id, result, code, detail])
			return
		motion_saved.emit(true, id, "saved")
	)


static func avatar_cache_path(character_id: String) -> String:
	return AVATAR_CACHE_DIR.path_join(character_id.validate_filename() + ".vrm")


# ---------------------------------------------------------------- VRMA motion assets

## Fetch the VRMA catalog. A 404 (older backend without /motion-assets) or a connection failure
## is reported as ok=false with a message; nothing else happens (built-in bank keeps working).
func fetch_motion_assets() -> void:
	_request("/motion-assets", HTTPClient.METHOD_GET, "", func(result: int, code: int, data: PackedByteArray) -> void:
		var empty: Array[Dictionary] = []
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			motion_assets_loaded.emit(false, empty, "GET /motion-assets unavailable (%d/%d)" % [result, code])
			return
		var errors: Array[String] = []
		var entries := MotionBank.parse_asset_catalog(_parse_json(data), errors)
		var msg := "ok (%d clips)" % entries.size()
		if not errors.is_empty():
			msg += "; skipped: " + "; ".join(errors)
		motion_assets_loaded.emit(true, entries, msg)
	)


static func motion_cache_path(name: String) -> String:
	return MOTION_CACHE_DIR.path_join(name.validate_filename() + ".vrma")


## True when the file exists and its SHA-256 equals [sha256] (case-insensitive hex).
static func verify_file_sha256(path: String, sha256: String) -> bool:
	if not MotionBank.is_sha256_hex(sha256) or not FileAccess.file_exists(path):
		return false
	return FileAccess.get_sha256(path).to_lower() == sha256.to_lower()


## Download (or reuse) one catalog entry. The cached file is reused only when its checksum
## matches the catalog; a mismatch (replaced/corrupt file) re-downloads. A downloaded file whose
## checksum differs from the catalog is deleted and reported as failed: unverified clips never
## reach MotionPlayer.
func fetch_motion_asset(entry: Dictionary, force: bool = false) -> void:
	var name := str(entry.get("name", ""))
	var sha := str(entry.get("sha256", "")).to_lower()
	if name.is_empty() or not MotionBank.is_sha256_hex(sha):
		motion_asset_ready.emit(false, name, "", "invalid catalog entry")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MOTION_CACHE_DIR))
	var cache := motion_cache_path(name)
	if not force and verify_file_sha256(cache, sha):
		motion_asset_ready.emit(true, name, cache, "cached")
		return
	var path := str(entry.get("asset_url", "/motion-assets/" + name))
	if path.begins_with("http://") or path.begins_with("https://"):
		if path.begins_with(base_url):
			path = path.substr(base_url.length())
	# Unique temp per request: a refresh while a clip is still downloading must not share a file.
	_motion_generation += 1
	var temp := cache + ".part%d" % _motion_generation
	_request(path, HTTPClient.METHOD_GET, "", func(result: int, code: int, _data: PackedByteArray) -> void:
		var abs_temp := ProjectSettings.globalize_path(temp)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			DirAccess.remove_absolute(abs_temp)
			motion_asset_ready.emit(false, name, "", "motion asset %s download failed (%d/%d)" % [name, result, code])
			return
		if not verify_file_sha256(temp, sha):
			DirAccess.remove_absolute(abs_temp)
			motion_asset_ready.emit(false, name, "", "motion asset %s sha256 mismatch; discarded" % name)
			return
		var abs_cache := ProjectSettings.globalize_path(cache)
		if FileAccess.file_exists(abs_cache):
			DirAccess.remove_absolute(abs_cache)
		var err := DirAccess.rename_absolute(abs_temp, abs_cache)
		if err != OK:
			motion_asset_ready.emit(false, name, "", "motion cache write failed: " + error_string(err))
			return
		motion_asset_ready.emit(true, name, cache, "downloaded")
	, temp)


## Download (or reuse cached) VRM for [character_id]. Only the latest request reports back.
func fetch_avatar(character_id: String, avatar_url: String, force: bool = false) -> void:
	_avatar_generation += 1
	var generation := _avatar_generation
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AVATAR_CACHE_DIR))
	var cache := avatar_cache_path(character_id)
	if not force and FileAccess.file_exists(cache) and FileAccess.open(cache, FileAccess.READ).get_length() > 1024:
		avatar_ready.emit(true, character_id, cache, "cached")
		return
	var path := avatar_url if not avatar_url.is_empty() else "/characters/%s/avatar" % character_id
	if path.begins_with("http://") or path.begins_with("https://"):
		# Absolute URL supplied by the catalog; strip our base if it matches.
		if path.begins_with(base_url):
			path = path.substr(base_url.length())
	var temp := cache + ".part%d" % generation
	_request(path, HTTPClient.METHOD_GET, "", func(result: int, code: int, _data: PackedByteArray) -> void:
		_avatar_inflight.erase(generation)
		if generation != _avatar_generation:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
			return # superseded by a newer request: discard silently
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
			avatar_ready.emit(false, character_id, "", "avatar download failed (%d/%d)" % [result, code])
			return
		var abs_temp := ProjectSettings.globalize_path(temp)
		var abs_cache := ProjectSettings.globalize_path(cache)
		if FileAccess.file_exists(abs_cache):
			DirAccess.remove_absolute(abs_cache)
		var err := DirAccess.rename_absolute(abs_temp, abs_cache)
		if err != OK:
			avatar_ready.emit(false, character_id, "", "cache write failed: " + error_string(err))
			return
		avatar_ready.emit(true, character_id, cache, "downloaded")
	, temp)
