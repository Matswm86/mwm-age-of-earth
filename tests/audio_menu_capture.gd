extends Node

## Dev-only: screenshot of the Menu with the Sound / Volume buttons and the volume panel open.
## Xvfb + NVIDIA recipe (game-studio CLAUDE.md), CAPTURE_DIR set.


func _ready() -> void:
	var main: Main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for k in 30:
		await get_tree().process_frame
	PerfOverlay.set_ui_visible(true)
	Sfx.call("_toggle_panel")
	for k in 10:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("CAPTURE_DIR") + "/audio_menu.png")
	get_tree().quit()
