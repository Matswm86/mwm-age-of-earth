extends Node

## Dev-only look bot (excluded from the APK): the four frames used to judge the world look.
## Run under Xvfb at 1920x1080 with CAPTURE_DIR set and the NVIDIA ICD (game-studio CLAUDE.md).
## l1_camp    default camera at match start, HUD on
## l2_hero    the camp, the Home Tree, the gallery forest and the lake in one frame, HUD hidden
## l3_shore   the lake shore, HUD hidden
## l4_far     maximum zoom-out over the camp, HUD hidden
## l5_low     l1 with the Low quality preset
## Each shot prints draw calls, primitives and the GPU frame time (laptop RTX 3060).

var out_dir: String = OS.get_environment("CAPTURE_DIR")
var only: String = OS.get_environment("CAPTURE_ONLY")
var main: Main


func _ready() -> void:
	# GPU timing: no vsync, no fps cap, so the laptop GPU stays at full clock (with vsync it
	# down-clocks and every measured ms inflates)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	# LOOK_OFF=ssil_enabled,ssao_enabled switches Environment flags off (A/B checks)
	for f: String in OS.get_environment("LOOK_OFF").split(",", false):
		main.env.set(f, false)
	# LOOK_HIDE=sun_shadow,<node name prefix>... hides parts (A/B checks)
	for h: String in OS.get_environment("LOOK_HIDE").split(",", false):
		if h == "sun_shadow":
			main.sun.shadow_enabled = false
		for n: Node in main.find_children(h + "*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).visible = false
	# LOOK_AA=msaa2|taa|fxaa: antialiasing A/B on top of the High preset
	match OS.get_environment("LOOK_AA"):
		"msaa2":
			get_viewport().msaa_3d = Viewport.MSAA_2X
		"taa":
			get_viewport().use_taa = true
		"fxaa":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	# LOOK_FOV=30: narrower lens, camera height scaled so units keep their on-screen size
	var fov: float = OS.get_environment("LOOK_FOV").to_float()
	if fov > 0.0:
		var k: float = tan(deg_to_rad(SpikeConfig.CAM_FOV * 0.5)) / tan(deg_to_rad(fov * 0.5))
		main.cam.fov = fov
		main.cam.height *= k
	await _seconds(2.5)
	_unit_px()
	if OS.get_environment("LOOK_HERO") != "":
		await _hero_poses()
		get_tree().quit()
		return
	await _shot("l1_camp")
	main.hud.visible = false
	main.cam.focus = GameConfig.HOME + Vector2(16.0, 12.0)
	main.cam.height = 24.0
	await _seconds(1.5)
	await _shot("l2_hero")
	main.set_fog(false)
	main.cam.focus = GameConfig.CROCODILES[0] + Vector2(-10.0, 14.0)
	main.cam.height = 24.0
	await _seconds(1.5)
	await _shot("l3_shore")
	main.cam.focus = GameConfig.HOME
	main.cam.height = SpikeConfig.CAM_MAX_H
	await _seconds(1.5)
	await _shot("l4_far")
	main.set_fog(true)
	main.hud.visible = true
	main.cam.focus = GameConfig.CAM_START
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main.apply_quality(1)
	await _seconds(1.5)
	await _shot("l5_low")
	print("CAPTURE DONE")
	get_tree().quit()


## Cinematic poses for the README hero shot (same game, camera freed from the RTS rig).
## Each pose: [eye, target] in map metres (y above the ground under the eye / target).
func _hero_poses() -> void:
	main.hud.visible = false
	main.set_fog(false)
	main.cam.set_process(false)
	main.cam.attributes = null
	var poses: Array = [
		[Vector3(372.0, 13.0, 286.0), Vector3(418.0, 2.0, 252.0)],
		[Vector3(380.0, 10.0, 292.0), Vector3(412.0, 3.0, 258.0)],
		[Vector3(392.0, 16.0, 300.0), Vector3(430.0, 0.0, 250.0)],
		[Vector3(388.0, 14.0, 296.0), Vector3(416.0, 0.0, 256.0)],
		[Vector3(392.0, 3.0, 278.0), Vector3(406.0, 4.0, 262.0)],
		[Vector3(400.0, 16.0, 276.0), Vector3(406.0, 4.0, 262.0)],
		[Vector3(384.0, 11.0, 300.0), Vector3(420.0, 2.0, 248.0)],
		[Vector3(406.0, 20.0, 282.0), Vector3(406.0, 6.0, 263.0)],
	]
	for k in poses.size():
		var e: Vector3 = poses[k][0]
		var t: Vector3 = poses[k][1]
		e.y += main.terrain.height_at(e.x, e.z)
		t.y += main.terrain.height_at(t.x, t.z)
		main.cam.position = e
		main.cam.look_at(t, Vector3.UP)
		main.cam.fov = 40.0
		main.cam.far = 4000.0
		main.grass.position = Vector3(t.x, 0.0, t.z)
		await _seconds(1.0)
		await _shot("h%d" % (k + 1))


## On-screen height (px) of the first Forager (feet to head, drawn size).
func _unit_px() -> void:
	var i: int = main.units.ids_of_team(0)[0]
	var p: Vector2 = main.units.pos[i]
	var y: float = main.units.hgt[i]
	var h: float = 1.3 * SpikeConfig.UNIT_DRAW_SCALE
	var a: Vector2 = main.cam.unproject_position(Vector3(p.x, y, p.y))
	var b: Vector2 = main.cam.unproject_position(Vector3(p.x, y + h, p.y))
	var px: float = a.distance_to(b)
	print("forager on-screen height %.0f px (camera height %.1f m)" % [px, main.cam.height])


func _seconds(s: float) -> void:
	var t: float = 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String) -> void:
	if only != "" and not shot_name.begins_with(only):
		return
	# GPU time averaged over 40 frames (single frames are noisy when other jobs share the GPU)
	var gpu: float = 0.0
	for k in 40:
		await get_tree().process_frame
		gpu += PerfOverlay.gpu_ms()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + shot_name + ".png")
	print(
		"shot %s: %d draws, %dk prims, GPU %.2f ms (40-frame mean), CPU %.2f ms"
		% [
			shot_name,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			gpu / 40.0,
			PerfOverlay.cpu_ms(),
		]
	)
