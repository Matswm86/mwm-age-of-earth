extends Node

## Dev-only screenshot bot (excluded from the APK). Run under Xvfb with CAPTURE_DIR set and the
## NVIDIA ICD (game-studio CLAUDE.md). Shots, 1920 x 1080 PNG:
## g01_match_start      default camera at the Home Tree, 6 Foragers, first hint
## g00_closeup          5 m camera on one Forager (body, paint, disc)
## g02_gathering        Foragers on figs, wood, tubers and stone after a few trips (+N floaters)
## g03_placement        Nest Grove ghost with the tick and cross
## g04_construction     the Nest Grove going up, builders kneeling
## g05_home_selected    Home Tree selected, Forager training on the command card
## g06_knapping         Knapping Floor selected, Stone That Cuts researching
## g07_carcass_hyena    the carcass with the hyena pack nearby
## g08_lake_shore       the lake shore: foam, jade water, crocodile, palms
## g09_far_zoom         maximum zoom-out, fog on
## g10_crowd_150        150-unit crowd (Bench preset), fog off, UI hidden
## Prints the on-screen height of a Forager in pixels at the default camera.
## CAPTURE_ONLY=g08 limits to shots whose name starts with that prefix (faster iteration).

var out_dir: String = OS.get_environment("CAPTURE_DIR")
var only: String = OS.get_environment("CAPTURE_ONLY")
var main: Main


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	_unit_px()
	await _shot("g01_match_start")
	var u0: int = main.units.ids_of_team(0)[0]
	main.cam.focus = main.units.pos[u0] + Vector2(0.0, -1.0)
	main.cam.height = 5.0
	await _seconds(0.6)
	await _shot("g00_closeup")
	main.cam.focus = GameConfig.CAM_START
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	# gather: 2 on figs, 2 on wood, 1 tuber, 1 stone
	var ids: PackedInt32Array = main.units.ids_of_team(0)
	var plan: Array[int] = [0, 1, 10, 11, 6, 14]
	for k in ids.size():
		main.game.order_gather(PackedInt32Array([ids[k]]), plan[k % plan.size()])
	main.units.set_selection(PackedInt32Array([ids[0], ids[1], ids[2]]))
	main._after_selection()
	await _ff(150.0)
	main.cam.focus = GameConfig.HOME + Vector2(-14.0, 2.0)
	main.cam.height = 26.0
	await _seconds(0.5)
	await _shot("g02_gathering")
	# placement: Nest Grove ghost south of the tree
	main.units.set_selection(PackedInt32Array([ids[0], ids[1]]))
	main._after_selection()
	main.cam.focus = GameConfig.HOME + Vector2(-4.0, 16.0)
	await _seconds(0.3)
	main._on_card("build:nest_grove")
	var spot := Vector2(GameConfig.HOME.x - 6.0, GameConfig.HOME.y + 22.0)
	var sp: Vector2 = main.cam.unproject_position(Vector3(spot.x, main.terrain.height_at(spot.x, spot.y), spot.y))
	main._move_ghost(sp)
	main.hud.show_place_confirm(main.ghost.position, main.ghost_ok)
	await _seconds(0.4)
	print("ghost ok=%s at %s" % [main.ghost_ok, str(main.ghost_at)])
	await _shot("g03_placement")
	main._on_place_answer(true)
	await _ff(8.0)
	await _seconds(0.5)
	await _shot("g04_construction")
	# finish it, then train at the Home Tree
	await _ff(25.0)
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main._on_home()
	main._on_card("train:forager")
	main._on_card("train:forager")
	await _seconds(3.0)
	await _shot("g05_home_selected")
	# Knapping Floor: place, finish instantly (capture shortcut), research
	main.game.res["wood"] = 400.0
	main.game.res["stone"] = 300.0
	main.game.res["food"] = 400.0
	var kf: int = main.game.place_building("knapping_floor", GameConfig.HOME + Vector2(14.0, 10.0), PackedInt32Array([ids[3]]))
	if kf >= 0:
		main.game.buildings[kf].progress = 0.9
	await _ff(25.0)
	if kf >= 0:
		main._clear_selection()
		main.sel_building = kf
		main._on_card("tech:stone_that_cuts")
		main._after_selection()
		main.cam.focus = main.game.buildings[kf].pos + Vector2(0.0, 5.0)
	await _seconds(4.0)
	await _shot("g06_knapping")
	main._clear_selection()
	main.set_fog(false)
	main.cam.focus = GameConfig.CARCASSES[0] + Vector2(2.0, 6.0)
	await _seconds(1.5)
	await _shot("g07_carcass_hyena")
	main.cam.focus = GameConfig.CROCODILES[0] + Vector2(-6.0, 12.0)
	main.cam.height = 26.0
	await _seconds(1.5)
	await _shot("g08_lake_shore")
	main.set_fog(true)
	main.cam.focus = GameConfig.HOME
	main.cam.height = SpikeConfig.CAM_MAX_H
	await _seconds(1.5)
	await _shot("g09_far_zoom")
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main.apply_preset(0)
	main.set_fog(false)
	main.cam.focus = Vector2(395.0, 292.0)
	main.cam.height = 30.0
	for t in 2:
		main.order_team(t, Vector2(395.0, 292.0) + Vector2(8.0 if t == 0 else -8.0, 0.0))
	await _seconds(5.0)
	main.hud.visible = false
	await _shot("g10_crowd_150")
	main.hud.visible = true
	var secs: float = OS.get_environment("CAPTURE_BENCH_SECONDS").to_float()
	if secs > 0.0:
		var text: String = await main.bench.run_all(secs)
		print(text)
	print("CAPTURE DONE")
	get_tree().quit()


## On-screen height (px) of the first Forager at the current camera (feet to head).
func _unit_px() -> void:
	var i: int = main.units.ids_of_team(0)[0]
	var p: Vector2 = main.units.pos[i]
	var y: float = main.units.hgt[i]
	var a: Vector2 = main.cam.unproject_position(Vector3(p.x, y, p.y))
	var b: Vector2 = main.cam.unproject_position(Vector3(p.x, y + 1.3, p.y))
	print("forager on-screen height %.0f px at camera height %.1f m" % [a.distance_to(b), main.cam.height])


## Runs `game_s` seconds of simulation as fast as the CPU allows (the frame-rate cap on ticks
## would make Engine.time_scale crawl under Xvfb), then lets a few frames render.
func _ff(game_s: float) -> void:
	var dt: float = 1.0 / SpikeConfig.SIM_HZ
	var n: int = int(game_s / dt)
	for k in n:
		main._poll_flow_tasks()
		main.units.tick(dt)
		main.game.game_tick(dt)
		main.animals.tick(dt)
		main.units.anim_time += dt
		if k % 60 == 0:
			main._update_fog()
			await get_tree().process_frame
	await _frames(4)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	var t: float = 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(shot_name: String) -> void:
	if only != "" and not shot_name.begins_with(only):
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + shot_name + ".png")
	print(
		"shot %s: %d units drawn, %d draws, %dk prims, GPU %.1f ms"
		% [
			shot_name,
			main.units.visible_count,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			PerfOverlay.gpu_ms(),
		]
	)
