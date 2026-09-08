extends SceneTree
class Motion extends RefCounted:
	var vrma_clips:Dictionary={}
	var locomotion_styles:Dictionary={}
	var locomotion_clips:Dictionary={"fixture":true}
	var _vrma_loop:=true
	var _travel_intent:=true
	var _vrma_start:=10.0
	var _vrma_playback_revision:=1
	var current:="fixture"
	var stops:=0
	var snapshots:=0
	func current_gesture()->String:return current
	func _begin_transition()->void:snapshots+=1
	func finish_locomotion()->void:_travel_intent=false
	func stop_gesture()->void:stops+=1;current="idle"
class Host extends RefCounted:
	var avatar:Node3D
	var motion:=Motion.new()
	var _pet_scale:=.6
	var _vrma_loaded:Dictionary={}
	var living:Dictionary={"selected_locomotion_id":"fixture"}
	var _walk_started:="fixture"
var failures:=0
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	print(label," ",value)
	if not value:failures+=1
func run()->void:
	var host:=Host.new();host.avatar=Node3D.new();root.add_child(host.avatar);host.avatar.scale=Vector3.ONE*.6
	var clip:=VrmaClip.new();host.motion.vrma_clips.fixture=clip
	var objects:=DesktopObjectsHost.new();objects.host=host
	var step:Dictionary={"pet_scale":.6,"actor_scale":Vector3.ONE*.6,"walk_name":"fixture","walk_instance":clip.get_instance_id(),"walk_revision":clip.source_revision,"walk_style_hash":hash({}),"phase":"move","owned_playback_start":10.0,"owned_playback_revision":1}
	check(objects._standing_source_rejection(step).is_empty(),"original admitted source remains valid")
	host.avatar.rotation.y=.8
	check(objects._standing_source_rejection(step).is_empty(),"normal yaw does not invalidate actor scale")
	host._pet_scale=.7;check(not objects._standing_source_rejection(step).is_empty(),"logical resize rejected");host._pet_scale=.6
	host.avatar.scale=Vector3.ONE*.7;check(not objects._standing_source_rejection(step).is_empty(),"actual basis resize rejected");host.avatar.scale=Vector3.ONE*.6
	host.motion.vrma_clips.fixture=VrmaClip.new();check(not objects._standing_source_rejection(step).is_empty(),"clip object replacement rejected");host.motion.vrma_clips.fixture=clip
	clip.source_revision+=1;check(not objects._standing_source_rejection(step).is_empty(),"in-place source reload rejected");clip.source_revision-=1
	host.motion.locomotion_styles.fixture={"changed":true};check(not objects._standing_source_rejection(step).is_empty(),"contact style replacement rejected");host.motion.locomotion_styles.clear()
	host.motion.current="idle";check(not objects._standing_source_rejection(step).is_empty(),"stopped playback rejected");host.motion.current="fixture"
	host.motion._travel_intent=false;check(not objects._standing_source_rejection(step).is_empty(),"missing gait ownership rejected");host.motion._travel_intent=true
	host.motion._vrma_playback_revision=2;check(not objects._standing_source_rejection(step).is_empty(),"same clip restarted by another owner rejected");host.motion._vrma_playback_revision=1
	objects._retire_standing_pose({"grip_walk_owner":{"name":"fixture","started":10.0,"revision":1}})
	check(host.motion.stops==1 and host._walk_started.is_empty() and host.motion.snapshots==1,"owned walk retired after capturing actual pose")
	host.motion.current="wave";host.motion._vrma_start=11;host.motion._vrma_playback_revision=2;host._walk_started="wave"
	objects._retire_standing_pose({"grip_walk_owner":{"name":"fixture","started":10.0,"revision":1}})
	check(host.motion.stops==1 and host.motion.current=="wave" and host._walk_started=="wave" and host.motion.snapshots==2,"new gesture survives old contact release")
	host.motion.current="fixture"
	objects._retire_standing_pose({"grip_walk_owner":{"name":"fixture","started":10.0,"revision":1}})
	check(host.motion.stops==1 and host.motion.current=="fixture","new playback of same named clip survives release")
	objects.free();host.avatar.free();print("standing ownership failures=",failures);quit(1 if failures else 0)
