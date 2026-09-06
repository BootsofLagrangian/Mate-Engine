extends SceneTree
var failures:=[]
var cells:=[]
func _init():call_deferred("run")
func run():
 await process_frame
 var viewport:=SubViewport.new();viewport.size=Vector2i(680,760);root.add_child(viewport)
 var camera:=Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=45
 var ppm:=760.0/(7.2*tan(deg_to_rad(22.5)))
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 for rig in ["cheval-grand","rice-shower","eishin-flash"]:
  avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+rig+".vrm"))
  avatar.transform=Transform3D.IDENTITY
  var local_foot:Vector3=avatar.contact_anchors().foot
  var geometry:=ProjectedAvatarGeometry.new();geometry.capture(avatar,local_foot)
  for yaw in [0.0,45.0,90.0]:
   for pitch in [0.0,30.0]:
    var orbit:=DesktopView.orbit_basis(yaw,pitch,0.0)
    camera.transform=Transform3D(orbit,orbit*Vector3(-178.0/ppm,340.0/ppm,3.6))
    var foot:=orbit*Vector3(.80497849,-1.33028173,.0081017)
    var origin:=Vector2(940,316)
    var body:=geometry.body_rect(camera,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.6),foot-local_foot*.6))
    var reserve:=geometry.navigation_rect(camera,foot,.6)
    var area:=Rect2(reserve.position+origin-Vector2(100,100),Vector2(reserve.size.x+200,body.end.y-reserve.position.y+100))
    var result:=geometry.nearest_safe_ground(camera,foot,.6,origin,[area])
    var passed:bool=result.ok
    var max_overrun:=0.0
    if result.ok:
     var point:Vector3=result.point
     passed=point.y==foot.y and result.distance_m<=.25
     for angle in 181:
      var basis:=Basis(Vector3.UP,deg_to_rad(angle*2.0)).scaled(Vector3.ONE*.6)
      var bounds:=geometry.body_rect(camera,Transform3D(basis,point-basis*local_foot));bounds.position+=origin
      if not area.encloses(bounds):passed=false
      max_overrun=maxf(max_overrun,bounds.end.y-area.end.y)
     var repeated:=geometry.nearest_safe_ground(camera,point,.6,origin,[area])
     passed=passed and repeated.ok and not repeated.changed and repeated.point==point
     var rejected:=geometry.nearest_safe_ground(camera,foot,.6,origin,[area],maxf(result.distance_m-.0001,0.0))
     if result.distance_m>.0001:passed=passed and not rejected.ok
    var cell:={"rig":rig,"yaw":yaw,"pitch":pitch,"ok":passed,"normalization":result,"max_y_overrun_px":max_overrun}
    cells.append(cell)
    if not passed:failures.append(cell)
 var report:={"scope":"18 exact swept-hull ground-placement cells,181 actual hull headings each; fixed worldY, safe idempotence, bound rejection. Geometry helper only; production admission is separate.","cells":cells,"failures":failures,"source_sha256":FileAccess.get_sha256("res://scripts/projected_avatar_geometry.gd")}
 FileAccess.open("res://../diagnostics/desktop_view/scene-ground-normalization.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("SCENE_GROUND cells=",cells.size()," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
