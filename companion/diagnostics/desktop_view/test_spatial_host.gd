extends SceneTree
const ObjHost = preload("res://scripts/desktop_objects_host.gd")
const ObjWindow = preload("res://scripts/desktop_object_window.gd")
const View = preload("res://scripts/desktop_view.gd")
class Host extends Node3D:
	var camera: Camera3D
	var _px_per_m := 217.28
	var _camera_pivot_depth := 5.0
	func spatial_camera() -> Camera3D: return camera
	func spatial_desktop_origin() -> Vector2: return Vector2(-1920,0)
class Objects extends ObjHost:
	func _after_change() -> void: pass
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600,900)
	var h := Host.new()
	root.add_child(h)
	h.camera = Camera3D.new()
	h.add_child(h.camera)
	h.camera.position = Vector3(0,1,5)
	View.configure_projection(h.camera,"perspective",3,45)
	var objects := Objects.new()
	h.add_child(objects)
	objects.host = h
	objects._screen_provider = func(): return [Rect2i(-1920,0,1600,900)]
	var record := {"id":"obj_1","type":"chair","label":"Chair","x":-1220,"y":400,"scale":1.0,"visible":true,"yaw_deg":0.0,"appearance":"default"}
	objects.store.set_data({"version":1,"next_id":2,"objects":[record]})
	var window := ObjWindow.new()
	objects.add_child(window)
	check(window.configure(record,Vector2i(220,280)),"load chair")
	objects.windows["obj_1"] = window
	await process_frame
	check(objects._sync_spatial_window("obj_1"),"migrate old screen pose into canonical frame")
	var migrated := objects.store.data()
	var world := window._scene.transform
	check(objects.store.get_object("obj_1").has("spatial_unit_scale"),"migration factor persisted")
	h.camera.fov = 55
	h.camera.position.z = 6
	h._px_per_m = 999 # deliberately change projection calibration after migration
	check(objects._sync_spatial_window("obj_1"),"lens/distance change reprojects")
	check(window._scene.transform.is_equal_approx(world),"lens cannot rescale or move world geometry")
	check(objects.store.data()==migrated,"lens cannot rewrite canonical data")
	var reloaded := ObjHost.Store.new()
	reloaded.set_data(JSON.parse_string(JSON.stringify(migrated)))
	var loaded := reloaded.get_object("obj_1")
	var saved := objects.store.get_object("obj_1")
	check(absf(loaded.spatial_unit_scale-saved.spatial_unit_scale)<1e-12 and Vector3(loaded.position_m.x,loaded.position_m.y,loaded.position_m.z).distance_to(Vector3(saved.position_m.x,saved.position_m.y,saved.position_m.z))<1e-9,"migration factor and position survive JSON reload")
	check(not objects.configure_spatial_position("obj_1",Vector3(0,0,10)),"behind-eye configuration rejected")
	check(objects.store.data()==migrated,"failed spatial edit rolls back position and factor")
	objects.windows.clear();window.free();objects.host=null;h.free()
	print(JSON.stringify({"checks":checks,"failures":failures,"scope":"Host canonical migration and rollback, actual imported chair geometry, headless"}))
	quit(1 if failures else 0)
