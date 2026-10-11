class_name GroundMarks
extends MultiMeshInstance3D

## Every flat mark on the ground in one draw call (shaders/ground_mark.gdshader): team discs under
## units and animals, selection rings, move markers, placement footprints. Callers add marks
## between begin() and finish() once per rendered frame.

const MAX_MARKS: int = 640
const MODE_DISC: float = 0.0
const MODE_RING: float = 1.0
const MODE_FOOTPRINT: float = 2.0

var count: int = 0
var _buf := PackedFloat32Array()


## overlay: drawn without depth test (building rings, markers, footprints).
func _init(overlay: bool = false) -> void:
	name = "GroundOverlay" if overlay else "GroundMarks"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = load(
		(
			"res://shaders/ground_mark_overlay.gdshader"
			if overlay
			else "res://shaders/ground_mark.gdshader"
		)
	)
	mat.render_priority = -1
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(
		Vector3(0.0, -20.0, 0.0), Vector3(SpikeConfig.MAP_SIZE, 80.0, SpikeConfig.MAP_SIZE)
	)
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_buf.resize(MAX_MARKS * 20)


func begin() -> void:
	count = 0


## A mark of radius r (m) at `pos` lying on the ground plane with normal `n`.
func add(pos: Vector3, n: Vector3, r: float, col: Color, mode: float) -> void:
	if count >= MAX_MARKS:
		return
	var x: Vector3 = n.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z: Vector3 = x.cross(n).normalized()
	var o: int = count * 20
	var p: Vector3 = pos + n * 0.05
	_buf[o] = x.x * r
	_buf[o + 1] = n.x * r
	_buf[o + 2] = z.x * r
	_buf[o + 3] = p.x
	_buf[o + 4] = x.y * r
	_buf[o + 5] = n.y * r
	_buf[o + 6] = z.y * r
	_buf[o + 7] = p.y
	_buf[o + 8] = x.z * r
	_buf[o + 9] = n.z * r
	_buf[o + 10] = z.z * r
	_buf[o + 11] = p.z
	_buf[o + 12] = col.r
	_buf[o + 13] = col.g
	_buf[o + 14] = col.b
	_buf[o + 15] = col.a
	_buf[o + 16] = mode
	_buf[o + 17] = 0.0
	_buf[o + 18] = 0.0
	_buf[o + 19] = 0.0
	count += 1


## add() for flat ground (normal straight up), without the per-mark cross products: the same
## buffer values add() writes for n = Vector3.UP (Units: one disc per unit per frame).
func add_flat(x: float, y: float, z: float, r: float, col: Color, mode: float) -> void:
	if count >= MAX_MARKS:
		return
	var o: int = count * 20
	_buf[o] = -r
	_buf[o + 1] = 0.0
	_buf[o + 2] = 0.0
	_buf[o + 3] = x
	_buf[o + 4] = 0.0
	_buf[o + 5] = r
	_buf[o + 6] = 0.0
	_buf[o + 7] = y + 0.05
	_buf[o + 8] = 0.0
	_buf[o + 9] = 0.0
	_buf[o + 10] = -r
	_buf[o + 11] = z
	_buf[o + 12] = col.r
	_buf[o + 13] = col.g
	_buf[o + 14] = col.b
	_buf[o + 15] = col.a
	_buf[o + 16] = mode
	count += 1


func finish() -> void:
	multimesh.buffer = _buf
	multimesh.visible_instance_count = count
