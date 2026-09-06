extends "res://scripts/living_behavior.gd"
## Real event/request/cancel routing; discovery and network publication isolated.
var published_count := 0
func _refresh_targets() -> void: pass
func publish_world(_force: bool = false) -> void: published_count += 1
