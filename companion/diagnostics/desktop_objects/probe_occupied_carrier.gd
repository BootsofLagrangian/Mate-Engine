extends SceneTree
var failures:=0
var capsule_reference:Dictionary={}
var capsule_error:=0.0
var pose_read_error:=0.0
var rows:Array=[]
func _init()->void:call_deferred("run")
func mesh_min(p:MotionPlayer)->float:
 var lowest:=INF;var sk:=p.avatar.skeleton
 for side in p.authored_seated_feet.foot_vertices:
  for candidate in p.authored_seated_feet.foot_vertices[side]:
   var point:=Vector3.ZERO
   for bind in candidate.influences:point+=(sk.get_bone_global_pose(bind[0])*bind[1]*candidate.vertex)*bind[2]
   lowest=minf(lowest,(sk.global_transform*(point/candidate.total)).y)
 return lowest
func run()->void:
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"));a.set_process(false)
  var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=a;p.idle_enabled=false;p.gaze_enabled=false
  for name in ["sit_enter","sit_idle","sit_exit"]:p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
  p.register_seated_transition("enter","sit_enter");p.register_seated_transition("exit","sit_exit")
  p._process(1.0/60)
  if p.set_seated_carrier(1,0):failures+=1
  var clearance:float=p.seated_transition_requirements("enter").source_seat_clearance_local
  p.set_seated_floor(clearance);var geometry:=a.calibrate_seated_pose(p.vrma_clips.sit_idle.sample(0))
  var floor_y:float=a.sole_calibration.floor_y
  var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer")
  var ratio:=clampf(clearance/.48,.5,1.25)
  scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
  scene.set_seat_scale(ratio)
  var requirements:Dictionary=p.seated_transition_requirements("enter")
  var anchors:Dictionary=a.contact_anchors()
  var setup:Dictionary=DesktopWorkstationSetup.plan(scene,Vector3(-1,0,1),.6,Vector3(anchors.sit)-Vector3(anchors.foot),requirements.source_root_delta_local,.072,a.compute_aabb().size.y*.6,[])
  var summary:Dictionary=setup.duplicate();summary.erase("setup_parts_local");print("PLANNED ",character," ",summary)
  if not setup.get("accepted",false):
   failures+=1;scene.free();p.free();a.free();continue
  var pull:float=setup.pullout_local_m
  var heading:float=setup.entry_facing_yaw
  var entry_delta:Vector3=requirements.source_root_delta_local
  entry_delta.x*=float(setup.root_distance_factor);entry_delta.z*=float(setup.root_distance_factor)
  entry_delta.y=clearance+floor_y-Vector3(geometry.anchor).y
  p.start_seated_transition("enter",entry_delta)
  for frame in 84:
   p._process(1.0/60)
   a.position=entry_delta*float(p.seated_transition_state().root_progress)
  p.finish_seated_transition()
  var seated_origin:=a.position
  for frame in 60:p._process(1.0/60)
  scene.set_seat_setup(pull,setup.yaw_delta_deg)
  a.basis=Basis(Vector3.UP,heading).scaled(Vector3.ONE*.6)
  a.position=scene.socket_world("seat")-a.basis*Vector3(geometry.anchor)
  p.set_seated_carrier(1,heading);p._process(1.0/60)
  var snapshot:=p.seated_carrier_body_snapshot()
  var obstacles:=DesktopSeatedCarrierSweep.fixed_solids(scene,[])
  var result:=DesktopSeatedCarrierSweep.check(scene,snapshot,pull,0,obstacles,a.model.get_instance_id())
  print("CARRY ",character," swivel ",result)
  if not result.get("accepted",false):failures+=1
  if result.get("accepted",false):
   a.global_transform=result.target_avatar_transform
   scene.set_seat_setup(pull,0)
   snapshot=p.seated_carrier_body_snapshot()
   result=DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,DesktopSeatedCarrierSweep.fixed_solids(scene,[]),a.model.get_instance_id())
   print("CARRY ",character," roll ",result)
   if not result.get("accepted",false):failures+=1
   else:
    a.global_transform=result.target_avatar_transform;scene.set_seat_setup(0,0)
    var envelope:Dictionary=p.seated_carrier_lift_envelope()
    var lower:Dictionary=DesktopSeatedCarrierSweep.check_stationary_envelope(scene,envelope,DesktopSeatedCarrierSweep.fixed_solids(scene,[]),a.model.get_instance_id())
    print("CARRY ",character," lower_envelope ",lower)
    if not lower.get("accepted",false):failures+=1
    p.set_seated_carrier(0,deg_to_rad(215));p._process(1.0/60);p.clear_seated_carrier()
    for side in ["left","right"]:
     var target:Vector3=scene.socket_world("keyboard_"+side)
     var reached:bool=a.apply_hand_contact(side,target)
     var error:float=a.bone_global_position(side+"Hand").distance_to(target)
     print("REACH ",character," ",side," reached=",reached," error_m=",error)
     if not reached or error>.00001:failures+=1
  scene.free()
  p.free();a.free()
 print("CARRY_SWEEP_FAILURES=",failures);quit(failures)
