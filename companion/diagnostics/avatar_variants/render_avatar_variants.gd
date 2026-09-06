extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var wrapper = load("res://scripts/companion_panel_window.gd").new()
	root.add_child(wrapper)
	var panel := ControlPanel.new()
	if FileAccess.file_exists("/mnt/c/Windows/Fonts/malgun.ttf"):
		var font := FontFile.new(); font.load_dynamic_font("/mnt/c/Windows/Fonts/malgun.ttf")
		var theme := Theme.new(); theme.default_font = font; panel.theme = theme
	var area := DisplayServer.screen_get_usable_rect(0)
	wrapper.configure(panel,Rect2i(area.position+Vector2i(800,200),Vector2i(220,330)),area)
	wrapper.open_next_to(Rect2i(area.position+Vector2i(800,200),Vector2i(220,330)),area)
	panel.set_characters([{"id":"hachimi","name":"하치미"}],"hachimi")
	panel.set_avatar_variants([{"id":"default","label":"평소 외형","avatar_available":true,"description":"평소의 깔끔한 외형입니다.","mood_tags":["편안함"]},{"id":"wet","label":"젖은 외형","avatar_available":true,"description":"비에 젖은 외형입니다.","mood_tags":["비 오는 날"]}],"default")
	for i in 5: await process_frame; await RenderingServer.frame_post_draw
	wrapper.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../diagnostics/avatar_variants/native-avatar-variants.png"))
	wrapper.free(); quit()
