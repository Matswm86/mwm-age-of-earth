class_name Bench
extends Node

## Bench mode: runs every entry of SpikeConfig.BENCH_RUNS (150, 165 and 210 units at 1x, then
## 210 at 1.5x) for BENCH_SECONDS each after BENCH_WARMUP, with the camera fixed at default
## height over the bench area and every team re-ordered every BENCH_ORDER_EVERY game seconds
## to the next point of a ring, so the groups walk through each other (flow fields + separation
## busy all the time). Enemy units are all drawn (reveal_all) so the 210 case really draws 210;
## the fog is still computed. Results go to the screen, the log and user://bench.txt.
## "1% low" = 1000 / mean of the slowest 1% of frame times.

signal finished(text: String)

var main: Main
var running: bool = false


func run_all(seconds: float = SpikeConfig.BENCH_SECONDS) -> String:
	running = true
	var keep_preset: int = main.preset
	var keep_speed: float = main.speed
	var lines: PackedStringArray = PackedStringArray()
	lines.append(header())
	var runs: Array[Vector2] = SpikeConfig.BENCH_RUNS
	for r in runs.size():
		var run: Vector2 = runs[r]
		PerfOverlay.set_button_text("bench", "Bench %d/%d" % [r + 1, runs.size()])
		main.apply_preset(int(run.x))
		main.set_speed(run.y)
		main.units.reveal_all = true
		main.cam.focus = SpikeConfig.BENCH_CENTRE
		main.cam.height = SpikeConfig.CAM_DEFAULT_H
		main.cam.apply()
		var stats: Dictionary = await _measure(seconds)
		var name: String = "%s x%.1f" % [SpikeConfig.PRESETS[int(run.x)]["name"], run.y]
		var line: String = format(name, stats)
		print("BENCH ", line)
		lines.append(line)
	main.units.reveal_all = false
	main.apply_preset(keep_preset)
	main.set_speed(keep_speed)
	PerfOverlay.set_button_text("bench", "Bench all")
	var text: String = "\n".join(lines)
	_save(text)
	running = false
	finished.emit(text)
	return text


func header() -> String:
	return "%s | %s %s | %s | %s quality | %d tris/unit" % [
		Time.get_datetime_string_from_system(),
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(),
		OS.get_model_name(),
		SpikeConfig.QUALITY[main.quality]["name"],
		main.units.mesh_tris,
	]


func _measure(seconds: float) -> Dictionary:
	var frames := PackedFloat32Array()
	var gpu_sum: float = 0.0
	var rcpu_sum: float = 0.0
	var sim_sum: float = 0.0
	var fog_sum: float = 0.0
	var draw_sum: float = 0.0
	main.flow_max_ms = 0.0
	var draws_max: float = 0.0
	var prims_max: float = 0.0
	var vis_min: int = 1 << 20
	var order_clock: float = SpikeConfig.BENCH_ORDER_EVERY
	var step: int = 0
	var t: float = -SpikeConfig.BENCH_WARMUP
	while t < seconds:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		order_clock += dt * main.speed
		if order_clock >= SpikeConfig.BENCH_ORDER_EVERY:
			order_clock = 0.0
			_orders(step)
			step += 1
		if t <= 0.0:
			continue
		frames.append(dt * 1000.0)
		gpu_sum += PerfOverlay.gpu_ms()
		rcpu_sum += PerfOverlay.cpu_ms()
		sim_sum += main.sim_ms
		fog_sum += main.fog_ms
		draw_sum += main.buffer_ms
		draws_max = maxf(draws_max, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims_max = maxf(prims_max, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		vis_min = mini(vis_min, main.units.visible_count)
	var n: int = maxi(frames.size(), 1)
	var total: float = 0.0
	for f in frames:
		total += f
	frames.sort()
	var worst: int = maxi(1, int(n / 100.0))
	var worst_sum: float = 0.0
	for k in worst:
		worst_sum += frames[frames.size() - 1 - k] if frames.size() > k else 0.0
	return {
		"frames": frames.size(),
		"avg_fps": 1000.0 * n / maxf(total, 0.001),
		"low1_fps": 1000.0 / maxf(worst_sum / worst, 0.001),
		"avg_ms": total / n,
		"p99_ms": frames[int(floor((n - 1) * 0.99))] if frames.size() > 0 else 0.0,
		"max_ms": frames[frames.size() - 1] if frames.size() > 0 else 0.0,
		"gpu_ms": gpu_sum / n,
		"rcpu_ms": rcpu_sum / n,
		"sim_ms": sim_sum / n,
		"fog_ms": fog_sum / n,
		"buf_ms": draw_sum / n,
		"flow_ms": main.flow_max_ms,
		"draws": draws_max,
		"prims": prims_max,
		"units": main.units.count,
		"vis_min": vis_min,
	}


## New move order for every team: the next point of a 4-point ring round the bench centre.
## The fields build on worker threads; Main.flow_max_ms records the slowest build.
func _orders(step: int) -> void:
	var teams: int = int(SpikeConfig.PRESETS[main.preset]["teams"])
	for t in teams:
		var a: float = TAU * float((step + t) % 4) / 4.0 + 0.4
		var goal: Vector2 = SpikeConfig.BENCH_CENTRE + Vector2(cos(a), sin(a)) * 14.0
		main.order_team(t, goal)


static func format(name: String, s: Dictionary) -> String:
	return (
		(
			"%-8s %3d units: %5.1f fps avg, 1%% low %5.1f fps | frame %4.1f ms avg, p99 %4.1f, max %4.1f"
			+ "\n         GPU %4.1f ms, render CPU %4.1f ms | sim %4.2f, fog %4.2f, buffer %4.2f ms/frame"
			+ "\n         flow field build max %4.1f ms (worker thread) | draws %d, %dk prims"
		)
		% [
			name,
			s["units"],
			s["avg_fps"],
			s["low1_fps"],
			s["avg_ms"],
			s["p99_ms"],
			s["max_ms"],
			s["gpu_ms"],
			s["rcpu_ms"],
			s["sim_ms"],
			s["fog_ms"],
			s["buf_ms"],
			s["flow_ms"],
			int(s["draws"]),
			int(s["prims"] / 1000.0),
		]
	)


func _save(text: String) -> void:
	var f := FileAccess.open("user://bench.txt", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://bench.txt", FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_string(text + "\n\n")
	f.close()
