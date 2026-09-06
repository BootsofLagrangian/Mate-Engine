extends SceneTree
## Offline authoring: reuse a verified UMA resting pose, add smooth bounded
## upper-body curves, retain the original VRMA hierarchy and rest transforms.
const SOURCE := "res://../assets/motions/uma_home_idle.vrma"
const EXPECTED_SOURCE := "679b086799df59c54fbb3760657b4c42e79bf7c1892c9fe3d99a1797fc27d0d9"
const DEFINITIONS := "res://../diagnostics/meme_motion/motions.json"
var blob := PackedByteArray()
var doc: Dictionary

func _init() -> void: call_deferred("run")

static func restore_integer_numbers(value: Variant) -> Variant:
	# JSON has one number type, but the Python catalog validates integer fields
	# strictly (including nested locomotion_style.version). Godot parses all
	# numbers as floats; restore lossless integral values recursively on write.
	if value is Dictionary:
		for key in value:value[key]=restore_integer_numbers(value[key])
	elif value is Array:
		for index in value.size():value[index]=restore_integer_numbers(value[index])
	elif value is float and is_finite(value) and absf(value)<=9007199254740991.0 and value==round(value):
		return int(value)
	return value

func accessor(values: Array, width: int) -> int:
	var floats := PackedFloat32Array()
	for row in values:
		for value in row: floats.append(value)
	var bytes := floats.to_byte_array()
	var view: int = doc.bufferViews.size()
	doc.bufferViews.append({"buffer":0,"byteOffset":blob.size(),"byteLength":bytes.size()})
	blob.append_array(bytes)
	var id: int = doc.accessors.size()
	doc.accessors.append({"bufferView":view,"componentType":5126,"count":values.size(),"type":"SCALAR" if width==1 else "VEC4"})
	if width==1:
		doc.accessors[id]["min"]=[values[0][0]]
		doc.accessors[id]["max"]=[values[-1][0]]
	return id

static func sample(track: Dictionary, time: float) -> Vector3:
	var keys: Array=track.keys
	for index in range(1,keys.size()):
		var a: Dictionary=keys[index-1]
		var b: Dictionary=keys[index]
		if time<=b.time:
			var u:=clampf((time-a.time)/(b.time-a.time),0,1)
			u=u*u*u*(u*(u*6-15)+10)
			return Vector3(a.x,a.y,a.z).lerp(Vector3(b.x,b.y,b.z),u)
	return Vector3.ZERO

static func node_rotation(node: Dictionary) -> Quaternion:
	var r: Array=node.get("rotation",[0,0,0,1])
	return Quaternion(r[0],r[1],r[2],r[3]).normalized()

func run() -> void:
	if FileAccess.get_sha256(SOURCE)!=EXPECTED_SOURCE:
		push_error("Verified UMA base pose missing or checksum changed")
		quit(1)
		return
	var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DEFINITIONS))
	var base:=VrmaClip.new()
	if not base.load_file(SOURCE):
		quit(1)
		return
	var base_pose:=base.sample(0.5)
	var source:=FileAccess.get_file_as_bytes(SOURCE)
	var original: Dictionary=JSON.parse_string(source.slice(20,20+source.decode_u32(12)).get_string_from_utf8())
	var manifest_path: String=ProjectSettings.globalize_path("res://../motion-assets.json")
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	manifest=restore_integer_numbers(manifest)
	var report:={"base_sha256":EXPECTED_SOURCE,"base_time_s":0.5,"base_pose_scope":"shoulders and arms only; head/neck/torso use neutral normalized rest","sample_hz":60,"motions":[]}
	for motion in definitions.motions:
		doc=original.duplicate(true)
		doc.asset.generator="Mate Companion bounded upper-body motion authoring"
		doc.accessors=[]
		doc.bufferViews=[]
		doc.animations=[{"name":motion.name,"channels":[],"samplers":[]}]
		blob=PackedByteArray()
		var parents:={}
		for i in doc.nodes.size():
			for child in doc.nodes[i].get("children",[]): parents[int(child)]=i
		var bones: Dictionary=doc.extensions.VRMC_vrm_animation.humanoid.humanBones
		var times: Array=[]
		for frame in int(round(motion.duration*60))+1: times.append([minf(frame/60.0,motion.duration)])
		var time_id:=accessor(times,1)
		for track in motion.tracks:
			if track.bone not in base_pose:
				push_error("Missing base track "+track.bone)
				quit(1)
				return
			var id:=int(bones[track.bone].node)
			var rest:=node_rotation(doc.nodes[id])
			var parent_rest:=Quaternion.IDENTITY
			var ancestor:int=parents.get(id,-1)
			while ancestor>=0:
				parent_rest=node_rotation(doc.nodes[ancestor])*parent_rest
				ancestor=parents.get(ancestor,-1)
			var rotations: Array=[]
			for t in times:
				# A partial upper-body overlay must not import a source head/neck
				# counter-rotation without its source ancestor rotations. Neutral
				# torso/head deltas avoid that accidental posture acquisition.
				var resting: Quaternion=base_pose[track.bone] if str(track.bone).begins_with("left") or str(track.bone).begins_with("right") else Quaternion.IDENTITY
				var normalized:Quaternion=(resting*VrmAvatar.canonical_to_basis(sample(track,t[0])).get_rotation_quaternion()).normalized()
				var rotation:Quaternion=(parent_rest.inverse()*normalized*parent_rest*rest).normalized()
				rotations.append([rotation.x,rotation.y,rotation.z,rotation.w])
			var output_id:=accessor(rotations,4)
			var sampler_id:int=doc.animations[0].samplers.size()
			doc.animations[0].samplers.append({"input":time_id,"output":output_id,"interpolation":"LINEAR"})
			doc.animations[0].channels.append({"sampler":sampler_id,"target":{"node":id,"path":"rotation"}})
		doc.buffers=[{"byteLength":blob.size()}]
		var json:=JSON.stringify(doc).to_utf8_buffer()
		while json.size()%4: json.append(32)
		var file_bytes:=PackedByteArray()
		file_bytes.resize(20)
		file_bytes.encode_u32(0,0x46546c67)
		file_bytes.encode_u32(4,2)
		file_bytes.encode_u32(8,28+json.size()+blob.size())
		file_bytes.encode_u32(12,json.size())
		file_bytes.encode_u32(16,0x4e4f534a)
		file_bytes.append_array(json)
		var bin_header:=PackedByteArray()
		bin_header.resize(8)
		bin_header.encode_u32(0,blob.size())
		bin_header.encode_u32(4,0x004e4942)
		file_bytes.append_array(bin_header)
		file_bytes.append_array(blob)
		var relative: String="assets/motions/"+motion.name+".vrma"
		var path: String=ProjectSettings.globalize_path("res://../"+relative)
		var file:=FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(file_bytes)
		file.close()
		var entry:={"name":motion.name,"path":relative,"kind":"vrma","duration":motion.duration,"loop":false,"ambient":false,"contact_mode":"foot","description":motion.description,"sha256":FileAccess.get_sha256(path),"source":"Original bounded upper-body curves over local UMA resting pose","source_manifest":"diagnostics/meme_motion/motions.json","license":"local-user-assets-not-redistributable"}
		var replaced:=false
		for index in manifest.motions.size():
			if manifest.motions[index].name==motion.name:
				manifest.motions[index]=entry
				replaced=true
				break
		if not replaced:manifest.motions.append(entry)
		report.motions.append(entry.merged({"bytes":file_bytes.size(),"rotation_tracks":motion.tracks.size(),"root_translation":false,"leg_tracks":false}))
	var file:=FileAccess.open(manifest_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  ",false,true)+"\n")
	file.close()
	file=FileAccess.open(ProjectSettings.globalize_path("res://../diagnostics/meme_motion/build.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	file.close()
	print("MEME_MOTION_BUILT=",report.motions.size())
	quit()
