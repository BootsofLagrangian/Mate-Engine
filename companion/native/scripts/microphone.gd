class_name Microphone
extends Node
## Microphone capture through a muted "Mic" bus with AudioEffectCapture
## (muting the bus silences monitoring but the capture effect still receives
## the input samples). Supports explicit push-to-talk start/stop (bounded to
## MAX_SECONDS) and an optional energy VAD that is paused while the companion's
## own voice is playing. There is no acoustic echo cancellation (noAEC).
## The hardware input is only opened while push-to-talk is held or VAD is
## enabled (AudioStreamMicrophone play/stop = driver input_start/input_stop);
## with neither requested the microphone is really off (capture_changed).

signal utterance_ready(wav: PackedByteArray, seconds: float, source: String)
signal level_changed(rms: float)
signal recording_changed(active: bool, source: String)
signal vad_state_changed(state: String) # off | paused | waiting | speech
signal capture_changed(active: bool) # hardware input opened / closed
signal error(message: String)

const BUS_NAME := "Mic"
const MAX_SECONDS := 30.0
const VAD_FRAME_SECONDS := 0.02
const VAD_PREROLL_SECONDS := 0.35
const VAD_START_FRAMES := 4 # 80 ms above threshold
const VAD_END_SECONDS := 0.8
const VAD_MIN_UTTERANCE := 0.4
const OWN_VOICE_TAIL := 0.45

var vad_enabled := false
var vad_threshold := 0.035
var target_rate := 0 # 0 = keep AudioServer mix rate
var own_voice_active := false
var input_rate: int = 48000
var available := false

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _bus_index := -1
var _recording := false
var _record_source := ""
var _buffer := PackedFloat32Array()
var _preroll := PackedFloat32Array()
var _level := 0.0
var _vad_state := "off"
var _vad_above := 0
var _vad_silence := 0.0
var _own_voice_tail := 0.0
var _vad_speech_seconds := 0.0


func _ready() -> void:
	input_rate = int(AudioServer.get_mix_rate())
	available = bool(ProjectSettings.get_setting("audio/driver/enable_input", false))
	_setup_bus()
	_player = AudioStreamPlayer.new()
	_player.name = "MicPlayer"
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	# Capture is opened lazily (PTT / VAD); nothing records by default.


func _setup_bus() -> void:
	_bus_index = AudioServer.get_bus_index(BUS_NAME)
	if _bus_index < 0:
		AudioServer.add_bus()
		_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_index, BUS_NAME)
		AudioServer.set_bus_send(_bus_index, "Master")
	_capture = null
	for i in AudioServer.get_bus_effect_count(_bus_index):
		var e := AudioServer.get_bus_effect(_bus_index, i)
		if e is AudioEffectCapture:
			_capture = e
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.0
		AudioServer.add_bus_effect(_bus_index, _capture)
	# Mute so the user does not hear themselves; the capture effect still sees the samples.
	AudioServer.set_bus_mute(_bus_index, true)


func set_input_device(device: String) -> void:
	if device.is_empty() or not AudioServer.get_input_device_list().has(device):
		return
	AudioServer.input_device = device


func is_recording() -> bool:
	return _recording


## True while the hardware input is open (PTT held, VAD enabled, or a recording in flight).
func is_capturing() -> bool:
	return _player != null and _player.playing


func _set_capture(on: bool) -> void:
	if _player == null or not available:
		return
	if on == _player.playing:
		return
	if on:
		_player.play()
		if _capture:
			_capture.clear_buffer()
	else:
		_player.stop()
		_preroll = PackedFloat32Array()
		_level = 0.0
		level_changed.emit(0.0)
	capture_changed.emit(on)


func _update_capture() -> void:
	_set_capture(_recording or vad_enabled)


func recording_seconds() -> float:
	return float(_buffer.size()) / float(input_rate)


func level() -> float:
	return _level


func vad_state() -> String:
	return _vad_state


## Explicit push-to-talk start. Interrupts VAD capture and is allowed even while the pet speaks.
func start_push_to_talk() -> void:
	if not available:
		error.emit("마이크 입력이 비활성화되어 있습니다 (audio/driver/enable_input)")
		return
	if _recording and _record_source == "vad":
		_buffer = PackedFloat32Array()
	_begin("ptt")


func stop_push_to_talk() -> void:
	if _recording and _record_source == "ptt":
		_finish(true)


func cancel_recording() -> void:
	if _recording:
		_recording = false
		_buffer = PackedFloat32Array()
		recording_changed.emit(false, _record_source)
		_record_source = ""
		_set_vad_state("waiting" if vad_enabled else "off")
	_update_capture()


func set_vad_enabled(enabled: bool) -> void:
	vad_enabled = enabled and available
	if not vad_enabled and _recording and _record_source == "vad":
		cancel_recording()
	_vad_above = 0
	_vad_silence = 0.0
	_set_vad_state("waiting" if vad_enabled else "off")
	_update_capture()


func set_own_voice_active(active: bool) -> void:
	if own_voice_active and not active:
		_own_voice_tail = OWN_VOICE_TAIL
	own_voice_active = active
	if active and _recording and _record_source == "vad":
		# The companion started speaking: avoid feeding its own voice back (noAEC).
		cancel_recording()


func _begin(source: String) -> void:
	_recording = true
	_record_source = source
	_update_capture()
	_buffer = PackedFloat32Array()
	if source == "vad":
		_buffer.append_array(_preroll)
	_vad_speech_seconds = 0.0
	recording_changed.emit(true, source)
	if source == "vad":
		_set_vad_state("speech")


func _finish(send: bool) -> void:
	_recording = false
	var source := _record_source
	_record_source = ""
	var seconds := recording_seconds()
	recording_changed.emit(false, source)
	_set_vad_state("waiting" if vad_enabled else "off")
	if send and seconds >= 0.15:
		var wav := WavEncoder.encode(_buffer, input_rate, target_rate)
		utterance_ready.emit(wav, seconds, source)
	_buffer = PackedFloat32Array()
	_update_capture()


func _process(delta: float) -> void:
	if _capture == null or not available or not _player.playing:
		return
	var frames_available := _capture.get_frames_available()
	if frames_available <= 0:
		return
	var stereo := _capture.get_buffer(frames_available)
	var mono := PackedFloat32Array()
	mono.resize(stereo.size())
	var acc := 0.0
	for i in stereo.size():
		var s := (stereo[i].x + stereo[i].y) * 0.5
		mono[i] = s
		acc += s * s
	var rms := sqrt(acc / maxf(mono.size(), 1.0))
	_level = lerpf(_level, rms, 0.5)
	level_changed.emit(_level)

	# Pre-roll ring for VAD so the first syllable is not cut.
	_preroll.append_array(mono)
	var max_pre := int(VAD_PREROLL_SECONDS * input_rate)
	if _preroll.size() > max_pre:
		_preroll = _preroll.slice(_preroll.size() - max_pre)

	if _recording:
		_buffer.append_array(mono)
		if recording_seconds() >= MAX_SECONDS:
			_finish(true)
			return

	if _own_voice_tail > 0.0:
		_own_voice_tail -= delta
	if not vad_enabled:
		return
	if own_voice_active or _own_voice_tail > 0.0:
		_set_vad_state("paused")
		_vad_above = 0
		_vad_silence = 0.0
		return
	if _recording and _record_source == "ptt":
		return
	var voiced := rms > vad_threshold
	if not _recording:
		_set_vad_state("waiting")
		_vad_above = _vad_above + 1 if voiced else 0
		if _vad_above >= VAD_START_FRAMES:
			_vad_above = 0
			_begin("vad")
		return
	# recording via VAD
	var chunk_seconds := float(mono.size()) / float(input_rate)
	if voiced:
		_vad_silence = 0.0
		_vad_speech_seconds += chunk_seconds
	else:
		_vad_silence += chunk_seconds
	if _vad_silence >= VAD_END_SECONDS:
		if _vad_speech_seconds >= VAD_MIN_UTTERANCE:
			_finish(true)
		else:
			cancel_recording()


func _set_vad_state(s: String) -> void:
	if s == _vad_state:
		return
	_vad_state = s
	vad_state_changed.emit(s)
