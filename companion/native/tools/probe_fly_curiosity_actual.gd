extends SceneTree
func arg(key:String)->String:
	var args:=OS.get_cmdline_user_args()
	for i in args.size()-1:
		if args[i]==key:return args[i+1]
	return ""
func _initialize()->void:call_deferred("run")
func run()->void:
	var model=load("res://scripts/fly_curiosity_circuit.gd").new()
	if not model.load_file(arg("--circuit")):push_error("circuit load failed");quit(2);return
	var rows:Array=[]
	for stimulus in [{"left":1.0,"right":0.0},{"left":0.0,"right":1.0},{"left":1.0,"right":1.0},{"left":.4,"right":.4},{"left":0.0,"right":0.0}]:
		model.reset()
		var result:Dictionary=model.step(stimulus)
		rows.append({"input":stimulus,"output":result,"us":model.diagnostics.last_us})
	var timing:Array=[]
	for i in 50:
		model.step({"left":float(i%7)/7,"right":float(i%11)/11})
		timing.append(model.diagnostics.last_us)
	timing.sort()
	var begin_us:Array=[]
	var poll_us:Array=[]
	for i in 24:
		var start:=Time.get_ticks_usec()
		model.begin({"left":float(i%7)/7,"right":float(i%11)/11})
		begin_us.append(Time.get_ticks_usec()-start)
		while model.pending():
			await process_frame
			start=Time.get_ticks_usec()
			model.poll()
			poll_us.append(Time.get_ticks_usec()-start)
	begin_us.sort();poll_us.sort()
	var report:={"async_enqueue_us_max":begin_us[-1],"async_poll_us_max":poll_us[-1],"patterns":rows,"timing_us_p50":timing[25],"timing_us_p99":timing[49],"diagnostics":model.diagnostics}
	print(JSON.stringify(report))
	if not arg("--output").is_empty():
		var f:=FileAccess.open(arg("--output"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "))
	quit()
