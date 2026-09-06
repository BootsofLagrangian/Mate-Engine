extends SceneTree
const Store=preload("res://scripts/desktop_object_store.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String):
 checks+=1
 if not value:failures+=1;push_error(label)
func _init():call_deferred("run")
func run():
 var store:=Store.new()
 var area:=[Rect2i(0,0,1920,1080)]
 var computer:=store.add_object("computer",Vector2i(200,200),area)
 var chair:=store.add_object("chair",Vector2i(700,200),area)
 check(store.set_seat_scale(computer,.906),"source chair fit accepted")
 check(store.resize_object(computer,1.3,area),"independent user global size accepted")
 check(store.get_object(computer).seat_scale==.906 and store.get_object(computer).scale==1.3,"user global resize does not rewrite adjustable seat")
 var before:=store.data()
 for invalid in [NAN,INF,-.1,.49,1.251]:
  check(not store.set_seat_scale(computer,invalid) and store.data()==before,"invalid seat scale rejected without mutation")
 check(not store.set_seat_scale(chair,.9),"ordinary chair cannot acquire computer capability")
 var restored:=Store.new();restored.set_data(JSON.parse_string(JSON.stringify(store.data())))
 check(absf(restored.get_object(computer).seat_scale-.906)<1e-12 and restored.get_object(computer).scale==1.3,"source fit and user global scale survive JSON roundtrip")
 var original:={"version":1,"objects":[{"id":"obj_7","type":"computer","x":50,"y":100,"scale":.8,"visible":true}]}
 restored.set_data(original)
 check(restored.get_object("obj_7").scale==.8 and restored.get_object("obj_7").get("seat_scale",1.0)==1.0,"existing user configuration retains global size and original chair")
 original.objects[0].seat_scale=INF;restored.set_data(original)
 check(restored.get_object("obj_7").get("seat_scale",1.0)==1.0,"corrupt seat field cannot inject nonfinite geometry")
 print("Seat scale: %d checks, %d failures" %[checks,failures]);quit(1 if failures else 0)
