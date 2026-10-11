extends Node

## Dev-only audio test (excluded from the APK). Headless:
##   godot --headless --audio-driver Dummy res://tests/audio_test.tscn
## 1. Every file named in SfxConfig (events, ambience layers, intro sounds) exists and loads as an
##    AudioStream with a length; loops are OGG, every intro cue used exists in IntroConfig.CUES.
## 2. Plays the real intro at 10x (cue signals -> Sfx) into Main and checks which intro sounds fired.
## 3. In Main: game signals, orders, selections, wildlife, alarm-free events, pool cap, volumes.
## Prints one line per check and AUDIO PASS or AUDIO FAIL. Removes user://intro.cfg and
## user://audio.cfg before and after.


func _ready() -> void:
	var runner := Runner.new()
	get_tree().root.add_child.call_deferred(runner)


class Runner:
	extends Node

	var fails: int = 0

	func _ready() -> void:
		_run()

	func check(ok: bool, what: String) -> void:
		print("%s  %s" % ["ok  " if ok else "FAIL", what])
		if not ok:
			fails += 1

	func _run() -> void:
		for p: String in [IntroConfig.SAVE_PATH, SfxConfig.SAVE_PATH]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		_static_checks()
		await _intro_and_main()
		for p: String in [IntroConfig.SAVE_PATH, SfxConfig.SAVE_PATH]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		print("AUDIO PASS" if fails == 0 else "AUDIO FAIL (%d)" % fails)
		get_tree().quit()

	func _loads(path: String) -> bool:
		if path == "":
			return false
		var s: AudioStream = load(path) as AudioStream
		return s != null and s.get_length() > 0.05

	func _static_checks() -> void:
		var n: int = 0
		var bad: Array[String] = []
		for ev: String in SfxConfig.EVENTS:
			for f: String in SfxConfig.EVENTS[ev][0]:
				n += 1
				if not _loads(SfxConfig.path_of(f)):
					bad.append(ev + ":" + f)
		check(bad.is_empty(), "%d event files load %s" % [n, bad])
		var bad_amb: Array[String] = []
		for layer: String in SfxConfig.AMB_LAYERS:
			var p: String = SfxConfig.path_of(SfxConfig.AMB_LAYERS[layer])
			if not _loads(p) or not p.ends_with(".ogg"):
				bad_amb.append(layer)
		check(bad_amb.is_empty(), "ambience loops load as OGG %s" % [bad_amb])
		var bad_in: Array[String] = []
		for ev: Array in SfxConfig.INTRO_EVENTS:
			if not IntroConfig.CUES.has(ev[0]):
				bad_in.append("cue " + str(ev[0]))
			if ev[2] in ["bed", "one"] and not _loads(SfxConfig.intro_path(ev[3])):
				bad_in.append(str(ev[3]))
		check(bad_in.is_empty(), "intro cue list resolves %s" % [bad_in])
		for bus: String in ["Master"] + SfxConfig.BUSES:
			check(AudioServer.get_bus_index(bus) >= 0, "bus " + bus)

	func _intro_and_main() -> void:
		Engine.time_scale = 10.0
		get_tree().change_scene_to_file.call_deferred("res://scenes/Intro.tscn")
		var reached: bool = await _wait_for_main(90.0)
		Engine.time_scale = 1.0
		check(reached, "intro played to the end and handed over to Main")
		var want: Array[String] = [
			"intro:space_hum", "intro:rise", "intro:dive_wind", "intro:cloud_whoosh",
			"intro:dawn_chorus", "intro:wake_call", "intro:bark_scrape", "intro:land_thud",
			"intro:footstep", "intro:band_call"
		]
		var missing: Array[String] = []
		for k: String in want:
			if not Sfx.played.has(k):
				missing.append(k)
		check(missing.is_empty(), "intro sounds fired from the cues %s" % [missing])
		if not reached:
			return
		var main: Main = get_tree().current_scene as Main
		await _seconds(1.5)
		check(Sfx.ambience_gain("wind_grass") > 0.2, "game ambience running (wind_grass %.2f)" % Sfx.ambience_gain("wind_grass"))
		await _main_events(main)

	func _main_events(main: Main) -> void:
		var g: Game = main.game
		var ids: PackedInt32Array = main.units.ids_of_team(0)
		Sfx.played.clear()
		# selections and orders (random chance, so many tries)
		for k in 12:
			main.units.set_selection(PackedInt32Array([ids[k % ids.size()]]))
			await _seconds(0.9)
			g.order_move(PackedInt32Array([ids[k % ids.size()]]), main.units.pos[ids[k % ids.size()]])
		check(Sfx.played.has("contact"), "selection -> contact call (%d)" % int(Sfx.played.get("contact", 0)))
		check(Sfx.played.has("ack"), "order -> acknowledge call (%d)" % int(Sfx.played.get("ack", 0)))
		g.dropped.emit(Vector3(400, 2, 262), "+10 wood")
		g.dropped.emit(Vector3(400, 2, 262), "+10 stone")
		g.dropped.emit(Vector3(400, 2, 262), "+10 food")
		check(Sfx.played.has("drop_wood") and Sfx.played.has("drop_stone") and Sfx.played.has("drop_food"), "resource drops")
		g.building_placed.emit(0)
		g.building_finished.emit(0)
		check(Sfx.played.has("build_place") and Sfx.played.has("chorus"), "building placed / finished")
		await _seconds(1.0)
		g.unit_trained.emit(ids[0])
		check(Sfx.played.has("contact"), "unit trained -> call")
		g.tech_finished.emit("stone_that_cuts")
		check(Sfx.played.has("research_done"), "discovery -> stone strike + shimmer")
		g.tech_finished.emit("fire_kept")
		check(Sfx.played.has("age_up"), "age-up -> sting")
		main.hud.card_pressed.emit("train:forager")
		main.hud.place_answer.emit(false)
		check(Sfx.played.has("ui_tap") and Sfx.played.has("ui_cancel"), "UI taps")
		for kind: String in SfxConfig.WILDLIFE_WEIGHTS:
			check(Sfx.play_wildlife(kind), "wildlife call: " + kind)
		# gather sounds: send everyone to the first fig bush and wait
		main.cam.focus = g.nodes[0].pos
		g.order_gather(ids, 0)
		await _seconds(12.0)
		check(Sfx.played.has("gather_food"), "gathering -> foraging rustle (%d)" % int(Sfx.played.get("gather_food", 0)))
		for k in 40:
			Sfx.play_at("knap", Vector3(400, 2, 262))
		check(Sfx.busy_voices() <= SfxConfig.POOL_SIZE, "pool cap: %d busy of %d" % [Sfx.busy_voices(), SfxConfig.POOL_SIZE])
		Sfx.set_volume("SFX", 0.5)
		var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
		check(absf(db - linear_to_db(0.25)) < 0.1, "SFX slider 0.5 -> %.1f dB" % db)
		Sfx.set_muted(true)
		check(AudioServer.is_bus_mute(0), "mute")
		Sfx.set_muted(false)
		var cf := ConfigFile.new()
		check(cf.load(SfxConfig.SAVE_PATH) == OK and float(cf.get_value("volume", "SFX", 0)) == 0.5, "settings saved")
		check(PerfOverlay.is_over_ui(Vector2(-10, -10)) == false, "menu panel hidden by default")

	func _wait_for_main(limit_s: float) -> bool:
		var t0: int = Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t0) / 1000.0 < limit_s:
			await get_tree().process_frame
			var cur: Node = get_tree().current_scene
			if cur != null and cur.name == "Main":
				return true
		return false

	func _seconds(s: float) -> void:
		await get_tree().create_timer(s).timeout
