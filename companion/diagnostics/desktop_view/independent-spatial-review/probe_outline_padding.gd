extends SceneTree
const View=preload("res://scripts/desktop_view.gd")
func _initialize() -> void: call_deferred("run")
func settle() -> void:
 for i in 5:
  await process_frame
  await RenderingServer.frame_post_draw
func run() -> void:
 root.size=Vector2i(680,760);root.transparent_bg=true
 RenderingServer.set_default_clear_color(Color(0,0,0,0))
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 if not avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm")):quit(2);return
 for node in avatar.find_children("*","SkeletonModifier3D",true,false):node.active=false
 var bounds:AABB=avatar.compute_aabb()
 var ppm:=AutonomyBridge.reference_height_px(760.0)/bounds.size.y
 var cam:=Camera3D.new();root.add_child(cam);cam.current=true
 cam.projection=Camera3D.PROJECTION_ORTHOGONAL;cam.size=760.0/ppm
 cam.position=Vector3(bounds.get_center().x,bounds.get_center().y,4.0)
 var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-35,-25,0)
 var worldenv:=WorldEnvironment.new();root.add_child(worldenv)
 worldenv.environment=Environment.new();worldenv.environment.background_mode=Environment.BG_CLEAR_COLOR
 worldenv.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;worldenv.environment.ambient_light_color=Color.WHITE;worldenv.environment.ambient_light_energy=.65
 var out:=ProjectSettings.globalize_path("res://../logs/outline-padding-review");DirAccess.make_dir_recursive_absolute(out)
 View.set_outline_reference_height(avatar,0.0)
 await settle();root.get_texture().get_image().save_png(out+"/reference.png")
 root.size=Vector2i(1160,1120);cam.size=1120.0/ppm
 await settle();root.get_texture().get_image().save_png(out+"/padded-uncompensated.png")
 View.set_outline_reference_height(avatar,0.0,Vector2(680,760))
 await settle();root.get_texture().get_image().save_png(out+"/padded-corrected.png")
 print("OUTLINE_PADDING_CAPTURE_COMPLETE ",out," size=",root.size)
 quit()
