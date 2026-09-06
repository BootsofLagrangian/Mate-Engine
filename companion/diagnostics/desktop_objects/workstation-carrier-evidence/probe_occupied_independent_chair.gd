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
  var entry_delta:Vector3=p.seated_transition_requirements("enter").source_full_endpoint_hips_local*1.2
  entry_delta.y=clearance+floor_y-Vector3(geometry.anchor).y
  p.start_seated_transition("enter",entry_delta)
  for frame in 84:
   p._process(1.0/60)
   a.position=entry_delta*float(p.seated_transition_state().root_progress)
  p.finish_seated_transition()
  var seated_origin:=a.position
  for frame in 60:p._process(1.0/60)
  var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer")
  var ratio:=clampf(clearance/.48,.75,1.25)
  scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6*ratio)
  scene.set_seat_setup(.1,-125)
  a.basis=Basis(Vector3.UP,PI/2).scaled(Vector3.ONE*.6)
  a.position=scene.socket_world("seat")-a.basis*Vector3(geometry.anchor)
  p.set_seated_carrier(1,PI/2);p._process(1.0/60)
  for pull in [.1,.2,.3,.4,.6]:
   scene.set_seat_setup(pull,-125)
   a.basis=Basis(Vector3.UP,PI/2).scaled(Vector3.ONE*.6)
   a.position=scene.socket_world("seat")-a.basis*Vector3(geometry.anchor)
   var snapshot:=p.seated_carrier_body_snapshot()
   var obstacles:=DesktopSeatedCarrierSweep.fixed_solids(scene,[])
   var result:=DesktopSeatedCarrierSweep.check(scene,snapshot,pull,0,obstacles,a.model.get_instance_id())
   print("CARRY ",character," pull ",pull," swivel ",result)
   if result.get("accepted",false):
    a.global_transform=result.target_avatar_transform
    scene.set_seat_setup(pull,0)
    snapshot=p.seated_carrier_body_snapshot()
    result=DesktopSeatedCarrierSweep.check(scene,snapshot,0,0,DesktopSeatedCarrierSweep.fixed_solids(scene,[]),a.model.get_instance_id())
    print("CARRY ",character," pull ",pull," roll ",result)
  scene.set_seat_setup(0,0)
  a.basis=Basis(Vector3.UP,deg_to_rad(215)).scaled(Vector3.ONE*.6)
  a.position=scene.socket_world("seat")-a.basis*Vector3(geometry.anchor)
  var final_check:=DesktopSeatedCarrierSweep.check(scene,p.seated_carrier_body_snapshot(),0,0,DesktopSeatedCarrierSweep.fixed_solids(scene,[]),a.model.get_instance_id())
  print("CARRY ",character," final_static ",final_check)
  var obstacles:=DesktopSeatedCarrierSweep.fixed_solids(scene,[])
  if final_check.get("obstacle_index",-1)>=0: audit_thigh(a,obstacles[final_check.obstacle_index],p.seated_carrier_body_snapshot())
  # Diagnostic only: keep desk full scale, adapt only chair to same source seat height.
  scene.basis=Basis(Vector3.UP,deg_to_rad(35)).scaled(Vector3.ONE*.6)
  scene.seat_node().scale=Vector3.ONE*ratio
  scene._sockets.seat=scene.seat_node().transform*Vector3(0,.48,.08)
  a.basis=Basis(Vector3.UP,deg_to_rad(215)).scaled(Vector3.ONE*.6)
  a.position=scene.socket_world("seat")-a.basis*Vector3(geometry.anchor)
  var new_solids:=DesktopSeatedCarrierSweep.fixed_solids(scene,[])
  print("INDEPENDENT_CHAIR_HEIGHT ",character," ratio=",ratio)
  audit_thigh(a,new_solids[6],p.seated_carrier_body_snapshot())
  scene.free()
  p.free();a.free()
 print("CARRY_SWEEP_FAILURES=",failures);quit(failures)

func audit_thigh(a:VrmAvatar,obstacle:Dictionary,snapshot:Dictionary):
 var inverse:Transform3D=Transform3D(obstacle.transform).affine_inverse()
 var box:AABB=obstacle.bounds
 for capsule in snapshot.capsules:
  if capsule.id=="left_thigh":print("THIGH_CAPSULE component=",box," a=",inverse*Transform3D(snapshot.transform)*Vector3(capsule.a)," b=",inverse*Transform3D(snapshot.transform)*Vector3(capsule.b)," radius_component=",float(capsule.radius)*RigBodyCapsules.scale_bound((inverse*Transform3D(snapshot.transform)).basis))
 var meshes:Array=[];a._collect_meshes(a.model,meshes)
 var low:=Vector3.INF;var high:=Vector3(-INF,-INF,-INF)
 var selected:=0;var inside:=0;var triangles:=0;var hits:=0
 for mesh:MeshInstance3D in meshes:
  if mesh.mesh==null or not mesh.is_visible_in_tree():continue
  var transforms:Array=[];var binds:Array=[]
  if mesh.skin:
   for bind in mesh.skin.get_bind_count():
    var idx:=mesh.skin.get_bind_bone(bind)
    if not mesh.skin.get_bind_name(bind).is_empty():idx=a.skeleton.find_bone(mesh.skin.get_bind_name(bind))
    transforms.append(a.skeleton.get_bone_global_pose(idx)*mesh.skin.get_bind_pose(bind));binds.append(idx)
  for surface in mesh.mesh.get_surface_count():
   var material_hits:=0
   var arrays:=mesh.mesh.surface_get_arrays(surface)
   var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
   var joints:Variant=arrays[Mesh.ARRAY_BONES];var weights:Variant=arrays[Mesh.ARRAY_WEIGHTS]
   var influences:=int(joints.size()/vertices.size()) if joints!=null and weights!=null and vertices.size()>0 else 0
   if influences==0:continue
   var points:=PackedVector3Array();var chosen:=PackedByteArray()
   for i in vertices.size():
    var p:=Vector3.ZERO;var total:=0.0;var thigh_weight:=0.0
    for slot in influences:
     var at:=i*influences+slot;var bind:=int(joints[at]);var weight:=float(weights[at])
     if weight<=0 or bind<0 or bind>=transforms.size():continue
     p+=(transforms[bind]*vertices[i])*weight;total+=weight
     if binds[bind]==a.bone_index.leftUpperLeg:thigh_weight+=weight
    var point:Vector3=inverse*a.skeleton.global_transform*(p/maxf(total,.000001))
    points.append(point);chosen.append(1 if thigh_weight>.25 else 0)
    if thigh_weight>.25:
     selected+=1;low=low.min(point);high=high.max(point)
     if box.has_point(point):inside+=1
   var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
   for ti in int(indices.size()/3):
    var ia:=indices[ti*3];var ib:=indices[ti*3+1];var ic:=indices[ti*3+2]
    if not chosen[ia] and not chosen[ib] and not chosen[ic]:continue
    triangles+=1
    var corners:Array[Vector3]=[points[ia],points[ib],points[ic],points[ic]]
    if DesktopSeatedCarrierSweep._hull_intersects_box(corners,box):hits+=1;material_hits+=1
   if material_hits>0:
    var mat:Material=mesh.get_active_material(surface)
    print("    HIT_MATERIAL mesh=",mesh.name," material=",mat.resource_name if mat!=null else "", " triangles=",material_hits)
 print("ACTUAL_THIGH vertices=",selected," inside_vertices=",inside," bounds=",AABB(low,high-low)," triangles=",triangles," triangle_box_hits=",hits)
