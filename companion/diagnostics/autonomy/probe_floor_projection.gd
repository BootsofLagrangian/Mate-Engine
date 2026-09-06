extends SceneTree
## Real VRM + actual main framing/projection, no OS movement or GPU rendering.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func run() -> void:
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/main.gd"\nvar test_clock := 0.0\nfunc _ready() -> void:\n\tset_process(false)\nfunc _now() -> float:\n\treturn test_clock\n'
	if script.reload() != OK:
		quit(1)
		return
	for name in ["cheval-grand", "rice-shower", "eishin-flash"]:
		var host = script.new()
		var viewport := SubViewport.new()
		viewport.size = Vector2i(680, 760)
		root.add_child(viewport)
		viewport.add_child(host)
		host.camera = Camera3D.new()
		host.camera.fov = 28.0
		host.add_child(host.camera)
		host.camera.current = true
		host.avatar = VrmAvatar.new()
		host.add_child(host.avatar)
		if not host.avatar.load_from_file(ProjectSettings.globalize_path("res://../assets/" + name + ".vrm")):
			check(false, "rig failed to load: " + name)
			viewport.free()
			continue
		for scale in [0.35, 0.6, 1.25]:
			for yaw in [-82.0, 0.0, 82.0]:
				host._pet_scale = scale
				host._pet_scale_target = scale
				host._frame_avatar()
				host.avatar.rotation.y = deg_to_rad(yaw)
				host._update_avatar_transform(0.0)
				host._update_pet_rect()
				var anchors: Dictionary = host._projected_anchors()
				var label := "%s scale%.2f yaw%.0f" % [name, scale, yaw]
				check(absf(host.pet_rect.end.y - Vector2(anchors.foot).y) < 0.05, label + " true sole and body bounds agree")
				var autonomy := DesktopAutonomy.new()
				host.autonomy = autonomy
				var areas: Array[Rect2] = [Rect2(0, 0, 2560, 1392)]
				autonomy.configure_simulation(areas, Vector2(100, 610), host.pet_rect)
				autonomy.set_surface_mode(true)
				autonomy.update_context(false, false, false, false, false)
				autonomy.locomotion_changed.connect(func(moving: bool, _velocity: Vector2): host._floating = moving)
				var world := {"monitors": [{"id": "floor", "x": 0, "y": 0, "width": 2560, "height": 1392}], "windows": []}
				var attached_frames := 0
				var unsafe_frames := 0
				for i in 1200:
					host.test_clock += 1.0 / 60.0
					host._update_avatar_transform(1.0 / 60.0)
					host._update_pet_rect()
					host._keep_pet_in_window()
					host._floating = true # surface mode must suppress any requested decoration
					host._update_float(1.0 / 60.0)
					autonomy.set_visible_bounds(host.pet_rect)
					autonomy.set_contact_anchors(host._projected_anchors())
					autonomy.set_world_snapshot(world)
					autonomy.advance(1.0 / 60.0)
					if not autonomy.is_origin_safe(autonomy.position):
						unsafe_frames += 1
					if autonomy.get_support_contact().get("attached", false):
						attached_frames += 1
						if attached_frames >= 120:
							break
				var contact := autonomy.get_support_contact()
				check(attached_frames >= 120, label + " floor remains attached for120frames")
				check(unsafe_frames == 0, label + " workarea safety retained")
				check(host.camera.position.is_equal_approx(host._camera_base) and host._float_blend == 0.0, label + " surface camera bob disabled")
				check(bool(contact.get("attached", false)) and absf((autonomy.position + Vector2(host._projected_anchors().foot)).y - 1392.0) < 0.1, label + " visible sole aligns with floor")
				autonomy.free()
				host.autonomy = null
		viewport.free()
	print("Floor projection: %d checks, %d failures (3 rigs x3scales x3yaws)" % [checks, failures])
	quit(0 if failures == 0 and checks == 135 else 1)
