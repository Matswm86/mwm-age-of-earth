extends Node

## Dev-only GPU bench (excluded from the APK): the 210-unit bench crowd at the default camera,
## rendered into a 2340 x 1080 SubViewport (the phone's screen) shown in a small window, so the
## laptop GPU stays at full clock (a full-size Xvfb window down-clocks it and inflates GPU ms).
## Orders every 5 game seconds as Bench.gd. Prints mean / p90 GPU ms, draws and primitives of
## the game viewport. SVB_LOW=1 measures the Low preset. Laptop ms are only relative.

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
	tr.size = Vector2(468, 216)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(tr)
	main = load("res://scenes/Main.tscn").instantiate()
	sv.add_child(main)
	await _frames(30)
	var q: int = 1 if OS.get_environment("SVB_LOW") != "" else 0
	main.apply_quality(q)
	main.apply_preset(2)
	main.units.reveal_all = true
	main.cam.focus = SpikeConfig.BENCH_CENTRE
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	# SVB_OFF=tilt,msaa,shadow,grass,glow: A/B a part off
	for f: String in OS.get_environment("SVB_OFF").split(",", false):
		match f:
			"tilt":
				main.cam.tilt_shift = false
			"msaa":
				sv.msaa_3d = Viewport.MSAA_DISABLED
			"shadow":
				main.sun.shadow_enabled = false
			"grass":
				main.grass.visible = false
			"glow":
				main.env.glow_enabled = false
	var scale: float = OS.get_environment("SVB_SCALE").to_float()
	if scale > 0.0:
		sv.scaling_3d_scale = scale
	main.cam.apply()
	var gpu := PackedFloat32Array()
	var draws: float = 0.0
	var prims: float = 0.0
	var clock: float = 99.0
	var step: int = 0
	var t: float = -3.0
	while t < 10.0:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		clock += dt
		if clock >= 5.0:
			clock = 0.0
			for k in 3:
				var a: float = TAU * float((step + k) % 4) / 4.0 + 0.4
				main.order_team(k, SpikeConfig.BENCH_CENTRE + Vector2(cos(a), sin(a)) * 14.0)
			step += 1
		if t <= 0.0:
			continue
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
		draws = maxf(draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxf(prims, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var sum: float = 0.0
	for g in gpu:
		sum += g
	gpu.sort()
	print(
		"SVBENCH %s %s quality %d off=%s scale=%s: GPU mean %.2f ms, p90 %.2f ms over %d frames | %d draws, %dk prims"
		% [
			RenderingServer.get_current_rendering_method(),
			RenderingServer.get_video_adapter_name(),
			q,
			OS.get_environment("SVB_OFF"),
			OS.get_environment("SVB_SCALE"),
			sum / gpu.size(),
			gpu[int(gpu.size() * 0.9)],
			gpu.size(),
			int(draws),
			int(prims / 1000.0),
		]
	)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
