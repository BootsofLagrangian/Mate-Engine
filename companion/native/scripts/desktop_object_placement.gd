class_name DesktopObjectPlacement
extends RefCounted
## Bounded geometry-only placement on a declared world-Y plane. The projection
## envelope is an exact convex hull of imported furniture, including its chair.
static func find(camera: Camera3D, desktop_origin: Vector2, areas: Array, desired: Vector3,
		basis: Basis, vertices: PackedVector3Array, parts: Array, obstacles: Array,
		maximum_distance: float = 1.5, candidate_validator: Callable = Callable()) -> Dictionary:
	if vertices.is_empty() or not desired.is_finite() or not basis.is_finite():return {"ok":false,"reason":"invalid_geometry"}
	var shape:=ConvexPolygonShape3D.new();shape.points=vertices
	var mesh:=shape.get_debug_mesh()
	var geometry:=ProjectedAvatarGeometry.new()
	var unique:={}
	for surface in mesh.get_surface_count():
		for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:unique[basis*vertex]=true
	for vertex in unique:geometry.swept.append(vertex)
	var inset:Array=[]
	# Standalone native crop reserves eight pixels plus integer edge rounding.
	for area in areas:
		var inner:=Rect2(area).grow(-9.0)
		if inner.has_area():inset.append(inner)
	var offsets:Array[Vector2]=[Vector2.ZERO]
	for radius in [.25,.5,.75,1.0]:
		for step in 12:
			var angle:=TAU*step/12.0
			offsets.append(Vector2(cos(angle),sin(angle))*radius)
	var best:Dictionary={"ok":false,"reason":"no_feasible_ground_placement"}
	var best_distance:=maximum_distance+1.0
	var candidates:Array=[]
	var candidate_points:={}
	for offset in offsets:
		var seed:=desired+Vector3(offset.x,0,offset.y)
		var proposal:=geometry.nearest_safe_ground(camera,seed,1.0,desktop_origin,inset,maximum_distance)
		if not proposal.get("ok",false):continue
		var point:Vector3=proposal.point
		var distance:=point.distance_to(desired)
		if distance>maximum_distance or distance>=best_distance:continue
		var transform:=Transform3D(basis,point)
		var clear:=true
		for part:AABB in parts:
			var world:=transform*part
			for obstacle:AABB in obstacles:
				if world.intersects(obstacle):clear=false;break
			if not clear:break
		if not clear:continue
		if candidate_validator.is_valid():
			if not candidate_points.has(point):
				candidate_points[point]=true
				candidates.append({"ok":true,"point":point,"distance_m":distance,"ground_y":desired.y,"bounds":proposal.bounds,"reason":"fits"})
			continue
		best_distance=distance
		best={"ok":true,"point":point,"distance_m":distance,"ground_y":desired.y,"bounds":proposal.bounds,"reason":"fits"}
		if distance<.000001:break
	# Validate nearest geometric proposals first. A complete setup/path probe is
	# expensive; ordering avoids revalidating progressively closer candidates.
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.distance_m)<float(b.distance_m))
	var checked:=0
	for candidate:Dictionary in candidates:
		checked+=1
		if bool(candidate_validator.call(candidate.point)):
			candidate["validated_candidates"]=checked
			return candidate
	if candidate_validator.is_valid():best["validated_candidates"]=checked
	return best
