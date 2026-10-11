class_name UnitMesh
extends RefCounted

## Placeholder early-hominin figure, about 1.4 m tall, facing +Z, built from primitive meshes
## (High about 1.7k triangles, Low about 0.6k). No skeleton: shaders/unit.gdshader
## animates the walk per vertex.
## Vertex COLOR.rgb = base colour, COLOR.a = team-colour mask. UV2.x = body part id:
## 0 body/head, 1 left thigh, 2 right thigh, 3 left shin+foot, 4 right shin+foot,
## 5 left arm, 6 right arm. Pivots (hip, knee, shoulder heights) live in the shader.

const SKIN := Color(0.36, 0.25, 0.18)
const FUR := Color(0.2, 0.15, 0.11)
const HIP_Y: float = 0.72
const KNEE_Y: float = 0.38
const SHOULDER_Y: float = 1.16

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv2 := PackedVector2Array()
var _idx := PackedInt32Array()
## 1 = High (about 1.7k triangles), 0 = Low (about 0.6k, for the 32-bit tablet).
var _detail: int = 1


func build(detail: int = 1) -> ArrayMesh:
	_detail = detail
	for s in [-1.0, 1.0]:
		var side: float = s
		var left: bool = side < 0.0
		var x: float = 0.1 * side
		# thigh, shin, foot
		_limb(Vector3(x, HIP_Y, 0.0), Vector3(x, KNEE_Y, 0.02), 0.068, 0.052, SKIN, 1 if left else 2)
		_limb(Vector3(x, KNEE_Y, 0.02), Vector3(x, 0.06, 0.0), 0.05, 0.04, SKIN, 3 if left else 4)
		var foot := BoxMesh.new()
		foot.size = Vector3(0.09, 0.05, 0.19)
		_add(foot, Transform3D(Basis(), Vector3(x, 0.03, 0.05)), SKIN, 0.0, 3 if left else 4)
		# arm (long, hominin proportions): upper, lower, hand
		var sx: float = 0.22 * side
		var elbow := Vector3(sx * 1.08, 0.86, 0.04)
		_limb(Vector3(sx, SHOULDER_Y, 0.02), elbow, 0.05, 0.043, FUR, 5 if left else 6)
		_limb(elbow, Vector3(sx * 1.1, 0.58, 0.08), 0.042, 0.036, SKIN, 5 if left else 6)
		var hand := SphereMesh.new()
		hand.radius = 0.045
		hand.height = 0.1
		hand.radial_segments = _seg(8, 5)
		hand.rings = _seg(4, 2)
		_add(hand, Transform3D(Basis(), Vector3(sx * 1.1, 0.54, 0.09)), SKIN, 0.0, 5 if left else 6)
	# pelvis band: the team colour (ochre-dyed hide in the real art)
	var band := CylinderMesh.new()
	band.top_radius = 0.175
	band.bottom_radius = 0.165
	band.height = 0.24
	band.radial_segments = _seg(12, 8)
	band.rings = 1
	var band_xf := Transform3D(Basis().scaled(Vector3(1.1, 1.0, 0.85)), Vector3(0.0, 0.76, 0.0))
	_add(band, band_xf, SKIN, 1.0, 0)
	# torso, leaning forward
	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.62
	torso.radial_segments = _seg(12, 8)
	torso.rings = _seg(6, 2)
	var lean := Basis(Vector3.RIGHT, 0.22).scaled(Vector3(1.15, 1.0, 0.82))
	_add(torso, Transform3D(lean, Vector3(0.0, 1.0, 0.06)), FUR, 0.0, 0)
	# head and muzzle
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.23
	head.radial_segments = _seg(14, 8)
	head.rings = _seg(8, 4)
	_add(head, Transform3D(Basis(), Vector3(0.0, 1.36, 0.14)), FUR, 0.0, 0)
	var muzzle := SphereMesh.new()
	muzzle.radius = 0.065
	muzzle.height = 0.11
	muzzle.radial_segments = _seg(8, 5)
	muzzle.rings = _seg(4, 2)
	_add(muzzle, Transform3D(Basis(), Vector3(0.0, 1.32, 0.23)), SKIN, 0.0, 0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _seg(high: int, low: int) -> int:
	return high if _detail == 1 else low


func triangle_count() -> int:
	return int(_idx.size() / 3.0)


## A tapered cylinder from a to b.
func _limb(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, part: int) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = ra
	cyl.bottom_radius = rb
	cyl.height = a.distance_to(b)
	cyl.radial_segments = _seg(10, 6)
	cyl.rings = _seg(2, 0)
	var y: Vector3 = (a - b).normalized()
	var x: Vector3 = Vector3.FORWARD.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	_add(cyl, Transform3D(Basis(x, y, z), (a + b) * 0.5), col, 0.0, part)


func _add(prim: PrimitiveMesh, xf: Transform3D, col: Color, team: float, part: int) -> void:
	var arr: Array = prim.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ids: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base: int = _v.size()
	var nb: Basis = xf.basis.inverse().transposed()
	var c := Color(col.r, col.g, col.b, team)
	for i in verts.size():
		_v.append(xf * verts[i])
		_n.append((nb * norms[i]).normalized())
		_c.append(c)
		_uv2.append(Vector2(float(part), 0.0))
	for i in ids.size():
		_idx.append(base + ids[i])
