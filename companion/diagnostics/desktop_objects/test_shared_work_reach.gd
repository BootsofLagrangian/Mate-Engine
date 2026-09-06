extends SceneTree
const Scene = preload("res://scripts/desktop_object_contact_scene.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func run():
 for id in ["cheval-grand","rice-shower","eishin-flash"]:
  var avatar := VrmAvatar.new()
  root.add_child(avatar)
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+id+".vrm"))
  var player := MotionPlayer.new()
  root.add_child(player)
  player.set_process(false)
  player.avatar=avatar
  player.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
  var scene := Scene.new()
  root.add_child(scene)
  scene.configure("computer")
  var clearance: float=scene.socket_local("seat").y-scene.get_local_bounds().position.y
  avatar.set_seated_floor(clearance)
  var pose: Dictionary=player.vrma_clips.sit_idle.sample(0.0)
  var geometry: Dictionary=avatar.calibrate_seated_pose(pose)
  avatar.apply_pose({})
  avatar.apply_normalized_rotations(pose,1.0)
  avatar.seated_floor.solve_legs()
  avatar.transform=Transform3D(Basis(Vector3.UP,deg_to_rad(-145.0)).scaled(Vector3.ONE*.6),Vector3.ZERO)
  scene.basis=Basis(Vector3.UP,deg_to_rad(35.0)).scaled(Vector3.ONE*.6)
  scene.position=avatar.global_transform*Vector3(geometry.anchor)-scene.basis*scene.socket_local("seat")
  for side in ["left","right"]:
   var target: Vector3=scene.socket_world("keyboard_"+side)
   var reached: bool=avatar.apply_hand_contact(side,target)
   var error: float=avatar.bone_global_position(side+"Hand").distance_to(target)
   checks+=1
   if not reached or error>.02: failures+=1;push_error(id+" "+side+" physical workstation reach failed")
   print(id," ",side," physical_work_error_m=",error," reached=",reached)
  player.free();scene.free();avatar.free()
 print("Shared work reach: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
