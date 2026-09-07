extends "probe_windows_continuity.gd"
var carrier_fixture:Dictionary={}
var captured_terminal:=false
func sample()->void:
 super.sample()
 if app==null or captured_terminal:return
 if app.motion.seated_carrier.active and app.objects.contact_scene_active():
  var body:Dictionary=app.motion.seated_carrier_body_snapshot()
  if not body.is_empty():
   var scene=app.objects._contact_scene
   var helper=load("res://scripts/desktop_seated_carrier_sweep.gd")
   carrier_fixture={"body":body.duplicate(true),"fixed":helper.fixed_solids(scene),"seat_transform":scene.seat_node().global_transform,"scene_transform":scene.global_transform,"setup":scene.seat_setup().duplicate(true),"interaction":app.objects._interaction.duplicate(true),"feet":app.motion.seated_carrier_state(),"model_id":app.avatar.model.get_instance_id(),"ms":elapsed()}
   report["last_carrier_fixture"]={"body":body,"fixed":carrier_fixture.fixed,"seat_transform":carrier_fixture.seat_transform,"scene_transform":carrier_fixture.scene_transform,"setup":carrier_fixture.setup,"feet":carrier_fixture.feet,"ms":elapsed()}
 if not report.commands.is_empty():
  captured_terminal=true
  report["failure_diagnostics"]=app.objects.fit_diagnostics.duplicate(true)
  report["fixture_record"]=app.objects.store.data()
  var file:=FileAccess.open(output.path_join("carrier-fixture.bin"),FileAccess.WRITE)
  file.store_var(carrier_fixture);file.close()
  call_deferred("finish")
