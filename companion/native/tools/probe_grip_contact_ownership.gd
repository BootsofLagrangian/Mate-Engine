extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<2:push_error("VRM and authored idle VRMA required");quit(2);return
	var avatar:=VrmAvatar.new();root.add_child(avatar)
	if not avatar.load_from_file(args[0]):quit(2);return
	var motion:=MotionPlayer.new();root.add_child(motion);motion.set_process(false);motion.avatar=avatar
	if not motion.load_vrma("ownership_idle",args[1]) or not motion.set_ambient_loop("ownership_idle"):quit(2);return
	for i in 120:motion._process(1.0/60.0)
	var running:=motion.authored_ambient.weight>.99
	motion.set_upper_body_contact_lock(true)
	var suspended:=true
	for i in 60:
		motion._process(1.0/60.0)
		suspended=suspended and motion.authored_ambient.weight==0.0
	motion.set_upper_body_contact_lock(false)
	for i in 120:motion._process(1.0/60.0)
	var resumed:=motion.authored_ambient.weight>.99
	print(JSON.stringify({"authored_idle_runs_before_contact":running,"contact_excludes_authored_idle_every_frame":suspended,"idle_resumes_after_release":resumed}))
	motion.free();avatar.free();quit(0 if running and suspended and resumed else 1)
