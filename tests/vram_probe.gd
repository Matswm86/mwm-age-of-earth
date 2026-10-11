extends Node

## Dev-only VRAM probe (excluded from the APK): plays the opening for a few seconds, hands over
## to the match, then lists video memory (texture, buffer, total) in both phases and whether
## the intro Earth textures are still loaded during the match.
## Run under Xvfb with the NVIDIA ICD (needs a real GPU).


func _ready() -> void:
	var runner := Runner.new()
	get_tree().root.add_child.call_deferred(runner)


class Runner:
	extends Node

	func _ready() -> void:
		_run()

	func _run() -> void:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IntroConfig.SAVE_PATH))
		get_tree().change_scene_to_file.call_deferred("res://scenes/Intro.tscn")
		await _seconds(8.0)
		_report("intro")
		var intro: Node = get_tree().current_scene
		if intro != null and intro.has_method("_hand_over"):
			intro.call("_hand_over", 0.3)
		var t: float = 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if get_tree().current_scene is Main:
				break
		await _seconds(4.0)
		_report("match")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IntroConfig.SAVE_PATH))
		get_tree().quit()

	func _report(phase: String) -> void:
		var mb: float = 1.0 / (1024.0 * 1024.0)
		print(
			"VRAM %s: textures %.0f MB, buffers %.0f MB, total video %.0f MB"
			% [
				phase,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * mb,
				Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) * mb,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * mb,
			]
		)
		# a texture resource that is no longer cached has been freed (its VRAM with it)
		for f: String in [
			"earth_albedo_16k.jpg", "earth_albedo_8k.jpg", "earth_clouds_8k.jpg", "earth_ocean_8k.png"
		]:
			print(
				"VRAM %s   %s loaded = %s"
				% [phase, f, ResourceLoader.has_cached(IntroConfig.TEX_DIR + f)]
			)

	func _seconds(s: float) -> void:
		var t: float = 0.0
		while t < s:
			await get_tree().process_frame
			t += get_process_delta_time()
