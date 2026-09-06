extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var failures := 0
 var checks := 0
 for id in ["cheval-grand","rice-shower","eishin-flash"]:
  var avatar := VrmAvatar.new()
  root.add_child(avatar)
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+id+".vrm"))
  avatar.scale = Vector3.ONE*0.6
  var points: Array[Vector3] = []
  for key in ["rightUpperArm","rightLowerArm","rightHand"]:
   points.append(avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_rest(avatar.bone_index[key]).origin)
  var reach := points[0].distance_to(points[1])+points[1].distance_to(points[2])
  var preferred := points[0]-Vector3.UP*reach*0.70
  var foot: Vector3 = avatar.contact_anchors().foot
  var target := Vector3(foot.x,preferred.y,0.0)
  avatar.apply_hand_contact("right",target)
  var result: Dictionary = avatar.arm_ik.diagnostics.get("right",{})
  var okay: bool = not result.is_empty() and result.clamped<0.001 and result.error<0.001
  checks += 1
  if not okay: failures += 1; push_error(id+" preferred rest-arm desk fit cannot reach")
  print(id," fit_world_height=",target.y-foot.y," result=",result)
  avatar.free()
 print("Work fit: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
