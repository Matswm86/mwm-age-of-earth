class_name Units
extends Node3D

## All hominins of all teams as flat arrays (no node per unit), drawn by one MultiMesh of the
## baked australopith body (VAT, shaders/vat.gdshader). tick() runs at SpikeConfig.SIM_HZ in game
## time: flow-field steering toward each unit's goal, separation through a 2 m spatial grid,
## terrain blocking, facing. render() interpolates between the last two ticks, picks each unit's
## clip (run while moving, else its set clip) and writes the MultiMesh buffer plus the team discs
## and selection rings. Enemy units outside the player's sight are left out (fog of war) unless
## reveal_all is set (bench).

## Separation grid cell: at least 2 x SEPARATION_DIST, so every neighbour within reach sits in the
## 2 x 2 cells on the unit's side of its cell (4 cells searched instead of 9).
const HASH_CELL_M: float = 2.4
const HASH_SIDE: int = 256
## Camera heights below this draw the full 6k-triangle body; above it (the default camera at 21 m
## and every zoom-out) the ~1.5k LOD, where a unit is 40-60 px tall.
const FULL_LOD_H: float = 15.0
## 3x4 transform + INSTANCE_CUSTOM (no colours) per instance.
const FLOATS: int = 16
const BODY_MODEL: String = "australopith"
## Clips by index (VatModel clip names).
const CLIPS: Array[String] = [
	"idle", "run", "gather", "pickup", "crouch", "attack", "throw", "hit", "death"
]
const C_IDLE: int = 0
const C_RUN: int = 1
const C_GATHER: int = 2
const C_PICKUP: int = 3
const C_CROUCH: int = 4
## Selection ring and team disc radius (DESIGN 4).
const RING_R: float = 0.62
const DISC_R: float = 0.55

var terrain: RtsTerrain
var fog: FogOfWar
var marks: GroundMarks
var body: VatModel
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
var goal := PackedVector2Array()
var arrive := PackedFloat32Array()
var clip := PackedInt32Array()
var clip_t0 := PackedFloat32Array()
var sel_time := PackedFloat32Array()
var orders: Array[FlowField] = []

var _clip_rg := PackedVector2Array()
var _mm: MultiMesh
## Shadow-only copy of the crowd on the low LOD (same buffer).
var _mm_shadow: MultiMesh
var _lod_mesh: Mesh
var _quality: int = 0
## Disc colour per team (alpha scaled by luminance), built once.
var _disc_cols: Array[Color] = []
var _buf := PackedFloat32Array()
var _grid_head := PackedInt32Array()
var _grid_next := PackedInt32Array()
var _push := PackedVector2Array()
var _rng := RandomNumberGenerator.new()


func setup(t: RtsTerrain, f: FogOfWar, gm: GroundMarks) -> void:
	terrain = t
	fog = f
	marks = gm
	body = VatModel.load_model(BODY_MODEL, true)
	# the source fur texture is light tan and vanished on the straw ground; darken toward the
	# look target's dark red-brown so bodies and paint read (DESIGN 8: units highest contrast)
	body.material.set_shader_parameter("albedo_mul", Color(0.62, 0.49, 0.41))
	body.material.set_shader_parameter("rim_strength", 0.7)
	mesh_tris = body.triangles
	for c in CLIPS:
		_clip_rg.append(body.clip_rg(c))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = body.mesh
	_mm.instance_count = SpikeConfig.MAX_UNITS
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(
		Vector3(0.0, -20.0, 0.0), Vector3(SpikeConfig.MAP_SIZE, 80.0, SpikeConfig.MAP_SIZE)
	)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "UnitsMM"
	mmi.multimesh = _mm
	mmi.material_override = body.material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# LODs: the 6k body only at close zoom; shadows always from the ~1.5k LOD
	body.make_lods()
	_lod_mesh = body.lods[body.lods.size() - 1] if body.lods.size() > 0 else body.mesh
	_mm_shadow = MultiMesh.new()
	_mm_shadow.transform_format = MultiMesh.TRANSFORM_3D
	_mm_shadow.use_custom_data = true
	_mm_shadow.mesh = _lod_mesh
	_mm_shadow.instance_count = SpikeConfig.MAX_UNITS
	_mm_shadow.visible_instance_count = 0
	_mm_shadow.custom_aabb = _mm.custom_aabb
	var smi := MultiMeshInstance3D.new()
	smi.name = "UnitsShadow"
	smi.multimesh = _mm_shadow
	smi.material_override = body.material
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(smi)
	for tc: Color in SpikeConfig.TEAM_COLOURS:
		# light team colours (kaolin) at full strength read as white plates: scale by luminance
		_disc_cols.append(Color(tc.r, tc.g, tc.b, 0.34 * (1.15 - 0.6 * tc.get_luminance())))
	_buf.resize(SpikeConfig.MAX_UNITS * FLOATS)
	_buf.fill(0.0)
	_grid_head.resize(HASH_SIDE * HASH_SIDE)
	_rng.seed = 5


## Quality preset hook: Low (q 1) never draws the full body, only the ~1.5k LOD.
func set_mesh_quality(q: int) -> void:
	_quality = q


## Flat annulus mesh kept for callers that want a standalone ring (unused by the game HUD).
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


func clear() -> void:
	count = 0
	# packed arrays are values in GDScript: resize each one by name
	pos.resize(0)
	prev_pos.resize(0)
	hgt.resize(0)
	prev_hgt.resize(0)
	yaw.resize(0)
	prev_yaw.resize(0)
	walk.resize(0)
	team.resize(0)
	cell.resize(0)
	moving.resize(0)
	selected.resize(0)
	goal.resize(0)
	arrive.resize(0)
	clip.resize(0)
	clip_t0.resize(0)
	sel_time.resize(0)
	orders.clear()
	_grid_next.resize(0)
	selected_count = 0


## Adds one unit at p for team t, idle, facing `face` (radians). Returns its index or -1.
func add_unit(p: Vector2, t: int, face: float = 0.0) -> int:
	if count >= SpikeConfig.MAX_UNITS:
		return -1
	var i: int = count
	count += 1
	var h: float = terrain.height_at(p.x, p.y)
	pos.append(p)
	prev_pos.append(p)
	hgt.append(h)
	prev_hgt.append(h)
	yaw.append(face)
	prev_yaw.append(face)
	walk.append(0.0)
	team.append(t)
	cell.append(terrain.cell_of(p))
	moving.append(0)
	selected.append(0)
	goal.append(p)
	arrive.append(1.0)
	clip.append(C_IDLE)
	clip_t0.append(anim_time - _rng.randf() * 3.0)
	sel_time.append(0.0)
	orders.append(null)
	_grid_next.append(-1)
	return i


## Bench: places `per_team` units for each of `teams` teams around the spawn points.
func spawn(teams: int, per_team: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for t in teams:
		var centre: Vector2 = terrain.nearest_walkable(SpikeConfig.SPAWN_POINTS[t])
		var placed: int = 0
		var ring: int = 0
		while placed < per_team and count < SpikeConfig.MAX_UNITS:
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
				add_unit(p, t, rng.randf_range(-PI, PI))
				placed += 1
			ring += 1
			if ring > 40:
				break


## Gives every unit in `ids` the order `ff`, sized for the group (stop as a blob, not a pile).
func order_move(ids: PackedInt32Array, ff: FlowField) -> void:
	ff.group_size = ids.size()
	ff.arrive_r = SpikeConfig.ARRIVE_SPREAD * sqrt(float(maxi(ids.size(), 1)))
	for i in ids:
		order_one(i, ff, ff.target, ff.arrive_r)


## One unit walks to `g` (stops within `arrive_r`), steering on `ff` (built for g's cell).
func order_one(i: int, ff: FlowField, g: Vector2, arrive_r: float) -> void:
	orders[i] = ff
	goal[i] = g
	arrive[i] = arrive_r
	moving[i] = 1


func stop(i: int) -> void:
	moving[i] = 0


## Plays clip `c` (C_*) when not moving; restarts only when it changes.
func set_clip(i: int, c: int) -> void:
	if clip[i] != c:
		clip[i] = c
		clip_t0[i] = anim_time - _rng.randf() * 0.5


func face(i: int, target: Vector2) -> void:
	var d: Vector2 = target - pos[i]
	if d.length_squared() > 0.0001:
		yaw[i] = atan2(d.x, d.y)


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
		sel_time[i] = anim_time
	selected_count = ids.size()


func tick(dt: float) -> void:
	# hot loop (210 units x 30 Hz): terrain lookups are inlined (height_at, cell_of,
	# is_blocked_at), the flow-field step is cached per cell, separation searches 2 x 2 cells
	var blk: PackedByteArray = terrain.blocked
	var hts: PackedFloat32Array = terrain.heights
	var n_side: int = terrain.n_side
	var inv_hs: float = 1.0 / SpikeConfig.HEIGHT_SPACING
	var h_max: float = n_side - 1.001
	var n_nav: int = SpikeConfig.NAV_CELLS
	var nav_hi: int = n_nav - 1
	var cm: float = SpikeConfig.NAV_CELL_M
	var inv_cm: float = 1.0 / cm
	var map_m: float = SpikeConfig.MAP_SIZE
	var sep: float = SpikeConfig.SEPARATION_DIST
	var sep2: float = sep * sep
	var speed: float = SpikeConfig.UNIT_SPEED
	var push_k: float = SpikeConfig.SEPARATION_PUSH
	var max_step: float = speed * 1.5 * dt
	var turn: float = minf(1.0, dt * SpikeConfig.TURN_RATE)
	var walk_step: float = dt * 6.0
	var inv_hash: float = 1.0 / HASH_CELL_M
	var hs_hi: int = HASH_SIDE - 1
	# spatial grid, rebuilt every tick; fill() is native and cheap
	_grid_head.fill(-1)
	for i in count:
		var p: Vector2 = pos[i]
		var key: int = (
			clampi(int(p.y * inv_hash), 0, hs_hi) * HASH_SIDE
			+ clampi(int(p.x * inv_hash), 0, hs_hi)
		)
		_grid_next[i] = _grid_head[key]
		_grid_head[key] = i
		prev_pos[i] = p
		prev_yaw[i] = yaw[i]
		prev_hgt[i] = hgt[i]
	# arrivals first, so the touch rule below sees who has stopped
	for i in count:
		if moving[i] == 1 and (goal[i] - pos[i]).length() < arrive[i]:
			moving[i] = 0
	# separation, every close pair once (j > i, both sides pushed): the grid cell is >= 2 x sep, so
	# every neighbour within reach sits in the 2 x 2 cells on my side of my cell. Arrival
	# spreading: a moving unit touching an arrived unit of the same order near the goal stops.
	_push.resize(count)
	_push.fill(Vector2.ZERO)
	for i in count:
		var p: Vector2 = pos[i]
		var fx: float = p.x * inv_hash
		var fz: float = p.y * inv_hash
		var hx: int = int(fx)
		var hz: int = int(fz)
		var x0: int = maxi(hx - 1 if fx - hx < 0.5 else hx, 0)
		var z0: int = maxi(hz - 1 if fz - hz < 0.5 else hz, 0)
		var x1: int = mini(x0 + 2, HASH_SIDE)
		var z1: int = mini(z0 + 2, HASH_SIDE)
		for gz in range(z0, z1):
			var row: int = gz * HASH_SIDE
			for gx in range(x0, x1):
				var j: int = _grid_head[row + gx]
				while j > i:
					var dv: Vector2 = p - pos[j]
					var dd: float = dv.length_squared()
					if dd < sep2:
						if dd < 0.0001:
							dv = Vector2(cos(float(i)), sin(float(i)))
							dd = 1.0
						var dl: float = sqrt(dd)
						var f: Vector2 = dv / dl * (sep - dl)
						_push[i] += f
						_push[j] -= f
						if moving[i] != moving[j] and orders[i] == orders[j] and goal[i] == goal[j]:
							var m: int = i if moving[i] == 1 else j
							if pos[m].distance_to(goal[m]) < arrive[m] * 2.5:
								moving[m] = 0
					j = _grid_next[j]
	for i in count:
		var p: Vector2 = pos[i]
		var v := Vector2.ZERO
		var ff: FlowField = orders[i]
		var is_moving: bool = moving[i] == 1
		if is_moving:
			var to_t: Vector2 = goal[i] - p
			var d: float = to_t.length()
			var dir: Vector2 = to_t / d
			if ff != null and ff.is_built and d > 6.0:
				var nc: int = ff.next_cached(cell[i], blk)
				if nc >= 0:
					var q := Vector2(
						((nc & nav_hi) + 0.5) * cm, ((nc >> SpikeConfig.NAV_SHIFT) + 0.5) * cm
					)
					dir = (q - p).normalized()
			v = dir * speed
		var push: Vector2 = _push[i]
		if v == Vector2.ZERO and push == Vector2.ZERO:
			# standing still and untouched: nothing moves, only the walk blend settles
			walk[i] = move_toward(walk[i], 0.0, walk_step)
			continue
		var step: Vector2 = (v + push * push_k) * dt
		if step.length_squared() > max_step * max_step:
			step = step.normalized() * max_step
		var np: Vector2 = p + step
		if (
			np.x < 0.0
			or np.y < 0.0
			or np.x >= map_m
			or np.y >= map_m
			or blk[mini(int(np.y * inv_cm), nav_hi) * n_nav + mini(int(np.x * inv_cm), nav_hi)] == 1
		):
			if not _blocked_at(Vector2(np.x, p.y), blk, inv_cm, nav_hi, map_m):
				np = Vector2(np.x, p.y)
			elif not _blocked_at(Vector2(p.x, np.y), blk, inv_cm, nav_hi, map_m):
				np = Vector2(p.x, np.y)
			else:
				np = p
		pos[i] = np
		cell[i] = (
			clampi(int(np.y * inv_cm), 0, nav_hi) * n_nav + clampi(int(np.x * inv_cm), 0, nav_hi)
		)
		# bilinear height (RtsTerrain.height_at inlined)
		var hx2: float = clampf(np.x * inv_hs, 0.0, h_max)
		var hz2: float = clampf(np.y * inv_hs, 0.0, h_max)
		var ix: int = int(hx2)
		var iz: int = int(hz2)
		var tx: float = hx2 - ix
		var k: int = iz * n_side + ix
		var ha: float = hts[k] + (hts[k + 1] - hts[k]) * tx
		var hb: float = hts[k + n_side] + (hts[k + n_side + 1] - hts[k + n_side]) * tx
		hgt[i] = ha + (hb - ha) * (hz2 - iz)
		if is_moving and v.length_squared() > 0.01:
			yaw[i] = lerp_angle(yaw[i], atan2(v.x, v.y), turn)
		walk[i] = move_toward(walk[i], 1.0 if is_moving else 0.0, walk_step)


## RtsTerrain.is_blocked_at with the tick's locals (off the map counts as blocked).
static func _blocked_at(
	p: Vector2, blk: PackedByteArray, inv_cm: float, hi: int, map_m: float
) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_m or p.y >= map_m:
		return true
	return blk[mini(int(p.y * inv_cm), hi) * (hi + 1) + mini(int(p.x * inv_cm), hi)] == 1


## Chests of up to `n` units of team `t` (w = 1), padded with unused entries (w = 0), for the
## canopy fade in shaders/foliage.gdshader.
func reveal_points(t: int, n: int) -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(n)
	var k: int = 0
	for i in count:
		if k >= n:
			break
		if team[i] != t:
			continue
		out[k] = Vector4(pos[i].x, hgt[i] + 0.9, pos[i].y, 1.0)
		k += 1
	return out


## True when unit i should be drawn (own team, or seen through the fog).
func is_seen(i: int) -> bool:
	return team[i] == 0 or reveal_all or fog_off or fog.is_visible_cell(cell[i])


## Writes the MultiMesh buffer and the ground marks; `alpha` is how far game time is between the
## last two ticks.
func render(alpha: float) -> void:
	var vis: int = 0
	var show_all: bool = reveal_all or fog_off
	var fb: PackedByteArray = fog.bytes
	var us: float = SpikeConfig.UNIT_DRAW_SCALE
	for i in count:
		var t: int = team[i]
		# is_seen() inlined
		if t != 0 and not show_all and fb[cell[i]] != 255:
			continue
		var p: Vector2 = prev_pos[i].lerp(pos[i], alpha)
		var y: float = lerpf(prev_hgt[i], hgt[i], alpha)
		var a: float = lerp_angle(prev_yaw[i], yaw[i], alpha)
		var cs: float = cos(a) * us
		var sn: float = sin(a) * us
		var o: int = vis * FLOATS
		_buf[o] = cs
		_buf[o + 1] = 0.0
		_buf[o + 2] = sn
		_buf[o + 3] = p.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = us
		_buf[o + 6] = 0.0
		_buf[o + 7] = y
		_buf[o + 8] = -sn
		_buf[o + 9] = 0.0
		_buf[o + 10] = cs
		_buf[o + 11] = p.y
		var c: int = C_RUN if walk[i] > 0.35 else clip[i]
		var rg: Vector2 = _clip_rg[c]
		_buf[o + 12] = rg.x
		_buf[o + 13] = rg.y
		_buf[o + 14] = clip_t0[i] if c != C_RUN else float(i) * 0.37
		_buf[o + 15] = float(t) + 4.0 * selected[i]
		vis += 1
		# flat discs: the ground is gentle and a normal per unit per frame cost ~1 ms of CPU
		marks.add_flat(p.x, y, p.y, DISC_R, _disc_cols[t], GroundMarks.MODE_DISC)
		if selected[i] == 1:
			var k: float = clampf((anim_time - sel_time[i]) / 0.12, 0.0, 1.0)
			marks.add_flat(p.x, y, p.y, RING_R * k, GameConfig.SELECT, GroundMarks.MODE_RING)
	# body LOD: the full mesh only at close zoom on High (MultiMesh LOD cannot pick per unit)
	var cam := get_viewport().get_camera_3d() as RtsCamera
	var full: bool = _quality == 0 and cam != null and cam.height < FULL_LOD_H
	var want: Mesh = body.mesh if full else _lod_mesh
	if _mm.mesh != want:
		_mm.mesh = want
	mesh_tris = body.triangles if full else _lod_tris()
	_mm.buffer = _buf
	_mm.visible_instance_count = vis
	_mm_shadow.buffer = _buf
	_mm_shadow.visible_instance_count = vis
	visible_count = vis
	body.material.set_shader_parameter("anim_time", anim_time)


func _lod_tris() -> int:
	var n: int = body.lod_triangles.size()
	return body.lod_triangles[n - 1] if n > 0 else body.triangles
