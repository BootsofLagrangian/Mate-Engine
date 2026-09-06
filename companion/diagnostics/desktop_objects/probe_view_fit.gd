extends "test_host_objects.gd"
func _run():
	host_script=GDScript.new()
	host_script.source_code='extends "res://scripts/main.gd"\nfunc _ready():\n\tset_process(false)\nfunc _update_passthrough(_force):\n\tpass\nfunc _save_window_position():\n\tpass\n'
	if host_script.reload()!=OK:quit(1);return
	var h=fixture()
	h.avatar.present=true
	h.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm"))
	h.camera=Camera3D.new();h.add_child(h.camera);h.camera.current=true
	root.size=Vector2i(680,760)
	var panel=h.panel;h.panel=null
	h._pet_scale=.6
	h._frame_avatar()
	h.motion.avatar=h.avatar
	h.motion.load_vrma("sit_idle",ProjectSettings.globalize_path("res://../assets/motions/sit_idle.vrma"))
	var scene=DesktopObjectsHost.ContactScene.new();h.add_child(scene);scene.configure("chair")
	var w=DesktopObjectWindow.new();h.add_child(w)
	var record={"id":"obj_1","type":"chair","label":"chair","scale":.8,"yaw_deg":45.0,"appearance":"cool","x":824,"y":1152,"visible":true}
	w.configure(record,Vector2i(208,240));w.set_view_basis(Basis.IDENTITY)
	h.objects.store.set_data({"version":1,"objects":[record]})
	h.objects._screen_provider=func():return [Rect2i(0,0,2560,1392)]
	h.objects._contact_scene=scene;h.objects._contact_id="obj_1"
	h.objects._contact_scale=w.pixels_per_metre()/h._px_per_m
	h.motion.set_seated_floor(.48*h.objects._contact_scale/.6)
	h._ensure_seated_geometry()
	h._sit_active=true;h._pivot_kind="sit"
	h._pivot_px=Vector2(337.8991,563.1867);h._pivot_px_target=h._pivot_px
	h.get_window().position=Vector2i(598,729)
	h.avatar.rotation.y=deg_to_rad(45)
	h._update_avatar_transform(0)
	for yaw in [0.0,45.0]:
		var basis=DesktopView.orbit_basis(yaw,yaw)
		h.camera.transform=Transform3D(basis,basis*Vector3(-.537937,1.027519,4.605996))
		h._camera_base=h.camera.position;h._camera_pivot_depth=4.605996
		h._update_avatar_transform(0);h._update_pet_rect()
		var object_basis=Basis(Vector3.UP,deg_to_rad(45)).scaled(Vector3.ONE*h.objects._contact_scale)
		var anchor=h.avatar.contact_anchors().sit
		var ground=Vector3(0,scene.get_local_bounds().position.y,0)
		var floor_world=anchor-object_basis*(scene.socket_local("seat")-ground)
		h.objects._contact_floor=Vector2(h.get_window().position)+h.camera.unproject_position(floor_world)
		h.objects._update_contact_transform()
		var nav=h._navigation_rect();var prop=h.objects.contact_bounds();var full=nav.merge(prop)
		print("view=",yaw," ppm=",h._px_per_m," object_scale=",h.objects._contact_scale," local_nav=",nav," local_prop=",prop," full=",full," global_prop=",Rect2(prop.position+Vector2(h.get_window().position),prop.size)," full_global=",Rect2(full.position+Vector2(h.get_window().position),full.size))
		if yaw == 45.0:
			h.autonomy.set_workareas([Rect2(0,0,2560,1392)])
			h.autonomy.position=Vector2(h.get_window().position)
			h.autonomy.contact_pose="sit"
			h.autonomy._seat_contact_owner="object:obj_1:seat"
			h.autonomy._support={"id":"object:obj_1:seat","kind":"object_seat","anchor_only":true}
			var before_origin:Vector2i=h.get_window().position
			var before_anchor:Vector2=h.camera.unproject_position(h.avatar.contact_anchors().sit)
			check(h.objects._fit_contact_view(true),"actual rotated Cheval/chair assembly fits after minimum nudge")
			check(h.get_window().position-before_origin==Vector2i(0,-53),"measured 52.59-pixel overflow uses exactly 53-pixel upward correction")
			check(h.camera.unproject_position(h.avatar.contact_anchors().sit).distance_to(before_anchor)<.001,"physical nudge preserves local avatar pose and camera projection")
			var seat:Vector2=h.objects.contact_socket_screen("seat")
			var pelvis:Vector2=Vector2(h.get_window().position)+h.camera.unproject_position(h.avatar.contact_anchors().sit)
			check(seat.distance_to(pelvis)<.001,"actual shared 3D seat remains coincident after assembly translation")
			check(h.autonomy.refresh_seat_projection("object:obj_1:seat",seat,h._projected_anchors(),h._navigation_rect()),"same owned seat reprojects within unchanged full-body safety bounds")
			var full_after:Rect2=h.objects.occupied_rect();full_after.position+=Vector2(h.get_window().position)
			check(Rect2(0,0,2560,1392).encloses(full_after),"full actual pet and furniture envelope is inside usable workarea")
			check(h.objects._fit_contact_view(true) and h.get_window().position==before_origin+Vector2i(0,-53),"repeated fit does not accumulate physical movement")
			print("fit_after=",h.objects.fit_diagnostics.view)
	check(DesktopObjectsHost._minimal_assembly_nudge(Rect2(-1905,-20,300,200),[Rect2(-1920,0,1920,1040)])==Vector2i(0,20),"negative-origin workarea receives minimal inward nudge")
	check(DesktopObjectsHost._minimal_assembly_nudge(Rect2(0,0,2000,100),[Rect2(0,0,1920,1040)])==null,"oversized geometry remains rejected")
	check(DesktopObjectsHost._minimal_assembly_nudge(Rect2(0,0,200,100),[Rect2(3000,0,1920,1040)])==null,"view fitting never jumps to a disconnected monitor")
	h.panel=panel;h.objects.shutdown();h.objects._contact_scene=null;scene.free();w.free();h.free()
	print("Occupied view fit: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
