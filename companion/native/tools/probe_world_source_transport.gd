extends SceneTree
var passed:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failures.append(label)
func _initialize()->void:call_deferred("run")
func write_payload(path:String,payload:String)->void:
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(payload);file.close()
func run()->void:
 var source:=DesktopWorldSource.new();root.add_child(source)
 var path:="/tmp/mate-world-transport-%d.json" % OS.get_process_id()
 source._snapshot_path=path
 var value:={"version":1,"timestamp_msec":10000,"monitors":[{"id":"m","x":0,"y":0,"width":1000,"height":800,"work_x":0,"work_y":0,"work_width":1000,"work_height":760}],"windows":[]}
 var received:Array=[]
 source.snapshot_changed.connect(func(snapshot:Dictionary):received.append(snapshot))
 write_payload(path,JSON.stringify(value))
 source._read_snapshot(10010)
 check(source.available and source.parse_count==1 and received.size()==1,"initial geometry parsed and published")
 for index in 24:source._read_snapshot(10100+index*125)
 check(source.parse_count==1 and source.unchanged_reads==24 and received.size()==1,"unchanged transport avoids JSON and downstream publication")
 source._read_snapshot(15001)
 check(not source.available and source.snapshot.is_empty() and received.size()==2,"unchanged stale file expires")
 source._read_snapshot(15126)
 check(source.parse_count==1 and received.size()==2,"expired unchanged file does not parse or repeat clear")
 value.timestamp_msec=15200
 write_payload(path,JSON.stringify(value))
 source._read_snapshot(15210)
 check(source.available and source.parse_count==2 and received.size()==3,"fresh heartbeat restores availability")
 write_payload(path,"invalid")
 source._read_snapshot(15300)
 check(source.available and not source.snapshot.is_empty(),"transport error retains last fresh geometry")
 source._read_snapshot(20201)
 check(not source.available and source.snapshot.is_empty(),"transport error cannot extend geometry deadline")
 check(DesktopWorldSource.POLL_SECONDS==.125,"consumer checks within eighth second")
 DirAccess.remove_absolute(path);source.queue_free()
 print("world source transport: %d passed, %d failed" % [passed,failures.size()])
 for failure in failures:print("FAIL: "+failure)
 quit(0 if failures.is_empty() else 1)
