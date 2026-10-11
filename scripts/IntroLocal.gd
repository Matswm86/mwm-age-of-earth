class_name IntroLocal
extends Node3D

## The intro after the cloud deck (owner 2026-10-11: cinematic, not the game view). One camera
## glides down through golden-hour haze to the Home Tree, a hominin (Australopithecus anamensis
## look: the Age 1 body, skinned, AnimationPlayer) wakes in its nest, climbs down the trunk,
## drops to the ground and walks to its place in the band, then the camera rises into Main's
## opening RTS pose while sun, haze and grade turn into the game's own (WorldLook), so the
## cross-fade into Main matches. The map, the tree and the props are the game's own
## (RtsTerrain, Scenery); nothing here edits them.
## apply(t) is a pure function of the timeline (the screenshot bot seeks).

const HERO_SCENE: String = "res://assets/intro/hero/australopith_hero.glb"
## Camera keys: [t, position, look-at point, fov]. Positions and look points are metres relative
## to the Home Tree's foot (x east, y up, z south). The last key is replaced by Main's RTS pose.
const CAM_KEYS: Array[Array] = [
	[64.0, Vector3(150.0, 230.0, 195.0), Vector3(0.0, 0.0, 0.0), 40.0],
	[68.5, Vector3(80.0, 80.0, 110.0), Vector3(0.0, 4.0, 0.0), 40.0],
	[72.5, Vector3(30.0, 14.0, 40.0), Vector3(0.5, 5.0, 0.5), 39.0],
	[75.5, Vector3(8.5, 2.6, 11.5), Vector3(1.7, 5.3, 0.6), 24.0],
	[78.5, Vector3(7.0, 2.6, 9.5), Vector3(1.4, 5.0, 0.8), 22.0],
	[80.0, Vector3(6.0, 2.4, 8.0), Vector3(1.0, 4.2, 0.8), 32.0],
	[82.0, Vector3(5.2, 1.9, 7.2), Vector3(0.8, 2.6, 1.0), 34.0],
	[85.0, Vector3(4.6, 1.5, 6.8), Vector3(0.8, 0.9, 1.4), 35.0],
	[88.0, Vector3(6.0, 3.5, 13.0), Vector3(1.0, 1.0, 6.0), 36.0],
	[93.0, Vector3.ZERO, Vector3.ZERO, 37.0],
]
## Weight of "look at the hero" over the keyed look point.
const TRACK_HERO: Vector4 = Vector4(75.0, 76.5, 86.4, 88.4)
## Camera clearance over the ground (m).
const CAM_CLEAR_M: float = 1.2

# --- the climber (times in intro seconds, speeds in m/s) ---
const WAKE_T: float = 75.5
## LayToIdle plays slowed to this rate (it is a quick get-up).
const WAKE_RATE: float = 0.6
const STEP_S: float = 0.9
## Climb speed; the clip covers 0.6 m per 1 s cycle (tools/intro/hero_clips.py DESCENT_M).
const CLIMB_V: float = 1.1
const CLIMB_CYCLE_M: float = 0.6
## Origin height (m over the ground) where the climb ends and the hominin drops.
const CLIMB_LOW_M: float = 0.15
const DROP_S: float = 0.4
const WALK_V: float = 1.3
## Walk clip covers this many metres per second at rate 1 (Quaternius Walk_Loop on this body).
const WALK_CLIP_V: float = 1.2
## The trunk is measured at build time from the Home Tree model's opaque (bark) surfaces: bark
## vertices within TRUNK_SEARCH_M of the tree's origin, centroid and radius per TRUNK_BIN_M of
## height (empty bins are filled from their neighbours). The climber's origin keeps the bark
## radius + TRUNK_GAP_M off the axis (the clip hugs a 0.45 m trunk 0.5 m ahead).
const TRUNK_SEARCH_M: float = 2.2
const TRUNK_BIN_M: float = 0.5
const TRUNK_GAP_M: float = 0.08
## Start ring slot (Game.start_match order) the climber walks to; the other five stand on theirs.
const CLIMBER_SLOT: int = 1

# --- light: golden hour at the start, the game's light at the end (WorldLook) ---
const GOLD_ELEV_DEG: float = 12.0
const GOLD_SUN := Color(1.0, 0.79, 0.57)
const GOLD_SUN_ENERGY: float = 2.6
const GOLD_HAZE := Color(0.96, 0.87, 0.74)
## Light turns from golden to game over this window.
const LIGHT_TURN: Vector2 = Vector2(86.0, 93.0)

var terrain: RtsTerrain
var sun: DirectionalLight3D
var env: Environment
var cam_attr: CameraAttributesPractical
var low_quality: bool = false
var live: bool = true
## Lowest height (m) with measured bark; below it the axis is extended straight down.
var trunk_low_m: float = 0.0

var _home: Vector3
var _nest_top: Vector3
## Trunk axis (world) per TRUNK_BIN_M of height over the tree's foot, and bark radius.
var _trunk_c: PackedVector3Array = PackedVector3Array()
var _trunk_r: PackedFloat32Array = PackedFloat32Array()

var _end_pos: Vector3
var _end_look: Vector3
var _end_focus_m: float = 30.0
var _base: Dictionary = {}
var _gold: Dictionary = {}
var _climber: Actor
var _band: Array[Actor] = []
var _slots: Array[Vector3] = []
# climber phase times, solved in build()
var _wake_end: float
var _step_end: float
var _climb_top: float
var _climb_end: float
var _drop_end: float
var _walk_end: float


class Actor:
	var node: Node3D
	var anim: AnimationPlayer
	var clip: String = ""
	var phase: float = 0.0


func build(low_q: bool) -> void:
	low_quality = low_q
	var white := Image.create(1, 1, false, Image.FORMAT_R8)
	white.fill(Color(1.0, 1.0, 1.0))
	terrain = RtsTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(ImageTexture.create_from_image(white))
	Scenery.build(terrain, self)
	var h: Vector2 = GameConfig.HOME
	_home = Vector3(h.x, terrain.height_at(h.x, h.y), h.y)
	var tree: Node3D = get_node_or_null("HomeTree")
	var model: Node3D = null
	if tree != null and tree.get_child_count() > 0:
		model = tree.get_child(0) as Node3D
		model = _debug_tree_override(tree, model)
	_measure_trunk(model)
	_nest_top = _home + Vector3(1.6, 7.6, 0.6)
	if tree != null:
		for c: Node in tree.get_children():
			if str(c.name).begins_with("branch_heap") and c is Node3D:
				var nh: float = ModelLib.height_of("branch_heap") * (c as Node3D).scale.y
				_nest_top = (c as Node3D).global_position + Vector3(0.0, nh * 0.8, 0.0)
				break
	sun = WorldLook.make_sun(not low_quality)
	sun.name = "Sun"
	add_child(sun)
	env = WorldLook.make_environment()
	WorldLook.set_quality(env, not low_quality)
	_store_light()
	cam_attr = WorldLook.make_camera_attributes()
	_solve_end_pose()
	_make_band()
	_solve_climber_times()


## Main's opening camera (RtsCamera at GameConfig.CAM_START, default height).
func _solve_end_pose() -> void:
	var rts := RtsCamera.new()
	add_child(rts)
	rts.setup(terrain, GameConfig.CAM_START)
	_end_pos = rts.global_position
	var f: Vector2 = GameConfig.CAM_START
	_end_look = Vector3(f.x, terrain.height_at(f.x, f.y), f.y)
	_end_focus_m = _end_pos.distance_to(_end_look)
	rts.current = false
	rts.queue_free()


func _hero() -> Actor:
	var a := Actor.new()
	var ps: PackedScene = load(HERO_SCENE)
	a.node = ps.instantiate()
	add_child(a.node)
	a.anim = a.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for n: String in ["idle", "walk", "crouch", "gather", "climb_down"]:
		if a.anim.has_animation(n):
			a.anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return a


func _make_band() -> void:
	var n: int = 6
	for k in n:
		var ang: float = TAU * k / n + 0.4
		var p: Vector2 = GameConfig.HOME + Vector2(cos(ang), sin(ang)) * GameConfig.START_RING_M
		p = terrain.nearest_walkable(p)
		_slots.append(Vector3(p.x, terrain.height_at(p.x, p.y), p.y))
	_climber = _hero()
	_climber.node.name = "Climber"
	for k in n:
		if k == CLIMBER_SLOT:
			continue
		var a: Actor = _hero()
		a.node.name = "Band%d" % k
		a.phase = 0.37 * k
		var s: Vector3 = _slots[k]
		a.node.global_transform = Transform3D(Basis(Vector3.UP, _yaw_to(s, _home)), s)
		a.clip = ""
		_band.append(a)


func _solve_climber_times() -> void:
	var wake_len: float = 1.6
	if _climber.anim.has_animation("wake"):
		wake_len = _climber.anim.get_animation("wake").length
	_wake_end = WAKE_T + wake_len / WAKE_RATE
	_step_end = _wake_end + STEP_S
	_climb_top = _nest_top.y - _home.y - 0.6
	_climb_end = _step_end + (_climb_top - CLIMB_LOW_M) / CLIMB_V
	_drop_end = _climb_end + DROP_S
	var foot: Vector3 = _trunk_at(0.0)
	_walk_end = _drop_end + Vector2(foot.x, foot.z).distance_to(
		Vector2(_slots[CLIMBER_SLOT].x, _slots[CLIMBER_SLOT].z)
	) / WALK_V


## Dev check only (debug builds, env INTRO_TREE=<game model>): swap the Home Tree model, e.g. to
## test the climb on a tree whose trunk reaches the ground.
func _debug_tree_override(tree: Node3D, model: Node3D) -> Node3D:
	var want: String = OS.get_environment("INTRO_TREE")
	if want == "" or not OS.is_debug_build() or model == null:
		return model
	var n: Node3D = ModelLib.make_node(want, Transform3D(Basis(Vector3.UP, 0.4), Vector3.ZERO))
	tree.add_child(n)
	tree.move_child(n, 0)
	model.queue_free()
	return n


func _measure_trunk(model: Node3D) -> void:
	var nb: int = 24
	var sx := PackedFloat32Array()
	var sz := PackedFloat32Array()
	var cnt := PackedFloat32Array()
	sx.resize(nb)
	sz.resize(nb)
	cnt.resize(nb)
	var pts: Array[Vector3] = []
	if model != null:
		for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for s in m.mesh.get_surface_count():
				var mat: Material = m.get_surface_override_material(s)
				if mat == null:
					mat = m.mesh.surface_get_material(s)
				var bark: bool = (
					mat is BaseMaterial3D
					and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				)
				if not bark:
					continue
				var xf: Transform3D = m.global_transform
				var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in verts:
					var w: Vector3 = xf * v - _home
					if w.y < 0.0 or Vector2(w.x, w.z).length() > TRUNK_SEARCH_M:
						continue
					var b: int = int(w.y / TRUNK_BIN_M)
					if b < nb:
						sx[b] += w.x
						sz[b] += w.z
						cnt[b] += 1.0
						pts.append(w)
	_trunk_c.resize(nb)
	_trunk_r.resize(nb)
	trunk_low_m = -1.0
	for b in nb:
		if cnt[b] > 0.0:
			_trunk_c[b] = Vector3(sx[b] / cnt[b], (b + 0.5) * TRUNK_BIN_M, sz[b] / cnt[b])
			if trunk_low_m < 0.0:
				trunk_low_m = b * TRUNK_BIN_M
	for w: Vector3 in pts:
		var b: int = int(w.y / TRUNK_BIN_M)
		var c: Vector3 = _trunk_c[b]
		_trunk_r[b] = maxf(_trunk_r[b], Vector2(w.x - c.x, w.z - c.z).length() * 0.8)
	# fill empty bins from the nearest measured one (straight axis)
	for b in nb:
		if cnt[b] > 0.0:
			continue
		var best: int = -1
		for k in nb:
			if cnt[k] > 0.0 and (best < 0 or absi(k - b) < absi(best - b)):
				best = k
		var c: Vector3 = _trunk_c[best] if best >= 0 else Vector3.ZERO
		_trunk_c[b] = Vector3(c.x, (b + 0.5) * TRUNK_BIN_M, c.z)
		_trunk_r[b] = _trunk_r[best] if best >= 0 else 0.4
	if trunk_low_m > 0.6:
		push_warning(
			"IntroLocal: Home Tree bark starts %.1f m above the ground; the climb continues below it"
			% trunk_low_m
		)


## Climber origin on the south face of the trunk at height y (m over the tree's foot).
func _trunk_at(y: float) -> Vector3:
	var f: float = clampf(y / TRUNK_BIN_M - 0.5, 0.0, _trunk_c.size() - 1.001)
	var i: int = int(f)
	var c: Vector3 = _trunk_c[i].lerp(_trunk_c[i + 1], f - i)
	var r: float = clampf(lerpf(_trunk_r[i], _trunk_r[i + 1], f - i), 0.15, 0.9)
	var w: Vector3 = _home + Vector3(c.x, y, c.z)
	return w + Vector3(0.0, 0.0, r + TRUNK_GAP_M + 0.05)


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	# the body faces +Z in its own space
	return atan2(to.x - from.x, to.z - from.z)


# ------------------------------------------------------------------ per frame


func apply(t: float, cam: Camera3D) -> void:
	_apply_light(t)
	_apply_climber(t)
	for a: Actor in _band:
		var clip: String = "idle"
		_play(a, clip, t * 1.0 + a.phase, 1.0)
	_apply_camera(t, cam)


func _apply_camera(t: float, cam: Camera3D) -> void:
	var keys: Array[Array] = CAM_KEYS
	var n: int = keys.size()
	var ps: Array[Vector3] = []
	var ls: Array[Vector3] = []
	var ts := PackedFloat32Array()
	var fs := PackedFloat32Array()
	for i in n:
		ts.append(float(keys[i][0]))
		fs.append(float(keys[i][3]))
		if i == n - 1:
			ps.append(_end_pos)
			ls.append(_end_look)
		else:
			ps.append(_home + (keys[i][1] as Vector3))
			ls.append(_home + (keys[i][2] as Vector3))
	var pos: Vector3 = _spline(ts, ps, t)
	var look: Vector3 = _spline(ts, ls, t)
	var w: float = smoothstep(TRACK_HERO.x, TRACK_HERO.y, t) * (
		1.0 - smoothstep(TRACK_HERO.z, TRACK_HERO.w, t)
	)
	var hero_chest: Vector3 = _climber.node.global_position + Vector3(0.0, 0.85, 0.0)
	look = look.lerp(hero_chest, w * 0.85)
	var gy: float = terrain.height_at(pos.x, pos.z)
	pos.y = maxf(pos.y, gy + CAM_CLEAR_M)
	cam.global_transform = Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)
	cam.fov = _spline_f(ts, fs, t)
	cam.near = 0.1 if t > 74.0 else 0.5
	cam.far = 4000.0
	# depth of field: none on the landscape, soft background behind the hero, the game's
	# tilt-shift at the end (as RtsCamera sets it)
	cam.attributes = cam_attr
	var focus: float = pos.distance_to(look)
	var hero_dof: float = w
	var end_k: float = smoothstep(88.0, IntroConfig.LOCAL_END_T, t)
	if low_quality:
		cam_attr.dof_blur_far_enabled = false
		cam_attr.dof_blur_near_enabled = false
	elif end_k > 0.0:
		WorldLook.update_tilt_shift(cam_attr, lerpf(focus, _end_focus_m, end_k), true)
		cam_attr.dof_blur_amount = lerpf(0.04, 0.06, end_k)
	else:
		cam_attr.dof_blur_near_enabled = false
		cam_attr.dof_blur_far_enabled = hero_dof > 0.01
		cam_attr.dof_blur_far_distance = focus + 3.0
		cam_attr.dof_blur_far_transition = 9.0
		cam_attr.dof_blur_amount = 0.04 * hero_dof


func _apply_climber(t: float) -> void:
	var a: Actor = _climber
	var stand: Vector3 = _trunk_at(_climb_top)
	var nest: Vector3 = _nest_top
	if t < _wake_end:
		var ct: float = maxf(t - WAKE_T, 0.0) * WAKE_RATE
		_play(a, "wake", ct, 0.0 if t < WAKE_T else WAKE_RATE)
		_place(a, nest, _yaw_to(nest, stand) + PI * 0.5)
	elif t < _step_end:
		var u: float = (t - _wake_end) / STEP_S
		var p: Vector3 = nest.lerp(stand + Vector3(0.0, 0.25, 0.0), smoothstep(0.0, 1.0, u))
		_play(a, "walk", t - _wake_end, 0.8)
		_place(a, p, lerp_angle(_yaw_to(nest, stand), PI, smoothstep(0.4, 1.0, u)))
	elif t < _climb_end:
		var d: float = (t - _step_end) * CLIMB_V
		var p: Vector3 = _trunk_at(_climb_top - d)
		_play(a, "climb_down", d / CLIMB_CYCLE_M, CLIMB_V / CLIMB_CYCLE_M)
		_place(a, p, PI)
	elif t < _drop_end:
		var u: float = (t - _climb_end) / DROP_S
		var p0: Vector3 = _trunk_at(CLIMB_LOW_M)
		var g: Vector3 = p0 + Vector3(0.0, 0.0, 0.35)
		g.y = terrain.height_at(g.x, g.z)
		var p: Vector3 = p0.lerp(g, u)
		p.y += sin(u * PI) * 0.12
		_play(a, "crouch", t - _climb_end, 1.0)
		_place(a, p, PI)
	else:
		var foot: Vector3 = _trunk_at(CLIMB_LOW_M) + Vector3(0.0, 0.0, 0.35)
		var slot: Vector3 = _slots[CLIMBER_SLOT]
		var u: float = clampf((t - _drop_end) / maxf(_walk_end - _drop_end, 0.01), 0.0, 1.0)
		var p: Vector3 = foot.lerp(slot, u)
		p.y = terrain.height_at(p.x, p.z)
		if u < 1.0:
			_play(a, "walk", t - _drop_end, WALK_V / WALK_CLIP_V)
			_place(a, p, _yaw_to(foot, slot))
		else:
			_play(a, "idle", t - _walk_end, 1.0)
			var turn: float = smoothstep(0.0, 1.2, t - _walk_end)
			_place(a, p, lerp_angle(_yaw_to(foot, slot), _yaw_to(slot, _home), turn))


func _place(a: Actor, p: Vector3, yaw: float) -> void:
	a.node.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)


## Plays `clip` at clip time `ct` (seconds, wrapped for loops). Live: the player runs at `rate`
## and blends clip changes; capture: exact pose, no blend.
func _play(a: Actor, clip: String, ct: float, rate: float) -> void:
	if a.anim == null or not a.anim.has_animation(clip):
		return
	var anim: Animation = a.anim.get_animation(clip)
	var len_s: float = maxf(anim.length, 0.001)
	var at: float = fposmod(ct, len_s) if anim.loop_mode != Animation.LOOP_NONE else minf(ct, len_s)
	if a.clip != clip:
		a.anim.play(clip, 0.25 if live else 0.0)
		a.clip = clip
		a.anim.seek(at, true)
	elif not live or absf(a.anim.current_animation_position - at) > 0.2:
		a.anim.seek(at, true)
	a.anim.speed_scale = rate if live else 0.0


# ------------------------------------------------------------------ light


func _store_light() -> void:
	for k: String in [
		"fog_light_color", "fog_density", "fog_sun_scatter", "fog_aerial_perspective",
		"volumetric_fog_density", "volumetric_fog_albedo", "volumetric_fog_anisotropy",
		"ambient_light_energy", "background_energy_multiplier", "adjustment_saturation",
		"adjustment_contrast", "tonemap_exposure", "glow_intensity", "fog_sky_affect",
	]:
		_base[k] = env.get(k)
	_gold = _base.duplicate()
	_gold["fog_light_color"] = GOLD_HAZE
	_gold["fog_density"] = 0.0016
	_gold["fog_sun_scatter"] = 0.45
	_gold["fog_aerial_perspective"] = 0.45
	_gold["fog_sky_affect"] = 0.35
	_gold["volumetric_fog_density"] = 0.0045
	_gold["volumetric_fog_albedo"] = Color(1.0, 0.93, 0.82)
	_gold["volumetric_fog_anisotropy"] = 0.7
	_gold["ambient_light_energy"] = 0.65
	_gold["adjustment_saturation"] = 1.25
	_gold["adjustment_contrast"] = 1.12
	_gold["tonemap_exposure"] = 1.05
	_gold["glow_intensity"] = 0.7


## 0 = golden hour, 1 = the game's light.
func light_k(t: float) -> float:
	return smoothstep(LIGHT_TURN.x, LIGHT_TURN.y, t)


func _apply_light(t: float) -> void:
	var k: float = light_k(t)
	for key: String in _base:
		var a: Variant = _gold[key]
		var b: Variant = _base[key]
		if a is Color:
			env.set(key, (a as Color).lerp(b as Color, k))
		else:
			env.set(key, lerpf(float(a), float(b), k))
	var el: float = deg_to_rad(lerpf(GOLD_ELEV_DEG, WorldLook.SUN_ELEV_DEG, k))
	var az: float = deg_to_rad(WorldLook.SUN_AZ_DEG)
	var d := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
	sun.basis = Basis.looking_at(-d, Vector3.UP)
	sun.light_color = GOLD_SUN.lerp(WorldLook.SUN_COLOUR, k)
	sun.light_energy = lerpf(GOLD_SUN_ENERGY, WorldLook.SUN_ENERGY, k)
	sun.directional_shadow_max_distance = lerpf(
		420.0, 140.0, smoothstep(66.0, 74.0, t)
	) if k <= 0.0 else 140.0


# ------------------------------------------------------------------ curves


## Catmull-Rom through (ts, ps) with non-uniform times; clamped at the ends.
static func _spline(ts: PackedFloat32Array, ps: Array[Vector3], t: float) -> Vector3:
	var n: int = ts.size()
	if t <= ts[0]:
		return ps[0]
	if t >= ts[n - 1]:
		return ps[n - 1]
	var i: int = 0
	while i < n - 2 and t > ts[i + 1]:
		i += 1
	var h: float = ts[i + 1] - ts[i]
	var m0: Vector3 = Vector3.ZERO
	var m1: Vector3 = Vector3.ZERO
	if i > 0:
		m0 = (ps[i + 1] - ps[i - 1]) / (ts[i + 1] - ts[i - 1])
	if i + 2 < n:
		m1 = (ps[i + 2] - ps[i]) / (ts[i + 2] - ts[i])
	var s: float = (t - ts[i]) / h
	var s2: float = s * s
	var s3: float = s2 * s
	return (
		(2.0 * s3 - 3.0 * s2 + 1.0) * ps[i]
		+ (s3 - 2.0 * s2 + s) * h * m0
		+ (-2.0 * s3 + 3.0 * s2) * ps[i + 1]
		+ (s3 - s2) * h * m1
	)


static func _spline_f(ts: PackedFloat32Array, fs: PackedFloat32Array, t: float) -> float:
	var ps: Array[Vector3] = []
	for f: float in fs:
		ps.append(Vector3(f, 0.0, 0.0))
	return _spline(ts, ps, t).x
