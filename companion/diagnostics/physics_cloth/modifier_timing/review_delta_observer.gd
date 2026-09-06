extends SkeletonModifier3D
var host:Variant
var tag:=""
func _process_modification_with_delta(delta:float):host.observe(tag,delta)
