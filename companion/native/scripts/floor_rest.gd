class_name FloorRest
extends RefCounted
## Authored floor seating keeps the standing ground coordinate frame. It must
## never enter the chair pivot/seat-height retarget path. Preparation is cached
## per rig and source clips; runtime samples curves and cached foot markers.
signal finished(outcome:String)
const ALIASES:Dictionary={"enter":"floor_rest_enter","idle":"floor_rest_idle","exit":"floor_rest_exit"}
var active:=false
var phase:=""
var time:=0.0
var diagnostics:Dictionary={}
var profile:Dictionary={}
var contacts:=AuthoredFootContacts.new()
var _cache_key:Array=[]
var _model_id:=0
var _source_ids:Dictionary={}
var _from:Dictionary={}
var _from_hips:=Vector3.ZERO
var _height:=1.0
func available(clips:Dictionary)->bool:
 for name in ALIASES.values():
  if not clips.has(name) or not clips[name] is VrmaClip or clips[name].hips_translation.is_empty():return false
 return true
func prepare(player:MotionPlayer)->Dictionary:
 if player.avatar==null or not player.avatar.has_model() or not available(player.vrma_clips):return {}
 var avatar:=player.avatar
 var key:Array=[avatar.model.get_instance_id()]
 for name in ALIASES.values():key.append(player.vrma_clips[name].get_instance_id())
 if key==_cache_key and not profile.is_empty():return profile.duplicate(true)
 var started:=Time.get_ticks_usec()
 var sk:=avatar.skeleton
 _height=sk.get_bone_global_rest(avatar.bone_index.hips).origin.y
 contacts.prepare(avatar)
 if contacts.markers.size()!=4:return {}
 var saved:Array=[]
 var posed_bones:Dictionary=avatar._posed_bones.duplicate()
 for i in sk.get_bone_count():saved.append([sk.get_bone_pose_position(i),sk.get_bone_pose_rotation(i),sk.get_bone_pose_scale(i)])
 var floor_y:=INF
 for side in contacts.support_vertices:
  for marker in contacts.support_vertices[side]:floor_y=minf(floor_y,float(marker.rest.y))
 var minimum:=INF
 var bounds:=AABB()
 var first:=true
 var samples:=0
 for name in ALIASES.values():
  var clip:VrmaClip=player.vrma_clips[name]
  var count:=maxi(2,ceili(clip.duration*30.0))
  for i in count+1:
   var t:=clip.duration*i/count
   var pose:=clip.sample(t);var hips:=clip.sample_hips_offset(t)
   avatar.reset_pose();avatar.apply_normalized_rotations(pose,1);avatar.set_hips_offset(hips*_height)
   for side in ["left","right"]:minimum=minf(minimum,contacts._support_min(side))
   var snapshot:=avatar.body_capsule_snapshot()
   for capsule in snapshot.get("capsules",[]):
    var box:=AABB(Vector3(capsule.a),Vector3.ZERO).expand(Vector3(capsule.b)).grow(float(capsule.radius))
    bounds=box if first else bounds.merge(box);first=false
   samples+=1
 for i in saved.size():
  sk.set_bone_pose_position(i,saved[i][0]);sk.set_bone_pose_rotation(i,saved[i][1]);sk.set_bone_pose_scale(i,saved[i][2])
 avatar._posed_bones=posed_bones
 if first or not is_finite(minimum) or not is_finite(floor_y):return {}
 var correction:=maxf(0,floor_y-minimum)
 # A malformed source/rig must not silently float far above the support.
 if correction>_height*.12:return {}
 bounds=bounds.merge(AABB(bounds.position+Vector3.UP*correction,bounds.size)).grow(.025)
 profile={"model_id":avatar.model.get_instance_id(),"ground_y_local":floor_y,"source_sole_min_y":minimum,"floor_correction_m":correction,"bounds_local":bounds,"samples":samples,"preparation_ms":(Time.get_ticks_usec()-started)/1000.0,"scope":"sampled rig capsules plus25mm margin; host must also enforce actual rendered bounds","sources":ALIASES.duplicate()}
 _cache_key=key
 return profile.duplicate(true)
func begin(player:MotionPlayer)->bool:
 if active or player._contact_pose!="foot" or player.seated_transition.active or player.seated_carrier.active or player._preview or player._custom_motion:return false
 if prepare(player).is_empty():return false
 _from.clear()
 for i in player.avatar.bone_index.values():_from[i]=player.avatar.skeleton.get_bone_pose_rotation(i)
 _from_hips=player.avatar.get_hips_offset()
 _model_id=player.avatar.model.get_instance_id()
 _source_ids.clear()
 for name in ALIASES.values():_source_ids[name]=player.vrma_clips[name].get_instance_id()
 var first_clip:VrmaClip=player.vrma_clips[ALIASES.enter]
 contacts.begin_reference(first_clip.sample(0),first_clip.sample_hips_offset(0))
 player.stop_gesture();player.upper_body.clear();player.finish_locomotion();player.turn.cancel()
 player._contact_pose="floor_rest"
 player._heading_pending=false;player._facing_velocity=0;player._facing_target=player.avatar.rotation.y
 active=true;phase="enter";time=0
 diagnostics={"active":true,"phase":phase,"time":time,"bounds_local":profile.bounds_local}
 return true
func request_exit(player:MotionPlayer)->bool:
 if not active or phase!="idle":return false
 if not valid(player):interrupt(player);return false
 _from.clear()
 for i in player.avatar.bone_index.values():_from[i]=player.avatar.skeleton.get_bone_pose_rotation(i)
 _from_hips=player.avatar.get_hips_offset()
 phase="exit";time=0;return true
func clear()->void:
 active=false;phase="";time=0;diagnostics.clear();_from.clear()
 _source_ids.clear();_model_id=0;contacts.clear_reference()
func valid(player:MotionPlayer)->bool:
 if player==null or player.avatar==null or not player.avatar.has_model() or player.avatar.model.get_instance_id()!=_model_id or not available(player.vrma_clips):return false
 for name in ALIASES.values():
  if int(_source_ids.get(name,0))!=player.vrma_clips[name].get_instance_id():return false
 return true
## Detach ownership before signalling: reset/model/source/cancel must notify the
## native host exactly once, even when its callback also requests cancellation.
func interrupt(player:MotionPlayer)->void:
 var owned:=active
 clear()
 if player!=null and player._contact_pose=="floor_rest":player._contact_pose="foot"
 if owned:finished.emit("interrupted")
func apply(player:MotionPlayer,delta:float)->void:
 if not active:return
 var avatar:=player.avatar
 if not valid(player):
  interrupt(player);return
 var clip:VrmaClip=player.vrma_clips[ALIASES[phase]]
 time+=maxf(delta,0)
 var t:=fmod(time,clip.duration) if phase=="idle" else minf(time,clip.duration)
 var pose:=clip.sample(t)
 var hips:=clip.sample_hips_offset(t)*_height
 var acquisition:=smoothstep(0,.2,time) if phase!="idle" else 1.0
 var release:=1.0-smoothstep(clip.duration-.2,clip.duration,time) if phase=="exit" else 1.0
 avatar.apply_normalized_rotations(pose,1)
 hips.y+=float(profile.floor_correction_m)*acquisition*release
 if phase!="idle" and acquisition<1:
  for i in _from:avatar.skeleton.set_bone_pose_rotation(i,Quaternion(_from[i]).slerp(avatar.skeleton.get_bone_pose_rotation(i),acquisition))
  hips=_from_hips.lerp(hips,acquisition)
 avatar.set_hips_offset(hips)
 contacts.apply_contact(pose,clip.sample_hips_offset(t),0,float(profile.ground_y_local),acquisition)
 diagnostics={"active":true,"phase":phase,"time":t,"duration":clip.duration,"bounds_local":profile.bounds_local,"floor_correction_m":profile.floor_correction_m,"source_hips_m":hips,"scope":profile.scope}
 if phase!="idle" and time>=clip.duration:
  if phase=="enter":phase="idle";time=0;diagnostics.phase=phase;finished.emit("entered")
  else:
   active=false;phase="done";diagnostics.active=false;diagnostics.phase=phase
   player._contact_pose="foot"
   player._begin_transition()
   finished.emit("exited")
