class_name RenderSurface
extends RefCounted
## Pixel density belongs to the camera, not the monitor resolution. Resize the
## visible film without scaling model transforms or stretching a fixed viewport.
static func foot_pixel(extent:Vector2,reference:Vector2,reference_foot:Vector2,padding:Vector2)->Vector2:
	var gutter:=Vector2(minf(padding.x,maxf(0,(extent.x-reference.x)*.5)),minf(padding.y,maxf(0,(extent.y-reference.y)*.5)))
	return Vector2(extent.x*.5,minf(reference_foot.y+gutter.y,maxf(0,extent.y-(reference.y-reference_foot.y))))
static func resize_orthographic(camera:Camera3D,old_extent:Vector2,new_extent:Vector2,origin_delta:Vector2,pixels_per_metre:float,desktop_shift:=Vector2.ZERO)->bool:
	if not is_instance_valid(camera) or camera.projection!=Camera3D.PROJECTION_ORTHOGONAL or not old_extent.is_finite() or not new_extent.is_finite() or minf(new_extent.x,new_extent.y)<=0 or not origin_delta.is_finite() or not desktop_shift.is_finite() or not is_finite(pixels_per_metre) or pixels_per_metre<=0:return false
	var centre_delta:=origin_delta+(new_extent-old_extent)*.5-desktop_shift
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=new_extent.y/pixels_per_metre
	camera.global_position+=camera.global_basis.x*(centre_delta.x/pixels_per_metre)-camera.global_basis.y*(centre_delta.y/pixels_per_metre)
	return true
