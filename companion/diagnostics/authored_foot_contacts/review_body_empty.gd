extends SceneTree
class UnsupportedAvatar extends VrmAvatar:
 func body_capsule_snapshot()->Dictionary:return {}
class ReadyCarrier extends SeatedCarrier:
 func valid(_player:MotionPlayer)->bool:return true
func _init()->void:
 var p:=MotionPlayer.new()
 var a:=UnsupportedAvatar.new()
 p.avatar=a
 p.seated_carrier=ReadyCarrier.new()
 p.seated_carrier.active=true
 p.seated_carrier.diagnostics={"ready":true}
 var result:=p.seated_carrier_body_snapshot()
 var failures:=0 if result.is_empty() else 1
 print("BODY_EMPTY_FAILURES=",failures)
 p.free();a.free();quit(failures)
