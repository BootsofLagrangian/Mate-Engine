class_name DesktopObjectsHost
extends Node
## Local furniture, geometry sockets and finite pose interactions. No screen-content read,
## keyboard/mouse injection, arbitrary files, or model calls are performed here.
signal changed
signal command_finished(id: String, outcome: String)
signal status_changed(message: String)
signal interaction_finished(id: String, verb: String, outcome: String)
const SceneSolids = preload("desktop_scene_solids.gd")
const Appearance = preload("desktop_object_appearance.gd")
const Store = preload("desktop_object_store.gd")
const ContactScene = preload("desktop_object_contact_scene.gd")
const FurnitureWindow = preload("desktop_object_window.gd")
var host
var store := Store.new()
var edit_enabled := false
var windows: Dictionary = {}
var _settings: Node
var _clock := 0.0
var _refresh_at := 0.0
var _interaction: Dictionary = {}
var _closed := false
var _last_character := ""
var _screen_provider := Callable()
var _published_ids: Dictionary = {}
var last_status := ""
var _contact_scene: ContactScene
var _contact_id := ""
var _contact_floor := Vector2.ZERO
var _contact_scale := 1.0
var _contact_reframe := Vector2i.ZERO
var _presentation: Dictionary = {}
var fit_diagnostics: Dictionary = {}
var _pending_command: Dictionary = {}
var _command_seen: Dictionary = {}
var _view_zoom := 1.0
var command_outcomes: Array[Dictionary] = []

func configure(app) -> void:
	host = app
	_view_zoom = float(host._view_settings.get("view_zoom",1.0))
	host.autonomy.frame_moved.connect(_on_frame_moved)
	_settings = get_node("/root/Settings")
	store.set_data(_settings.get_value("desktop_objects",{}))
	_last_character = str(host.session.character_id)
	if host.panel.has_method("bind_desktop_objects"): host.panel.bind_desktop_objects(self)
	if host.living != null:
		host.living.director.intent_outcome.connect(_intent_outcome)
		command_finished.connect(host.living.object_command_result)
	_sync_windows()

func catalogue() -> Array:
	return Store.catalogue()

func screen_rects() -> Array:
	if _screen_provider.is_valid(): return _screen_provider.call()
	var screens: Array = []
	for i in DisplayServer.get_screen_count(): screens.append(DisplayServer.screen_get_usable_rect(i))
	return screens

func native_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS) and is_inside_tree() and not get_tree().root.gui_embed_subwindows

func rows() -> Array:
	var result := store.rows(screen_rects())
	for row in result:
		if row.status == "ready" and not native_available():
			row.status_text = "데스크톱 창이 필요합니다"
		elif windows.has(row.id) and not windows[row.id].loaded:
			row.status_text = windows[row.id].error
		if not _interaction.is_empty() and _interaction.id == row.id:
			row.status_text = "상호작용 중" if _interaction.stage in ["seated","using"] else "자리를 준비하는 중"
	return result

func add_object(type: String) -> String:
	if _closed or host == null: return ""
	var size := Store.base_size(type)
	var origin := Vector2i(Vector2(host.get_window().position)+host.pet_rect.get_center())-size/2
	var id: String = store.add_object(type,origin,screen_rects())
	if id.is_empty(): _status("물건을 둘 공간이 없거나 개수 제한에 도달했습니다"); return ""
	# Furniture and the pet share physical pixels/metre. Seat admission uses the
	# canonical seated geometry; never inflate a chair to fit standing leg bounds.
	var sizing_window := FurnitureWindow.new()
	add_child(sizing_window)
	var sizing_ok := sizing_window.configure(store.get_object(id),size)
	sizing_window.set_view_basis(host.camera.global_basis)
	# A just-created native HWND may not yet have a drawable viewport. Its
	# authored reference scale is deterministic; camera.unproject_position is not
	# a valid sizing measurement before the first native frame.
	var source_ppm := sizing_window._reference_ppm if sizing_ok else 0.0
	fit_diagnostics["last_creation"]={"type":type,"model_loaded":sizing_ok,"model_error":sizing_window.error,"reference_ppm":source_ppm,"reason":"sizing"}
	sizing_window.free()
	if source_ppm <= 1.0:
		fit_diagnostics.last_creation.reason="model_sizing_failed"
		store.remove_object(id)
		_status("물건 모델을 준비하지 못했습니다")
		return ""
	var physical_ppm: float = host._px_per_m*host._pet_scale/maxf(_view_zoom,.01)
	var default_scale := clampf(physical_ppm/source_ppm,0.5,1.8)
	fit_diagnostics[id] = {"physical_ppm":physical_ppm,"applied_ratio":1.0,"seat_floor_adaptation":true}

	if not store.resize_object(id,default_scale,screen_rects()):
		fit_diagnostics.last_creation.reason="legacy_size_does_not_fit"
		store.remove_object(id)
		_status("물건을 안전한 크기로 둘 공간이 없습니다")
		return ""
	var record: Dictionary = store.get_object(id)
	var dimensions: Vector2i = store.rect_for(record).size
	var foot: Vector2 = Vector2(host.get_window().position)+Vector2(host._projected_anchors().get("foot",host.pet_rect.get_center()))
	var floor_y := foot.y
	var contact: Dictionary = host.autonomy.get_support_contact()
	if contact.get("attached",false): floor_y = Vector2(contact.screen_point).y
	else:
		for area in screen_rects():
			if Rect2(area).has_point(foot): floor_y = Rect2(area).end.y; break
	store.move_object(id,Vector2i(roundi(foot.x-dimensions.x*0.5),roundi(floor_y-dimensions.y)),screen_rects())
	if _spatial_enabled():
		var world_foot:Vector3=host.avatar.contact_anchors().foot
		store.set_spatial_unit_scale(id,host._pet_scale/maxf(default_scale,.001))
		store.set_position_m(id,world_foot)
	fit_diagnostics.last_creation.reason="created"
	_after_change()
	set_edit_enabled(true)
	_status("물건을 끌어 놓고 크기를 맞춰 주세요. 좌석 접촉은 미리보기입니다")
	return id

## Model commands are queued while a response is speaking. No model call is made here.
func furniture_types() -> Array:
	return ["chair", "sofa", "computer"] if native_available() and not _closed else []

func furniture_catalog() -> Array:
	var result: Array = []
	for item in catalogue():
		if item.type not in furniture_types(): continue
		var verbs: Array = ["place","configure","appearance","hide","remove"]
		verbs.append_array(item.verbs)
		result.append({"version":1,"spatial":{"frame":"desktop_scene_v1","bounds":{"x":[-20.0,20.0],"y":[-20.0,20.0],"z":[-20.0,20.0]}},"perception":{"mode":"geometry_only","available":true,"reason":"native_geometry","reachable":"unknown"},"id":item.type,"verbs":verbs,"sockets":["seat","keyboard_left","keyboard_right","inspect"] if item.type == "computer" else ["seat","inspect"],"appearances":Store.APPEARANCES.duplicate(),"bounds":{"scale":[.5,1.8],"yaw_deg":[-180.0,180.0]}})
		if not _spatial_enabled(): result.back().erase("spatial")
	return result

func configure_object(id: String, yaw_deg: float, appearance: String) -> bool:
	var previous: Dictionary = store.data()
	if not store.configure_object(id,yaw_deg,appearance): return false
	if not _validate_configured_projection(id,previous): return false
	cancel_interaction("object_configured")
	_after_change()
	return true

func request_intent(intent: Dictionary, source: String, command_id: String) -> Dictionary:
	if _closed or host == null or host.living == null or not host.living.enabled:
		return {"accepted":false,"reason":"disabled"}
	if source not in ["user","llm"] or intent.get("kind","") != "furniture": return {"accepted":false,"reason":"invalid_intent"}
	for key in intent:
		if key not in ["kind","object_type","verb","target_id","placement","scale","yaw_deg","appearance","position_m"]: return {"accepted":false,"reason":"invalid_intent"}
	if command_id.is_empty() or command_id.length() > 160: return {"accepted":false,"reason":"invalid_id"}
	if _command_seen.has(command_id): return {"accepted":false,"reason":"duplicate"}
	var type := str(intent.get("object_type",""))
	var verb := str(intent.get("verb",""))
	var placement := str(intent.get("placement","near"))
	if type not in furniture_types() or verb not in ["place","configure","appearance","sit","use","inspect","hide","remove"] or placement not in ["near","left","right"]:
		return {"accepted":false,"reason":"invalid_intent"}
	if verb == "configure" and not (intent.has("scale") or intent.has("yaw_deg") or intent.has("appearance") or intent.has("position_m")): return {"accepted":false,"reason":"missing_configuration"}
	if verb == "appearance" and not intent.has("appearance"): return {"accepted":false,"reason":"missing_appearance"}
	if verb in ["configure","appearance"] and intent.has("placement"): return {"accepted":false,"reason":"unexpected_placement"}
	if verb in ["hide","remove"] and (intent.has("scale") or intent.has("yaw_deg") or intent.has("appearance")): return {"accepted":false,"reason":"unexpected_configuration"}
	if (verb == "sit" and type == "computer") or (verb == "use" and type != "computer"):
		return {"accepted":false,"reason":"unsupported_verb"}
	if intent.has("scale") and (typeof(intent.scale) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(intent.scale)) or float(intent.scale) < .5 or float(intent.scale) > 1.8):
		return {"accepted":false,"reason":"invalid_scale"}
	if intent.has("position_m") and (verb not in ["place","configure"] or not _spatial_enabled() or intent.has("placement") or not Store.valid_position_m(intent.position_m)): return {"accepted":false,"reason":"invalid_position"}
	if intent.has("yaw_deg") and (not Store._number(intent.yaw_deg) or absf(float(intent.yaw_deg)) > 180.0): return {"accepted":false,"reason":"invalid_yaw"}
	if intent.has("appearance") and intent.appearance not in Store.APPEARANCES: return {"accepted":false,"reason":"invalid_appearance"}
	var target := str(intent.get("target_id",""))
	if target.is_empty() and verb in ["hide","remove","configure","appearance"]: return {"accepted":false,"reason":"target_required"}
	if not target.is_empty():
		if not target.begins_with("object:"): return {"accepted":false,"reason":"unknown_target"}
		var record: Dictionary = store.get_object(target.trim_prefix("object:"))
		if record.is_empty() or record.type != type: return {"accepted":false,"reason":"unknown_target"}
	if source == "llm" and (host.living.director.has_user_intent() or (not _pending_command.is_empty() and _pending_command.source == "user") or (not _interaction.is_empty() and _interaction.get("source","user") == "user")):
		return {"accepted":false,"reason":"user_priority"}
	cancel_commands("superseded")
	_pending_command = {"id":command_id,"intent":intent.duplicate(true),"source":source,"expires":_clock+30.0,"character":str(host.session.character_id)}
	_command_seen[command_id] = _clock
	while _command_seen.size() > 128: _command_seen.erase(_command_seen.keys()[0])
	return {"accepted":true,"reason":"queued"}

func _command_outcome(id: String, outcome: String) -> void:
	command_outcomes.append({"id":id,"outcome":outcome,"time":_clock})
	if command_outcomes.size() > 64: command_outcomes.pop_front()
	command_finished.emit(id,outcome)
	if outcome == "expired": _status("오래된 물건 요청을 정리했습니다")
	elif outcome in ["unknown_target","unavailable","no_space","unsafe_size","invalid_configuration"]: _status("지금은 요청한 물건 동작을 안전하게 진행할 수 없습니다")

func cancel_commands(reason: String = "cancelled", id: String = "") -> void:
	if not _pending_command.is_empty() and (id.is_empty() or _pending_command.id == id):
		var previous := str(_pending_command.id)
		_pending_command.clear()
		_command_outcome(previous,reason)
	if not _interaction.is_empty() and _interaction.has("command_id") and (id.is_empty() or _interaction.command_id == id):
		cancel_interaction(reason)

func _tick_command() -> void:
	if _pending_command.is_empty(): return
	if _pending_command.character != str(host.session.character_id): cancel_commands("character_changed"); return
	if _clock >= float(_pending_command.expires): cancel_commands("expired"); return
	if _pending_command.source == "llm" and host.living.director.has_user_intent(): cancel_commands("user_priority"); return
	if not host.living.enabled or not host.autonomy.enabled or not host.autonomy.surface_mode: cancel_commands("disabled"); return
	if host._drag_active or is_dragging(): cancel_commands("dragged"); return
	var job_active: bool = not host.session.job.is_empty() and str(host.session.job.get("status","")) not in ["done","failed","cancelled","completed"]
	if job_active or host.mic.is_recording() or host.motion._preview or host.motion._custom_motion or ((host.audio.voice_active or host.session.is_foreground_busy() or host.bridge.dialogue_holding(host._now())) and not _owns_command_speech(_pending_command)): return
	var command := _pending_command.duplicate(true)
	_pending_command.clear() # callbacks below can cancel/re-enter without losing this dispatch
	_execute_command(command)

func _place_command_object(id: String, placement: String) -> bool:
	var record: Dictionary = store.get_object(id)
	if record.is_empty(): return false
	if _spatial_enabled():
		var foot_world:Vector3=host.avatar.contact_anchors().foot
		var side:Vector3=host.spatial_camera().global_basis.x
		side.y=0
		if side.length_squared()<.000001:return false
		side=side.normalized()*(-1.0 if placement=="left" else 1.0)
		var distance_m:float=(.7 if placement=="near" else 1.0)*host._pet_scale
		return configure_spatial_position(id,foot_world+side*distance_m)
	var dimensions: Vector2i = store.rect_for(record).size
	var foot: Vector2 = Vector2(host.get_window().position)+Vector2(host._projected_anchors().get("foot",host.pet_rect.get_center()))
	var floor_y := foot.y
	var contact: Dictionary = host.autonomy.get_support_contact()
	if contact.get("attached",false): floor_y = Vector2(contact.screen_point).y
	else:
		for area in screen_rects():
			if Rect2(area).has_point(foot): floor_y = Rect2(area).end.y; break
	var side := -1.0 if placement == "left" else 1.0
	var distance := maxf(100.0,dimensions.x*.55) if placement != "near" else 100.0
	return move_object(id,Vector2i(roundi(foot.x+side*distance-dimensions.x*.5),roundi(floor_y-dimensions.y)))

func _execute_command(command: Dictionary) -> void:
	var intent: Dictionary = command.intent
	var id := str(intent.get("target_id","")).trim_prefix("object:")
	var verb := str(intent.verb)
	if not id.is_empty() and (not store.has_object(id) or store.get_object(id).type != intent.object_type):
		_command_outcome(command.id,"unknown_target"); return
	if id.is_empty():
		for row in store.rows(screen_rects()):
			if row.type == intent.object_type: id = row.id; break
	if id.is_empty(): id = add_object(str(intent.object_type))
	if id.is_empty(): _command_outcome(command.id,"no_space"); return
	if verb in ["hide","remove"]:
		var ok := set_object_visible(id,false) if verb == "hide" else remove_object(id)
		_command_outcome(command.id,"completed" if ok else "unknown_target"); return
	set_object_visible(id,true)
	if intent.has("scale") and not resize_object(id,float(intent.scale)):
		_command_outcome(command.id,"unsafe_size"); return
	var record: Dictionary = store.get_object(id)
	if intent.has("yaw_deg") or intent.has("appearance"):
		if not configure_object(id,float(intent.get("yaw_deg",record.get("yaw_deg",0.0))),str(intent.get("appearance",record.get("appearance","default")))):
			_command_outcome(command.id,"invalid_configuration"); return
	if intent.has("position_m"):
		var xyz: Dictionary = intent.position_m
		if not configure_spatial_position(id,Vector3(float(xyz.x),float(xyz.y),float(xyz.z))):
			_command_outcome(command.id,"invalid_position"); return
	if verb in ["configure","appearance"]:
		_command_outcome(command.id,"completed"); return
	if not intent.has("position_m") and not _place_command_object(id,str(intent.get("placement","near"))):
		_command_outcome(command.id,"no_space"); return
	set_edit_enabled(false)
	if verb == "place":
		_command_outcome(command.id,"completed"); _status("물건을 화면 안에 놓았습니다"); return
	if verb == "inspect":
		_refresh_adapters()
		var inspected: Dictionary = host.living.request_intent({"kind":"inspect","target_id":"object:"+id},str(command.source),str(command.id))
		if not inspected.get("accepted",false): _command_outcome(command.id,"unavailable")
		return
	var result := interact(id,verb)
	if not result.get("accepted",false): _command_outcome(command.id,"unavailable"); return
	_interaction.command_id = command.id
	_interaction.source = command.source

func rename_object(id: String, label: String) -> bool:
	if not store.rename_object(id,label): return false
	_after_change(); return true

func move_object(id: String, point: Vector2i) -> bool:
	if _spatial_enabled() and windows.has(id):
		var record: Dictionary = store.get_object(id)
		if Store.valid_position_m(record.get("position_m")):
			var legacy := store.rect_for(record)
			var pixel := Vector2(point)+Vector2(legacy.size.x*.5,legacy.size.y-1.0)
			var distance := DesktopView.depth(host.spatial_camera(),_spatial_transform(record).origin)
			var world := DesktopView.screen_to_world_at_depth(host.spatial_camera(),pixel-host.spatial_desktop_origin(),distance)
			if not configure_spatial_position(id,world): return false
			store.move_object(id,point,screen_rects())
			_after_change()
			return true
	cancel_interaction("object_moved")
	if not store.move_object(id,point,screen_rects()): _sync_windows(); return false
	_after_change(); return true

func resize_object(id: String, scale: float) -> bool:
	var previous: Dictionary = store.data()
	if not store.resize_object(id,scale,screen_rects()): _status("그 크기로는 화면 안에 놓을 수 없습니다"); return false
	if not _validate_configured_projection(id,previous): return false
	cancel_interaction("object_resized")
	_after_change(); return true

## Geometry edits are transactional: never report a hidden/uncroppable spatial object as configured.
func _validate_configured_projection(id: String, previous: Dictionary) -> bool:
	if not _spatial_enabled(): return true
	if windows.has(id):
		var candidate: Dictionary = store.get_object(id)
		windows[id].apply_record(candidate,store.rect_for(candidate).size)
		if _sync_spatial_window(id): return true
	store.set_data(previous)
	if windows.has(id):
		var restored: Dictionary = store.get_object(id)
		windows[id].apply_record(restored,store.rect_for(restored).size)
		_sync_spatial_window(id)
	return false

func remove_object(id: String) -> bool:
	if not _interaction.is_empty() and _interaction.id == id: cancel_interaction("object_removed")
	if not store.remove_object(id): return false
	_after_change(); return true

func set_object_visible(id: String, value: bool) -> bool:
	if not value and not _interaction.is_empty() and _interaction.id == id: cancel_interaction("object_hidden")
	if not store.set_object_visible(id,value): return false
	_after_change(); return true

func set_edit_enabled(value: bool) -> void:
	if edit_enabled == value: return
	if value: cancel_interaction("editing")
	edit_enabled = value
	for window in windows.values(): window.set_editable(value)
	changed.emit()

func is_dragging() -> bool:
	for window in windows.values():
		if window.dragging: return true
	return false

func blocks_roaming() -> bool:
	return not _interaction.is_empty() and _interaction.stage in ["scene_approaching","facing","pose_wait","entering","exiting","using"]

func object_catalog() -> Array:
	var result: Array = []
	for row in rows():
		var item := {"id":row.id,"type":row.type,"label":row.label,"verbs":row.verbs,"status":row.status,"sockets":{}}
		if windows.has(row.id): item.sockets = windows[row.id].socket_catalogue()
		result.append(item)
	return result

## Future tools may attach their own definition/socket handler here; no handheld
## rendering or real application automation is claimed by this first furniture slice.
func tool_socket_contract() -> Dictionary:
	return {"version":1,"supported_verbs":["inspect","sit","use"],"future_verbs":["hold","tool"],"coordinate_space":"godot_desktop_pixels","content_reading":false}

func interact(id: String, verb: String) -> Dictionary:
	var record: Dictionary = store.get_object(id)
	if _closed or record.is_empty(): return _reject("물건이 없습니다")
	if not native_available() or not windows.has(id) or not windows[id].loaded or not bool(record.visible): return _reject("보이는 데스크톱 물건이 필요합니다")
	var verbs: Array = []
	for item in catalogue():
		if item.type == record.type: verbs = item.verbs
	if verb not in verbs: return _reject("아직 지원하지 않는 동작입니다")
	if host.living == null or not host.living.enabled: return _reject("스스로 행동하기를 켜 주세요")
	cancel_interaction("superseded")
	set_edit_enabled(false)
	_refresh_adapters()
	if verb == "inspect":
		var inspected: Dictionary = host.living.request_intent({"kind":"inspect","target_id":"object:"+id},"user")
		if inspected.get("accepted",false): host._set_panel_open(false); _status("물건을 잠깐 바라봅니다")
		return inspected
	if not host.autonomy.enabled or not host.autonomy.surface_mode: return _reject("표면 산책을 켜고 먼저 설 자리를 잡아 주세요")
	if host.is_sitting(): host._stand_up("")
	host.living.cancel("object_interaction")
	_interaction = {"id":id,"verb":verb,"stage":"waiting","expires":_clock+65.0,"character":host.session.character_id}
	host._set_panel_open(false)
	_status("대화가 끝나고 자리가 안정되면 물건 쪽으로 갑니다")
	changed.emit()
	return {"accepted":true,"reason":"queued"}

func cancel_interaction(reason: String = "cancelled") -> void:
	if reason == "completed" and _interaction.get("stage","") == "using" and request_stand(): return
	if not _pending_command.is_empty():
		var pending_id := str(_pending_command.id)
		_pending_command.clear()
		_command_outcome(pending_id,reason)
	if _interaction.is_empty(): return
	var previous := _interaction.duplicate()
	if not _presentation.is_empty():
		var foot: Vector3 = host.avatar.contact_anchors().foot-presentation_offset()
		if _presentation.kind == "exit": foot += Vector3(_presentation.world_delta)
		host._pivot_kind = "foot"
		host._pivot_px = host.camera.unproject_position(foot)
		host._pivot_px_target = host._pivot_px
		host._camera_pivot_depth = DesktopView.depth(host.camera,foot)
		_presentation.clear()
		host.motion.cancel_seated_transition()
		host._update_avatar_transform(0.0)
		host._update_pet_rect()
	_interaction.clear() # clear before host callbacks can re-enter
	if host != null and host.has_method("cancel_scene_approach"): host.cancel_scene_approach(reason)
	if host != null:
		_release_contact_scene()
		if host.living != null and previous.has("request_id"):
			host.living.director.cancel_intent(str(previous.request_id),reason)
		host.autonomy.cancel_target(reason)
		if previous.stage in ["pose_wait","entering","exiting","seating","seated","using"] and host.is_sitting(): host._stand_up("")
		if previous.stage == "facing": host.motion.cancel_heading()
		if previous.stage == "using": host.motion.set_ambient_state("rest",0.0)
	if previous.has("command_id"): _command_outcome(str(previous.command_id),reason)
	interaction_finished.emit(str(previous.id),str(previous.verb),reason)
	changed.emit()

func tick(delta: float) -> void:
	if _closed or host == null: return
	_clock += maxf(delta,0.0)
	_update_contact_transform()
	if str(host.session.character_id) != _last_character:
		cancel_interaction("character_changed")
		_last_character = str(host.session.character_id)
	if contact_scene_active():
		_refresh_adapters()
	if _clock >= _refresh_at:
		_sync_windows()
		_refresh_adapters()
		_refresh_at = _clock+0.5
	_tick_command()
	if _interaction.is_empty(): return
	if host.living == null or not host.living.enabled or not host.autonomy.enabled or not host.autonomy.surface_mode:
		cancel_interaction("disabled"); return
	if host._drag_active:
		cancel_interaction("pet_dragged"); return
	var id := str(_interaction.id)
	if not store.has_object(id) or not windows.has(id) or (not windows[id].visible and id != _contact_id) or is_dragging(): cancel_interaction("object_unavailable"); return
	if _clock >= float(_interaction.expires) and _interaction.stage != "seated": cancel_interaction("expired"); _status("상호작용 요청 시간이 지나 멈췄습니다"); return
	if host.panel_open and _interaction.stage not in ["seated","using","exiting"]:
		cancel_interaction("panel_open"); return
	var job_active: bool = not host.session.job.is_empty() and str(host.session.job.get("status","")) not in ["done","failed","cancelled","completed"]
	var busy: bool = job_active or host.mic.is_recording() or host._drag_active or host.motion._preview or host.motion._custom_motion or ((host.audio.voice_active or host.session.is_foreground_busy()) and not owns_foreground_speech())
	if _interaction.stage == "using":
		if not _owns_seat_contact(id): cancel_interaction("contact_lost"); return
		if busy or (host._dialogue_gesture_active() and not owns_foreground_speech()): cancel_interaction("foreground"); return
		if _clock >= float(_interaction.until): cancel_interaction("completed"); _status("컴퓨터 작업 자세 미리보기를 마쳤습니다"); return
		_apply_work_contact(windows[id])
		return
	if _interaction.stage == "seated":
		if not _owns_seat_contact(id): cancel_interaction("contact_lost")
		return
	if busy or (host.bridge.dialogue_holding(host._now()) and not owns_foreground_speech()):
		if _interaction.stage in ["facing","pose_wait","entering","exiting"]: cancel_interaction("foreground")
		return
	if _interaction.stage in ["entering","exiting"]:
		_tick_presentation()
		return
	if _interaction.stage == "pose_wait":
		if _clock < float(_interaction.pose_until): return
		_interaction.stage = "seating"
		host._push_autonomy_context()
		host.autonomy.set_visible_bounds(host._seated_navigation_rect())
		if not host.autonomy.request_seat_contact("object:"+id+":seat",contact_socket_screen("seat") if contact_scene_active() else windows[id].socket_point("seat")):
			cancel_interaction("unsafe_seat")
		return
	if _interaction.stage == "seating":
		var contact: Dictionary = host.autonomy.get_support_contact()
		if contact.get("attached",false) and not _owns_seat_contact(id): cancel_interaction("wrong_support"); return
		if not contact.get("attached",false) and not host.autonomy.is_seat_contact_pending("object:"+id+":seat"):
			cancel_interaction("contact_lost"); return
		if _owns_seat_contact(id):
			_interaction.stage = "using" if _interaction.verb == "use" else "seated"
			if _interaction.stage == "using": _interaction.until = _clock+10.0
			elif _interaction.has("command_id"):
				_command_outcome(str(_interaction.command_id),"arrived")
				_interaction.erase("command_id")
			_status("좌석에 앉았습니다 · 물건을 옮기면 다시 일어납니다")
			changed.emit()
		elif not host.is_sitting(): cancel_interaction("contact_lost")
		return
	if _interaction.stage in ["approaching","scene_approaching"]: return
	if _interaction.stage == "waiting" and not contact_scene_active():
		if not _activate_contact_scene(id): cancel_interaction("missing_contact_scene")
		return
	if _interaction.stage != "facing" and not (_spatial_enabled() and _interaction.stage in ["waiting","ready"]) and not host.autonomy.can_request_move(): return
	var object_window = windows[id]
	var socket := "seat" if contact_scene_active() or _interaction.verb == "sit" else "use"
	var point: Vector2 = contact_socket_screen(socket) if contact_scene_active() else object_window.socket_point(socket)
	if not point.is_finite(): cancel_interaction("missing_socket"); return
	if _interaction.stage == "waiting" and _spatial_enabled():
		var plan := scene_approach_plan(id)
		if plan.is_empty(): cancel_interaction("missing_scene_plan"); return
		_interaction.scene_target = plan.target_world
		_interaction.stage = "scene_approaching"
		var accepted: Dictionary = host.request_scene_approach(plan.target_world,scene_obstacle_bounds())
		if not accepted.get("accepted",false): cancel_interaction(str(accepted.get("reason","unreachable")))
		return
	if _interaction.stage == "waiting":
		# Stage in front of the cushion using the authored backwards hips travel.
		# Only X is walked on the existing support; entry owns the short 3D root path.
		var requirements: Dictionary = host.motion.seated_transition_requirements("enter")
		if requirements.is_empty(): cancel_interaction("missing_authored_transition"); return
		if not host._ensure_seated_geometry(): cancel_interaction("missing_seat_geometry"); return
		var facing: Vector3 = _contact_scene.facing_direction_world()
		var entry_basis := Basis(Vector3.UP,atan2(facing.x,facing.z)).scaled(Vector3.ONE*host._pet_scale)
		var seated_offset: Vector3 = Vector3(host._pivot_local.sit)-Vector3(host._pivot_local.foot)
		var staged_foot: Vector3 = contact_socket_world("seat")-entry_basis*(seated_offset+Vector3(requirements.source_root_delta_local))
		point.x = host.camera.unproject_position(staged_foot).x+host.get_window().position.x
		var foot: Vector2 = Vector2(host.get_window().position)+Vector2(host._projected_anchors().get("foot",host.pet_rect.get_center()))
		if absf(foot.x-point.x) > 24.0:
			var approach_id := "object:"+id+":approach"
			host.living.observe_interest(approach_id,Vector2(point.x,foot.y),1.0,60.0,"point",str(store.get_object(id).label)+" 앞")
			var request_id := "object-use:"+id+":"+str(Time.get_ticks_msec())
			_interaction.request_id = request_id
			_interaction.stage = "approaching"
			var accepted: Dictionary = host.living.request_intent({"kind":"move_to","target_id":approach_id},"user",request_id)
			if not accepted.get("accepted",false): cancel_interaction("unreachable"); _status("같은 지지면에서 물건 앞으로 걸어갈 수 없습니다")
			return
		_interaction.stage = "ready"
	if _interaction.stage == "ready":
		if not _activate_contact_scene(id): cancel_interaction("missing_contact_scene"); return
		if not _fit_contact_view(): cancel_interaction("contact_view_too_large"); _status("함께 보기에 물건이 큽니다. 크기를 조금 줄여 주세요"); return
		_contact_scene.show()
		windows[id].hide()
		_interaction.stage = "facing"
		_interaction.facing_until = _clock+6.0
		host._push_autonomy_context()
		var direction: Vector3 = _contact_scene.facing_direction_world()
		if not host.motion.set_contact_heading(atan2(direction.x,direction.z)):
			cancel_interaction("heading_rejected")
		return
	if _interaction.stage == "facing":
		if _clock >= float(_interaction.facing_until): cancel_interaction("heading_timeout"); return
		if not host.motion.heading_ready(): return
		_interaction.stage = "ready_contact"
		host._push_autonomy_context()
		_begin_seat(id,contact_socket_screen("seat"))

## The authored entry defines the staging distance, including real scene depth.
## Ground navigation changes X/Z; only the seat-height retarget may change source Y.
static func authored_staging_foot(seat_world: Vector3, entry_basis: Basis, sit_minus_foot: Vector3, source_delta: Vector3, ground_y: float) -> Vector3:
	if not seat_world.is_finite() or not sit_minus_foot.is_finite() or not source_delta.is_finite() or not is_finite(ground_y): return Vector3.INF
	var point := seat_world-entry_basis*(sit_minus_foot+source_delta)
	point.y = ground_y
	return point

## Conservative actual mesh-part bounds, including the target furniture. Hollow
## access is never granted by silently omitting the object being approached.
func scene_obstacle_bounds() -> Array:
	var result: Array = []
	if contact_scene_active(): _append_scene_solids(_contact_scene,result)
	for id in windows:
		if id == _contact_id or not bool(store.get_object(id).get("visible",false)): continue
		if is_instance_valid(windows[id]._scene): _append_scene_solids(windows[id]._scene,result)
	return result

static func _append_scene_solids(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for box in SceneSolids.local_parts(node.mesh):
			var world: AABB = node.global_transform*AABB(box)
			if world.size.length_squared()>0:result.append(world)
	for child in node.get_children(): _append_scene_solids(child,result)

func scene_approach_plan(id: String) -> Dictionary:
	if not _spatial_enabled() or not contact_scene_active() or id != _contact_id: return {}
	var requirements: Dictionary = host.motion.seated_transition_requirements("enter")
	if requirements.is_empty() or not host._ensure_seated_geometry(): return {}
	var facing: Vector3 = _contact_scene.facing_direction_world()
	var yaw := atan2(facing.x,facing.z)
	var entry_basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*host._pet_scale)
	var foot: Vector3 = host.avatar.contact_anchors().foot
	var source: Vector3 = requirements.source_root_delta_local
	var target := authored_staging_foot(contact_socket_world("seat"),entry_basis,Vector3(host._pivot_local.sit)-Vector3(host._pivot_local.foot),source,foot.y)
	if not target.is_finite(): return {}
	var solids := scene_obstacle_bounds()
	var selected := select_authored_staging(foot,contact_socket_world("seat"),entry_basis,Vector3(host._pivot_local.sit)-Vector3(host._pivot_local.foot),source,solids,.12*host._pet_scale,host._model_aabb.size.y*host._pet_scale)
	if selected.get("accepted",false):target=selected.target_world
	fit_diagnostics["scene_staging"]=selected
	return {"target_world":target,"facing_yaw":yaw,"ground_y":foot.y,"source_delta_local":source,"root_distance_factor":selected.get("factor",1.0),"object_id":id}

## Keep source angular curves and timing; admit the smallest bounded root-distance
## adjustment which clears every actual connected furniture part and path cell.
static func select_authored_staging(start: Vector3, seat: Vector3, basis: Basis, sit_minus_foot: Vector3, source: Vector3, solids: Array, radius: float, height: float) -> Dictionary:
	var last_reason := "blocked_endpoint"
	for factor in [1.0,1.05,1.1,1.15,1.2,1.25]:
		var adjusted := source
		adjusted.x *= factor;adjusted.z *= factor
		var target := authored_staging_foot(seat,basis,sit_minus_foot,adjusted,start.y)
		if not target.is_finite():return {"accepted":false,"reason":"invalid_staging"}
		var low := Vector2(minf(start.x,target.x),minf(start.z,target.z))-Vector2.ONE*1.2
		var high := Vector2(maxf(start.x,target.x),maxf(start.z,target.z))+Vector2.ONE*1.2
		var nav := DesktopSceneNavigation.new()
		var geometry := nav.configure(Rect2(low,high-low),start.y,solids,radius,height,DesktopSceneNavigationHost.navigation_cell_size(high-low))
		var result := nav.plan("staging",start,target) if geometry.get("ok",false) else {"accepted":false,"reason":geometry.get("reason","invalid_geometry")}
		nav.dispose()
		if result.get("accepted",false):return {"accepted":true,"target_world":target,"factor":factor,"source_delta_local":source,"applied_delta_local":adjusted}
		last_reason=str(result.get("reason","unreachable"))
	return {"accepted":false,"reason":last_reason,"maximum_factor":1.25}

func scene_navigation_finished(outcome: String) -> void:
	if _interaction.get("stage","") != "scene_approaching": return
	if outcome != "arrived": cancel_interaction(outcome); return
	var target: Vector3 = _interaction.get("scene_target",Vector3.INF)
	var actual: Vector3 = host.avatar.contact_anchors().foot
	if not target.is_finite() or Vector2(actual.x-target.x,actual.z-target.z).length() > .015:
		cancel_interaction("approach_misaligned"); return
	_interaction.stage = "ready"

func _owns_seat_contact(id: String) -> bool:
	var contact: Dictionary = host.autonomy.get_support_contact()
	return host.is_sitting() and host._sit_attached and contact.get("attached",false) and contact.get("pose","") == "sit" and str(contact.get("surface_id","")) == "object:"+id+":seat"

func _begin_seat(id: String, point: Vector2) -> void:
	if not host._ensure_seated_geometry():
		cancel_interaction("missing_seat_geometry"); return
	var previous_bounds: Rect2 = host.autonomy.visible_bounds
	host.autonomy.set_visible_bounds(host._seated_navigation_rect())
	var anchors: Dictionary = host._projected_anchors()
	var seat: Vector2 = anchors.get("sit",Vector2.INF)
	if not host.autonomy.can_request_seat_contact("object:"+id+":seat",point,seat):
		host.autonomy.set_visible_bounds(previous_bounds)
		cancel_interaction("unsafe_seat")
		_status("좌석이 낮거나 화면 가장자리에 가깝습니다. 물건 높이·위치나 펫 크기를 맞춰 주세요")
		return
	if host.get("scene_navigation") != null: host.scene_navigation.release_to_contact()
	var delta: Vector3 = contact_socket_world("seat")-host.avatar.contact_anchors().sit
	_interaction["standing_foot_local"] = _contact_scene.to_local(host.avatar.contact_anchors().foot)
	if not _start_presentation("enter",delta):
		cancel_interaction("missing_authored_transition"); return
	host._sit_pending = false
	host._walk_started = ""
	host._floating = false
	# The authored knees/hips start while the body is still standing. The
	# terminal seated pivot is committed only after that clip finishes.
	_interaction.stage = "entering"
	host._push_autonomy_context()
	host._refresh_sit_button()

func has_presentation_transition() -> bool:
	return not _presentation.is_empty()

func presentation_offset() -> Vector3:
	if _presentation.is_empty(): return Vector3.ZERO
	var state: Dictionary = host.motion.seated_transition_state()
	return Vector3(_presentation.world_delta)*float(state.get("root_progress",0.0))

func presentation_bounds() -> AABB:
	if _presentation.is_empty(): return AABB()
	var state: Dictionary = host.motion.seated_transition_state()
	return state.get("transition_bounds",AABB())

func _start_presentation(kind: String, world_delta: Vector3) -> bool:
	if not world_delta.is_finite() or not host.motion.has_method("start_seated_transition"): return false
	var local_delta: Vector3 = host.avatar.global_basis.inverse()*world_delta
	if not host.motion.start_seated_transition(kind,local_delta): return false
	_presentation = {"kind":kind,"world_delta":world_delta,"started":_clock}
	var state: Dictionary = host.motion.seated_transition_state()
	if not state.get("transition_bounds") is AABB or state.transition_bounds.size.length_squared() <= 0.0:
		_presentation.clear(); host.motion.cancel_seated_transition(); return false
	# Preframe the complete authored path while the furniture still follows
	# transparent-frame compensation; freeze its 3D transform only after entry.
	if not _fit_contact_view():
		_presentation.clear(); host.motion.cancel_seated_transition(); return false
	return true

func request_stand() -> bool:
	if _interaction.get("stage","") not in ["seated","using"] or not contact_scene_active(): return false
	if not _interaction.has("standing_foot_local"): return false
	var target: Vector3 = _contact_scene.to_global(Vector3(_interaction.standing_foot_local))
	var delta: Vector3 = target-host.avatar.contact_anchors().foot
	if not _start_presentation("exit",delta): return false
	_interaction.stage = "exiting"
	host._sit_active = false
	host._sit_attached = false
	host.motion.set_upper_body_contact_lock(false)
	host.autonomy.set_contact_pose("foot")
	host._push_autonomy_context()
	return true

func _tick_presentation() -> void:
	var state: Dictionary = host.motion.seated_transition_state()
	if state.is_empty() or _clock-float(_presentation.get("started",_clock)) > float(state.get("duration",0.0))+2.0:
		cancel_interaction("transition_timeout"); return
	if not bool(state.get("finished",false)): return
	var entering: bool = _interaction.stage == "entering"
	# Capture the rendered endpoint, including real camera depth, before
	# removing the transient displacement (perspective must not flatten it).
	var pivot_kind := "sit" if entering else "foot"
	var pivot_world: Vector3 = host.avatar.global_transform*Vector3(host._pivot_local[pivot_kind])
	host._camera_pivot_depth = DesktopView.depth(host.camera,pivot_world)
	host._switch_pivot("sit" if entering else "foot")
	host._pivot_px_target = host._pivot_px
	_presentation.clear()
	host._sit_active = entering
	host._sit_attached = false
	if not host.motion.finish_seated_transition(): cancel_interaction("transition_failed"); return
	host._update_avatar_transform(0.0)
	host._update_pet_rect()
	if not entering:
		cancel_interaction("completed")
		host._refresh_sit_button()
		return
	_interaction.stage = "seating"
	_update_contact_transform()
	_refresh_adapters()
	host.autonomy.set_contact_pose("sit")
	host.autonomy.set_visible_bounds(host._seated_navigation_rect())
	host.autonomy.set_contact_anchors(host._projected_anchors())
	host._push_autonomy_context()
	if not host.autonomy.request_seat_contact("object:"+str(_interaction.id)+":seat",contact_socket_screen("seat")):
		cancel_interaction("unsafe_seat")
	host._refresh_sit_button()

func _apply_work_contact(_object_window) -> void:
	if host.motion.has_method("set_upper_body_contact_lock"): host.motion.set_upper_body_contact_lock(true)
	host.motion.set_ambient_state("working",1.0)
	if host.living != null: host.living._look = contact_socket_screen("inspect")
	if not contact_scene_active() or not host.avatar.has_model(): return
	var both := true
	for side in ["left","right"]:
		var socket: String = "keyboard_"+side
		var target := contact_socket_world(socket)
		var reached: bool = target.is_finite() and host.avatar.apply_hand_contact(side,target)
		_interaction[side+"_hand_reachable"] = reached
		both = both and reached
	_interaction["hand_reachable"] = both

func contact_scene_active() -> bool:
	return is_instance_valid(_contact_scene) and _contact_scene.loaded

func contact_socket_world(socket: String) -> Vector3:
	return _contact_scene.socket_world(socket) if contact_scene_active() else Vector3.INF

func contact_socket_screen(socket: String) -> Vector2:
	var point := contact_socket_world(socket)
	return Vector2(host.get_window().position)+host.camera.unproject_position(point) if point.is_finite() else Vector2.INF

func contact_bounds() -> Rect2:
	if not contact_scene_active(): return Rect2()
	var box := _contact_scene.get_world_bounds()
	var low := Vector2(INF,INF)
	var high := Vector2(-INF,-INF)
	for i in 8:
		var p: Vector2 = host.camera.unproject_position(box.get_endpoint(i))
		low = low.min(p); high = high.max(p)
	return Rect2(low,high-low)

func _contact_seat_surface() -> Dictionary:
	if not contact_scene_active(): return {}
	var point := contact_socket_screen("seat")
	# Horizontal pelvis admission only; the shared mesh supplies actual depth.
	var width := 24.0
	return {"id":"object:"+_contact_id+":seat","x1":point.x-width*0.5,"x2":point.x+width*0.5,"y":point.y}

func _activate_contact_scene(id: String) -> bool:
	if contact_scene_active(): return _contact_id == id
	var scene := ContactScene.new()
	host.add_child(scene)
	if not scene.configure(str(store.get_object(id).type)): scene.free(); return false
	Appearance.apply(scene,str(store.get_object(id).get("appearance","default")))
	_contact_scene = scene
	_contact_id = id
	var window = windows[id]
	_contact_floor = Vector2(window.position)+Vector2(window.size.x*0.5,window.size.y-1.0)
	_contact_scale = window.pixels_per_metre()/host._px_per_m
	if _spatial_enabled():
		_contact_scale = float(store.get_object(id).scale)*float(store.get_object(id).get("spatial_unit_scale",1.0))
	var floor_clearance := (scene.socket_local("seat").y-scene.get_local_bounds().position.y)*_contact_scale/maxf(host._pet_scale,0.001)
	if not host.motion.set_seated_floor(floor_clearance):
		_release_contact_scene()
		return false
	if not host._ensure_seated_geometry():
		_release_contact_scene()
		return false
	# Reframe transparent window space while preserving every visible desktop point.
	_contact_reframe = Vector2i(roundi(host._pivot_px.x-host.WINDOW_SIZE.x*0.5),0)
	host.get_window().position += _contact_reframe
	host.autonomy.position = Vector2(host.get_window().position)
	host._pivot_px -= Vector2(_contact_reframe)
	host._pivot_px_target -= Vector2(_contact_reframe)
	host._update_avatar_transform(0.0)
	host._update_pet_rect()
	host.autonomy.set_visible_bounds(host._navigation_rect())
	host.autonomy.set_contact_anchors(host._projected_anchors())
	_update_contact_transform()
	scene.hide() # keep the unoccupied native object visible during the approach
	_refresh_adapters()
	return true

func _on_frame_moved(_displacement: Vector2,_velocity: Vector2) -> void:
	# Autonomy commits after main.tick; keep furniture fixed on the actual frame.
	_update_contact_transform()

func _fit_contact_view(preserve_seat: bool = false) -> bool:
	var rect: Rect2 = host._navigation_rect().merge(contact_bounds())
	var viewport := Vector2(host.WINDOW_SIZE)
	fit_diagnostics["view"] = {"reason":"checking","local_bounds":rect,"viewport":viewport,"origin":host.get_window().position}
	if rect.size.x > viewport.x-8.0 or rect.size.y > viewport.y-8.0:
		fit_diagnostics.view.reason = "viewport_too_small"
		return false
	var shift := AutonomyBridge.fit_shift(rect.grow(2.0),viewport)
	var delta := Vector2i(-shift.round())
	if delta != Vector2i.ZERO:
		_contact_reframe += delta
		host.get_window().position += delta
		host.autonomy.position = Vector2(host.get_window().position)
		host._pivot_px -= Vector2(delta)
		host._pivot_px_target -= Vector2(delta)
		host._update_avatar_transform(0.0)
		host._update_pet_rect()
		if not preserve_seat: host.autonomy.set_contact_anchors(host._projected_anchors())
		_update_contact_transform()
	var global_rect: Rect2 = host._navigation_rect().merge(contact_bounds()) if preserve_seat else contact_bounds()
	global_rect.position += Vector2(host.get_window().position)
	fit_diagnostics.view["global_bounds_before"] = global_rect
	for area in screen_rects():
		if Rect2(area).encloses(global_rect):
			fit_diagnostics.view.reason = "fits"
			return true
	if preserve_seat and not _spatial_enabled():
		var nudge: Variant = _minimal_assembly_nudge(global_rect,screen_rects())
		if nudge != null:
			# Move the occupied assembly together. Unlike the transparent-frame
			# compensation above, local pivots do not move in the opposite direction.
			# The shared floor receives exactly the same desktop displacement.
			host.get_window().position += Vector2i(nudge)
			host.autonomy.position = Vector2(host.get_window().position)
			_contact_floor += Vector2(nudge)
			_update_contact_transform()
			global_rect.position += Vector2(nudge)
			fit_diagnostics.view["nudge"] = Vector2i(nudge)
			fit_diagnostics.view["global_bounds_after"] = global_rect
			fit_diagnostics.view.reason = "assembly_nudged"
			return true
	fit_diagnostics.view.reason = "outside_workarea"
	return false

## Integer minimum translation within the current intersecting workarea. Never
## scale the assembly, cross a disconnected monitor, or make a large desktop jump.
static func _minimal_assembly_nudge(rect: Rect2, areas: Array) -> Variant:
	if not rect.position.is_finite() or not rect.size.is_finite(): return null
	var best: Variant = null
	var distance := INF
	for value in areas:
		var area := Rect2(value)
		if not area.intersects(rect) or rect.size.x > area.size.x or rect.size.y > area.size.y: continue
		var low := area.position-rect.position
		var high := area.end-rect.end
		var shift := Vector2i(clampi(0,ceili(low.x),floori(high.x)),clampi(0,ceili(low.y),floori(high.y)))
		var moved := Rect2(rect.position+Vector2(shift),rect.size)
		if not area.encloses(moved) or Vector2(shift).length() > 256.0: continue
		if Vector2(shift).length_squared() < distance:
			best = shift
			distance = Vector2(shift).length_squared()
	return best


func _update_contact_transform() -> void:
	if not contact_scene_active() or _interaction.get("stage","") in ["entering","exiting"]: return
	if _spatial_enabled():
		var record: Dictionary = store.get_object(_contact_id)
		if Store.valid_position_m(record.get("position_m")):
			var placement := _spatial_transform(record)
			placement.basis = Basis(Vector3.UP,deg_to_rad(_contact_scene.recommended_yaw_degrees+float(record.get("yaw_deg",0.0))))*placement.basis
			_contact_scene.transform = placement
		return
	var basis := Basis(Vector3.UP,deg_to_rad(_contact_scene.recommended_yaw_degrees+float(store.get_object(_contact_id).get("yaw_deg",0.0)))).scaled(Vector3.ONE*_contact_scale)
	var anchor: Vector3 = host.avatar.contact_anchors().get("sit",Vector3.ZERO)
	var ground := Vector3(0,_contact_scene.get_local_bounds().position.y,0)
	var offset := basis*(_contact_scene.socket_local("seat")-ground)
	var depth := DesktopView.base_depth_for_offset(host.camera,anchor,offset)
	var floor_world := DesktopView.screen_to_world_at_depth(host.camera,_contact_floor-Vector2(host.get_window().position),depth)
	if not floor_world.is_finite(): return
	_contact_scene.transform = Transform3D(basis,floor_world-basis*ground)

func _release_contact_scene() -> void:
	if host != null and host.motion.has_method("set_upper_body_contact_lock"): host.motion.set_upper_body_contact_lock(false)
	if not is_instance_valid(_contact_scene): return
	host.motion.clear_seated_floor()
	_contact_scene.free()
	_contact_scene = null
	var id := _contact_id
	_contact_id = ""
	host.get_window().position -= _contact_reframe
	host.autonomy.position = Vector2(host.get_window().position)
	host._pivot_px += Vector2(_contact_reframe)
	host._pivot_px_target += Vector2(_contact_reframe)
	_contact_reframe = Vector2i.ZERO
	host._update_avatar_transform(0.0)
	host._update_pet_rect()
	if windows.has(id): windows[id].show()
	_refresh_adapters()

func _intent_outcome(id: String, outcome: String) -> void:
	if _interaction.is_empty() or str(_interaction.get("request_id","")) != id: return
	if outcome == "arrived": _interaction.stage = "ready"
	else: cancel_interaction(outcome); _status("물건까지의 이동을 멈췄습니다")

func _after_change() -> void:
	_sync_windows()
	if _settings != null: _settings.set_value("desktop_objects",store.data())
	_refresh_adapters()
	changed.emit()

func _sync_windows() -> void:
	if _closed: return
	var live := {}
	if native_available():
		for record in store.rows(screen_rects()):
			if record.status != "ready" or not record.visible or _runtime_rect(record).size == Vector2i.ZERO: continue
			var id := str(record.id)
			live[id] = true
			if not windows.has(id):
				var window = FurnitureWindow.new()
				add_child(window)
				window.configure(record,_runtime_rect(record).size)
				window.set_view_basis(host.camera.global_basis)
				window.set_projection_zoom(_view_zoom)
				window.drag_started.connect(func(_id): cancel_interaction("object_dragged"); host.autonomy.cancel_target("object_dragged"))
				window.drag_finished.connect(_object_drag_finished)
				windows[id] = window
			var window = windows[id]
			window.apply_record(record,store.rect_for(record).size)
			if _spatial_enabled():
				if not _sync_spatial_window(id):
					window.hide()
					continue
				window.set_editable(edit_enabled)
				if window.loaded and (id != _contact_id or not _contact_scene.visible): window.show_native()
				elif id == _contact_id: window.hide()
				continue
			elif is_instance_valid(window._shared_camera):
				window.clear_shared_projection()
			var safe_position: Variant = store.clamp_position(window.position,window.size,screen_rects())
			if safe_position == null:
				window.hide()
				continue
			if not window.dragging: window.position = Vector2i(safe_position)
			window.set_editable(edit_enabled)
			if window.loaded and (id != _contact_id or not _contact_scene.visible): window.show_native()
			elif id == _contact_id: window.hide()
	for id in windows.keys():
		if not live.has(id):
			var window = windows[id]
			windows.erase(id)
			window.hide()
			window.queue_free()

func _refresh_adapters() -> void:
	if host == null or _closed: return
	var seats: Array = []
	var live := {}
	for id in windows:
		var window = windows[id]
		var record: Dictionary = store.get_object(id)
		if record.is_empty() or not record.get("visible",false): continue
		if (not window.visible and id != _contact_id) or not window.loaded or window.dragging: continue
		var seat: Dictionary = _contact_seat_surface() if id == _contact_id else window.seat_surface()
		if not seat.is_empty(): seats.append(seat)
		var interest_id := "object:"+str(id)
		live[interest_id] = true
		if host.living != null: host.living.observe_interest(interest_id,window.socket_point("inspect"),0.8,1.5,"prop",str(record.label))
	host.autonomy.set_seat_surfaces(seats)
	for id in _published_ids:
		if not live.has(id) and host.living != null:
			host.living._external.erase(id)
			host.living.director.remove_interest(id)
	_published_ids = live

func _reject(message: String) -> Dictionary:
	_status(message)
	return {"accepted":false,"reason":message}

func _status(message: String) -> void:
	last_status = message
	status_changed.emit(message)
	if host != null: host.panel.set_status_message(message)

func shutdown() -> void:
	if _closed: return
	cancel_interaction("shutdown")
	if host != null and is_instance_valid(host.autonomy): host.autonomy.set_seat_surfaces([])
	_closed = true
	for window in windows.values():
		window.hide()
		window.queue_free()
	windows.clear()

func _exit_tree() -> void:
	shutdown()

func _runtime_rect(record: Dictionary) -> Rect2i:
	var base := store.rect_for(record)
	var dimensions := Vector2i(Vector2(base.size)*_view_zoom)
	var desired := base.position+Vector2i((base.size.x-dimensions.x)/2,base.size.y-dimensions.y)
	var placed: Variant = store.clamp_position(desired,dimensions,screen_rects())
	return Rect2i() if placed == null else Rect2i(Vector2i(placed),dimensions)

func occupied_rect() -> Rect2:
	return host._navigation_rect().merge(contact_bounds()) if contact_scene_active() else host.pet_rect

func refresh_view() -> void:
	if _closed or host == null: return
	_view_zoom = float(host._view_settings.get("view_zoom",1.0))
	for window in windows.values():
		if window.has_method("set_view_basis"):
			window.set_view_basis(host.camera.global_basis)
			window.set_projection_zoom(_view_zoom)
	_sync_windows()
	if _spatial_enabled() and _settings != null: _settings.set_value("desktop_objects",store.data())
	if not contact_scene_active(): return
	if _spatial_enabled():
		_update_contact_transform()
		# A changed view never changes canonical prop pose. Reanchor the already
		# occupied avatar to the same world seat before normal fit/admission.
		if _interaction.get("stage","") in ["seated","using"]:
			var seat := contact_socket_world("seat")
			host._camera_pivot_depth = DesktopView.depth(host.camera,seat)
			host._pivot_px = host.camera.unproject_position(seat)
			host._pivot_px_target = host._pivot_px
			host._update_avatar_transform(0.0)
			host._update_pet_rect()
			if not _fit_contact_view(true): cancel_interaction("view_does_not_fit"); return
			if not host.autonomy.refresh_seat_projection("object:"+_contact_id+":seat",contact_socket_screen("seat"),host._projected_anchors(),host._navigation_rect()):
				cancel_interaction("unsafe_view"); return
		_refresh_adapters()
		if _interaction.get("stage","") == "using": _apply_work_contact(windows[_contact_id])
		return
	# Preserve real world seat coincidence while the camera orbits. Its new
	# projected floor may move, but neither the pelvis nor furniture floats apart.
	var basis := Basis(Vector3.UP,deg_to_rad(_contact_scene.recommended_yaw_degrees+float(store.get_object(_contact_id).get("yaw_deg",0.0)))).scaled(Vector3.ONE*_contact_scale)
	var anchor: Vector3 = host.avatar.contact_anchors().get("sit",Vector3.ZERO)
	var ground := Vector3(0,_contact_scene.get_local_bounds().position.y,0)
	var floor_world := anchor-basis*(_contact_scene.socket_local("seat")-ground)
	_contact_floor = Vector2(host.get_window().position)+host.camera.unproject_position(floor_world)
	_update_contact_transform()
	if not _fit_contact_view(true): cancel_interaction("view_does_not_fit"); return
	if _interaction.get("stage","") in ["seated","using"]:
		var point := contact_socket_screen("seat")
		if not host.autonomy.refresh_seat_projection("object:"+_contact_id+":seat",point,host._projected_anchors(),host._navigation_rect()):
			cancel_interaction("unsafe_view"); return
	_refresh_adapters()
	if _interaction.get("stage","") == "using": _apply_work_contact(windows[_contact_id])

func _object_drag_finished(id: String, actual_position: Vector2i) -> void:
	if not windows.has(id) or not store.has_object(id): return
	if _spatial_enabled():
		var row: Dictionary = store.get_object(id)
		if Store.valid_position_m(row.get("position_m")):
			var old_world := _spatial_transform(row).origin
			var reference: Camera3D = host.spatial_camera()
			var old_window_origin: Vector2 = host.spatial_desktop_origin()+windows[id]._shared_crop.position
			var pixel: Vector2 = reference.unproject_position(old_world)+Vector2(actual_position)-old_window_origin
			configure_spatial_position(id,DesktopView.screen_to_world_at_depth(reference,pixel,DesktopView.depth(reference,old_world)))
			_sync_windows()
		return
	var record: Dictionary = store.get_object(id)
	var base := Vector2(Store.base_size(str(record.type)))*float(record.scale)
	var actual := Vector2(windows[id].size)
	var persisted := Vector2(actual_position)+Vector2((actual.x-base.x)*.5,actual.y-base.y)
	move_object(id,Vector2i(persisted.round()))

## Canonical perspective frame is owned by main; native windows are exact crops.
func _spatial_enabled() -> bool:
	return host != null and host.has_method("spatial_camera") and host.spatial_camera() != null

func _spatial_transform(record: Dictionary) -> Transform3D:
	var value: Dictionary = record.position_m
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*float(record.scale)*float(record.get("spatial_unit_scale",1.0))),Vector3(value.x,value.y,value.z))

func _sync_spatial_window(id: String) -> bool:
	if not _spatial_enabled() or not windows.has(id): return false
	var window = windows[id]
	var record: Dictionary = store.get_object(id)
	var reference: Camera3D = host.spatial_camera()
	if not record.has("spatial_unit_scale"):
		var unit: float = window._reference_ppm*maxf(_view_zoom,.01)/maxf(host._px_per_m,1.0)
		if not store.set_spatial_unit_scale(id,unit): return false
	if not Store.valid_position_m(record.get("position_m")):
		var legacy := store.rect_for(record)
		var screen := Vector2(legacy.position)+Vector2(legacy.size.x*.5,legacy.size.y-1.0)
		var world := DesktopView.screen_to_world_at_depth(reference,screen-host.spatial_desktop_origin(),host._camera_pivot_depth)
		if not store.set_position_m(id,world): return false
		record = store.get_object(id)
	else: record = store.get_object(id)
	window.set_shared_world(host.get_viewport().world_3d,host.get_viewport())
	if not window.set_shared_projection(reference,host.spatial_desktop_origin(),_spatial_transform(record)): return false
	var projected := Rect2(Vector2(window.position),Vector2(window.size))
	for area in screen_rects():
		if Rect2(area).encloses(projected): return true
	return false

func configure_spatial_position(id: String, value: Vector3) -> bool:
	if not _spatial_enabled() or not windows.has(id): return false
	var previous: Dictionary = store.data()
	if not store.set_position_m(id,value): return false
	if not _sync_spatial_window(id):
		store.set_data(previous)
		_sync_spatial_window(id)
		return false
	cancel_interaction("object_configured")
	_after_change()
	return true

func _owns_command_speech(command: Dictionary) -> bool:
	var id := str(command.get("command_id",command.get("id","")))
	return command.get("source","") == "llm" and not str(host.session.turn_id).is_empty() and id == str(host.session.turn_id)+":intent"

func owns_foreground_speech() -> bool:
	return not _interaction.is_empty() and _owns_command_speech(_interaction)

func admits_contact_during_reply() -> bool:
	if not owns_foreground_speech() or _interaction.get("stage","") not in ["ready_contact","seating"]: return false
	var job_active:bool=not host.session.job.is_empty() and str(host.session.job.get("status","")) not in ["done","failed","cancelled","completed"]
	return not job_active and not host.motion._preview and not host.motion._custom_motion
