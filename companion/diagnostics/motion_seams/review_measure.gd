extends SceneTree
func _init():call_deferred("run")
func run():
 var rows:Array=[];var failures:=0
 for character in ["cheval-grand","rice-shower","eishin-flash"]:
  var a:=VrmAvatar.new();root.add_child(a);a.load_from_file(ProjectSettings.globalize_path("res://../assets/"+character+".vrm"));a.rotation.y=0.7;a.scale=Vector3.ONE*0.6
  var loose:=MeshInstance3D.new();loose.mesh=BoxMesh.new();loose.position=Vector3(1.3,0.5,0);loose.scale=Vector3.ONE*0.1;a.model.add_child(loose)
  var clip:=VrmaClip.new();clip.load_file(ProjectSettings.globalize_path("res://../assets/motions/authored_wave.vrma"))
  for phase in [0.0,0.2,0.4,0.6,0.8]:
   a.reset_pose();a.apply_normalized_rotations(clip.sample(clip.duration*phase),1)
   var original:Dictionary=SeatedGeometryCalibrator.measure(a,{},true,false)
   var optimized:Dictionary=TransitionBoundsMeasure.measure(a,true)
   var exact:AABB=original.bounds;var broad:AABB=optimized.bounds
   var low:=broad.position-exact.position;var high:=exact.end-broad.end
   var overflow:=maxf(maxf(low.x,maxf(low.y,low.z)),maxf(high.x,maxf(high.y,high.z)))
   var y_error:=absf(exact.position.y-broad.position.y)
   if overflow>0.00001 or y_error>0.00001:failures+=1
   rows.append({"character":character,"phase":phase,"overflow_m":maxf(0,overflow),"minimum_y_error_m":y_error,"extra_x_m":broad.size.x-exact.size.x,"extra_z_m":broad.size.z-exact.size.z})
  var meshes:Array=[];a._collect_meshes(a.model,meshes)
  for mesh in meshes:mesh.hide()
  if not TransitionBoundsMeasure.measure(a,true).is_empty():failures+=1
  a.free()
 FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/motion_seams/review-measure.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows},"  ")+"\n")
 print("INDEPENDENT_BOUNDS_MEASURE_FAILURES=",failures);quit(1 if failures else 0)
