extends SceneTree
## Independent final-pose boundary audit. No runtime mutation or renderer claims.
var failures: Array = []
var results: Array = []
const BONES := ["head","chest","rightUpperArm","rightLowerArm","rightHand","hips","leftFoot","rightFoot"]
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func rotation_vector(a: Quaternion,b: Quaternion) -> Vector3:
	var q := (b*a.inverse()).normalized()
	if q.w<0: q=Quaternion(-q.x,-q.y,-q.z,-q.w)
	var v:=Vector3(q.x,q.y,q.z)
	return v.normalized()*rad_to_deg(2*atan2(v.length(),q.w)) if v.length()>0.00000001 else Vector3.ZERO
func run() -> void:
	var source_hashes:={}
	source_hashes.probe=FileAccess.get_sha256("res://tools/probe_upper_body_review.gd")
	for name in ["motion_player","upper_body_overlay","desktop_gait","vrm_avatar","arm_ik","leg_ik","turn_stepper"]:
		source_hashes[name]=FileAccess.get_sha256("res://scripts/"+name+".gd")
	var bank:=MotionBank.parse_json_text(FileAccess.get_file_as_string("res://../../Assets/StreamingAssets/cheval-motions.json"))
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		for fps in [30,60]:
			var baseline:=[]
			for scenario in ["baseline","replace","stop","lock","finite"]:
				var avatar:=VrmAvatar.new()
				root.add_child(avatar)
				avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"))
				var p:=MotionPlayer.new()
				root.add_child(p)
				p.set_process(false)
				p.avatar=avatar
				p.set_bank(bank)
				p.idle_enabled=false
				p.gaze_enabled=false
				avatar.rotation.y=deg_to_rad(82)
				p.load_vrma("uma_walk",ProjectSettings.globalize_path("res://../assets/motions/uma_walk.vrma"))
				p.register_locomotion_clip("uma_walk",true)
				p.play_vrma("uma_walk",1,true)
				var previous:={}
				var velocity:={}
				var edges:=[]
				var max_step:={}
				var peak_frames:={}
				var max_lower_error:=0.0
				var max_hand_difference:=0.0
				var overlap_frames:=0
				for frame in fps*7:
					if frame==fps and scenario!="baseline": check(p.play_upper_body_gesture("wave"),"start "+character)
					var event_frame:=int(2.2*fps)
					if frame==event_frame:
						if scenario=="replace": check(p.play_upper_body_gesture("nod"),"replacement "+character)
						if scenario=="stop": p.stop_upper_body_gesture()
						if scenario=="lock": p.set_upper_body_contact_lock(true)
					if frame==3*fps and scenario=="lock":p.set_upper_body_contact_lock(false)
					p._process(1.0/fps)
					p.set_locomotion_sample(Vector2(80,0),Vector2(80.0/fps,0),300,true)
					var now:={}
					for bone in BONES:
						var xf:Transform3D=avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(avatar.bone_index[bone])
						var q:=xf.basis.orthonormalized().get_rotation_quaternion()
						now[bone]={"q":q,"p":xf.origin}
						if previous.has(bone):
							var step:=rotation_vector(previous[bone].q,q)
							if step.length()>float(max_step.get(bone,0.0)):
								max_step[bone]=step.length()
								peak_frames[bone]={"frame":frame,"time":float(frame)/fps,"speed_deg_s":step.length()*fps,"velocity_change_deg_s":(step*fps-Vector3(velocity.get(bone,Vector3.ZERO))).length(),"actions":p.upper_body.diagnostics.get("active",[]).duplicate(true)}
							if abs(frame-event_frame)<=3:
								edges.append({"frame":frame,"bone":bone,"step_deg":step.length(),"speed_deg_s":step.length()*fps,"velocity_change_deg_s":(step*fps-Vector3(velocity.get(bone,Vector3.ZERO))).length(),"position_step_m":xf.origin.distance_to(previous[bone].p)})
							velocity[bone]=step*fps
						if scenario!="baseline":
							if bone in ["hips","leftFoot","rightFoot"]:max_lower_error=maxf(max_lower_error,xf.origin.distance_to(baseline[frame][bone].p))
							if bone=="rightHand":max_hand_difference=maxf(max_hand_difference,xf.origin.distance_to(baseline[frame][bone].p))
					if scenario=="baseline":baseline.append(now)
					previous=now
					if p.upper_body.diagnostics.get("active",[]).size()==2:overlap_frames+=1
				check(max_lower_error<0.00001,"lower-body invariance "+character+scenario)
				check(not p.is_upper_body_active(),"finite cleanup "+character+scenario)
				if scenario=="replace":check(overlap_frames>=fps/3,"live overlap "+character)
				results.append({"character":character,"fps":fps,"scenario":scenario,"max_joint_step_deg":max_step,"peak_frames":peak_frames,"boundary_frames":edges,"max_lower_position_difference_m":max_lower_error,"max_hand_difference_m":max_hand_difference,"overlap_frames":overlap_frames})
				p.free()
				avatar.free()
	var output:="res://../diagnostics/upper_body_review/results.json"
	var args:=OS.get_cmdline_user_args()
	var idx:=args.find("--output")
	if idx>=0 and idx+1<args.size():output=args[idx+1]
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Deterministic actual MotionPlayer final world pose, three rigs at30/60Hz, continuous UMA walking; no main, contact acquisition solver or rendered naturalness claim.","source_hashes":source_hashes,"results":results,"failures":failures},"\t"))
	print("UPPER_REVIEW cells=",results.size()," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
