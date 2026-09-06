extends SceneTree
const View = preload("res://scripts/desktop_view.gd")
const Obj = preload("res://scripts/desktop_object_window.gd")
const Objects = preload("res://scripts/desktop_objects_host.gd")
class FakeHost extends Node3D:
 var camera: Camera3D
 func spatial_camera() -> Camera3D: return camera
const Contact = preload("res://scripts/desktop_object_contact_scene.gd")
var checks := 0
var failures: Array = []
func check(ok: bool,label: String) -> void:
 checks+=1
 if not ok: failures.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size=Vector2i(1000,1000)
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1,6)
 View.configure_projection(camera,"perspective",3,45)
 var host:=FakeHost.new();root.add_child(host);host.camera=camera
 var objects:=Objects.new();root.add_child(objects);objects.host=host
 for kind in ["chair","sofa","computer"]:
  for yaw in [0.0,45.0,-110.0]:
   var w:=Obj.new();root.add_child(w)
   var record:={"id":"obj_1","type":kind,"label":kind,"x":0,"y":0,"scale":0.8,"visible":true,"yaw_deg":yaw,"appearance":"default"}
   w.configure(record,Vector2i(220,280))
   var placement:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.8),Vector3(.1,0,-.5))
   check(w.set_shared_projection(camera,Vector2.ZERO,placement),kind+" configure")
   var scene:=Contact.new();root.add_child(scene);scene.configure(kind)
   record.position_m={"x":.1,"y":0.0,"z":-.5};record.spatial_unit_scale=1.0
   objects.store.set_data({"version":1,"next_id":2,"objects":[record]})
   objects._contact_scene=scene;objects._contact_id="obj_1"
   objects._update_contact_transform()
   for socket in w._sockets:
    if not scene._sockets.has(socket): continue
    var a:Vector3=w._scene.global_transform*w._sockets[socket]
    var b:Vector3=scene.socket_world(socket)
    check(a.distance_to(b)<.0001,kind+" yaw="+str(yaw)+" socket="+socket+" transfer_error_m="+str(a.distance_to(b)))
   w.free();scene.free()
 objects._contact_scene=null;objects._contact_id="";objects.host=null;objects.free();host.free()
 print(JSON.stringify({"checks":checks,"failures":failures,"scope":"Independent actual imported standalone-to-contact socket spatial continuity, pure geometry"}))
 quit(1 if failures else 0)
