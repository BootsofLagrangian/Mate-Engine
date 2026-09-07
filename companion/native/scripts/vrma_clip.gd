class_name VrmaClip
extends RefCounted
## Embedded GLB VRMA rotation playback. Root translation is intentionally pinned
## for desktop presentation. Supports LINEAR/STEP float tracks; rejects others.
var duration := 0.0
var tracks: Dictionary = {}
var error := ""
var hips_translation: Dictionary = {}
var hips_rest := Vector3.ZERO
var source_hips_height := 1.0

func load_file(path: String) -> bool:
	tracks.clear()
	hips_translation.clear()
	duration = 0.0
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 28 or bytes.decode_u32(0) != 0x46546c67:
		return _fail("Not a GLB VRMA")
	var json_size := bytes.decode_u32(12)
	if 20 + json_size + 8 > bytes.size():
		return _fail("Truncated GLB")
	var data: Variant = JSON.parse_string(bytes.slice(20,20+json_size).get_string_from_utf8())
	if not data is Dictionary:
		return _fail("Invalid JSON")
	var binary := bytes.slice(28+json_size)
	var bones: Dictionary = data.get("extensions", {}).get("VRMC_vrm_animation", {}).get("humanoid", {}).get("humanBones", {})
	if bones.is_empty() or data.get("animations", []).is_empty():
		return _fail("Missing VRMA humanoid/animation")
	var nodes: Array = data.nodes
	var parents := {}
	for i in nodes.size():
		for child in nodes[i].get("children", []):
			parents[int(child)] = i
	var names := {}
	for bone in bones:
		names[int(bones[bone].node)] = bone
	if bones.has("hips"):
		var hips_node := int(bones.hips.node)
		var rest_values: Array = nodes[hips_node].get("translation",[0,0,0])
		hips_rest = Vector3(rest_values[0],rest_values[1],rest_values[2])
		# Baked humanoid candidates place hips at the scene root in metres.
		# Other sources remain rotation-only unless their profile opts in.
		source_hips_height = maxf(absf(hips_rest.y),0.001)
	var animation: Dictionary = data.animations[0]
	for channel in animation.channels:
		var node := int(channel.target.get("node", -1))
		if channel.target.path == "translation" and names.get(node,"") == "hips":
			var translation_sampler: Dictionary = animation.samplers[int(channel.sampler)]
			if str(translation_sampler.get("interpolation","LINEAR")) not in ["LINEAR","STEP"]:
				return _fail("Unsupported hips translation interpolation")
			var translation_times := _accessor(data,binary,int(translation_sampler.input),1)
			var translation_values := _accessor(data,binary,int(translation_sampler.output),3)
			if translation_values.size() != translation_times.size()*3 or translation_times.is_empty():
				return _fail("Invalid hips translation accessor")
			hips_translation = {"times":translation_times,"values":translation_values,"step":translation_sampler.get("interpolation","LINEAR") == "STEP"}
		if channel.target.path != "rotation" or not names.has(node):
			continue
		var sampler: Dictionary = animation.samplers[int(channel.sampler)]
		var interpolation := str(sampler.get("interpolation", "LINEAR"))
		if interpolation not in ["LINEAR", "STEP"]:
			return _fail("Unsupported interpolation: " + interpolation)
		var times := _accessor(data, binary, int(sampler.input), 1)
		var values := _accessor(data, binary, int(sampler.output), 4)
		if times.is_empty() or values.size() != times.size()*4:
			return _fail("Invalid rotation accessor")
		var rest := _rotation(nodes[node])
		var parent_rest := Quaternion.IDENTITY
		var ancestor: int = parents.get(node,-1)
		while ancestor >= 0:
			parent_rest = _rotation(nodes[ancestor]) * parent_rest
			ancestor = parents.get(ancestor,-1)
		var rotations: Array[Quaternion] = []
		for i in times.size():
			var q := Quaternion(values[i*4],values[i*4+1],values[i*4+2],values[i*4+3]).normalized()
			rotations.append((parent_rest * q * rest.inverse() * parent_rest.inverse()).normalized())
		tracks[names[node]] = {"times": times, "rotations": rotations, "step": interpolation == "STEP"}
		duration = maxf(duration, times[-1])
	return not tracks.is_empty()

func sample(time: float) -> Dictionary:
	var pose := {}
	for bone in tracks:
		var track: Dictionary = tracks[bone]
		var times: PackedFloat32Array = track.times
		var right := times.bsearch(time)
		right = clampi(right,0,times.size()-1)
		var left := maxi(0,right-1)
		var weight := clampf((time-times[left])/maxf(0.000001,times[right]-times[left]),0,1)
		if track.step:
			weight = 0.0 if time < times[right] else 1.0
		pose[bone] = track.rotations[left].slerp(track.rotations[right],weight)
	return pose

## Source-metres offset / source hip height; caller scales by target hip height.
## Only the explicit contact-aware ambient layer consumes it.
func sample_hips_offset(time: float) -> Vector3:
	if hips_translation.is_empty():
		return Vector3.ZERO
	var times: PackedFloat32Array = hips_translation.times
	var values: PackedFloat32Array = hips_translation.values
	var right := clampi(times.bsearch(time),0,times.size()-1)
	var left := maxi(0,right-1)
	var weight := clampf((time-times[left])/maxf(0.000001,times[right]-times[left]),0,1)
	if hips_translation.step:
		weight = 0.0 if time < times[right] else 1.0
	var a := Vector3(values[left*3],values[left*3+1],values[left*3+2])
	var b := Vector3(values[right*3],values[right*3+1],values[right*3+2])
	return (a.lerp(b,weight)-hips_rest)/source_hips_height

func _accessor(data: Dictionary, binary: PackedByteArray, idx: int, width: int) -> PackedFloat32Array:
	var accessor: Dictionary = data.accessors[idx]
	if int(accessor.componentType) != 5126 or not accessor.has("bufferView"):
		return PackedFloat32Array()
	var view: Dictionary = data.bufferViews[int(accessor.bufferView)]
	var offset := int(view.get("byteOffset",0)) + int(accessor.get("byteOffset",0))
	var stride := int(view.get("byteStride",width*4))
	var result := PackedFloat32Array()
	for i in int(accessor.count):
		for c in width:
			var address := offset+i*stride+c*4
			if address+4 > binary.size():
				return PackedFloat32Array()
			result.append(binary.decode_float(address))
	return result

func _rotation(node: Dictionary) -> Quaternion:
	var r: Array = node.get("rotation",[0,0,0,1])
	return Quaternion(r[0],r[1],r[2],r[3]).normalized()

func _fail(message: String) -> bool:
	error = message
	tracks.clear()
	return false
