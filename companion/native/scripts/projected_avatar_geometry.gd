class_name ProjectedAvatarGeometry
extends RefCounted
## Cached rest-mesh silhouette and a heading-invariant desktop envelope.
## A projected desktop edge is not a replacement for the physical world-Y sole.
const RING_SIDES := 32
var points := PackedVector3Array()
var swept := PackedVector3Array()
var model_id := 0
var source_vertex_count := 0
var _navigation_key:=[]
var _navigation_cached:=Rect2()

func capture(avatar: VrmAvatar, foot: Vector3) -> void:
	points.clear()
	swept.clear()
	source_vertex_count=0
	_navigation_key.clear()
	model_id=avatar.model.get_instance_id() if avatar.has_model() else 0
	if model_id==0:return
	var all_points:=PackedVector3Array()
	var meshes:=[]
	avatar._collect_meshes(avatar.model,meshes)
	for mesh:MeshInstance3D in meshes:
		if mesh.mesh==null:continue
		var xf:=avatar.global_transform.affine_inverse()*mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays:=mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty():continue
			for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:all_points.append(xf*vertex)
	source_vertex_count=all_points.size()
	if all_points.is_empty():return
	# A convex hull has the same projected outer silhouette as its input points,
	# without projecting tens of thousands of skin vertices every frame.
	var shape:=ConvexPolygonShape3D.new()
	shape.points=all_points
	var hull:=shape.get_debug_mesh()
	var unique:={}
	for surface in hull.get_surface_count():
		var arrays:=hull.surface_get_arrays(surface)
		for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:unique[vertex]=true
	for vertex:Vector3 in unique:points.append(vertex)
	if points.is_empty():points=all_points
	# Circumscribed rings contain every heading, rather than sampling headings
	# and missing the extrema between samples. Heights stay paired with their
	# real radial extent; unlike AABB corners no shoulder width is put at sole Y.
	var rings:={}
	for point in points:
		var offset:=point-foot
		var radius:=Vector2(offset.x,offset.z).length()/cos(PI/RING_SIDES)
		var key:=Vector2(radius,offset.y)
		if rings.has(key):continue
		rings[key]=true
		for step in RING_SIDES:
			var angle:=TAU*float(step)/RING_SIDES
			swept.append(Vector3(cos(angle)*radius,offset.y,sin(angle)*radius))

func valid_for(avatar: VrmAvatar) -> bool:
	return avatar.has_model() and avatar.model.get_instance_id()==model_id and not points.is_empty()

func body_rect(camera:Camera3D, transform:Transform3D) -> Rect2:
	return _project(camera,points,transform)

func navigation_rect(camera:Camera3D, foot_world:Vector3, scale:float) -> Rect2:
	var key:=[camera.global_transform,camera.get_camera_projection(),foot_world.snapped(Vector3.ONE*0.000001),snappedf(scale,0.000001)]
	if key!=_navigation_key:
		_navigation_key=key
		_navigation_cached=_project(camera,swept,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale),foot_world))
	return _navigation_cached

static func _project(camera:Camera3D, vertices:PackedVector3Array, transform:Transform3D) -> Rect2:
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for point in vertices:
		var world:=transform*point
		if camera.is_position_behind(world):continue
		var pixel:=camera.unproject_position(world)
		low=low.min(pixel)
		high=high.max(pixel)
	# Convex-hull/transform float roundoff can differ by a few thousandths of a
	# pixel from projecting every original mesh vertex. Reserve it explicitly.
	return Rect2(low,high-low).grow(0.01) if low.is_finite() and high.is_finite() else Rect2()


## Closest point in the union of monitor-contained ground footprints. For a
## fixed camera each screen edge induces one linear half-plane in ground X/Z;
## all swept vertices share its normal. Enumerating edge/vertex projections
## therefore solves the 2D Euclidean nearest-point problem without a grid.
func nearest_safe_ground(camera: Camera3D, foot_world: Vector3, scale: float,
		desktop_origin: Vector2, workareas: Array, max_distance: float = 0.25) -> Dictionary:
	var rejected := {"ok":false,"point":foot_world,"changed":false,"distance_m":0.0,"correction_m":Vector3.ZERO,"reason":"no_bounded_safe_ground"}
	if swept.is_empty() or not foot_world.is_finite() or not is_finite(scale) or scale <= 0.0 or not is_finite(max_distance) or max_distance < 0.0:
		rejected.reason="invalid_geometry";return rejected
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		rejected.reason="invalid_camera";return rejected
	var viewport := camera.get_viewport()
	if not is_instance_valid(viewport):
		rejected.reason="invalid_camera";return rejected
	var viewport_size := viewport.get_visible_rect().size
	if not viewport_size.is_finite() or viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or not camera.get_camera_transform().is_finite():
		rejected.reason="invalid_camera";return rejected
	var camera_projection := camera.get_camera_projection()
	if not camera_projection.x.is_finite() or not camera_projection.y.is_finite() or not camera_projection.z.is_finite() or not camera_projection.w.is_finite():
		rejected.reason="invalid_camera";return rejected
	if not desktop_origin.is_finite():
		rejected.reason="invalid_desktop_origin";return rejected
	for raw_area in workareas:
		if not (raw_area is Rect2 or raw_area is Rect2i):
			rejected.reason="invalid_workarea";return rejected
		var area := Rect2(raw_area)
		if not area.position.is_finite() or not area.size.is_finite() or not area.has_area():
			rejected.reason="invalid_workarea";return rejected
	var initial := navigation_rect(camera,foot_world,scale)
	initial.position += desktop_origin
	var all_in_front := true
	for offset in swept:
		if -(camera.get_camera_transform().affine_inverse()*(foot_world+offset*scale)).z < camera.near: all_in_front=false;break
	for area in workareas:
		if all_in_front and Rect2(area).encloses(initial):
			return {"ok":true,"point":foot_world,"changed":false,"distance_m":0.0,"correction_m":Vector3.ZERO,"bounds":initial,"reason":"already_safe"}
	var projection := camera.get_camera_projection()
	var view := camera.get_camera_transform().affine_inverse()
	var dx := projection * Vector4(view.basis.x.x,view.basis.x.y,view.basis.x.z,0.0)
	var dz := projection * Vector4(view.basis.z.x,view.basis.z.y,view.basis.z.z,0.0)
	var size := camera.get_viewport().get_visible_rect().size
	var best := Vector2.INF
	var best_bounds := Rect2()
	for raw_area in workareas:
		# _project reserves .01px. A further .001px puts the analytic
		# boundary inside float32 projection rounding, not outside the monitor.
		var area := Rect2(raw_area).grow(-0.011)
		area.position -= desktop_origin
		if not area.has_area():continue
		var left := area.position.x*2.0/size.x-1.0
		var right := area.end.x*2.0/size.x-1.0
		var top := 1.0-area.position.y*2.0/size.y
		var bottom := 1.0-area.end.y*2.0/size.y
		var planes: Array[Vector3] = [Vector3(dx.x-right*dx.w,dz.x-right*dz.w,-INF),Vector3(left*dx.w-dx.x,left*dz.w-dz.x,-INF),Vector3(dx.y-top*dx.w,dz.y-top*dz.w,-INF),Vector3(bottom*dx.w-dx.y,bottom*dz.w-dz.y,-INF),Vector3(view.basis.x.z,view.basis.z.z,-INF)]
		for offset in swept:
			var local := view*(foot_world+offset*scale)
			var clip := projection*Vector4(local.x,local.y,local.z,1.0)
			var values := [clip.x-right*clip.w,left*clip.w-clip.x,clip.y-top*clip.w,bottom*clip.w-clip.y,local.z+camera.near]
			for i in planes.size():planes[i].z=maxf(planes[i].z,values[i])
		var candidates: Array[Vector2] = [Vector2.ZERO]
		for plane in planes:
			var normal := Vector2(plane.x,plane.y)
			if normal.length_squared()>1e-12:candidates.append(-plane.z*normal/normal.length_squared())
		for i in planes.size():
			for j in range(i+1,planes.size()):
				var a := planes[i];var b := planes[j]
				var determinant := a.x*b.y-a.y*b.x
				if absf(determinant)>1e-10:candidates.append(Vector2(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z)/determinant)
		for candidate in candidates:
			if candidate.length()>max_distance or candidate.length_squared()>=best.length_squared():continue
			var feasible := true
			for plane in planes:
				if Vector2(plane.x,plane.y).dot(candidate)+plane.z>0.000001:feasible=false;break
			if not feasible:continue
			var point := foot_world+Vector3(candidate.x,0.0,candidate.y)
			var bounds := navigation_rect(camera,point,scale);bounds.position+=desktop_origin
			# Final acceptance uses the actual projected bounds, including padding;
			# the half-plane feasibility epsilon never relaxes desktop containment.
			if not Rect2(raw_area).encloses(bounds):continue
			best=candidate;best_bounds=bounds
	if not best.is_finite():return rejected
	var correction := Vector3(best.x,0.0,best.y)
	return {"ok":true,"point":foot_world+correction,"changed":true,"distance_m":best.length(),"correction_m":correction,"bounds":best_bounds,"reason":"normalized"}
