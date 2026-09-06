extends SceneTree
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;push_error(label)
func sphere_snapshot(position:Vector3)->Dictionary:
 return {"space":"avatar_local","model_id":42,"transform":Transform3D(Basis.IDENTITY,position),"articulation_frozen":true,"capsules":[{"id":"torso","a":Vector3.ZERO,"b":Vector3.ZERO,"radius":.02}],"scope":"test_sphere"}
func run():
 var scene:=DesktopObjectContactScene.new();root.add_child(scene);check(scene.configure("computer"),"actual assembly loads")
 var snapshot:=sphere_snapshot(Vector3(0,.9,.5))
 var barrier:=AABB(Vector3(-.1,.8,.69),Vector3(.2,.2,.02))
 var model_id:=42
 check(DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,[barrier],model_id).accepted,"translation start endpoint clear")
 var no_obstacles:=DesktopSeatedCarrierSweep.check(scene,snapshot,.4,0,[],model_id)
 check(no_obstacles.accepted,"empty continuous translation admitted")
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,.4,0,[barrier],model_id).accepted,"thin midpath wall blocks despite clear endpoints")
 scene.set_seat_setup(.4,0);snapshot.transform=no_obstacles.target_avatar_transform
 check(DesktopSeatedCarrierSweep.check(scene,snapshot,.4,0,[barrier],model_id).accepted,"translation final endpoint independently clear")
 scene.set_seat_setup(0,0)
 var from:Transform3D=scene.seat_node().global_transform
 snapshot=sphere_snapshot(from*Vector3(1,.7,0))
 scene.set_seat_setup(0,180);var to:Transform3D=scene.seat_node().global_transform;scene.set_seat_setup(0,0)
 var mid:Vector3=from.interpolate_with(to,.5)*Vector3(1,.7,0)
 var arc_barrier:=AABB(mid-Vector3.ONE*.015,Vector3.ONE*.03)
 check(DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,[arc_barrier],model_id).accepted,"rotation endpoint starts clear")
 var rotated:=DesktopSeatedCarrierSweep.check(scene,snapshot,0,180,[],model_id)
 check(rotated.accepted,"empty continuous rotation admitted")
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,0,180,[arc_barrier],model_id).accepted,"rotation arc collision cannot hide between clear endpoints")
 scene.set_seat_setup(0,180);snapshot.transform=rotated.target_avatar_transform
 check(DesktopSeatedCarrierSweep.check(scene,snapshot,0,180,[arc_barrier],model_id).accepted,"rotation final endpoint independently clear")
 scene.set_seat_setup(0,0)
 var oriented:=Transform3D(Basis(Vector3.UP,PI/4),Vector3.ZERO)
 var obstacle:Dictionary={"bounds":AABB(Vector3(-.6,-.1,-.3),Vector3(1.2,.2,.6)),"transform":oriented,"id":"desk"}
 snapshot=sphere_snapshot(oriented*Vector3(0,0,.5))
 check(DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,[obstacle],model_id).accepted,"true oriented tabletop avoids phantom world-AABB corner")
 snapshot=sphere_snapshot(oriented*Vector3(0,0,.2))
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,[obstacle],model_id).accepted,"same actual oriented tabletop remains solid")
 snapshot=sphere_snapshot(Vector3(2,1,2));snapshot.articulation_frozen=false
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,.1,0,[],model_id).accepted,"unbounded articulation cannot claim rigid sweep")
 snapshot.articulation_enclosed=true
 check(DesktopSeatedCarrierSweep.check_stationary_envelope(scene,snapshot,[],model_id).accepted,"declared lifted-body envelope can be tested while stationary")
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,.1,0,[],model_id).accepted,"lift envelope cannot authorize carrier motion")
 snapshot.articulation_frozen=true
 check(not DesktopSeatedCarrierSweep.check(scene,snapshot,.1,0,[],43).accepted,"stale rig identity rejected")
 check(scene.seat_setup().pullout_local_m==0 and scene.seat_setup().yaw_delta_deg==0,"success and rejection preserve actual chair pose")
 check(DesktopSeatedCarrierSweep.fixed_solids(scene,[]).size()>0,"stationary desk components retained")
 scene.free();print("Carrier sweep geometry: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
