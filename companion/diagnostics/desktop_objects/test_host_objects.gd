extends "res://tools/probe_host_lifecycle.gd"
class Objects:
	extends DesktopObjectsHost
	func native_available() -> bool: return true
	func _sync_windows() -> void: pass
class FacingObjects:
	extends Objects
	func _fit_contact_view(_preserve_seat: bool = false) -> bool: return true
	func _activate_contact_scene(_id: String) -> bool:
		_contact_id = _id
		_contact_scene = ContactScene.new()
		add_child(_contact_scene)
		_contact_scene.loaded = true
		return true
	func _update_contact_transform() -> void: pass
	func _release_contact_scene() -> void:
		if is_instance_valid(_contact_scene): _contact_scene.free()
		_contact_scene = null
	func contact_socket_screen(_socket: String) -> Vector2: return Vector2(810,850)
	func _begin_seat(_id: String,_point: Vector2) -> void: _interaction.stage="using"
class FacingMotion:
	extends Motion
	var facing_ready := false
	var fronts := 0
	func face_front() -> void:
		fronts += 1
		_heading_pending = true
	func heading_ready() -> bool: return facing_ready
	func set_contact_heading(_yaw: float) -> bool:
		fronts += 1
		_heading_pending = true
		return true
class Furniture:
	extends Node
	var _scene:Node3D
	var visible := true
	var loaded := true
	var dragging := false
	var error := ""
	func socket_point(socket: String) -> Vector2: return Vector2(810,850) if socket == "seat" else Vector2(810,800)
	func seat_surface() -> Dictionary: return {"id":"object:obj_1:seat","x1":790,"x2":830,"y":850}
	func socket_catalogue() -> Dictionary: return {"seat":socket_point("seat"),"inspect":socket_point("inspect")}
	func set_editable(_value: bool) -> void: pass
	func hide() -> void: visible = false
class Living:
	extends Node
	var enabled := true
	var director := BehaviorDirector.new()
	var _external := {}
	var _look := Vector2.INF
	func is_marker_dragging() -> bool: return false
	func cancel(reason: String) -> void: director.cancel_all(reason)
	func observe_interest(id,point,confidence,ttl,kind,label):
		_external[id] = point
		director.observe_interest(id,point,confidence,ttl,kind,label)
	func request_intent(intent,source="user",id="test") -> Dictionary:
		return director.request_intent(id,intent.kind,intent.get("target_id",""),source)
class Values:
	extends Node
	var data := {}
	func set_value(key,value): data[key]=value
	func get_value(key,fallback=null): return data.get(key,fallback)
func fixture(facing_test := false):
	var h := make_host()
	h.motion.avatar = h.avatar
	h.living = Living.new()
	h.add_child(h.living)
	h.objects = FacingObjects.new() if facing_test else Objects.new()
	h.add_child(h.objects)
	h.objects.host = h
	h.objects._last_character = h.session.character_id
	h.panel_open = false
	h.objects._settings = Values.new()
	h.objects.add_child(h.objects._settings)
	h.objects._screen_provider = func():return [Rect2i(0,0,1920,1040)]
	h.objects.store.set_data({"version":1,"objects":[{"id":"obj_1","type":"chair","label":"의자","x":600,"y":620,"scale":1.4,"visible":true}]})
	var window := Furniture.new()
	h.objects.add_child(window)
	h.objects.windows["obj_1"] = window
	h.autonomy.set_surface_mode(true)
	h.autonomy.update_context(false,false,false,false,false)
	h.objects._refresh_adapters()
	return h
func own_test_seat(h) -> void:
	h._sit_active = true
	h._sit_attached = true
	h.motion.contact = "sit"
	h.autonomy.contact_pose = "sit"
	h.autonomy._support={"id":"object:obj_1:seat","kind":"object_seat","x1":790.0,"x2":830.0,"y":850.0,"anchor_only":true}
	h.autonomy._locked_anchor=Vector2(810,850)

func _run() -> void:
	host_script = GDScript.new()
	host_script.source_code = 'extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\nfunc _projected_anchors()->Dictionary:\n\treturn {"foot":Vector2(510,680),"sit":Vector2(510,500)}\n'
	if host_script.reload()!=OK: quit(1);return
	var h=fixture()
	check(h.living.director.interest_catalogue().size()==1,"visible object enters reusable curiosity catalogue")
	check(h.autonomy._seat_surfaces.has("object:obj_1:seat"),"actual narrow seat adapter registered separately from walking surfaces")
	check(h.objects.interact("obj_1","sit").accepted,"explicit chair interaction queues")
	h._cancel_current()
	check(h.objects._interaction.is_empty(),"actual main user cancel clears waiting object interaction")
	h.free()
	for trigger in ["behavior_off","autonomy_off","surface_off","pet_drag","character","hidden","removed","resize","moved"]:
		h=fixture()
		h.objects._interaction={"id":"obj_1","verb":"sit","stage":"seated","expires":65.0,"character":""}
		h._sit_active=true
		h._sit_attached=true
		h.motion.contact="sit"
		match trigger:
			"behavior_off":h.living.enabled=false
			"autonomy_off":h.autonomy.set_enabled(false)
			"surface_off":h.autonomy.set_surface_mode(false)
			"pet_drag":h._drag_active=true
			"character":h.session.character_id="new"
			"hidden":h.objects.set_object_visible("obj_1",false)
			"removed":h.objects.remove_object("obj_1")
			"resize":h.objects.resize_object("obj_1",1.2)
			"moved":h.objects.move_object("obj_1",Vector2i(500,600))
		h.objects.tick(0.1)
		check(h.objects._interaction.is_empty() and not h._sit_active and not h._sit_attached,"occupied-seat lifecycle releases on "+trigger)
		h.free()
	for trigger in ["voice","mic","job"]:
		h=fixture()
		h.objects._interaction={"id":"obj_1","verb":"use","stage":"using","expires":65.0,"until":10.0,"character":""}
		own_test_seat(h)
		check(h.objects._owns_seat_contact("obj_1"),"work yield fixture begins on correct owned seat: "+trigger)
		if trigger=="voice":h.audio.voice_active=true
		if trigger=="mic":h.mic._recording=true
		if trigger=="job":h.session.job={"status":"running"}
		h.objects.tick(0.1)
		check(h.objects._interaction.is_empty() and not h.objects.blocks_roaming(),"work contact yields to "+trigger)
		h.free()
	for stage in ["seating","seated","using"]:
		h=fixture()
		own_test_seat(h)
		h.autonomy._support.id="window:unrelated"
		h.autonomy._support.kind="window"
		h.objects._refresh_at=100.0
		h.objects._interaction={"id":"obj_1","verb":"use","stage":stage,"expires":65.0,"until":10.0}
		h.objects.tick(0.1)
		check(h.objects._interaction.is_empty() and not h.is_sitting(),"wrong surface never becomes successful object contact: "+stage)
		h.free()
	h=fixture(true)
	h.motion.free()
	h.motion = FacingMotion.new()
	h.add_child(h.motion)
	h.motion.avatar = h.avatar
	h.autonomy.state_changed.connect(func(state):
		if state in ["paused","settle"]: h.motion.cancel_heading())
	h.autonomy._support = {"id":"floor","kind":"floor","x1":0.0,"x2":1920.0,"y":1040.0}
	h.autonomy._settle_until = 0.0
	h.objects._refresh_at = 100.0
	h.objects._interaction={"id":"obj_1","verb":"use","stage":"ready","expires":65.0,"character":h.session.character_id}
	h.objects.tick(0.01)
	check(h.objects._interaction.get("stage") == "facing" and h.motion.fronts == 1 and h.motion._heading_pending,"facing begins after paused callback without cancelling heading")
	check(h.objects.blocks_roaming() and not h.autonomy.can_request_move(),"facing holds autonomous travel")
	h.objects.tick(0.01)
	check(h.objects._interaction.get("stage") == "facing" and h.motion.fronts == 1,"unready heading stays facing without restarting")
	h.motion.facing_ready = true
	h.objects.tick(0.01)
	check(h.objects._interaction.get("stage") == "using","ready heading enters work despite held autonomy")
	h.objects.cancel_interaction()
	h.objects._interaction={"id":"obj_1","verb":"use","stage":"facing","expires":65.0,"facing_until":10.0,"character":h.session.character_id}
	h.audio.voice_active = true
	h.objects.tick(0.01)
	check(h.objects._interaction.is_empty(),"speech cancels facing so cancelled heading cannot falsely admit sideways contact")
	h.audio.voice_active = false
	h.objects._interaction={"id":"obj_1","verb":"use","stage":"facing","expires":65.0,"facing_until":0.0,"character":h.session.character_id}
	h.objects.tick(0.01)
	check(h.objects._interaction.is_empty(),"facing has bounded timeout")
	h.free()
	h=fixture()
	var original_position := root.position
	root.size = Vector2i(680,760)
	h.camera = Camera3D.new()
	h.add_child(h.camera)
	h.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	h.camera.size = 3.0
	h.camera.position = Vector3(0,1,3)
	h._camera_base = h.camera.position
	h._px_per_m = 760.0/3.0
	h.objects._contact_scene = load("res://scripts/desktop_object_contact_scene.gd").new()
	h.add_child(h.objects._contact_scene)
	h.objects._contact_scene.configure("chair")
	h.objects._contact_id = "obj_1"
	h.objects._contact_floor = Vector2(500,900)
	h.objects._contact_scale = 0.6
	h.objects._update_contact_transform()
	var before: Vector2 = h.objects.contact_socket_screen("seat")
	root.position += Vector2i(27,13)
	h.objects._on_frame_moved(Vector2(27,13),Vector2(60,0))
	check(h.objects.contact_socket_screen("seat").distance_to(before)<0.001,"postcommit callback keeps shared furniture fixed on desktop in same rendered frame")
	h.objects._contact_scale = 10.0
	h.objects._update_contact_transform()
	check(not h.objects._fit_contact_view(),"oversized full shared arrangement is rejected instead of clipped")
	h.objects._contact_scene.free()
	h.objects._contact_scene = null
	h.objects._contact_id = ""
	h.free()
	root.position = original_position
	h=fixture()
	h.objects.rename_object("obj_1","새 의자")
	check(h.objects._settings.data.desktop_objects.objects[0].label=="새 의자","mutations persist through settings owner")
	h.objects.shutdown()
	h.objects.shutdown()
	check(h.objects.windows.is_empty() and h.autonomy._seat_surfaces.is_empty(),"shutdown idempotently removes windows and seat geometry")
	h.free()
	print("Object host: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
