extends "res://tools/probe_host_lifecycle.gd"
## Actual main refresh/callback handlers; no network, assets, GPU or OS movement.
class RefreshClient extends Client:
	var fetched: Array = []
	func fetch_motion_asset(entry: Dictionary, _force: bool = false) -> void:
		fetched.append(entry.duplicate(true))
class RefreshPanel extends HostPanel:
	func set_vrma_clips(clips: Dictionary) -> void:
		vrma_clips = clips.duplicate(true)
	func set_motion_result(_text: String, _ok: bool) -> void:
		pass
class RefreshMotion extends Motion:
	func load_vrma(name: String, _path: String, contact_mode: String = "") -> bool:
		var clip := VrmaClip.new()
		clip.duration = 1.0
		vrma_clips[name] = clip
		vrma_contact_modes[name] = contact_mode
		return true
	func stop_gesture() -> void:
		stops += 1
		_vrma_name = ""
func _run() -> void:
	host_script = GDScript.new()
	host_script.source_code = 'extends "res://scripts/main.gd"\nfunc _ready() -> void:\n\tset_process(false)\nfunc _update_passthrough(_force: bool) -> void:\n\tpass\n'
	if host_script.reload() != OK: quit(1); return
	var host := make_host()
	host.client.free()
	host.client = RefreshClient.new()
	host.add_child(host.client)
	host.panel.free()
	host.panel = RefreshPanel.new()
	host.add_child(host.panel)
	host.motion.free()
	host.motion = RefreshMotion.new()
	host.add_child(host.motion)
	var declared: Dictionary = {"name":"custom_walk","locomotion":true,"locomotion_priority":50,"locomotion_preserve_hips":true,"loop":true}
	var entries: Array[Dictionary] = [declared]
	host._on_motion_assets_loaded(true, entries, "test")
	check(host.walk_clip().is_empty() and host.client.fetched.size()==1,"catalog announcement alone cannot select unimported clip")
	host._on_motion_asset_ready(true,"custom_walk","stub","test")
	check(host.walk_clip()=="custom_walk" and host.motion.locomotion_clips.get("custom_walk")==true,"successful import registers selected capability and hips flag")
	check(host.motion._locomotion_hip_centers.has("custom_walk"),"registration establishes clip center cache")
	var navigation: Array = []
	host.autonomy.navigation_finished.connect(func(id, outcome): navigation.append([id, outcome]))
	host.autonomy._active_target_id = "owned-trip"
	host._walk_started = "custom_walk"
	host.motion._vrma_name = "custom_walk"
	var empty: Array[Dictionary] = []
	host._on_motion_assets_loaded(true, empty, "test")
	check(host.walk_clip().is_empty() and host._vrma_loaded.is_empty() and host.panel.vrma_clips.is_empty(),"removed highpriority clip immediately leaves host selection and UI")
	check(not host.motion.locomotion_clips.has("custom_walk") and host.motion._locomotion_hip_centers.is_empty(),"removed custom registry and hips cache revoked")
	check(navigation==[["owned-trip","motion_catalog_refresh"]],"active navigation receives explicit refresh cancellation")
	check(host._walk_started.is_empty() and host.motion.stops==1,"owned active walk stopped on replacement")
	check(host.motion.locomotion_clips=={"walk":false,"walk_formal":false},"legacy registrations intentionally retained")
	host._on_motion_asset_ready(true,"custom_walk","stub","late")
	check(host.walk_clip().is_empty(),"late callback for removed name cannot readmit capability")
	host._on_motion_assets_loaded(true, entries, "test")
	host._on_motion_asset_ready(true,"custom_walk","stub","test")
	declared = declared.duplicate(true)
	declared.locomotion = false
	entries = [declared]
	host._on_motion_assets_loaded(true, entries, "test")
	check(not host.motion.locomotion_clips.has("custom_walk"),"revoked flag clears registry before download callback")
	host._on_motion_asset_ready(true,"custom_walk","stub","test")
	check(host._vrma_loaded.has("custom_walk") and host.walk_clip().is_empty() and not host.motion.locomotion_clips.has("custom_walk"),"revoked clip remains previewable without locomotion capability")
	host._on_motion_assets_loaded(false, empty, "intentional failed refresh")
	check(host._vrma_loaded.has("custom_walk"),"failed refresh preserves last successful catalogue")
	host.panel_open = true
	host._vrma_catalog["generic_new_gait"] = {"locomotion":true}
	host.motion.gestures.clear()
	host._on_event({"type":"action","turn_id":"gait-action","gesture":"generic_new_gait"})
	check(host.motion.gestures.size()==1 and host.motion.gestures[0][0]=="idle","actual action handler rejects newly declared locomotion")
	host._on_event({"type":"done","turn_id":"gait-action","gesture":"generic_new_gait"})
	check(host.motion.gestures.size()==1,"done deduplicates already handled locomotion action")
	host._on_event({"type":"done","turn_id":"gait-legacy-done","gesture":"generic_new_gait"})
	check(host.motion.gestures.size()==2 and host.motion.gestures[1][0]=="idle","legacy done-only handler also rejects declared locomotion")
	host._on_event({"type":"action","turn_id":"normal-wave","gesture":"wave","intensity":0.7,"speed":0.9})
	check(host.motion.gestures.back()[0]=="wave" and host.motion.gestures.back()[2]==0.7 and host.motion.gestures.back()[3]==0.9,"unrelated dialogue gesture and metadata unchanged")
	check(host._dialogue_gesture_name({"gesture":"walk"})=="idle" and host._dialogue_gesture_name({"gesture":"sit_idle"})=="idle","legacy walk and seated exclusions retained")
	host.free()
	print("Locomotion host refresh: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
