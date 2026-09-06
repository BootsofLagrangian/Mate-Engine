extends SceneTree
class Avatar extends Node:
 var point:=Vector3.ZERO
 func has_model():return true
 func contact_anchors():return {"foot":point}
class ProfileWindow extends Node:
 var projection_profile:Dictionary={"fits":3,"cache_hits":4,"geometry_collections":2,"last_fit_us":23,"last_request_at_us":100,"last_fit_at_us":80}
class Objects extends Node:
 var windows:Dictionary={}
 var _interaction:Dictionary={}
 var scans:=0
 var solids:Array=[AABB(Vector3(.1,0,.1),Vector3(.4,.8,.3))]
 func scene_obstacle_bounds():
  scans+=1
  return solids
 func screen_rects():return [Rect2(-5000,-5000,10000,10000)]
class Navigation extends Node:
 var diagnostics:Dictionary={}
 var ground_latched:=true
 func owns_foot():return true
class Autonomy extends Node:
 var contact:Dictionary={"attached":false}
 func get_support_contact():return contact
 func available_surface_targets():return []
class Host extends Node:
 var avatar:=Avatar.new()
 var objects:=Objects.new()
 var scene_navigation:=Navigation.new()
 var autonomy:=Autonomy.new()
 var camera:=Camera3D.new()
 var session:CompanionSession
 var _pet_scale:=.6
 var _model_aabb:=AABB(Vector3.ZERO,Vector3(1,1.5,1))
 func spatial_camera():return camera
 func spatial_desktop_origin():return Vector2.ZERO
 func _navigation_rect():return Rect2(0,0,30,60)
class Living extends LivingBehavior:
 var exploration:=true
 func _scene_exploration_enabled()->bool:return exploration
 func cancel(_reason:String="cancelled")->void:pass
func _init():call_deferred("run")
func run():
 var h:=Host.new();root.add_child(h);h.add_child(h.camera);h.camera.position=Vector3(0,1,3)
 for node in [h.avatar,h.objects,h.scene_navigation,h.autonomy]:h.add_child(node)
 var window:=ProfileWindow.new();h.add_child(window);h.objects.windows["computer"]=window
 h.session=CompanionSession.new();h.session.character_id="first"
 var computer:=DesktopObjectContactScene.new();root.add_child(computer);computer.configure("computer");computer.scale=Vector3.ONE*.6
 h.objects.solids.clear();DesktopObjectsHost._append_scene_solids(computer,h.objects.solids)
 var living:=Living.new();root.add_child(living);living.host=h;living._character="first"
 living.director.set_character("first");living.points=InterestPoints.new();living.add_child(living.points)
 living._refresh_targets()
 var stale:="scene:ground:stale"
 living._known[stale]={};living.scene_interests.targets[stale]={"world":Vector3.ONE}
 living.director.observe_interest(stale,Vector2.ONE,1,30)
 living.director.request_intent("old","move_to",stale,"llm",30,6,"first")
 var failures:=0
 h.objects._interaction={"stage":"entering"};h.scene_navigation.ground_latched=false;living.exploration=false
 var scans:int=h.objects.scans
 living._refresh_targets()
 if not living.scene_interests.suspended or living.scene_interests.has_target(stale):failures+=1
 if living.director._interests.has(stale) or not living.director._queue.is_empty():failures+=1
 var request:=living.request_intent({"kind":"move_to","target_id":stale},"llm","new")
 if request.get("accepted",false) or request.get("reason","")!="unknown_target":failures+=1
 h.objects._interaction.clear();living._refresh_targets()
 living.exploration=true;living._refresh_targets()
 if h.objects.scans!=scans or not living.scene_interests.suspended:failures+=1
 var rebuilds:int=living.scene_interests.diagnostics.rebuilds
 h.autonomy.contact={"attached":true,"pose":"foot","surface_id":"floor:test"}
 living._refresh_targets();living._refresh_targets()
 if living.scene_interests.suspended or living.scene_interests.diagnostics.rebuilds!=rebuilds+1:failures+=1
 var telemetry:Dictionary=h.scene_navigation.diagnostics.interest_refresh
 if telemetry.calls!=7 or telemetry.last_refresh_us<0 or telemetry.last_refresh_msec<0 or telemetry.scene.rebuilds!=living.scene_interests.diagnostics.rebuilds:failures+=1
 if telemetry.window_projection.computer!=window.projection_profile:failures+=1
 window.projection_profile.fits=99
 living.refresh_diagnostics.scene.calls=999
 living.refresh_diagnostics.window_projection.computer.last_fit_us=999
 if telemetry.window_projection.computer.fits!=3 or telemetry.window_projection.computer.last_fit_us!=23 or telemetry.scene.calls==999:failures+=1
 if living.refresh_diagnostics.window_projection.computer.fits!=3:failures+=1
 var result:={"telemetry":telemetry,"failures":failures,"rejected_stale_intent":request,"diagnostics":living.scene_interests.diagnostics}
 FileAccess.open("/tmp/interest-telemetry-review.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("INTEREST_LIVING_REVIEW=",result)
 living.free();computer.free();h.free();quit(failures)
