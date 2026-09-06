extends SceneTree
const Samples=preload("res://tools/garment_quality_samples.gd")
var output:="/tmp/cape-continuous-automatic"
var profile:Dictionary
var avatars:=[]
var players:=[]
var samplers:=[]
var cameras:=[]
var rows:=[]
var captures:=[{},{}]
var counts:=[0,0]
var previous:=[{},{}]
var frame:=-1
var generation:=0
var phase:="startup"
var max_source_error:=0.0
var max_world_error:=0.0
var seat_origins:=[Vector3.ZERO,Vector3.ZERO]
var seat_deltas:=[Vector3.ZERO,Vector3.ZERO]
var parameter_endpoints:=[]
var parameter_checks:=[]
var original_parameters:={}
var overlay:Label
var input_directions:=[{},{}]
var engine_deltas:=[-1.0,-1.0]
var modifier_observations:=[]
func observe(tag:String,delta:float)->void:
 if not started or frame<0:return
 var parts:=tag.split(":");var side:=int(parts[0]);var epoch:=int(parts[1])
 if epoch!=generation:return
 if parts[2]=="before":engine_deltas[side]=delta
 modifier_observations.append({"tag":tag,"source_frame":frame,"engine_frame":Engine.get_process_frames(),"engine_delta_s":delta})
var capture_mesh:=true
var source_start:={}
func hashes()->Dictionary:
 var result:={}
 for path in ["res://addons/vrm/vrm_secondary.gd","res://addons/vrm/vrm_spring_bone.gd","res://addons/vrm/vrm_spring_bone_logic.gd","res://tools/probe_cape_continuous_automatic.gd","res://tools/cape_delta_observer.gd","res://tools/garment_quality_samples.gd","res://scripts/motion_player.gd","res://scripts/seated_transition.gd","res://scripts/vrm_avatar.gd","res://scripts/desktop_gait.gd","res://../assets/cheval-grand.vrm","res://../assets/research/cape-candidates/cyspring-cloth00.json"]:
  result[path]=FileAccess.get_sha256(path)
 return result
func _init()->void:call_deferred("run")
func params(avatar:VrmAvatar)->Dictionary:
 var result:={}
 for state in avatar.spring_contacts.secondary.spring_bones_internal:
  var sb:VRMSpringBone=state.springbone
  result[state.joint_nodes[0]]={"stiffness_scale":sb.stiffness_scale,"gravity_scale":sb.gravity_scale,"drag_scale":sb.drag_force_scale,"radius_scale":sb.hit_radius_scale,"stiffness":Array(sb.stiffness_force),"gravity":Array(sb.gravity_power),"drag":Array(sb.drag_force),"radius":Array(sb.hit_radius),"collider_ids":sb.collider_groups.map(func(c):return c.get_instance_id())}
 return result
func apply_candidate(avatar:VrmAvatar, gravity_anchor:float)->void:
 for chain in profile.chains:
  for state in avatar.spring_contacts.secondary.spring_bones_internal:
   if state.joint_nodes[0]!=chain.root: continue
   print("CANDIDATE_CHAIN ", chain.root, " gravity ",gravity_anchor)
   # Isolate resource: other chains can share the imported group.
   state.springbone=state.springbone.duplicate(false)
   var stiffness:=PackedFloat64Array();var gravity:=PackedFloat64Array()
   for name in state.joint_nodes:
    var source:Dictionary={}
    for joint in chain.joints:
     if joint._boneName==name: source=joint;break
    if source.is_empty(): source=chain.joints[-1]
    stiffness.append(2.5*float(source._stiffnessForce)/float(chain.joints[0]._stiffnessForce))
    gravity.append(gravity_anchor*float(source._gravity)/float(chain.joints[0]._gravity))
   state.springbone.stiffness_force=stiffness;state.springbone.gravity_power=gravity
   state.springbone.stiffness_scale=1.0;state.springbone.gravity_scale=1.0
   # Preserve imported drag/radii/colliders: source unit/basis mapping is unresolved.


func live(side:int, epoch:int)->void:
 if epoch!=generation or frame<0:return
 counts[side]+=1
 var avatar:VrmAvatar=avatars[side]
 var secondary=avatar.spring_contacts.secondary
 var bones:={};var tails:={};var origins:={};var max_deflection:=0.0;var max_step:=0.0;var length_error:=0.0
 for si in secondary.spring_bones_internal.size():
  var state=secondary.spring_bones_internal[si]
  if not "Mantle" in state.joint_nodes[0]:continue
  var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[si]]
  for joint in state.verlets:
   var name:String=avatar.skeleton.get_bone_name(joint.bone_idx)
   var pose:=avatar.skeleton.get_bone_global_pose(joint.bone_idx)
   var tail:Vector3=joint.current_tail
   length_error=maxf(length_error,absf(tail.distance_to(xf*pose.origin)-joint.length))
   tails[name]=[tail.x,tail.y,tail.z]
   var origin:Vector3=xf*pose.origin
   origins[name]=[origin.x,origin.y,origin.z]
   if input_directions[side].has(name):max_deflection=maxf(max_deflection,(tail-origin).normalized().angle_to(input_directions[side][name]))
   if previous[side].has(name):max_step=maxf(max_step,tail.distance_to(previous[side][name]))
   previous[side][name]=tail
   bones[name]={"origin":pose.origin,"tail":tail,"scale":pose.basis.get_scale()}
 var sample:Dictionary=samplers[side].sample(avatar) if capture_mesh else {}
 captures[side]={"frame":frame,"generation":generation,"phase":phase,"boundary":frame in [120,420,480,600,720,900,1100],"yaw":avatar.rotation.y,"callback":counts[side],"elapsed":players[side].elapsed,"gesture":players[side].current_gesture(),"max_tail_step_m":max_step,"length_error_m":length_error,"bones":bones,"mesh":sample}
 # Every actual callback retained, independent of displayed frame count.
 rows.append({"side":side,"frame":frame,"engine_delta_s":engine_deltas[side],"engine_frame":Engine.get_process_frames(),"delta_s":secondary.get_process_delta_time(),"generation":generation,"phase":phase,"boundary":frame in [120,420,480,600,720,900,1100],"yaw":avatar.rotation.y,"callback":counts[side],"max_tail_step_m":max_step,"length_error_m":length_error,"tails":tails,"origins":origins,"max_source_deflection_rad":max_deflection})
func prepare_avatar(side:int)->void:
 var avatar:VrmAvatar=avatars[side]
 avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
 var before:=params(avatar)
 if side==1:apply_candidate(avatar,1.2)
 var after:=params(avatar)
 var selected:={}
 for c in profile.chains:selected[c.root]=true
 var unchanged:=true
 for key in before:
  if not selected.has(key) and before[key]!=after[key]:unchanged=false
 parameter_checks.append({"side":side,"generation":generation,"noncape_unchanged":unchanged,"before":before,"after":after})
 var player:MotionPlayer=players[side]
 player._check_model_identity()
 player.elapsed=0;player._noise.seed=4107;player._blink_next=1000
 player.play_vrma("uma_cheval_idle",1,true)
 avatar.rebase_secondary_physics()
 var sampler:=Samples.new();sampler.configure(avatar,"Mantle");samplers[side]=sampler
 previous[side]={};captures[side]={}
 avatar.spring_contacts.secondary.internal_modifier_node.modification_processed.connect(live.bind(side,generation))
 var observer_script=load("res://tools/cape_delta_observer.gd")
 var first=observer_script.new();first.host=self;first.tag="%d:%d:before"%[side,generation];avatar.skeleton.add_child(first,false,Node.INTERNAL_MODE_FRONT)
 var last=observer_script.new();last.host=self;last.tag="%d:%d:after"%[side,generation];avatar.skeleton.add_child(last,false,Node.INTERNAL_MODE_BACK)
func compare_mesh(a:Dictionary,b:Dictionary)->Dictionary:
 var displacements:=[];var edges:=[];var areas:=[];var reversed:=0
 assert(a.points.size()==b.points.size() and a.edges.size()==b.edges.size())
 for i in a.points.size():displacements.append(a.points[i].distance_to(b.points[i]))
 for i in a.edges.size():
  if a.edges[i]>.001:edges.append(absf(b.edges[i]/a.edges[i]-1.0))
 for i in a.normals.size():
  if a.normals[i].length()>1e-8:
   areas.append(b.normals[i].length()/a.normals[i].length())
   if a.normals[i].dot(b.normals[i])<0:reversed+=1
 displacements.sort();edges.sort();areas.sort()
 return {"vertices":a.points.size(),"triangles":a.normals.size(),"max_displacement_m":displacements[-1],"p95_displacement_m":displacements[int(displacements.size()*.95)],"max_relative_edge_change":edges[-1],"p95_relative_edge_change":edges[int(edges.size()*.95)],"min_relative_area":areas[0],"p05_relative_area":areas[int(areas.size()*.05)],"opposed_normals":reversed}
func source_error()->float:
 var error:=0.0
 for key in avatars[0].bone_index:
  if not avatars[1].bone_index.has(key):continue
  var a:Transform3D=avatars[0].skeleton.get_bone_pose(avatars[0].bone_index[key])
  var b:Transform3D=avatars[1].skeleton.get_bone_pose(avatars[1].bone_index[key])
  error=maxf(error,a.origin.distance_to(b.origin))
  for axis in 3:error=maxf(error,a.basis[axis].distance_to(b.basis[axis]))
 return error

class Driver:
 extends Node
 var coordinator:Variant
 var before:=true
 func _process(_delta:float)->void:
  if before:coordinator.begin_frame()
  else:coordinator.end_frame()
var started:=false
var heading:=0.0
var velocity:=Vector3.ZERO
var meshes:=[]
var draw_last_frame:=-1
var frame_inputs:={}
func run()->void:
 source_start=hashes()
 profile=JSON.parse_string(FileAccess.get_file_as_string("res://../assets/research/cape-candidates/cyspring-cloth00.json"))
 DirAccess.make_dir_recursive_absolute(output)
 root.size=Vector2i(1100,760)
 for side in 2:
  var container:=SubViewportContainer.new();container.position=Vector2(side*550,30);container.size=Vector2(550,730);root.add_child(container)
  var viewport:=SubViewport.new();viewport.size=Vector2i(550,730);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
  var stage:=Node3D.new();viewport.add_child(stage)
  var camera:=Camera3D.new();camera.fov=32;stage.add_child(camera);cameras.append(camera)
  var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-30,0);stage.add_child(light)
  var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.1,.13,.18);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;stage.add_child(env)
  var avatar:=VrmAvatar.new();stage.add_child(avatar);avatars.append(avatar)
  var player:=MotionPlayer.new();stage.add_child(player);player.set_process(false);player.avatar=avatar;player.gaze_enabled=false;player.idle_enabled=false
  for clip in ["uma_cheval_idle","uma_walk","authored_overhead_stretch","sit_enter","sit_exit","sit_idle"]:assert(player.load_vrma(clip,ProjectSettings.globalize_path("res://../assets/motions/"+clip+".vrma")))
  player.register_locomotion_clip("uma_walk",true)
  players.append(player);samplers.append(null)
  prepare_avatar(side)
 overlay=Label.new();overlay.position=Vector2(12,5);root.add_child(overlay)
 for side in 2:
  players[side].register_seated_transition("enter","sit_enter");players[side].register_seated_transition("exit","sit_exit")
  players[side].set_process(true)
 var before:=Driver.new();before.coordinator=self;before.before=true;before.process_priority=-20;root.add_child(before)
 var after:=Driver.new();after.coordinator=self;after.before=false;after.process_priority=-5;root.add_child(after)
 RenderingServer.frame_post_draw.connect(capture_draw)
 started=true

func begin_frame()->void:
 if not started:return
 frame+=1
 var f:=frame
 var t:=f/60.0
 if f==720:
  parameter_endpoints.append({"at":"before_reload","generation":generation,"baseline":params(avatars[0]),"candidate":params(avatars[1])})
  generation+=1
  for side in 2:
   avatars[side].clear_model();avatars[side].position=Vector3(.2,0,-.1);avatars[side].scale=Vector3.ONE*.9
   prepare_avatar(side)
 phase="startup_idle" if f<120 else "walk_blend_in" if f<180 else "walk" if f<240 else "curved_turn" if f<360 else "walk_blend_out" if f<480 else "overhead_blend" if f<600 else "idle_return" if f<720 else "reload_settling" if f<900 else "sit_enter" if f<990 else "sit_hold" if f<1100 else "sit_exit" if f<1170 else "final_idle"
 var speed:=0.0
 if f>=120 and f<420:
  speed=.18*smoothstep(120.0,180.0,float(f))*(1.0-smoothstep(360.0,420.0,float(f)))
 heading=deg_to_rad(110.0)*smoothstep(240.0,360.0,float(f))
 velocity=Vector3(sin(heading),0,cos(heading))*speed
 for side in 2:
  var player:MotionPlayer=players[side];var avatar:VrmAvatar=avatars[side]
  if f==120:player.prepare_scene_locomotion(0.0);player.play_vrma("uma_walk",1,true)
  if f==420:player.finish_locomotion();player.play_vrma("uma_cheval_idle",1,true)
  if f==480:player.play_vrma("authored_overhead_stretch",1,false)
  if f==600:player.play_vrma("uma_cheval_idle",1,true)
  if f==900:
   player.set_seated_floor(.45)
   seat_origins[side]=avatar.position
   seat_deltas[side]=player.seated_transition_requirements("enter").source_root_delta_local
   assert(player.start_seated_transition("enter",seat_deltas[side]))
  if f==1100:
   seat_origins[side]=avatar.position
   seat_deltas[side]=-seat_deltas[side]
   assert(player.start_seated_transition("exit",seat_deltas[side]))

func end_frame()->void:
 if not started:return
 var f:=frame
 var t:=f/60.0
 for side in 2:
  var player:MotionPlayer=players[side];var avatar:VrmAvatar=avatars[side]
  if player.seated_transition.active:
   var state:=player.seated_transition_state()
   avatar.position=seat_origins[side]+avatar.basis*seat_deltas[side]*float(state.root_progress)
   if state.finished:
    var exiting:bool=state.kind=="exit"
    assert(player.finish_seated_transition())
    if exiting:player.play_vrma("uma_cheval_idle",1,true)
  if f>=120 and f<420:
   avatar.position+=velocity/60.0
   player.set_scene_locomotion_sample(velocity,velocity/60.0,heading,true)
  var center:Vector3=avatar.position+Vector3(0,.9*avatar.scale.y,0)
  cameras[side].position=center+Vector3(2.5,1.2,3.3);cameras[side].look_at(center)
 for side in 2:
  input_directions[side]={}
  var secondary=avatars[side].spring_contacts.secondary
  secondary.update_centers(avatars[side].skeleton.global_transform)
  for si in secondary.spring_bones_internal.size():
   var state=secondary.spring_bones_internal[si]
   if not "Mantle" in state.joint_nodes[0]:continue
   var xf:Transform3D=secondary.center_transforms[secondary.springs_centers[si]]
   for joint in state.verlets:
    var name:String=avatars[side].skeleton.get_bone_name(joint.bone_idx)
    input_directions[side][name]=(xf.basis*avatars[side].skeleton.get_bone_global_pose(joint.bone_idx).basis*joint.bone_axis).normalized()
 if frame in [0,720]:
  for avatar in avatars:avatar.rebase_secondary_physics()
 var err:=source_error();max_source_error=maxf(max_source_error,err)
 var worlderr:float=avatars[0].global_position.distance_to(avatars[1].global_position)
 for axis in 3:worlderr=maxf(worlderr,avatars[0].global_basis[axis].distance_to(avatars[1].global_basis[axis]))
 max_world_error=maxf(max_world_error,worlderr)
 capture_mesh=f%2==0
 overlay.text="Production springs                 |                 Candidate 1.2    %s %.2fs"%[phase,t]
 frame_inputs={"source_error":err,"world_error":worlderr}

func capture_draw()->void:
 if not started or frame<0 or frame==draw_last_frame:return
 draw_last_frame=frame
 var f:=frame
 var err:float=frame_inputs.get("source_error",INF)
 var worlderr:float=frame_inputs.get("world_error",INF)
 if f%2==0:
  if not captures[0].is_empty() and not captures[1].is_empty() and captures[0].frame==f and captures[1].frame==f and captures[0].generation==generation and captures[1].generation==generation:
   meshes.append({"frame":f,"generation":generation,"phase":phase,"source_error":err,"world_error":worlderr,"baseline_yaw":avatars[0].rotation.y,"candidate_yaw":avatars[1].rotation.y,"baseline_callback":captures[0].callback,"candidate_callback":captures[1].callback,"comparison":compare_mesh(captures[0].mesh,captures[1].mesh)})
  root.get_texture().get_image().save_png(output.path_join("frame-%04d.png"%(f/2)))
 if frame>=1319:finish_run()

func finish_run()->void:
 started=false
 parameter_endpoints.append({"at":"final","generation":generation,"baseline":params(avatars[0]),"candidate":params(avatars[1])})
 var report:={"source_start":source_start,"source_end":hashes(),"modifier_observations":modifier_observations,"parameter_endpoints":parameter_endpoints,"max_world_transform_error":max_world_error,"scope":"automatic MotionPlayer at priority-10 with scripted host drivers before/after; shared events; automatic idle selection disabled, authored idle retained; own-world twin viewports same-origin/identical transforms; real modifier callbacks; cape-only sparse triangles every17th; model reload same asset with translated/scaled placement; actual seated transition layer and .45m floorclearance, source rootdelta applied by diagnostic host, no chair/backrest and no host/window acceptance","player_priorities":players.map(func(p):return p.process_priority),"frames":1320,"fps":60,"capture_fps":30,"counts":counts,"max_prephysics_humanoid_pose_error":max_source_error,"parameters":parameter_checks,"callbacks":rows,"mesh_samples":meshes}
 FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("CONTINUOUS_CALLBACKS ",counts," SOURCE_ERROR ",max_source_error);quit()
