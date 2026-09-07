extends SceneTree
var failures:=0
func _init()->void:call_deferred("run")
func verify(value:bool,label:String)->void:
 print(label," ",value)
 if not value:failures+=1
func run()->void:
 var bounded:=true
 var changed:=false
 var prior:=Vector3.ZERO
 for i in 1200:
  var pose:=AuthoredSeatedPresence.offsets(i/60.0,Vector2.ONE,true,true,true)
  for bone in pose:
   bounded=bounded and bone in ["head","neck","chest","spine"] and Vector3(pose[bone]).length()<7
  changed=changed or Vector3(pose.head).distance_to(prior)>.0001
  prior=pose.head
 verify(bounded and changed,"bounded time-varying upper body without root leg arm channels")
 verify(AuthoredSeatedPresence.offsets(1,Vector2.ZERO,false,false,false).is_empty(),"disabled idle and gaze emit no offsets")
 verify(AuthoredSeatedPresence.offsets(NAN,Vector2.ZERO,true,true,true).is_empty(),"invalid source time rejected")
 var args:=OS.get_cmdline_user_args()
 if args.size()!=2:push_error("avatar.vrm sit_idle.vrma required");quit(2);return
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 if not avatar.load_from_file(args[0]):push_error("avatar load failed");quit(2);return
 var clip:=VrmaClip.new()
 if not clip.load_file(args[1]):push_error("clip load failed");quit(2);return
 var player:=MotionPlayer.new()
 player.avatar=avatar
 player._contact_pose="sit"
 player.upper_body.contact_locked=true
 var unchanged:=true
 var head_changes:=0
 for frame in 300:
  player.elapsed=frame/60.0
  avatar.reset_pose()
  avatar.apply_normalized_rotations(clip.sample(fmod(player.elapsed,clip.duration)),1)
  var before:={}
  for bone in avatar.bone_index:before[bone]=avatar.skeleton.get_bone_pose_rotation(avatar.bone_index[bone])
  player.seated_presence.apply(player,1.0/60)
  for bone in before:
   if bone not in ["head","neck","chest","spine"]:
    unchanged=unchanged and avatar.skeleton.get_bone_pose_rotation(avatar.bone_index[bone]).is_equal_approx(before[bone])
  if not avatar.skeleton.get_bone_pose_rotation(avatar.bone_index.head).is_equal_approx(before.head):head_changes+=1
 verify(unchanged and head_changes>200,"actual Cheval source legs pelvis arms preserved while head animates")
 player.seated_carrier.active=true
 var frozen_head:=avatar.skeleton.get_bone_pose_rotation(avatar.bone_index.head)
 player.seated_presence.apply(player,1.0/60)
 verify(player.seated_presence.diagnostics.is_empty() and avatar.skeleton.get_bone_pose_rotation(avatar.bone_index.head)==frozen_head,"active carrier suppresses additive layer without pose mutation")
 player.seated_carrier.active=false
 player.seated_presence.apply(player,1.0/60)
 verify(player.seated_presence.weight<.001,"carrier release re-enters with eased near-zero amplitude")
 player.free();avatar.free()
 quit(1 if failures else 0)
