extends SceneTree
func _initialize():
	var checks:=0
	for yaw in [-170.0,-90.0,0.0,35.0,90.0,180.0]:
		for scale in [.35,.6,1.0]:
			var basis:=Basis(Vector3.UP,deg_to_rad(yaw)).scaled(Vector3.ONE*scale)
			var seat:=Vector3(1.1,.48,-2.0)
			var offset:=Vector3(.01,.80,.04)
			var source:=Vector3(.015,-.30,-.314)
			var stage:=DesktopObjectsHost.authored_staging_foot(seat,basis,offset,source,.02)
			var current_seat:=stage+basis*offset
			var actual_delta:=basis.inverse()*(seat-current_seat)
			assert(absf(actual_delta.x-source.x)<.00001 and absf(actual_delta.z-source.z)<.00001)
			assert(absf(stage.y-.02)<.000001)
			checks+=2
	assert(not DesktopObjectsHost.authored_staging_foot(Vector3.INF,Basis.IDENTITY,Vector3.ZERO,Vector3.ZERO,0).is_finite());checks+=1
	print("Scene authored staging: %d checks, 0 failures"%checks)
	quit()
