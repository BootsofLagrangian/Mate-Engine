class_name AuthoredSeatedPresence
extends RefCounted
## Small additive life after authored seated pose, before deliberate gestures.
## Pelvis/legs/arms are never written; workstation host re-solves wrist targets.
## Occupied carrier sweeps keep their exact captured articulation.
var weight:=0.0
var _progress:=0.0
var _lock_weight:=0.0
var diagnostics:Dictionary={}
func reset()->void:
 weight=0;_progress=0;_lock_weight=0;diagnostics.clear()
static func offsets(time:float,gaze:Vector2,idle:bool,attention:bool,locked:bool)->Dictionary:
 var result:Dictionary={}
 if not is_finite(time) or not gaze.is_finite():return result
 var breath:=sin(time*TAU/4.2)
 if idle:
  result.head=Vector3(-.55*breath+.25*sin(time*.63),.65*sin(time*.41)+.2*sin(time*.17),.25*sin(time*.53))
  result.chest=Vector3((.35 if locked else .65)*breath,0,0)
  result.spine=Vector3((.15 if locked else .3)*breath,0,(.075 if locked else .15)*sin(time*TAU/9.0))
 if attention:
  var yaw:=clampf((gaze.x-.5)*18,-6,6)
  var pitch:=clampf((gaze.y-.45)*12,-4,4)
  result.head=Vector3(result.get("head",Vector3.ZERO))+Vector3(pitch*.7,yaw*.7,0)
  result.neck=Vector3(pitch*.3,yaw*.3,0)
 return result
func apply(player:MotionPlayer,delta:float)->void:
 var allowed:=player.current_contact_pose()=="sit" and not player.seated_carrier.active and not player.seated_transition.active and not player._preview and not player._custom_motion
 if not allowed:
  # A carrier freezes the previous final pose itself; never perturb its proof.
  reset();return
 _progress=move_toward(_progress,1.0,maxf(delta,0)/.8)
 weight=_progress*_progress*_progress*(_progress*(_progress*6-15)+10)
 _lock_weight=lerpf(_lock_weight,1.0 if player.upper_body.contact_locked else 0.0,1.0-exp(-6.0*maxf(delta,0)))
 var pose:=offsets(player.elapsed,player._gaze_current,player.idle_enabled,player.gaze_enabled,false)
 var locked_pose:=offsets(player.elapsed,player._gaze_current,player.idle_enabled,player.gaze_enabled,true)
 for bone in ["chest","spine"]:
  if pose.has(bone):pose[bone]=Vector3(pose[bone]).lerp(locked_pose[bone],_lock_weight)
 for bone in pose:pose[bone]*=weight
 player.avatar.add_pose_offsets(pose)
 diagnostics={"active":not pose.is_empty(),"weight":weight,"contact_locked":player.upper_body.contact_locked,"offsets_deg":pose.duplicate(),"preserves_lower_body":true,"policy":"post_authored_stationary_seated_presence"}
