class_name RtsTerrain
extends Node3D

## The Rift Lake map (West Turkana, Copernicus GLO-30 at 1:10, DESIGN 7.2): 512 x 512 m, heights
## from assets/terrain/game/height_f32.bin (vertical exaggeration x3 baked in, lake surface at y 0),
## a 7-layer height-blended PBR ground (shaders/terrain.gdshader), the Lake Turkana water plane
## (shaders/water.gdshader) and the 128 x 128 navigation
## grid (4 m cells, water and wet shore blocked).
## The ground mesh is one flat 64 x 64 m grid reused by 8 x 8 chunks; the vertex shader lifts it
## from the height texture, so nothing heavy is built on the CPU (the intro builds this too).
## ground_image (512 x 512, 1 m texels) holds runtime marks the shader reads: R contact
## occlusion under trees, rocks and buildings (1 = open), G trampled camp floor.

const DIR: String = "res://assets/terrain/game/"
const SRC: String = "res://assets/terrain/rift_lake/"
## Vegetation biome mask (tools/game/bake_biome.py): R forest, G lush, B trails, A reeds.
const BIOME: String = "res://assets/terrain/game/biome.png"
const CHUNKS: int = 8
## Layer tiling in metres and albedo tints (DESIGN 7.2), splat order a.rgba then b.rgb.
const TILE_M: Array[float] = [3.0, 2.5, 3.5, 3.0, 2.5, 1.8, 3.0]
const TINTS: Array[Color] = [
	Color(0.78, 0.70, 0.56),
	Color(0.80, 0.70, 0.62),
	Color(0.85, 0.82, 0.80),
	Color(0.92, 0.88, 0.82),
	Color(0.80, 0.78, 0.74),
	Color(0.95, 0.92, 0.88),
	Color(1.0, 0.95, 0.90),
]

var n_side: int = 0
## Game heights (m) on the 0.5 m grid, row-major, row 0 = north (z = 0).
var heights: PackedFloat32Array = PackedFloat32Array()
## 1 = blocked nav cell (water, wet shore or steep).
var blocked: PackedByteArray = PackedByteArray()
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var ground_image: Image
var ground_tex: ImageTexture
var height_tex: ImageTexture


func build(fog_tex: Texture2D) -> void:
	n_side = SpikeConfig.HEIGHT_SAMPLES
	_load_heights()
	_make_nav()
	ground_image = Image.create(512, 512, false, Image.FORMAT_RG8)
	ground_image.fill(Color(1.0, 0.0, 0.0))
	ground_tex = ImageTexture.create_from_image(ground_image)
	var macro := NoiseTexture2D.new()
	macro.width = 256
	macro.height = 256
	macro.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.012
	fn.fractal_octaves = 3
	macro.noise = fn
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	var m: ShaderMaterial = terrain_mat
	m.set_shader_parameter("fog_tex", fog_tex)
	m.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)
	m.set_shader_parameter("height_tex", height_tex)
	m.set_shader_parameter("normal_tex", load(DIR + "normal.png"))
	m.set_shader_parameter("sky_ao_tex", load(DIR + "sky_ao.png"))
	m.set_shader_parameter("splat_a", load(SRC + "splat_a.png"))
	m.set_shader_parameter("splat_b", load(SRC + "splat_b.png"))
	m.set_shader_parameter("shore_tex", load(SRC + "shore.png"))
	m.set_shader_parameter("ground_tex", ground_tex)
	m.set_shader_parameter("biome_tex", load(BIOME))
	m.set_shader_parameter("macro_tex", macro)
	m.set_shader_parameter("albedo_arr", load(DIR + "albedo_array.png"))
	m.set_shader_parameter("normal_arr", load(DIR + "normal_array.png"))
	m.set_shader_parameter("mat_arr", load(DIR + "mat_array.png"))
	var tiles := PackedFloat32Array()
	var tints := PackedVector3Array()
	for k in 7:
		tiles.append(1.0 / TILE_M[k])
		tints.append(Vector3(TINTS[k].r, TINTS[k].g, TINTS[k].b))
	m.set_shader_parameter("inv_tile", tiles)
	m.set_shader_parameter("tints", tints)
	_make_chunks()
	_make_water(fog_tex)


func _load_heights() -> void:
	var f := FileAccess.open(DIR + "height_f32.bin", FileAccess.READ)
	if f == null:
		push_error("RtsTerrain: cannot open height_f32.bin (export include_filter?)")
		heights.resize(n_side * n_side)
		heights.fill(1.0)
	else:
		heights = f.get_buffer(n_side * n_side * 4).to_float32_array()
	var img := Image.create_from_data(
		n_side, n_side, false, Image.FORMAT_RF, heights.to_byte_array()
	)
	height_tex = ImageTexture.create_from_image(img)


## Bilinear terrain height at world x, z (clamped to the map).
func height_at(x: float, z: float) -> float:
	var inv: float = 1.0 / SpikeConfig.HEIGHT_SPACING
	var fx: float = clampf(x * inv, 0.0, n_side - 1.001)
	var fz: float = clampf(z * inv, 0.0, n_side - 1.001)
	var i: int = int(fx)
	var j: int = int(fz)
	var tx: float = fx - i
	var tz: float = fz - j
	var k: int = j * n_side + i
	var a: float = lerpf(heights[k], heights[k + 1], tx)
	var b: float = lerpf(heights[k + n_side], heights[k + n_side + 1], tx)
	return lerpf(a, b, tz)


## Ground normal at x, z from the height samples 1 m apart.
func normal_at(x: float, z: float) -> Vector3:
	var hl: float = height_at(x - 1.0, z)
	var hr: float = height_at(x + 1.0, z)
	var hd: float = height_at(x, z - 1.0)
	var hu: float = height_at(x, z + 1.0)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


func _make_nav() -> void:
	var n: int = SpikeConfig.NAV_CELLS
	var c: float = SpikeConfig.NAV_CELL_M
	var centre := PackedFloat32Array()
	centre.resize(n * n)
	for j in n:
		for i in n:
			centre[j * n + i] = height_at((i + 0.5) * c, (j + 0.5) * c)
	blocked.resize(n * n)
	for j in n:
		for i in n:
			var k: int = j * n + i
			var h: float = centre[k]
			var bad: bool = h < SpikeConfig.NAV_MIN_HEIGHT
			if not bad and i + 1 < n:
				bad = absf(centre[k + 1] - h) > SpikeConfig.NAV_MAX_STEP
			if not bad and j + 1 < n:
				bad = absf(centre[k + n] - h) > SpikeConfig.NAV_MAX_STEP
			if not bad and i > 0:
				bad = absf(centre[k - 1] - h) > SpikeConfig.NAV_MAX_STEP
			if not bad and j > 0:
				bad = absf(centre[k - n] - h) > SpikeConfig.NAV_MAX_STEP
			blocked[k] = 1 if bad else 0


func cell_of(p: Vector2) -> int:
	var n: int = SpikeConfig.NAV_CELLS
	var i: int = clampi(int(p.x / SpikeConfig.NAV_CELL_M), 0, n - 1)
	var j: int = clampi(int(p.y / SpikeConfig.NAV_CELL_M), 0, n - 1)
	return j * n + i


func is_blocked_at(p: Vector2) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= SpikeConfig.MAP_SIZE or p.y >= SpikeConfig.MAP_SIZE:
		return true
	return blocked[cell_of(p)] == 1


## Nearest walkable cell centre to p (spiral search), or p itself when it is walkable.
func nearest_walkable(p: Vector2) -> Vector2:
	if not is_blocked_at(p):
		return p
	var n: int = SpikeConfig.NAV_CELLS
	var c: float = SpikeConfig.NAV_CELL_M
	var ci: int = clampi(int(p.x / c), 0, n - 1)
	var cj: int = clampi(int(p.y / c), 0, n - 1)
	for r in range(1, n):
		var best: Vector2 = Vector2.INF
		var best_d: float = INF
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var i: int = ci + di
				var j: int = cj + dj
				if i < 0 or j < 0 or i >= n or j >= n or blocked[j * n + i] == 1:
					continue
				var q := Vector2((i + 0.5) * c, (j + 0.5) * c)
				var d: float = q.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = q
		if best_d < INF:
			return best
	return p


## First hit of a camera ray with the terrain (or the lake surface), by marching then bisecting.
func ray_hit(origin: Vector3, dir: Vector3) -> Vector3:
	var t: float = 0.0
	var prev: float = 0.0
	var step: float = 1.0
	while t < 600.0:
		var p: Vector3 = origin + dir * t
		var ground: float = maxf(height_at(p.x, p.z), SpikeConfig.WATER_LEVEL)
		if p.y <= ground:
			var lo: float = prev
			var hi: float = t
			for _k in 12:
				var mid: float = (lo + hi) * 0.5
				var q: Vector3 = origin + dir * mid
				if q.y <= maxf(height_at(q.x, q.z), SpikeConfig.WATER_LEVEL):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
		t += step
	return Vector3.INF


# --- runtime ground marks (contact occlusion, trampled floors) ---


## Darkens a soft disc of radius r (m) at x, z: `strength` 0..1 at the centre.
func stamp_contact(x: float, z: float, r: float, strength: float) -> void:
	_stamp(x, z, r, 0, strength, true)


## Tramples a noisy disc of radius r (m) at x, z toward red earth (DESIGN 7.2 camp floors).
func stamp_trample(x: float, z: float, r: float) -> void:
	_stamp(x, z, r, 1, 1.0, false)


func commit_ground() -> void:
	ground_tex.update(ground_image)


func _stamp(x: float, z: float, r: float, ch: int, strength: float, darken: bool) -> void:
	var r_px: int = int(ceilf(r)) + 1
	var cx: int = int(x)
	var cz: int = int(z)
	for j in range(maxi(cz - r_px, 0), mini(cz + r_px + 1, 512)):
		for i in range(maxi(cx - r_px, 0), mini(cx + r_px + 1, 512)):
			var d: float = Vector2(i + 0.5 - x, j + 0.5 - z).length() / r
			if d >= 1.0:
				continue
			var wobble: float = 0.0 if darken else 0.18 * sin(float(i) * 1.7 + float(j) * 2.3)
			var k: float = clampf((1.0 - d + wobble) * 1.6, 0.0, 1.0) * strength
			var c: Color = ground_image.get_pixel(i, j)
			if ch == 0:
				c.r = minf(c.r, 1.0 - k)
			else:
				c.g = maxf(c.g, k)
			ground_image.set_pixel(i, j, c)


# --- meshes ---


## 8 x 8 chunks of one shared flat 64 m grid (1 m quads); the shader adds the height.
func _make_chunks() -> void:
	var size: float = SpikeConfig.MAP_SIZE / CHUNKS
	var quads: int = int(size / SpikeConfig.TERRAIN_STEP)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = quads - 1
	plane.subdivide_depth = quads - 1
	plane.center_offset = Vector3(size * 0.5, 0.0, size * 0.5)
	plane.custom_aabb = AABB(Vector3(0.0, -8.0, 0.0), Vector3(size, 24.0, size))
	for cj in CHUNKS:
		for ci in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = plane
			mi.position = Vector3(ci * size, 0.0, cj * size)
			mi.material_override = terrain_mat
			# no terrain shadow pass: the x3 relief is gentle (14 m over 512 m) and casting doubled the
			# draw calls (64 chunks x 2 splits, ~40 draws and ~250k triangles measured 2026-10-11)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


func _make_water(fog_tex: Texture2D) -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("fog_tex", fog_tex)
	water_mat.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)
	water_mat.set_shader_parameter("shore_tex", load(SRC + "shore.png"))
	for k in 2:
		var nt := NoiseTexture2D.new()
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0 if k == 0 else 4.0
		var fn := FastNoiseLite.new()
		fn.seed = 11 + k
		fn.frequency = 0.02 if k == 0 else 0.035
		fn.fractal_octaves = 4
		nt.noise = fn
		water_mat.set_shader_parameter("wave_a" if k == 0 else "wave_b", nt)
	var foam := NoiseTexture2D.new()
	foam.width = 256
	foam.height = 256
	foam.seamless = true
	var ffn := FastNoiseLite.new()
	ffn.frequency = 0.05
	ffn.fractal_octaves = 3
	foam.noise = ffn
	water_mat.set_shader_parameter("foam_noise", foam)
	# the lake covers the east of the map (water.png: x >= 339.5 m) and runs on past the map edge
	# to the horizon (Lake Turkana is 30 km wide), so no map edge shows from the intro or far zoom
	var plane := PlaneMesh.new()
	plane.size = Vector2(9000.0, 9000.0)
	var water := MeshInstance3D.new()
	water.name = "Lake"
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(330.0 + 4500.0, SpikeConfig.WATER_LEVEL, SpikeConfig.MAP_SIZE * 0.5)
	add_child(water)
