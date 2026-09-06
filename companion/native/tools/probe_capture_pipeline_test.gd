extends "probe_windows_authored_seating.gd"
## Linux-owned viewport exercise of the exact external probe writer, no app.
func run() -> void:
 output="/tmp/probe-capture-pipeline"
 DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
 root.size=Vector2i(1920,1760)
 started=Time.get_ticks_msec()
 var control:=ColorRect.new()
 control.color=Color(.15,.25,.4)
 control.size=Vector2(700,900)
 root.add_child(control)
 var maximum_readback:=0
 var intervals:Array=[]
 var previous:=elapsed()
 for index in 90:
  await process_frame
  await RenderingServer.frame_post_draw
  poll_capture_jobs()
  var now:=elapsed()
  intervals.append(now-previous);previous=now
  var row:Dictionary={"ms":now,"sequence":"pipeline","stage":"first" if index<45 else "second","render_frame":Engine.get_frames_drawn()}
  capture_frame(row)
  maximum_readback=maxi(maximum_readback,row.capture_readback_us)
  samples.append(row)
  control.position.x=float(index)*2
 await drain_capture_jobs()
 var failures:=0
 for row in samples:
  if not str(row.image).is_empty() and (row.image_error!=OK or not FileAccess.file_exists(output.path_join(row.image))):failures+=1
 if samples.size()!=90 or not capture_jobs.is_empty() or capture_queue_skips!=0:failures+=1
 # An actual filesystem save failure must remain visible after draining.
 var obstruction:=output.path_join("not_a_directory")
 var file:=FileAccess.open(obstruction,FileAccess.WRITE);file.store_string("fixture");file=null
 var failed_job:=CaptureWriteJob.new()
 failed_job.image=root.get_texture().get_image();failed_job.path=obstruction.path_join("bad.png")
 failed_job.row={"image":"not_a_directory/bad.png","ms":elapsed(),"render_frame":Engine.get_frames_drawn(),"capture_readback_us":0}
 failed_job.task_id=WorkerThreadPool.add_task(failed_job.run);capture_jobs.append(failed_job)
 await drain_capture_jobs()
 if failed_job.row.image_error==OK or capture_records[-1].sha256!="":failures+=1
 var result:Dictionary={"expected_save_failures":1,"samples":samples.size(),"captures":capture_records,"max_readback_us":maximum_readback,"queue_skips":capture_queue_skips,"intervals_ms":intervals,"failures":failures,"scope":"Writer lifecycle/flush with synthetic owned viewport; not app performance acceptance"}
 FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("CAPTURE_PIPELINE_FAILURES=",failures," samples=",samples.size()," captures=",capture_records.size())
 quit(failures)
