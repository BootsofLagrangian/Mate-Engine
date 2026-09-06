extends SceneTree
class Host:
 extends Node
 const WINDOW_SIZE:=Vector2i(1920,1760)
 var camera:Camera3D
class Objects:
 extends DesktopObjectsHost
 func _exit_tree()->void:pass
 func screen_rects()->Array:return [Rect2(0,0,2560,1392)]
var failures:=0
func check(value:bool,label:String)->void:
 print("CHECK ",label," ",value)
 if not value:failures+=1
func _init()->void:call_deferred("run")
func projected(camera:Camera3D,box:AABB,transform:Transform3D)->Rect2:
 var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
 for i in 8:
  var point:=camera.unproject_position(transform*box.get_endpoint(i))+Vector2(root.position)
  low=low.min(point);high=high.max(point)
 return Rect2(low,high-low).grow(2)
func run()->void:
 root.size=Vector2i(680,760);root.position=Vector2i(940,316)
 var h:=Host.new();root.add_child(h)
 h.camera=Camera3D.new();h.add_child(h.camera);h.camera.position=Vector3(-.698495,1.334204,3.6);h.camera.fov=45;h.camera.near=.01;h.camera.far=100
 var objects:=Objects.new();h.add_child(objects);objects.host=h
 var scene:=DesktopObjectContactScene.new();h.add_child(scene)
 check(scene.configure("computer"),"actual computer loads")
 scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
 scene.set_seat_scale(.4349648273/.48);scene.position=Vector3(3.98705,-1.314583,-.709737)
 var envelope:=AABB(Vector3(-.65,-.000344,-.325),Vector3(1.3,1.189844,1.441179))
 var area:=Rect2(0,0,2560,1392)
 check(area.encloses(projected(h.camera,envelope,scene.global_transform)),"old local-corner admission reproduces false pass")
 check(not area.encloses(projected(h.camera,scene.get_world_bounds(),Transform3D.IDENTITY)),"actual runtime world box is outside monitor")
 check(not objects._chair_setup_fits(scene,envelope),"setup rejects actual runtime overflow")
 check(not objects._chair_setup_fits(scene),"current-pose admission also uses runtime world box")
 scene.position.x-=1.0
 check(objects._chair_setup_fits(scene,envelope),"inward feasible setup remains admitted")
 print("SETUP_PROJECTION 6 checks ",failures," failures")
 h.free();quit(1 if failures else 0)
