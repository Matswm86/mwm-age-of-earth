class_name Units
extends Node3D

## All units of all teams as flat arrays (no node per unit). One MultiMesh draws them all with
## the vertex-animated hominin; a second MultiMesh draws the selection rings.
## tick() runs at SpikeConfig.SIM_HZ in game time: flow-field steering toward the order's target,
## separation through a 2 m spatial grid, terrain blocking, facing. render() interpolates between
## the last two ticks and writes the MultiMesh buffer (16 floats per instance: 3x4 transform +
## custom data team colour rgb, walk + 2 x selected). Enemy units outside the player's sight are
## left out of the buffer (fog of war), unless reveal_all is set (bench).

const HASH_CELL_M: float = 2.0
const HASH_SIDE: int = 256
const FLOATS: int = 16

var terrain: RtsTerrain
var fog: FogOfWar
var reveal_all: bool = false
## Fog switched off by the Fog button: draw every unit.
var fog_off: bool = false
var count: int = 0
var visible_count: int = 0
var selected_count: int = 0
var anim_time: float = 0.0
var mesh_tris: int = 0

var pos := PackedVector2Array()
var prev_pos := PackedVector2Array()
var hgt := PackedFloat32Array()
var prev_hgt := PackedFloat32Array()
var yaw := PackedFloat32Array()
var prev_yaw := PackedFloat32Array()
var walk := PackedFloat32Array()
var team := PackedInt32Array()
var cell := PackedInt32Array()
var moving := PackedByteArray()
var selected := PackedByteArray()
var orders: Array[FlowField] = []

var _meshes: Array[ArrayMesh] = []
var _tris: Array[int] = []
var _mm: MultiMesh
var _rings: MultiMesh
var _mat: ShaderMaterial
var _buf := PackedFloat32Array()
var _ring_buf := PackedFloat32Array()
var _grid_head := PackedInt32Array()
var _grid_next := PackedInt32Array()


func setup(t: RtsTerrain, f: FogOfWar) -> void:
	terrain = t
	fog = f
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/unit.gdshader")
	for detail in [1, 0]:
		var builder := UnitMesh.new()
		var m: ArrayMesh = builder.build(detail)
		m.surface_set_material(0, _mat)
		_meshes.append(m)
		_tris.append(builder.triangle_count())
	var mesh: ArrayMesh = _meshes[0]
	mesh_tris = _tris[0]
	var map_box := AABB(
		Vector3(0.0, -20.0, 0.0), Vector3(SpikeConfig.MAP_SIZE, 80.0, SpikeConfig.MAP_SIZE)
	)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = SpikeConfig.MAX_UNITS
	_mm.visible_instance_count = 0
	_mm.custom_aabb = map_box
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "UnitsMM"
	mmi.multimesh = _mm
	add_child(mmi)
	_rings = MultiMesh.new()
	_rings.transform_format = MultiMesh.TRANSFORM_3D
	_rings.mesh = ring_mesh(0.42, 0.56)
	_rings.instance_count = SpikeConfig.MAX_UNITS
	_rings.visible_instance_count = 0
	_rings.custom_aabb = map_box
	var rmi := MultiMeshInstance3D.new()
	rmi.name = "RingsMM"
	rmi.multimesh = _rings
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rmi)
	_buf.resize(SpikeConfig.MAX_UNITS * FLOATS)
	_buf.fill(0.0)
	_ring_buf.resize(SpikeConfig.MAX_UNITS * 12)
	_ring_buf.fill(0.0)
	_grid_head.resize(HASH_SIDE * HASH_SIDE)


## 0 = High mesh, 1 = Low mesh (same order as SpikeConfig.QUALITY).
func set_mesh_quality(q: int) -> void:
	_mm.mesh = _meshes[q]
	mesh_tris = _tris[q]


## Flat annulus mesh (selection ring, move marker) with the unshaded ring shader.
static func ring_mesh(inner: float, outer: float) -> ArrayMesh:
	var segs: int = 24
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in segs:
		var a: float = TAU * s / segs
		v.append(Vector3(cos(a) * inner, 0.0, sin(a) * inner))
		v.append(Vector3(cos(a) * outer, 0.0, sin(a) * outer))
	for s in segs:
		var a0: int = s * 2
		var a1: int = ((s + 1) % segs) * 2
		idx.append_array(PackedInt32Array([a0, a0 + 1, a1, a1, a0 + 1, a1 + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ring.gdshader")
	m.surface_set_material(0, mat)
	return m


## Places `per_team` units for each of `teams` teams around the spawn points.
func spawn(teams: int, per_team: int) -> void:
	count = mini(teams * per_team, SpikeConfig.MAX_UNITS)
	pos.resize(count)
	prev_pos.resize(count)
	hgt.resize(count)
	prev_hgt.resize(count)
	yaw.resize(count)
	prev_yaw.resize(count)
	walk.resize(count)
	team.resize(count)
	cell.resize(count)
	moving.resize(count)
	selected.resize(count)
	moving.fill(0)
	selected.fill(0)
	walk.fill(0.0)
	orders.clear()
	orders.resize(count)
	_grid_next.resize(count)
	selected_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var i: int = 0
	for t in teams:
		var centre: Vector2 = terrain.nearest_walkable(SpikeConfig.SPAWN_POINTS[t])
		var placed: int = 0
		var ring: int = 0
		while placed < per_team and i < count:
			# square spiral, 1.3 m apart, skipping blocked spots
			var side: int = ring * 2 + 1
			for k in side * side:
				if placed >= per_team:
					break
				var gx: int = k % side - ring
				var gz: int = int(float(k) / side) - ring
				if maxi(absi(gx), absi(gz)) != ring:
					continue
				var p: Vector2 = centre + Vector2(gx, gz) * 1.3
				p += Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
				if terrain.is_blocked_at(p):
					continue
				pos[i] = p
				prev_pos[i] = p
				var h: float = terrain.height_at(p.x, p.y)
				hgt[i] = h
				prev_hgt[i] = h
				var y: float = rng.randf_range(-PI, PI)
				yaw[i] = y
				prev_yaw[i] = y
				team[i] = t
				cell[i] = terrain.cell_of(p)
				placed += 1
				i += 1
			ring += 1
			if ring > 40:
				break
	count = i


## Gives every unit in `ids` the order `ff` (already built), sized for the group.
func order_move(ids: PackedInt32Array, ff: FlowField) -> void:
	ff.group_size = ids.size()
	ff.arrive_r = SpikeConfig.ARRIVE_SPREAD * sqrt(float(maxi(ids.size(), 1)))
	for i in ids:
		orders[i] = ff
		moving[i] = 1


func ids_of_team(t: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in count:
		if team[i] == t:
			out.append(i)
	return out


func selected_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in count:
		if selected[i] == 1:
			out.append(i)
	return out


func set_selection(ids: PackedInt32Array) -> void:
	selected.fill(0)
	for i in ids:
		selected[i] = 1
	selected_count = ids.size()


func tick(dt: float) -> void:
	var blk: PackedByteArray = terrain.blocked
	var n_nav: int = SpikeConfig.NAV_CELLS
	var cm: float = SpikeConfig.NAV_CELL_M
	var sep: float = SpikeConfig.SEPARATION_DIST
	var sep2: float = sep * sep
	var speed: float = SpikeConfig.UNIT_SPEED
	var push_k: float = SpikeConfig.SEPARATION_PUSH
	var turn: float = minf(1.0, dt * SpikeConfig.TURN_RATE)
	var inv_hash: float = 1.0 / HASH_CELL_M
	# spatial grid (2 m cells), rebuilt every tick; fill() is native and cheap
	_grid_head.fill(-1)
	for i in count:
		var p: Vector2 = pos[i]
		var key: int = (
			clampi(int(p.y * inv_hash), 0, HASH_SIDE - 1) * HASH_SIDE
			+ clampi(int(p.x * inv_hash), 0, HASH_SIDE - 1)
		)
		_grid_next[i] = _grid_head[key]
		_grid_head[key] = i
		prev_pos[i] = p
		prev_yaw[i] = yaw[i]
		prev_hgt[i] = hgt[i]
	for i in count:
		var p: Vector2 = pos[i]
		var v := Vector2.ZERO
		var ff: FlowField = orders[i]
		var is_moving: bool = moving[i] == 1
		if is_moving:
			var to_t: Vector2 = ff.target - p
			var d: float = to_t.length()
			if d < ff.arrive_r:
				moving[i] = 0
				is_moving = false
			else:
				var dir: Vector2 = to_t / d
				var c: int = cell[i]
				if ff.is_built and d > 6.0 and ff.dist[c] < FlowField.UNREACHED:
					var nc: int = ff.next_cell(c, blk)
					if nc >= 0:
						var q := Vector2(
							((nc & (n_nav - 1)) + 0.5) * cm, ((nc >> SpikeConfig.NAV_SHIFT) + 0.5) * cm
						)
						dir = (q - p).normalized()
				v = dir * speed
		# separation (and arrival spreading: touching an arrived unit of the same order stops me)
		var push := Vector2.ZERO
		var hx: int = int(p.x * inv_hash)
		var hz: int = int(p.y * inv_hash)
		for gz in range(maxi(hz - 1, 0), mini(hz + 2, HASH_SIDE)):
			for gx in range(maxi(hx - 1, 0), mini(hx + 2, HASH_SIDE)):
				var j: int = _grid_head[gz * HASH_SIDE + gx]
				while j >= 0:
					if j != i:
						var dv: Vector2 = p - pos[j]
						var dd: float = dv.length_squared()
						if dd < sep2:
							if dd < 0.0001:
								dv = Vector2(cos(float(i)), sin(float(i)))
								dd = 1.0
							var dl: float = sqrt(dd)
							push += dv / dl * (sep - dl)
							if (
								is_moving
								and moving[j] == 0
								and orders[j] == ff
								and p.distance_to(ff.target) < ff.arrive_r * 2.5
							):
								moving[i] = 0
								is_moving = false
								v = Vector2.ZERO
					j = _grid_next[j]
		var step: Vector2 = (v + push * push_k) * dt
		var max_step: float = speed * 1.5 * dt
		if step.length() > max_step:
			step = step.normalized() * max_step
		var np: Vector2 = p + step
		if terrain.is_blocked_at(np):
			if not terrain.is_blocked_at(Vector2(np.x, p.y)):
				np = Vector2(np.x, p.y)
			elif not terrain.is_blocked_at(Vector2(p.x, np.y)):
				np = Vector2(p.x, np.y)
			else:
				np = p
		pos[i] = np
		cell[i] = terrain.cell_of(np)
		hgt[i] = terrain.height_at(np.x, np.y)
		if is_moving and v.length_squared() > 0.01:
			yaw[i] = lerp_angle(yaw[i], atan2(v.x, v.y), turn)
		var want: float = 1.0 if is_moving else clampf(push.length() * 2.0, 0.0, 0.6)
		walk[i] = move_toward(walk[i], want, dt * 4.0)


## Writes the MultiMesh buffers; `alpha` is how far game time is between the last two ticks.
func render(alpha: float) -> void:
	var vis: int = 0
	var rings: int = 0
	var colours: Array[Color] = SpikeConfig.TEAM_COLOURS
	for i in count:
		var t: int = team[i]
		if t != 0 and not (reveal_all or fog_off) and not fog.is_visible_cell(cell[i]):
			continue
		var p: Vector2 = prev_pos[i].lerp(pos[i], alpha)
		var y: float = lerpf(prev_hgt[i], hgt[i], alpha)
		var a: float = lerp_angle(prev_yaw[i], yaw[i], alpha)
		var cs: float = cos(a)
		var sn: float = sin(a)
		var o: int = vis * FLOATS
		_buf[o] = cs
		_buf[o + 1] = 0.0
		_buf[o + 2] = sn
		_buf[o + 3] = p.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = 1.0
		_buf[o + 6] = 0.0
		_buf[o + 7] = y
		_buf[o + 8] = -sn
		_buf[o + 9] = 0.0
		_buf[o + 10] = cs
		_buf[o + 11] = p.y
		var col: Color = colours[t]
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b
		_buf[o + 15] = walk[i] + 2.0 * selected[i]
		vis += 1
		if selected[i] == 1:
			var r: int = rings * 12
			_ring_buf[r] = 1.0
			_ring_buf[r + 3] = p.x
			_ring_buf[r + 5] = 1.0
			_ring_buf[r + 7] = y + 0.06
			_ring_buf[r + 10] = 1.0
			_ring_buf[r + 11] = p.y
			rings += 1
	_mm.buffer = _buf
	_mm.visible_instance_count = vis
	_rings.buffer = _ring_buf
	_rings.visible_instance_count = rings
	visible_count = vis
	_mat.set_shader_parameter("anim_time", anim_time)
