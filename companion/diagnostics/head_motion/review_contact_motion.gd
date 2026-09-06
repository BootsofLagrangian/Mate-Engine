extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var a := VrmAvatar.new()
	root.add_child(a)
	a.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	a.process_mode = Node.PROCESS_MODE_DISABLED
	var p := MotionPlayer.new()
	root.add_child(p)
	p.avatar = a
	p.set_process(false)
	p.idle_enabled = false
	p.gaze_enabled = false
	for name in ["walk","sit_idle","idle_natural","idle_talking","dance","interact","pick_up","walk_formal"]:
		p.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
		var c: VrmaClip = p.vrma_clips[name]
		var first := c.sample(0)
		var last := c.sample(c.duration)
		var near := c.sample(c.duration-1.0/60)
		var seam := 0.0
		var frame_seam := 0.0
		var bone := ""
		for b in first:
			var angle := rad_to_deg(first[b].angle_to(last[b]))
			if angle > seam: seam = angle; bone = b
			frame_seam = maxf(frame_seam,rad_to_deg(first[b].angle_to(near[b])))
		print("SEAM ",name," endpoint_deg=",seam," bone=",bone," prior_frame_deg=",frame_seam)
	for i in 60: p._process(1.0/60)
	var target := a.bone_global_position("leftUpperArm") + Vector3(.24,-.12,.12)
	p.start_contact_pose("lean",target)
	for i in 30:
		p._process(1.0/60)
		if i in [0,1,5,15,29]: print("LEAN_FRAME ",i," claimed=",p.contact_reachable," actual_world_error=",target.distance_to(a.bone_global_position("leftHand")))
	p.stop_contact_pose()
	p.start_contact_pose("sit")
	for i in 180: p._process(1.0/60)
	p.play_vrma("idle_talking",1,true)
	for i in 60: p._process(1.0/60)
	print("SEATED_TALK hip_y=",a.bone_global_position("hips").y," knee_y=",a.bone_global_position("leftLowerLeg").y," contact=",p.current_contact_pose())
	p.free();a.free();quit()
