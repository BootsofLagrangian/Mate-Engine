extends SceneTree
func _initialize():call_deferred("run")
func run():
 var rows:Array=[]
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  var avatar:=VrmAvatar.new();root.add_child(avatar);avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  var p:=MotionPlayer.new();root.add_child(p);p.set_process(false);p.avatar=avatar;p.load_vrma("sit_enter",ProjectSettings.globalize_path("res://../assets/motions/sit_enter.vrma"))
  var clip:VrmaClip=p.vrma_clips.sit_enter
  var measured:=SeatedGeometryCalibrator.measure(avatar,clip.sample(clip.duration),false,false)
  var height:float=avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y
  var hip_offset:Vector3=clip.sample_hips_offset(clip.duration)*height
  rows.append({"character":character,"canonical_anchor":str(measured.anchor),"source_full_hips_offset":str(hip_offset),"source_seat_clearance_local":measured.anchor.y+hip_offset.y-float(avatar.sole_calibration.floor_y),"current_nominal_chair":.48})
  p.free();avatar.free()
 print(JSON.stringify(rows));quit()
