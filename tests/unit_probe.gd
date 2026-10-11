extends Node
## Dev probe (not shipped): low side views of the VAT bodies in idle, run and gather, plus the
## gazelle and leopard, to check the bake (pose, facing +Z, paint bands). CAPTURE_DIR as capture.gd.

var out_dir: String = OS.get_environment("CAPTURE_DIR")


func _ready() -> void:
	var main: Main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.hud.visible = false
	main.set_fog(false)
	var c := Vector2(404.0, 300.0)
	var y: float = main.terrain.height_at(c.x, c.y)
	var clips: Array[int] = [Units.C_IDLE, Units.C_RUN, Units.C_GATHER, Units.C_PICKUP]
	for k in 4:
		var u: int = main.units.add_unit(c + Vector2(-2.4 + k * 1.6, 0.0), 0, 0.0)
		main.game.job.append(0)
		main.game.target.append(-1)
		main.game.carry_res.append("")
		main.game.carry_amt.append(0.0)
		main.game.timer.append(0.0)
		main.units.set_clip(u, clips[k])
		if clips[k] == Units.C_RUN:
			main.units.walk[u] = 1.0
	var u2: int = main.units.add_unit(c + Vector2(3.6, 0.0), 1, 0.0)
	main.game.job.append(0)
	main.game.target.append(-1)
	main.game.carry_res.append("")
	main.game.carry_amt.append(0.0)
	main.game.timer.append(0.0)
	main.bench_mode = true
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30.0
	cam.position = Vector3(c.x + 0.4, y + 1.2, c.y + 9.0)
	cam.look_at(Vector3(c.x + 0.4, y + 0.7, c.y), Vector3.UP)
	cam.current = true
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + "/p1_bodies_front.png")
	cam.position = Vector3(c.x + 9.0, y + 1.2, c.y)
	cam.look_at(Vector3(c.x, y + 0.7, c.y), Vector3.UP)
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + "/p2_bodies_side.png")
	print("PROBE DONE ", u2)
	get_tree().quit()
