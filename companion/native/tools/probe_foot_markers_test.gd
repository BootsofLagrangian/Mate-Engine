extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var failures:=0;var maximum:=0.0
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  var avatar:=VrmAvatar.new();root.add_child(avatar)
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  avatar.scale=Vector3.ONE*.6;avatar.rotation.y=.7
  var markers=load("res://tools/probe_foot_markers.gd").new();markers.prepare(avatar)
  var player:=MotionPlayer.new();root.add_child(player);player.set_process(false);player.avatar=avatar
  player.load_vrma("sit_enter",ProjectSettings.globalize_path("res://../assets/motions/sit_enter.vrma"))
  var clip:VrmaClip=player.vrma_clips.sit_enter
  for phase in [0.0,.5,1.0]:
   var sk:=avatar.skeleton
   for idx in sk.get_bone_count():
    var rest:=sk.get_bone_rest(idx);sk.set_bone_pose_position(idx,rest.origin);sk.set_bone_pose_rotation(idx,rest.basis.get_rotation_quaternion());sk.set_bone_pose_scale(idx,rest.basis.get_scale())
   var rotations:=clip.sample(clip.duration*phase);var hips:=clip.sample_hips_offset(clip.duration*phase)
   avatar.apply_normalized_rotations(rotations,1)
   sk.set_bone_pose_position(avatar.bone_index.hips,sk.get_bone_rest(avatar.bone_index.hips).origin+hips*sk.get_bone_global_rest(avatar.bone_index.hips).origin.y)
   var live:Dictionary=markers.live_world();var source:Dictionary=markers.source_local(rotations,hips)
   if live.size()!=4:failures+=1
   for name in source:
    var error:float=live[name].distance_to(sk.global_transform*source[name]);maximum=maxf(maximum,error)
    if error>.000001:failures+=1
  player.free();avatar.free()
 print("FOOT_MARKER_FAILURES=",failures," max_engine_fk_error_m=",maximum)
 quit(failures)
