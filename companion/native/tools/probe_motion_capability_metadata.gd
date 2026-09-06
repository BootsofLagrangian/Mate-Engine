extends SceneTree
func _init() -> void:
	var entry:={"name":"test","duration":1.0,"sha256":"a".repeat(64),"locomotion":true,"seated_transition":"enter","locomotion_style":{"version":1,"cycle_stride_leg_lengths":1.8,"contacts":{"left":[0.05,0.45],"right":[0.55,0.95]},"hip_translation_limit_leg_lengths":0.2}}
	var failures:=0
	if not MotionBank.validate_asset_entry(entry).is_empty():failures+=1
	for bad in ["sit",1,{},null]:
		var candidate:=entry.duplicate(true)
		candidate.seated_transition=bad
		if MotionBank.validate_asset_entry(candidate).is_empty():failures+=1
	var invalid:=entry.duplicate(true)
	invalid.locomotion_style.contacts.left=[[0.0,0.5],[0.4,0.7]]
	if MotionBank.validate_asset_entry(invalid).is_empty():failures+=1
	var errors:Array[String]=[]
	var parsed:=MotionBank.parse_asset_catalog({"motions":[entry]},errors)
	if parsed.size()!=1 or parsed[0].seated_transition!="enter" or parsed[0].locomotion_style!=entry.locomotion_style:failures+=1
	print("MOTION_CAPABILITY_FAILURES=",failures)
	quit(1 if failures else 0)
