class_name Main
extends Node3D

## Tech spike scene (go/no-go, GDD section 10): placeholder terrain and lake, up to 210
## MultiMesh hominins on a 128 x 128 flow field, fog of war, steep RTS camera, touch controls
## (GDD section 8 subset: tap select, drag box, tap to move, two-finger pan, pinch zoom).
## Game time runs a fixed SIM_HZ simulation (45 ticks per real second at 1.5x); rendering
## interpolates between ticks. Buttons on the PerfOverlay: unit preset, speed, quality, bench,
## select all, fog on/off. User arg `--bench` (or `--bench=<seconds>`) runs the bench at
## start and quits.

var preset: int = SpikeConfig.DEFAULT_PRESET
var speed: float = 1.0
var quality: int = 0
## Fog button: off = whole map visible, no fog updates (to isolate the fog cost on the device).
var fog_on: bool = true
var terrain: RtsTerrain
var units: Units
var fog: FogOfWar
var cam: RtsCamera
var sun: DirectionalLight3D
var bench: Bench
## Per-frame timings (ms) for the readout and the bench.
var sim_ms: float = 0.0
var fog_ms: float = 0.0
var buffer_ms: float = 0.0
var last_flow_ms: float = 0.0
## Slowest flow-field build since the bench last reset it (ms, worker thread).
var flow_max_ms: float = 0.0

var _acc: float = 0.0
var _fog_timer: float = 0.0
var _status_timer: float = 0.0
var _select_box: SelectBox
var _marker: MeshInstance3D
var _marker_t: float = 0.0
var _touches: Dictionary = {}
var _start: Vector2 = Vector2.ZERO
var _boxing: bool = false
var _multi: bool = false
var _pinch_mid: Vector2 = Vector2.ZERO
var _pinch_dist: float = 0.0
## Flow fields being built on worker threads: [task id, FlowField] pairs.
var _flow_tasks: Array = []


func _ready() -> void:
	fog = FogOfWar.new()
	_make_world()
	terrain = RtsTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(fog.texture)
	units = Units.new()
	units.name = "Units"
	add_child(units)
	units.setup(terrain, fog)
	cam = RtsCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.setup(terrain, SpikeConfig.BENCH_CENTRE)
	_marker = MeshInstance3D.new()
	_marker.mesh = Units.ring_mesh(1.1, 1.4)
	_marker.visible = false
	add_child(_marker)
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	_select_box = SelectBox.new()
	_select_box.visible = false
	hud.add_child(_select_box)
	bench = Bench.new()
	bench.main = self
	add_child(bench)
	_add_buttons()
	apply_quality(0)
	set_speed(1.0)
	apply_preset(preset)
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--bench" or arg.begins_with("--bench="):
			var secs: float = SpikeConfig.BENCH_SECONDS
			if arg.begins_with("--bench="):
				secs = arg.get_slice("=", 1).to_float()
			_run_bench_and_quit.call_deferred(secs)


func _make_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.64, 0.62)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# fixed late-afternoon sun from the west-south-west (GDD section 10)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.87, 0.7)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-30.0, -115.0, 0.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _add_buttons() -> void:
	PerfOverlay.add_button("preset", "", _next_preset)
	PerfOverlay.add_button("speed", "", func() -> void: set_speed(1.5 if speed < 1.25 else 1.0))
	PerfOverlay.add_button("quality", "", func() -> void: apply_quality((quality + 1) % 2))
	PerfOverlay.add_button("bench", "Bench all", func() -> void: _on_bench())
	PerfOverlay.add_button("select", "Select all", select_all)
	PerfOverlay.add_button("fog", "Fog: on", func() -> void: set_fog(not fog_on))
	PerfOverlay.add_button("result", "Hide result", PerfOverlay.hide_result)


func _next_preset() -> void:
	apply_preset((preset + 1) % SpikeConfig.PRESETS.size())


func apply_preset(i: int) -> void:
	preset = i
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
	if on:
		fog.reset()
		fog.update(units.cell, units.team, units.count)
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
	units.set_mesh_quality(q)
	PerfOverlay.set_button_text("quality", "Quality: %s" % d["name"])


func select_all() -> void:
	units.set_selection(units.ids_of_team(0))


## Starts a flow field to `goal` on a worker thread and returns it (not built yet).
func start_flow(goal: Vector2) -> FlowField:
	var ff := FlowField.new()
	ff.set_target(terrain.nearest_walkable(goal))
	var blk: PackedByteArray = terrain.blocked
	var id: int = WorkerThreadPool.add_task(ff.build.bind(blk), false, "flow field")
	_flow_tasks.append([id, ff])
	return ff


## Collects finished flow-field tasks; the field goes live on the main thread.
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


## Gives every unit of team `t` a move order to `goal`.
func order_team(t: int, goal: Vector2) -> FlowField:
	var ff: FlowField = start_flow(goal)
	units.order_move(units.ids_of_team(t), ff)
	return ff


## Moves the current selection to a ground point (world x, z). Returns false with no selection.
func move_selection(goal: Vector2) -> bool:
	var ids: PackedInt32Array = units.selected_ids()
	if ids.is_empty():
		return false
	var ff: FlowField = start_flow(goal)
	var g: Vector2 = ff.target
	units.order_move(ids, ff)
	_marker.position = Vector3(g.x, terrain.height_at(g.x, g.y) + 0.08, g.y)
	_marker.visible = true
	_marker_t = 1.2
	return true


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


func _process(delta: float) -> void:
	_poll_flow_tasks()
	var gdt: float = delta * speed
	var tick: float = 1.0 / SpikeConfig.SIM_HZ
	_acc += gdt
	var t0: int = Time.get_ticks_usec()
	var ticks: int = 0
	while _acc >= tick and ticks < SpikeConfig.MAX_TICKS_PER_FRAME:
		units.tick(tick)
		_acc -= tick
		ticks += 1
	if ticks == SpikeConfig.MAX_TICKS_PER_FRAME:
		_acc = minf(_acc, tick)
	var t1: int = Time.get_ticks_usec()
	sim_ms = (t1 - t0) / 1000.0
	units.anim_time += gdt
	_fog_timer -= gdt
	fog_ms = 0.0
	if _fog_timer <= 0.0 and fog_on:
		_fog_timer = maxf(_fog_timer + 1.0 / SpikeConfig.FOG_HZ, 0.0)
		fog.update(units.cell, units.team, units.count)
		fog_ms = fog.update_ms
	var t2: int = Time.get_ticks_usec()
	units.render(_acc / tick)
	buffer_ms = (Time.get_ticks_usec() - t2) / 1000.0
	if _marker_t > 0.0:
		_marker_t -= delta
		_marker.visible = _marker_t > 0.0
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.25
		PerfOverlay.status_line = (
			"%d units (%d drawn, %d sel) %.1fx %s\nsim %.2f ms  buffer %.2f ms  flow %.1f ms\n%s"
			% [
				units.count,
				units.visible_count,
				units.selected_count,
				speed,
				SpikeConfig.QUALITY[quality]["name"],
				sim_ms,
				buffer_ms,
				last_flow_ms,
				RenderingServer.get_video_adapter_api_version(),
			]
		)


# --- input (GDD section 8 subset) ---


func _unhandled_input(event: InputEvent) -> void:
	if bench.running:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		# desktop testing only: wheel zooms
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom_by(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom_by(1.1)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _touches.is_empty() and PerfOverlay.is_over_ui(e.position):
			return
		_touches[e.index] = e.position
		if _touches.size() == 1 and not _multi:
			_start = e.position
			_boxing = false
		elif _touches.size() >= 2:
			_multi = true
			_boxing = false
			_select_box.hide_rect()
			_pinch_start()
		return
	if not _touches.has(e.index):
		return
	if not _multi and _touches.size() == 1:
		if _boxing:
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


## Tap: own unit under the finger -> select it; else, with a selection, move there.
func tap(screen: Vector2) -> void:
	var best: int = -1
	var best_d: float = SpikeConfig.TAP_UNIT_PX
	for i in units.count:
		if units.team[i] != 0:
			continue
		var w := Vector3(units.pos[i].x, units.hgt[i] + 0.8, units.pos[i].y)
		if cam.is_position_behind(w):
			continue
		var d: float = cam.unproject_position(w).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		units.set_selection(PackedInt32Array([best]))
		return
	var hit: Vector3 = terrain.ray_hit(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if hit != Vector3.INF:
		move_selection(Vector2(hit.x, hit.z))


## Selects the player's units inside the screen rectangle a-b (replaces the selection).
func box_select(a: Vector2, b: Vector2) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	var ids := PackedInt32Array()
	for i in units.count:
		if units.team[i] != 0:
			continue
		var w := Vector3(units.pos[i].x, units.hgt[i] + 0.7, units.pos[i].y)
		if cam.is_position_behind(w):
			continue
		if r.has_point(cam.unproject_position(w)):
			ids.append(i)
	units.set_selection(ids)
