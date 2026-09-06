extends SceneTree
var failures:=[]
var checks:=0
func check(value:bool,label:String):
 checks+=1
 if not value:failures.append(label)
func _init():call_deferred("run")
func run():
 await process_frame
 var geometry:=ProjectedAvatarGeometry.new()
 geometry.swept=PackedVector3Array([Vector3.ZERO])
 var area:=Rect2(-100,-100,2000,2000)
 var detached:=Camera3D.new()
 check(geometry.nearest_safe_ground(null,Vector3.ZERO,1,Vector2.ZERO,[area]).reason=="invalid_camera","null camera")
 check(geometry.nearest_safe_ground(detached,Vector3.ZERO,1,Vector2.ZERO,[area]).reason=="invalid_camera","detached camera")
 detached.free()
 var camera:=Camera3D.new();root.add_child(camera);camera.position.z=3.6
 check(geometry.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2(INF,0),[area]).reason=="invalid_desktop_origin","nonfinite desktop origin")
 for invalid in [null,"monitor",{},Rect2(0,0,0,100),Rect2(INF,0,100,100),Rect2(0,0,-1,100)]:
  check(geometry.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[invalid]).reason=="invalid_workarea","invalid workarea "+str(invalid))
 check(geometry.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[Rect2i(area)]).ok,"Rect2i accepted")
 check(not geometry.nearest_safe_ground(camera,Vector3.ZERO,1,Vector2.ZERO,[]).ok,"empty monitors rejected")
 var report:={"checks":checks,"failures":failures,"source_sha256":FileAccess.get_sha256("res://scripts/projected_avatar_geometry.gd")}
 FileAccess.open("res://../diagnostics/desktop_view/scene-ground-guards.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("SCENE_GROUND_GUARDS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
