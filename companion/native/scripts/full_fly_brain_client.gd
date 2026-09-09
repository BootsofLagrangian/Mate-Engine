extends Node
## Full available connectome runs in the backend's GPU worker. Native HTTP is
## asynchronous and carries only engineered goal signals, never screen content.
var loaded := false
var enabled := false
var base_url := ""
var diagnostics: Dictionary = {"ready":false,"reason":"full_brain_disabled","calls":0}
var provenance: Dictionary = {"scope":"full available signed connectome; engineered goal encoding and body decoder"}
var _session := ""
var _generation := 0
var _sequence := 0
var _step_request: HTTPRequest
var _status_request: HTTPRequest
var _result: Dictionary = {}
var _next_status := 0.0
var _retry_at := 0.0

func _ready()->void:
	_session = "native-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]

func configure(url: String)->void:
	url = url.trim_suffix("/")
	if url == base_url: return
	if is_instance_valid(_status_request):_status_request.cancel_request();_status_request.queue_free();_status_request=null
	reset(); base_url = url; loaded = false; _next_status = 0.0

func set_enabled(value: bool)->void:
	if value != enabled:
		enabled = value; reset(); _next_status = 0.0
		if not enabled and is_instance_valid(_status_request):_status_request.cancel_request();_status_request.queue_free();_status_request=null

func _process(_delta: float)->void:
	if not enabled or loaded or base_url.is_empty() or _status_request != null or Time.get_ticks_msec()*.001 < _next_status:return
	_next_status = Time.get_ticks_msec()*.001+2.0
	_status_request = HTTPRequest.new();_status_request.use_threads=true;_status_request.timeout=5.0;add_child(_status_request)
	var request := _status_request
	request.request_completed.connect(func(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		if _status_request != request:return
		_status_request=null;request.queue_free()
		var data = JSON.parse_string(body.get_string_from_utf8())
		if result==HTTPRequest.RESULT_SUCCESS and code==200 and data is Dictionary:
			loaded=bool(data.get("loaded",false))
			diagnostics["ready"]=loaded;diagnostics["status"]=data
			diagnostics["reason"]="full_connectome_ready" if loaded else "full_connectome_loading"
		else:diagnostics["reason"]="full_connectome_unavailable")
	var error := request.request(base_url+"/autonomy/brain/load",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,"{}")
	if error!=OK:_status_request=null;request.queue_free()

func reset()->void:
	_generation+=1;_result={}
	if is_instance_valid(_step_request):_step_request.cancel_request();_step_request.queue_free()
	_step_request=null

func pending()->bool:
	return _step_request != null or not _result.is_empty() or Time.get_ticks_msec()*.001 < _retry_at

func begin(sensory:Dictionary)->void:
	if not loaded or pending():return
	_sequence+=1
	var generation:=_generation
	var sequence:=_sequence
	var payload:={"session_id":_session,"generation":generation,"sequence":sequence,"left":float(sensory.get("left",0.0)),"right":float(sensory.get("right",0.0))}
	_step_request=HTTPRequest.new();_step_request.use_threads=true;_step_request.timeout=4.5;add_child(_step_request)
	var request:=_step_request
	request.request_completed.connect(func(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		if _step_request!=request:return
		_step_request=null;request.queue_free()
		if generation!=_generation:return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or not data is Dictionary:
			_retry_at=Time.get_ticks_msec()*.001+2.0;loaded=false;diagnostics["reason"]="full_connectome_retry";return
		if str(data.get("session_id",""))!=_session or int(data.get("generation",-1))!=generation or int(data.get("sequence",-1))!=sequence:return
		for key in ["forward","turn"]:
			if not (data.get(key) is float or data.get(key) is int) or not is_finite(float(data[key])):return
		data.forward=clampf(float(data.forward),0.0,1.0);data.turn=clampf(float(data.turn),-1.0,1.0)
		_result=data;diagnostics.calls+=1;diagnostics["last"]=data.duplicate(true);diagnostics["reason"]="full_connectome_ready")
	var error:=request.request(base_url+"/autonomy/brain/step",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if error!=OK:_step_request=null;request.queue_free();_retry_at=Time.get_ticks_msec()*.001+2.0

func poll()->Dictionary:
	var value:=_result;_result={};return value

func is_ready()->bool:return loaded
