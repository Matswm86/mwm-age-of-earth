class_name GrassField
extends Node3D

## Dense wind-animated grass over the Rift Lake map (shaders/grass.gdshader). 2 x 2 m patches,
## each holding BLADES procedural blades, laid on a grid that follows the camera (the GPU drops
## every blade on the terrain and thins it by the biome mask), so the cost is the same anywhere on
## the map and nothing per blade runs on the CPU. The grid is split into CHUNK x CHUNK patch
## MultiMeshes so the camera culls the off-screen part (one MultiMesh drew the whole 76 x 68 m
## field, ~80 % of it off screen at the default camera: 1.4M triangles, 2026-10-11 phone pass);
## chunks beyond the focus draw a sparser patch (FAR_SHARE of the blades, wider), and chunks with no
## ground for grass (lake) or no reed bed are skipped (coarse mask built once in setup).
## `quality` 0..1 scales the blade count (Low preset); at high zoom the grid stretches (`spread`)
## so the field still covers the screen while each blade is sub-pixel anyway.
## Reeds use the same shader with tall green blades (`make_reeds`, biome A at the waterline).

const PATCH_M: float = 2.0
const BLADES: int = 290
## Field size in patches (x, z): 76 x 68 m at spread 1.
const COLS: int = 38
const ROWS: int = 34
## Field centre sits this far north (-z) of the camera focus: the steep view sees more ground
## ahead of the focus than behind it.
const AHEAD_M: float = 12.0
## Patches per chunk side (16 m chunks: 25 chunks, ~8-10 on screen at the default camera).
const CHUNK: int = 8
## Share of the blades in the far patch (beyond the camera focus), drawn wider.
const FAR_SHARE: float = 0.4
## Chunks closer to the camera than this x the focus distance draw the full patch.
const NEAR_K: float = 1.05
## Coarse ground mask: 8 m cells over the map (land for grass, reed bed for reeds).
const MASK_M: float = 8.0
const MASK_N: int = 64

var _mat: ShaderMaterial
var _cam: RtsCamera
var _quality: float = -1.0
var _reeds: bool = false
var _near_mesh: ArrayMesh
var _far_mesh: ArrayMesh
## per chunk: [MultiMeshInstance3D, Vector2 patch-offset min (m), Vector2 max (m), far: bool,
## ground: bool (something can grow under it)]
var _chunks: Array = []
## 1 where grass (or reeds, for the reed field) can grow somewhere in the 8 m cell
var _mask := PackedByteArray()
var _last_c := Vector2.INF
var _last_spread: float = -1.0


## A field added to `parent`, bound to the terrain and the biome mask; `reeds` = the reed beds.
static func create(
	parent: Node, terrain: RtsTerrain, fog_tex: Texture2D, reeds: bool
) -> GrassField:
	var g := GrassField.new()
	parent.add_child(g)
	g._reeds = reeds
	g.setup(terrain, load(RtsTerrain.BIOME), fog_tex, 1.0)
	if reeds:
		g.make_reeds()
	return g


## `terrain` supplies the height, ground and shore textures; `biome` is
## assets/terrain/game/biome.png.
func setup(terrain: RtsTerrain, biome: Texture2D, fog_tex: Texture2D, quality: float) -> void:
	name = "Reeds" if _reeds else "Grass"
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	_bind(terrain, biome, fog_tex)
	_build_mask(terrain, biome)
	_quality = quality
	_near_mesh = _patch_for(quality, false)
	_far_mesh = _patch_for(quality, true)
	for cj in range(0, ROWS, CHUNK):
		for ci in range(0, COLS, CHUNK):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _near_mesh
			var nj: int = mini(CHUNK, ROWS - cj)
			var ni: int = mini(CHUNK, COLS - ci)
			mm.instance_count = ni * nj
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for j in nj:
				for i in ni:
					var o := Vector3(
						(ci + i - COLS * 0.5) * PATCH_M, 0.0, (cj + j - ROWS * 0.5) * PATCH_M
					)
					mm.set_instance_transform(j * ni + i, Transform3D(Basis(), o))
					lo = lo.min(Vector2(o.x, o.z) - Vector2.ONE * PATCH_M * 0.5)
					hi = hi.max(Vector2(o.x, o.z) + Vector2.ONE * PATCH_M * 0.5)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Chunk_%d_%d" % [ci / CHUNK, cj / CHUNK]
			mmi.multimesh = mm
			mmi.material_override = _mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_chunks.append([mmi, lo, hi, false, true])
	_set_spread(1.0)


func _bind(terrain: RtsTerrain, biome: Texture2D, fog_tex: Texture2D) -> void:
	_mat.set_shader_parameter("height_tex", terrain.height_tex)
	_mat.set_shader_parameter("biome_tex", biome)
	_mat.set_shader_parameter("ground_tex", terrain.ground_tex)
	_mat.set_shader_parameter("shore_tex", load(RtsTerrain.SRC + "shore.png"))
	_mat.set_shader_parameter("splat_a", load(RtsTerrain.SRC + "splat_a.png"))
	_mat.set_shader_parameter("fog_tex", fog_tex)
	_mat.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)


## 8 m cells where blades can stand: grass on land above the waterline, reeds where the biome
## has a reed bed (A) within 0.6 m of the water level. Sampled every 2 m.
func _build_mask(terrain: RtsTerrain, biome: Texture2D) -> void:
	var img: Image = biome.get_image()
	if img.is_compressed():
		img.decompress()
	var bw: float = img.get_width() / SpikeConfig.MAP_SIZE
	_mask.resize(MASK_N * MASK_N)
	_mask.fill(0)
	for cz in MASK_N:
		for cx in MASK_N:
			var ok: bool = false
			for sz in 5:
				for sx in 5:
					var x: float = cx * MASK_M + sx * 2.0
					var z: float = cz * MASK_M + sz * 2.0
					var h: float = terrain.height_at(x, z)
					if _reeds:
						var px: int = clampi(int(x * bw), 0, img.get_width() - 1)
						var pz: int = clampi(int(z * bw), 0, img.get_height() - 1)
						var a: float = img.get_pixel(px, pz).a
						ok = a > 0.08 and h > SpikeConfig.WATER_LEVEL - 0.7 and h < 1.3
					else:
						ok = h > SpikeConfig.WATER_LEVEL + 0.03
					if ok:
						break
				if ok:
					break
			_mask[cz * MASK_N + cx] = 1 if ok else 0


## Share of blades drawn (1 = High, Low draws about a third): patch meshes with fewer blades, so
## Low also saves the vertex work, not only the pixels.
func set_quality(q: float) -> void:
	if not is_equal_approx(q, _quality):
		_quality = q
		_near_mesh = _patch_for(q, false)
		_far_mesh = _patch_for(q, true)
		for ch: Array in _chunks:
			(ch[0] as MultiMeshInstance3D).multimesh.mesh = _far_mesh if ch[3] else _near_mesh
	_quality = q


func _patch_for(q: float, far: bool) -> ArrayMesh:
	if _reeds:
		return _reed_patch(q * (FAR_SHARE if far else 1.0), far)
	return _grass_patch(q * (FAR_SHARE if far else 1.0), far)


static func _grass_patch(q: float, far: bool = false) -> ArrayMesh:
	var n: int = int(BLADES * clampf(q, 0.1, 1.0))
	# blades 12 % wider than the 360-blade patch of the look pass, so the sward covers the same
	var w: float = 1.5 if far else 1.12
	return _blade_patch(n, Vector2(0.038, 0.075) * w, Vector2(0.22, 0.55), 0.3, 7, 3)


func follow(cam: RtsCamera) -> void:
	_cam = cam
	set_process(true)


func _process(_delta: float) -> void:
	if _cam == null:
		return
	# spread 1 up to ~26 m camera height, then stretch so the 92 m field covers the wider view
	var spread: float = maxf(1.0, _cam.height / 22.0)
	var step: float = PATCH_M * spread
	var c: Vector2 = _cam.focus + Vector2(0.0, -AHEAD_M * spread)
	# snap to the patch grid so blades never slide under the camera
	c = (c / step).round() * step
	position = Vector3(c.x, 0.0, c.y)
	_mat.set_shader_parameter("centre", c)
	_mat.set_shader_parameter("spread", spread)
	var dist: float = _cam.height / sin(deg_to_rad(_cam.tilt_deg()))
	var reach: float = 1.0 if _quality > 0.5 else 0.6
	_mat.set_shader_parameter("fade_start", (dist * 1.05 + 4.0) * reach)
	_mat.set_shader_parameter("fade_end", (dist * 1.05 + 18.0 * spread) * reach)
	if not is_equal_approx(spread, _last_spread):
		_set_spread(spread)
	if c != _last_c or not is_equal_approx(spread, _last_spread):
		_last_c = c
		_last_spread = spread
		_update_chunks(c, spread)
	_update_lod(c, spread, dist, (dist * 1.05 + 18.0 * spread) * reach)


## Chunk bounds for the stretched grid (the shader scales offsets from the centre by `spread`).
func _set_spread(spread: float) -> void:
	for ch: Array in _chunks:
		var lo: Vector2 = ch[1]
		var hi: Vector2 = ch[2]
		var a: Vector2 = lo * spread - Vector2.ONE
		var b: Vector2 = hi * spread + Vector2.ONE
		(ch[0] as MultiMeshInstance3D).custom_aabb = AABB(
			Vector3(a.x, -12.0, a.y), Vector3(b.x - a.x, 40.0, b.y - a.y)
		)


## Hides chunks over cells where nothing can grow (open lake; no reed bed for the reed field).
func _update_chunks(c: Vector2, spread: float) -> void:
	for ch: Array in _chunks:
		var lo: Vector2 = c + (ch[1] as Vector2) * spread
		var hi: Vector2 = c + (ch[2] as Vector2) * spread
		var x0: int = clampi(int(floorf(lo.x / MASK_M)), 0, MASK_N - 1)
		var x1: int = clampi(int(floorf(hi.x / MASK_M)), 0, MASK_N - 1)
		var z0: int = clampi(int(floorf(lo.y / MASK_M)), 0, MASK_N - 1)
		var z1: int = clampi(int(floorf(hi.y / MASK_M)), 0, MASK_N - 1)
		var any: bool = false
		var off_map: bool = (
			hi.x < 0.0 or hi.y < 0.0 or lo.x > SpikeConfig.MAP_SIZE or lo.y > SpikeConfig.MAP_SIZE
		)
		if not off_map:
			for z in range(z0, z1 + 1):
				for x in range(x0, x1 + 1):
					if _mask[z * MASK_N + x] == 1:
						any = true
						break
				if any:
					break
		ch[4] = any


## Full patch for chunks nearer than the focus (x NEAR_K), the sparse one beyond; chunks past the
## fade end (every blade there is shrunk to nothing) or over bare ground are hidden.
func _update_lod(c: Vector2, spread: float, focus_dist: float, fade_end: float) -> void:
	var cam_p: Vector3 = _cam.global_position
	var lim: float = focus_dist * NEAR_K
	for ch: Array in _chunks:
		var mid: Vector2 = c + ((ch[1] as Vector2) + (ch[2] as Vector2)) * 0.5 * spread
		# nearest point of the chunk rectangle to the camera, on the ground plane
		var half: Vector2 = ((ch[2] as Vector2) - (ch[1] as Vector2)) * 0.5 * spread
		var q := Vector2(
			clampf(cam_p.x, mid.x - half.x, mid.x + half.x),
			clampf(cam_p.z, mid.y - half.y, mid.y + half.y)
		)
		var d: float = Vector3(q.x - cam_p.x, cam_p.y, q.y - cam_p.z).length()
		var mmi := ch[0] as MultiMeshInstance3D
		mmi.visible = ch[4] and d < fade_end + 6.0
		var far: bool = d > lim
		if far != ch[3]:
			ch[3] = far
			(ch[0] as MultiMeshInstance3D).multimesh.mesh = _far_mesh if far else _near_mesh


## A 2 x 2 m patch of about `n` curved blades (a segment + a tip each, 3 triangles) grown in
## tussocks: blades
## gather round random clump centres and lean outward, so the sward reads as bunch grass, not
## lawn. COLOR r, g = blade randoms, b = 0 at the root .. 1 at the tip. Heights in metres.
static func _blade_patch(
	n: int, width: Vector2, height: Vector2, lean: float, seed: int, per_clump: int = 12
) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clumps: int = maxi(n / per_clump, 1)
	for cl in clumps:
		var cc := Vector3(rng.randf() * PATCH_M, 0.0, rng.randf() * PATCH_M)
		var cr: float = rng.randf_range(0.04, 0.12)
		var ch: float = rng.randf_range(height.x, height.y)
		var cr1: float = rng.randf()
		for b in per_clump:
			var a: float = rng.randf() * TAU
			var rr: float = sqrt(rng.randf()) * cr
			var off := Vector3(cos(a), 0.0, sin(a)) * rr
			var p: Vector3 = cc + off
			p.x = fposmod(p.x, PATCH_M)
			p.z = fposmod(p.z, PATCH_M)
			var yaw: float = rng.randf() * TAU
			var side := Vector3(cos(yaw), 0.0, sin(yaw))
			var face := Vector3(-side.z, 0.0, side.x)
			var w: float = rng.randf_range(width.x, width.y)
			var h: float = ch * rng.randf_range(0.55, 1.15)
			var out: Vector3 = (off / maxf(cr, 0.01)) if rr > 0.001 else face
			var lean_v: Vector3 = (out * lean + face * rng.randf_range(-0.5, 0.5) * lean) * h
			# r: one density random per clump (+ a little per blade) so tussocks thin as a whole
			var r1: float = clampf(cr1 + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
			var r2: float = rng.randf()
			var ring: Array[Vector3] = []
			var tips: Array[float] = []
			for k in 3:
				var t: float = k / 2.0
				var c: Vector3 = p + Vector3(0.0, h * t, 0.0) + lean_v * t * t
				var half: float = w * 0.5 * (1.0 - t * 0.85)
				if k == 2:
					ring.append(c)
					tips.append(t)
				else:
					ring.append(c - side * half)
					ring.append(c + side * half)
					tips.append(t)
					tips.append(t)
			var nrm: Vector3 = (face + Vector3(0.0, 0.3, 0.0)).normalized()
			var idx: Array[int] = [0, 1, 2, 2, 1, 3, 2, 3, 4]
			for i in idx:
				st.set_color(Color(r1, r2, tips[i]))
				st.set_normal(nrm)
				st.set_uv(Vector2(0.5, tips[i]))
				st.add_vertex(ring[i] - Vector3(PATCH_M * 0.5, 0.0, PATCH_M * 0.5))
	st.index()
	return st.commit()


## Reed beds (biome A) at the waterline: the same field with tall, upright green blades.
func make_reeds() -> void:
	name = "Reeds"
	_mat.set_shader_parameter("reeds", true)
	_mat.set_shader_parameter("wind_strength", 0.2)
	if _reeds:
		return
	_reeds = true
	_near_mesh = _patch_for(_quality, false)
	_far_mesh = _patch_for(_quality, true)
	for ch: Array in _chunks:
		(ch[0] as MultiMeshInstance3D).multimesh.mesh = _far_mesh if ch[3] else _near_mesh


static func _reed_patch(q: float, far: bool = false) -> ArrayMesh:
	var n: int = int(220 * clampf(q, 0.3, 1.0))
	var w: float = 1.35 if far else 1.0
	return _blade_patch(n, Vector2(0.03, 0.05) * w, Vector2(1.1, 2.2), 0.18, 11, 14)
