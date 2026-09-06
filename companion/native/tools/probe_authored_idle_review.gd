extends SceneTree
var avatar: VrmAvatar
var motion: MotionPlayer
var output := "/tmp/authored-idle-review"
var model := ""
var clock := 0.0
var previous_q := Quaternion.IDENTITY
var previous_velocity := Vector3.ZERO
var previous_hips := Vector3.ZERO
var previous_feet: Dictionary = {}
var rows: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var csv: FileAccess
var DT := 1.0/60.0
var manifest: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String,details: Dictionary = {}) -> void:
	checks.append({"model":model,"ok":ok,"label":label,"details":details})
	print("AUTHORED_REVIEW ",model," ",label," ",ok," ",JSON.stringify(details))
func path(relative: String) -> String: return ProjectSettings.globalize_path("res://../"+relative)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--output" in args: output = args[args.find("--output")+1]
	if "--fps" in args: DT = 1.0/clampf(float(args[args.find("--fps")+1]),30,60)
	for name in ["action_overlap.gd","arm_ik.gd","ambient_motion.gd","motion_player.gd","vrma_clip.gd","vrm_avatar.gd","turn_stepper.gd","leg_ik.gd","desktop_gait.gd"]: manifest[name] = FileAccess.get_sha256("res://scripts/"+name)
	manifest["motion-assets.json"] = FileAccess.get_sha256(path("motion-assets.json"))
	manifest["probe"] = FileAccess.get_sha256(get_script().resource_path)
	for alias in ["uma_home_idle","uma_cheval_idle_action","uma_rice_idle_action","uma_eishin_idle_action"]: manifest[alias] = FileAccess.get_sha256(path("assets/research/uma/candidates/"+alias+".vrma"))
	DirAccess.make_dir_recursive_absolute(output)
	csv = FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	csv.store_line("model,time,stage,head_speed,head_acceleration,hips_step,foot_error,sole_error,foot_step,contact_weight,ambient_weight,head_weight,action,heading")
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		model = character
		avatar = VrmAvatar.new()
		root.add_child(avatar)
		check(avatar.load_from_file(path("assets/"+model+".vrm")),"model loaded")
		avatar.scale = Vector3.ONE*0.6
		motion = MotionPlayer.new()
		root.add_child(motion)
		motion.set_process(false)
		motion.avatar = avatar
		motion.set_bank(MotionBank.parse_json_text(FileAccess.get_file_as_string(path("../Assets/StreamingAssets/cheval-motions.json"))))
		for alias in ["uma_home_idle","uma_cheval_idle_action","uma_rice_idle_action","uma_eishin_idle_action"]:
			check(load_installed_clip(alias),"clip loaded "+alias)
		check(load_installed_clip("idle_talking"),"talking loaded")
		motion.set_ambient_loop("uma_home_idle")
		clock = 0.0
		previous_q = head_q()
		previous_velocity = Vector3.ZERO
		previous_hips = avatar.bone_global_position("hips")
		previous_feet = {"left":avatar.bone_global_position("leftFoot"),"right":avatar.bone_global_position("rightFoot")}
		observe("home",20.0)
		var alias := "uma_"+model.split("-")[0]+"_idle_action"
		check(motion.play_ambient_action(alias),"rare action accepted")
		observe("rare_action",7.0)
		check(motion.authored_ambient.action_name.is_empty(),"rare action ends")
		motion.play_ambient_action(alias)
		observe("before_speech",1.0)
		motion.set_ambient_suspended(true)
		motion.play_vrma("idle_talking",1.0,true)
		observe("speech",3.0)
		check(not motion.authored_ambient.owns_head() and motion.authored_ambient.action_name.is_empty(),"speech preempts authored ownership")
		motion.stop_gesture()
		motion.set_ambient_suspended(false)
		observe("speech_end",4.0)
		check(motion.authored_ambient.weight > 0.99,"home resumes after speech")
		motion.gaze_has_target = true
		motion.gaze_target = Vector2(0.9,0.3)
		motion.set_ambient_attention_override(true)
		observe("gaze_override",3.0)
		check(motion.authored_ambient.head_weight < 0.001,"gaze fully masks authored head")
		motion.set_ambient_attention_override(false)
		observe("gaze_release",3.0)
		motion.set_heading_intent(Vector2.RIGHT)
		observe("heading",4.0)
		check(motion.heading_ready(),"heading completes")
		motion.face_front()
		observe("heading_return",4.0)
		motion.idle_enabled = false
		check(not motion.play_ambient_action(alias),"disabled idle rejects rare action")
		observe("disabled_idle",3.0)
		check(not motion.authored_ambient.owns_head(),"disabled idle relinquishes authored pose")
		motion.idle_enabled = true
		observe("idle_resume",3.0)
		motion.play_ambient_action(alias)
		motion.set_ambient_attention_override(true)
		observe("before_switch",1.0)
		var replacement := "rice-shower" if model != "rice-shower" else "eishin-flash"
		check(avatar.load_from_file(path("assets/"+replacement+".vrm")),"replacement model loaded")
		motion._process(DT)
		check(motion.authored_ambient.action_name.is_empty(),"model switch clears rare action")
		check(not motion._ambient_attention_override and motion.authored_ambient.head_weight > 0.99,"model switch clears stale head mask")
		previous_q = head_q()
		previous_velocity = Vector3.ZERO
		previous_hips = avatar.bone_global_position("hips")
		previous_feet = {"left":avatar.bone_global_position("leftFoot"),"right":avatar.bone_global_position("rightFoot")}
		observe("model_switch",3.0)
		motion.set_ambient_attention_override(true)
		motion.reset_all()
		check(not motion._ambient_attention_override and motion.authored_ambient.head_weight > 0.99,"reset clears stale head mask")
		motion.free()
		avatar.free()
	analyze()
	csv.close()
	var failures := 0
	for item in checks:
		if not item.ok: failures += 1
	var hashes := {}
	for name in ["action_overlap.gd","arm_ik.gd","ambient_motion.gd","motion_player.gd","vrma_clip.gd","vrm_avatar.gd","turn_stepper.gd","leg_ik.gd","desktop_gait.gd"]: hashes[name] = FileAccess.get_sha256("res://scripts/"+name)
	var f := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"real VRM MotionPlayer integration; actual scaled world feet; no OS origin or rendered naturalness claim","checks":checks,"failures":failures,"fps":1.0/DT,"source_sha256":manifest,"source_after_sha256":hashes},"\t"))
	f.close()
	print("AUTHORED_REVIEW_RESULT ",failures)
	quit(1 if failures else 0)
func head_q() -> Quaternion:
	var sk := avatar.skeleton
	return (sk.global_transform.basis*sk.get_bone_global_pose(avatar.bone_index.head).basis).orthonormalized().get_rotation_quaternion().normalized()
func observe(stage: String,seconds: float) -> void:
	for i in int(round(seconds/DT)):
		motion._process(DT)
		clock += DT
		var q := head_q()
		var change := (q*previous_q.inverse()).normalized()
		if change.w < 0: change = -change
		var axis := Vector3(change.x,change.y,change.z)
		var velocity := axis.normalized()*rad_to_deg(2*atan2(axis.length(),change.w))/DT
		var hips := avatar.bone_global_position("hips")
		var error := 0.0
		var sole_error := 0.0
		var foot_step := 0.0
		for side in ["left","right"]:
			foot_step = maxf(foot_step,avatar.bone_global_position(side+"Foot").distance_to(previous_feet[side]))
			previous_feet[side] = avatar.bone_global_position(side+"Foot")
			var idx: int = avatar.bone_index[side+"Foot"]
			var target := avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_rest(idx).origin
			error = maxf(error,avatar.bone_global_position(side+"Foot").distance_to(target))
			var rest: Transform3D = avatar.skeleton.get_bone_global_rest(idx)
			var rest_sole := Vector3(rest.origin.x,float(avatar.sole_calibration.get("floor_y",rest.origin.y)),rest.origin.z)
			var live_sole := avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(idx)*(rest.affine_inverse()*rest_sole)
			sole_error = maxf(sole_error,live_sole.distance_to(avatar.skeleton.global_transform*rest_sole))
		var row := {"model":model,"stage":stage,"stage_time":i*DT,"head_speed":velocity.length(),"head_acceleration":(velocity-previous_velocity).length()/DT,"hips_step":hips.distance_to(previous_hips),"foot_error":error,"sole_error":sole_error,"foot_step":foot_step,"contact_weight":float(motion.authored_ambient.diagnostics.get("contact_weight",0.0))}
		rows.append(row)
		csv.store_csv_line(PackedStringArray([model,str(clock),stage,str(row.head_speed),str(row.head_acceleration),str(row.hips_step),str(error),str(sole_error),str(foot_step),str(row.contact_weight),str(motion.authored_ambient.weight),str(motion.authored_ambient.head_weight),motion.authored_ambient.action_name,str(rad_to_deg(avatar.rotation.y))]))
		previous_q = q
		previous_velocity = velocity
		previous_hips = hips
func analyze() -> void:
	for character in ["cheval-grand","rice-shower","eishin-flash"]:
		model = character
		var stages := {}
		for row in rows:
			if row.model != model: continue
			if not stages.has(row.stage): stages[row.stage] = {"head_speed":0.0,"head_acceleration":0.0,"hips_step":0.0,"foot_error":0.0,"sole_error":0.0,"foot_step":0.0}
			for key in stages[row.stage]: stages[row.stage][key] = maxf(stages[row.stage][key],row[key])
		var quiet_speed := 0.0
		var quiet_acceleration := 0.0
		var contact := 0.0
		var contact_frames := 0
		var acquisition_frames := 0
		for row in rows:
			if row.model != model: continue
			if row.stage == "home" and row.stage_time >= 1.0:
				quiet_speed = maxf(quiet_speed,row.head_speed)
				quiet_acceleration = maxf(quiet_acceleration,row.head_acceleration)
			if row.stage in ["home","rare_action","speech_end","gaze_override","gaze_release"]:
				if row.contact_weight >= 0.999:
					contact_frames += 1
					contact = maxf(contact,maxf(row.foot_error,row.sole_error))
				else: acquisition_frames += 1
		check(quiet_speed <= 12 and quiet_acceleration <= 150,"generic home quiet head bounds",{"speed":quiet_speed,"acceleration":quiet_acceleration})
		check(contact_frames >= 100 and contact <= 0.002,"authored standing actual world foot error",{"max_metres":contact,"fully_acquired_frames":contact_frames,"acquisition_frames":acquisition_frames})
		for stage in ["gaze_override","gaze_release"]:
			check(stages[stage].head_speed <= 30 and stages[stage].head_acceleration <= 150,"purposeful "+stage+" bounds",stages[stage])
		checks.append({"model":model,"label":"raw continuity by stage","ok":true,"details":stages,"diagnostic_only":true})

func load_installed_clip(name: String) -> bool:
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path("motion-assets.json")))
	for entry: Dictionary in catalogue.get("motions",[]):
		if str(entry.get("name","")) == name:
			return motion.load_vrma(name,path(str(entry.path)),str(entry.get("contact_mode","")))
	return false
