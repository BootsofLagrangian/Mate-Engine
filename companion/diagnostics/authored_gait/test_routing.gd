extends "res://tools/probe_host_lifecycle.gd"
class RouteLiving extends LivingBehavior:
 var cancellations:Array=[]
 func _refresh_targets() -> void: pass
 func cancel(reason:String="cancelled") -> void:
  cancellations.append(reason);selected_locomotion_id=""
class RouteMotion extends Motion:
 var clips:Array=[]
 func play_vrma(name:String,_speed:float=1.0,_loop:bool=false,_repeat:int=1)->bool:
  clips.append(name);_vrma_name=name;return true
func _run():
 host_script=GDScript.new()
 host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready(): set_process(false)\nfunc _save_window_position(): pass\nfunc _update_passthrough(_force): pass\n'
 if host_script.reload()!=OK:quit(1);return
 var host:=make_host()
 host.session=CompanionSession.new()
 host.session.character_id="mambo"
 host.motion.free();host.motion=RouteMotion.new();host.add_child(host.motion)
 host.living=RouteLiving.new();host.add_child(host.living);host.living.host=host
 host.living.director.set_character("mambo")
 host.living.director.observe_interest("floor:test",Vector2(400,1000),1,30,"floor","floor")
 host._vrma_loaded={"uma_walk":{"loop":true,"locomotion":true,"locomotion_priority":50},"playful_strut":{"loop":true,"locomotion":true,"description":"Authored strut"},"preview":{"locomotion":false},"not_registered":{"loop":true,"locomotion":true}}
 host.motion.locomotion_clips["uma_walk"]=true;host.motion.locomotion_clips["playful_strut"]=true
 check(host.living.locomotion_catalog().size()==2,"catalog only actualloaded registeredlocomotion")
 check(not host.living.request_intent({"kind":"move_to","target_id":"floor:test","locomotion_id":"preview"},"llm","invalid").accepted,"preview excluded")
 check(not host.living.request_intent({"kind":"inspect","target_id":"floor:test","locomotion_id":"playful_strut"},"llm","wrongkind").accepted,"nonmovement rejects selectedgait")
 check(host.living.request_intent({"kind":"move_to","target_id":"floor:test","locomotion_id":"playful_strut"},"llm","owned").accepted,"approvedgait queues")
 check(host.living.director._queue[0].locomotion_id=="playful_strut","director retains selection")
 host.autonomy.surface_mode=false
 host.living.selected_locomotion_id="playful_strut"
 host._on_locomotion(true,Vector2(75,0))
 check(host.motion.clips==["playful_strut"],"actual main chooses explicitgait overpreferreddefault")
 host._on_locomotion(true,Vector2(75,0))
 check(host.motion.clips.size()==1,"velocityupdates do not restartauthoredclip")
 host._vrma_loaded.erase("playful_strut")
 host._on_locomotion(true,Vector2(75,0))
 check(host.living.cancellations==["locomotion_revoked"],"revokedchoice cancels instead ofsilentfallback")
 host._on_locomotion(true,Vector2(75,0))
 check(host.motion.clips.back()=="uma_walk","omittedchoice keeps existingdefault")
 host.living._navigation_finished("floor:test","completed")
 check(host.living.selected_locomotion_id.is_empty(),"terminalnavigation clearschoice")
 host.free();print("ROUTING_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
