class_name Animals
extends Node3D

## Neutral wildlife for the Age 1 opening (no combat in this build): a grazing gazelle herd (VAT,
## its only baked clip is a standing idle, so they drift slowly while grazing), a leopard on a
## patrol loop (VAT run clip), a hyena pack prowling near the carcasses (static scanned body with
## a trot bob: the rigged hyena's skin is broken, see report) and crocodiles basking at the
## waterline (static, tinted from the pale source texture toward Nile-croc olive grey).
## Each animal gets a neutral ground disc; all are hidden outside the player's sight.

const GAZELLE_SPEED: float = 0.9
const HYENA_SPEED: float = 1.8
const LEOPARD_SPEED: float = 4.2

var terrain: RtsTerrain
var fog: FogOfWar
var marks: GroundMarks
var anim_time: float = 0.0
var reveal_all: bool = false
var visible_count: int = 0

var _gaz: VatModel
var _leo: VatModel
var _gaz_mm: MultiMesh
var _leo_mm: MultiMesh
## per animal: kind (0 gazelle, 1 leopard, 2 hyena), pos, yaw, target, wait, home, node
var _a: Array[Dictionary] = []
var _crocs: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func setup(t: RtsTerrain, f: FogOfWar, gm: GroundMarks) -> void:
	terrain = t
	fog = f
	marks = gm
	_rng.seed = 31
	_gaz = VatModel.load_model("gazelle", false)
	_leo = VatModel.load_model("leopard", false)
	_gaz.material.set_shader_parameter("rim_strength", 0.2)
	_leo.material.set_shader_parameter("rim_strength", 0.2)
	_gaz_mm = _make_mm(_gaz, GameConfig.GAZELLES, "Gazelles")
	_leo_mm = _make_mm(_leo, 1, "Leopard")
	for k in GameConfig.GAZELLES:
		var p: Vector2 = (
			GameConfig.GAZELLE_HERD + Vector2(_rng.randf_range(-7, 7), _rng.randf_range(-6, 6))
		)
		_add(0, p, null)
	_add(1, GameConfig.LEOPARD_PATH[0], null)
	for k in GameConfig.HYENAS:
		var p: Vector2 = (
			GameConfig.HYENA_DEN + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
		)
		var n: Node3D = ModelLib.make_node("hyena", Transform3D.IDENTITY)
		add_child(n)
		_add(2, p, n)
	for p: Vector2 in GameConfig.CROCODILES:
		var h: float = maxf(terrain.height_at(p.x, p.y), -0.45)
		var b := Basis(Vector3.UP, _rng.randf() * TAU)
		var xf := Transform3D(b, Vector3(p.x, h - 0.35, p.y))
		var n: Node3D = ModelLib.make_node(
			"crocodile", xf, {"tint": GameConfig.CROC_TINT, "saturation": 0.6}
		)
		add_child(n)
		_crocs.append(n)


func _make_mm(v: VatModel, n: int, node_name: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = v.mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(
		Vector3(0.0, -20.0, 0.0), Vector3(SpikeConfig.MAP_SIZE, 80.0, SpikeConfig.MAP_SIZE)
	)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = v.material
	add_child(mmi)
	return mm


func _add(kind: int, p: Vector2, node: Node3D) -> void:
	(
		_a
		. append(
			{
				"kind": kind,
				"pos": p,
				"yaw": _rng.randf() * TAU,
				"target": p,
				"wait": _rng.randf_range(0.0, 6.0),
				"home": p,
				"node": node,
				"leg": 0,
				"phase": _rng.randf() * 10.0,
				"moving": false,
			}
		)
	)


## Position of the first hyena (the predator the onboarding warns about), or INF when none.
func hyena_pos() -> Vector2:
	for a in _a:
		if int(a["kind"]) == 2:
			return a["pos"]
	return Vector2.INF


## Positions of one kind of animal (0 gazelle, 1 leopard, 2 hyena), for Sfx calls.
func positions_of(kind: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for a in _a:
		if int(a["kind"]) == kind:
			out.append(a["pos"])
	return out


func tick(dt: float) -> void:
	anim_time += dt
	for a in _a:
		var kind: int = a["kind"]
		var p: Vector2 = a["pos"]
		var tgt: Vector2 = a["target"]
		var speed: float = [GAZELLE_SPEED, LEOPARD_SPEED, HYENA_SPEED][kind]
		var d: Vector2 = tgt - p
		if d.length() < 0.3:
			a["moving"] = false
			a["wait"] = float(a["wait"]) - dt
			if float(a["wait"]) <= 0.0:
				a["target"] = _next_target(a)
				a["wait"] = _rng.randf_range(4.0, 12.0) if kind != 1 else 0.0
			continue
		a["moving"] = true
		var step: Vector2 = d.normalized() * minf(speed * dt, d.length())
		var np: Vector2 = p + step
		if terrain.is_blocked_at(np):
			a["target"] = p
			continue
		a["pos"] = np
		a["yaw"] = lerp_angle(float(a["yaw"]), atan2(d.x, d.y), minf(1.0, dt * 4.0))


func _next_target(a: Dictionary) -> Vector2:
	var kind: int = a["kind"]
	if kind == 1:
		var leg: int = (int(a["leg"]) + 1) % GameConfig.LEOPARD_PATH.size()
		a["leg"] = leg
		return GameConfig.LEOPARD_PATH[leg]
	var home: Vector2 = a["home"]
	var r: float = 4.0 if kind == 0 else 12.0
	return home + Vector2(_rng.randf_range(-r, r), _rng.randf_range(-r, r))


func _seen(p: Vector2) -> bool:
	return reveal_all or fog.is_visible_cell(terrain.cell_of(p))


func render() -> void:
	var gi: int = 0
	var gb := PackedFloat32Array()
	gb.resize(GameConfig.GAZELLES * 16)
	var lb := PackedFloat32Array()
	lb.resize(16)
	var li: int = 0
	visible_count = 0
	for a in _a:
		var p: Vector2 = a["pos"]
		var kind: int = a["kind"]
		var seen: bool = _seen(p)
		var y: float = terrain.height_at(p.x, p.y)
		var yw: float = a["yaw"]
		var node: Node3D = a["node"]
		if node != null:
			node.visible = seen
		if not seen:
			continue
		visible_count += 1
		var n: Vector3 = terrain.normal_at(p.x, p.y)
		var r: float = [0.75, 0.9, 0.7][kind]
		marks.add(
			Vector3(p.x, y, p.y), n, r, Color(GameConfig.NEUTRAL_DISC, 0.3), GroundMarks.MODE_DISC
		)
		if kind == 2:
			var bob: float = (
				absf(sin(anim_time * 9.0 + float(a["phase"]))) * 0.05 if a["moving"] else 0.0
			)
			node.transform = Transform3D(Basis(Vector3.UP, yw), Vector3(p.x, y + bob, p.y))
			continue
		var buf: PackedFloat32Array = gb if kind == 0 else lb
		var o: int = (gi if kind == 0 else li) * 16
		var cs: float = cos(yw)
		var sn: float = sin(yw)
		var vals: Array[float] = [cs, 0.0, sn, p.x, 0.0, 1.0, 0.0, y, -sn, 0.0, cs, p.y]
		for k in 12:
			buf[o + k] = vals[k]
		var v: VatModel = _gaz if kind == 0 else _leo
		var rg: Vector2 = v.clip_rg(v.clips.keys()[0])
		buf[o + 12] = rg.x
		buf[o + 13] = rg.y
		buf[o + 14] = -float(a["phase"])
		buf[o + 15] = 3.0
		if kind == 0:
			gi += 1
		else:
			li += 1
	_gaz_mm.buffer = gb
	_gaz_mm.visible_instance_count = gi
	_leo_mm.buffer = lb
	_leo_mm.visible_instance_count = li
	_gaz.material.set_shader_parameter("anim_time", anim_time)
	_leo.material.set_shader_parameter("anim_time", anim_time)
	for c in _crocs:
		c.visible = _seen(Vector2(c.position.x, c.position.z))
