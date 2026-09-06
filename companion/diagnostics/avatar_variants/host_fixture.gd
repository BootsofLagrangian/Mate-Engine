extends "res://scripts/main.gd"
## Transaction harness: production request/download callback/apply methods remain.
## Rendering/contact internals stubbed; actual Windows rig reload is separate.
var frame_calls := 0
var stand_calls := 0
func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func _frame_avatar() -> void: frame_calls += 1
func _stand_up(_reason: String = "") -> void: stand_calls += 1
