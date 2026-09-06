extends SceneTree
var rows: Array=[]
var failures:=0
func _init(): call_deferred("run")
func run():
 var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../motion-assets.json")))
 var entries:Dictionary={}
 for e in catalog.motions:
  if e.name in ["playful_strut","mambo_goofy_walk"]:entries[e.name]=e
 for character in ["mambo","hachimi","cheval-grand","rice-shower","eishin-flash"]:
  var avatar:=VrmAvatar.new();root.add_child(avatar)
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  for clip_name in entries:
   for fps in [30,60]:
    avatar.rotation.y=PI/2
    var motion:=MotionPlayer.new();root.add_child(motion);motion.set_process(false);motion.avatar=avatar
    motion.idle_enabled=false;motion.gaze_enabled=false
    motion.load_vrma(clip_name,ProjectSettings.globalize_path("res://../assets/motions/"+clip_name+".vrma"))
    motion.register_locomotion_clip(clip_name,true)
    motion.register_locomotion_style(clip_name,entries[clip_name].locomotion_style)
    motion.play_vrma(clip_name,1,true);motion.set_locomotion_direction(Vector2.RIGHT)
    var length:=avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
    var clip:VrmaClip=motion.vrma_clips[clip_name]
    var speed:float=length*float(entries[clip_name].locomotion_style.cycle_stride_leg_lengths)/clip.duration*300
    var desktop:=0.0;var max_slide:=0.0;var max_clamp:=0.0;var max_swing:=0.0;var samples:=0;var swings:=0;var prior:Dictionary={}
    for frame in int(clip.duration*fps*5):
     motion._process(1.0/fps)
     desktop+=speed/fps
     motion.set_locomotion_sample(Vector2(speed,0),Vector2(speed/fps,0),300,true)
     for side in motion.gait.diagnostics:
      var d:Dictionary=motion.gait.diagnostics[side]
      var foot:=avatar.bone_global_position(side+"Foot")+Vector3.RIGHT*desktop/300
      if frame>fps and d.stance and prior.has(side) and prior[side].stance:
       samples+=1;max_slide=maxf(max_slide,foot.distance_to(prior[side].foot)*300);max_clamp=maxf(max_clamp,float(d.get("reach_clamp",0)))
      if frame>fps and float(d.contact_weight)==0:
       swings+=1
       for id in motion.gait._feet[side].source_rotations:
        var q:Quaternion=avatar.skeleton.get_bone_pose_rotation(id)
        max_swing=maxf(max_swing,1.0-absf(q.dot(motion.gait._feet[side].source_rotations[id])))
      prior[side]={"stance":d.stance,"foot":foot}
    var row:Dictionary={"character":character,"clip":clip_name,"fps":fps,"plant_samples":samples,"swing_samples":swings,"max_plant_slide_px":max_slide,"max_reach_clamp_m":max_clamp,"swing_quaternion_error":max_swing}
    rows.append(row);print(JSON.stringify(row))
    # Larger rigs are measured transfer cases; the two real mini rigs are acceptance.
    if character in ["mambo","hachimi"] and (max_slide>1 or max_swing>0.000001 or samples<10):failures+=1
    motion.free()
  avatar.free()
 var output:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/authored_gait/runtime-summary.json"),FileAccess.WRITE)
 output.store_string(JSON.stringify({"failures":failures,"scope":"Production MotionPlayer with production installed source metadata; all five real rigs, 30/60fps, five periods each; mini rigs acceptance, three larger rigs disclosed transfer measurements","rows":rows},"  ")+"\n")
 print("RUNTIME_FAILURES=",failures);quit(1 if failures else 0)
