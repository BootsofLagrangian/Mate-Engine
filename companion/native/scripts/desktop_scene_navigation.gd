class_name DesktopSceneNavigation
extends RefCounted
## True world X/Z navigation. Godot's navigation server owns route finding;
## callers commit the returned world foot position through the shared camera.
## Furniture obstacles are conservative solid AABBs, expanded by actor radius.
signal finished(request_id: String, outcome: String)
const MAX_OBSTACLES := 96
const MAX_CELLS := 16384
var position_world := Vector3.ZERO
var active := false
var request_id := ""
var path := PackedVector3Array()
var diagnostics: Dictionary = {}
var speed_mps := 0.35
var acceleration_mps2 := 0.8
var lookahead_m := 0.18
var _map := RID()
var _region := RID()
var _mesh: NavigationMesh
var _bounds := Rect2()
var _ground_y := 0.0
var _obstacles: Array[Rect2] = []
var _index := 1
var _speed := 0.0
var _elapsed := 0.0
var _timeout := 0.0
var _heading := 0.0
var _ready := false

func configure(bounds_xz: Rect2, ground_y: float, obstacle_solids: Array = [],
		actor_radius_m: float = 0.12, actor_height_m: float = 1.6, cell_size_m: float = 0.08) -> Dictionary:
	if not bounds_xz.position.is_finite() or not bounds_xz.size.is_finite() or not is_finite(ground_y) or not is_finite(actor_radius_m) or not is_finite(actor_height_m) or not is_finite(cell_size_m):
		return {"ok":false,"reason":"nonfinite_geometry"}
	if actor_radius_m < 0 or actor_radius_m > 1 or actor_height_m <= 0 or actor_height_m > 4 or cell_size_m < 0.02 or cell_size_m > 0.3 or obstacle_solids.size() > MAX_OBSTACLES:
		return {"ok":false,"reason":"invalid_geometry"}
	var bounds := bounds_xz.grow(-actor_radius_m)
	if bounds.size.x < cell_size_m or bounds.size.y < cell_size_m or bounds.size.x > 20 or bounds.size.y > 20:
		return {"ok":false,"reason":"invalid_bounds"}
	var nx := int(ceil(bounds.size.x/cell_size_m))
	var nz := int(ceil(bounds.size.y/cell_size_m))
	if nx*nz > MAX_CELLS: return {"ok":false,"reason":"grid_too_dense"}
	var solids: Array[Rect2] = []
	for value in obstacle_solids:
		if not value is AABB or not value.position.is_finite() or not value.size.is_finite() or value.size.x < 0 or value.size.y < 0 or value.size.z < 0:
			return {"ok":false,"reason":"invalid_obstacle"}
		var box: AABB = value
		if box.end.y <= ground_y or box.position.y >= ground_y+actor_height_m: continue
		solids.append(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(actor_radius_m))
	cancel("geometry_changed")
	_dispose_map()
	_bounds = bounds
	_ground_y = ground_y
	_obstacles = solids
	_mesh = NavigationMesh.new()
	_mesh.cell_size = cell_size_m
	_mesh.cell_height = 0.01
	var vertices := PackedVector3Array()
	var dx := bounds.size.x/nx
	var dz := bounds.size.y/nz
	for z in nz+1:
		for x in nx+1:
			vertices.append(Vector3(bounds.position.x+x*dx,ground_y,bounds.position.y+z*dz))
	_mesh.vertices = vertices
	var kept := 0
	for z in nz:
		for x in nx:
			var cell := Rect2(bounds.position+Vector2(x*dx,z*dz),Vector2(dx,dz))
			var blocked := false
			for solid in solids:
				if cell.intersects(solid,true): blocked = true; break
			if blocked: continue
			var a := z*(nx+1)+x
			_mesh.add_polygon(PackedInt32Array([a,a+nx+1,a+nx+2,a+1]))
			kept += 1
	if kept == 0:
		diagnostics = {"reason":"no_free_ground","cells":nx*nz,"polygons":0}
		return {"ok":false,"reason":"no_free_ground"}
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(_map,false)
	NavigationServer3D.map_set_up(_map,Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map,cell_size_m)
	NavigationServer3D.map_set_cell_height(_map,0.01)
	NavigationServer3D.map_set_active(_map,true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(_region,false)
	NavigationServer3D.region_set_navigation_mesh(_region,_mesh)
	NavigationServer3D.region_set_map(_region,_map)
	# Synchronize once when geometry changes, never once per rendered frame.
	NavigationServer3D.map_force_update(_map)
	_ready = true
	diagnostics = {"cells":nx*nz,"polygons":kept,"obstacles":solids.size(),"cell_size_m":maxf(dx,dz),"ground_y":ground_y}
	return {"ok":true,"reason":"ready","polygons":kept}

func plan(id: String, start_world: Vector3, target_world: Vector3, wanted_speed_mps: float = 0.35) -> Dictionary:
	if not _ready: return {"accepted":false,"reason":"no_navigation_geometry"}
	if id.is_empty() or id.length() > 160 or not start_world.is_finite() or not target_world.is_finite() or not is_finite(wanted_speed_mps) or wanted_speed_mps < 0.03 or wanted_speed_mps > 2.0:
		return {"accepted":false,"reason":"invalid_request"}
	if absf(start_world.y-_ground_y) > 0.01 or absf(target_world.y-_ground_y) > 0.01:
		return {"accepted":false,"reason":"different_ground_plane"}
	start_world.y = _ground_y
	target_world.y = _ground_y
	if not is_navigable(start_world) or not is_navigable(target_world):
		return {"accepted":false,"reason":"blocked_endpoint"}
	var candidate := NavigationServer3D.map_get_path(_map,start_world,target_world,true)
	if candidate.is_empty() or candidate[candidate.size()-1].distance_to(target_world) > 0.01:
		return {"accepted":false,"reason":"unreachable"}
	cancel("superseded")
	request_id = id
	position_world = start_world
	path = candidate
	_index = 1
	speed_mps = wanted_speed_mps
	_speed = 0.0
	_elapsed = 0.0
	var length := _remaining_distance()
	_timeout = minf(120.0,maxf(10.0,length/wanted_speed_mps*3.0+5.0))
	active = true
	if path.size() > 1:
		var first := path[1]-position_world
		_heading = atan2(first.x,first.z)
	diagnostics["path_length_m"] = length
	diagnostics["path_points"] = path.size()
	return {"accepted":true,"reason":"started","path":path,"distance_m":length}

func tick(delta: float) -> Dictionary:
	var before := position_world
	var id := request_id
	if not active: return _frame(id,before,0.0,false,"")
	if not is_finite(delta) or delta < 0:
		cancel("invalid_delta")
		return _frame(id,before,0.0,false,"invalid_delta")
	# Long suspension cannot teleport a pet through an entire path in one frame.
	var dt := minf(delta,0.1)
	_elapsed += delta
	if _elapsed > _timeout:
		cancel("timeout")
		return _frame(id,before,0.0,false,"timeout")
	var remaining := _remaining_distance()
	var target_speed := minf(speed_mps,sqrt(maxf(0.0,2.0*acceleration_mps2*remaining)))
	_speed = move_toward(_speed,target_speed,acceleration_mps2*dt)
	var budget := minf(remaining,_speed*dt)
	var measured := budget
	while budget > 0.0000001 and _index < path.size():
		var toward := path[_index]-position_world
		var distance := toward.length()
		if distance <= budget:
			position_world = path[_index]
			_index += 1
			budget -= distance
		else:
			position_world += toward/distance*budget
			budget = 0.0
	position_world.y = _ground_y
	var look := _lookahead_point(lookahead_m)-position_world
	if look.length_squared() > 0.000001:
		_heading = lerp_angle(_heading,atan2(look.x,look.z),1-exp(-8.0*dt))
	var arrived := _remaining_distance() <= 0.00001
	if arrived:
		position_world = path[path.size()-1]
		active = false
		_speed = 0.0
		finished.emit(id,"arrived")
	return _frame(id,before,measured,arrived,"arrived" if arrived else "")

func cancel(reason: String = "cancelled") -> void:
	var was_active := active
	active = false
	_speed = 0.0
	if was_active: finished.emit(request_id,reason)

func is_navigable(point: Vector3) -> bool:
	if not _ready or not point.is_finite() or absf(point.y-_ground_y)>0.01 or not _bounds.has_point(Vector2(point.x,point.z)): return false
	for solid in _obstacles:
		if solid.has_point(Vector2(point.x,point.z)): return false
	return NavigationServer3D.map_get_closest_point(_map,point).distance_to(point) <= 0.001

func _remaining_distance() -> float:
	var result := 0.0
	var prior := position_world
	for i in range(_index,path.size()):
		result += prior.distance_to(path[i])
		prior = path[i]
	return result

func _lookahead_point(distance: float) -> Vector3:
	var prior := position_world
	for i in range(_index,path.size()):
		var span := prior.distance_to(path[i])
		if span >= distance: return prior.lerp(path[i],distance/maxf(span,0.000001))
		distance -= span
		prior = path[i]
	return prior

func _frame(id: String, before: Vector3, distance: float, arrived: bool, outcome: String) -> Dictionary:
	return {"request_id":id,"active":active,"position_world":position_world,"delta_world":position_world-before,
		"distance_m":distance,"heading_world":_heading,"speed_mps":_speed,"arrived":arrived,"outcome":outcome}

func dispose() -> void:
	cancel("disposed")
	_dispose_map()

func _dispose_map() -> void:
	_ready = false
	if _region.is_valid(): NavigationServer3D.free_rid(_region)
	if _map.is_valid(): NavigationServer3D.free_rid(_map)
	_region = RID()
	_map = RID()
	_mesh = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _region.is_valid(): NavigationServer3D.free_rid(_region)
		if _map.is_valid(): NavigationServer3D.free_rid(_map)
