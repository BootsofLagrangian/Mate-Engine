extends SceneTree
## Exact same input pose comparison: authored swing joints must remain untouched.
var failures := 0
var rows: Array = []
const STYLES := {
 "uma_homewalk03_loop":{"version":1,"cycle_stride_leg_lengths":1.539550751,"contacts":{"left":[0.31,0.59],"right":[0.81,0.09]},"contact_blend_phase":0.04},
 "uma_walkunique09_loop":{"version":1,"cycle_stride_leg_lengths":4.165960726,"contacts":{"left":[[0.37,0.52],[0.88,0.01]],"right":[[0.06,0.30],[0.645,0.835]]},"contact_blend_phase":0.025}}
func _init(): call_deferred("run")
func run():
 for character in ["mambo","hachimi","cheval-grand","rice-shower","eishin-flash"]:
  var avatar := VrmAvatar.new()
  root.add_child(avatar)
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  for clip_name in STYLES:
   var clip := VrmaClip.new()
   if not clip.load_file(ProjectSettings.globalize_path("res://../assets/research/playful-walk/candidates/"+clip_name+".vrma")):
    failures+=1;continue
   for fps in [30,60]:
    var gait := DesktopGait.new()
    if not gait.configure_authored_locomotion(STYLES[clip_name]): failures+=1
    var length := avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(avatar.skeleton.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
    var stride := length*float(STYLES[clip_name].cycle_stride_leg_lengths)
    var dt: float = 1.0/fps
    var desktop := 0.0
    var max_swing := 0.0
    var max_slide := 0.0
    var max_clamp := 0.0
    var stance_samples := 0
    var swing_samples := 0
    var prior := {}
    avatar.rotation.y = PI/2
    for frame in int(clip.duration*fps*5):
     gait.phase = fposmod(frame*dt/clip.duration,1.0)
     avatar.reset_pose()
     avatar.apply_normalized_rotations(clip.sample(gait.phase*clip.duration),1)
     # Measured source hip Y is retained; horizontal root offset is irrelevant to joint angles.
     avatar.set_hips_offset(clip.sample_hips_offset(gait.phase*clip.duration)*avatar.skeleton.get_bone_global_rest(avatar.bone_index.hips).origin.y)
     var raw := {}
     for side in ["left","right"]: raw[side] = gait._source_leg_rotations(avatar,side)
     var travel: float = stride*dt/clip.duration
     desktop += travel
     gait.sample(Vector2(stride/clip.duration*300,0),Vector2(travel*300,0),300,true)
     gait.apply(avatar,dt,true)
     gait.compensate_movement(avatar)
     for side in gait.diagnostics:
      var d: Dictionary = gait.diagnostics[side]
      var point := avatar.bone_global_position(side+"Foot")+Vector3.RIGHT*desktop
      if float(d.contact_weight)==0:
       swing_samples +=1
       for id in raw[side]:
        var now:Quaternion = avatar.skeleton.get_bone_pose_rotation(id)
        max_swing = maxf(max_swing,1.0-absf(now.dot(raw[side][id])))
      if frame>fps and d.stance and prior.has(side) and prior[side].stance:
       stance_samples +=1
       max_slide=maxf(max_slide,point.distance_to(prior[side].point)*300)
       max_clamp=maxf(max_clamp,float(d.get("reach_clamp",0)))
      prior[side]={"point":point,"stance":d.stance}
    gait.apply(avatar,dt,false)
    var cancelled := gait._feet.is_empty() and gait.diagnostics.is_empty()
    var row := {"character":character,"clip":clip_name,"fps":fps,"swing_quaternion_error":max_swing,"max_plant_slide_px":max_slide,"max_reach_clamp_m":max_clamp,"stance_samples":stance_samples,"swing_samples":swing_samples,"cancelled":cancelled}
    rows.append(row);print(JSON.stringify(row))
    if max_swing > 0.000001 or not cancelled or stance_samples<10 or swing_samples<10 or max_slide>1.0: failures+=1
  avatar.free()
 var file:=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/authored_gait/direct-screening-summary.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"scope":"Direct DesktopGait on real source rotations and complete source hips; no full MotionPlayer/OS window rendering", "rows":rows},"  ")+"\n")
 print("AUTHORED_FAILURES=",failures)
 quit(1 if failures else 0)
