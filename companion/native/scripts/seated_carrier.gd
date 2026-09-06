class_name SeatedCarrier
extends RefCounted
## Procedural additive foot clearance while a seated support carries the body.
## The authored seated pose remains primary. This is not authored chair pushing.
var active:=false
var lift:=0.0
var diagnostics:Dictionary={}
var legs:=LegIK.new()
var phase_time:=0.0
var started_at:=0.0
var model_id:=0
var clip_id:=0
var reference_epoch:=0
var playback_start:=0.0
var idle_start:=0.0
var floor_clearance:=INF
var floor_height:=INF
var body_pose:Dictionary={}
var hips_offset:=Vector3.ZERO
var lift_reference:Dictionary={}
func capture(player:MotionPlayer)->void:
 var a:=player.avatar
 phase_time=player.elapsed-player._seated_idle_start
 started_at=player.elapsed
 playback_start=player._vrma_start
 idle_start=player._seated_idle_start
 reference_epoch=player.authored_seated_feet.reference_epoch
 floor_clearance=a.seated_floor.clearance
 floor_height=a.seated_floor.floor_y
 model_id=a.model.get_instance_id()
 clip_id=player.vrma_clips.sit_idle.get_instance_id()
 body_pose.clear()
 lift_reference.clear()
 for name in a.bone_index:
  if name in ["leftEye","rightEye","jaw"]:continue
  var idx:int=a.bone_index[name]
  body_pose[idx]=a.skeleton.get_bone_pose_rotation(idx)
 hips_offset=a.get_hips_offset()

func valid(player:MotionPlayer)->bool:
 if player==null or player.avatar==null or not player.avatar.has_model():return false
 if player.avatar.seated_floor.clearance!=floor_clearance or player.avatar.seated_floor.floor_y!=floor_height:return false
 if player._vrma_start!=playback_start or player._seated_idle_start!=idle_start or player.authored_seated_feet.reference_epoch!=reference_epoch:return false
 return player.current_contact_pose()=="sit" and not player.seated_transition.active and not player._preview and not player._custom_motion and player._vrma_name=="sit_idle" and player.vrma_clips.has("sit_idle") and player.vrma_clips.sit_idle.get_instance_id()==clip_id and player.avatar.model.get_instance_id()==model_id and is_finite(player.avatar.seated_floor.clearance) and player.authored_seated_feet.active

func restore_body(player:MotionPlayer)->void:
 if not active:return
 if not valid(player):clear(player);return
 for idx in body_pose:player.avatar.skeleton.set_bone_pose_rotation(idx,body_pose[idx])
 player.avatar.set_hips_offset(hips_offset)

func clear(player:MotionPlayer=null)->void:
 if active and player!=null and player.avatar!=null and player.avatar.has_model() and player.avatar.model.get_instance_id()==model_id and player._vrma_name=="sit_idle" and player._vrma_start==playback_start and player._seated_idle_start==idle_start:
  var pause:=maxf(0,player.elapsed-started_at)
  player._seated_idle_start+=pause
  player._vrma_start+=pause
 active=false;lift=0;diagnostics.clear();body_pose.clear();lift_reference.clear()
func apply(player:MotionPlayer)->void:
 if not active:return
 var a:=player.avatar
 if not valid(player):
  clear(player);return
 var sk:=a.skeleton
 if lift_reference.is_empty():
  lift_reference={"snapshot":a.body_capsule_snapshot(),"to_avatar":a.global_transform.affine_inverse()*sk.global_transform,"legs":{},"clearance":{}}
  for side in ["left","right"]:
   var points:Array[Vector3]=[]
   for suffix in ["UpperLeg","LowerLeg","Foot"]:
    if not a.bone_index.has(side+suffix):points.clear();break
    points.append(sk.get_bone_global_pose(a.bone_index[side+suffix]).origin)
   if points.size()==3:
    lift_reference.legs[side]=points
    var rest_hip:=sk.get_bone_global_rest(a.bone_index[side+"UpperLeg"]).origin
    var rest_knee:=sk.get_bone_global_rest(a.bone_index[side+"LowerLeg"]).origin
    var rest_ankle:=sk.get_bone_global_rest(a.bone_index[side+"Foot"]).origin
    lift_reference.clearance[side]=(rest_hip.distance_to(rest_knee)+rest_knee.distance_to(rest_ankle))*.04
 var ready:=lift>=.999;var limited:=false;var minimum:=INF;var clearance_min:=INF;var maximum_error:=0.0
 for side in ["left","right"]:
  if not a.bone_index.has(side+"UpperLeg") or not a.bone_index.has(side+"LowerLeg") or not a.bone_index.has(side+"Foot"):
   limited=true;ready=false;continue
  var upper:int=a.bone_index[side+"UpperLeg"];var knee:int=a.bone_index[side+"LowerLeg"];var ankle:int=a.bone_index[side+"Foot"]
  var length:=sk.get_bone_global_rest(upper).origin.distance_to(sk.get_bone_global_rest(knee).origin)+sk.get_bone_global_rest(knee).origin.distance_to(sk.get_bone_global_rest(ankle).origin)
  var clearance:=length*.04
  var foot:=sk.get_bone_global_pose(ankle)
  legs.solve(a,side,foot.origin+Vector3.UP*clearance*lift,1,foot.basis.orthonormalized(),true)
  var error:float=legs.diagnostics.get(side,{}).get("error",INF)
  var gap:=player.authored_seated_feet._support_min(side)-a.seated_floor.floor_y
  if player.authored_seated_feet.diagnostics.has(side):
   player.authored_seated_feet.diagnostics[side]["floor_gap_local"]=gap
   player.authored_seated_feet.diagnostics[side]["world_plant_claimed"]=false
  var reached:=is_finite(gap) and gap>=clearance*.90 and error<length*.005
  limited=limited or error>=length*.005
  ready=ready and reached
  minimum=minf(minimum,gap);clearance_min=minf(clearance_min,clearance);maximum_error=maxf(maximum_error,error)
 diagnostics={"active":true,"lift":lift,"ready":ready,"limited":limited,"clearance_local":clearance_min,"min_gap_local":minimum,"reach_error_local":maximum_error,"world_plant_claimed":false,"policy":"procedural_seated_carry_clearance","body_frozen":true,"source_phase":phase_time,"source_clip_id":clip_id,"model_id":model_id}
 for side in ["left","right"]:
  if player.authored_seated_feet.diagnostics.has(side):player.authored_seated_feet.diagnostics[side]["carrier"]=diagnostics.duplicate()
