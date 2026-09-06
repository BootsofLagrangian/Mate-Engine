extends "test_spatial_window.gd"
func run()->void:
 root.size=Vector2i(1600,900)
 var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1,5);View.configure_projection(camera,"perspective",3,45)
 var window:=Obj.new();root.add_child(window)
 var record:Dictionary={"id":"obj_1","type":"computer","label":"Computer","x":50,"y":80,"scale":1.0,"visible":true,"yaw_deg":0.0,"appearance":"default","seat_scale":.9}
 check(window.configure(record,Vector2i(360,300)),"actual complete computer loads")
 await process_frame
 var origin:=Vector2(-1920,0);var pose:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.6),Vector3.ZERO)
 check(window.set_shared_projection(camera,origin,pose),"initial projection succeeds")
 var fits:int=window.projection_profile.fits;var collects:int=window.projection_profile.geometry_collections
 var before:=fingerprint(window)
 for repeat in 10:check(window.set_shared_projection(camera,origin,pose),"unchanged projection returns valid")
 check(window.projection_profile.fits==fits and window.projection_profile.geometry_collections==collects and window.projection_profile.cache_hits==10,"unchanged sync neither extracts nor reprojects vertices")
 check(fingerprint(window)==before,"cache preserves exact crop and sockets")
 window._shared_projection_key.clear();window.set_shared_projection(camera,origin,pose)
 check(fingerprint(window)==before,"forced full projection equals cached result")
 for change in ["fov","camera_position","camera_offset","viewport","object_pose","origin","mesh_transform","mesh_resource","mesh_changed","seat_setup","seat_scale","object_yaw","near_far"]:
  fits=window.projection_profile.fits
  var mesh:MeshInstance3D=window._scene.find_children("*","MeshInstance3D",true,false)[0]
  match change:
   "fov":camera.fov=55
   "camera_position":camera.position.x+=.1
   "camera_offset":camera.h_offset=.05
   "viewport":root.size=Vector2i(1400,900)
   "object_pose":pose.origin.z-=.2
   "origin":origin.x+=20
   "mesh_transform":mesh.position.x+=.01
   "mesh_resource":mesh.mesh=mesh.mesh.duplicate()
   "mesh_changed":mesh.mesh.emit_changed()
   "seat_setup":window.set_seat_setup(.1,145)
   "seat_scale":window.set_seat_scale(.82)
   "object_yaw":record.yaw_deg=30;window.apply_record(record,window.size)
   "near_far":camera.near=.02;camera.far=100
  check(window.set_shared_projection(camera,origin,pose),change+" valid projection")
  check(window.projection_profile.fits>fits,change+" invalidates cached fit")
  before=fingerprint(window);fits=window.projection_profile.fits
  window.set_shared_projection(camera,origin,pose)
  check(window.projection_profile.fits==fits and fingerprint(window)==before,change+" next unchanged fit cached")
  window._shared_projection_key.clear();window.set_shared_projection(camera,origin,pose)
  check(fingerprint(window)==before,change+" cache/full result equivalent")
 window.set_shared_world(root.world_3d,root);window.hide();fits=window.projection_profile.fits;collects=window.projection_profile.geometry_collections
 for repeat in 4:window.set_shared_projection(camera,origin,pose)
 check(window.projection_profile.fits==fits and window.projection_profile.geometry_collections==collects,"hidden occupied window retains valid static projection cache")
 window.clear_shared_projection();check(window._shared_projection_key.is_empty(),"leaving shared projection invalidates cache")
 check(window.set_shared_projection(camera,origin,pose) and window.projection_profile.fits>fits,"reactivation computes actual projection")
 print("PROJECTION_PROFILE ",window.projection_profile)
 window.free();camera.free()
 print(JSON.stringify({"checks":checks,"failures":failures,"scope":"actual imported computer cached/full projection equivalence and all owned invalidations, not Windows timing"}));quit(1 if failures else 0)
func fingerprint(window:DesktopObjectWindow)->Array:
 return [window.position,window.size,window._shared_crop,window.socket_catalogue(),window._camera.get_camera_transform(),window._camera.get_camera_projection()]
