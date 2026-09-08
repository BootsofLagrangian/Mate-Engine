extends SceneTree
## Actual premium meshes, controlled geometry fixture; not live VRM/camera timing.
var passed := 0
var failures: Array[String] = []
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var baseline:Script
 var args:=OS.get_cmdline_user_args()
 var at:=args.find("--baseline")
 if at>=0 and at+1<args.size():baseline=load(args[at+1])
 var scene:=DesktopObjectContactScene.new();root.add_child(scene)
 if not scene.configure("computer"):push_error(scene.error);quit(2);return
 # Warm mesh-part decomposition identically before measuring either planner.
 var warm:Array=[];DesktopObjectsHost._append_scene_solids(scene,warm)
 var timings:Array=[]
 for fixture in [{"scale":.45,"start":Vector3(1,0,1),"accepted":true},{"scale":.45,"start":Vector3(-1,0,1),"accepted":true},{"scale":.45,"start":Vector3(0,0,1.3),"accepted":true},{"scale":.8,"start":Vector3(1,0,1),"accepted":false}]:
  scene.scale=Vector3.ONE*float(fixture.scale)
  var results:Array=[]
  var solvers:Array=[DesktopWorkstationSetup] if baseline==null else [baseline,DesktopWorkstationSetup]
  for solver in solvers:
   scene.set_seat_setup(0,0)
   var original:=scene.seat_setup()
   var started:=Time.get_ticks_usec()
   var plan:Dictionary=solver.plan(scene,fixture.start,.6,Vector3(0,.55,0),Vector3(0,-.3,-.3),.072,.95)
   var elapsed:=Time.get_ticks_usec()-started
   results.append(plan)
   timings.append({"scale":fixture.scale,"start":str(fixture.start),"solver":"baseline" if solver==baseline else "optimized","elapsed_us":elapsed,"accepted":plan.accepted,"attempts":plan.attempts})
   check(plan.accepted==fixture.accepted,"expected fixture admission")
   check(scene.seat_setup()==original,"scene setup restored")
  if baseline!=null:
   for key in ["accepted","reason","pullout_local_m","yaw_delta_deg","target_world","root_distance_factor","approach_path","setup_bounds_local","setup_parts_local","attempts","navigation_geometry"]:
    check(results[0].get(key)==results[1].get(key),"baseline result identical: "+key)
 # Existing sweep uses the maximum part radius for every axis pad. A near-Y
 # obstacle within that pad must remain in the optimized candidate list.
 var parts:Array=[AABB(Vector3(-1,0,-1),Vector3(2,.1,2)),AABB(Vector3.ZERO,Vector3(.1,.1,.1))]
 var obstacle:=AABB(Vector3(0,.1005,0),Vector3(.1,.01,.1))
 var candidates:=DesktopWorkstationSetup._fixed_part_candidates(parts,Transform3D.IDENTITY,[obstacle])
 check(candidates[1].size()==1,"global arc padding retained for small part Y broadphase")

 scene.scale=Vector3.ONE*.45
 scene.set_seat_setup(0,0)
 var original:=scene.seat_setup()
 var starts:Array=[]
 var moved_start:=Vector3(1.2,0,1.2)
 var validator:=func(_pull:float,_yaw:float)->Dictionary:
  starts.append(scene.seat_setup())
  return {"accepted":true,"actor_after_world":moved_start}
 var admitted:=DesktopWorkstationSetup.plan(scene,Vector3(1,0,1),.6,Vector3(0,.55,0),Vector3(0,-.3,-.3),.072,.95,[],Callable(),Callable(),PackedVector3Array(),validator)
 check(admitted.accepted and admitted.preparation_actor_world==moved_start,"moving actor endpoint becomes staging origin")
 check(starts.all(func(value):return value==original) and scene.seat_setup()==original,"callback sees original chair and planner restores it")
 check(admitted.approach_path[0].distance_to(moved_start)<.001,"planned path begins at moving actor endpoint")
 var calls:Array=[]
 var reject:=func(_pull:float,_yaw:float)->Dictionary:
  calls.append(true)
  return {"accepted":false,"terminal":true,"reason":"original_grasp_unreachable"}
 var denied:=DesktopWorkstationSetup.plan(scene,Vector3(1,0,1),.6,Vector3(0,.55,0),Vector3(0,-.3,-.3),.072,.95,[],Callable(),Callable(),PackedVector3Array(),reject)
 check(not denied.accepted and denied.reason=="original_grasp_unreachable" and calls.size()==1,"shared grasp failure terminates once")
 check(scene.seat_setup()==original,"terminal failure restores scene")
 var invalid:=func(_pull:float,_yaw:float)->Dictionary:return {"accepted":true,"actor_after_world":Vector3.INF}
 var malformed:=DesktopWorkstationSetup.plan(scene,Vector3(1,0,1),.6,Vector3(0,.55,0),Vector3(0,-.3,-.3),.072,.95,[],Callable(),Callable(),PackedVector3Array(),invalid)
 check(not malformed.accepted and scene.seat_setup()==original,"invalid replacement body endpoint never admits")
 print(JSON.stringify({"scope":"controlled actual premium mesh fixtures; no live camera/rig callbacks","timings":timings}))
 print("workstation planning: %d passed, %d failed" % [passed,failures.size()])
 for failure in failures:print("FAIL: "+failure)
 scene.queue_free();quit(0 if failures.is_empty() else 1)
