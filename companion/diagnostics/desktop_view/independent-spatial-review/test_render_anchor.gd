extends SceneTree
const Bridge=preload("res://scripts/autonomy_bridge.gd")
const REF=Vector2i(680,760)
const FOOT=Vector2(550,720)
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var screens:Array=[Rect2i(-1920,0,1920,1080),Rect2i(0,0,1920,1080)]
 var fallback:Rect2i=screens[1]
 for render_size in [Vector2i(1160,1120),Vector2i(1600,1440),Vector2i(1920,1760)]:
  var render_foot:=Vector2(render_size.x*.5,720+(render_size.y-760)*.5)
  for anchor in [Vector2(-600,950),Vector2(800,1000),Vector2(1100.25,940.25)]:
   var settings:={"window_pos_saved":true,"window_x":123,"window_y":456,"window_foot_x":anchor.x,"window_foot_y":anchor.y}
   var result:=Bridge.restore_render_position(settings,REF,FOOT,render_foot,screens,fallback)
   check((Vector2(result)+render_foot).distance_to(anchor)<.71,"global foot stable across gutters "+str(render_size)+" "+str(anchor))
  var legacy:={"window_pos_saved":true,"window_x":-1000,"window_y":200}
  var migrated:=Bridge.restore_render_position(legacy,REF,FOOT,render_foot,screens,fallback)
  check(Vector2(migrated)+render_foot==Vector2(-1000,200)+FOOT,"negative legacy reference origin migrates")
  var expected:=Vector2(Bridge.restore_position(false,0,0,REF,screens,fallback))+FOOT
  var removed:={"window_pos_saved":true,"window_x":0,"window_y":0,"window_foot_x":2100.0,"window_foot_y":900.0}
  var recovered:=Bridge.restore_render_position(removed,REF,FOOT,render_foot,screens,fallback)
  check(Vector2(recovered)+render_foot==expected,"removed right monitor foot falls back even if logical rectangle overlaps "+str(render_size))
  var edge:={"window_pos_saved":true,"window_x":0,"window_y":0,"window_foot_x":1000.0,"window_foot_y":1080.0}
  var boundary:=Bridge.restore_render_position(edge,REF,FOOT,render_foot,screens,fallback)
  check(Vector2(boundary)+render_foot==Vector2(1000,1080),"floor edge remains a valid saved anchor")
  var ignored:=edge.duplicate();ignored.window_pos_saved=false
  var unsaved:=Bridge.restore_render_position(ignored,REF,FOOT,render_foot,screens,fallback)
  check(Vector2(unsaved)+render_foot==expected,"unsaved flag ignores stale anchor")
  var corrupt:={"window_pos_saved":true,"window_x":-1000,"window_y":200,"window_foot_x":NAN,"window_foot_y":900.0}
  var rejected:=Bridge.restore_render_position(corrupt,REF,FOOT,render_foot,screens,fallback)
  check(Vector2(rejected)+render_foot==expected,"nonfinite explicit anchor safely falls back")
 print(JSON.stringify({"checks":checks,"failures":failures,"scope":"Independent persisted desktop foot/padding migration arithmetic; no window launch or settings mutation"}))
 quit(1 if failures else 0)
