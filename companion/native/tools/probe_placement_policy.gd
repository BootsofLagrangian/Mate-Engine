extends SceneTree
func _initialize()->void:
	var learner=load("res://scripts/placement_preferences.gd").new();learner.configure("")
	var policy=load("res://scripts/curiosity_policy.gd").new()
	var monitor:=Rect2(0,0,2000,1000)
	var candidates:=[{"id":"left","point":Vector2(400,900),"kind":"surface"},{"id":"right","point":Vector2(1600,900),"kind":"surface"}]
	var initial:Dictionary=policy.choose(candidates,Vector2(1000,900),10)
	var taught:Dictionary=candidates[1] if initial.target_id=="left" else candidates[0]
	for i in 3:learner.record_placement("test",taught.point,monitor,"taskbar",10+i)
	var d:=BehaviorDirector.new();d.set_character("test");d.fly_enabled=false
	d.preference_provider=func(candidate:Dictionary):return learner.bonus("test",candidate.point,monitor,"taskbar",20)
	for candidate in candidates:d.observe_interest(candidate.id,candidate.point,.65,120,"surface")
	d.tick(12.1,{"character_id":"test","can_move":true,"actor_point":Vector2(1000,900),"autonomy_state":"rest"})
	var selected:Dictionary=d.curiosity_decisions[-1]
	var count:int=learner.export_diagnostics().event_count
	d.curiosity.observe_arrival(taught.id,taught.point,30,"arrived")
	var offline=load("res://scripts/placement_preferences.gd").new();offline.configure("");offline.rebuild(learner.export_diagnostics().events)
	var same:bool=is_equal_approx(learner.bonus("test",taught.point,monitor,"taskbar",40),offline.bonus("test",taught.point,monitor,"taskbar",40))
	var checks:={"explicit_placement_changes_actual_director_choice":selected.target_id==taught.id,"self_arrival_does_not_train":learner.export_diagnostics().event_count==count,"offline_model_matches":same}
	print("PLACEMENT_POLICY ",JSON.stringify(checks))
	quit(0 if checks.values().all(func(v):return v) else 1)
