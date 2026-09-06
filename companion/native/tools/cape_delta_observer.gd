extends SkeletonModifier3D
## Diagnostic observer only: receives engine-supplied modifier time; writes no bones.
var host:Variant
var tag:=""
func _process_modification_with_delta(delta:float)->void:
 host.observe(tag,delta)
