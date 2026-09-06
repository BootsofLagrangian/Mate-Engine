class_name RigBodyCapsules
extends RefCounted
## Read-only bone-volume approximation. Not a mesh/garment enclosure.
static func snapshot(avatar:VrmAvatar)->Dictionary:
 if avatar==null or not avatar.has_model():return {}
 var sk:=avatar.skeleton
 var transform:=avatar.global_transform.affine_inverse()*sk.global_transform
 var live:Dictionary={};var rest:Dictionary={}
 for name in avatar.bone_index:
  var idx:int=avatar.bone_index[name]
  live[name]=sk.get_bone_global_pose(idx)
  rest[name]=sk.get_bone_global_rest(idx)
 for required in ["hips","spine","chest","neck","head","leftUpperLeg","rightUpperLeg","leftLowerLeg","rightLowerLeg","leftFoot","rightFoot","leftUpperArm","rightUpperArm","leftLowerArm","rightLowerArm","leftHand","rightHand"]:
  if not live.has(required):return {}
 var shoulder_width:float=rest.leftUpperArm.origin.distance_to(rest.rightUpperArm.origin)
 var hip_width:float=rest.leftUpperLeg.origin.distance_to(rest.rightUpperLeg.origin)
 var trunk_step:float=rest.hips.origin.distance_to(rest.spine.origin)
 var head_step:float=rest.neck.origin.distance_to(rest.head.origin)
 var head_radius:=maxf(shoulder_width*.65,head_step*2.2)
 var capsules:Array=[]
 var radius_scale:=scale_bound(transform.basis)
 _add(capsules,"pelvis",live.leftUpperLeg.origin,live.rightUpperLeg.origin,maxf(hip_width*.34,trunk_step*.7),transform,radius_scale)
 _add(capsules,"lower_torso",live.hips.origin,live.chest.origin,shoulder_width*.42,transform,radius_scale)
 _add(capsules,"upper_torso",live.chest.origin,live.neck.origin,shoulder_width*.48,transform,radius_scale)
 _add(capsules,"neck",live.neck.origin,live.head.origin,head_radius*.36,transform,radius_scale)
 var head_rotation:Basis=live.head.basis.orthonormalized()*rest.head.basis.orthonormalized().inverse()
 var head_center:Vector3=live.head.origin+head_rotation*Vector3.UP*head_radius*.8
 _add(capsules,"head",head_center,head_center,head_radius,transform,radius_scale)
 for side in ["left","right"]:
  var thigh:String=side+"UpperLeg";var calf:String=side+"LowerLeg";var foot:String=side+"Foot";var toes:String=side+"Toes"
  var leg_length:float=rest[thigh].origin.distance_to(rest[calf].origin)+rest[calf].origin.distance_to(rest[foot].origin)
  var thigh_radius:=maxf(hip_width*.28,leg_length*.075)
  _add(capsules,side+"_thigh",live[thigh].origin,live[calf].origin,thigh_radius,transform,radius_scale)
  _add(capsules,side+"_calf",live[calf].origin,live[foot].origin,thigh_radius*.7,transform,radius_scale)
  var floor_y:float=avatar.sole_calibration.get("floor_y",0)
  var ankle_height:float=maxf(0,rest[foot].origin.y-floor_y)
  var foot_radius:=maxf(leg_length*.055,ankle_height*.35)
  var toe_length:float=rest[toes].origin.z-rest[foot].origin.z if rest.has(toes) else rest[calf].origin.distance_to(rest[foot].origin)*.4
  var foot_rotation:Basis=live[foot].basis.orthonormalized()*rest[foot].basis.orthonormalized().inverse()
  var heel:Vector3=live[foot].origin+foot_rotation*Vector3(0,floor_y+foot_radius-rest[foot].origin.y,-foot_radius*.4)
  var toe:Vector3=live[foot].origin+foot_rotation*Vector3(0,floor_y+foot_radius-rest[foot].origin.y,maxf(0,toe_length)+foot_radius*.3)
  _add(capsules,side+"_foot",heel,toe,foot_radius,transform,radius_scale)
  _add(capsules,side+"_upper_arm",live[side+"UpperArm"].origin,live[side+"LowerArm"].origin,shoulder_width*.14,transform,radius_scale)
  _add(capsules,side+"_forearm",live[side+"LowerArm"].origin,live[side+"Hand"].origin,shoulder_width*.12,transform,radius_scale)
 return {"space":"avatar_local","transform":avatar.global_transform,"model_id":avatar.model.get_instance_id(),"capsules":capsules,"scope":"rig_body_volume_approximation","excludes":["hands","garments","hair","accessories"],"pose_margin_m":0.0,"articulation_frozen":false}

static func _add(output:Array,id:String,a:Vector3,b:Vector3,radius:float,transform:Transform3D,radius_scale:float)->void:
 output.append({"id":id,"a":transform*a,"b":transform*b,"radius":radius*radius_scale})

static func scale_bound(basis:Basis)->float:
 # Gershgorin bound on the largest eigenvalue of B^T B, including small
 # scaled shears. No absolute orthogonality tolerance can underbound it.
 var columns:Array[Vector3]=[basis.x,basis.y,basis.z]
 var maximum:=0.0
 for i in 3:
  var row_sum:=0.0
  for j in 3:row_sum+=absf(columns[i].dot(columns[j]))
  maximum=maxf(maximum,row_sum)
 return sqrt(maximum)
