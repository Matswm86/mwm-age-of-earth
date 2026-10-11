class_name ModelLib
extends RefCounted

## Loads the phone-ready models (assets/game_models/*.glb, tools/game/optimize_models.py) and
## turns them into nodes or MultiMesh groups. Every GLB is Z-up in Blender, Y-up here; parts keep
## their transform relative to the scene root. Leaf materials are forced to alpha scissor (source
## cut-off, at most 0.3) with alpha-to-coverage and a back-light wrap (DESIGN 7.5: never
## alpha-blended foliage). Materials are shared per
## (model, tint) so instances batch.

const DIR: String = "res://assets/game_models/"

## Shared grade per model (owner feedback 2026-10-11: consistency beats detail): trees from
## different sources are pulled toward one olive-green crown so they sit in one light. Used when
## the caller passes no tint.
const GRADE: Dictionary = {
	"chinaberry_a": Color(0.74, 0.78, 0.6),
	"home_tree": Color(0.74, 0.8, 0.6),
	"chinaberry_b": Color(0.74, 0.78, 0.6),
	"chinaberry_young": Color(0.78, 0.8, 0.6),
	"poinciana_b": Color(0.76, 0.78, 0.62),
	"acacia": Color(1.0, 1.0, 1.0),
	# Searsia scan leaves are grey-silver: pulled toward the woodland green so the bushes read alive
	"shrub_searsia": Color(0.72, 0.9, 0.55),
	"shrub_leafy": Color(0.8, 0.9, 0.7),
}

## Models whose leaf cards use shaders/foliage.gdshader (crown shading, translucency, wind).
const FOLIAGE: Array[String] = [
	"home_tree",
	"chinaberry_a",
	"chinaberry_a_far",
	"chinaberry_b",
	"chinaberry_b_far",
	"chinaberry_young",
	"chinaberry_young_far",
	"poinciana_b",
	"poinciana_b_far",
	"acacia",
	"fig_bush",
]

## Leafy models whose generated mesh LODs drop the leaf cards (the bush turns into bare twigs at
## RTS distance with the 6 px LOD threshold): keep them near LOD 0.
const KEEP_LOD: Dictionary = {"shrub_searsia": 8.0, "shrub_leafy": 8.0, "fig_bush": 8.0}

## Big trees placed as single nodes (Home Tree, the woodland stand): the full mesh draws without a
## shadow and a cheaper twin casts it (the 5 woodland trees and the Home Tree were ~450k shadow
## triangles, phone pass 2026-10-11).
const SHADOW_TWIN: Array[String] = [
	"home_tree", "poinciana_b", "chinaberry_a", "chinaberry_b", "chinaberry_young"
]
## LOD bias of a twin that reuses the tree's own mesh: low, so it picks a coarse LOD.
const SHADOW_TWIN_LOD_BIAS: float = 0.05

static var _parts: Dictionary = {}
## Every foliage ShaderMaterial made, for the canopy fade (set_reveal).
static var _foliage_mats: Array[ShaderMaterial] = []
static var _mats: Dictionary = {}
static var _dups: Dictionary = {}


## Registers a mesh built at runtime as a one-part model (e.g. merged grass tussocks).
static func register(model: String, mesh: Mesh) -> void:
	_parts[model] = [{"mesh": mesh, "xform": Transform3D.IDENTITY, "name": model}]


## A new mesh of several parts of `model` merged into one surface (same material), each placed
## by its transform in `xforms` (part index per entry in `which`).
static func merge_parts(model: String, which: Array[int], xforms: Array[Transform3D]) -> ArrayMesh:
	var all: Array = parts(model)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = null
	for k in which.size():
		var p: Dictionary = all[which[k]]
		var m: Mesh = p["mesh"]
		st.append_from(m, 0, xforms[k] * (p["xform"] as Transform3D))
		if mat == null:
			mat = m.surface_get_material(0)
	var out: ArrayMesh = st.commit()
	out.surface_set_material(0, mat)
	return out


## [{mesh: Mesh, xform: Transform3D, name: String}] for a model name (file stem).
static func parts(model: String) -> Array:
	if _parts.has(model):
		return _parts[model]
	var out: Array = []
	var ps: PackedScene = load(DIR + model + ".glb")
	if ps == null:
		push_error("ModelLib: missing model %s" % model)
		_parts[model] = out
		return out
	var root: Node = ps.instantiate()
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	_parts[model] = out
	return out


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here: Transform3D = xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			out.append({"mesh": mi.mesh, "xform": here, "name": str(mi.name)})
	for c in n.get_children():
		_collect(c, here, out)


## Material for surface `s` of `mesh`, fixed for the phone and tinted (cached).
static func material(model: String, mesh: Mesh, s: int, tint: Color, opts: Dictionary) -> Material:
	# far LODs share the grade of their tree
	if model.ends_with("_far") and not opts.has("tint") and GRADE.has(model.trim_suffix("_far")):
		tint = GRADE[model.trim_suffix("_far")]
	var key: String = "%s|%d|%d|%s|%s" % [model, mesh.get_instance_id(), s, tint, str(opts)]
	if _mats.has(key):
		return _mats[key]
	var src: Material = mesh.surface_get_material(s)
	var m: Material = src
	if src is StandardMaterial3D:
		var sm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		var leafy: bool = (
			sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or opts.get("leaf", false)
		)
		if leafy and FOLIAGE.has(model) and not opts.has("fade"):
			m = _foliage(model, mesh, sm, tint)
			_mats[key] = m
			return m
		if leafy:
			# keep the source cut-off (acacia leaves: 0.21); mipmapped leaf-card alpha drops far
			# below 0.5 at RTS distance and the canopy vanishes (seen 2026-10-11)
			var cut: float = 0.3
			if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				cut = minf(sm.alpha_scissor_threshold, 0.3)
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			sm.alpha_scissor_threshold = cut
			sm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.backlight_enabled = true
			sm.backlight = Color(0.25, 0.25, 0.2)
		sm.albedo_color = Color(
			sm.albedo_color.r * tint.r,
			sm.albedo_color.g * tint.g,
			sm.albedo_color.b * tint.b,
			sm.albedo_color.a
		)
		if opts.has("saturation"):
			# no saturation control on StandardMaterial3D: grey the albedo colour instead
			var g: float = (sm.albedo_color.r + sm.albedo_color.g + sm.albedo_color.b) / 3.0
			var k: float = float(opts["saturation"])
			sm.albedo_color = Color(
				lerpf(g, sm.albedo_color.r, k),
				lerpf(g, sm.albedo_color.g, k),
				lerpf(g, sm.albedo_color.b, k)
			)
		if opts.has("albedo"):
			sm.albedo_texture = null
			sm.albedo_color = opts["albedo"]
			sm.roughness = float(opts.get("roughness", 0.7))
		if opts.has("fade"):
			var f: Vector2 = opts["fade"]
			sm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			sm.distance_fade_min_distance = f.y
			sm.distance_fade_max_distance = f.x
		m = sm
	elif src == null and opts.has("albedo"):
		var nm := StandardMaterial3D.new()
		nm.albedo_color = opts["albedo"]
		nm.roughness = float(opts.get("roughness", 0.7))
		m = nm
	_mats[key] = m
	return m


## Leaf material on shaders/foliage.gdshader: the crown ellipsoid comes from the mesh bounds
## (crown = upper 70 % of the tree), wind and translucency scale with the tree.
static func _foliage(model: String, mesh: Mesh, sm: StandardMaterial3D, tint: Color) -> Material:
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/foliage.gdshader")
	fm.set_shader_parameter("albedo_tex", sm.albedo_texture)
	fm.set_shader_parameter(
		"albedo_col",
		Color(sm.albedo_color.r * tint.r, sm.albedo_color.g * tint.g, sm.albedo_color.b * tint.b)
	)
	if sm.normal_enabled and sm.normal_texture != null:
		fm.set_shader_parameter("normal_tex", sm.normal_texture)
		fm.set_shader_parameter("use_normal", true)
	var cut: float = 0.3
	if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		cut = minf(sm.alpha_scissor_threshold, 0.3)
	fm.set_shader_parameter("alpha_cut", cut)
	var bb: AABB = mesh.get_aabb()
	var low: float = bb.position.y + bb.size.y * 0.3
	var top: float = bb.end.y
	var centre := Vector3(bb.get_center().x, (low + top) * 0.5, bb.get_center().z)
	var rad := Vector3(bb.size.x * 0.5, (top - low) * 0.5, bb.size.z * 0.5).max(Vector3.ONE * 0.3)
	fm.set_shader_parameter("crown_centre", centre)
	fm.set_shader_parameter("crown_radius", rad)
	var small: bool = model.begins_with("shrub") or model == "fig_bush"
	fm.set_shader_parameter("wind", 0.03 if small else 0.12)
	_foliage_mats.append(fm)
	return fm


## Canopy fade: up to 16 points (unit chests) the tree crowns must not hide; used points come
## first (w = 1), so the shader loops only over those.
static func set_reveal(points: PackedVector4Array) -> void:
	var n: int = 0
	while n < points.size() and points[n].w > 0.5:
		n += 1
	for m in _foliage_mats:
		m.set_shader_parameter("reveal", points)
		m.set_shader_parameter("reveal_count", n)


## A Node3D holding one MeshInstance3D per part. opts: tint (Color), shadow (bool),
## albedo (Color, replaces the texture), roughness, leaf (bool).
static func make_node(model: String, xf: Transform3D, opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = model
	root.transform = xf
	var tint: Color = opts.get("tint", GRADE.get(model, Color(1, 1, 1)))
	var twin: bool = SHADOW_TWIN.has(model) and opts.get("shadow", true)
	_add_parts(
		root, model, tint, opts, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if twin else -1
	)
	if twin:
		# a cheaper caster throws the shadow: the tree's far model, else a coarse LOD of itself
		var far: String = model + "_far"
		if ResourceLoader.exists(DIR + far + ".glb"):
			_add_parts(
				root, far, tint, opts, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			)
		else:
			var n0: int = root.get_child_count()
			_add_parts(
				root, model, tint, opts, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			)
			for k in range(n0, root.get_child_count()):
				(root.get_child(k) as MeshInstance3D).lod_bias = SHADOW_TWIN_LOD_BIAS
	return root


## MeshInstance3D per part of `model` under `root`; `cast` overrides the shadow setting (-1: from
## opts).
static func _add_parts(
	root: Node3D, model: String, tint: Color, opts: Dictionary, cast: int
) -> void:
	for p: Dictionary in parts(model):
		var mi := MeshInstance3D.new()
		var mesh: Mesh = p["mesh"]
		mi.mesh = mesh
		mi.transform = p["xform"]
		for s in mesh.get_surface_count():
			mi.set_surface_override_material(s, material(model, mesh, s, tint, opts))
		if not opts.get("shadow", true):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if cast >= 0:
			mi.cast_shadow = cast as GeometryInstance3D.ShadowCastingSetting
		if KEEP_LOD.has(model):
			mi.lod_bias = KEEP_LOD[model]
		root.add_child(mi)


## One MultiMeshInstance3D per part for all `xforms`. opts as make_node plus
## part (int, only that part index), vis_end (float, visibility range), fade (Vector2 near/far).
static func make_multimesh(
	model: String, xforms: Array[Transform3D], opts: Dictionary = {}
) -> Array:
	var out: Array = []
	if xforms.is_empty():
		return out
	var tint: Color = opts.get("tint", GRADE.get(model, Color(1, 1, 1)))
	var all: Array = parts(model)
	for pi in all.size():
		if opts.has("part") and int(opts["part"]) != pi:
			continue
		var p: Dictionary = all[pi]
		var mesh: Mesh = p["mesh"]
		var local: Transform3D = p["xform"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [model, pi]
		mmi.multimesh = mm
		# MultiMeshInstance3D has no per-surface override: one override for a single surface, else a
		# shared copy of the mesh carrying the fixed materials
		if mesh.get_surface_count() == 1:
			mmi.material_override = material(model, mesh, 0, tint, opts)
		else:
			var dkey: String = "%s|%d|%s|%s" % [model, pi, tint, str(opts)]
			if not _dups.has(dkey):
				var dup := mesh.duplicate() as Mesh
				for s in mesh.get_surface_count():
					dup.surface_set_material(s, material(model, mesh, s, tint, opts))
				_dups[dkey] = dup
			mm.mesh = _dups[dkey]
		if not opts.get("shadow", true):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if opts.has("vis_end"):
			mmi.visibility_range_end = float(opts["vis_end"])
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if opts.has("vis_begin"):
			mmi.visibility_range_begin = float(opts["vis_begin"])
			mmi.visibility_range_begin_margin = 8.0
		if opts.get("vis_fade", false):
			# dithered cross-fade between the near and far LOD (Forward+)
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if opts.get("shadow_only", false):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if opts.has("lod_bias"):
			mmi.lod_bias = float(opts["lod_bias"])
		elif KEEP_LOD.has(model):
			mmi.lod_bias = KEEP_LOD[model]
		out.append(mmi)
	return out


## Height (m) of a model's bounds, for sizing instances (Y-up).
static func height_of(model: String) -> float:
	var lo: float = INF
	var hi: float = -INF
	for p: Dictionary in parts(model):
		var aabb: AABB = (p["xform"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
		lo = minf(lo, aabb.position.y)
		hi = maxf(hi, aabb.end.y)
	return hi - lo if hi > lo else 1.0
