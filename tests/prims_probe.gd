extends Node

## Dev-only triangle accounting (excluded from the APK): the bench crowd at the default camera;
## for each group, the primitives and draw calls it adds to the frame (shown, then hidden), and
## for shadow casters what their shadow pass adds. Run under Xvfb like sv_bench.tscn.

var main: Main


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	main.apply_preset(2)
	main.units.reveal_all = true
	main.cam.focus = SpikeConfig.BENCH_CENTRE
	main.cam.height = SpikeConfig.CAM_DEFAULT_H
	main.cam.apply()
	for t in 3:
		main.order_team(t, SpikeConfig.BENCH_CENTRE + Vector2(cos(t * 2.1), sin(t * 2.1)) * 14.0)
	await _frames(60)
	main.set_process(false)
	await _frames(5)
	var base: Vector2 = await _m()
	print("PRIMS all: %dk prims, %d draws" % [base.x / 1000, base.y])
	var groups: Dictionary = {}
	for n: Node in main.dressing.get_children():
		var key: String = (n.name as String).get_slice("_c", 0).rstrip("0123456789").trim_suffix("_")
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(n)
	groups["GRASS"] = [main.grass]
	groups["REEDS"] = [main.reeds]
	groups["UNITS body"] = [main.units.get_node("UnitsMM")]
	groups["UNITS shadow"] = [main.units.get_node("UnitsShadow")]
	groups["ANIMALS"] = [main.animals]
	groups["CAMP+KIT"] = [main.game]
	groups["TERRAIN+LAKE"] = [main.terrain]
	groups["MARKS"] = [main.marks, main.overlay]
	for k: String in groups:
		for n: Node3D in groups[k]:
			n.visible = false
		var m: Vector2 = await _m()
		for n: Node3D in groups[k]:
			n.visible = true
		print("PRIMS %-26s %6dk prims %4d draws" % [k, (base.x - m.x) / 1000, base.y - m.y])
	var camp: Dictionary = {}
	for n: Node in main.game.find_children("*", "GeometryInstance3D", true, false):
		var key: String = (n.get_parent().name as String).rstrip("0123456789@").trim_suffix("_")
		if not camp.has(key):
			camp[key] = []
		(camp[key] as Array).append(n)
	for k: String in camp:
		for n: GeometryInstance3D in camp[k]:
			n.visible = false
		var m: Vector2 = await _m()
		for n: GeometryInstance3D in camp[k]:
			n.visible = true
		var sh: int = 0
		for n: GeometryInstance3D in camp[k]:
			if n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				sh += 1
		print("PRIMS camp %-21s %6dk prims %4d draws (%d nodes, %d cast shadows)" % [k, (base.x - m.x) / 1000, base.y - m.y, (camp[k] as Array).size(), sh])
	main.sun.shadow_enabled = false
	var ns: Vector2 = await _m()
	main.sun.shadow_enabled = true
	print("PRIMS %-26s %6dk prims %4d draws" % ["(whole sun shadow pass)", (base.x - ns.x) / 1000, base.y - ns.y])
	get_tree().quit()


func _m() -> Vector2:
	await _frames(4)
	await RenderingServer.frame_post_draw
	return Vector2(
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
