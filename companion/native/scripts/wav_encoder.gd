class_name WavEncoder
extends RefCounted
## Mono 16-bit PCM WAV encoding with optional downsampling.


## Encode mono float samples at [rate]. When [target_rate] > 0 and differs from [rate],
## the signal is box-filtered and linearly resampled first.
static func encode(samples: PackedFloat32Array, rate: int, target_rate: int = 0) -> PackedByteArray:
	var out_rate := rate
	var data := samples
	if target_rate > 0 and target_rate != rate:
		data = resample(samples, rate, target_rate)
		out_rate = target_rate
	var pcm := PackedByteArray()
	pcm.resize(data.size() * 2)
	for i in data.size():
		var v := int(round(clampf(data[i], -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 2, v)
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # "RIFF"
	header.encode_u32(4, 36 + pcm.size())
	header.encode_u32(8, 0x45564157) # "WAVE"
	header.encode_u32(12, 0x20746d66) # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1) # PCM
	header.encode_u16(22, 1) # mono
	header.encode_u32(24, out_rate)
	header.encode_u32(28, out_rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # "data"
	header.encode_u32(40, pcm.size())
	header.append_array(pcm)
	return header


static func resample(samples: PackedFloat32Array, rate: int, target_rate: int) -> PackedFloat32Array:
	if samples.is_empty() or rate == target_rate or target_rate <= 0:
		return samples
	var ratio := float(rate) / float(target_rate)
	var src := samples
	if ratio > 1.0:
		# Simple moving-average low-pass to limit aliasing before decimation.
		var win := int(ceil(ratio))
		var filtered := PackedFloat32Array()
		filtered.resize(samples.size())
		var acc := 0.0
		for i in samples.size():
			acc += samples[i]
			if i >= win:
				acc -= samples[i - win]
			filtered[i] = acc / float(mini(i + 1, win))
		src = filtered
	var count := int(floor(float(samples.size()) / ratio))
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var pos := i * ratio
		var idx := int(floor(pos))
		var frac := pos - idx
		var a := src[mini(idx, src.size() - 1)]
		var b := src[mini(idx + 1, src.size() - 1)]
		out[i] = a + (b - a) * frac
	return out


## Minimal header parse for verification: returns {rate, channels, bits, frames} or {}.
static func parse_header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44 or bytes.decode_u32(0) != 0x46464952 or bytes.decode_u32(8) != 0x45564157:
		return {}
	var channels := bytes.decode_u16(22)
	var rate := bytes.decode_u32(24)
	var bits := bytes.decode_u16(34)
	var data_size := bytes.decode_u32(40)
	return {"rate": rate, "channels": channels, "bits": bits, "frames": data_size / maxi(channels * bits / 8, 1)}
