extends SceneTree
## Actual three VRMs and main projection, with deterministic yaw and simulated desktop floor.
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/main.gd"\nfunc _ready() -> void:\n\tset_process(false)\n'
	if script.reload() != OK: quit(1); return
	for name in ["cheval-grand","rice-shower","eishin-flash"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(680,760)
		root.add_child(viewport)
		var host = script.new()
		viewport.add_child(host)
		host.camera = Camera3D.new()
		host.add_child(host.camera)
		host.camera.current = true
		host.avatar = VrmAvatar.new()
		host.add_child(host.avatar)
		if not host.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/"+name+".vrm")):
			check(false,"model load "+name); viewport.free(); continue
		for scale in [0.6,1.0,1.25]:
			for fps in [30,60]:
				var dt := 1.0/float(fps)
				host._pet_scale = scale
				host._pet_scale_target = scale
				host._frame_avatar()
				host.avatar.rotation.y = deg_to_rad(82)
				for i in 180:
					host._update_avatar_transform(dt)
					host._update_pet_rect()
					host._keep_pet_in_window()
				var anchor: Vector2 = host._projected_anchors().foot
				var a := DesktopAutonomy.new()
				host.autonomy = a
				a.configure_simulation([Rect2(0,0,2560,1400)],Vector2(660,1400-anchor.y),host._navigation_rect())
				a.set_contact_anchors(host._projected_anchors())
				a.set_surface_mode(true)
				a.set_external_decisions(true)
				a.update_context(false,false,false,false,false)
				for i in 180: a.advance(dt)
				var label := "%s scale%.2f fps%d" % [name,scale,fps]
				check(a.get_support_contact().get("attached",false),label+" begins attached")
				var max_drift := 0.0
				var detached := 0
				var unsafe := 0
				for i in fps*3:
					host.avatar.rotation.y = deg_to_rad(lerpf(82,-82,minf(float(i)*dt/2.4,1)))
					host._update_avatar_transform(dt)
					host._update_pet_rect()
					host._keep_pet_in_window()
					max_drift = maxf(max_drift,Vector2(host._projected_anchors().foot).distance_to(anchor))
					a.set_visible_bounds(host._navigation_rect())
					a.set_contact_anchors(host._projected_anchors())
					a.advance(dt)
					if not a.get_support_contact().get("attached",false): detached += 1
					if not a.is_origin_safe(a.position): unsafe += 1
				print("TURN_SUPPORT ",label," anchor_drift=",max_drift," detached=",detached," unsafe=",unsafe," envelope_width=",host._navigation_rect().size.x)
				check(max_drift < 0.1,label+" yaw cannot move stable window-local foot anchor")
				check(detached == 0 and unsafe == 0,label+" yaw retains safe support")
				a.free()
				host.autonomy = null
		viewport.free()
	print("Turn support: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
