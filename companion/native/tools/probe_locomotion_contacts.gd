extends SceneTree
## Composed source + DesktopGait validation, with real world root displacement.
## Usage: -- profile.json clip.vrma output.json avatar.vrm [avatar.vrm ...]
## Tests source phase and same-frame post-move contact correction; not rendered
## MotionPlayer transitions, steering, desktop projection, or Windows behavior.
var failures := 0
func _init() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<4: push_error("profile clip output avatar required");quit(2);return
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if FileAccess.get_sha256(args[1]) != profile.source_sha256: push_error("source hash mismatch");quit(2);return
	var style: Dictionary = profile.locomotion_style
	var clip := VrmaClip.new()
	if not clip.load_file(args[1]):push_error("clip load failed");quit(2);return
	var center := Vector3.ZERO
	for i in 120:center += clip.sample_hips_offset(clip.duration*i/120.0)
	center /= 120.0
	var rows: Array = []
	for path in args.slice(3):
		var avatar := VrmAvatar.new()
		root.add_child(avatar)
		if not avatar.load_from_file(path):push_error("avatar load failed");quit(2);return
		var sk := avatar.skeleton
		var leg: float = sk.get_bone_global_rest(avatar.bone_index.leftUpperLeg).origin.distance_to(sk.get_bone_global_rest(avatar.bone_index.leftFoot).origin)
		var height: float = sk.get_bone_global_rest(avatar.bone_index.hips).origin.y
		var stride: float = leg*float(style.cycle_stride_leg_lengths)
		for fps in [30,60]:
			avatar.position = Vector3.ZERO
			var gait := DesktopGait.new()
			if not gait.configure_authored_locomotion(style):push_error("invalid profile");quit(2);return
			var dt: float = 1.0/fps
			var speed := stride/clip.duration
			var prior := {}
			var max_swing := 0.0
			var max_slide := 0.0
			var max_clamp := 0.0
			var max_same_frame_residual := 0.0
			var worst_correction := {}
			var max_uncorrected_shift := 0.0
			var stance_samples := 0
			var swing_samples := 0
			var max_hip_clipping := 0.0
			for frame in int(ceil(clip.duration*fps*5)):
				var time := fposmod(frame*dt,clip.duration)
				gait.phase = time/clip.duration
				avatar.reset_pose()
				avatar.apply_normalized_rotations(clip.sample(time),1.0)
				var hips := clip.sample_hips_offset(time)-center
				if style.get("preserve_source_hip_height",false):hips.y=clip.sample_hips_offset(time).y
				hips *= height
				var limited := hips.limit_length(leg*float(style.get("hip_translation_limit_leg_lengths",.035)))
				max_hip_clipping=maxf(max_hip_clipping,hips.distance_to(limited))
				avatar.set_hips_offset(limited)
				var raw := {}
				for side in ["left","right"]:raw[side]=gait._source_leg_rotations(avatar,side)
				gait.sample(Vector2(speed*300,0),Vector2.ZERO,300,true,Vector3.ZERO)
				gait.apply(avatar,dt,true)
				var before_move := {}
				for side in ["left","right"]:before_move[side]=avatar.bone_global_position(side+"Foot")
				var movement := Vector3(0,0,speed*dt)
				avatar.position += movement
				for side in gait.diagnostics:
					if gait.diagnostics[side].stance:
						max_uncorrected_shift=maxf(max_uncorrected_shift,avatar.bone_global_position(side+"Foot").distance_to(before_move[side]))
				gait.sample(Vector2(speed*300,0),Vector2.ZERO,300,true,movement)
				gait.compensate_movement(avatar)
				for side in gait.diagnostics:
					var state: Dictionary = gait.diagnostics[side]
					var point := avatar.bone_global_position(side+"Foot")
					if float(state.contact_weight)==0:
						swing_samples += 1
						for index in raw[side]:
							var actual := sk.get_bone_pose_rotation(index)
							max_swing=maxf(max_swing,1.0-absf(actual.dot(raw[side][index])))
					if frame>fps and state.stance:
						var residual: float = point.distance_to(before_move[side])
						if residual>max_same_frame_residual:worst_correction={"phase":gait.phase,"side":side,"frame":frame,"reach_clamp_m":state.get("reach_clamp",0)}
						max_same_frame_residual=maxf(max_same_frame_residual,residual)
						if prior.has(side) and prior[side].stance:
							stance_samples += 1
							max_slide=maxf(max_slide,point.distance_to(prior[side].point))
						max_clamp=maxf(max_clamp,float(state.get("reach_clamp",0)))
					prior[side]={"point":point,"stance":state.stance}
			gait.apply(avatar,dt,false)
			var cancelled := gait._feet.is_empty() and gait.diagnostics.is_empty()
			var ok := max_swing<=.000001 and max_slide*300<=1.0 and max_same_frame_residual*300<=1.0 and stance_samples>10 and swing_samples>10 and cancelled
			if not ok:failures+=1
			var row := {"avatar":path,"avatar_sha256":FileAccess.get_sha256(path),"fps":fps,"rest_leg_m":leg,"speed_mps":speed,"stride_m":stride,"swing_quaternion_error":max_swing,"plant_slide_m":max_slide,"plant_slide_px_at_300ppm":max_slide*300,"same_frame_correction_residual_m":max_same_frame_residual,"worst_correction":worst_correction,"uncorrected_root_shift_m":max_uncorrected_shift,"max_reach_clamp_m":max_clamp,"max_source_hip_clipping_m":max_hip_clipping,"stance_samples":stance_samples,"swing_samples":swing_samples,"cancelled":cancelled,"ok":ok}
			rows.append(row);print(JSON.stringify(row))
		avatar.free()
	var report := {"scope":"Full source rotations + runtime-equivalent centered hips + DesktopGait; exact source phase, five periods, actual post-pose root movement and same-frame compensation; no full MotionPlayer/window/steering acceptance","profile_sha256":FileAccess.get_sha256(args[0]),"source_sha256":FileAccess.get_sha256(args[1]),"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"gait_sha256":FileAccess.get_sha256("res://scripts/desktop_gait.gd"),"failures":failures,"rows":rows}
	var output := FileAccess.open(args[2],FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n");output.close()
	quit(1 if failures else 0)
