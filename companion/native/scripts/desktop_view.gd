class_name DesktopView
extends RefCounted
## Shared orthographic/perspective projection. Depth is positive optical-axis
## metres, never world Z or an object scale. Cameras must belong to a viewport.
const DEFAULTS := {"yaw_deg":0.0,"pitch_deg":0.0,"height_m":0.0,"zoom":1.0}
const EPSILON := 0.000001

static func _finite(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback

static func clamp_settings(values: Dictionary) -> Dictionary:
	var result := {"yaw_deg":clampf(_finite(values.get("yaw_deg"),0.0),-180.0,180.0),
		"pitch_deg":clampf(_finite(values.get("pitch_deg"),0.0),-60.0,70.0),
		"height_m":clampf(_finite(values.get("height_m"),0.0),-0.5,0.5),
		"zoom":clampf(_finite(values.get("zoom"),1.0),0.6,1.6)}
	if values.has("projection") or values.has("fov_deg") or values.has("distance_m"):
		result["projection"] = "perspective" if values.get("projection") == "perspective" else "orthographic"
		result["fov_deg"] = clampf(_finite(values.get("fov_deg"),45.0),20.0,80.0)
		result["distance_m"] = perspective_distance(values.get("distance_m",3.6))
	return result

## Positive pitch raises the nominal eye and looks downward. Height adds world
## UP to that eye offset before looking at the fixed orbit target. Consequently
## height changes effective elevation; it is not a pan cancelled by pivot locking.
static func orbit_basis(yaw_deg: float, pitch_deg: float, height_m: float = 0.0, radius: float = 3.6) -> Basis:
	var values := clamp_settings({"yaw_deg":yaw_deg,"pitch_deg":pitch_deg,"height_m":height_m})
	var distance := maxf(_finite(radius,3.6),0.01)
	var pitch := deg_to_rad(float(values.pitch_deg))
	var offset := Basis(Vector3.UP,deg_to_rad(float(values.yaw_deg)))*Vector3(0,sin(pitch)*distance,cos(pitch)*distance)
	offset += Vector3.UP*float(values.height_m)
	return Basis.looking_at(-offset,Vector3.UP)

static func orthographic_size(base_size: float, zoom: float) -> float:
	return maxf(_finite(base_size,2.0),0.001)/clampf(_finite(zoom,1.0),0.6,1.6)

static func _valid(camera: Camera3D) -> bool:
	return is_instance_valid(camera) and camera.is_inside_tree() and camera.projection in [Camera3D.PROJECTION_ORTHOGONAL,Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_FRUSTUM]

static func _forward(camera: Camera3D) -> Vector3:
	return -camera.get_camera_transform().basis.z.normalized()

## Positive in front of the camera, measured along its optical axis.
static func depth(camera: Camera3D, point: Vector3) -> float:
	if not _valid(camera) or not point.is_finite(): return NAN
	return _forward(camera).dot(point-camera.get_camera_transform().origin)

## Delegating to Camera3D preserves actual viewport/aspect/offset semantics.
static func screen_to_world_at_depth(camera: Camera3D, pixel: Vector2, camera_depth: float) -> Vector3:
	if not _valid(camera) or not pixel.is_finite() or not is_finite(camera_depth) or camera_depth <= EPSILON: return Vector3.INF
	var viewport := camera.get_viewport().get_visible_rect().size
	if viewport.x <= 0 or viewport.y <= 0: return Vector3.INF
	# Godot 4.5 project_position/project_ray_normal assume a symmetric frustum.
	# Invert the actual projection to retain off-axis crop offsets.
	var clip := Vector4(pixel.x/viewport.x*2.0-1.0,1.0-pixel.y/viewport.y*2.0,-1.0,1.0)
	var near_h: Vector4 = camera.get_camera_projection().inverse()*clip
	if absf(near_h.w) <= EPSILON: return Vector3.INF
	var local := Vector3(near_h.x,near_h.y,near_h.z)/near_h.w
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		local.z = -camera_depth
	else:
		if -local.z <= EPSILON: return Vector3.INF
		local *= camera_depth/(-local.z)
	return camera.get_camera_transform()*local

## Perspective displacement is defined only on an explicit constant-depth plane.
## Existing two-argument callers remain valid for orthographic projection only.
static func screen_delta_to_world(camera: Camera3D, delta_pixels: Vector2, camera_depth: float = NAN) -> Vector3:
	if not _valid(camera) or not delta_pixels.is_finite(): return Vector3.INF
	var distance := camera_depth
	if is_nan(distance) and camera.projection == Camera3D.PROJECTION_ORTHOGONAL: distance = 1.0
	if not is_finite(distance) or distance <= EPSILON: return Vector3.INF
	return screen_to_world_at_depth(camera,delta_pixels,distance)-screen_to_world_at_depth(camera,Vector2.ZERO,distance)

static func screen_to_world_at_reference_depth(camera: Camera3D, pixel: Vector2, reference: Vector3) -> Vector3:
	return screen_to_world_at_depth(camera,pixel,depth(camera,reference))

## Translation on this point's own viewing ray preserves its projected pixel
## in both modes. Optical-axis translation alone is wrong off-axis in perspective.
static func translation_to_depth(camera: Camera3D, point: Vector3, target_depth: float) -> Vector3:
	var current := depth(camera,point)
	if not is_finite(current) or current <= EPSILON or not is_finite(target_depth) or target_depth <= EPSILON: return Vector3.INF
	return screen_to_world_at_depth(camera,camera.unproject_position(point),target_depth)-point

static func base_depth_for_offset(camera: Camera3D, seat_world: Vector3, seat_offset_world: Vector3) -> float:
	if not _valid(camera) or not seat_offset_world.is_finite(): return NAN
	return depth(camera,seat_world)-_forward(camera).dot(seat_offset_world)

## Projected world-axis derivatives in pixels/metre. A world axis can collapse
## (world X at yaw90), so consumers must retain vectors and check degeneracy.
static func projection_axes(camera: Camera3D, reference: Vector3 = Vector3.INF) -> Dictionary:
	if not _valid(camera): return {}
	var center := reference
	if not center.is_finite():
		if camera.projection != Camera3D.PROJECTION_ORTHOGONAL: return {}
		center = screen_to_world_at_depth(camera,camera.get_viewport().get_visible_rect().size*0.5,1.0)
	var distance := depth(camera,center)
	if not is_finite(distance) or distance <= EPSILON: return {}
	var frame := camera.get_camera_transform()
	var pixel := camera.unproject_position(center)
	var right := camera.unproject_position(center+frame.basis.x)-pixel
	var up := camera.unproject_position(center+frame.basis.y)-pixel
	var radial := Vector2.ZERO
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		radial = (pixel-camera.unproject_position(frame.origin+_forward(camera)*distance))/distance
	var result := {"screen_pixels_per_metre":right.length(),"camera_depth":distance}
	for pair in [["world_x",Vector3.RIGHT],["world_y",Vector3.UP],["world_z",Vector3.BACK]]:
		var axis: Vector3 = pair[1]
		result[pair[0]] = right*axis.dot(frame.basis.x)+up*axis.dot(frame.basis.y)-radial*axis.dot(_forward(camera))
	return result

## A pixel specifies a ray. A fixed world plane is optional and can be parallel
## to that ray; never silently replace its physical constraint with another one.
static func solve_screen_on_plane(camera: Camera3D, pixel: Vector2, plane_point: Vector3, plane_normal: Vector3) -> Dictionary:
	if not _valid(camera) or not pixel.is_finite() or not plane_point.is_finite() or not plane_normal.is_finite() or plane_normal.length_squared() < EPSILON*EPSILON:
		return {"ok":false,"point":Vector3.INF,"reason":"invalid_input"}
	var origin := screen_to_world_at_depth(camera,pixel,maxf(camera.near,0.001))
	var farther := screen_to_world_at_depth(camera,pixel,maxf(camera.near,0.001)+1.0)
	var direction := (farther-origin).normalized()
	var normal := plane_normal.normalized()
	var denominator := direction.dot(normal)
	if absf(denominator) < EPSILON:
		return {"ok":false,"point":Vector3.INF,"reason":"parallel"}
	var point := origin+direction*(plane_point-origin).dot(normal)/denominator
	if not point.is_finite() or depth(camera,point) <= EPSILON:
		return {"ok":false,"point":Vector3.INF,"reason":"behind_camera"}
	return {"ok":true,"point":point,"reason":""}

static func solve_screen_at_world_y(camera: Camera3D, pixel: Vector2, world_y: float) -> Dictionary:
	return solve_screen_on_plane(camera,pixel,Vector3(0,world_y,0),Vector3.UP)

static func solve_screen_at_world_z(camera: Camera3D, pixel: Vector2, world_z: float) -> Dictionary:
	return solve_screen_on_plane(camera,pixel,Vector3(0,0,world_z),Vector3.BACK)

## A vertical base FOV and optical distance are independent physical parameters.
## Zoom changes the lens, not object transforms or declared depth.
static func perspective_fov(base_fov_degrees: float, zoom: float = 1.0) -> float:
	var fov := clampf(_finite(base_fov_degrees,45.0),20.0,80.0)
	var magnification := clampf(_finite(zoom,1.0),0.6,1.6)
	return rad_to_deg(2.0*atan(tan(deg_to_rad(fov)*0.5)/magnification))

static func perspective_distance(value: Variant) -> float:
	return clampf(_finite(value,3.6),1.0,12.0)

## FOV is vertical (KEEP_HEIGHT). Matching this plus camera transform and viewport
## dimensions is necessary for a shared projection; centered independent prop
## cameras are not equivalent crops of a common perspective camera.
static func configure_projection(camera: Camera3D, mode: String, base_orthographic_size: float,
		base_fov_degrees: float = 45.0, zoom: float = 1.0) -> bool:
	if not is_instance_valid(camera) or mode not in ["orthographic","perspective"]: return false
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if mode == "perspective":
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = perspective_fov(base_fov_degrees,zoom)
	else:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = orthographic_size(base_orthographic_size,zoom)
	return true

## Exact crop of one virtual camera. crop_pixels is in the reference viewport's
## coordinate frame and may extend outside it; child viewport size must match.
## Scene world coordinates are unchanged. Child desktop origin is reference
## desktop origin + crop_pixels.position. Objects require their same world pose.
static func configure_crop(child: Camera3D, reference: Camera3D, crop_pixels: Rect2) -> bool:
	if not _valid(reference) or not is_instance_valid(child) or not child.is_inside_tree(): return false
	if not crop_pixels.position.is_finite() or not crop_pixels.size.is_finite() or crop_pixels.size.x <= 0 or crop_pixels.size.y <= 0: return false
	if child.get_viewport().get_visible_rect().size.distance_to(crop_pixels.size) > 0.01: return false
	var frame := reference.get_camera_transform()
	var near_depth := reference.near
	var lo := frame.affine_inverse()*screen_to_world_at_depth(reference,Vector2(crop_pixels.position.x,crop_pixels.end.y),near_depth)
	var hi := frame.affine_inverse()*screen_to_world_at_depth(reference,Vector2(crop_pixels.end.x,crop_pixels.position.y),near_depth)
	if not lo.is_finite() or not hi.is_finite(): return false
	child.h_offset = 0.0
	child.v_offset = 0.0
	child.keep_aspect = Camera3D.KEEP_HEIGHT
	child.global_transform = frame
	var center := Vector2(lo.x+hi.x,lo.y+hi.y)*0.5
	if reference.projection == Camera3D.PROJECTION_ORTHOGONAL:
		child.set_orthogonal(hi.y-lo.y,reference.near,reference.far)
		child.global_position += frame.basis*Vector3(center.x,center.y,0)
	else:
		child.set_frustum(hi.y-lo.y,center,reference.near,reference.far)
	return true

## Set once after avatar import/view-mode change. Materials are shared by all
## exact cropped cameras, so the reference height must belong to the canonical
## virtual film, not whichever native window renders this material next.
static func set_outline_reference_height(scene: Node, reference_height: float, legacy_reference_size: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(scene): return
	var value := maxf(0.0,_finite(reference_height,0.0))
	var legacy_size := legacy_reference_size if legacy_reference_size.is_finite() and legacy_reference_size.x > 0.0 and legacy_reference_size.y > 0.0 else Vector2.ZERO
	var seen := {}
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			while material != null and not seen.has(material.get_instance_id()):
				seen[material.get_instance_id()] = true
				if material is ShaderMaterial and material.shader != null:
					for uniform in material.shader.get_shader_uniform_list():
						if str(uniform.name) == "_OutlineReferenceViewportHeight":
							material.set_shader_parameter("_OutlineReferenceViewportHeight",value)
						elif str(uniform.name) == "_OutlineLegacyReferenceViewportSize":
							material.set_shader_parameter("_OutlineLegacyReferenceViewportSize",legacy_size)
				material = material.next_pass
