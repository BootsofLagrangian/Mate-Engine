extends SceneTree
func _init() -> void:
	var player := MotionPlayer.new()
	var path := ProjectSettings.globalize_path("res://../assets/motions/walk.vrma")
	assert(player.load_vrma("candidate",path))
	assert(player.register_locomotion_clip("candidate",true))
	assert(player.locomotion_clips.has("candidate"))
	assert(player._locomotion_hip_centers.has("candidate"))
	player.clear_locomotion_registrations()
	assert(not player.locomotion_clips.has("candidate"))
	assert(player._locomotion_hip_centers.is_empty())
	assert(player.vrma_clips.has("candidate")) # still available as ordinary preview
	assert(player.locomotion_clips == {"walk":false,"walk_formal":false})
	assert(player.register_locomotion_clip("candidate",false))
	assert(not player.locomotion_clips.candidate)
	player.free()
	print("REGISTRY_CHECKS=10 FAILURES=0")
	quit()
