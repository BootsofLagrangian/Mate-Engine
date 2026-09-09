extends RefCounted
## Optional reduced FlyWire graph. This is an engineered, bounded rate model,
## NOT a whole-brain emulation or a reproduction of the published LIF dynamics.
## Only actual exported signed edges carry activity from sensory to output groups.
const MAX_NODES := 1024
const MAX_EDGES := 32768
var ready := false
var state := PackedFloat64Array()
var edges: Array = []
var inputs: Dictionary = {}
var outputs: Dictionary = {}
var provenance: Dictionary = {}
var goal_input_map: Dictionary = {"left":"left","right":"right"}
var output_gain: Dictionary = {"left":1.0,"right":1.0}
var diagnostics: Dictionary = {"ready":false,"reason":"not_installed"}

func load_file(path: String = "user://fly-curiosity.json") -> bool:
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4000000: return false
	var parsed = JSON.parse_string(file.get_as_text())
	return configure(parsed) if parsed is Dictionary else false

func configure(data: Dictionary) -> bool:
	if pending(): return false # preserve the immutable graph of an outstanding worker
	_generation += 1
	ready = false; edges = []; state = PackedFloat64Array()
	inputs = {}; outputs = {}; provenance = {}
	diagnostics = {"ready":false,"reason":"invalid_circuit"}
	var nodes = data.get("nodes", [])
	var raw_edges = data.get("edges", [])
	if not nodes is Array or not raw_edges is Array or nodes.is_empty() or nodes.size() > MAX_NODES or raw_edges.is_empty() or raw_edges.size() > MAX_EDGES: return false
	for groups in [data.get("inputs",{}), data.get("outputs",{})]:
		if not groups is Dictionary: return false
		for side in ["left","right"]:
			var group = groups.get(side, [])
			if not group is Array or group.is_empty() or group.size() > nodes.size(): return false
			for index in group:
				if not (index is int or index is float) or not is_finite(float(index)) or float(index) != int(index) or int(index) < 0 or int(index) >= nodes.size(): return false
	var norms := PackedFloat64Array(); norms.resize(nodes.size()); norms.fill(0.0)
	for edge in raw_edges:
		if not edge is Array or edge.size() != 3: return false
		for value in edge:
			if not (value is float or value is int) or not is_finite(float(value)): return false
		var a := int(edge[0]); var b := int(edge[1]); var weight := float(edge[2])
		if float(a) != float(edge[0]) or float(b) != float(edge[1]) or a < 0 or b < 0 or a >= nodes.size() or b >= nodes.size(): return false
		norms[b] += absf(weight)
		edges.append([a,b,weight])
	for edge in edges: edge[2] = .85*float(edge[2])/maxf(norms[int(edge[1])],1.0)
	inputs = data.inputs.duplicate(true); outputs = data.outputs.duplicate(true)
	if not data.get("provenance",{}) is Dictionary: return false
	provenance = data.get("provenance",{}).duplicate(true)
	var mapping = data.get("goal_input_map", {"left":"left","right":"right"})
	if not mapping is Dictionary or mapping.get("left","") not in ["left","right"] or mapping.get("right","") not in ["left","right"]: return false
	goal_input_map = mapping.duplicate(true)
	output_gain = {"left":1.0,"right":1.0}
	state.resize(nodes.size()); state.fill(0.0)
	ready = true
	diagnostics = {"ready":true,"nodes":nodes.size(),"edges":edges.size(),"reason":"reduced_connectome_rate","last_us":0,"calls":0}
	var calibration: Dictionary = step({"left":1.0,"right":1.0})
	for side in ["left","right"]:
		var reference := float(calibration.raw_readout[side])
		# Silent/inhibitory output fixtures may be valid, but cannot be amplified.
		output_gain[side] = 1.0/reference if reference >= .0001 else 1.0
	reset()
	diagnostics.calls = 0
	diagnostics["output_gain"] = output_gain.duplicate()
	diagnostics["goal_input_map"] = goal_input_map.duplicate()
	return true

func reset() -> void:
	_generation += 1
	state.fill(0.0)

func step(sensory: Dictionary) -> Dictionary:
	if not ready: return {}
	var started := Time.get_ticks_usec()
	var stimulation := PackedFloat64Array(); stimulation.resize(state.size()); stimulation.fill(0.0)
	for side in ["left","right"]:
		var value := float(sensory.get(goal_input_map[side],0.0))
		value = clampf(value,0.0,1.0) if is_finite(value) else 0.0
		for index in inputs[side]: stimulation[int(index)] += value
	# Fixed work per decision; these settling steps are not elapsed biological time.
	for iteration in 24:
		var current := stimulation.duplicate()
		for edge in edges: current[int(edge[1])] += state[int(edge[0])]*float(edge[2])
		for i in state.size(): state[i] = lerpf(state[i],maxf(0.0,tanh(current[i])),.5)
	var readout := {}
	for side in ["left","right"]:
		var activity := 0.0
		for index in outputs[side]: activity += state[int(index)]
		readout[side] = activity/float(outputs[side].size())
	var raw_readout: Dictionary = readout.duplicate()
	for side in ["left","right"]: readout[side] = clampf(float(readout[side])*float(output_gain[side]),0.0,1.0)
	var total: float = readout.left + readout.right
	var result := {"forward":clampf(total*.5,0.0,1.0),"turn":clampf((readout.right-readout.left)/maxf(total,.00001),-1.0,1.0),"source":"reduced_flywire_rate","readout":readout,"raw_readout":raw_readout,"sensory":sensory.duplicate(true)}
	diagnostics.last_us = Time.get_ticks_usec()-started
	diagnostics.calls += 1
	diagnostics["last"] = result.duplicate(true)
	return result

# Immutable graph arrays are shared with a private worker state. Rendering never
# waits for circuit settling; stale generation results are discarded on reset.
var _task_id := -1
var _generation := 0
var _job_result: Dictionary = {}
func pending() -> bool:
	return _task_id >= 0
func begin(sensory: Dictionary) -> void:
	if not ready or pending(): return
	var worker = get_script().new()
	worker.ready = true; worker.edges = edges; worker.inputs = inputs; worker.outputs = outputs
	worker.goal_input_map = goal_input_map; worker.output_gain = output_gain
	worker.state = state.duplicate(); worker.diagnostics = {"calls":0}
	var generation := _generation
	var stimulus := sensory.duplicate(true)
	_task_id = WorkerThreadPool.add_task(func():
		var drive: Dictionary = worker.step(stimulus)
		_job_result = {"drive":drive,"state":worker.state,"us":worker.diagnostics.last_us,"generation":generation})
func poll() -> Dictionary:
	if not pending() or not WorkerThreadPool.is_task_completed(_task_id): return {}
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var result := _job_result; _job_result = {}
	if int(result.get("generation",-1)) != _generation: return {}
	state = result.state
	diagnostics.last_us = result.us; diagnostics.calls += 1
	diagnostics["last"] = result.drive.duplicate(true)
	return result.drive

func is_ready()->bool:return ready
