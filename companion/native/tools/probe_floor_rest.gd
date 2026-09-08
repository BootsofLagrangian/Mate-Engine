extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()<3:push_error("avatar source_directory output_directory [render] required");quit(2);return
 DirAccess.make_dir_recursive_absolute(args[2])
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 if not avatar.load_from_file(args[0]):quit(2);return
 var player:=MotionPlayer.new();root.add_child(player);player.set_process(false);player.avatar=avatar
 player._check_model_identity()
 for pair in [["enter","s"],["idle","loop"],["exit","e"]]:
  if not player.load_vrma(FloorRest.ALIASES[pair[0]],args[1].path_join("uma_sitdown02_"+pair[1]+".vrma")):quit(2);return
 var profile:=player.prepare_floor_rest()
 if profile.is_empty():push_error("profile preparation failed");quit(2);return
 print("PROFILE ",profile)
 var render:=args.size()>3 and args[3]=="render"
 if render:
  root.size=Vector2i(640,640)
  var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.15,.18);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;root.add_child(environment)
  var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,-35,0);root.add_child(light)
  var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(2,1.35,3);camera.look_at(Vector3(0,.75,0));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;camera.current=true
 var cached_at:=Time.get_ticks_usec()
 var cached_profile:=player.prepare_floor_rest()
 var cached_us:=Time.get_ticks_usec()-cached_at
 var rows:Array=[];var failures:=0
 if cached_profile!=profile:failures+=1
 var source_hashes:Dictionary={}
 for pair in [["enter","s"],["idle","loop"],["exit","e"]]:source_hashes[pair[0]]=FileAccess.get_sha256(args[1].path_join("uma_sitdown02_"+pair[1]+".vrma"))
 for fps in [30,60]:
  player.cancel_floor_rest();avatar.reset_pose();player._contact_pose="foot"
  if not player.begin_floor_rest():failures+=1;continue
  var acquired:=false;var requested:=false;var events:Array=[]
  var minimum:=INF;var maximum_head_step:=0.0;var previous_head:=Vector3.INF
  var idle_count:=0
  for frame in int(8*fps):
   player._process(1.0/fps)
   if player.floor_rest.active:
    for side in ["left","right"]:minimum=minf(minimum,player.floor_rest.contacts._support_min(side))
   var head:=avatar.bone_global_position("head")
   if previous_head.is_finite():maximum_head_step=maxf(maximum_head_step,head.distance_to(previous_head))
   previous_head=head
   if player.floor_rest.phase=="idle":
    acquired=true;idle_count+=1
    if render and fps==30 and idle_count==5:
     await process_frame;await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png(args[2].path_join("floor-rest-idle.png"))
    if idle_count>=fps and not requested:requested=player.end_floor_rest()
   if requested and not player.floor_rest.active:break
  var done:=requested and not player.floor_rest.active and player.current_contact_pose()=="foot"
  if not acquired or not done or minimum-float(profile.ground_y_local) < -.0001:failures+=1
  var row:={"fps":fps,"entered":acquired,"exited":done,"minimum_sole_y":minimum,"reference_floor_y":profile.ground_y_local,"minimum_gap_m":minimum-float(profile.ground_y_local),"max_head_frame_step_m":maximum_head_step,"last_state":player.floor_rest_state()}
  rows.append(row);print(JSON.stringify(row))
 var output:=FileAccess.open(args[2].path_join("report.json"),FileAccess.WRITE);output.store_string(JSON.stringify({"failures":failures,"profile":profile,"avatar_sha256":FileAccess.get_sha256(args[0]),"source_sha256":source_hashes,"cached_prepare_us":cached_us,"rows":rows,"scope":"actualrig full MotionPlayer floor source lifecycle; one rendered idle view optional; no native taskbar integration"},"  "));output.close()
 player.free();avatar.free();quit(1 if failures else 0)
