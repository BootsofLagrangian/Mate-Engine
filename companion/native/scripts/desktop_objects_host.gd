class_name DesktopObjectsHost
extends Node
## Local furniture, geometry sockets and finite pose interactions. No screen-content read,
## keyboard/mouse injection, arbitrary files, or model calls are performed here.
signal changed
signal status_changed(message: String)
signal interaction_finished(id: String, verb: String, outcome: String)
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
var fit_diagnostics: Dictionary = {}

func configure(app) -> void:
	host = app
	host.autonomy.frame_moved.connect(_on_frame_moved)
	_settings = get_node("/root/Settings")
	store.set_data(_settings.get_value("desktop_objects",{}))
	_last_character = str(host.session.character_id)
	if host.panel.has_method("bind_desktop_objects"): host.panel.bind_desktop_objects(self)
	if host.living != null:
		host.living.director.intent_outcome.connect(_intent_outcome)
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
	var source_ppm := sizing_window.pixels_per_metre() if sizing_ok else 0.0
	sizing_window.free()
	if source_ppm <= 1.0:
		store.remove_object(id)
		_status("물건 모델을 준비하지 못했습니다")
		return ""
	var physical_ppm: float = host._px_per_m*host._pet_scale
	var default_scale := clampf(physical_ppm/source_ppm,0.5,1.8)
	fit_diagnostics[id] = {"physical_ppm":physical_ppm,"applied_ratio":1.0,"seat_floor_adaptation":true}

	if not store.resize_object(id,default_scale,screen_rects()):
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
	_after_change()
	set_edit_enabled(true)
	_status("물건을 끌어 놓고 크기를 맞춰 주세요. 좌석 접촉은 미리보기입니다")
	return id

func rename_object(id: String, label: String) -> bool:
	if not store.rename_object(id,label): return false
	_after_change(); return true

func move_object(id: String, point: Vector2i) -> bool:
	cancel_interaction("object_moved")
	if not store.move_object(id,point,screen_rects()): _sync_windows(); return false
	_after_change(); return true

func resize_object(id: String, scale: float) -> bool:
	cancel_interaction("object_resized")
	if not store.resize_object(id,scale,screen_rects()): _status("그 크기로는 화면 안에 놓을 수 없습니다"); return false
	_after_change(); return true

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
	return not _interaction.is_empty() and _interaction.stage in ["facing","pose_wait","using"]

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
	if _interaction.is_empty(): return
	var previous := _interaction.duplicate()
	_interaction.clear() # clear before host callbacks can re-enter
	if host != null:
		_release_contact_scene()
		if host.living != null and previous.has("request_id"):
			host.living.director.cancel_intent(str(previous.request_id),reason)
		host.autonomy.cancel_target(reason)
		if previous.stage in ["pose_wait","seating","seated","using"] and host.is_sitting(): host._stand_up("")
		if previous.stage == "facing": host.motion.cancel_heading()
		if previous.stage == "using": host.motion.set_ambient_state("rest",0.0)
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
	if _interaction.is_empty(): return
	if host.living == null or not host.living.enabled or not host.autonomy.enabled or not host.autonomy.surface_mode:
		cancel_interaction("disabled"); return
	if host._drag_active:
		cancel_interaction("pet_dragged"); return
	var id := str(_interaction.id)
	if not store.has_object(id) or not windows.has(id) or (not windows[id].visible and id != _contact_id) or is_dragging(): cancel_interaction("object_unavailable"); return
	if _clock >= float(_interaction.expires) and _interaction.stage != "seated": cancel_interaction("expired"); _status("상호작용 요청 시간이 지나 멈췄습니다"); return
	if host.panel_open:
		cancel_interaction("panel_open"); return
	var job_active: bool = not host.session.job.is_empty() and str(host.session.job.get("status","")) not in ["done","failed","cancelled","completed"]
	var busy: bool = job_active or host.audio.voice_active or host.mic.is_recording() or host.session.is_foreground_busy() or host._drag_active or host.motion._preview or host.motion._custom_motion
	if _interaction.stage == "using":
		if not _owns_seat_contact(id): cancel_interaction("contact_lost"); return
		if busy or host._dialogue_gesture_active(): cancel_interaction("foreground"); return
		if _clock >= float(_interaction.until): cancel_interaction("completed"); _status("컴퓨터 작업 자세 미리보기를 마쳤습니다"); return
		_apply_work_contact(windows[id])
		return
	if _interaction.stage == "seated":
		if not _owns_seat_contact(id): cancel_interaction("contact_lost")
		return
	if busy or host.bridge.dialogue_holding(host._now()):
		if _interaction.stage in ["facing","pose_wait"]: cancel_interaction("foreground")
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
			_status("좌석에 앉았습니다 · 물건을 옮기면 다시 일어납니다")
			changed.emit()
		elif not host.is_sitting(): cancel_interaction("contact_lost")
		return
	if _interaction.stage == "approaching": return
	if _interaction.stage == "waiting" and not contact_scene_active():
		if not _activate_contact_scene(id): cancel_interaction("missing_contact_scene")
		return
	if _interaction.stage != "facing" and not host.autonomy.can_request_move(): return
	var object_window = windows[id]
	var socket := "seat" if contact_scene_active() or _interaction.verb == "sit" else "use"
	var point: Vector2 = contact_socket_screen(socket) if contact_scene_active() else object_window.socket_point(socket)
	if not point.is_finite(): cancel_interaction("missing_socket"); return
	if _interaction.stage == "waiting":
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
	if not host.motion.start_contact_pose("sit"):
		cancel_interaction("missing_pose"); _status("앉기 동작을 준비하지 못했습니다"); return
	host._sit_pending = false
	host._sit_active = true
	host._sit_attached = false
	host._walk_started = ""
	host._floating = false
	host._switch_pivot("sit")
	host._update_pet_rect()
	_interaction.stage = "pose_wait"
	_interaction.pose_until = _clock+0.8
	host._push_autonomy_context()
	host.autonomy.set_contact_pose("sit")
	host.autonomy.set_contact_anchors(host._projected_anchors())
	host._refresh_sit_button()

func _apply_work_contact(_object_window) -> void:
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
	_contact_scene = scene
	_contact_id = id
	var window = windows[id]
	_contact_floor = Vector2(window.position)+Vector2(window.size.x*0.5,window.size.y-1.0)
	_contact_scale = window.pixels_per_metre()/host._px_per_m
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

func _fit_contact_view() -> bool:
	var rect: Rect2 = host._navigation_rect().merge(contact_bounds())
	var viewport := Vector2(host.WINDOW_SIZE)
	if rect.size.x > viewport.x-8.0 or rect.size.y > viewport.y-8.0: return false
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
		host.autonomy.set_contact_anchors(host._projected_anchors())
		_update_contact_transform()
	var global_rect := contact_bounds()
	global_rect.position += Vector2(host.get_window().position)
	for area in screen_rects():
		if Rect2(area).encloses(global_rect): return true
	return false

func _update_contact_transform() -> void:
	if not contact_scene_active(): return
	var basis := Basis(Vector3.UP,deg_to_rad(_contact_scene.recommended_yaw_degrees)).scaled(Vector3.ONE*_contact_scale)
	var origin := AutonomyBridge.pixel_to_world(_contact_floor-Vector2(host.get_window().position),host._camera_base,host._px_per_m,Vector2(host.WINDOW_SIZE))
	origin.y -= _contact_scene.get_local_bounds().position.y*_contact_scale
	_contact_scene.transform = Transform3D(basis,origin)
	var anchor: Vector3 = host.avatar.contact_anchors().get("sit",Vector3.ZERO)
	_contact_scene.position.z += anchor.z-_contact_scene.socket_world("seat").z

func _release_contact_scene() -> void:
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
	if _settings != null: _settings.set_value("desktop_objects",store.data())
	_sync_windows()
	_refresh_adapters()
	changed.emit()

func _sync_windows() -> void:
	if _closed: return
	var live := {}
	if native_available():
		for record in store.rows(screen_rects()):
			if record.status != "ready" or not record.visible: continue
			var id := str(record.id)
			live[id] = true
			if not windows.has(id):
				var window = FurnitureWindow.new()
				add_child(window)
				window.configure(record,store.rect_for(record).size)
				window.drag_started.connect(func(_id): cancel_interaction("object_dragged"); host.autonomy.cancel_target("object_dragged"))
				window.drag_finished.connect(move_object)
				windows[id] = window
			var window = windows[id]
			window.apply_record(record,store.rect_for(record).size)
			window.set_editable(edit_enabled)
			if window.loaded and (id != _contact_id or not _contact_scene.visible): window.show()
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
