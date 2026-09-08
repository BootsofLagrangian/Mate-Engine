extends SceneTree
func _init()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=3:push_error("avatar source_directory output.json required");quit(2);return
 var avatars:Array=[]
 for i in 2:
  var avatar:=VrmAvatar.new();root.add_child(avatar)
  if not avatar.load_from_file(args[0]):quit(2);return
  avatars.append(avatar)
 var player:=MotionPlayer.new();root.add_child(player);player.set_process(false);player.avatar=avatars[0];player._check_model_identity()
 for pair in [["enter","s"],["idle","loop"],["exit","e"]]:
  if not player.load_vrma(FloorRest.ALIASES[pair[0]],args[1].path_join("uma_sitdown02_"+pair[1]+".vrma")):quit(2);return
 var notices:Array=[]
 player.floor_rest.finished.connect(func(outcome:String):
  if outcome=="interrupted":
   notices.append(outcome)
   player.cancel_floor_rest()) # Reentrant host cleanup must not double-emit.
 var rows:Array=[];var failures:=0
 for phase in ["enter","idle","exit"]:
  for reason in ["reset","cancel","source","model"]:
   player.reset_all();player.avatar=avatars[0];player._check_model_identity();player.avatar.reset_pose()
   var began:=player.begin_floor_rest()
   if phase!="enter":
    for frame in 180:
     player._process(1.0/60)
     if player.floor_rest.phase=="idle":break
   if phase=="exit":player.end_floor_rest()
   player._process(1.0/60)
   var prepared:bool=began and player.floor_rest.active and player.floor_rest.phase==phase
   notices.clear()
   if reason=="reset":player.reset_all()
   elif reason=="cancel":player.cancel_floor_rest()
   elif reason=="source":
    var replacement:=VrmaClip.new()
    replacement.load_file(args[1].path_join("uma_sitdown02_e.vrma"))
    player.vrma_clips[FloorRest.ALIASES.exit]=replacement
   else:player.avatar=avatars[1]
   player._process(1.0/60);player._process(1.0/60);player.cancel_floor_rest()
   var ok:bool=prepared and not player.floor_rest.active and player.current_contact_pose()=="foot" and notices==["interrupted"] and not player.floor_rest.contacts.active
   if not ok:failures+=1
   var row:={"phase":phase,"reason":reason,"prepared":prepared,"interruptions":notices.size(),"active":player.floor_rest.active,"contact_pose":player.current_contact_pose(),"contact_reference_active":player.floor_rest.contacts.active,"ok":ok}
   rows.append(row);print(JSON.stringify(row))
 var file:=FileAccess.open(args[2],FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"rows":rows,"scope":"actual rig; reset/cancel/same-name source replacement/model replacement in S/idle/E; reentrant host cleanup"},"  "));file.close()
 player.free()
 for avatar in avatars:avatar.free()
 quit(1 if failures else 0)
