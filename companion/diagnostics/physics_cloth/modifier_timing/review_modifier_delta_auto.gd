extends SceneTree
var avatar:VrmAvatar
var rows:=[]
var step:=-1
var before_tails:=[]
var pass_index:=0
func _init():call_deferred("run")
func observe(tag:String,delta:float):
 var tails:=[]
 for state in avatar.spring_contacts.secondary.spring_bones_internal:
  for joint in state.verlets:tails.append(joint.current_tail)
 if tag=="before":before_tails=tails;pass_index+=1
 var difference:=0.0
 if tag=="after":
  for i in tails.size():difference=maxf(difference,tails[i].distance_to(before_tails[i]))
 rows.append({"tag":tag,"pass":pass_index,"step":step,"engine_delta":delta,"node_delta":avatar.get_process_delta_time(),"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"max_tail_change_m":difference})
func run():
 avatar=VrmAvatar.new();root.add_child(avatar)
 avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
 var script=load("/tmp/review_delta_observer.gd")
 var first=script.new();first.host=self;first.tag="before";avatar.skeleton.add_child(first,false,Node.INTERNAL_MODE_FRONT)
 var last=script.new();last.host=self;last.tag="after";avatar.skeleton.add_child(last,false,Node.INTERNAL_MODE_BACK)
 var player:=MotionPlayer.new();root.add_child(player);player.avatar=avatar;player.gaze_enabled=false
 player.load_vrma("uma_cheval_idle",ProjectSettings.globalize_path("res://../assets/motions/uma_cheval_idle.vrma"));player.play_vrma("uma_cheval_idle",1,true)
 for i in 90:
  step=i
  if i==60:player.set_process(false)
  await process_frame
 var report:={"scope":"Observer modifiers immediately before/after imported VRM modifier; no observer bone writes; automatic production MotionPlayer first60iterations then disabled30 (no coroutine pose writes). Engine supplied delta versus addon node delta and actual Verlet change.","rows":rows}
 FileAccess.open("/tmp/review_modifier_delta_auto.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("TRACE ",rows.size());quit()
