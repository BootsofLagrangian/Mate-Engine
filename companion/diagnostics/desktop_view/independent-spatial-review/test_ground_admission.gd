extends SceneTree
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(800,800)
 var camera:=Camera3D.new();root.add_child(camera)
 camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;camera.position=Vector3(0,0,4)
 var g:=ProjectedAvatarGeometry.new()
 for x in [-.1,.1]:
  for y in [0.0,1.0]:
   for z in [-.1,.1]:g.swept.append(Vector3(x,y,z));g.points.append(Vector3(x,y,z))
 var a:=Rect2(0,0,385,800)
 var b:=Rect2(405,0,395,800)
 var expected:=(25.011/200.0)
 for areas in [[a,b],[b,a]]:
  var result:=g.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,areas)
  check(result.ok,"union admits closest monitor")
  if result.ok:
   check(absf(result.point.x-expected)<.00001 and absf(result.point.z)<.00001,"nearest Euclidean ground point matches independent 200px/m closed form")
   check(result.point.y==0.0,"Y unchanged")
   check(b.encloses(result.bounds),"winner fits nearest right monitor")
   var repeated:=g.nearest_safe_ground(camera,result.point,1,Vector2.ZERO,areas)
   check(repeated.ok and not repeated.changed and repeated.point==result.point,"safe point exactly unchanged")
 check(not g.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[a,b],.1).ok,"budget below optimum rejects")
 check(not g.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[]).ok,"empty monitor set rejects")
 for scale in [0.0,-1.0,NAN]:check(not g.nearest_safe_ground(camera,Vector3.ZERO,scale,Vector2.ZERO,[a,b]).ok,"invalid scale rejected")
 check(not g.nearest_safe_ground(camera,Vector3.INF,1,Vector2.ZERO,[a,b]).ok,"nonfinite foot rejected")
 # Translated negative desktop coordinates preserve the same scene correction.
 var negative:=Vector2(-1920,-1080)
 var shifted:=g.nearest_safe_ground(camera,Vector3.ZERO,1,negative,[Rect2(a.position+negative,a.size),Rect2(b.position+negative,b.size)])
 check(shifted.ok and absf(shifted.point.x-expected)<.00001,"negative monitor origin preserves nearest world point")
 check(not g.nearest_safe_ground(null,Vector3.ZERO,1,Vector2.ZERO,[a,b]).ok,"null camera rejects before dereference")
 var detached:=Camera3D.new()
 check(not g.nearest_safe_ground(detached,Vector3.ZERO,1,Vector2.ZERO,[a,b]).ok,"detached camera rejects before projection")
 detached.free()
 check(not g.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.INF,[a,b]).ok,"nonfinite desktop origin rejects")
 for invalid_area in [null,"bad",Rect2(),Rect2(Vector2.INF,Vector2.ONE)]:
  check(not g.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[invalid_area]).ok,"invalid workarea rejects")
 print(JSON.stringify({"checks":checks,"failures":failures,"scope":"Independent closed-form ground-plane monitor-union minimizer, idempotence, budget and malformed numeric input; no Windows"}))
 quit(1 if failures else 0)
