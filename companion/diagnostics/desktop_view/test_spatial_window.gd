extends SceneTree
const View = preload("res://scripts/desktop_view.gd")
const Obj = preload("res://scripts/desktop_object_window.gd")
const Store = preload("res://scripts/desktop_object_store.gd")
var checks := 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600,900)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,1,5)
	View.configure_projection(camera,"perspective",3,45)
	var window := Obj.new()
	root.add_child(window)
	var record := {"id":"obj_1","type":"chair","label":"Chair","x":50,"y":80,"scale":1.0,"visible":true,"yaw_deg":30.0,"appearance":"default"}
	check(window.configure(record,Vector2i(200,300)),"load actual chair")
	await process_frame
	var origin := Vector2(-1920,0)
	var pose := Transform3D(Basis.IDENTITY,Vector3(-1,0,0))
	check(window.set_shared_projection(camera,origin,pose),"actual window shared projection")
	var seat_world: Vector3 = pose*window._sockets.seat
	check(window.socket_point("seat").distance_to(origin+camera.unproject_position(seat_world))<.02,"window socket is exact shared global pixel")
	var old_size := window.size
	pose.origin.z = -4
	check(window.set_shared_projection(camera,origin,pose),"farther pose shared projection")
	check(window.size.y < old_size.y*.7,"actual farther geometry shrinks without scale change")
	check(window._scene.scale.is_equal_approx(Vector3.ONE),"world depth never changes physical scale")
	seat_world = pose*window._sockets.seat
	check(window.socket_point("seat").distance_to(origin+camera.unproject_position(seat_world))<.02,"far socket crop exact")
	camera.basis = View.orbit_basis(20,10)
	check(window.set_shared_projection(camera,origin,pose),"view rotation reprojects same pose")
	check(window._scene.transform.is_equal_approx(pose),"view keeps canonical world pose")
	var store := Store.new()
	store.set_data({"version":1,"next_id":2,"objects":[record]})
	check(store.set_position_m("obj_1",Vector3(1,2,-3)),"set canonical pose")
	var copy := Store.new()
	copy.set_data(JSON.parse_string(JSON.stringify(store.data())))
	check(copy.get_object("obj_1").position_m=={"x":1.0,"y":2.0,"z":-3.0},"position survives JSON and reload")
	check(not store.set_position_m("obj_1",Vector3(21,0,0)),"out-of-bounds pose rejected")
	check(not Store.valid_position_m({"x":true,"y":0,"z":0}),"boolean pose rejected")
	check(not Store.valid_position_m({"x":0,"y":0,"z":0,"w":1}),"extra pose field rejected")
	window.set_shared_world(root.world_3d,root)
	check(window.world_3d==root.world_3d,"native window shares root World3D")
	var environments:=window._scene.find_children("*","WorldEnvironment",true,false)
	check(environments.size()==1 and environments[0].environment==null,"private environment disabled in shared world")
	window.show()
	check(window._model_nodes.all(func(model):return model.visible),"visible shared window models render")
	window.hide()
	check(window._model_nodes.all(func(model):return not model.visible),"hidden occupied window cannot duplicate shared model")
	window.clear_shared_projection()
	check(window.world_3d!=root.world_3d and environments[0].environment!=null,"orthographic return restores private world/environment")
	check(window._model_nodes.all(func(model):return model.visible),"orthographic return restores original model visibility")
	window.free()
	print(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual imported chair camera/geometry; headless projection only"}))
	quit(1 if failures else 0)
