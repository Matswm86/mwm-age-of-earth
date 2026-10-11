extends Node

## Dev-only CPU profile (excluded from the APK): the per-call cost of every per-tick and
## per-frame CPU job with the 210-unit bench crowd walking (orders every 2.5 s, as the bench).
## Runs headless: godot --headless --audio-driver Dummy res://tests/sim_profile.tscn
## Prints mean and max microseconds per call. The phone runs SIM_HZ ticks per game second, so
## sim ms per frame = tick cost x 30 / fps.

const FRAMES: int = 600

var main: Main


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.apply_preset(2)
	main.units.reveal_all = true
	var names: Array[String] = [
		"units.tick", "animals.tick", "units.render+marks", "animals.render", "fog.update",
		"foot_dust.tick", "world.per_frame"
	]
	var sum := PackedFloat64Array()
	var mx := PackedFloat64Array()
	sum.resize(names.size())
	mx.resize(names.size())
	var dt: float = 1.0 / SpikeConfig.SIM_HZ
	var step: int = 0
	for f in FRAMES:
		if f % 75 == 0:
			main.bench._orders(step)
			step += 1
		await get_tree().process_frame
		main._poll_flow_tasks()
		var us := PackedFloat64Array()
		us.resize(names.size())
		var t: int = Time.get_ticks_usec()
		main.units.tick(dt)
		us[0] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		main.animals.tick(dt)
		us[1] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		main.marks.begin()
		main.units.render(0.5)
		main.marks.finish()
		us[2] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		main.marks.begin()
		main.animals.render()
		main.marks.finish()
		us[3] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		main._update_fog()
		us[4] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		main.foot_dust._timer = 0.0
		main.foot_dust.tick(0.016, main.units, true)
		us[5] = Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		WorldLook.per_frame(main.sun, main.cam, main.units)
		us[6] = Time.get_ticks_usec() - t
		main.units.anim_time += dt
		if f >= 60:
			for k in names.size():
				sum[k] += us[k]
				mx[k] = maxf(mx[k], us[k])
	var moving: int = 0
	for i in main.units.count:
		moving += main.units.moving[i]
	print("PROFILE %d units (%d still moving at the end), %d frames" % [main.units.count, moving, FRAMES - 60])
	for k in names.size():
		print("PROFILE %-20s mean %7.1f us  max %7.1f us" % [names[k], sum[k] / (FRAMES - 60), mx[k]])
	get_tree().quit()
