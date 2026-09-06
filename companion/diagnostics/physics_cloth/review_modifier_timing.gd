extends SceneTree
var avatar:VrmAvatar
var rows:=[]
var step:=-1
func _init():call_deferred("run")
func capture():rows.append({"step":step,"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"process_delta":avatar.get_process_delta_time(),"physics_delta":avatar.get_physics_process_delta_time(),"callback_mode":avatar.skeleton.modifier_callback_mode_process})
func run():
 avatar=VrmAvatar.new();root.add_child(avatar)
 avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
 avatar.spring_contacts.secondary.internal_modifier_node.modification_processed.connect(capture)
 for i in 30:
  step=i;avatar.apply_pose({"head":Vector3(0,float(i),0)})
  await process_frame
 print(JSON.stringify(rows));quit()
