extends SceneTree
const Furniture = preload("res://scripts/desktop_object_window.gd")
const Store = preload("res://scripts/desktop_object_store.gd")
const Appearance = preload("res://scripts/desktop_object_appearance.gd")
const Scene = preload("res://scripts/desktop_object_contact_scene.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error(label)
func run():
	for type in ["chair","sofa","computer"]:
		var window := Furniture.new()
		root.add_child(window)
		var record={"id":"obj_1","type":type,"label":type,"x":-1000,"y":200,"yaw_deg":0.0,"appearance":"default"}
		check(window.configure(record,Store.base_size(type)),type+" loads")
		var reference_ppm := window.pixels_per_metre()
		for yaw in [0.0,60.0,180.0]:
			window.set_view_basis(DesktopView.orbit_basis(yaw,20.0))
			for object_yaw in [-90.0,45.0,120.0]:
				record.yaw_deg=object_yaw
				record.appearance="cool"
				window.apply_record(record,Store.base_size(type))
				var safe:=true
				for point in window._geometry_points:
					var pixel:Vector2=window._camera.unproject_position(point)
					if not Rect2(Vector2.ZERO,Vector2(window.size)).grow(.1).has_point(pixel):safe=false
				check(absf(window.pixels_per_metre()-reference_ppm)<.001,"camera/object yaw preserves exact physical PPM")
				check(safe and window.pixels_per_metre()>1,type+" remains fully framed under camera/object yaw")
		for zoom in [.6,1.6]:
			window.set_projection_zoom(zoom)
			check(absf(window.pixels_per_metre()-reference_ppm*zoom)<.001,"zoom alone scales physical PPM linearly")
		window.free()
	var scene:=Scene.new();root.add_child(scene);scene.configure("chair")
	var mesh=scene.find_children("*","MeshInstance3D",true,false)[0]
	var original=mesh.get_active_material(0)
	Appearance.apply(scene,"warm");var warm=mesh.get_active_material(0)
	Appearance.apply(scene,"cool");Appearance.apply(scene,"warm")
	check(warm.albedo_color==mesh.get_active_material(0).albedo_color,"preset switching never accumulates tint")
	Appearance.apply(scene,"default")
	check(mesh.get_active_material(0)==original,"default restores original authored material identity")
	check(not Appearance.apply(scene,"shader_code"),"arbitrary shader preset rejected")
	scene.free()
	var autonomy:=DesktopAutonomy.new();root.add_child(autonomy)
	autonomy.configure_simulation([Rect2(0,0,1920,1040)],Vector2(400,700),Rect2(0,0,200,300))
	autonomy.set_surface_mode(true)
	autonomy.contact_pose="sit";autonomy._seat_contact_owner="object:obj_1:seat"
	autonomy._support={"id":"object:obj_1:seat","anchor_only":true}
	check(autonomy.refresh_seat_projection("object:obj_1:seat",Vector2(500,850),{"sit":Vector2(100,150)},Rect2(0,0,200,300)),"owned seat may reproject without OS travel")
	check(autonomy.position==Vector2(400,700),"view refresh does not move desktop origin")
	check(not autonomy.refresh_seat_projection("object:other:seat",Vector2(500,850),{"sit":Vector2(100,150)},Rect2(0,0,200,300)),"view API cannot steal another support")
	check(not autonomy.refresh_seat_projection("object:obj_1:seat",Vector2(500,850),{"sit":Vector2(100,150)},Rect2(0,0,200,400)),"view API rejects full-body workarea overflow")
	autonomy.free()
	print("Object view: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
