extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func run():
	var parts:Array=[]
	for type in ["computer","chair"]:
		var scene:=DesktopObjectContactScene.new();root.add_child(scene);scene.configure(type)
		scene.transform=Transform3D(Basis(Vector3.UP,deg_to_rad(scene.recommended_yaw_degrees)).scaled(Vector3.ONE*.5437),Vector3(1.55 if type=="computer" else 1.0,-1.33028,-.38875 if type=="computer" else -.1))
		var current:Array=[];DesktopObjectsHost._append_scene_solids(scene,current);parts.append_array(current)
		print("RAW_PARTS ",type," ",current.size());scene.free()
	var nav:=DesktopSceneNavigation.new();var result:=nav.configure(Rect2(-1,-2,5,4),-1.33028,parts,.072,1,.06)
	print("UNION_RESULT ",result," ",nav.diagnostics)
	if not result.get("ok",false):failures+=1
	if result.get("ok",false):
		var originals:Array[Rect2]=[]
		for box:AABB in parts:
			if box.end.y<=-1.33028 or box.position.y>=-.33028:continue
			var rect:=Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(.072)
			originals.append(rect)
			if not nav._obstacles.any(func(outer):return outer.encloses(rect)):failures+=1
		for outer in nav._obstacles:
			if outer not in originals:failures+=1
		print("Exact union: every original rectangle covered; every retained rectangle original")
	var dense:Array=[]
	for i in 97:dense.append(AABB(Vector3((i%10)*.2,0,(i/10)*.2),Vector3(.01,1,.01)))
	var rejected:=nav.configure(Rect2(-1,-1,5,5),0,dense,0,1,.1)
	if rejected.get("ok",true) or rejected.get("reason","")!="too_many_effective_obstacles":failures+=1
	print("Dense disjoint rejection ",rejected)
	var excessive:Array=[];excessive.resize(2049)
	var raw_rejected:=nav.configure(Rect2(-1,-1,5,5),0,excessive,0,1,.1)
	if raw_rejected.get("ok",true) or raw_rejected.get("reason","")!="invalid_geometry":failures+=1
	nav.dispose();print("Obstacle union failures=",failures);quit(1 if failures else 0)
