extends "../../native/tools/probe_windows_authored_seating.gd"
func run()->void:
 output="/tmp/mate-independent-capture-worker"
 DirAccess.make_dir_recursive_absolute(output)
 var actual_jobs:Array=[]
 for index in 2:
  var job:=CaptureWriteJob.new()
  job.image=Image.create(8,8,false,Image.FORMAT_RGBA8);job.image.fill(Color.RED)
  job.path=output.path_join("valid.png" if index==0 else "missing-directory/invalid.png")
  job.row={"image":job.path,"ms":index,"render_frame":index,"capture_readback_us":0}
  job.task_id=WorkerThreadPool.add_task(job.run)
  capture_jobs.append(job);actual_jobs.append(job)
 await drain_capture_jobs()
 var failures:=0
 if not capture_jobs.is_empty() or capture_records.size()!=2:failures+=1
 if actual_jobs[0].row.image_error!=OK or actual_jobs[0].row.capture_status!="saved" or actual_jobs[0].sha256.length()!=64:failures+=1
 if actual_jobs[1].row.image_error==OK or actual_jobs[1].row.capture_status!="save_error" or not actual_jobs[1].sha256.is_empty():failures+=1
 if capture_records.all(func(row):return row.error==OK and str(row.sha256).length()==64):failures+=1
 FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/motion_seams/review-capture-worker.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":4,"scope":"Concurrent valid/invalid PNG writes; failure is deliberate and must remain visible","records":capture_records},"  ")+"\n")
 print("INDEPENDENT_CAPTURE_WORKER_FAILURES=",failures);quit(failures)
