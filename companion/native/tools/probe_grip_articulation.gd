extends SceneTree
## Real-rig hand acquisition and release; no Windows rendering assertion.
func _init()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.is_empty():push_error("VRM path required");quit(2);return
	var avatar:=VrmAvatar.new();root.add_child(avatar)
	if not avatar.load_from_file(args[0]):quit(2);return
	avatar.scale=Vector3.ONE*.6
	var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure("computer");scene.scale=Vector3.ONE*.6;scene.set_seat_scale(.906176591431814)
	var target:=DesktopContactManipulation.target(scene,0)
	avatar.rotation.y=target.yaw
	avatar.position+=target.foot-avatar.contact_anchors().foot
	var solids:Array=[];DesktopContactManipulation._collect(scene,solids)
	var failures:=0
	var worst:=0.0
	for sample in 61:
		var weight:=float(sample)/60
		avatar.reset_pose()
		avatar.add_pose_offsets({"spine":Vector3(25*weight,0,0),"chest":Vector3(15*weight,0,0)})
		for side in ["left","right"]:
			var contact:=DesktopGripPose.solve(avatar,side,target[side],Vector3(sin(float(target.yaw)),0,cos(float(target.yaw))),weight,.3*.6*sin(PI*weight))
			var reached:bool=contact.get("reached",false)
			if sample==60:
				var error:float=contact.get("contact_error_m",INF)
				worst=maxf(worst,error)
				if not reached or error>.008:failures+=1
		var body:=DesktopContactManipulation.articulation_clear(avatar,solids)
		if not body.clear:print("BLOCKED ",weight," ",body);failures+=1
	print(JSON.stringify({"scope":"61 static source-rest arm/torso contact weights including reverse release path; no walking/Windows acceptance","avatar":args[0],"contact_feature":"palm_pad_proxy","worst_full_contact_error_m":worst,"failures":failures}))
	avatar.free();scene.free();quit(1 if failures else 0)
