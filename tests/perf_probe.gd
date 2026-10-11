extends Node

## Dev-only render cost breakdown at the default camera (excluded from the APK). Interleaved A/B:
## for every part, the mean GPU ms over 60 frames with everything on, then with that part off,
## so laptop thermal drift does not pile up on one side. Prints "part: base -> off (saves x ms)".
## No vsync and no fps cap, so the GPU stays at full clock. Run like look_capture.tscn.

var main: Main
var _rid: RID


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# the game renders into a 1920 x 1080 SubViewport shown in a small window: presenting through
	# Xvfb (a software X server) is then cheap, the frame rate stays high and the GPU stays at full
	# clock, so the measured GPU ms means something (in a full-size window the GPU idled at
	# ~900 MHz and every number was inflated, 2026-10-11)
	var sv := SubViewport.new()
	sv.size = Vector2i(1920, 1080)
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
	await _frames(120)
	await _frames(60)
	print(
		"pacing: %d fps, process %.2f ms, physics %.2f ms, render CPU %.2f ms"
		% [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			PerfOverlay.cpu_ms(),
		]
	)
	var env: Environment = main.env
	# High vs Low first, while the laptop GPU is cool (the baseline drifts up ~50 % as it heats)
	print("High preset (cool GPU): %.2f ms" % await _gpu())
	main.apply_quality(1)
	print("Low preset (cool GPU): %.2f ms" % await _gpu())
	main.apply_quality(0)
	if OS.get_environment("PERF_PRESETS_ONLY") != "":
		get_tree().quit()
		return
	var parts: Array = [
		["grass", func(on: bool) -> void: main.grass.visible = on],
		["trees", func(on: bool) -> void: _trees(on, false)],
		["tree shadows", func(on: bool) -> void: _trees(on, true)],
		["sun shadow", func(on: bool) -> void: main.sun.shadow_enabled = on],
		["ssao", func(on: bool) -> void: env.ssao_enabled = on],
		["ssil", func(on: bool) -> void: env.ssil_enabled = on],
		["ssr", func(on: bool) -> void: env.ssr_enabled = on],
		["volumetric fog", func(on: bool) -> void: env.volumetric_fog_enabled = on],
		["glow", func(on: bool) -> void: env.glow_enabled = on],
		["tilt-shift", func(on: bool) -> void: _tilt(on)],
		["msaa 4x -> 2x", func(on: bool) -> void: _msaa(on)],
		["camp + kit props", func(on: bool) -> void: main.game.visible = on],
	]
	var total: float = 0.0
	for p: Array in parts:
		var f: Callable = p[1]
		var prims0: float = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		# 4 alternations of on/off windows; the share of the frame is robust to thermal drift
		var on_ms: float = 0.0
		var off_ms: float = 0.0
		var prims1: float = prims0
		for r in 4:
			on_ms += await _gpu()
			f.call(false)
			off_ms += await _gpu()
			prims1 = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			f.call(true)
		on_ms /= 4.0
		off_ms /= 4.0
		total += on_ms
		print(
			"%s: %.2f -> %.2f ms (%.0f %% of the frame, %dk prims)"
			% [p[0], on_ms, off_ms, 100.0 * (on_ms - off_ms) / on_ms, int((prims0 - prims1) / 1000.0)]
		)
	print("all on (mean of baselines): %.2f ms" % (total / parts.size()))
	print(
		"draws %d, prims %dk"
		% [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		]
	)
	# floor: every 3D node hidden (only sky, post effects and the HUD left)
	for c in main.get_children():
		if c is Node3D and not (c is Camera3D) and not (c is DirectionalLight3D):
			(c as Node3D).visible = false
	print("everything hidden (sky + post only): %.2f ms" % await _gpu())
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	main.cam.tilt_shift = false
	main.cam.apply()
	print("everything hidden, post off: %.2f ms" % await _gpu())
	get_tree().quit()
	get_tree().quit()


func _named(root: Node, prefixes: Array, on: bool) -> void:
	for c in root.get_children():
		for pre: String in prefixes:
			if (c.name as String).begins_with(pre) and c is Node3D:
				(c as Node3D).visible = on


func _is_tree(c: Node) -> bool:
	var n: String = c.name
	for pre: String in ["cobbles", "stones", "boulder", "shrub", "doum"]:
		if n.begins_with(pre):
			return false
	return c is MultiMeshInstance3D


func _trees(on: bool, shadow_only: bool) -> void:
	for c in main.dressing.get_children():
		if not _is_tree(c):
			continue
		var g := c as GeometryInstance3D
		if shadow_only:
			g.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if on
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
		else:
			g.visible = on


func _tilt(on: bool) -> void:
	main.cam.tilt_shift = on
	main.cam.apply()


func _msaa(on: bool) -> void:
	main.get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_2X


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Mean GPU ms of the game SubViewport over 40 frames (Godot's viewport GPU timer).
func _gpu() -> float:
	await _frames(15)
	var t: float = 0.0
	for i in 40:
		await get_tree().process_frame
		t += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	return t / 40.0
