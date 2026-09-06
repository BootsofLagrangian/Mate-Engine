extends SceneTree
class WindowStub:
	extends Node
	var applied := {}
	func apply_record(record: Dictionary, _size: Vector2i): applied=record.duplicate(true)
class HostStub:
	extends DesktopObjectsHost
	var saves := 0
	func _spatial_enabled() -> bool: return true
	func _sync_spatial_window(id: String) -> bool:
		var record: Dictionary=store.get_object(id)
		return float(record.scale)<=1.1 and absf(float(record.yaw_deg))<80.0
	func _after_change(): saves+=1
	func cancel_interaction(_reason="cancelled"): pass
	func screen_rects() -> Array: return [Rect2i(0,0,3000,2000)]
func _initialize():
	var objects:=HostStub.new();root.add_child(objects)
	var id=objects.store.add_object("chair",Vector2i(300,400),objects.screen_rects())
	objects.store.resize_object(id,1.0,objects.screen_rects())
	var window:=WindowStub.new();objects.add_child(window);objects.windows[id]=window
	var original=objects.store.data().duplicate(true)
	assert(not objects.configure_object(id,90,"cool"))
	assert(objects.store.data()==original and window.applied==objects.store.get_object(id) and objects.saves==0)
	assert(not objects.resize_object(id,1.5))
	assert(objects.store.data()==original and window.applied==objects.store.get_object(id) and objects.saves==0)
	assert(objects.configure_object(id,45,"cool"))
	assert(objects.store.get_object(id).yaw_deg==45 and window.applied.appearance=="cool" and objects.saves==1)
	assert(objects.resize_object(id,1.05))
	assert(is_equal_approx(objects.store.get_object(id).scale,1.05) and objects.saves==2)
	objects.host=null;objects.free()
	print("Spatial configuration transaction: 8 checks, 0 failures")
	quit()
