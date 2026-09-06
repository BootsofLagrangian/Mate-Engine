extends SceneTree
var checks:=0
var failures:=0
var results:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
 checks+=1
 results.append({"check":label,"passed":ok})
 if not ok:failures+=1;push_error(label)
func run():
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 check(avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/mambo.vrm")),"real mini avatar loads")
 var gait:=DesktopGait.new()
 var valid:Dictionary={"version":1,"cycle_stride_leg_lengths":1.0,"contacts":{"left":[[0.85,0.15],[0.3,0.5]],"right":[0.2,0.7]},"contact_blend_phase":0.04}
 check(gait.configure_authored_locomotion(valid),"multiple and wrap contacts accepted")
 for bad in [null,[],[0.4],[0.0,1.0],[0.4,0.4],[[0.8,0.2],[0.1,0.4]],[[0.2,0.6],[0.3,0.5]],[0.3,NAN],[true,0.6]]:
  var changed:=valid.duplicate(true);changed.contacts.left=bad
  check(not gait.configure_authored_locomotion(changed),"malformed interval rejected: "+str(bad))
  check(gait.authored_locomotion==valid,"invalid interval cannot disturb live style")
 gait._weight=1.0
 gait.phase=0.95;gait._apply_authored_contacts(avatar,Vector3.ZERO)
 var prior:Vector3=gait._feet.left.target
 avatar.reset_pose();gait.phase=0.05;gait._apply_authored_contacts(avatar,Vector3(0.001,0,0))
 check(gait._feet.left.target.distance_to(prior-Vector3(0.001,0,0))<0.000001,"plant persists across zero phase wrap")
 avatar.reset_pose();gait.phase=0.25
 var raw:=gait._source_leg_rotations(avatar,"left")
 gait._apply_authored_contacts(avatar,Vector3(0.002,0,0))
 check(gait._source_leg_rotations(avatar,"left")==raw,"unplanted swing exactly keeps authored source")
 avatar.reset_pose();gait.phase=0.35
 var new_source:=avatar.skeleton.get_bone_global_pose(avatar.bone_index.leftFoot).origin
 gait._apply_authored_contacts(avatar,Vector3(0.004,0,0))
 check(gait._feet.left.target.distance_to(new_source)<0.000001,"second distinct contact acquires current source ankle")
 var target_before:Vector3=gait._feet.left.target
 check(gait.configure_authored_locomotion(valid) and gait._feet.left.target==target_before,"idempotent registration preserves active plant")
 gait.configure_authored_locomotion({})
 avatar.rotation.y=0.7;avatar.scale=Vector3.ONE*0.6
 var world:=Vector3(0.002,0.003,-0.001)
 gait.sample(Vector2(10,0),Vector2(1,0),180,true,world)
 var local:=gait._take_movement(avatar)
 check((avatar.skeleton.global_basis*local).distance_to(world)<0.000001,"actual world delta uses full rotated scaled basis inverse")
 gait.sample(Vector2(10,0),Vector2(1,0),180,true,world)
 gait.sample(Vector2(INF,0),Vector2.ZERO,180,true)
 check(gait._pending_world==Vector3.ZERO and gait._pending==Vector2.ZERO,"invalid sample drops unconsumed displacement")
 gait._support_height_offset=0.2
 gait.sample(Vector2.ZERO,Vector2.ZERO,180,false)
 check(gait._support_height_offset==0,"lost support clears prior support plane")
 gait._support_height_offset=0.2
 gait.sample(Vector2.ZERO,Vector2.ZERO,300,true)
 check(gait._support_height_offset==0,"changed effective scale clears prior support plane")
 gait.sample(Vector2(10,0),Vector2.ZERO,300,true)
 gait._feet={"left":{"target":Vector3.ZERO}};gait._weight=1
 gait.sample(Vector2(-10,0),Vector2.ZERO,300,true)
 check(gait._feet.is_empty() and gait._weight==0,"reversal reacquires feet without obsolete contact")
 gait._support_height_offset=0.2;gait.apply(avatar,1.0/60,false)
 check(gait._support_height_offset==0 and gait._feet.is_empty(),"disabled gait clears support and cached feet")
 avatar.free()
 var output:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/authored_gait/review-lifecycle.json"),FileAccess.WRITE)
 output.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"  ")+"\n")
 print("REVIEW_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
