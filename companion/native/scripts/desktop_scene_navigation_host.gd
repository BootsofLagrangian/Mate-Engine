class_name DesktopSceneNavigationHost
extends Node
## Commits navigation metres through the canonical camera; legacy desktop surfaces
## are suspended while this adapter owns the standing foot.
var host: Node
var navigation := DesktopSceneNavigation.new()
var holding := false
var foot_world := Vector3.INF
var diagnostics: Dictionary = {}
var _serial := 0
var _preparing := false
var _prepare_time := 0.0
var _base_speed := 0.0
var _completion := Callable()
var ground_latched := false
func configure(app: Node) -> void: host=app
func owns_foot() -> bool: return holding and foot_world.is_finite()
func request(target: Vector3, solids: Array) -> Dictionary:
	if host == null or host.spatial_camera()==null or not host.avatar.has_model(): return {"accepted":false,"reason":"scene_unavailable"}
	if _blocked(): return {"accepted":false,"reason":"foreground"}
	if not host.motion.has_method("prepare_scene_locomotion"): return {"accepted":false,"reason":"scene_motion_unavailable"}
	var original: Vector3=host.avatar.contact_anchors().foot
	var placement:Dictionary=host.normalize_scene_ground_placement(original)
	if not placement.get("ok",false):return {"accepted":false,"reason":placement.get("reason","outside_workarea")}
	var start: Vector3=placement.point
	if not placement_is_clear(original,start,solids,.12*host._pet_scale,host._model_aabb.size.y*host._pet_scale):return {"accepted":false,"reason":"blocked_placement"}
	var low:=Vector2(minf(start.x,target.x),minf(start.z,target.z))-Vector2.ONE*1.2
	var high:=Vector2(maxf(start.x,target.x),maxf(start.z,target.z))+Vector2.ONE*1.2
	var candidate:=DesktopSceneNavigation.new()
	var geometry:=candidate.configure(Rect2(low,high-low),start.y,solids,.12*host._pet_scale,host._model_aabb.size.y*host._pet_scale,navigation_cell_size(high-low))
	if not geometry.ok:candidate.dispose();return {"accepted":false,"reason":geometry.reason}
	_serial+=1
	var result:=candidate.plan("scene:"+str(_serial),start,target,.35*host._pet_scale)
	if not result.accepted:candidate.dispose();return result
	if holding:cancel("superseded")
	navigation.dispose();navigation=candidate
	ground_latched=false
	foot_world=start;holding=true;_preparing=true;_prepare_time=0;_base_speed=.35*host._pet_scale
	diagnostics={"initial_placement":placement,"original_world":original}
	host._update_avatar_transform(0);host._update_pet_rect()
	host.autonomy.cancel_target("scene_navigation")
	host.autonomy.set_process(false)
	var direction:Vector3=target-start
	if not host.motion.prepare_scene_locomotion(atan2(direction.x,direction.z)):
		cancel("motion_rejected");return {"accepted":false,"reason":"motion_rejected"}
	return result
func _blocked() -> bool:
	var job_active:bool=not host.session.job.is_empty() and str(host.session.job.get("status","")) not in ["done","failed","cancelled","completed"]
	return job_active or not host.autonomy.enabled or host.autonomy._pointer_interaction or host.objects.is_dragging() or host.panel_open or host._drag_active or host._sit_active or ((host.audio.voice_active or host.session.is_foreground_busy() or host.bridge.dialogue_holding(host._now())) and not host.objects.owns_foreground_speech()) or host.mic.is_recording() or host.motion._preview or host.motion._custom_motion
func tick(delta: float) -> void:
	if not holding:return
	if host._drag_active or host.spatial_camera()==null or not host.autonomy.enabled or not host.autonomy.surface_mode:
		cancel("dragged" if host._drag_active else "disabled")
		return
	if not navigation.active:return
	if _blocked():cancel("dragged" if host._drag_active else "foreground");return
	if _preparing:
		_prepare_time+=delta
		if _prepare_time>6:cancel("heading_timeout");return
		if _prepare_time<.25:return
		_preparing=false
		var clip:=AutonomyBridge.pick_walk_clip(host._vrma_loaded)
		if host.living != null and not str(host.living.get("selected_locomotion_id")).is_empty() and host.living.get("selected_locomotion_id") != null:clip=str(host.living.selected_locomotion_id)
		if clip.is_empty() or not host.motion.play_vrma(clip,1.0,true):cancel("missing_locomotion");return
		host._walk_started=clip
	var heading_error:=absf(angle_difference(host.avatar.rotation.y,navigation._heading))
	navigation.speed_mps=_base_speed*heading_speed_factor(heading_error)
	var before:=foot_world
	var old_origin:Vector2i=host.get_window().position
	var frame:=navigation.tick(delta)
	foot_world=frame.position_world
	var projected:Vector2=host.spatial_camera().unproject_position(foot_world)+host.spatial_desktop_origin()
	if host.spatial_camera().is_position_behind(foot_world):foot_world=before;cancel("outside_view");return
	host.get_window().position=Vector2i((projected-host._pivot_px).round())
	host.autonomy.position=Vector2(host.get_window().position)
	host._refresh_spatial_crop()
	host._pivot_px=host.camera.unproject_position(foot_world);host._pivot_px_target=host._pivot_px
	host._update_avatar_transform(0);host._update_pet_rect()
	var occupied:Rect2=host._navigation_rect();occupied.position+=Vector2(host.get_window().position)
	var safe:=false
	for area in host.objects.screen_rects():
		if Rect2(area).encloses(occupied):safe=true;break
	if not safe:
		diagnostics=frame.duplicate();diagnostics["rejected_occupied_rect"]=occupied;diagnostics["workareas"]=host.objects.screen_rects();diagnostics["before_world"]=before;diagnostics["yaw"]=host.avatar.rotation.y
		foot_world=before;host.get_window().position=old_origin;host.autonomy.position=Vector2(old_origin)
		host._refresh_spatial_crop();host._pivot_px=host.camera.unproject_position(foot_world);host._pivot_px_target=host._pivot_px;host._update_avatar_transform(0)
		cancel("outside_workarea");return
	host.motion.update_scene_heading(float(frame.heading_world))
	var world_delta:=foot_world-before
	var pixels:Vector2=host.spatial_camera().unproject_position(foot_world)-host.spatial_camera().unproject_position(before)
	host.motion.set_scene_locomotion_sample(world_delta/maxf(delta,.001),world_delta,float(frame.heading_world),true,float(frame.distance_m))
	diagnostics=frame.duplicate();diagnostics["committed_world_delta"]=world_delta
	if frame.arrived:
		_stop_scene_motion()
		if _completion.is_valid() and not ground_latched: release_to_contact()
		_notify("arrived")
	elif not navigation.active:cancel(str(frame.outcome))
func release_to_contact(reason: String="contact_handoff", notify_owner: bool=true) -> void:
	# Explicit mode departure owns cancellation, even if a prior caller already
	# released the foot. Never leave a completion callback for another request.
	var callback:=_completion if notify_owner else Callable()
	if notify_owner:_completion=Callable()
	if holding:
		_stop_scene_motion()
		host._pivot_px=host.camera.unproject_position(foot_world);host._pivot_px_target=host._pivot_px
		host._camera_pivot_depth=DesktopView.depth(host.camera,foot_world)
		holding=false;ground_latched=false;navigation.cancel(reason);host.autonomy.set_process(true)
	if callback.is_valid():callback.call(reason)
func cancel(reason: String="cancelled") -> void:
	if not holding:
		if _completion.is_valid():_notify(reason)
		return
	navigation.cancel(reason)
	_stop_scene_motion();host.motion.cancel_heading()
	var stopped_scene := reason == "cancelled" and not ground_latched
	if stopped_scene:ground_latched=true
	if ground_latched and reason not in ["shutdown","disabled","character_changed","avatar_changed","dragged"]:
		if _completion.is_valid() or stopped_scene:_notify(reason)
		return
	release_to_contact(reason,false)
	_notify(reason)
func shutdown() -> void:
	if host!=null:cancel("shutdown")
	navigation.dispose();host=null

func request_owned(target: Vector3, solids: Array, completion: Callable) -> Dictionary:
	if not completion.is_valid():return {"accepted":false,"reason":"missing_owner"}
	var result:=request(target,solids)
	if result.accepted:
		_completion=completion
		ground_latched=true
	return result

func _notify(outcome: String) -> void:
	var callback:=_completion
	_completion=Callable()
	if callback.is_valid():callback.call(outcome)
	else:host.objects.scene_navigation_finished(outcome)

func has_completion_owner() -> bool:return _completion.is_valid()

func _stop_scene_motion() -> void:
	host.motion.finish_locomotion()
	if not str(host._walk_started).is_empty() and host.motion.current_gesture()==host._walk_started:host.motion.stop_gesture()
	host._walk_started=""

## Forward authored walking cannot translate into the rear hemisphere.
## Smoothstep has zero slope at acquisition and still permits turning travel.
static func heading_speed_factor(error: float) -> float:
	var forward := clampf(cos(error),0.0,1.0)
	return forward*forward*(3.0-2.0*forward)

static func navigation_cell_size(size: Vector2) -> float:
	return maxf(.03,maxf(size.x,size.y)/127.0)

## Explicit virtual-floor mode admission. This is placement, not locomotion;
## only an unsafe initial anchor is normalized, once, before any heading change.
func adopt_ground_placement() -> Dictionary:
	if host==null or host.spatial_camera()==null or not host.avatar.has_model():return {"ok":false,"reason":"scene_unavailable"}
	if _blocked() or navigation.active or not host.autonomy.surface_mode:return {"ok":false,"reason":"foreground"}
	if holding:return {"ok":true,"point":foot_world,"changed":false}
	var original:Vector3=host.avatar.contact_anchors().foot
	var result:Dictionary=host.normalize_scene_ground_placement(original)
	if not result.get("ok",false):return result
	if not placement_is_clear(original,result.point,host.objects.scene_obstacle_bounds(),.12*host._pet_scale,host._model_aabb.size.y*host._pet_scale):return {"ok":false,"reason":"blocked_placement"}
	foot_world=result.point;holding=true;ground_latched=true
	host.autonomy.cancel_target("scene_placement");host.autonomy.set_process(false)
	host._update_avatar_transform(0);host._update_pet_rect()
	diagnostics={"initial_placement":result,"original_world":original}
	return result

## Continuous capsule-center segment admission, including the placement start.
## No pathfinding detour is silently substituted for an explicit placement.
static func placement_is_clear(start: Vector3, target: Vector3, solids: Array, radius: float, height: float) -> bool:
	if not start.is_finite() or not target.is_finite():return false
	var a:=Vector2(start.x,start.z);var b:=Vector2(target.x,target.z)
	for value in solids:
		if not value is AABB:return false
		var box:AABB=value
		if box.end.y<=start.y or box.position.y>=start.y+height:continue
		var rect:=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(radius)
		if rect.has_point(a) or rect.has_point(b):return false
		var corners:=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
		for i in 4:
			if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4])!=null:return false
	return true
