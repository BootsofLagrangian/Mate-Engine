extends "res://tools/probe_host_lifecycle.gd"
class Dispatch extends BehaviorDirector:
 var next_action:Dictionary={}
 func tick(_delta:float,_context:Dictionary)->Dictionary:return {"state":"rest","action":next_action}
class IsolatedLiving extends LivingBehavior:
 func _refresh_targets()->void:pass
 func publish_world(_force:bool=false)->void:pass
 func _maybe_idle_action(_state:String)->void:pass
func _run():
 host_script=GDScript.new()
 host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():set_process(false)\nfunc _save_window_position():pass\nfunc _update_passthrough(_force):pass\n'
 if host_script.reload()!=OK:quit(1);return
 var host=make_host()
 host.session=CompanionSession.new();host.session.character_id="mambo"
 host.living=IsolatedLiving.new();host.add_child(host.living);host.living.host=host
 host.living._settings=root.get_node("Settings");host.living._last_state="rest"
 var dispatch:=Dispatch.new();host.living.director=dispatch
 host.autonomy.surface_mode=false;host.autonomy.enabled=true;host.autonomy._blocked=false;host.autonomy._settle_until=0
 host.autonomy.navigation_finished.connect(host.living._navigation_finished)
 host._vrma_loaded={"playful_strut":{"loop":true,"locomotion":true}}
 host.motion.locomotion_clips["playful_strut"]=true
 host.autonomy.observe_interest("old",Vector2(950,500),1,30)
 check(host.autonomy.move_to_interest("old"),"old native target starts")
 host.living.selected_locomotion_id="old_gait"
 dispatch.next_action={"type":"move_interest","id":"new-intent","target_id":"new","point":Vector2(1200,500),"kind":"point","ttl":30.0,"locomotion_id":"playful_strut"}
 host.living.tick(0.016)
 check(host.autonomy._active_target_id=="new","actual native target replacement accepted")
 check(host.living.selected_locomotion_id=="playful_strut","old target terminal callback cannot erase new gait")
 dispatch.next_action.point=host.autonomy.position+host.autonomy.visible_bounds.get_center()
 dispatch.next_action.target_id="already_here"
 host.living.tick(0.016)
 check(host.autonomy.last_request_outcome=="arrived","same-point target immediately arrives")
 check(host.living.selected_locomotion_id.is_empty(),"immediate arrival leaves no selected gait")
 dispatch.next_action.target_id="revoked";dispatch.next_action.point=Vector2(1200,500)
 host._vrma_loaded.clear();host.living.tick(0.016)
 check(host.autonomy._active_target_id.is_empty(),"catalog revocation before dispatch cannot start native target")
 host.audio._player.stop();host.audio._playback=null;host.free();await process_frame;await process_frame;print("REVIEW_ROUTING_CHECKS=",checks," FAILURES=",failures);quit(1 if failures else 0)
