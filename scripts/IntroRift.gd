class_name IntroRift
extends MeshInstance3D

## The Lake Turkana rift as a displaced mesh on the intro planet (km units). Heights come from
## assets/intro/rift_height.png (Copernicus GLO-30, 16 bit split into R and G, 1/16 m steps),
## the box from IntroConfig.PATCH. The outer 5 % sinks 300 m below sea level, so at the edges
## the planet sphere (same Sentinel-2 imagery) covers the patch: no step, no z-fighting.

const TAPER: float = 0.05


func build(verts_per_side: int, material: Material) -> void:
	var tex: Texture2D = load(IntroConfig.TEX_DIR + "rift_height.png")
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	var w: int = img.get_width()
	var data: PackedByteArray = img.get_data()
	var n: int = verts_per_side
	var b: Vector4 = IntroConfig.PATCH
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	uvs.resize(n * n)
	var exag: float = IntroConfig.RELIEF_EXAG
	for j in n:
		var v: float = float(j) / float(n - 1)
		var lat: float = lerpf(b.w, b.y, v)
		var py: int = mini(int(round(v * (w - 1))), w - 1)
		for i in n:
			var u: float = float(i) / float(n - 1)
			var lon: float = lerpf(b.x, b.z, u)
			var px: int = mini(int(round(u * (w - 1))), w - 1)
			var k: int = (py * w + px) * 3
			var h_m: float = float(data[k] * 256 + data[k + 1]) / 16.0
			var edge: float = minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var t: float = smoothstep(0.0, TAPER, edge)
			var h_km: float = lerpf(-0.3, h_m * 0.001 * exag, t)
			var idx: int = j * n + i
			verts[idx] = IntroConfig.geo_dir(lat, lon) * (IntroConfig.PLANET_R + h_km)
			uvs[idx] = Vector2(u, v)
	var ind := PackedInt32Array()
	ind.resize((n - 1) * (n - 1) * 6)
	var c: int = 0
	for j in n - 1:
		for i in n - 1:
			var a: int = j * n + i
			# winding for outward faces (Godot front faces are clockwise seen from outside)
			ind[c] = a
			ind[c + 1] = a + 1
			ind[c + 2] = a + n
			ind[c + 3] = a + 1
			ind[c + 4] = a + n + 1
			ind[c + 5] = a + n
			c += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = ind
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
