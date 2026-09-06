extends SceneTree
var geometry:=ProjectedAvatarGeometry.new()
var camera:Camera3D
var failures:=0
const AREAS:=[Rect2(0,0,2560,1392),Rect2(2560,0,1920,1032)]
func _init()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 print("CHECK ",label," ",value)
 if not value:failures+=1
func query(point:Vector3)->Dictionary:
 return geometry.nearest_safe_ground(camera,point,.6,Vector2(940,316),AREAS,.25)
func run()->void:
 root.size=Vector2i(680,760)
 camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(-.698495,1.334204,3.6);camera.fov=45;camera.near=.05;camera.far=50
 var avatar:=VrmAvatar.new();root.add_child(avatar)
 avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"));avatar.set_process(false)
 geometry.capture(avatar,avatar.contact_anchors().foot)
 var failed:=Vector3(3.701519,-1.314583,-.030323)
 var target:=Vector3(3.954308,-1.314583,-.25213)
 var result:=DesktopSceneNavigationHost.route_view_admission(PackedVector3Array([failed,target]),query,AREAS)
 check(not result.accepted,"recorded route rejects before travel")
 var inward:=PackedVector3Array([failed-Vector3(1,0,0),target-Vector3(1,0,0)])
 check(DesktopSceneNavigationHost.route_view_admission(inward,query,AREAS).accepted,"same ground inward route admitted")
 var unchanged:=avatar.global_transform
 DesktopSceneNavigationHost.route_view_admission(inward,query,AREAS)
 check(avatar.global_transform==unchanged,"view preflight never moves actor")
 var endpoints:=func(point:Vector3)->Dictionary:return {"ok":true,"changed":false,"bounds":Rect2(point.x,0,1,1)}
 check(not DesktopSceneNavigationHost.route_view_admission(PackedVector3Array([Vector3(0,0,0),Vector3(20,0,0)]),endpoints,[Rect2(0,0,5,5),Rect2(20,0,5,5)]).accepted,"endpoint-only monitor gap cannot pass segment admission")
 check(not DesktopSceneNavigationHost.route_view_admission(PackedVector3Array(),query,AREAS).accepted,"empty route fails closed")
 print("APPROACH_ROUTE_VIEW 5 checks ",failures," failures")
 avatar.free();camera.free();quit(1 if failures else 0)
