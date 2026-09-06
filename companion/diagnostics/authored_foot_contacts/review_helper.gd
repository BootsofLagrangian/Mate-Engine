extends SceneTree
var rows:Array=[]
var failures:=0
func _init():call_deferred("run")
func pose(a:VrmAvatar,rotations:Dictionary,hips:Vector3):
 a.apply_pose({});a.apply_normalized_rotations(rotations,1)
 a.set_hips_offset(hips*a.skeleton.get_bone_global_rest(a.bone_index.hips).origin.y)
func run():
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
  var feet:=AuthoredFootContacts.new();feet.prepare(a)
  var clip:=VrmaClip.new();clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
  var rotations:=clip.sample(0);var hips:=clip.sample_hips_offset(0)
  pose(a,rotations,hips)
  var floor_y:=minf(feet._support_min("left"),feet._support_min("right"))
  feet.begin_reference(rotations,hips)
  a.set_hips_offset(a.get_hips_offset()+Vector3(0,.02,0))
  var basis_before:=a.skeleton.get_bone_global_pose(a.bone_index.leftFoot).basis.orthonormalized().get_rotation_quaternion()
  var before:=feet.live_local();feet.apply_contact(rotations,hips,0,floor_y)
  var after:=feet.live_local();var drop:float=before.leftHeel.y-after.leftHeel.y
  var basis_after:=a.skeleton.get_bone_global_pose(a.bone_index.leftFoot).basis.orthonormalized().get_rotation_quaternion()
  var basis_error:=1-absf(basis_before.dot(basis_after))
  if basis_error>.000001:failures+=1
  var ground:=minf(feet._support_min("left"),feet._support_min("right"))-floor_y
  if drop<.01 or ground<-.001:failures+=1
  rows.append({"character":character,"test":"floating_foot_can_lower","drop_m":drop,"ground_gap_m":ground,"foot_orientation_dot_error":basis_error})
  pose(a,rotations,hips)
  var original:=feet.live_local();feet.apply_contact(rotations,hips,0,floor_y,0)
  var unowned:=feet.live_local();var error:=0.0
  for key in original:error=maxf(error,Vector3(original[key]).distance_to(unowned[key]))
  if error>.000001:failures+=1
  rows.append({"character":character,"test":"unowned_pose_unchanged","error_m":error})
  var lifted:=hips+Vector3(0,.25,0);pose(a,rotations,lifted)
  var raw:=feet.live_local();feet.apply_contact(rotations,lifted,0,floor_y)
  var live:=feet.live_local();error=0
  for key in raw:error=maxf(error,Vector3(raw[key]).distance_to(live[key]))
  if error>.000001 or feet.diagnostics.left.planned_weight!=0 or feet.diagnostics.right.planned_weight!=0:failures+=1
  rows.append({"character":character,"test":"clear_authored_lift_not_pinned","error_m":error})
  feet.clear_reference()
  if feet.active or not feet.reference_live.is_empty() or not feet.reference_source.is_empty():failures+=1
  a.free()
 FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/authored_foot_contacts/review-helper.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  ")+"\n")
 print("INDEPENDENT_FOOT_HELPER_FAILURES=",failures);quit(failures)
