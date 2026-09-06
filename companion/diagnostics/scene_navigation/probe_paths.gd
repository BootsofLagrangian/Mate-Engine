extends SceneTree
const Navigation = preload("res://scripts/desktop_scene_navigation.gd")
var failures:=0
var checks:=0
var rows:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func run():
 for fps in [30,60,120]:
  for name in ["depth_only","diagonal","around_chair","blocked_wall"]:
   var nav=Navigation.new()
   var obstacles:Array=[]
   var start:=Vector3(-1.4,0,-1.2)
   var goal:=Vector3(1.4,0,1.2)
   if name=="depth_only":goal=Vector3(-1.4,0,1.2)
   if name=="around_chair":obstacles=[AABB(Vector3(-0.6,0,-0.6),Vector3(1.2,1.0,1.2))]
   if name=="blocked_wall":obstacles=[AABB(Vector3(-0.3,0,-2),Vector3(0.6,1.0,4))]
   var configured:Dictionary=nav.configure(Rect2(-2,-2,4,4),0,obstacles,0.12,1.6,0.08)
   check(configured.ok,name+" configured")
   var requested:Dictionary=nav.plan(name,start,goal,0.6)
   if name=="blocked_wall":
    check(not requested.accepted and requested.reason=="unreachable","wall rejects disconnected route")
    nav.dispose();continue
   check(requested.accepted,name+" planned")
   if not requested.accepted:nav.dispose();continue
   var events:Array=[]
   nav.finished.connect(func(id,outcome):events.append([id,outcome]))
   var distance:=0.0
   var max_ground:=0.0
   var min_z:=start.z
   var max_z:=start.z
   var max_step:=0.0
   var trace:Array=[]
   for frame in fps*40:
    var sample:Dictionary=nav.tick(1.0/fps)
    distance+=sample.distance_m
    max_ground=maxf(max_ground,absf(sample.position_world.y))
    min_z=minf(min_z,sample.position_world.z);max_z=maxf(max_z,sample.position_world.z)
    max_step=maxf(max_step,sample.delta_world.length())
    check(nav.is_navigable(sample.position_world),name+" every rendered foot navigable")
    if frame%maxi(1,fps/10)==0:trace.append([sample.position_world.x,sample.position_world.y,sample.position_world.z])
    if sample.arrived:break
   check(not nav.active and nav.position_world.distance_to(goal)<0.00001,name+" exact finitearrival")
   check(events==[[name,"arrived"]],name+" terminalonce")
   check(max_ground==0,name+" physicalgroundYinvariant")
   check(max_z-min_z>2.0,name+" actualdepthtravel")
   check(absf(distance-float(requested.distance_m))<0.0001,name+" truepatharc drivesdistance")
   if name=="around_chair":check(distance>start.distance_to(goal)+0.2,"actualobstacledetour")
   rows.append({"name":name,"fps":fps,"distance_m":distance,"straight_distance_m":start.distance_to(goal),"path_points":requested.path.size(),"max_ground_error_m":max_ground,"max_step_m":max_step,"trace":trace})
   nav.dispose()
 var probe=Navigation.new()
 probe.configure(Rect2(-2,-2,4,4),0,[AABB(Vector3(-.3,0,-.3),Vector3(.6,1,.6))])
 check(not probe.plan("inside",Vector3(-1,0,-1),Vector3.ZERO).accepted,"targetinsidefurniture rejected")
 check(not probe.plan("offground",Vector3(-1,0,-1),Vector3(1,.3,1)).accepted,"differentphysicalground rejected")
 check(probe.plan("cancel",Vector3(-1,0,-1),Vector3(-1,0,1)).accepted,"cancelroute starts")
 var cancelled:Array=[];probe.finished.connect(func(id,outcome):cancelled.append([id,outcome]))
 probe.tick(.1);probe.cancel("user");probe.cancel("user")
 check(cancelled==[["cancel","user"]],"cancelterminalonce")
 var before:Vector3=probe.position_world;probe.tick(.1);check(probe.position_world==before,"cancelstopsworldtravel")
 probe.dispose()
 var output:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/scene_navigation/path-summary.json"),FileAccess.WRITE)
 output.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Built-in NavigationServer3D real XZ navmesh+obstacles+paths; fixed-ground integration, no native window projection","rows":rows},"  ")+"\n")
 print("SCENE_NAV_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
