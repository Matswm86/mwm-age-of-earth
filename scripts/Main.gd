class_name Main
extends Node3D

## The game scene: the Age 1 opening on the Rift Lake map (GDD 11, ~10 minutes playable).
## Builds the lit world (WorldLook), the real terrain and lake (RtsTerrain), vegetation (Dressing),
## the hominins (Units, VAT bodies), wildlife (Animals), the economy (Game), the HUD and the
## onboarding hints, then runs a fixed SIM_HZ simulation (45 ticks per real second at 1.5x) with
## interpolated rendering. Touch (GDD 8): tap select, double-tap selects that type on screen, drag
## box, tap ground to move, tap a resource to gather, tap your unfinished building to build,
## two-finger pan, pinch zoom, command card for buildings / training / the Stone That Cuts.
## The tech-spike Bench stays: Menu -> Bench all (it replaces the match with the 150-210 unit
## crowds, then reloads the scene). User arg `--bench` (or `--bench=<seconds>`) benches and quits.

var preset: int = SpikeConfig.DEFAULT_PRESET
var speed: float = 1.0
var quality: int = 0
var fog_on: bool = true
var terrain: RtsTerrain
var dressing: Dressing
var grass: GrassField
var reeds: GrassField
var foot_dust: FootDust
var units: Units
var animals: Animals
var game: Game
var fog: FogOfWar
var cam: RtsCamera
var sun: DirectionalLight3D
var env: Environment
var marks: GroundMarks
## Rings, markers and footprints that must not be cut by the terrain (no depth test).
var overlay: GroundMarks
var hud: Hud
var auto_quality: AutoQuality
var icons: IconBaker
var bench: Bench
## True once the bench has replaced the match with crowds (no economy ticks).
var bench_mode: bool = false
var sim_ms: float = 0.0
var fog_ms: float = 0.0
var buffer_ms: float = 0.0
var last_flow_ms: float = 0.0
var flow_max_ms: float = 0.0
## Selected own building index, or -1 (units and a building are never selected together).
var sel_building: int = -1
## Building type being placed ("" when not placing), ghost node and spot.
var placing: String = ""
var ghost: Node3D
var ghost_at := Vector2.INF
var ghost_ok: bool = false

var _acc: float = 0.0
var _fog_timer: float = 0.0
var _status_timer: float = 0.0
var _card_timer: float = 0.0
var _select_box: SelectBox
var _marker_at := Vector3.INF
var _marker_t: float = 0.0
var _marker_col := GameConfig.SELECT
var _touches: Dictionary = {}
var _start: Vector2 = Vector2.ZERO
var _boxing: bool = false
var _multi: bool = false
var _pinch_mid: Vector2 = Vector2.ZERO
var _pinch_dist: float = 0.0
var _last_tap_t: float = -10.0
var _last_tap_unit: int = -1
var _flow_tasks: Array = []
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
## onboarding: hint id -> true once done; current hint id
var _hints_done: Dictionary = {}
var _hint_now: String = ""
var _predator_hint_t: float = 0.0


func _ready() -> void:
	fog = FogOfWar.new()
	_make_world()
	terrain = RtsTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(fog.texture)
	dressing = Dressing.new()
	dressing.name = "Dressing"
	add_child(dressing)
	dressing.build(terrain, Game.exclusions())
	grass = GrassField.create(self, terrain, fog.texture, false)
	reeds = GrassField.create(self, terrain, fog.texture, true)
	marks = GroundMarks.new()
	add_child(marks)
	overlay = GroundMarks.new(true)
	add_child(overlay)
	units = Units.new()
	units.name = "Units"
	add_child(units)
	units.setup(terrain, fog, marks)
	animals = Animals.new()
	animals.name = "Animals"
	add_child(animals)
	animals.setup(terrain, fog, marks)
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.setup(self)
	game.start_match()
	cam = RtsCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.setup(terrain, GameConfig.CAM_START)
	grass.follow(cam)
	reeds.follow(cam)
	_make_ghost_materials()
	foot_dust = FootDust.create(self)
	icons = IconBaker.new()
	icons.name = "Icons"
	add_child(icons)
	icons.bake(_icon_spec())
	hud = Hud.new()
	hud.icons = icons.icons
	hud.cam = cam
	add_child(hud)
	_select_box = SelectBox.new()
	_select_box.visible = false
	hud.root.add_child(_select_box)
	_connect_hud()
	_connect_game()
	bench = Bench.new()
	bench.main = self
	add_child(bench)
	_add_buttons()
	auto_quality = AutoQuality.attach(self)
	set_speed(1.0)
	PerfOverlay.set_ui_visible(false)
	_on_resources()
	_refresh_card()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--bench" or arg.begins_with("--bench="):
			var secs: float = SpikeConfig.BENCH_SECONDS
			if arg.begins_with("--bench="):
				secs = arg.get_slice("=", 1).to_float()
			_run_bench_and_quit.call_deferred(secs)


func _make_world() -> void:
	var we := WorldEnvironment.new()
	env = WorldLook.make_environment()
	add_child(Backdrop.new())
	we.environment = env
	add_child(we)
	sun = WorldLook.make_sun()
	add_child(sun)


func _icon_spec() -> Dictionary:
	var body := func() -> Node3D:
		var ps: PackedScene = load("res://assets/vat/australopith.glb")
		return ps.instantiate() as Node3D
	return {
		"forager": [body, 0.5, 8.0],
		"food": [func() -> Node3D: return Kit.tuber_pile(), 0.4, 40.0],
		"wood":
		[
			func() -> Node3D: return ModelLib.make_node("dead_branch", Transform3D.IDENTITY),
			0.6,
			35.0
		],
		"stone":
		[
			func() -> Node3D:
				return ModelLib.make_node(
					"cobbles", Transform3D.IDENTITY, {"tint": Kit.BASALT, "saturation": 0.5}
				),
			0.3,
			40.0
		],
		"home":
		[func() -> Node3D: return Kit.home_tree_model(), 0.4, 15.0],
		"nest_grove": [func() -> Node3D: return Kit.nest_grove(), 0.3, 30.0],
		"cache": [func() -> Node3D: return Kit.cache(), 0.5, 35.0],
		"knapping_floor":
		[
			func() -> Node3D:
				return ModelLib.make_node(
					"lithic_core",
					Transform3D.IDENTITY,
					{"tint": Color(0.5, 0.5, 0.5), "saturation": 0.15}
				),
			0.8,
			45.0
		],
		"stone_that_cuts":
		[func() -> Node3D: return ModelLib.make_node("hand_axe", Transform3D.IDENTITY), 0.2, 50.0],
		"fig": [func() -> Node3D: return Kit.fig_bush(), 0.2, 20.0],
		"stop":
		[
			func() -> Node3D:
				return ModelLib.make_node("boulder_c", Transform3D.IDENTITY, {"tint": Kit.BASALT}),
			0.3,
			30.0
		],
	}


func _make_ghost_materials() -> void:
	_ghost_ok_mat = StandardMaterial3D.new()
	_ghost_ok_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_ok_mat.albedo_color = Color(GameConfig.SELECT, 0.35)
	_ghost_ok_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_ok_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ghost_bad_mat = _ghost_ok_mat.duplicate() as StandardMaterial3D
	_ghost_bad_mat.albedo_color = Color(GameConfig.ATTACK, 0.45)


func _connect_hud() -> void:
	hud.card_pressed.connect(_on_card)
	hud.idle_pressed.connect(_on_idle)
	hud.home_pressed.connect(_on_home)
	hud.clear_pressed.connect(func() -> void: _clear_selection())
	hud.menu_pressed.connect(
		func() -> void: PerfOverlay.set_ui_visible(not PerfOverlay.is_ui_visible())
	)
	hud.place_answer.connect(_on_place_answer)


func _connect_game() -> void:
	game.resources_changed.connect(_on_resources)
	game.dropped.connect(func(w: Vector3, t: String) -> void: hud.float_text(w, t))
	game.banner.connect(func(t: String) -> void: hud.show_banner(t))
	game.building_placed.connect(func(k: int) -> void: _dust(game.buildings[k].node.position, 20))
	game.building_finished.connect(_on_building_finished)
	game.unit_trained.connect(func(_u: int) -> void: _refresh_card())
	game.tech_finished.connect(_on_tech_finished)


func _add_buttons() -> void:
	PerfOverlay.add_button("preset", "", _next_preset)
	PerfOverlay.add_button("speed", "", func() -> void: set_speed(1.5 if speed < 1.25 else 1.0))
	PerfOverlay.add_button("quality", "", func() -> void: auto_quality.cycle())
	PerfOverlay.add_button("bench", "Bench all", func() -> void: _on_bench())
	PerfOverlay.add_button("select", "Select all", select_all)
	PerfOverlay.add_button("fog", "Fog: on", func() -> void: set_fog(not fog_on))
	PerfOverlay.add_button("result", "Hide result", PerfOverlay.hide_result)
	PerfOverlay.add_button(
		"restart", "Restart match", func() -> void: get_tree().reload_current_scene()
	)
	PerfOverlay.set_button_text("preset", "Crowd test")


func _next_preset() -> void:
	apply_preset((preset + 1) % SpikeConfig.PRESETS.size())


## Bench / crowd test: replaces the match's hominins with a 150-210 unit crowd.
func apply_preset(i: int) -> void:
	preset = i
	bench_mode = true
	_clear_selection()
	var p: Dictionary = SpikeConfig.PRESETS[i]
	units.spawn(int(p["teams"]), int(p["per_team"]))
	if fog_on:
		fog.reset()
		fog.update(units.cell, units.team, units.count)
	_fog_timer = 1.0 / SpikeConfig.FOG_HZ
	_acc = 0.0
	PerfOverlay.set_button_text("preset", "Units: %d" % units.count)


func set_fog(on: bool) -> void:
	fog_on = on
	units.fog_off = not on
	animals.reveal_all = not on
	if on:
		fog.reset()
		_update_fog()
	else:
		fog.set_all_visible()
	PerfOverlay.set_button_text("fog", "Fog: on" if on else "Fog: off")


func set_speed(s: float) -> void:
	speed = s
	PerfOverlay.set_button_text("speed", "Speed %.1fx" % speed)


func apply_quality(q: int) -> void:
	quality = q
	var d: Dictionary = SpikeConfig.QUALITY[q]
	var vp := get_viewport()
	vp.scaling_3d_scale = float(d["scale"])
	vp.msaa_3d = d["msaa"]
	sun.shadow_enabled = bool(d["shadows"])
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	WorldLook.set_quality(env, bool(d["effects"]))
	cam.tilt_shift = bool(d["effects"])
	grass.set_quality(float(d["grass"]))
	reeds.set_quality(float(d["grass"]))
	cam.apply()
	units.set_mesh_quality(q)
	PerfOverlay.set_button_text("quality", AutoQuality.label(self))


func select_all() -> void:
	units.set_selection(units.ids_of_team(0))
	sel_building = -1
	_after_selection()


## Starts a flow field to `goal` on a worker thread and returns it (not built yet).
func start_flow(goal: Vector2) -> FlowField:
	var ff := FlowField.new()
	ff.set_target(terrain.nearest_walkable(goal))
	var blk: PackedByteArray = terrain.blocked
	var id: int = WorkerThreadPool.add_task(ff.build.bind(blk), false, "flow field")
	_flow_tasks.append([id, ff])
	return ff


func _poll_flow_tasks() -> void:
	var k: int = 0
	while k < _flow_tasks.size():
		var entry: Array = _flow_tasks[k]
		var id: int = entry[0]
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			var ff: FlowField = entry[1]
			ff.is_built = true
			last_flow_ms = ff.build_ms
			flow_max_ms = maxf(flow_max_ms, ff.build_ms)
			_flow_tasks.remove_at(k)
		else:
			k += 1


## Bench: gives every unit of team `t` a move order to `goal`.
func order_team(t: int, goal: Vector2) -> FlowField:
	var ff: FlowField = start_flow(goal)
	units.order_move(units.ids_of_team(t), ff)
	return ff


func _on_bench(seconds: float = SpikeConfig.BENCH_SECONDS) -> void:
	if bench.running:
		return
	PerfOverlay.hide_result()
	PerfOverlay.set_buttons_enabled(false)
	var text: String = await bench.run_all(seconds)
	PerfOverlay.set_buttons_enabled(true)
	PerfOverlay.show_result(text)


func _run_bench_and_quit(seconds: float) -> void:
	await _on_bench(seconds)
	get_tree().quit()


# --- frame ---


func _process(delta: float) -> void:
	_poll_flow_tasks()
	var gdt: float = delta * speed
	var tick: float = 1.0 / SpikeConfig.SIM_HZ
	_acc += gdt
	var t0: int = Time.get_ticks_usec()
	var ticks: int = 0
	while _acc >= tick and ticks < SpikeConfig.MAX_TICKS_PER_FRAME:
		units.tick(tick)
		if not bench_mode:
			game.game_tick(tick)
		animals.tick(tick)
		_acc -= tick
		ticks += 1
	if ticks == SpikeConfig.MAX_TICKS_PER_FRAME:
		_acc = minf(_acc, tick)
	sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	units.anim_time += gdt
	_fog_timer -= gdt
	fog_ms = 0.0
	if _fog_timer <= 0.0 and fog_on:
		_fog_timer = maxf(_fog_timer + 1.0 / SpikeConfig.FOG_HZ, 0.0)
		_update_fog()
		fog_ms = fog.update_ms
	var t2: int = Time.get_ticks_usec()
	marks.begin()
	overlay.begin()
	units.render(_acc / tick)
	animals.render()
	_extra_marks(delta)
	marks.finish()
	overlay.finish()
	buffer_ms = (Time.get_ticks_usec() - t2) / 1000.0
	if not bench_mode:
		hud.set_clock(game.time)
		_card_timer -= delta
		if _card_timer <= 0.0:
			_card_timer = 0.25
			_refresh_card()
			_refresh_selection_text()
			hud.set_idle(game.idle_foragers().size())
		_update_hints(delta)
	foot_dust.tick(delta, units, quality == 0)
	WorldLook.per_frame(sun, cam, units)
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.25
		PerfOverlay.status_line = (
			"%d units (%d drawn, %d sel) %d animals %.1fx %s\nsim %.2f ms  buffer %.2f ms  flow %.1f ms"
			% [
				units.count,
				units.visible_count,
				units.selected_count,
				animals.visible_count,
				speed,
				SpikeConfig.QUALITY[quality]["name"],
				sim_ms,
				buffer_ms,
				last_flow_ms,
			]
		)


func _update_fog() -> void:
	var extra := PackedInt32Array()
	if not bench_mode:
		for b in game.buildings:
			extra.append(terrain.cell_of(b.pos))
	fog.update(units.cell, units.team, units.count, extra)


func _extra_marks(delta: float) -> void:
	if _marker_t > 0.0:
		_marker_t -= delta
		var k: float = 1.0 - clampf(_marker_t / 0.3, 0.0, 1.0)
		var r: float = lerpf(1.0, 0.3, k)
		var p := Vector2(_marker_at.x, _marker_at.z)
		overlay.add(_marker_at, terrain.normal_at(p.x, p.y), r, _marker_col, GroundMarks.MODE_RING)
	if sel_building >= 0 and not bench_mode:
		var b: Game.Bld = game.buildings[sel_building]
		var g := Vector3(b.pos.x, terrain.height_at(b.pos.x, b.pos.y), b.pos.y)
		overlay.add(g, Vector3.UP, b.radius + 0.5, GameConfig.SELECT, GroundMarks.MODE_RING)
	if placing != "" and ghost_at != Vector2.INF:
		var r2: float = float(GameConfig.FOOTPRINT.get(placing, 4.0)) * 0.5
		var c: Color = GameConfig.SELECT if ghost_ok else GameConfig.ATTACK
		var g2 := Vector3(ghost_at.x, terrain.height_at(ghost_at.x, ghost_at.y), ghost_at.y)
		overlay.add(g2, Vector3.UP, r2, c, GroundMarks.MODE_FOOTPRINT)


# --- HUD wiring ---


func _on_resources() -> void:
	hud.set_resources(game.res, game.pop(), game.pop_cap)
	_card_timer = 0.0


func _selected_foragers() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in units.selected_ids():
		if units.team[i] == 0:
			out.append(i)
	return out


func _cost_caption(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	var short: Dictionary = {"food": "F", "wood": "W", "stone": "S", "ochre": "O"}
	for k: String in ["food", "wood", "stone", "ochre"]:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d%s" % [int(cost[k]), short[k]])
	return " ".join(parts)


func _refresh_card() -> void:
	if bench_mode:
		hud.set_card([])
		return
	var entries: Array = []
	if placing != "":
		hud.set_card([])
		return
	if units.selected_count > 0:
		for type: String in GameConfig.BUILD_MENU:
			var cost: Dictionary = Balance.cost_of(Balance.building(type))
			entries.append(
				{
					"id": "build:" + type,
					"icon": type,
					"caption": _cost_caption(cost),
					"enabled": game.can_afford(cost)
				}
			)
		entries.append({"id": "stop", "icon": "stop", "caption": "Stop", "enabled": true})
	elif sel_building >= 0:
		var b: Game.Bld = game.buildings[sel_building]
		var busy: Dictionary = game.busy_of(sel_building)
		if b.done and b.type == "home_tree":
			var why: String = game.can_train(sel_building)
			var cap: String = _cost_caption(Balance.cost_of(Balance.unit("forager")))
			if busy.get("kind", "") == "forager":
				cap = "x%d" % int(busy.get("count", 1))
			(
				entries
				. append(
					{
						"id": "train:forager",
						"icon": "forager",
						"caption": cap,
						"enabled": why == "",
						"progress":
						float(busy.get("frac", 0.0)) if busy.get("kind", "") == "forager" else 0.0,
					}
				)
			)
		elif b.done and b.type == "knapping_floor":
			var tid: String = "stone_that_cuts"
			var why2: String = game.can_research(sel_building, tid)
			var cap2: String = (
				"Done" if why2 == "done" else _cost_caption(Balance.cost_of(Balance.tech(tid)))
			)
			(
				entries
				. append(
					{
						"id": "tech:" + tid,
						"icon": tid,
						"caption": cap2,
						"enabled": why2 == "",
						"progress":
						float(busy.get("frac", 0.0)) if busy.get("kind", "") == tid else 0.0,
					}
				)
			)
	hud.set_card(entries)


func _refresh_selection_text() -> void:
	if units.selected_count > 0:
		var gathering: int = 0
		var carrying: int = 0
		for i in units.selected_ids():
			if game.job[i] == Game.Job.GATHER or game.job[i] == Game.Job.GO_GATHER:
				gathering += 1
			if game.carry_amt[i] > 0.5:
				carrying += 1
		var t: String = (
			"Forager x%d" % units.selected_count if units.selected_count > 1 else "Forager"
		)
		if gathering > 0:
			t += "  ·  %d gathering" % gathering
		hud.set_selection("forager", t)
	elif sel_building >= 0:
		var b: Game.Bld = game.buildings[sel_building]
		var name: String = str(GameConfig.BUILD_NAMES.get(b.type, b.type))
		var t2: String = name
		if not b.done:
			t2 += "  ·  building %d%%" % int(b.progress * 100.0)
		elif b.type == "home_tree" and not b.queue.is_empty() and game.pop_blocked():
			t2 += "  ·  needs a Nest Grove"
		elif b.research != "":
			t2 += "  ·  discovering"
		var icon: String = "home" if b.type == "home_tree" else b.type
		hud.set_selection(icon, t2)
	else:
		hud.set_selection("", "")


func _on_card(id: String) -> void:
	if id.begins_with("build:"):
		_begin_placing(id.trim_prefix("build:"))
	elif id == "stop":
		game.stop_units(_selected_foragers())
	elif id == "train:forager" and sel_building >= 0:
		if game.queue_forager(sel_building):
			_hints_done["train"] = true
	elif id.begins_with("tech:") and sel_building >= 0:
		game.start_research(sel_building, id.trim_prefix("tech:"))
	_card_timer = 0.0


func _on_idle() -> void:
	var idle: PackedInt32Array = game.idle_foragers()
	if idle.is_empty():
		return
	var pick: int = idle[0]
	for k in idle.size():
		if units.selected_count == 1 and units.selected[idle[k]] == 1:
			pick = idle[(k + 1) % idle.size()]
	units.set_selection(PackedInt32Array([pick]))
	sel_building = -1
	cam.focus = units.pos[pick]
	_after_selection()


func _on_home() -> void:
	_clear_selection()
	sel_building = 0
	cam.focus = game.buildings[0].pos + Vector2(0.0, 6.0)
	_after_selection()


func _clear_selection() -> void:
	units.set_selection(PackedInt32Array())
	sel_building = -1
	_after_selection()


func _after_selection() -> void:
	_card_timer = 0.0
	_refresh_card()
	_refresh_selection_text()


func _on_building_finished(k: int) -> void:
	_dust(game.buildings[k].node.position, 8)
	hud.show_banner("%s ready" % str(GameConfig.BUILD_NAMES.get(game.buildings[k].type, "")))
	_card_timer = 0.0


func _on_tech_finished(_id: String) -> void:
	for b in game.buildings:
		if b.type == "knapping_floor":
			_sparkle(b.node.position + Vector3(0, 0.3, 0))


# --- placement (GDD 8: ghost follows the finger; release shows a tick and a cross) ---


func _begin_placing(type: String) -> void:
	_cancel_placing()
	placing = type
	ghost = Kit.building(type)
	ghost.name = "Ghost"
	add_child(ghost)
	Kit.set_transparency(ghost, 0.45)
	var mid: Vector2 = get_viewport().get_visible_rect().size * 0.5
	_move_ghost(mid)
	_refresh_card()


func _move_ghost(screen: Vector2) -> void:
	var hit: Vector3 = terrain.ray_hit(
		cam.project_ray_origin(screen), cam.project_ray_normal(screen)
	)
	if hit == Vector3.INF:
		return
	ghost_at = Vector2(hit.x, hit.z)
	ghost.position = Vector3(hit.x, terrain.height_at(hit.x, hit.z), hit.z)
	ghost_ok = (
		game.place_problem(placing, ghost_at) == ""
		and game.can_afford(Balance.cost_of(Balance.building(placing)))
	)
	Kit.set_overlay(ghost, _ghost_ok_mat if ghost_ok else _ghost_bad_mat)


func _on_place_answer(ok: bool) -> void:
	if ok and placing != "" and ghost_ok:
		var k: int = game.place_building(placing, ghost_at, _selected_foragers())
		if k >= 0:
			_hints_done[placing] = true
	_cancel_placing()


func _cancel_placing() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	placing = ""
	ghost_at = Vector2.INF
	hud.show_place_confirm(Vector3.INF, false)
	_card_timer = 0.0


# --- feedback FX (GDD 12) ---


func _dust(at: Vector3, n: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0.0, -0.6, 0.0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.6
	p.mesh = _soft_quad(Color(0.549, 0.482, 0.376, 0.4), 1.2)
	p.position = at + Vector3(0.0, 0.3, 0.0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _sparkle(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.mesh = _soft_quad(Color(1.6, 1.4, 1.0, 1.0), 0.18)
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


func _soft_quad(col: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = gt
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q


# --- onboarding (GDD 11.2): ring + icon + at most 6 words, each once, dismissed by doing it ---


func _update_hints(delta: float) -> void:
	var want: String = ""
	var world := Vector3.INF
	var screen := Vector2.INF
	var icon: String = ""
	var red: bool = false
	if units.selected_count > 0:
		_hints_done["select"] = true
	for i in units.count:
		if units.team[i] == 0 and game.job[i] in [Game.Job.GO_GATHER, Game.Job.GATHER]:
			_hints_done["gather"] = true
	# predator alarm beats everything for 4 s, once
	var hy: Vector2 = animals.hyena_pos()
	if not _hints_done.has("predator") and hy != Vector2.INF:
		for i in units.count:
			if units.team[i] == 0 and units.pos[i].distance_to(hy) < 16.0:
				_predator_hint_t = 4.0
				_hints_done["predator"] = true
				break
	if _predator_hint_t > 0.0:
		_predator_hint_t -= delta
		want = GameConfig.HINT_PREDATOR
		world = Vector3(hy.x, terrain.height_at(hy.x, hy.y) + 0.6, hy.y)
		red = true
	elif not _hints_done.has("select"):
		want = GameConfig.HINT_SELECT
		var u: int = units.ids_of_team(0)[0]
		world = Vector3(units.pos[u].x, units.hgt[u] + 0.7, units.pos[u].y)
		icon = "forager"
	elif not _hints_done.has("gather"):
		want = GameConfig.HINT_GATHER
		var nd: Game.ResNode = game.nodes[0]
		world = Vector3(nd.pos.x, terrain.height_at(nd.pos.x, nd.pos.y) + 1.0, nd.pos.y)
		icon = "fig"
	elif not _hints_done.has("nest_grove") and game.pop() >= game.pop_cap:
		want = GameConfig.HINT_NEST
		icon = "nest_grove"
		screen = hud.card_button_centre("build:nest_grove")
		if screen == Vector2.INF:
			var u2: int = units.ids_of_team(0)[0]
			world = Vector3(units.pos[u2].x, units.hgt[u2] + 0.7, units.pos[u2].y)
	elif not _hints_done.has("train") and game.pop() < game.pop_cap:
		want = GameConfig.HINT_TRAIN
		icon = "forager"
		screen = hud.card_button_centre("train:forager")
		if screen == Vector2.INF:
			var h: Vector2 = game.buildings[0].pos
			world = Vector3(h.x, terrain.height_at(h.x, h.y) + 4.0, h.y)
	elif not _hints_done.has("knapping_floor") and game.time >= GameConfig.HINT_KNAP_AT_S:
		want = GameConfig.HINT_KNAP
		icon = "knapping_floor"
		screen = hud.card_button_centre("build:knapping_floor")
		if screen == Vector2.INF:
			var u3: int = units.ids_of_team(0)[0]
			world = Vector3(units.pos[u3].x, units.hgt[u3] + 0.7, units.pos[u3].y)
	if placing != "":
		want = ""
	_hint_now = want
	hud.set_hint(want, world, icon, screen, red)


# --- input (GDD 8) ---


func _unhandled_input(event: InputEvent) -> void:
	if bench.running:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom_by(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom_by(1.1)


func _over_ui(p: Vector2) -> bool:
	return PerfOverlay.is_over_ui(p) or (hud != null and hud.is_over_ui(p))


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _touches.is_empty() and _over_ui(e.position):
			return
		_touches[e.index] = e.position
		if _touches.size() == 1 and not _multi:
			_start = e.position
			_boxing = false
			if placing != "":
				hud.show_place_confirm(Vector3.INF, false)
				_move_ghost(e.position)
		elif _touches.size() >= 2:
			_multi = true
			_boxing = false
			_select_box.hide_rect()
			_pinch_start()
		return
	if not _touches.has(e.index):
		return
	if not _multi and _touches.size() == 1:
		if placing != "":
			_move_ghost(e.position)
			hud.show_place_confirm(ghost.position, ghost_ok)
		elif _boxing:
			_select_box.hide_rect()
			box_select(_start, e.position)
		else:
			tap(e.position)
	_touches.erase(e.index)
	_boxing = false
	if _touches.is_empty():
		_multi = false
	elif _touches.size() >= 2:
		_pinch_start()


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _multi:
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[1]
			var mid: Vector2 = (a + b) * 0.5
			var dist: float = maxf(a.distance_to(b), 1.0)
			cam.pan_pixels(mid - _pinch_mid)
			cam.zoom_by(_pinch_dist / dist)
			_pinch_mid = mid
			_pinch_dist = dist
		return
	if placing != "":
		_move_ghost(e.position)
		return
	if not _boxing and e.position.distance_to(_start) > SpikeConfig.DRAG_START_PX:
		_boxing = true
	if _boxing:
		_select_box.show_rect(_start, e.position)


func _pinch_start() -> void:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	_pinch_mid = (a + b) * 0.5
	_pinch_dist = maxf(a.distance_to(b), 1.0)


## Own unit nearest to a screen point within TAP_UNIT_PX, or -1.
func unit_at_screen(screen: Vector2) -> int:
	var best: int = -1
	var best_d: float = SpikeConfig.TAP_UNIT_PX
	for i in units.count:
		if units.team[i] != 0:
			continue
		var w := Vector3(units.pos[i].x, units.hgt[i] + 0.65, units.pos[i].y)
		if cam.is_position_behind(w):
			continue
		var d: float = cam.unproject_position(w).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	return best


## Tap (GDD 8): own unit -> select (double-tap: all own Foragers on screen); with Foragers
## selected: resource -> gather, own unfinished building -> build, ground -> move; with nothing
## selected: own building -> select it.
func tap(screen: Vector2) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var u: int = unit_at_screen(screen)
	if u >= 0:
		if u == _last_tap_unit and now - _last_tap_t < 0.35:
			var r := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			box_select(r.position, r.end)
		else:
			units.set_selection(PackedInt32Array([u]))
			sel_building = -1
			_after_selection()
		_last_tap_unit = u
		_last_tap_t = now
		return
	var hit: Vector3 = terrain.ray_hit(
		cam.project_ray_origin(screen), cam.project_ray_normal(screen)
	)
	if hit == Vector3.INF:
		return
	var g := Vector2(hit.x, hit.z)
	if bench_mode:
		var sel: PackedInt32Array = units.selected_ids()
		if not sel.is_empty():
			units.order_move(sel, start_flow(g))
			_marker(g, GameConfig.SELECT)
		return
	var ids: PackedInt32Array = _selected_foragers()
	var b: int = game.building_at(g)
	if not ids.is_empty():
		var nd: int = game.node_at(g)
		if nd >= 0:
			game.order_gather(ids, nd)
			_marker(game.nodes[nd].pos, GameConfig.SELECT)
			return
		if b >= 0 and not game.buildings[b].done:
			game.order_build(ids, b)
			_marker(game.buildings[b].pos, GameConfig.SELECT)
			return
		game.order_move(ids, g)
		_marker(g, GameConfig.SELECT)
		return
	if b >= 0:
		units.set_selection(PackedInt32Array())
		sel_building = b
		_after_selection()
	else:
		_clear_selection()


func _marker(p: Vector2, col: Color) -> void:
	_marker_at = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	_marker_t = 0.3
	_marker_col = col


## Moves the current selection to a ground point (bench / capture helper).
func move_selection(goal: Vector2) -> bool:
	var ids: PackedInt32Array = units.selected_ids()
	if ids.is_empty():
		return false
	if bench_mode:
		units.order_move(ids, start_flow(goal))
	else:
		game.order_move(ids, goal)
	_marker(goal, GameConfig.SELECT)
	return true


## Selects the player's units inside the screen rectangle a-b (replaces the selection).
func box_select(a: Vector2, b: Vector2) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	var ids := PackedInt32Array()
	for i in units.count:
		if units.team[i] != 0:
			continue
		var w := Vector3(units.pos[i].x, units.hgt[i] + 0.6, units.pos[i].y)
		if cam.is_position_behind(w):
			continue
		if r.has_point(cam.unproject_position(w)):
			ids.append(i)
	units.set_selection(ids)
	sel_building = -1
	_after_selection()
