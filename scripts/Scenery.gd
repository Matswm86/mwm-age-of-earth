class_name Scenery
extends RefCounted

## The camp's look without the game state, for scenes that show the map but are not the match
## (the opening intro's local stage): vegetation (Dressing), the Home Tree with its trampled
## floor, the resource kit props and the woodland stand, all as in Main at match start.
## Usage: `Scenery.build(terrain, parent)` after `terrain.build(...)`.


static func build(terrain: RtsTerrain, parent: Node3D) -> void:
	var d := Dressing.new()
	d.name = "Dressing"
	parent.add_child(d)
	d.build(terrain, Game.exclusions())
	var home: Node3D = Kit.home_tree()
	var h: Vector2 = GameConfig.HOME
	home.position = Vector3(h.x, terrain.height_at(h.x, h.y), h.y)
	parent.add_child(home)
	terrain.stamp_trample(h.x, h.y, float(GameConfig.TRAMPLE_R["home_tree"]))
	var kit: Array = [
		["fruit", GameConfig.FIG_BUSHES],
		["tuber", GameConfig.TUBER_PATCHES],
		["carcass", GameConfig.CARCASSES],
		["wood", GameConfig.WOOD_HEAPS],
		["stone", GameConfig.STONE_BEDS],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for e: Array in kit:
		var spots: Array[Vector2] = []
		spots.assign(e[1])
		for p in spots:
			var n: Node3D = Kit.resource(str(e[0]))
			n.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
			n.rotation.y = rng.randf() * TAU
			parent.add_child(n)
	var spots: Array[Vector2] = Game.woodland_spots()
	for k in spots.size():
		var xf: Transform3D = Game.woodland_xform(k, spots[k], terrain)
		parent.add_child(ModelLib.make_node(GameConfig.WOODLAND_TREE, xf))
	terrain.commit_ground()
