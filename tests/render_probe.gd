extends Node

## Dev-only GPU breakdown of the bench scene (excluded from the APK): the 210-unit crowd at the
## default camera over the camp, as the phone bench. For each part: GPU ms with everything on,
## then with that part off (4 interleaved windows each, so thermal drift and other GPU jobs hit
## both sides), plus the primitives and draw calls it adds. Laptop ms are only relative.
## Run under Xvfb like look_capture.tscn. RPROBE_LOW=1 starts from the Low preset.

var main: Main
var _rid: RID


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var sv := SubViewport.new()
	sv.size = Vector2i(2340, 1080)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	_rid = sv.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	var tr := TextureRect.new()
	tr.texture = sv.get_texture()
	tr.size = Vector2(480, 270)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(tr)
	main = load("res://scenes/Main.tscn").instantiate()
	sv.add_child(main)
	await _frames(30)
	if OS.get_environment("RPROBE_LOW") != "":
		main.apply_quality(1)
	main.apply_preset(2)
	main.units.reveal_all = true
	main.cam.focus = SpikeConfig.BENCH_CENTRE
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main.cam.apply()
	for t in 3:
		main.order_team(t, SpikeConfig.BENCH_CENTRE + Vector2(cos(t * 2.1), sin(t * 2.1)) * 14.0)
	await _frames(90)
	print("RPROBE %s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	print("RPROBE all on: %.2f ms GPU, %d draws, %dk prims, %d units drawn" % [await _gpu(), _draws(), _prims() / 1000, main.units.visible_count])
	var env: Environment = main.env
	var parts: Array = [
		["grass", func(on: bool) -> void: main.grass.visible = on],
		["reeds", func(on: bool) -> void: main.reeds.visible = on],
		["units", func(on: bool) -> void: main.units.visible = on],
		["trees+shrubs+rocks", func(on: bool) -> void: main.dressing.visible = on],
		["camp + kit props", func(on: bool) -> void: main.game.visible = on],
		["terrain+lake", func(on: bool) -> void: main.terrain.visible = on],
		["sun shadow", func(on: bool) -> void: main.sun.shadow_enabled = on],
		["glow", func(on: bool) -> void: env.glow_enabled = on],
		["tilt-shift", func(on: bool) -> void: _tilt(on)],
		["msaa", func(on: bool) -> void: _msaa(on)],
		["foot dust", func(on: bool) -> void: main.foot_dust.visible = on],
		["lake (water)", func(on: bool) -> void: main.terrain.get_node("Lake").visible = on],
		["unit shadows", func(on: bool) -> void: main.units.get_node("UnitsShadow").visible = on],
		["hud", func(on: bool) -> void: main.hud.visible = on],
	]
	for p: Array in parts:
		var f: Callable = p[1]
		var on_ms: float = 0.0
		var off_ms: float = 0.0
		var d0: int = _draws()
		var p0: int = _prims()
		var d1: int = d0
		var p1: int = p0
		for r in 4:
			on_ms += await _gpu()
			f.call(false)
			off_ms += await _gpu()
			d1 = _draws()
			p1 = _prims()
			f.call(true)
		on_ms /= 4.0
		off_ms /= 4.0
		print(
			"RPROBE %-20s %6.2f -> %6.2f ms (%3.0f %%)  %4d draws  %5dk prims"
			% [p[0], on_ms, off_ms, 100.0 * (on_ms - off_ms) / on_ms, d0 - d1, (p0 - p1) / 1000]
		)
	get_tree().quit()


var _msaa_keep: int = -1


func _msaa(on: bool) -> void:
	var vp: Viewport = main.get_viewport()
	if _msaa_keep < 0:
		_msaa_keep = vp.msaa_3d
	vp.msaa_3d = _msaa_keep if on else Viewport.MSAA_DISABLED


func _tilt(on: bool) -> void:
	main.cam.tilt_shift = on
	main.cam.apply()


func _draws() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _prims() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _gpu() -> float:
	await _frames(10)
	var t: float = 0.0
	for i in 30:
		await get_tree().process_frame
		t += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	return t / 30.0
