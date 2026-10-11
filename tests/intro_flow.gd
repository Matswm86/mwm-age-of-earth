extends Node

## Dev-only flow test (excluded from the APK): first viewing plays to the end and hands over
## to Main by itself and saves the seen flag; a second viewing skips on a tap. Runs at 10x time
## scale. Removes user://intro.cfg before and after. Prints FLOW PASS or FLOW FAIL.


func _ready() -> void:
	# this node is the current scene and dies on the first scene change: run from the root
	var runner := Runner.new()
	get_tree().root.add_child.call_deferred(runner)


class Runner:
	extends Node

	func _ready() -> void:
		_run()

	func _run() -> void:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IntroConfig.SAVE_PATH))
		Engine.time_scale = 10.0
		get_tree().change_scene_to_file.call_deferred("res://scenes/Intro.tscn")
		var t0: int = Time.get_ticks_msec()
		# limits include building Main (~7 s headless with the 2026-10-11 art pass)
		var ok_first: bool = await _wait_for_main(60.0)
		var secs: float = float(Time.get_ticks_msec() - t0) / 1000.0
		var cfg := ConfigFile.new()
		var seen: bool = (
			cfg.load(IntroConfig.SAVE_PATH) == OK and bool(cfg.get_value("intro", "seen"))
		)
		print(
			(
				"first viewing: reached Main=%s after %.1f s real (10x), seen flag=%s"
				% [ok_first, secs, seen]
			)
		)
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file("res://scenes/Intro.tscn")
		await _frames(30)
		# taps count only after IntroConfig.SKIP_AFTER on the intro's own clock (its build is slow)
		for k in 600:
			var it: Node = get_tree().current_scene
			if it is Intro and (it as Intro).t > IntroConfig.SKIP_AFTER + 0.1:
				break
			await get_tree().process_frame
		var tap := InputEventScreenTouch.new()
		tap.pressed = true
		tap.position = Vector2(960.0, 540.0)
		Input.parse_input_event(tap)
		var ok_skip: bool = await _wait_for_main(15.0)
		print("second viewing: tap skipped to Main=%s" % ok_skip)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IntroConfig.SAVE_PATH))
		print("FLOW PASS" if ok_first and seen and ok_skip else "FLOW FAIL")
		get_tree().quit()

	func _wait_for_main(limit_s: float) -> bool:
		var t0: int = Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t0) / 1000.0 < limit_s:
			await get_tree().process_frame
			var cur: Node = get_tree().current_scene
			if cur != null and cur.name == "Main":
				return true
		return false

	func _frames(n: int) -> void:
		for k in n:
			await get_tree().process_frame
