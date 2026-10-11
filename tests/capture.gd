extends Node

## Dev-only screenshot bot (excluded from the APK). Run under Xvfb with CAPTURE_DIR set, see
## game-studio CLAUDE.md. Shots (1920 x 1080 PNG):
## 01 210 units at start (player in sight, rivals under fog), readout visible
## 02 player army selected (rings) and walking to a tapped point
## 03 drag box being drawn
## 04 all 210 drawn (fog off), teams crossing, UI hidden (README shot); 04b readout; 04c Low
## 05 lake shore at far zoom, fog off
## 06 far zoom, fog on: visible, explored (dim) and unexplored (black)
## CAPTURE_BENCH_SECONDS > 0 then runs the bench (laptop numbers say nothing about phones).

var out_dir: String = OS.get_environment("CAPTURE_DIR")
var main: Main


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	await _shot("01_210_start")
	main.select_all()
	var target: Vector2 = SpikeConfig.SPAWN_POINTS[0] + Vector2(-6.0, -22.0)
	var tap_at: Vector2 = main.cam.unproject_position(
		Vector3(target.x, main.terrain.height_at(target.x, target.y), target.y)
	)
	main.tap(tap_at)
	print("selected %d, order to %s" % [main.units.selected_count, str(target)])
	await _seconds(1.6)
	await _shot("02_210_moving_selected")
	var box: Rect2 = _army_screen_rect().grow(40.0)
	main._select_box.show_rect(box.position, box.end)
	await _frames(3)
	await _shot("03_drag_box")
	main._select_box.hide_rect()
	main.box_select(box.position, box.end)
	print("box selected %d of %d player units" % [main.units.selected_count, 70])
	main.units.set_selection(PackedInt32Array())
	main.set_fog(false)
	main.cam.focus = SpikeConfig.BENCH_CENTRE
	main.cam.apply()
	for t in 3:
		var a: float = TAU * float(t) / 3.0 + 0.4
		main.order_team(t, SpikeConfig.BENCH_CENTRE + Vector2(cos(a), sin(a)) * 12.0)
	await _seconds(7.0)
	PerfOverlay.set_ui_visible(false)
	await _shot("04_210_all_drawn_clean")
	PerfOverlay.set_ui_visible(true)
	await _frames(3)
	await _shot("04b_210_all_drawn_readout")
	main.apply_quality(1)
	await _seconds(0.6)
	await _shot("04c_210_low_quality")
	main.apply_quality(0)
	main.cam.focus = Vector2(215.0, 250.0)
	main.cam.height = SpikeConfig.CAM_MAX_H
	main.cam.apply()
	await _seconds(1.5)
	await _shot("05_lake_far_zoom_fog_off")
	main.set_fog(true)
	main.cam.focus = SpikeConfig.BENCH_CENTRE
	main.cam.apply()
	await _seconds(1.5)
	await _shot("06_far_zoom_fog_on")
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main.cam.apply()
	var secs: float = OS.get_environment("CAPTURE_BENCH_SECONDS").to_float()
	if secs > 0.0:
		var text: String = await main.bench.run_all(secs)
		print(text)
	print("CAPTURE DONE")
	get_tree().quit()


## Screen rectangle round the player's units.
func _army_screen_rect() -> Rect2:
	var r := Rect2()
	var first: bool = true
	for i in main.units.count:
		if main.units.team[i] != 0:
			continue
		var w := Vector3(main.units.pos[i].x, main.units.hgt[i] + 0.7, main.units.pos[i].y)
		var sp: Vector2 = main.cam.unproject_position(w)
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	return r


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	var t: float = 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print(
		"shot %s: %d units drawn, %d draws, %dk prims"
		% [
			name,
			main.units.visible_count,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		]
	)
