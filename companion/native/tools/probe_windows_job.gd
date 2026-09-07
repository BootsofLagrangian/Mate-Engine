extends "probe_windows_space_skills.gd"
## Actual native job submission; no ordinary-chat intent injection or microphone capture.
var job_id := ""
var job_started := -1
var workspace := ""
var fixture := ""
var timings := {}
var job_terminal := {}
var speech_done := {}
var speech_bytes := {}
var playback_open := {}
var playback_closed := {}

func wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := mini(Time.get_ticks_msec()+int(seconds*1000),started+235000)
	while not closing and Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await process_frame
		await RenderingServer.frame_post_draw
	return false

func received(event: Dictionary) -> void:
	super.received(event)
	if job_id.is_empty(): return
	var kind := str(event.get("type",""))
	var speech := str(event.get("turn_id",""))
	if speech in ["job:"+job_id+":ack","job:"+job_id+":result"]:
		var phase := "ack" if speech.ends_with(":ack") else "result"
		if kind == "audio":
			speech_bytes[phase] = int(speech_bytes.get(phase,0))+Marshalls.base64_to_raw(str(event.get("pcm",""))).size()
			if not timings.has(phase+"_first_pcm_ms"): timings[phase+"_first_pcm_ms"] = elapsed()
		if kind == "done": speech_done[phase] = event.duplicate(true)
	if kind != "job" or str(event.get("job_id","")) != job_id: return
	var status := str(event.get("status",""))
	if status == "starting" and not timings.has("job_start_ms"): timings["job_start_ms"] = elapsed()
	var message := str(event.get("message",""))
	if status == "running" and (message.begins_with("$ ") or message.begins_with("exit ") or message.begins_with("edited ") or message.begins_with("tool ")):
		if not timings.has("first_tool_ms"): timings["first_tool_ms"] = elapsed()
	if status in ["completed","failed","cancelled"]:
		job_terminal = event.duplicate(true); timings["terminal_ms"] = elapsed()
	report["timings"] = timings; report["terminal"] = job_terminal
	write_report()

func playback_event(id: String, active: bool) -> void:
	if id not in ["job:"+job_id+":ack","job:"+job_id+":result"]: return
	var phase := "ack" if id.ends_with(":ack") else "result"
	if active:
		playback_open[phase] = elapsed()
		if not timings.has(phase+"_playback_ms"): timings[phase+"_playback_ms"] = elapsed()
	else:
		playback_closed[phase] = elapsed()
	report["timings"] = timings; report["playback_ended_ms"] = playback_closed
	write_report()

func run() -> void:
	if OS.get_name() != "Windows": push_error("Windows only"); quit(2); return
	output = argument("--output"); workspace = argument("--workspace")
	var character := argument("--character")
	if character.is_empty(): character = "cheval-grand"
	if output.is_empty() or not DirAccess.dir_exists_absolute(workspace):
		push_error("Require fresh --output and Windows-readable --workspace mapped to backend user-data/workspace"); quit(2); return
	if DirAccess.dir_exists_absolute(output): push_error("Output must be new"); quit(2); return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create report directory"); quit(2); return
	var report_test := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if report_test == null: push_error("Cannot write report"); quit(2); return
	report_test.close()
	started=Time.get_ticks_msec()
	fixture = "mate-native-job-smoke.txt"
	if FileAccess.file_exists(workspace.path_join(fixture)):
		fixture = "mate-native-job-smoke-"+str(Time.get_unix_time_from_system()).replace(".","-")+".txt"
	if not check(not FileAccess.file_exists(workspace.path_join(fixture)),"fresh fixture; no overwrite"): await finish(); return
	report["fixture"] = fixture; report["workspace_windows"] = workspace
	report["scope"] = "Actual native _start_job, real Codex process, native playback signals and read-back. PCM receipt is not acoustic onset. No ordinary LM request."
	settings_node=root.get_node("Settings"); original=settings_node.data.duplicate(true)
	settings_node.data.merge({"vad_enabled":false,"panel_open":false,"character":character},true)
	create_timer(240).timeout.connect(func():
		if not closing: check(false,"job probe watchdog"); finish())
	app=load("res://main.tscn").instantiate(); root.add_child(app); current_scene=app
	app.client.event_received.connect(received); app.audio.playback_changed.connect(playback_event)
	if not check(await wait_for(func(): return app.session.hello_received and app.avatar.has_model() and app._vrma_pending==0,45),"native ready"): await finish(); return
	app._switch_character(character)
	if not check(await wait_for(func(): return app.session.character_id==character and app._selection_announced==character and not app.loading_label.visible,20),"selected rig ready"): await finish(); return
	var caps: Dictionary = app.session.capabilities
	report["capabilities"] = caps.duplicate(true)
	report["identity"] = {"character":app.session.character_id,"model_path":app.avatar.model_path,"model_sha256":FileAccess.get_sha256(app.avatar.model_path),"renderer":RenderingServer.get_video_adapter_name()}
	if not check(bool(caps.get("jobs",false)) and str(caps.get("job_sandbox",""))=="workspace-write" and str(caps.get("job_workspace","")).replace("\\","/").ends_with("/user-data/workspace"),"authorized workspace-write job capability"): await finish(); return
	var prompt := "In the current working directory, create exactly one NEW file named "+fixture+" containing exactly MATE_NATIVE_JOB_OK followed by a newline. Use exclusive creation; if the file already exists, stop without changing it. Read the new file back and verify exact bytes. Do not modify any other file or access outside the current working directory. Report the verified result in one brief sentence."
	job_started=elapsed(); app._start_job(prompt); job_id=str(app.session.job.get("job_id",""))
	report["job_id"]=job_id; report["submitted_ms"]=job_started
	if not check(not job_id.is_empty(),"native job submission owns ID"): await finish(); return
	var ended := await wait_for(func(): return not job_terminal.is_empty() and (str(job_terminal.get("status",""))!="completed" or (speech_done.has("result") and playback_closed.has("result"))),170)
	check(ended,"job and result playback finished within deadline")
	check(job_terminal.get("status","")=="completed","real job completed")
	check(timings.has("first_tool_ms"),"native received tool progress")
	check(app.session.job.get("status","")=="completed" and not app.session.job.get("log",[]).is_empty(),"native session status and job log updated")
	for phase in ["ack","result"]:
		check(int(speech_bytes.get(phase,0))>0 and playback_open.has(phase) and playback_closed.has(phase),phase+" actual PCM and playback start/drain")
		check(bool(speech_done.get(phase,{}).get("ok",false)),phase+" speech generation succeeded")
	check(timings.has("ack_first_pcm_ms") and timings.has("job_start_ms") and int(timings.ack_first_pcm_ms)<=int(timings.job_start_ms),"ack PCM received before job starting event")
	# Playback may start after server launch: record ordering without inventing a server playback gate.
	report["ack_playback_before_job_start"] = timings.has("ack_playback_ms") and timings.has("job_start_ms") and int(timings.ack_playback_ms)<=int(timings.job_start_ms)
	report["ack_playback_before_first_tool"] = timings.has("ack_playback_ms") and timings.has("first_tool_ms") and int(timings.ack_playback_ms)<=int(timings.first_tool_ms)
	check(bool(report.ack_playback_before_first_tool),"ack playback began before first tool progress")
	var path := workspace.path_join(fixture)
	var bytes := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	report["fixture_sha256"] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	report["fixture_bytes"] = bytes.size(); report["speech_bytes"] = speech_bytes
	check(bytes == "MATE_NATIVE_JOB_OK\n".to_utf8_buffer(),"actual workspace file bytes verified independently")
	await finish()

func finish() -> void:
	if closing: return
	closing=true
	if app != null:
		app._cancel_job(); app.mic.cancel_recording(); app.audio.cancel(); app.world_source.stop()
		app.objects.shutdown(); app.client.disconnect_ws(); app.queue_free()
		await process_frame
		await process_frame
	if settings_node != null:
		settings_node.data=original.duplicate(true); settings_node.save_now()
		check(settings_node.data==original,"original settings restored")
		var restored: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_node.PATH))
		var serialized_original: Variant = JSON.parse_string(JSON.stringify(original))
		check(restored is Dictionary and restored==serialized_original,"original serialized settings restored on disk")
	write_report(); print("NATIVE_JOB_REPORT ",output.path_join("report.json"))
	quit(0 if int(report.get("failures",0))==0 else 1)
