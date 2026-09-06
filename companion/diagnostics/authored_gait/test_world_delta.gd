extends SceneTree
var checks:=0
var failures:=0
func _init():call_deferred("run")
func check(ok:bool):
 checks+=1
 if not ok:failures+=1
func run():
 for character in ["mambo","cheval-grand","rice-shower","eishin-flash"]:
  var avatar:=VrmAvatar.new();root.add_child(avatar);avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  avatar.scale=Vector3.ONE*0.6
  var gait:=DesktopGait.new()
  for i in 60:
   avatar.reset_pose();gait.sample(Vector2.ZERO,Vector2.ZERO,180,true);gait.apply(avatar,1.0/60,true)
  var prior:=avatar.bone_global_position("leftFoot")
  for shift in [Vector3(0,0.001,0),Vector3(0,0.001,0),Vector3.ZERO,Vector3.ZERO]:
   avatar.position+=shift
   avatar.reset_pose();gait.sample(Vector2.ZERO,Vector2.ZERO,180,true,shift);gait.apply(avatar,1.0/60,true)
   var point:=avatar.bone_global_position("leftFoot")
   var error:=point.distance_to(prior)*300
   print(character," world shift=",shift," footdrift_px=",error," local_floor=",gait._support_height_offset)
   check(error<0.05)
  check(absf(gait._support_height_offset+0.002/0.6)<0.00001)
  gait.apply(avatar,1.0/60,false)
  check(gait._support_height_offset==0)
  avatar.free()
 print("WORLD_DELTA_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
