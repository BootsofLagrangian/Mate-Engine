extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var main_size := root.size
	var wrapper = load("res://scripts/companion_panel_window.gd").new()
	root.add_child(wrapper)
	var panel := ControlPanel.new()
	# Linux diagnostic has no installed Korean font; use the existing Windows
	# system font read-only for this preview, never copy it into the application.
	if FileAccess.file_exists("/mnt/c/Windows/Fonts/malgun.ttf"):
		var font := FontFile.new()
		font.load_dynamic_font("/mnt/c/Windows/Fonts/malgun.ttf")
		var panel_theme := Theme.new()
		panel_theme.default_font = font
		panel.theme = panel_theme
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(0)
	var pet := Rect2i(usable.position+Vector2i(usable.size.x/2,usable.size.y/2),Vector2i(220,330))
	wrapper.configure(panel,pet,usable)
	wrapper.open_next_to(pet,usable)
	panel._tabs.current_tab = 3
	panel.set_view_settings({"view_yaw_deg":35.0,"view_pitch_deg":45.0,"view_height":.12,"view_zoom":1.1})
	for i in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../diagnostics/panel_window/native-view-tab.png")
	wrapper.get_texture().get_image().save_png(output)
	print("PANEL_RENDER ",output," window_id=",wrapper.get_window_id()," embedded=",wrapper.is_embedded()," bounds=",Rect2i(wrapper.position,wrapper.size)," avatar_viewport_unchanged=",root.size==main_size)
	panel.set_view_settings({"view_projection":"perspective","view_fov_deg":55.0,"view_distance_m":4.2})
	for i in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var perspective_output := ProjectSettings.globalize_path("res://../diagnostics/panel_window/native-view-perspective-tab.png")
	wrapper.get_texture().get_image().save_png(perspective_output)
	print("PANEL_RENDER ", perspective_output, " camera_controls=", panel.view_settings())
	wrapper.close_panel()
	wrapper.free()
	quit()
