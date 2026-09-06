class_name LivingBehavior
extends Node
## Coordinates local behavior, user points, named LLM intents and presentation.
## The director never calls a model; only existing conversation turns may return intents.
var host
var director := BehaviorDirector.new()
var scene_interests = preload("desktop_scene_interests.gd").new()
var points: InterestPoints
var last_output: Dictionary = {}
var selected_locomotion_id := ""
var outcomes: Array[Dictionary] = []
var enabled := true
var _settings: Node
var _known: Dictionary = {}
var _external: Dictionary = {}
var _clock := 0.0
var _refresh_at := 0.0
var _publish_at := 0.0
var _published := ""
var _character := ""
var _style_fingerprint := ""
var _motion_profile_fingerprint := ""
var _idle_action_next := 20.0
var _idle_action_index := 0
var _request_counter := 0
var _attention_until := 0.0
var _pointer_seen := Vector2.INF
var _pointer_next := 0.0
var _look := Vector2.INF
var _last_state := ""
const LABELS := {"rest":"편하게 쉬는 중", "curious":"관심 있는 곳 살펴보기", "sleepy":"잠깐 눈을 쉬는 중",
	"anticipate":"갈 곳을 바라보는 중", "walk":"천천히 걸어가는 중", "arrive":"자리를 잡는 중",
	"approach":"설 자리를 찾는 중", "attentive":"사용자를 바라보는 중", "thinking":"생각하는 중",
	"listening":"귀 기울이는 중", "speaking":"이야기하는 중", "working":"작업에 집중하는 중", "held":"이동해 주는 대로 따라가는 중"}

func configure(app) -> void:
	host = app
	_settings = get_node("/root/Settings")
	points = InterestPoints.new()
	points.name = "InterestPoints"
	points.anchor_provider = func(): return Vector2i(Vector2(host.get_window().position) + Vector2(host._projected_anchors().get("foot", host.pet_rect.get_center())) - Vector2(0, 2))
	add_child(points)
	points.set_points(_settings.get_value("interest_points", {}))
	points.changed.connect(_points_changed)
	host.panel.bind_interest_points(points)
	host.panel.point_go.connect(func(id: String): _user_point(id, "move_to"))
	host.panel.point_inspect.connect(func(id: String): _user_point(id, "inspect"))
	host.autonomy.frame_moved.connect(_frame_moved)
	host.autonomy.navigation_finished.connect(_navigation_finished)
	host.session.event_accepted.connect(_event)
	host.session.character_changed.connect(func(_id: String): _refresh_at = 0.0; _published = "")
	host.client.disconnected.connect(func(_why: String): cancel("disconnected"); _published = "")
	director.intent_outcome.connect(func(id: String, outcome: String):
		object_command_result(id,outcome)
		outcomes.append({"id": id, "outcome": outcome, "time": _clock})
		if outcomes.size() > 64: outcomes.pop_front()
		if not id.begins_with("local:"):
			var messages := {"arrived":"도착했습니다", "completed":"잠깐 살펴보기를 마쳤습니다", "unreachable":"지금 서 있는 곳에서는 그 자리로 걸어갈 수 없습니다", "expired":"오래된 이동 요청을 정리했습니다", "preempted":"새 상호작용에 맞춰 움직임을 멈췄습니다", "unknown_target":"그 지점이 없어 요청을 정리했습니다", "heading_timeout":"발을 디딜 자세가 준비되지 않아 이동을 멈췄습니다"}
			if messages.has(outcome): host.panel.set_status_message(messages[outcome]))
	_set_enabled(bool(_settings.get_value("behavior_enabled", true)))

func _set_enabled(value: bool) -> void:
	if enabled != value: cancel("disabled" if not value else "enabled")
	enabled = value
	host.autonomy.set_external_decisions(enabled)
	host.panel.set_behavior_enabled(enabled)
	if not enabled:
		host.motion.set_ambient_state("rest", 0.0)
		host.panel.set_behavior_state("스스로 행동 끔")

func _points_changed() -> void:
	cancel("points_changed")
	_settings.set_value("interest_points", points.sanitized_data())
	_refresh_at = 0.0
	_refresh_targets()
	publish_world(true)

func _user_point(id: String, kind: String) -> void:
	var result := request_intent({"kind": kind, "target_id": id}, "user")
	if bool(result.get("accepted", false)):
		points.set_markers_visible(false)
		host._set_panel_open(false)
		host.panel.set_status_message("대화가 끝나고 자리가 안정되면 " + ("걸어갑니다" if kind == "move_to" else "살펴봅니다"))
	else:
		host.panel.set_status_message("요청할 수 없습니다: " + str(result.get("reason", "")))

func request_intent(intent: Dictionary, source: String = "user", id: String = "") -> Dictionary:
	if not enabled: return {"accepted": false, "reason": "behavior_disabled"}
	_refresh_targets()
	if id.is_empty():
		_request_counter += 1
		id = "%s:%d:%d" % [source, Time.get_ticks_msec(), _request_counter]
	if str(intent.get("kind", "")) == "furniture":
		return host.objects.request_intent(intent,source,id) if host.objects != null else {"accepted":false,"reason":"furniture_unavailable"}
	if str(intent.get("kind", "")) == "change_appearance":
		return host.request_avatar_variant(str(intent.get("variant_id","")),id,source) if host.has_method("request_avatar_variant") else {"accepted":false,"reason":"appearance_unavailable"}
	if intent.has("locomotion_id") and not intent.locomotion_id is String:
		return {"accepted":false,"reason":"invalid_locomotion"}
	var locomotion_id := str(intent.get("locomotion_id",""))
	if not locomotion_id.is_empty() and (str(intent.get("kind","")) != "move_to" or not is_locomotion_available(locomotion_id)):
		return {"accepted":false,"reason":"unknown_locomotion"}
	if source == "user" and not id.begins_with("object-use:") and host.objects != null:
		host.objects.cancel_commands("superseded")
	if str(intent.get("kind","")) == "move_to" and not scene_interests.has_target(str(intent.get("target_id",""))) and host.get("scene_navigation") != null and host.scene_navigation.ground_latched:
		host.scene_navigation.release_to_contact("superseded")
	return director.request_intent(id, str(intent.get("kind", "")), str(intent.get("target_id", "")), source,
		30.0, float(intent.get("duration_s", 6.0)), host.session.character_id, locomotion_id)

func observe_interest(id: String, point: Vector2, confidence: float = 0.5, ttl: float = 30.0, kind: String = "point", label: String = "") -> void:
	if not InterestPoints.is_valid_id(id) or not point.is_finite() or not is_finite(ttl) or ttl <= 0: return
	if id.begins_with("support:") or points.has_point(id): return
	if not _external.has(id) and _external.size() >= 16:
		var oldest: String = _external.keys()[0]
		for key in _external:
			if float(_external[key].expires) < float(_external[oldest].expires): oldest = key
		_external.erase(oldest)
	_external[id] = {"id":id,"point":point,"confidence":confidence,"expires":_clock + minf(ttl,120.0),"kind":kind,"label":label if not label.is_empty() else id}
	_refresh_at = 0.0

func _refresh_targets() -> void:
	if host == null: return
	if _character != host.session.character_id:
		cancel("character_changed")
		_character = host.session.character_id
		director.set_character(_character)
		_style_fingerprint = ""
		_motion_profile_fingerprint = ""
		_idle_action_index = 0
		_idle_action_next = _clock + 20.0
		_known.clear()
		_external.clear()
		_published = ""
	# A saved character can be selected before its catalogue arrives. Reapply
	# profile settings on catalogue/reconnect changes even if its ID stayed equal.
	var profile: Dictionary = host.session.character_by_id(_character)
	var style: Dictionary = profile.get("behavior_style", {})
	var style_key := JSON.stringify(style)
	if style_key != _style_fingerprint:
		director.configure_style(style)
		_style_fingerprint = style_key
	var motion_key := JSON.stringify([profile.get("ambient_loop", ""), profile.get("idle_actions", [])])
	if motion_key != _motion_profile_fingerprint:
		_motion_profile_fingerprint = motion_key
		_idle_action_next = _clock + maxf(20.0, float(director.style.idle_interval_s) * 1.5)
		if host.has_method("_apply_ambient_idle"):
			host._apply_ambient_idle()
	var available: Array = []
	for p in points.points():
		if points.reachable(str(p.id)):
			available.append({"id":p.id,"point":Vector2(p.x,p.y),"kind":p.kind,"label":p.label,"confidence":0.85})
	if _scene_exploration_enabled():
		available.append_array(scene_interests.refresh(host))
	else:
		scene_interests.clear()
		available.append_array(host.autonomy.available_surface_targets())
	for id in _external.keys():
		if float(_external[id].expires) <= _clock: _external.erase(id)
		else: available.append(_external[id])
	var fresh := {}
	for p in available:
		if fresh.size() >= 16: break
		var id := str(p.id)
		fresh[id] = p
		var kind := str(p.get("kind", "point"))
		if kind not in ["window", "floor", "surface", "point", "prop", "pointer"]: kind = "point"
		director.observe_interest(id, Vector2(p.point), float(p.get("confidence", 0.65)), 30.0, kind, str(p.get("label", id)))
	for id in _known:
		if not fresh.has(id): director.remove_interest(id)
	_known = fresh
	_refresh_at = _clock + 0.5

func is_locomotion_available(id: String) -> bool:
	return host != null and host._vrma_loaded.has(id) and bool(host._vrma_loaded[id].get("locomotion",false)) and bool(host._vrma_loaded[id].get("loop",false)) and host.motion.locomotion_clips.has(id)

func locomotion_catalog() -> Array:
	var result: Array = []
	var ids: Array = host._vrma_loaded.keys()
	ids.sort()
	var pattern := RegEx.create_from_string("^[a-z0-9][a-z0-9_-]{0,31}$")
	for id in ids:
		if result.size() >= 32: break
		if not is_locomotion_available(str(id)) or pattern.search(str(id)) == null: continue
		var description := str(host._vrma_loaded[id].get("description",host._vrma_loaded[id].get("label",id))).left(240).replace("\n"," ").replace("\r"," ").replace("\t"," ")
		result.append({"id":id,"description":description})
	return result

func publish_world(force: bool = false) -> void:
	if host.client.state != "open" or not host.session.hello_received or not bool(host.session.capabilities.get("world_context", false)): return
	if host._selection_announced != host.session.character_id: return
	if force: _refresh_targets()
	var entries: Array = director.interest_catalogue() if enabled else []
	if host.objects != null:
		for entry in entries:
			if entry.get("kind","") == "prop" and str(entry.id).begins_with("object:"):
				var record: Dictionary = host.objects.store.get_object(str(entry.id).trim_prefix("object:"))
				if not record.is_empty() and str(record.type) in host.objects.furniture_types(): entry["object_type"] = str(record.type)
	entries.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var furniture: Array = host.objects.furniture_catalog() if enabled and host.objects != null else []
	var locomotion := locomotion_catalog() if enabled else []
	var appearance_supported: bool = enabled and host.has_method("request_avatar_variant")
	var active_variant: String = host.active_avatar_variant() if appearance_supported and host.has_method("active_avatar_variant") else "default"
	var fingerprint: String = JSON.stringify([entries,furniture,locomotion,appearance_supported,active_variant]) + str(host.session.character_id)
	if not force and fingerprint == _published and _clock < _publish_at: return
	if host.client.send({"type":"world_context","character_id":host.session.character_id,"interests":entries,"furniture_catalog":furniture,"locomotion_catalog":locomotion,"appearance_supported":appearance_supported,"active_variant_id":active_variant}):
		_published = fingerprint
		_publish_at = _clock + 20.0

func _event(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type in ["hello", "character_selected", "reset"]:
		_refresh_targets()
		publish_world(true)
	elif type == "done" and not bool(event.get("ok", true)):
		if host.has_method("cancel_avatar_variant"): host.cancel_avatar_variant(str(event.get("turn_id",""))+":intent","failed","turn_failed")
		director.cancel_intent(str(event.get("turn_id", "")) + ":intent", "failed")
		if host.objects != null: host.objects.cancel_commands("failed",str(event.get("turn_id", "")) + ":intent")
	elif type in ["action", "done"] and typeof(event.get("intent")) == TYPE_DICTIONARY:
		var intent_id := str(event.get("turn_id", "")) + ":intent"
		var accepted := request_intent(event.intent, "llm", intent_id)
		if not accepted.get("accepted",false) and accepted.get("reason","") != "duplicate" and not accepted.get("feedback_sent",false): object_command_result(intent_id,"rejected")
	elif type in ["error", "cancelled"]:
		if host.has_method("cancel_avatar_variant"): host.cancel_avatar_variant(str(event.get("turn_id",""))+":intent","failed" if type == "error" else "cancelled","turn_failed" if type == "error" else "turn_cancelled")
		director.cancel_intent(str(event.get("turn_id", "")) + ":intent", type)
		if host.objects != null: host.objects.cancel_commands(type,str(event.get("turn_id", "")) + ":intent")

func cancel(reason: String = "cancelled") -> void:
	# The appearance loader itself clears locomotion with avatar_changed;
	# every external cancellation must also revoke its pending/deferred load.
	if reason != "avatar_changed" and host != null and host.has_method("cancel_avatar_variant"):
		host.cancel_avatar_variant("","interrupted" if reason == "disconnected" else "cancelled","disconnected" if reason == "disconnected" else "behavior_cancelled")
	selected_locomotion_id = ""
	director.cancel_all(reason)
	if host != null:
		if host.get("scene_navigation") != null: host.scene_navigation.cancel(reason)
		if host.objects != null: host.objects.cancel_commands(reason)
		host.autonomy.cancel_target(reason)
		host.motion.finish_locomotion()
		host.motion.cancel_heading()
		host.motion.set_locomotion_sample(Vector2.ZERO, Vector2.ZERO, maxf(host._px_per_m * host.pet_scale(), 1.0), false)

func tick(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	var wanted := bool(_settings.get_value("behavior_enabled", true))
	if wanted != enabled: _set_enabled(wanted)
	if _clock >= _refresh_at: _refresh_targets()
	publish_world()
	# Foreground ownership applies even when autonomous decisions are disabled.
	if host.motion.has_method("set_ambient_suspended"):
		var working: bool = not host.session.job.is_empty() and str(host.session.job.get("status", "")) not in host.session.JOB_TERMINAL
		host.motion.set_ambient_suspended(host.audio.voice_active or host.mic.is_recording() or host.session.is_foreground_busy() or working or host._drag_active or is_marker_dragging() or host.motion._preview or host.motion._custom_motion or host.autonomy.state in ["anticipate", "walk", "arrive", "approach"])
	if not enabled:
		if host.motion.has_method("set_ambient_attention_override"):
			host.motion.set_ambient_attention_override(host.panel_open or host.audio.voice_active or host.mic.is_recording() or host.session.is_foreground_busy())
		return
	var pointer := Vector2(DisplayServer.mouse_get_position())
	var near: bool = host.pet_rect.grow(100.0).has_point(pointer - Vector2(host.get_window().position))
	var job_active: bool = not host.session.job.is_empty() and str(host.session.job.get("status", "")) not in host.session.JOB_TERMINAL
	var speaking: bool = host.audio.voice_active
	var listening: bool = host.mic.is_recording()
	var thinking: bool = host.session.is_foreground_busy() and not speaking
	if _scene_exploration_enabled() and not host.scene_navigation.holding and host.autonomy.can_request_move():
		host.scene_navigation.adopt_ground_placement()
	var scene_moving:bool=host.get("scene_navigation") != null and host.scene_navigation.navigation.active
	var scene_ground:bool=host.get("scene_navigation") != null and host.scene_navigation.ground_latched
	var furniture_busy:bool=host.objects != null and not host.objects._interaction.is_empty()
	var can_move: bool = (scene_ground or host.autonomy.can_request_move()) and not host.bridge.dialogue_holding(host._now()) and not host.is_sitting() and not scene_moving and (not furniture_busy or _owns_legacy_furniture_approach())
	last_output = director.tick(delta, {"character_id":host.session.character_id,"panel_open":host.panel_open,
		"dragging":host._drag_active or is_marker_dragging(),"speaking":speaking,"listening":listening,"thinking":thinking,"working":job_active,
		"pointer_interaction":host.autonomy._pointer_interaction,"can_move":can_move,
		"autonomy_enabled":host.autonomy.enabled,"autonomy_state":"walk" if scene_moving else ("rest" if scene_ground else host.autonomy.state),
		"moving":scene_moving or host.autonomy.state == "walk", "pointer_point":pointer,
		"actor_point":Vector2(host.get_window().position) + host.pet_rect.get_center(),
		"preview_active":host.motion._preview or host.motion._custom_motion,
		"dialogue_gesture_active":host._dialogue_gesture_active()})
	var action: Dictionary = last_output.get("action", {})
	match str(action.get("type", "")):
		"move_interest":
			var requested := str(action.get("locomotion_id",""))
			if not requested.is_empty() and not is_locomotion_available(requested):
				director.resolve_intent(str(action.id),"locomotion_revoked")
				return
			if scene_interests.has_target(str(action.target_id)) and _scene_exploration_enabled():
				var target_id:=str(action.target_id)
				var callback:=func(outcome:String):
					selected_locomotion_id=""
					director.navigation_result(target_id,outcome)
				var result:Dictionary=host.scene_navigation.request_owned(scene_interests.world_target(target_id),host.objects.scene_obstacle_bounds(),callback)
				selected_locomotion_id=requested if result.get("accepted",false) else ""
				director.resolve_intent(str(action.id),"started" if result.get("accepted",false) else str(result.get("reason","unreachable")))
				return
			host.autonomy.observe_interest(str(action.target_id), Vector2(action.point), 1.0, float(action.ttl), str(action.kind))
			var accepted: bool = host.autonomy.move_to_interest(str(action.target_id))
			# move_to_interest synchronously finishes its previous native target.
			# Install the new selection after those old terminal callbacks return.
			selected_locomotion_id = requested if accepted and host.autonomy.last_request_outcome == "started" else ""
			director.resolve_intent(str(action.id), "started" if accepted else host.autonomy.last_request_outcome)
			if not accepted: selected_locomotion_id = ""
		"cancel_move":
			if host.get("scene_navigation") != null and host.scene_navigation.has_completion_owner():host.scene_navigation.cancel(str(action.get("reason","cancelled")))
			selected_locomotion_id = ""
			host.autonomy.cancel_target(str(action.get("reason", "cancelled")), Vector2(action.get("replacement_point", Vector2.INF)))
	# User attention is brief and has a refractory period, rather than cursor tracking forever.
	_look = Vector2(last_output.get("attention_point", Vector2.INF))
	if speaking or listening or thinking or host._drag_active:
		_look = pointer if near else Vector2.INF
	elif near and _clock >= _pointer_next and (not _pointer_seen.is_finite() or pointer.distance_to(_pointer_seen) > 30.0):
		_pointer_seen = pointer
		_attention_until = _clock + float(director.style.gaze_hold_s)
		_pointer_next = _attention_until + 5.0
	elif _clock < _attention_until:
		_look = _pointer_seen
	var state := str(last_output.get("state", "rest"))
	if state != _last_state:
		if state in ["listening", "thinking", "speaking", "attentive"] and _last_state not in ["listening", "thinking", "speaking", "attentive"] and not host._drag_active and not host.motion._preview:
			host.motion.face_front()
		_last_state = state
		host.panel.set_behavior_state(str(LABELS.get(state, state)))
	host.motion.set_ambient_state(str(last_output.get("ambient", "rest")), float(last_output.get("strength", 0.5)))
	if host.motion.has_method("set_ambient_attention_override"):
		host.motion.set_ambient_attention_override(_look.is_finite() or speaking or listening or thinking or host.panel_open)
	_maybe_idle_action(state)

func _maybe_idle_action(state: String) -> void:
	if str(_settings.get_value("idle_clip", "auto")) != "auto": return
	if _clock < _idle_action_next or state not in ["rest", "sleepy"] or _look.is_finite(): return
	if host.autonomy.state not in ["rest", "inspect"] or host._dialogue_gesture_active() or not host.motion.heading_ready(): return
	if not host.motion.has_method("play_ambient_action"): return
	var actions: Variant = host.session.character_by_id(host.session.character_id).get("idle_actions", [])
	var available: Array[String] = []
	if actions is Array:
		for name in actions:
			if name is String and host._vrma_loaded.has(name) and not available.has(name): available.append(name)
	_idle_action_next = _clock + maxf(20.0, float(director.style.idle_interval_s) * 1.5)
	if available.is_empty(): return
	var name := available[_idle_action_index % available.size()]
	if host.motion.play_ambient_action(name):
		_idle_action_index += 1

func apply_attention() -> bool:
	if not enabled: return false
	if _look.is_finite() and host.avatar.has_model():
		var head: Vector2 = host.camera.unproject_position(host.avatar.bone_global_position("head"))
		var delta := (_look - Vector2(host.get_window().position) - head) / 320.0
		# Navigation destinations are floor/seat coordinates, not eye-level targets.
		# Look ahead during travel; explicit stationary inspection retains its height.
		if host.autonomy.state in ["anticipate", "walk", "arrive"] and not host.is_sitting():
			delta.y = 0.0
		host.motion.gaze_target = Vector2(0.5 - clampf(delta.x,-1,1)*0.5, 0.45 + clampf(delta.y,-1,1)*0.5)
		host.motion.gaze_has_target = true
	else:
		host.motion.gaze_target = Vector2(0.5, 0.45)
		host.motion.gaze_has_target = true # neutral stable gaze between deliberate looks
	return true

func _frame_moved(displacement: Vector2, velocity: Vector2) -> void:
	if host.get("scene_navigation") != null and host.scene_navigation.owns_foot():return
	var supported: bool = bool(host.autonomy.get_support_contact().get("attached", false)) and not host.is_sitting() and host.autonomy.state in ["anticipate", "walk", "arrive"] and not host._dialogue_gesture_active()
	var world_delta: Variant = null
	if host.avatar.has_model():
		var placement_delta: Variant = host.take_projection_world_delta()
		if host.spatial_camera() != null:
			# A moved perspective crop changes the avatar's canonical world
			# placement. Measure that change once before correcting cached feet.
			if placement_delta is Vector3:
				world_delta = placement_delta
			else:
				var local_foot: Vector3 = host._pivot_local.get("foot", Vector3.ZERO)
				var before: Vector3 = host.avatar.global_transform * local_foot
				host._update_avatar_transform(0.0)
				world_delta = host.avatar.global_transform * local_foot - before
		else:
			# Orthographic windows carry their local scene with the OS origin;
			# convert the desktop displacement through the actual tilted camera.
			world_delta = DesktopView.screen_delta_to_world(host.camera, displacement, host._camera_pivot_depth)
			if placement_delta is Vector3: world_delta += placement_delta
	host.motion.set_locomotion_sample(velocity, displacement, maxf(host._px_per_m * host.pet_scale(), 1.0), supported, world_delta)

func _navigation_finished(target_id: String, outcome: String) -> void:
	selected_locomotion_id = ""
	if outcome == "heading_timeout":
		host.motion.cancel_heading()
	director.navigation_result(target_id, outcome)

func is_marker_dragging() -> bool:
	if points == null: return false
	for p in points.points():
		var marker := points.marker_for(str(p.id))
		if marker != null and bool(marker.get("dragging")): return true
	return false

## Terminal execution feedback is attached to future user turns; it never calls a model.
func object_command_result(id: String, outcome: String) -> void:
	if not id.ends_with(":intent") or host.client.state != "open": return
	var canonical := outcome
	if outcome not in ["completed","arrived","expired","cancelled","interrupted","rejected","failed"]:
		canonical = "cancelled" if outcome in ["superseded","character_changed","disabled","dragged","pet_dragged","foreground","panel_open","disconnected","shutdown"] else "failed"
	var reason := ""
	for character in outcome:
		if character in "abcdefghijklmnopqrstuvwxyz_": reason += character
	host.client.send({"type":"intent_result","character_id":host.session.character_id,"intent_id":id,"outcome":canonical,"reason":reason.left(64)})

func _scene_exploration_enabled() -> bool:
	if not enabled or not host.autonomy.surface_mode or _settings == null or not bool(_settings.get_value("scene_exploration_enabled",true)) or host.get("scene_navigation") == null or host.spatial_camera()==null:return false
	# Explicit desktop window/taskbar support remains a separate movement mode.
	var contact:Dictionary=host.autonomy.get_support_contact()
	return str(contact.get("surface_id","")).begins_with("floor:") or host.scene_navigation.ground_latched

## Furniture's own legacy support approach is still a Director command. Its
## ownership must not block itself, nor grant movement to an unrelated request.
func _owns_legacy_furniture_approach() -> bool:
	if host.objects == null:return false
	var interaction:Dictionary=host.objects._interaction
	if interaction.get("stage","") != "approaching":return false
	var id:=str(interaction.get("request_id",""))
	if id.is_empty():return false
	if not director._active.is_empty():return str(director._active.id)==id
	if director._queue.is_empty():return false
	return director._queue.all(func(entry):return str(entry.id)==id)
