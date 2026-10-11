class_name Dressing
extends Node3D

## Vegetation and ground cover over the Rift Lake map (DESIGN 7.3, 7.5), all MultiMesh:
## acacias (veg.png R), doum palms (G), grass tussocks (B), shore sedge (A), shrubs, boulders,
## cobble pavement. Instances are grouped in 64 m chunks so the camera culls them and each
## chunk's mesh LOD follows its distance; grass and cobbles stop at 60-70 m (DESIGN 7.3).
## Every tree, shrub and boulder stamps contact occlusion into the terrain's ground mask
## (the stand-in for the baked lightmap; LightmapGI cannot bake MultiMesh instances).
## clear_area() removes ground cover under a new building.

## Ground cover chunks (grass, cobbles): small, so the 60-70 m range culls per chunk.
const CHUNK_M: float = 64.0
## Trees, shrubs, boulders: bigger chunks, fewer draw calls (each multi-surface model costs one
## draw per surface per chunk).
const BIG_CHUNK_M: float = 128.0
const SEED: int = 20261011
## Per-kind density, spacing and size (metres). Densities are probabilities per grid cell.
const GRASS_CELL: float = 3.2
const SHRUB_CELL: float = 4.5
const ACACIA_CELL: float = 9.0
const PALM_CELL: float = 11.0
const COBBLE_CELL: float = 3.2
const BOULDER_CELL: float = 14.0
const GRASS_RANGE: float = 55.0
const COBBLE_RANGE: float = 70.0
const SHRUB_RANGE: float = 140.0
## Sun-cured straw, a shade darker than the ground so each tussock reads by its own shade.
const GRASS_TINT := Color(0.92, 0.80, 0.55)
const SEDGE_TINT := Color(0.85, 1.05, 0.7)
const BASALT_TINT := Color(0.42, 0.38, 0.35)

var terrain: RtsTerrain
var grass_count: int = 0
var tree_count: int = 0
var shrub_count: int = 0
var rock_count: int = 0

var _veg: Image
var _shore: Image
var _splat_a: Image
var _splat_b: Image
var _rng := RandomNumberGenerator.new()
var _excl: Array = []
## grass chunk key -> [MultiMeshInstance3D, Array[Transform3D]] per part, for clear_area()
var _grass_chunks: Dictionary = {}


## `exclusions`: Array of [Vector2 centre, float radius] kept free of trees, shrubs and cover.
func build(t: RtsTerrain, exclusions: Array) -> void:
	terrain = t
	_excl = exclusions
	_rng.seed = SEED
	_veg = _img("res://assets/terrain/rift_lake/veg.png")
	_shore = _img("res://assets/terrain/rift_lake/shore.png")
	_splat_a = _img("res://assets/terrain/rift_lake/splat_a.png")
	_splat_b = _img("res://assets/terrain/rift_lake/splat_b.png")
	_trees()
	_shrubs()
	_grass()
	_rocks()
	terrain.commit_ground()


static func _img(path: String) -> Image:
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	return img


func _sample(img: Image, x: float, z: float) -> Color:
	return img.get_pixel(clampi(int(x * 2.0), 0, 1024), clampi(int(z * 2.0), 0, 1024))


## Metres to the waterline (0 on the line, 40 = 40 m or more).
func shore_m(x: float, z: float) -> float:
	return _sample(_shore, x, z).r * 40.0


func _free(p: Vector2, margin: float) -> bool:
	for e: Array in _excl:
		var c: Vector2 = e[0]
		if p.distance_to(c) < float(e[1]) + margin:
			return false
	return true


## Jittered grid over the map: yields points (x, z) with the cell's random jitter.
func _grid(cell: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = int(SpikeConfig.MAP_SIZE / cell)
	for j in n:
		for i in n:
			out.append(
				Vector2(
					(i + _rng.randf_range(0.1, 0.9)) * cell, (j + _rng.randf_range(0.1, 0.9)) * cell
				)
			)
	return out


func _on_land(p: Vector2, min_h: float) -> bool:
	return terrain.height_at(p.x, p.y) > min_h


func _xf(p: Vector2, scale: float, sink: float, tilt: float = 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale, scale))
	if tilt > 0.0:
		var n: Vector3 = terrain.normal_at(p.x, p.y)
		var axis: Vector3 = Vector3.UP.cross(n)
		if axis.length() > 0.001:
			b = Basis(axis.normalized(), Vector3.UP.angle_to(n) * tilt) * b
	return Transform3D(b, Vector3(p.x, terrain.height_at(p.x, p.y) - sink, p.y))


static func _chunk_key(p: Vector2, size: float) -> int:
	return int(p.y / size) * 16 + int(p.x / size)


## Adds one MultiMesh group per chunk for `model` (opts.big: 128 m chunks).
func _add_chunked(model: String, xfs: Array[Transform3D], opts: Dictionary) -> Array:
	var by: Dictionary = {}
	var size: float = BIG_CHUNK_M if opts.get("big", false) else CHUNK_M
	for xf in xfs:
		var k: int = _chunk_key(Vector2(xf.origin.x, xf.origin.z), size)
		if not by.has(k):
			var arr: Array[Transform3D] = []
			by[k] = arr
		(by[k] as Array[Transform3D]).append(xf)
	var made: Array = []
	for k: int in by:
		var list: Array[Transform3D] = by[k]
		for mmi: MultiMeshInstance3D in ModelLib.make_multimesh(model, list, opts):
			mmi.name = "%s_c%d" % [mmi.name, k]
			add_child(mmi)
			made.append([k, mmi, list])
	return made


func _trees() -> void:
	var acacias: Array[Transform3D] = []
	for p in _grid(ACACIA_CELL):
		var v: Color = _sample(_veg, p.x, p.y)
		if _rng.randf() > v.r * 0.9 + 0.02 or not _on_land(p, 0.9) or not _free(p, 7.0):
			continue
		acacias.append(_xf(p, _rng.randf_range(0.85, 1.2), 0.05))
		terrain.stamp_contact(p.x, p.y, 5.5, 0.35)
	var palms: Array[Transform3D] = []
	for p in _grid(PALM_CELL):
		var v: Color = _sample(_veg, p.x, p.y)
		var sd: float = shore_m(p.x, p.y)
		var band: float = 1.0 if sd > 6.0 and sd < 38.0 else 0.0
		if _rng.randf() > v.g * 0.8 * band or not _on_land(p, 0.6) or not _free(p, 4.0):
			continue
		palms.append(_xf(p, _rng.randf_range(0.75, 1.1), 0.05))
		terrain.stamp_contact(p.x, p.y, 2.5, 0.3)
	tree_count = acacias.size() + palms.size()
	_add_chunked("acacia", acacias, {"big": true})
	# Mexican fan palm stand-in: bleached trunk and lawn-green fronds pulled toward doum_green
	_add_chunked(
		"doum_palm", palms, {"big": true, "tint": Color(0.78, 0.76, 0.6), "saturation": 0.75}
	)


func _shrubs() -> void:
	var searsia: Array[Transform3D] = []
	var leafy: Array[Transform3D] = []
	for p in _grid(SHRUB_CELL):
		var v: Color = _sample(_veg, p.x, p.y)
		if _rng.randf() > v.r * 0.55 + 0.05 or not _on_land(p, 0.5) or not _free(p, 2.5):
			continue
		if _rng.randf() < 0.75:
			searsia.append(_xf(p, _rng.randf_range(0.5, 1.05), 0.03))
		else:
			leafy.append(_xf(p, _rng.randf_range(0.6, 0.95), 0.03))
		terrain.stamp_contact(p.x, p.y, 1.4, 0.3)
	shrub_count = searsia.size() + leafy.size()
	# shrubs cast no shadow: their contact occlusion is stamped into the ground instead, and the
	# shadow pass would double their draw calls (budget < 150, DESIGN 7.9)
	_add_chunked("shrub_searsia", searsia, {"vis_end": SHRUB_RANGE, "big": true, "shadow": false})
	_add_chunked("shrub_leafy", leafy, {"vis_end": SHRUB_RANGE, "big": true, "shadow": false})


func _grass() -> void:
	# Tussocks (DESIGN 7.3): each instance is 2-3 Poly Haven clumps merged into one mesh (~1.4-1.9k
	# tris), two variants, so the plain reads as tussock grass from RTS height; single wispy
	# clumps vanished at 50 m (capture 2026-10-11).
	_make_tussocks()
	var by_part: Array = [[], []]
	var sedge: Array[Transform3D] = []
	for p in _grid(GRASS_CELL):
		if not _on_land(p, 0.25) or not _free(p, 0.0):
			continue
		var v: Color = _sample(_veg, p.x, p.y)
		var sd: float = shore_m(p.x, p.y)
		if sd < 6.0 and _rng.randf() < v.a * 0.9:
			sedge.append(_xf(p, _rng.randf_range(1.0, 1.6), 0.02, 0.6))
			continue
		if sd < 3.0 or _rng.randf() > v.b * 0.8 + 0.1:
			continue
		var k: int = _rng.randi_range(0, 1)
		(by_part[k] as Array).append(_xf(p, _rng.randf_range(1.2, 2.0), 0.02, 0.6))
	var opts := {
		"tint": GRASS_TINT,
		"saturation": 0.6,
		"shadow": false,
		"leaf": true,
		"vis_end": GRASS_RANGE + 20.0,
	}
	for k in 2:
		var list: Array[Transform3D] = []
		list.assign(by_part[k])
		grass_count += list.size()
		for e: Array in _add_chunked("tussock_%d" % k, list, opts):
			_grass_chunks["%d_%d" % [k, e[0]]] = [e[1], e[2]]
	var so := {
		"tint": SEDGE_TINT, "shadow": false, "leaf": true, "vis_end": GRASS_RANGE + 40.0, "part": 4
	}
	_add_chunked("grass", sedge, so)
	grass_count += sedge.size()


func _make_tussocks() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 404
	# clumps a-e grow from 0.17 m to 0.45 m tall; only d and e read from RTS height
	var recipes: Array = [[4, 3], [3, 4, 3]]
	for k in 2:
		var which: Array[int] = []
		which.assign(recipes[k])
		var xfs: Array[Transform3D] = []
		for j in which.size():
			var a: float = TAU * j / which.size() + r.randf() * 0.8
			var off := Vector3(cos(a), 0.0, sin(a)) * 0.16
			var s: float = r.randf_range(0.8, 1.15)
			# the Poly Haven clumps sit side by side in their file: centre each before placing
			var c: Vector3 = (
				((ModelLib.parts("grass")[which[j]] as Dictionary)["mesh"] as Mesh)
				. get_aabb()
				. get_center()
			)
			var place := Transform3D(
				Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s), off
			)
			xfs.append(place * Transform3D(Basis(), -Vector3(c.x, 0.0, c.z)))
		ModelLib.register("tussock_%d" % k, ModelLib.merge_parts("grass", which, xfs))


func _rocks() -> void:
	var cob: Array[Transform3D] = []
	var stn: Array[Transform3D] = []
	for p in _grid(COBBLE_CELL):
		if not _on_land(p, 0.4) or not _free(p, 1.0) or shore_m(p.x, p.y) < 3.0:
			continue
		var a: Color = _sample(_splat_a, p.x, p.y)
		var b: Color = _sample(_splat_b, p.x, p.y)
		var want: float = 0.08 + 0.6 * b.g + 0.4 * a.b
		if _rng.randf() > want:
			continue
		if _rng.randf() < 0.5:
			cob.append(_xf(p, _rng.randf_range(0.7, 1.3), 0.03, 1.0))
		else:
			stn.append(_xf(p, _rng.randf_range(0.8, 1.5), 0.02, 1.0))
	var boulders: Array = [[], [], []]
	for p in _grid(BOULDER_CELL):
		var a: Color = _sample(_splat_a, p.x, p.y)
		if _rng.randf() > 0.12 + a.b * 0.6 or not _on_land(p, 0.5) or not _free(p, 3.0):
			continue
		var s: float = _rng.randf_range(0.35, 0.9)
		(boulders[_rng.randi_range(0, 2)] as Array).append(_xf(p, s, 0.25 * s, 0.5))
		terrain.stamp_contact(p.x, p.y, 1.6 * s, 0.5)
	var ro := {"tint": BASALT_TINT, "saturation": 0.5, "big": true}
	var co: Dictionary = ro.duplicate()
	co.erase("big")
	co["shadow"] = false
	co["vis_end"] = COBBLE_RANGE
	_add_chunked("cobbles", cob, co)
	_add_chunked("stones", stn, co)
	var names: Array[String] = ["boulder_a", "boulder_b", "boulder_c"]
	for k in 3:
		var list: Array[Transform3D] = []
		list.assign(boulders[k])
		rock_count += list.size()
		_add_chunked(names[k], list, ro)
	rock_count += cob.size() + stn.size()


## Hides grass in a disc (new building floor). Rebuilds only the touched chunks.
func clear_area(c: Vector2, r: float) -> void:
	var r2: float = r * r
	for key: String in _grass_chunks:
		var e: Array = _grass_chunks[key]
		var mmi: MultiMeshInstance3D = e[0]
		var list: Array[Transform3D] = e[1]
		var mm: MultiMesh = mmi.multimesh
		for i in list.size():
			var o: Vector3 = list[i].origin
			if Vector2(o.x - c.x, o.z - c.y).length_squared() < r2:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), o))
	_excl.append([c, r])
