extends SceneTree
const View = preload("res://scripts/desktop_view.gd")
var failures: Array = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(680,760)
	root.transparent_bg=true
	if "--no-msaa" in OS.get_cmdline_user_args(): root.msaa_3d=Viewport.MSAA_DISABLED
	RenderingServer.set_default_clear_color(Color(0,0,0,0))
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,28,0);sun.light_energy=.85;root.add_child(sun)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_CLEAR_COLOR;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;root.add_child(env)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,.65,3);camera.current=true
	View.configure_projection(camera,"orthographic" if "--orthographic" in OS.get_cmdline_user_args() else "perspective",2.2,35)
	for i in 2:
		var packed:PackedScene=load("res://assets/desktop_objects/premium/chair.glb")
		var model:Node3D=packed.instantiate();root.add_child(model)
		model.position=Vector3(-.12 if i==0 else .12,0,-.35 if i==0 else .15)
		for mesh in model.find_children("*","MeshInstance3D",true,false):
			var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color(.9,.12,.05) if i==0 else Color(.04,.2,.9)
			mesh.material_override=mat
	var with_avatar := "--avatar" in OS.get_cmdline_user_args()
	if with_avatar:
		var avatar := VrmAvatar.new();root.add_child(avatar)
		if not avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/cheval-grand.vrm")): failures.append("avatar load")
		avatar.scale=Vector3.ONE*.65
		avatar.position=Vector3(0,0,.35)
		View.set_outline_reference_height(avatar,0.0 if "--orthographic" in OS.get_cmdline_user_args() else 760.0)
		if "--legacy-shader" in OS.get_cmdline_user_args() or "--inline-current" in OS.get_cmdline_user_args(): install_legacy_shader(avatar)
	var views:Array=[]
	var crops: Array[Rect2]=[Rect2(180,280,340,420),Rect2(220,260,340,420)]
	for crop in crops:
		var viewport:=SubViewport.new();viewport.size=Vector2i(crop.size);viewport.transparent_bg=true;viewport.world_3d=root.world_3d;viewport.msaa_3d=root.msaa_3d;viewport.screen_space_aa=root.screen_space_aa;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var child:=Camera3D.new();viewport.add_child(child);child.current=true
		if not View.configure_crop(child,camera,crop):failures.append("crop configure")
		views.append(viewport)
	for i in 6: await process_frame;await RenderingServer.frame_post_draw
	var output:=ProjectSettings.globalize_path("res://../logs/shared-world-avatar-render" if with_avatar else "res://../diagnostics/desktop_view/shared-world-render")
	if "--no-msaa" in OS.get_cmdline_user_args(): output += "-no-msaa"
	if "--orthographic" in OS.get_cmdline_user_args(): output += "-orthographic"
	if "--legacy-shader" in OS.get_cmdline_user_args(): output += "-legacy"
	if "--inline-current" in OS.get_cmdline_user_args(): output += "-inline-current"
	DirAccess.make_dir_recursive_absolute(output)
	var full:=root.get_texture().get_image();full.save_png(output+"/full.png")
	var count:=0;var mismatches:=0;var max_difference:=0.0;var blue_front:=0
	for i in views.size():
		var actual:Image=views[i].get_texture().get_image();actual.save_png(output+"/crop-%d.png"%i)
		for y in range(2,actual.get_height()-2):
			for x in range(2,actual.get_width()-2):
				var reference:=full.get_pixel(x+int(crops[i].position.x),y+int(crops[i].position.y))
				if reference.a<.999:continue
				var pixel:=actual.get_pixel(x,y)
				var difference:=maxf(absf(reference.r-pixel.r),maxf(absf(reference.g-pixel.g),absf(reference.b-pixel.b)))
				count+=1;max_difference=maxf(max_difference,difference)
				if difference>.015 or pixel.a<.999:mismatches+=1
				if reference.b>reference.r*2:blue_front+=1
	if count<1000 or blue_front<100:failures.append("insufficient opaque overlapping geometry")
	if mismatches>0:failures.append("opaque crop pixels differ from common world render")
	var report:={"opaque_samples":count,"mismatches":mismatches,"max_rgb_difference":max_difference,"front_blue_samples":blue_front,"failures":failures,"scope":"Actual intersecting imported chair meshes in one World3D, root and two off-axis crops. Linux renderer; native desktop alpha overdraw not covered."}
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(1 if failures else 0)

func install_legacy_shader(avatar: Node) -> void:
	var common:=FileAccess.get_file_as_string("res://addons/Godot-MToon-Shader/mtoon_common.gdshaderinc" if "--inline-current" in OS.get_cmdline_user_args() else "res://../logs/mtoon-outline-before-source.gdshaderinc")
	var seen:={}
	for mesh in avatar.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		for surface in mesh.mesh.get_surface_count():
			var material:Material=mesh.get_active_material(surface)
			while material!=null and not seen.has(material.get_instance_id()):
				seen[material.get_instance_id()]=true
				if material is ShaderMaterial and material.shader!=null:
					var original:String=material.shader.code
					if original.contains("mtoon_common.gdshaderinc"):
						var parameters:={}
						for uniform in material.shader.get_shader_uniform_list(): parameters[uniform.name]=material.get_shader_parameter(uniform.name)
						var shader:=Shader.new()
						shader.code=original.replace('#include "./mtoon_common.gdshaderinc"',common)
						material.shader=shader
						for name in parameters:
							if name!="_OutlineReferenceViewportHeight": material.set_shader_parameter(name,parameters[name])
				material=material.next_pass
