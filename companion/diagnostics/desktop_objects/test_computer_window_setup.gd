extends "test_projection.gd"
func run():
 for scale in [.5,1.0,1.8]:
  var w:=DesktopObjectWindow.new();root.add_child(w)
  var record:Dictionary={"id":"computer","type":"computer","x":-500,"y":400,"label":"computer","scale":scale,"yaw_deg":45.0,"seat_scale":.82}
  check(w.configure(record,Vector2i(Vector2(360,300)*scale)),"combined computer loads at configured scale")
  check(is_instance_valid(w._computer_assembly) and is_instance_valid(w._computer_assembly.seat_node()),"standalone computer includes same actual chair assembly")
  var keyboard:Vector3=w._computer_assembly.socket_world("keyboard_left")
  check(w.set_seat_scale(.9) and w._computer_assembly.socket_world("keyboard_left")==keyboard,"chair-only height adjustment preserves actual keyboard geometry")
  check(absf(w._computer_assembly.socket_local("seat").y-.48*.9)<.000001,"native cushion height follows real adjusted chair")
  check(not w.set_seat_scale(.49) and is_equal_approx(float(w.seat_setup().seat_scale),.9),"invalid seat scale preserves existing chair")
  for view in [Basis.IDENTITY,Basis.from_euler(Vector3(deg_to_rad(-45),deg_to_rad(45),0))]:
   w.set_view_basis(view)
   for zoom in [.6,1.6]:
    w.set_projection_zoom(zoom)
    for pose in [Vector2.ZERO,Vector2(.1,-125)]:
     check(w.set_seat_setup(pose.x,pose.y),"native chair preserves actual interrupted/working setup")
     var actual_world:Vector3=w._computer_assembly.socket_world("seat")
     var socket:Vector2=w.socket_point("seat")-Vector2(w.position)
     check(socket.distance_to(w._camera.unproject_position(actual_world))<.001,"native projected seat agrees with actual chair transform")
     var inside:=true;var bottom:float=-INF
     for vertex in w._geometry_points:
      var pixel:Vector2=w._camera.unproject_position(vertex)
      if not Rect2(Vector2.ZERO,Vector2(w.size)).has_point(pixel):inside=false
      bottom=maxf(bottom,pixel.y)
     check(inside and absf(bottom-(w.size.y-1))<.01,"combined resized/rotated/zoomed chair and desk retain all vertices and ground margin")
  w.free()
 print("Computer native setup: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
