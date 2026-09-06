class_name CarrierLiftEnvelope
extends RefCounted
## Conservative stationary lift/lower union for the existing two-bone IK.
## All derivatives below are with respect to normalized lift in [0,1].
const INTERVALS:=16
static func build(reference:Dictionary)->Dictionary:
 if reference.is_empty() or reference.get("legs",{}).size()!=2:return {}
 var base:Dictionary=reference.get("snapshot",{})
 if base.get("capsules",[]).size()!=15:return {}
 var transform:Transform3D=reference.to_avatar
 var scale_bound:=RigBodyCapsules.scale_bound(transform.basis)
 var numeric_guard:=0.0
 for points in reference.legs.values():
  numeric_guard=maxf(numeric_guard,(Vector3(points[0]).distance_to(points[1])+Vector3(points[1]).distance_to(points[2]))*.00001*scale_bound)
 var capsules:Array=[];var maximum_margin:=0.0
 for capsule in base.capsules:
  if not str(capsule.id).ends_with("_thigh") and not str(capsule.id).ends_with("_calf") and not str(capsule.id).ends_with("_foot"):capsules.append(capsule.duplicate(true))
 for side in ["left","right"]:
  var points:Array=reference.legs[side]
  var hip:Vector3=points[0];var knee:Vector3=points[1];var ankle:Vector3=points[2]
  var u:=hip.distance_to(knee);var l:=knee.distance_to(ankle)
  if minf(u,l)<.001:return {}
  var clearance:float=reference.get("clearance",{}).get(side,0)
  if not is_finite(clearance) or clearance<=0:return {}
  var q:=ankle-hip
  for interval in INTERVALS:
   var lo:=float(interval)/INTERVALS;var hi:=float(interval+1)/INTERVALS
   var mid:float=(lo+hi)*.5;var half:float=(hi-lo)*.5
   var bounds:=_interval(q,u,l,clearance,lo,hi)
   if bounds.is_empty():return {}
   var pose:=_pose(q,u,l,clearance,mid)
   var knee_at:Vector3=hip+pose.knee;var ankle_at:Vector3=hip+pose.ankle
   var knee_margin:float=bounds.knee_speed*half*scale_bound
   var ankle_margin:float=bounds.ankle_speed*half*scale_bound
   maximum_margin=maxf(maximum_margin,maxf(knee_margin,ankle_margin))
   for original in base.capsules:
    if not str(original.id) in [side+"_thigh",side+"_calf",side+"_foot"]:continue
    var capsule:Dictionary=original.duplicate(true)
    if original.id==side+"_thigh":
     capsule.a=transform*hip;capsule.b=transform*knee_at;capsule.radius+=knee_margin
    elif original.id==side+"_calf":
     capsule.a=transform*knee_at;capsule.b=transform*ankle_at;capsule.radius+=maxf(knee_margin,ankle_margin)
    else:
     var shift:=transform.basis*(ankle_at-ankle)
     capsule.a+=shift;capsule.b+=shift;capsule.radius+=ankle_margin
    capsule["sample_lift"]=mid;capsule["interval"]=[lo,hi]
    capsules.append(capsule)
 for capsule in capsules:capsule.radius+=numeric_guard
 var result:=base.duplicate(true)
 result["capsules"]=capsules
 result["articulation_frozen"]=false
 result["articulation_enclosed"]=true
 result["scope"]="rig_lift_envelope"
 result["articulation_envelope"]="seated_carrier_lift_0_1"
 result["intervals"]=INTERVALS
 result["maximum_margin_m"]=maximum_margin
 result["numeric_guard_m"]=numeric_guard
 return result

static func _pose(q:Vector3,u:float,l:float,c:float,t:float)->Dictionary:
 var v:=q+Vector3.UP*c*t
 var r:=clampf(v.length(),_reach(u,l,140),_reach(u,l,2))
 var d:=v.normalized()
 var pole:Vector3=(Vector3.BACK-d*d.dot(Vector3.BACK)).normalized()
 var x:float=(u*u-l*l+r*r)/(2*r)
 return {"knee":d*x+pole*sqrt(maxf(0,u*u-x*x)),"ankle":d*r}

static func _reach(u:float,l:float,angle:float)->float:
 return sqrt(u*u+l*l+2*u*l*cos(deg_to_rad(angle)))

static func _interval(q:Vector3,u:float,l:float,c:float,lo:float,hi:float)->Dictionary:
 var closest:=clampf(-q.y/c,lo,hi)
 var raw_min:float=(q+Vector3.UP*c*closest).length()
 var raw_max:float=maxf((q+Vector3.UP*c*lo).length(),(q+Vector3.UP*c*hi).length())
 if raw_min<=.00001:return {}
 var minimum:=_reach(u,l,140);var maximum:=_reach(u,l,2)
 var rmin:=clampf(raw_min,minimum,maximum);var rmax:=clampf(raw_max,minimum,maximum)
 var x0:float=(u*u-l*l+rmin*rmin)/(2*rmin)
 var x1:float=(u*u-l*l+rmax*rmax)/(2*rmax)
 # x(r) has at most one interior minimum; max |x| is at an endpoint
 # or that stationary point (included defensively for unequal lengths).
 var xmax:=maxf(absf(x0),absf(x1))
 if u*u>l*l:
  var critical:=sqrt(u*u-l*l)
  if critical>=rmin and critical<=rmax:xmax=maxf(xmax,critical)
 var hmin:=sqrt(maxf(0,u*u-xmax*xmax))
 if hmin<=u*.0001:return {}
 var direction_speed:=c/raw_min
 var middle:Vector3=(q+Vector3.UP*c*(lo+hi)*.5).normalized()
 var pole_middle:float=(Vector3.BACK-middle*middle.dot(Vector3.BACK)).length()
 # Unnormalized pole derivative <=2|d'|. Reject the solver's fallback
 # boundary throughout the interval rather than assuming one pole branch.
 var pole_min:=pole_middle-2*direction_speed*(hi-lo)*.5
 if pole_min<=sqrt(.00001):return {}
 var x_speed:float=.5*(1+absf(u*u-l*l)/(rmin*rmin))*c
 var knee_speed:float=direction_speed*xmax+x_speed+2*direction_speed/pole_min*u+xmax/hmin*x_speed
 var ankle_speed:float=c if raw_min>=minimum and raw_max<=maximum else direction_speed*rmax+c
 return {"knee_speed":knee_speed,"ankle_speed":ankle_speed}
