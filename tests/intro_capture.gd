extends Node

## Dev-only screenshot bot for the opening intro (excluded from the APK with tests/*). Run under
## Xvfb at 1920 x 1080 with CAPTURE_DIR set (game-studio CLAUDE.md recipe), scene
## res://tests/intro_capture.tscn. Seeks the intro to fixed times and saves
## intro_<nn>_<t>s.png (every ~5 s, plus the wake and four climb frames), then shows the
## cross-fade into Main (intro_99_*). Optional
## INTRO_TIMES="1,12,30" overrides the list.

const TIMES: Array[float] = [
	1.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 63.0, 65.0,
	70.0, 75.0, 77.0, 80.0, 81.5, 83.0, 84.5, 87.0, 90.0, 93.0
]

var out_dir: String = OS.get_environment("CAPTURE_DIR")


func _ready() -> void:
	var times: Array[float] = TIMES.duplicate()
	var env_times: String = OS.get_environment("INTRO_TIMES")
	if env_times != "":
		times.clear()
		for s: String in env_times.split(","):
			times.append(s.to_float())
	var intro: Intro = load("res://scenes/Intro.tscn").instantiate()
	intro.capture_mode = true
	add_child(intro)
	# INTRO_HIDE="Atmosphere,Clouds" hides planet-stage nodes (GPU cost probe)
	for n: String in OS.get_environment("INTRO_HIDE").split(",", false):
		intro.planet_root.get_node(n).visible = false
	await _frames(10)
	var i: int = 0
	for ts: float in times:
		intro.seek(ts)
		# the first frames after a seek settle sky radiance and texture streaming
		await _frames(6)
		var ms: float = 0.0
		for f in 20:
			await get_tree().process_frame
			ms += PerfOverlay.gpu_ms() / 20.0
		await _shot("intro_%02d_%04.1fs" % [i, ts], ms)
		i += 1
	# hand-over: frozen last frame over the game scene, mid-fade
	intro.seek(IntroConfig.FADE_START_T)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	intro.queue_free()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	PerfOverlay.set_ui_visible(false)
	Intro.cross_fade(self, ImageTexture.create_from_image(img), 1.0)
	await _seconds(0.65)
	await _shot("intro_99_crossfade_mid", 0.0)
	await _seconds(1.0)
	await _shot("intro_99_game_after", 0.0)
	print("CAPTURE DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	var t: float = 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String, frame_ms: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + shot_name + ".png")
	print(
		(
			"shot %s: GPU %.2f ms (RTX 3060 laptop), %d draws, %dk prims"
			% [
				shot_name,
				frame_ms,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			]
		)
	)
