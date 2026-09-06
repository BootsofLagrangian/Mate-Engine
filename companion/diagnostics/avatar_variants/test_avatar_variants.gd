extends SceneTree
class FakeClient extends BackendClient:
	var requests := []
	var messages := []
	func fetch_avatar(id: String,url: String,force: bool = false,variant: String = "default") -> void:
		requests.append({"id":id,"url":url,"force":force,"variant":variant})
	func send(event: Dictionary) -> bool:
		messages.append(event.duplicate(true)); return true
class FakeAudio extends AudioOutput:
	func cancel() -> void: pass
class FakeAvatar extends VrmAvatar:
	var load_ok := true
	var loads := []
	func load_from_file(path: String) -> bool:
		loads.append(path); return load_ok
class FakeContact extends Node:
	var calls := []
	func cancel_commands(reason: String) -> void: calls.append("commands:"+reason)
	func cancel_interaction(reason: String) -> void: calls.append("contact:"+reason)
class FakeLiving extends Node:
	var calls := []
	func cancel(reason: String) -> void: calls.append(reason)
	func publish_world(_force: bool = false) -> void: calls.append("publish")
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed += 1
	else: failed += 1; print("FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var settings = root.get_node("Settings")
	var saved: Dictionary = settings.data.duplicate(true)
	settings.data["avatar_variant_choices"] = {}
	var panel := ControlPanel.new(); root.add_child(panel)
	var entries := [{"id":"default","label":"Default","avatar_available":true,"avatar_url":"/characters/hachimi/avatar"},
		{"id":"wet","label":"젖은 외형","description":"비 오는 날","mood_tags":["rainy"],"avatar_available":true,"avatar_url":"/characters/hachimi/avatar?variant=wet"},
		{"id":"missing","label":"미설치","avatar_available":false}]
	var changed := []
	panel.avatar_variant_selected.connect(func(id: String): changed.append(id))
	panel.set_avatar_variants(entries,"wet")
	check(changed.is_empty() and panel._avatar_variant_option.selected == 1,"host sync silent")
	check(panel._avatar_variant_option.is_item_disabled(2),"missing asset disabled")
	check(panel._avatar_variant_note.text.contains("rainy"),"mood description visible")
	panel._avatar_variant_option.select(0); panel._avatar_variant_option.item_selected.emit(0)
	check(changed == ["default"],"manual selection emits catalogue id")
	check(BackendClient.avatar_cache_path("hachimi") == "user://avatars/hachimi.vrm","legacy default cache retained")
	check(BackendClient.avatar_cache_path("hachimi","wet") != BackendClient.avatar_cache_path("hachimi"),"variant cache separate")
	check(BackendClient.avatar_cache_path("a","b/c") != BackendClient.avatar_cache_path("a","b_c"),"variant punctuation cannot collide")
	check(BackendClient.avatar_cache_path("a","wet") != BackendClient.avatar_cache_path("b","wet"),"character cache isolated")
	check(BackendClient.avatar_variant_url("hachimi","wet") == "/characters/hachimi/avatar?variant=wet","HTTP variant query")
	check(BackendClient.avatar_variant_url("a b","wet rain").contains("a%20b/avatar?variant=wet%20rain"),"URL identifiers encoded")
	panel.set_vrma_clips({"sit_enter":{"seated_transition":"enter"},"sit_exit":{"seated_transition":"exit"},"sit_idle":{},"styled_walk":{"locomotion_style":{"speed":1.0}},"ordinary_wave":{"duration":1.0}})
	check(not panel.preset_names().has("sit_enter") and not panel.preset_names().has("sit_exit") and not panel.preset_names().has("sit_idle") and not panel.preset_names().has("styled_walk"),"contact/travel-only clips absent from ordinary preview")
	check(panel.vrma_clips.has("sit_enter") and panel.preset_names().has("ordinary_wave"),"context clips remain loaded while ordinary gesture remains selectable")
	var host = load("res://../diagnostics/avatar_variants/host_fixture.gd").new()
	host.panel = panel; host.loading_label = Label.new(); host.client = FakeClient.new(); host.client.state = "open"
	host.avatar = FakeAvatar.new(); host.motion = MotionPlayer.new(); host.objects = FakeContact.new(); host.living = FakeLiving.new()
	host.session.characters = [{"id":"hachimi","name":"Hachimi","avatar_variants":entries}]
	host.session.character_id = "hachimi"; host.session.turn_id = "keep-turn"; host.session.text = "keep conversation"
	var result: Dictionary = host.request_avatar_variant("missing","reject:intent","llm")
	check(not result.accepted and result.feedback_sent and host.client.requests.is_empty(),"missing rejected before download")
	check(host.client.messages[-1].outcome == "rejected","missing terminal rejected feedback")
	result = host.request_avatar_variant("wet","turn:intent","llm")
	check(result.accepted and host.client.requests.size() == 1 and host.client.requests[0].variant == "wet","valid request downloads requested variant")
	check(host.objects.calls.size() >= 2 and host.stand_calls > 0,"contact and pose cleared before request")
	check(host.avatar_variant_outcomes.size() == 1,"accepted download not falsely completed")
	check(host.request_avatar_variant("wet","turn:intent","llm").reason == "duplicate" and host.client.requests.size() == 1,"action/done duplicate does not redownload")
	host.request_avatar_variant("default","next:intent","llm")
	check(host.avatar_variant_outcomes[-1].id == "turn:intent" and host.avatar_variant_outcomes[-1].outcome == "cancelled","superseded request cancelled")
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi","wet"),"stale")
	check(host._pending_avatar_path.is_empty(),"stale different variant callback ignored")
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi"),"downloaded")
	await process_frame
	check(host.frame_calls == 1 and host.avatar.loads.size() == 1,"completion runs actual load path then frame")
	check(host.avatar_variant_outcomes[-1].id == "next:intent" and host.avatar_variant_outcomes[-1].outcome == "completed","completion after successful load")
	check(host.session.character_id == "hachimi" and host.session.turn_id == "keep-turn" and host.session.text == "keep conversation","same character session and conversation preserved")
	host.request_avatar_variant("wet","badload:intent","llm")
	host.avatar.load_ok = false
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi","wet"),"downloaded")
	await process_frame
	check(host.avatar_variant_outcomes[-1].outcome == "failed" and host.active_avatar_variant() == "default","load failure keeps saved variant and fails request")
	host.request_avatar_variant("wet","cancel:intent","llm")
	var generation: int = host.client._avatar_generation
	host.cancel_avatar_variant("cancel:intent")
	check(host.client._avatar_generation > generation and host._avatar_variant_command.is_empty(),"cancel invalidates inflight generation")
	host.audio = FakeAudio.new()
	host.avatar.load_ok = true
	host.request_avatar_variant("wet","stoprace:intent","llm")
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi","wet"),"downloaded")
	var loads_before: int = host.avatar.loads.size()
	host._cancel_current()
	await process_frame
	check(host.avatar.loads.size() == loads_before and host._avatar_variant_command.is_empty(),"local stop cancels queued avatar apply")
	host.request_avatar_variant("wet","refresh:intent","llm")
	host._on_characters_loaded(true,host.session.characters.duplicate(true),"catalogue refreshed")
	check(host._avatar_loading_variant == "wet" and host.client.requests[-1].variant == "wet","catalogue refresh preserves pending requested variant")
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi"),"wrong default")
	await process_frame
	check(not host._avatar_variant_command.is_empty(),"wrong default cannot complete pending wet command")
	host._on_avatar_ready(true,"hachimi",BackendClient.avatar_cache_path("hachimi","wet"),"correct wet")
	await process_frame
	check(host.avatar_variant_outcomes[-1].id == "refresh:intent" and host.avatar_variant_outcomes[-1].outcome == "completed" and host.active_avatar_variant() == "wet","correct refreshed variant loads and completes")
	host.autonomy = DesktopAutonomy.new()
	var living = load("res://scripts/living_behavior.gd").new()
	living.host = host
	for reason in ["disabled","disconnected"]:
		host.request_avatar_variant("default",reason+":intent","llm")
		living.cancel(reason)
		check(host._avatar_variant_command.is_empty() and host.avatar_variant_outcomes[-1].outcome in ["cancelled","interrupted"],reason+" cancels appearance transaction")
	host.request_avatar_variant("default","selfcleanup:intent","llm")
	living.cancel("avatar_changed")
	check(not host._avatar_variant_command.is_empty(),"internal contact cleanup does not self-cancel appearance")
	host.cancel_avatar_variant()
	living.free(); host.autonomy.free(); host.audio.free()
	host.loading_label.free(); host.client.free(); host.avatar.free(); host.motion.free(); host.objects.free(); host.living.free(); host.free(); panel.free()
	settings.data = saved; settings.save_now()
	print("AVATAR_VARIANTS ",passed," passed ",failed," failed")
	quit(1 if failed else 0)
