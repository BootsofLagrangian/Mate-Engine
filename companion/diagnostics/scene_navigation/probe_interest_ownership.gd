extends SceneTree
class Avatar extends Node:
 var point:=Vector3.ZERO
 func has_model():return true
 func contact_anchors():return {"foot":point}
class Objects extends Node:
 var _interaction:Dictionary={}
 var scans:=0
 var solids:Array=[AABB(Vector3(.1,0,.1),Vector3(.4,.8,.3))]
 func scene_obstacle_bounds():
  scans+=1
  return solids
 func screen_rects():return [Rect2(-5000,-5000,10000,10000)]
class Navigation extends Node:
 var ground_latched:=true
 func owns_foot():return true
class Autonomy extends Node:
 func get_support_contact():return {"attached":false}
class Host extends Node:
 var avatar:=Avatar.new()
 var objects:=Objects.new()
 var scene_navigation:=Navigation.new()
 var autonomy:=Autonomy.new()
 var camera:=Camera3D.new()
 var session:Dictionary={"character_id":"first"}
 var _pet_scale:=.6
 var _model_aabb:=AABB(Vector3.ZERO,Vector3(1,1.5,1))
 func spatial_camera():return camera
 func spatial_desktop_origin():return Vector2.ZERO
 func _navigation_rect():return Rect2(0,0,30,60)
func _init():call_deferred("run")
func run():
 var h:=Host.new();root.add_child(h);h.add_child(h.camera);h.camera.position=Vector3(0,1,3)
 for node in [h.avatar,h.objects,h.scene_navigation,h.autonomy]:h.add_child(node)
 var computer:=DesktopObjectContactScene.new();root.add_child(computer);computer.configure("computer");computer.scale=Vector3.ONE*.6
 h.objects.solids.clear();DesktopObjectsHost._append_scene_solids(computer,h.objects.solids)
 var interests:=DesktopSceneInterests.new();var failures:=0;var rows:Array=[]
 interests.refresh(h)
 var rebuilds:int=interests.diagnostics.rebuilds
 for i in 4:
  h.avatar.point.y-=.04
  interests.refresh(h)
  rows.append(interests.diagnostics.duplicate())
 if interests.diagnostics.rebuilds!=rebuilds+4:failures+=1
 h.objects._interaction={"stage":"entering"}
 var scans:int=h.objects.scans
 for i in 4:
  h.avatar.point.y-=.04
  if not interests.refresh(h).is_empty() or not interests.targets.is_empty():failures+=1
 if h.objects.scans!=scans:failures+=1
 interests.clear(true)
 if not interests.suspended:failures+=1
 h.objects._interaction.clear();h.scene_navigation.ground_latched=false
 if not interests.refresh(h).is_empty() or h.objects.scans!=scans:failures+=1
 h.scene_navigation.ground_latched=true
 rebuilds=interests.diagnostics.rebuilds
 interests.refresh(h);interests.refresh(h)
 if interests.diagnostics.rebuilds!=rebuilds+1:failures+=1
 h.objects._interaction={"stage":"exiting"};interests.refresh(h)
 h.session.character_id="replacement";h.scene_navigation.ground_latched=false;h.objects._interaction.clear()
 if not interests.refresh(h).is_empty():failures+=1
 h.scene_navigation.ground_latched=true;interests.refresh(h)
 if interests._character!="replacement" or interests.suspended:failures+=1
 FileAccess.open("/tmp/interest-ownership.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"unsuppressed_rebuilds":rows,"final":interests.diagnostics},"  "))
 print("INTEREST_OWNERSHIP_FAILURES=",failures)
 computer.free();h.free();quit(failures)
