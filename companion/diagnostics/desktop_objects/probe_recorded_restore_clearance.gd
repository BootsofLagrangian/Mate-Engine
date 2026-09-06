extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
 var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer")
 var foot:=Vector3(1.81110954284668,-1.33028185367584,-.104586124420166)
 var local_foot:=Vector3(-.241796970367432,0,1.10460007190704)
 scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
 scene.position=foot-scene.basis*local_foot
 scene.set_seat_scale(.90617672348496);scene.set_seat_setup(.1,144.999995010116)
 var before:=scene.seat_setup()
 var blocked:=DesktopWorkstationSetup.validate_setup_sweep(scene,.1,0,foot,.072,1.00092451572418)
 var result:=DesktopWorkstationSetup.find_restore_clearance(scene,foot,.072,1.00092451572418)
 var summary:=result.duplicate();summary.erase("swivel");summary.erase("roll")
 print("RECORDED_RESTORE blocked=",blocked.get("reason")," candidate=",summary," seat=",scene.socket_world("seat"))
 var okay:bool=blocked.get("reason")=="chair_sweep_hits_actor" and result.get("accepted",false) and scene.seat_setup()==before
 if okay:okay=result.swivel.accepted and result.roll.accepted and Vector3(result.target_world).y==foot.y and Vector3(result.target_world).distance_to(foot)<=.500001
 if okay:
  var solids:Array=[];DesktopObjectsHost._append_scene_solids(scene,solids)
  var nav:=DesktopSceneNavigation.new();var descriptor:Dictionary=result.navigation_geometry
  var configured:=nav.configure(descriptor.area,foot.y,solids,.072,1.00092451572418,descriptor.cell_size)
  var revalidated:Dictionary=nav.plan("recorded-restore",foot,result.target_world) if configured.get("ok",false) else {}
  okay=revalidated.get("accepted",false);print("RECORDED_RESTORE_ROUTE_REVALIDATED=",okay);nav.dispose()
 print("RECORDED_RESTORE_PASS=",okay," scope=exact_recorded_workstation_and_actor_geometry_without_other_objects_or_camera")
 scene.free();quit(0 if okay else 1)
