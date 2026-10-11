class_name RtsTerrain
extends Node3D

## Placeholder map: 512 x 512 m of noise hills, two steep ridges (pathfinding obstacles) and a
## lake basin on the west side, plus the 128 x 128 navigation grid (4 m cells).
## Procedural on purpose: the real map (Copernicus GLO-30, West Turkana) comes later via the
## Wayfarer DEM pipeline; noise needs no data licence or credit line.

const GRASS := Color(0.55, 0.47, 0.26)
const GREEN := Color(0.26, 0.36, 0.15)
const SAND := Color(0.7, 0.62, 0.46)
const MUD := Color(0.33, 0.31, 0.24)
const ROCK := Color(0.47, 0.42, 0.38)
## Terrain mesh split per side (8 x 8 chunks of 64 m).
const CHUNKS: int = 8

var n_side: int = 0
var heights: PackedFloat32Array = PackedFloat32Array()
## 1 = blocked nav cell (water, wet shore or steep).
var blocked: PackedByteArray = PackedByteArray()
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial


func build(fog_tex: Texture2D) -> void:
	n_side = int(SpikeConfig.MAP_SIZE / SpikeConfig.TERRAIN_STEP) + 1
	_make_heights()
	_make_nav()
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("fog_tex", fog_tex)
	terrain_mat.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)
	_make_chunks()
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	water_mat.set_shader_parameter("fog_tex", fog_tex)
	water_mat.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(SpikeConfig.MAP_SIZE, SpikeConfig.MAP_SIZE)
	var water := MeshInstance3D.new()
	water.name = "Lake"
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(
		SpikeConfig.MAP_SIZE * 0.5, SpikeConfig.WATER_LEVEL, SpikeConfig.MAP_SIZE * 0.5
	)
	add_child(water)


func _make_heights() -> void:
	var hills := FastNoiseLite.new()
	hills.seed = SpikeConfig.TERRAIN_SEED
	hills.frequency = 0.006
	hills.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = SpikeConfig.TERRAIN_SEED + 1
	ridge.frequency = 0.004
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 2
	var shore := FastNoiseLite.new()
	shore.seed = SpikeConfig.TERRAIN_SEED + 2
	shore.frequency = 0.012
	heights.resize(n_side * n_side)
	var step: float = SpikeConfig.TERRAIN_STEP
	for j in n_side:
		for i in n_side:
			var x: float = i * step
			var z: float = j * step
			var h: float = 9.0 + 7.0 * hills.get_noise_2d(x, z)
			var r: float = ridge.get_noise_2d(x, z)
			h += 14.0 * clampf((r - 0.55) / 0.3, 0.0, 1.0)
			var d: float = Vector2(x, z).distance_to(SpikeConfig.LAKE_CENTRE)
			var rad: float = SpikeConfig.LAKE_RADIUS + 28.0 * shore.get_noise_2d(x, z)
			var t: float = smoothstep(rad + 45.0, rad - 15.0, d)
			h = lerpf(h, -5.0, t)
			heights[j * n_side + i] = h


## Bilinear terrain height at world x, z (clamped to the map).
func height_at(x: float, z: float) -> float:
	var step: float = SpikeConfig.TERRAIN_STEP
	var fx: float = clampf(x / step, 0.0, n_side - 1.001)
	var fz: float = clampf(z / step, 0.0, n_side - 1.001)
	var i: int = int(fx)
	var j: int = int(fz)
	var tx: float = fx - i
	var tz: float = fz - j
	var k: int = j * n_side + i
	var a: float = lerpf(heights[k], heights[k + 1], tx)
	var b: float = lerpf(heights[k + n_side], heights[k + n_side + 1], tx)
	return lerpf(a, b, tz)


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


## Terrain as CHUNKS x CHUNKS meshes so the camera and the shadow pass cull what they do not
## see. Chunks cast shadows: without that, unit shadows fall through ridges onto the ground
## behind them (seen in the 2026-10-11 capture).
func _make_chunks() -> void:
	var per: int = int((n_side - 1) / float(CHUNKS))
	for cj in CHUNKS:
		for ci in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = _make_mesh(ci * per, cj * per, per + 1)
			mi.material_override = terrain_mat
			add_child(mi)


func _make_mesh(i0: int, j0: int, n: int) -> ArrayMesh:
	var step: float = SpikeConfig.TERRAIN_STEP
	var tint := FastNoiseLite.new()
	tint.seed = SpikeConfig.TERRAIN_SEED + 3
	tint.frequency = 0.02
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colours.resize(n * n)
	var ns: int = n_side
	for lj in n:
		for li in n:
			var k: int = lj * n + li
			var i: int = i0 + li
			var j: int = j0 + lj
			var h: float = heights[j * ns + i]
			verts[k] = Vector3(i * step, h, j * step)
			var hl: float = heights[j * ns + maxi(i - 1, 0)]
			var hr: float = heights[j * ns + mini(i + 1, ns - 1)]
			var hd: float = heights[maxi(j - 1, 0) * ns + i]
			var hu: float = heights[mini(j + 1, ns - 1) * ns + i]
			var nrm := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			normals[k] = nrm
			colours[k] = _ground_colour(h, nrm.y, tint.get_noise_2d(i * step, j * step))
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var w: int = 0
	for j in n - 1:
		for i in n - 1:
			var a: int = j * n + i
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			idx[w] = a
			idx[w + 1] = b
			idx[w + 2] = c
			idx[w + 3] = b
			idx[w + 4] = d
			idx[w + 5] = c
			w += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ground_colour(h: float, up: float, n: float) -> Color:
	# savanna mosaic: dry grass and greener patches from the tint noise
	var col: Color = GRASS.lerp(GREEN, clampf(0.5 + 1.4 * n, 0.0, 1.0) * 0.75)
	# greener, wetter ground close to the lake
	col = col.lerp(GREEN, clampf(1.0 - (h - 1.0) / 4.0, 0.0, 1.0) * 0.7)
	if h < 1.2:
		col = col.lerp(SAND, clampf((1.2 - h) / 0.8, 0.0, 1.0))
	if h < SpikeConfig.WATER_LEVEL:
		col = SAND.lerp(MUD, clampf(-h / 2.0, 0.0, 1.0))
	col = col.lerp(ROCK, clampf((0.86 - up) / 0.12, 0.0, 1.0))
	return col
