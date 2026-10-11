class_name GrassField
extends MultiMeshInstance3D

## Dense wind-animated grass over the Rift Lake map (shaders/grass.gdshader). One MultiMesh of
## 2 x 2 m patches, each holding BLADES procedural blades, laid on a grid that follows the camera
## (the GPU drops every blade on the terrain and thins it by the biome mask), so the cost is the
## same anywhere on the map and nothing per blade runs on the CPU. `quality` 0..1 scales the blade
## count (Low preset); at high zoom the grid stretches (`spread`) so the field still covers the
## screen while each blade is sub-pixel anyway.
## Reeds use the same shader with tall green blades (`make_reeds`, biome A at the waterline).

const PATCH_M: float = 2.0
const BLADES: int = 360
## Field size in patches (x, z): 76 x 68 m at spread 1.
const COLS: int = 38
const ROWS: int = 34
## Field centre sits this far north (-z) of the camera focus: the steep view sees more ground
## ahead of the focus than behind it.
const AHEAD_M: float = 12.0

var _mat: ShaderMaterial
var _cam: RtsCamera
var _quality: float = -1.0
var _reeds: bool = false


## A field added to `parent`, bound to the terrain and the biome mask; `reeds` = the reed beds.
static func create(
	parent: Node, terrain: RtsTerrain, fog_tex: Texture2D, reeds: bool
) -> GrassField:
	var g := GrassField.new()
	parent.add_child(g)
	g.setup(terrain, load(RtsTerrain.BIOME), fog_tex, 1.0)
	if reeds:
		g.make_reeds()
	return g


## `terrain` supplies the height, ground and shore textures; `biome` is
## assets/terrain/game/biome.png.
func setup(terrain: RtsTerrain, biome: Texture2D, fog_tex: Texture2D, quality: float) -> void:
	name = "Grass"
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	_bind(terrain, biome, fog_tex)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _patch_for(quality)
	mm.instance_count = COLS * ROWS
	for j in ROWS:
		for i in COLS:
			var o := Vector3((i - COLS * 0.5) * PATCH_M, 0.0, (j - ROWS * 0.5) * PATCH_M)
			mm.set_instance_transform(j * COLS + i, Transform3D(Basis(), o))
	mm.custom_aabb = AABB(Vector3(-400.0, -50.0, -400.0), Vector3(800.0, 100.0, 800.0))
	multimesh = mm
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quality = quality


func _bind(terrain: RtsTerrain, biome: Texture2D, fog_tex: Texture2D) -> void:
	_mat.set_shader_parameter("height_tex", terrain.height_tex)
	_mat.set_shader_parameter("biome_tex", biome)
	_mat.set_shader_parameter("ground_tex", terrain.ground_tex)
	_mat.set_shader_parameter("shore_tex", load(RtsTerrain.SRC + "shore.png"))
	_mat.set_shader_parameter("splat_a", load(RtsTerrain.SRC + "splat_a.png"))
	_mat.set_shader_parameter("fog_tex", fog_tex)
	_mat.set_shader_parameter("map_size", SpikeConfig.MAP_SIZE)


## Share of blades drawn (1 = High, Low draws about a third): a patch mesh with fewer blades, so
## Low also saves the vertex work, not only the pixels.
func set_quality(q: float) -> void:
	if multimesh != null and not is_equal_approx(q, _quality):
		_quality = q
		multimesh.mesh = _patch_for(q)
	_quality = q


func _patch_for(q: float) -> ArrayMesh:
	if _reeds:
		return _reed_patch(q)
	return _grass_patch(q)


static func _grass_patch(q: float) -> ArrayMesh:
	var n: int = int(BLADES * clampf(q, 0.1, 1.0))
	return _blade_patch(n, Vector2(0.038, 0.075), Vector2(0.22, 0.55), 0.3, 7, 3)


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
	_reeds = true
	_mat.set_shader_parameter("reeds", true)
	_mat.set_shader_parameter("wind_strength", 0.2)
	multimesh.mesh = _patch_for(_quality)


static func _reed_patch(q: float) -> ArrayMesh:
	var n: int = int(220 * clampf(q, 0.3, 1.0))
	return _blade_patch(n, Vector2(0.03, 0.05), Vector2(1.1, 2.2), 0.18, 11, 14)
