extends SceneTree
var failures:=0
func _init()->void:call_deferred("run")
func verify(value:bool,label:String)->void:
 print(label," ",value)
 if not value:failures+=1
func run()->void:
 var scene:=DesktopObjectContactScene.new();root.add_child(scene)
 if not scene.configure("computer"):push_error(scene.error);quit(2);return
 var original:=scene.seat_setup()
 var from:Transform3D=scene.seat_node().global_transform
 var snapshot:={"space":"avatar_local","model_id":1,"transform":from,"articulation_frozen":true,"capsules":[{"id":"fixture","a":Vector3(.35,1,0),"b":Vector3(.35,1.05,0),"radius":.01}],"scope":"synthetic capsule for path collision regression"}
 var a:=DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[],1)
 var b:=DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[],1,[Vector2.ZERO,Vector2.ONE])
 verify(a.accepted and b.accepted and a.body_bounds_world==b.body_bounds_world and a.target_avatar_transform==b.target_avatar_transform and a.segments==b.segments,"default and explicit linear equivalent")
 scene.set_seat_setup(.25,45)
 var center:Vector3=scene.seat_node().global_transform*Vector3(.35,1.025,0)
 scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
 var obstacle:=AABB(center-Vector3.ONE*.015,Vector3.ONE*.03)
 verify(not DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[obstacle],1).accepted,"linear midpath collision rejected")
 var path:=[Vector2.ZERO,Vector2(.05,.8),Vector2.ONE]
 var curved:=DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[obstacle],1,path)
 verify(curved.accepted,"nonlinear timing avoids linear obstacle")
 scene.set_seat_setup(.025,72)
 var curve_center:Vector3=scene.seat_node().global_transform*Vector3(.35,1.025,0)
 scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
 verify(not DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[AABB(curve_center-Vector3.ONE*.015,Vector3.ONE*.03)],1,path).accepted,"actual nonlinear intermediate collision rejected")
 for invalid in [[Vector2.ZERO],[Vector2.ZERO,Vector2(.6,.4),Vector2(.5,.5),Vector2.ONE],[Vector2.ZERO,Vector2(INF,0),Vector2.ONE],[Vector2(.01,0),Vector2.ONE],[Vector2.ZERO,Vector2(1,1.1)],[Vector2.ZERO,"bad",Vector2.ONE]]:
  verify(not DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[],1,invalid).accepted and scene.seat_setup()==original,"invalid trajectory rejected without mutation")
 verify(not DesktopSeatedCarrierSweep.check(scene,snapshot,100,90,[],1,path).accepted and scene.seat_setup()==original,"invalid setup target restored")
 var dense:Array=[]
 for i in 65:dense.append(Vector2(float(i)/64,float(i)/64))
 verify(DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[],1,dense).accepted,"65 point trajectory accepted")
 dense.insert(1,Vector2.ZERO)
 verify(not DesktopSeatedCarrierSweep.check(scene,snapshot,.5,90,[],1,dense).accepted,"overlong trajectory rejected")
 for pair in [Vector2(170,-170),Vector2(-170,170)]:
  scene.set_seat_setup(0,pair.x)
  var wrap_original:=scene.seat_setup()
  var wrap_from:Transform3D=scene.seat_node().global_transform
  snapshot.transform=wrap_from
  var wrapped:=DesktopSeatedCarrierSweep.check(scene,snapshot,0,pair.y,[],1)
  verify(wrapped.accepted and wrapped.segments<=5 and scene.seat_setup()==wrap_original,"wrapped yaw follows short arc and restores")
  scene.set_seat_setup(0,0)
  var long_center:Vector3=scene.seat_node().global_transform*Vector3(.35,1.025,0)
  scene.set_seat_setup(0,pair.x)
  verify(DesktopSeatedCarrierSweep.check(scene,snapshot,0,pair.y,[AABB(long_center-Vector3.ONE*.02,Vector3.ONE*.04)],1).accepted,"wrapped yaw avoids untraveled long arc")
 scene.set_seat_setup(0,180)
 snapshot.transform=scene.seat_node().global_transform
 snapshot.articulation_frozen=false
 snapshot.articulation_enclosed=true
 verify(DesktopSeatedCarrierSweep.check(scene,snapshot,0,-180,[],1).accepted,"opposite signed180 is stationary envelope")
 scene.set_seat_setup(original.pullout_local_m,original.yaw_delta_deg)
 verify(scene.seat_setup()==original,"all paths restore setup")
 scene.free();quit(1 if failures else 0)
