extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
 checks += 1
 if not value: failures += 1; push_error(label)
func run():
 var store=load("res://scripts/desktop_object_store.gd").new()
 for type in ["chair","sofa","computer"]:
  for scale in [1.0,1.4]:
   var w=DesktopObjectWindow.new()
   root.add_child(w)
   var dimensions=Vector2i(Vector2(store.base_size(type))*scale)
   var ok=w.configure({"id":type,"type":type,"x":-500,"y":1040-dimensions.y,"label":type},dimensions)
   await process_frame
   check(ok,type+" source mesh loads")
   var rect=Rect2(w.position,w.size)
   var sockets=w.socket_catalogue()
   for name in sockets:
    check(Vector2(sockets[name]).is_finite() and rect.has_point(sockets[name]),type+" socket safely projects inside owned viewport: "+name)
   if type != "computer":
    var seat=w.seat_surface()
    check(seat.x2>seat.x1 and absf(seat.y-w.socket_point("seat").y)<0.001,type+" actual seat surface matches projected pelvis socket")
    check(1040-seat.y>60*scale,type+" grounded seat has measured support clearance")
   var bottom := -INF
   var all_inside := true
   for vertex in w._geometry_points:
    var projected: Vector2 = w._camera.unproject_position(vertex)
    bottom = maxf(bottom,projected.y)
    all_inside = all_inside and Rect2(Vector2.ZERO,Vector2(w.size)).has_point(projected)
   check(absf(bottom-(w.size.y-1.0))<0.01,type+" actual mesh ground aligns one pixel above viewport floor")
   check(all_inside,type+" all actual mesh vertices remain inside safe viewport after ground alignment")
   w.free()
 print("Object projection: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
