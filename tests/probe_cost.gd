extends Node
## Dev probe (not shipped): primitives and draw calls per scenery group at the default camera,
## by hiding one group at a time. Run like capture.tscn (needs the GPU).
func _ready() -> void:
	var main: Main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	for i in 20:
		await get_tree().process_frame
	var base: Vector2 = await _measure()
	print("COST all: %dk prims, %d draws; grass %d trees %d shrubs %d rocks %d" % [base.x / 1000, base.y, main.dressing.grass_count, main.dressing.tree_count, main.dressing.shrub_count, main.dressing.rock_count])
	var groups: Array[String] = ["tussock", "grass", "acacia", "doum_palm", "shrub", "cobbles", "stones", "boulder"]
	for g in groups:
		for c in main.dressing.get_children():
			if str(c.name).begins_with(g):
				(c as Node3D).visible = false
		var m: Vector2 = await _measure()
		print("COST %-10s %5dk prims %4d draws" % [g, (base.x - m.x) / 1000, base.y - m.y])
		for c in main.dressing.get_children():
			(c as Node3D).visible = true
	main.sun.shadow_enabled = false
	var ns: Vector2 = await _measure()
	print("COST shadows   %5dk prims %4d draws" % [(base.x - ns.x) / 1000, base.y - ns.y])
	main.sun.shadow_enabled = true
	main.terrain.visible = false
	var nt: Vector2 = await _measure()
	print("COST terrain+lake %5dk prims %4d draws" % [(base.x - nt.x) / 1000, base.y - nt.y])
	get_tree().quit()


func _measure() -> Vector2:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return Vector2(
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	)
