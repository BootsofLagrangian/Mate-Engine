class_name UpperBodyOverlay
extends RefCounted
## Independent finite upper-body timelines over a live locomotion/contact base.
## No root translation, hips or leg ownership is admitted through this layer.
var actions: Array[Dictionary] = []
var diagnostics: Dictionary = {}
var contact_locked := false
const FADE_SECONDS := 0.5

func clear() -> void:
	actions.clear()
	diagnostics.clear()

func stop(time: float) -> void:
	for action in actions:
		if action.stop_at<0: action.stop_at=time

func start(player: MotionPlayer, name: String, intensity: float, speed: float, repeat: int, requested: Array) -> bool:
	if player.avatar==null or not player.avatar.has_model() or player._preview or player._custom_motion or player.seated_transition.active: return false
	if name in player.seated_transition.clips.values() or not Dictionary(player.locomotion_styles.get(name,{})).is_empty(): return false
	if not is_finite(intensity) or not is_finite(speed): return false
	var source := "vrma" if player.vrma_clips.has(name) else "bank"
	var motion: Dictionary=player.bank.get_motion(name) if source=="bank" else {}
	if name=="idle" or (source=="bank" and motion.is_empty()): return false
	var channels:=[]
	for channel in requested:
		if channel in ["head","arms","torso"] and channel not in channels: channels.append(channel)
	if contact_locked:
		channels.erase("arms")
		channels.erase("torso")
	if channels.is_empty(): return false
	# A bounded two-action handoff avoids truncating a live outgoing blend.
	if actions.size()>=2: return false
	stop(player.elapsed)
	speed=clampf(speed,0.5,2.0)
	repeat=clampi(repeat,1,3)
	var duration:float=player.vrma_clips[name].duration*repeat/speed if source=="vrma" else MotionBank.performed_duration(motion,speed,repeat)
	actions.append({"name":name,"source":source,"motion":motion,"channels":channels,"intensity":clampf(intensity,0,1.5),"speed":speed,"repeat":repeat,"duration":duration,"start":player.elapsed,"stop_at":-1.0,"hands":{}})
	return true

static func _ease_weight(value: float) -> float:
	var x:=clampf(value,0,1)
	return x*x*x*(x*(x*6-15)+10)

func apply(player: MotionPlayer, delta: float) -> void:
	diagnostics={"active":[],"contact_locked":contact_locked}
	if player._preview or player._custom_motion:
		clear()
		return
	var avatar:=player.avatar
	for action in actions.duplicate():
		var age:float=player.elapsed-action.start
		var weight:=_ease_weight(age/FADE_SECONDS)*_ease_weight((action.duration-age)/FADE_SECONDS)
		if action.stop_at>=0: weight*=1.0-_ease_weight((player.elapsed-action.stop_at)/FADE_SECONDS)
		if age>=action.duration or (action.stop_at>=0 and player.elapsed-action.stop_at>=FADE_SECONDS):
			actions.erase(action)
			continue
		var arm_weight := 1.0
		if action.has("retire_at"):
			arm_weight = 1.0-_ease_weight((player.elapsed-action.retire_at)/FADE_SECONDS)
			if arm_weight <= 0.0 and "head" not in action.channels:
				actions.erase(action)
				continue
		var sampled:Dictionary
		if action.source=="vrma":
			var clip:VrmaClip=player.vrma_clips[action.name]
			sampled=clip.sample(fmod(age*action.speed,maxf(clip.duration,0.001)))
		else:
			sampled=MotionBank.sample_performed(action.motion,age,action.intensity,action.speed,action.repeat)
		for bone in sampled.keys():
			var channel:=player._bone_channel(bone)
			if channel not in action.channels or channel in ["root","legs"] or (arm_weight <= 0.0 and channel in ["arms","torso"]): sampled.erase(bone)
		var before:={}
		for bone in sampled:
			if avatar.bone_index.has(bone):
				var idx:int=avatar.bone_index[bone]
				before[idx]=avatar.skeleton.get_bone_pose_rotation(idx)
		if action.source=="vrma":
			avatar.apply_normalized_rotations(sampled,minf(action.intensity,1.0))
		else:
			avatar.add_pose_offsets(sampled)
			if player.ik_enabled:
				var goals:={}
				for side in ["left","right"]:
					var owns_arm:=false
					for bone in sampled:
						if str(bone).begins_with(side) and player._bone_channel(bone)=="arms": owns_arm=true
					if not owns_arm: continue
					for joint in ["UpperArm","LowerArm","Hand"]:
						var idx:int=avatar.bone_index.get(side+joint,-1)
						if idx>=0 and not before.has(idx):before[idx]=avatar.skeleton.get_bone_pose_rotation(idx)
					var rest:=player._action_hand_goal(side,"",{},0,0,1,false)
					var wanted:=player._action_hand_goal(side,action.name,action.motion,age,action.intensity,action.speed)
					var current:Vector3=action.hands.get(side,rest)
					var smooth:=current.lerp(wanted,1-exp(-float(player.motion_style.get("response",7))*delta))
					action.hands[side]=current.move_toward(smooth,2*delta)
					goals[side]=action.hands[side]
				avatar.apply_hand_goals(goals)
				if goals.has("right"):avatar.add_wrist_rotation("right",Vector3(0,0,player._wave_wrist(action.name,action.motion,age,action.speed,action.intensity)))
		for idx in before:
			var bone_weight := weight
			if player._bone_channel(str(avatar.bone_index.find_key(idx))) in ["arms","torso"]: bone_weight *= arm_weight
			avatar.skeleton.set_bone_pose_rotation(idx,Quaternion(before[idx]).slerp(avatar.skeleton.get_bone_pose_rotation(idx),bone_weight))
		diagnostics.active.append({"name":action.name,"source":action.source,"time":age,"weight":weight,"arm_weight":weight*arm_weight,"channels":action.channels.duplicate(),"bones":sampled.keys()})
