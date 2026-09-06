extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
 root.size=Vector2i(720,800)
 var output:=ProjectSettings.globalize_path("res://../diagnostics/desktop_objects/normal-chair-alignment")
 DirAccess.make_dir_recursive_absolute(output)
 var stage:=Node3D.new();root.add_child(stage)
 var environment:=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.14,.17,.21)
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
 stage.add_child(environment)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-30,0);light.light_energy=.8;stage.add_child(light)
 var camera:=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.15;camera.current=true
 var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(2,2);floor.mesh=plane
 var material:=StandardMaterial3D.new();material.albedo_color=Color(.23,.27,.31);floor.material_override=material;floor.position.y=-.001;stage.add_child(floor)
 var avatar:=VrmAvatar.new();stage.add_child(avatar);avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"));avatar.set_process(false)
 var player:=MotionPlayer.new();stage.add_child(player);player.set_process(false);player.avatar=avatar;player.idle_enabled=false;player.gaze_enabled=false
 for name in ["sit_enter","sit_idle","sit_exit"]:player.load_vrma(name,ProjectSettings.globalize_path("res://../assets/motions/"+name+".vrma"))
 player.register_seated_transition("enter","sit_enter");player.register_seated_transition("exit","sit_exit");player._process(1.0/60)
 var req:=player.seated_transition_requirements("enter");var clearance:float=req.source_seat_clearance_local
 player.set_seated_floor(clearance);var geometry:=avatar.calibrate_seated_pose(player.vrma_clips.sit_idle.sample(0))
 var chair:=DesktopObjectContactScene.new();stage.add_child(chair);chair.configure("chair")
 chair.scale=Vector3.ONE*.6*clampf(clearance/.48,.5,1.25)
 var delta:Vector3=req.source_root_delta_local;delta.y=clearance+float(avatar.sole_calibration.floor_y)-Vector3(geometry.anchor).y
 player.start_seated_transition("enter",delta)
 for frame in 84:player._process(1.0/60)
 player.finish_seated_transition()
 for frame in 60:player._process(1.0/60)
 avatar.basis=Basis.IDENTITY.scaled(Vector3.ONE*.6);avatar.position=chair.socket_world("seat")-avatar.basis*Vector3(geometry.anchor)
 var seat:Vector3=chair.socket_world("seat")
 var chair_floor:=INF
 for vertex in chair.geometry_points_local():chair_floor=minf(chair_floor,(chair.global_transform*vertex).y)
 var foot_floor:=INF
 for side in player.authored_seated_feet.foot_vertices:
  for candidate in player.authored_seated_feet.foot_vertices[side]:
   var point:=Vector3.ZERO
   for bind in candidate.influences:point+=(avatar.skeleton.get_bone_global_pose(bind[0])*bind[1]*candidate.vertex)*bind[2]
   foot_floor=minf(foot_floor,(avatar.skeleton.global_transform*(point/candidate.total)).y)
 var rays:Array=[]
 for dx in [-.06,0,.06]:
  var origin:=chair.to_global(Vector3(dx,.6,.08));var best:=INF;var best_point:=Vector3.ZERO;var hit_mesh:=""
  var meshes:Array=[];collect(chair,meshes)
  for mesh:MeshInstance3D in meshes:
   var faces:PackedVector3Array=mesh.mesh.get_faces()
   for i in range(0,faces.size(),3):
    var hit:Variant=Geometry3D.ray_intersects_triangle(origin,Vector3.DOWN,mesh.global_transform*faces[i],mesh.global_transform*faces[i+1],mesh.global_transform*faces[i+2])
    if hit is Vector3 and origin.distance_to(hit)<best:best=origin.distance_to(hit);best_point=hit;hit_mesh=str(mesh.name)
  rays.append({"asset_x":dx,"hit":best_point,"mesh":hit_mesh,"surface_above_anchor_m":best_point.y-seat.y})
 var report:Dictionary={"character":"cheval-grand","scope":"reconstructed installed source terminal pose; not a replay of the Windows skeleton snapshot","avatar_scale":.6,"chair_scale":chair.scale.x,"geometry":geometry.diagnostics,"seat_world":seat,"sit_world":avatar.contact_anchors().sit,"seat_error_m":seat.distance_to(avatar.contact_anchors().sit),"pelvis_world":avatar.bone_global_position("hips"),"chair_lowest_vertex_y":chair_floor,"actual_selected_foot_mesh_min_y":foot_floor,"chair_facing":chair.facing_direction_world(),"avatar_forward":avatar.global_basis.z.normalized(),"cushion_rays":rays}
 var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("CHAIR_ALIGNMENT ",report)
 for view in [{"id":"side","position":Vector3(2,.48,0)},{"id":"oblique","position":Vector3(1.4,1.0,1.7)},{"id":"rear-oblique","position":Vector3(-1.4,.8,-1.7)}]:
  camera.position=view.position;camera.look_at(Vector3(0,.4,0))
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(output.path_join(view.id+".png"))
 print("CHAIR_ALIGNMENT_OUTPUT=",output);quit()
func collect(node:Node,result:Array)->void:
 if node is MeshInstance3D and node.mesh!=null:result.append(node)
 for child in node.get_children():collect(child,result)
