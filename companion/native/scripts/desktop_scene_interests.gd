class_name DesktopSceneInterests
extends RefCounted
## Stable, bounded world-ground choices. Rebuilt on geometry/view/rig change,
## never randomized per frame and never requests model inference.
var targets: Dictionary = {}
var _key := ""
var _anchor := Vector3.INF
var _character := ""
var suspended:=false
var diagnostics:Dictionary={"calls":0,"rebuilds":0,"last_refresh_us":0,"last_rebuild_us":0,"suppressed":false}
func suspend()->void:
	targets.clear();_key="";_anchor=Vector3.INF;suspended=true;diagnostics.suppressed=true
func interaction_owned(host:Node)->bool:
	return host.objects!=null and not host.objects._interaction.is_empty()
func _ground_ready(host:Node)->bool:
	if host.scene_navigation.owns_foot() and host.scene_navigation.ground_latched:return true
	var contact:Dictionary=host.autonomy.get_support_contact()
	return bool(contact.get("attached",false)) and str(contact.get("pose",""))=="foot"

func refresh(host: Node) -> Array:
	var started:=Time.get_ticks_usec()
	diagnostics.calls+=1
	var result:=_refresh(host)
	diagnostics.last_refresh_us=Time.get_ticks_usec()-started
	return result
func _refresh(host:Node)->Array:
	if interaction_owned(host):
		suspend()
		return []
	if suspended:
		if host.scene_navigation==null or not _ground_ready(host):return []
		suspended=false;diagnostics.suppressed=false
	if host.spatial_camera()==null or not host.avatar.has_model() or host.scene_navigation==null:
		targets.clear();_key="";return []
	var actor:Vector3=host.avatar.contact_anchors().foot
	if _character!=str(host.session.character_id) or not _anchor.is_finite() or absf(actor.y-_anchor.y)>.02:
		_character=str(host.session.character_id);_anchor=actor;_key=""
	var solids:Array=host.objects.scene_obstacle_bounds()
	var camera:Camera3D=host.spatial_camera()
	var key:=str([_character,host._pet_scale,camera.global_transform,camera.get_camera_projection(),solids,host.objects.screen_rects()])
	if key!=_key:
		var rebuild_started:=Time.get_ticks_usec()
		diagnostics.rebuilds+=1
		_key=key;targets.clear()
		var scale:float=host._pet_scale
		var nav:=DesktopSceneNavigation.new()
		var bounds:=Rect2(Vector2(_anchor.x,_anchor.z)-Vector2.ONE*1.4*scale,Vector2.ONE*2.8*scale)
		var configured:=nav.configure(bounds,actor.y,solids,.12*scale,host._model_aabb.size.y*scale,.06)
		if configured.ok:
			var offsets: Array = [Vector2(-.65,-.55),Vector2(.65,-.55),Vector2(-.65,.25),Vector2(.65,.25),Vector2(0,-.9),Vector2(0,.5)]
			for index in offsets.size():
				var offset:Vector2=offsets[index]*scale
				var point:=_anchor+Vector3(offset.x,0,offset.y)
				if not nav.is_navigable(point) or camera.is_position_behind(point):continue
				var projected:Vector2=camera.unproject_position(point)+host.spatial_desktop_origin()
				var current:Vector2=camera.unproject_position(actor)+host.spatial_desktop_origin()
				var ratio:=DesktopView.depth(camera,actor)/maxf(DesktopView.depth(camera,point),.01)
				var body:Rect2=host._navigation_rect()
				body.position=projected+(body.position+Vector2(host.get_window().position)-current)*ratio
				body.size*=ratio
				var safe:=false
				for area in host.objects.screen_rects():
					if Rect2(area).encloses(body.grow(2)):safe=true;break
				if not safe:continue
				var route:=nav.plan("candidate",actor,point)
				if route.accepted:targets["scene:ground:"+str(index)]={"world":point,"point":projected,"id":"scene:ground:"+str(index),"kind":"floor","label":"가상 공간 둘러보기 "+str(index+1),"confidence":.55}
		nav.dispose()
		diagnostics.last_rebuild_us=Time.get_ticks_usec()-rebuild_started
	var result:Array=[]
	for item in targets.values():
		var row:Dictionary=item.duplicate()
		row.point=camera.unproject_position(row.world)+host.spatial_desktop_origin()
		result.append(row)
	return result
func has_target(id: String) -> bool:return targets.has(id)
func world_target(id: String) -> Vector3:return targets.get(id,{}).get("world",Vector3.INF)
func clear(preserve_suspension:bool=false) -> void:
	targets.clear();_key="";_anchor=Vector3.INF
	if not preserve_suspension:suspended=false;diagnostics.suppressed=false
