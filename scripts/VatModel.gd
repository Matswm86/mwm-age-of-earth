class_name VatModel
extends RefCounted

## A vertex-animation-texture body baked by tools/game/bake_vat.py: assets/vat/<name>.glb (static
## mesh, UV2.x = vertex id, UV2.y = rest height 0..1), <name>.vat (float16 RGBA, 2048 wide:
## [position, normal] per vertex, rows_per_frame rows per 15 fps frame) and <name>.json (clips).
## The .vat and .json files are raw data, so the export preset includes assets/vat/*.
## Draw with a MultiMesh whose INSTANCE_CUSTOM is (clip first frame, frames + 1000 x loop,
## clip start time, team + 4 x selected); see shaders/vat.gdshader.

const DIR: String = "res://assets/vat/"

var name: String = ""
var mesh: Mesh
var material: ShaderMaterial
var vertices: int = 0
var rows_per_frame: int = 1
var fps: float = 15.0
## clip name -> [first frame, frames, loop 0/1]
var clips: Dictionary = {}
var triangles: int = 0


static func load_model(model: String, paint: bool) -> VatModel:
	var v := VatModel.new()
	v.name = model
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + model + ".json"))
	if not meta is Dictionary:
		push_error("VatModel: missing %s.json" % model)
		return v
	var md: Dictionary = meta
	v.vertices = int(md["vertices"])
	v.rows_per_frame = int(md["rows_per_frame"])
	v.fps = float(md["fps"])
	v.clips = md["clips"]
	var w: int = int(md["width"])
	var h: int = int(md["height"])
	var f := FileAccess.open(DIR + model + ".vat", FileAccess.READ)
	var bytes: PackedByteArray = f.get_buffer(w * h * 8) if f != null else PackedByteArray()
	if bytes.size() != w * h * 8:
		push_error("VatModel: %s.vat has %d bytes, want %d" % [model, bytes.size(), w * h * 8])
		bytes.resize(w * h * 8)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBAH, bytes)
	var tex := ImageTexture.create_from_image(img)
	var ps: PackedScene = load(DIR + model + ".glb")
	var root: Node = ps.instantiate()
	var mi: MeshInstance3D = _find_mesh(root)
	v.mesh = mi.mesh
	var albedo: Texture2D = null
	var src: Material = mi.get_active_material(0)
	if src is StandardMaterial3D:
		albedo = (src as StandardMaterial3D).albedo_texture
	root.free()
	var arrays: Array = v.mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	v.triangles = int(idx.size() / 3.0)
	v.material = ShaderMaterial.new()
	v.material.shader = load("res://shaders/vat.gdshader")
	v.material.set_shader_parameter("vat", tex)
	v.material.set_shader_parameter("vcount", v.vertices)
	v.material.set_shader_parameter("rows_per_frame", v.rows_per_frame)
	v.material.set_shader_parameter("fps", v.fps)
	v.material.set_shader_parameter("albedo_tex", albedo)
	v.material.set_shader_parameter("paint", 1.0 if paint else 0.0)
	var cols := PackedVector3Array()
	for c: Color in SpikeConfig.TEAM_COLOURS:
		cols.append(Vector3(c.r, c.g, c.b))
	cols.append(Vector3(0.43, 0.40, 0.36))
	v.material.set_shader_parameter("team_cols", cols)
	return v


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m: MeshInstance3D = _find_mesh(c)
		if m != null:
			return m
	return null


## INSTANCE_CUSTOM.rg for a clip: (first frame, frames + 1000 x loop).
func clip_rg(clip: String) -> Vector2:
	var c: Array = clips.get(clip, clips.values()[0])
	return Vector2(float(c[0]), float(c[1]) + 1000.0 * float(c[2]))


## Clip length in seconds.
func clip_len(clip: String) -> float:
	var c: Array = clips.get(clip, clips.values()[0])
	return float(c[1]) / fps
