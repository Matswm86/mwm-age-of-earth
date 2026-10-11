class_name Kit
extends RefCounted

## Buildings and resource nodes built from the real scanned props (DESIGN 7.7: "never boxes").
## Every builder returns a Node3D whose origin sits on the ground at the object's centre; the
## caller places it. `ground` (Callable(x, z) -> height) lets props sit on the real slope.

const BASALT := Color(0.42, 0.38, 0.35)
## Sleeping-nest grade: the heap scan's leaves pulled toward dry, wilted brown so the nests read
## against the live canopy.
const NEST_TINT := Color(0.62, 0.46, 0.28)


static func _put(
	root: Node3D, model: String, at: Vector3, yaw: float, s: float, opts: Dictionary = {}
) -> Node3D:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	if opts.has("pre"):
		b = b * (opts["pre"] as Basis)
	var n: Node3D = ModelLib.make_node(model, Transform3D(b, at), opts)
	root.add_child(n)
	return n


## Home Tree (Age 1): a broad Melia crown with three leafy sleeping nests in its forks.
static func home_tree() -> Node3D:
	var r := Node3D.new()
	r.name = "HomeTree"
	var yaw: float = 0.4
	var sc: float = GameConfig.HOME_TREE_SCALE
	_put(r, GameConfig.HOME_TREE_MODEL, Vector3.ZERO, yaw, sc)
	# nests sit in the outer canopy on the south (camera) side like chimp nests: on the crown's
	# leaf surface (the top leaf height over each spot, measured on the model, y up, metres) above
	# outer forks; anything deeper is hidden by the leaves from every RTS angle (2026-10-11)
	var forks: Array[Vector3] = [
		Vector3(2.6, 6.55, 0.5), Vector3(1.0, 6.35, 1.95), Vector3(-1.0, 6.5, 2.0)
	]
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
	for k in forks.size():
		# the heap scan is pale grey from below: graded to bark brown with green leaves
		_put(r, "branch_heap", b * forks[k], k * 2.1, 1.3, {"shadow": true, "tint": NEST_TINT})
	_camp_clutter(r)
	return r


## Lived-in camp floor under the Home Tree: dragged-in branches, dead wood, basalt cobbles and
## knapping debris, so the trampled ground reads as a camp from RTS height (look only, no
## gameplay; clear of the 9 m ring where the Foragers start).
static func _camp_clutter(r: Node3D) -> void:
	var rock := {"tint": BASALT, "saturation": 0.5, "shadow": false}
	_put(r, "dry_branches", Vector3(-4.6, 0.0, 2.4), 0.6, 2.4)
	_put(r, "dry_branches", Vector3(3.8, 0.0, -4.4), 2.2, 2.2)
	_put(r, "branch_heap", Vector3(-5.8, 0.0, -1.6), 0.9, 1.1, {"tint": NEST_TINT})
	_put(r, "branch_heap", Vector3(4.4, 0.0, 4.6), 2.6, 0.9, {"tint": NEST_TINT})
	_put(r, "dry_branches", Vector3(-1.4, 0.0, -6.2), 1.1, 2.0)
	_put(r, "cobbles", Vector3(2.6, 0.0, 4.8), 0.3, 1.8, rock)
	_put(r, "cobbles", Vector3(-1.8, 0.0, 5.6), 1.9, 1.5, rock)
	_put(r, "stones", Vector3(1.2, 0.0, 5.2), 0.7, 2.6, rock)
	_put(r, "stones", Vector3(-6.4, 0.0, 3.8), 2.4, 2.4, rock)
	_put(r, "boulder_c", Vector3(3.4, -0.1, 5.6), 0.5, 0.35, rock)
	_put(r, "boulder_b", Vector3(-7.2, -0.15, 0.4), 1.5, 0.45, rock)
	_put(r, "tuber", Vector3(-2.6, 0.0, -2.8), 0.4, 2.0, {"shadow": false})
	_put(r, "tuber", Vector3(-2.2, 0.0, -3.1), 2.0, 1.8, {"shadow": false})
	return


## The Home Tree's tree alone (command-card icon).
static func home_tree_model() -> Node3D:
	return ModelLib.make_node(GameConfig.HOME_TREE_MODEL, Transform3D.IDENTITY)


## Nest Grove: three young acacias with branch nests in the crowns (footprint 8 m).
static func nest_grove() -> Node3D:
	var r := Node3D.new()
	r.name = "NestGrove"
	var spots: Array[Vector3] = [
		Vector3(-2.2, 0, -1.4), Vector3(2.4, 0, -0.8), Vector3(0.2, 0, 2.3)
	]
	for k in spots.size():
		_put(r, "acacia", spots[k], k * 2.3, 0.55)
		_put(r, "branch_heap", spots[k] + Vector3(0.3, 3.4, 0.2), k * 1.7, 0.55)
	_put(r, "dry_branches", Vector3(0.0, 0.0, 0.0), 0.5, 1.4, {"shadow": false})
	return r


## Cache: a branch heap with piles of tubers, cobbles and wood (footprint 4 m).
static func cache() -> Node3D:
	var r := Node3D.new()
	r.name = "Cache"
	_put(r, "branch_heap", Vector3(0.0, 0.0, -0.6), 0.3, 0.85)
	for k in 5:
		_put(r, "tuber", Vector3(-1.0 + 0.18 * k, 0.0, 0.9 + 0.1 * (k % 2)), k * 1.3, 1.5)
	_put(r, "cobbles", Vector3(0.9, 0.0, 0.8), 1.0, 0.8, {"tint": BASALT, "saturation": 0.5})
	_put(r, "dry_branches", Vector3(1.1, 0.0, -0.2), 2.0, 1.2)
	return r


## Knapping Floor: a disc of flakes and cobbles, two lithic cores and hammerstones (footprint 6 m).
static func knapping_floor() -> Node3D:
	var r := Node3D.new()
	r.name = "KnappingFloor"
	var rock := {"tint": BASALT, "saturation": 0.6, "shadow": false}
	# a 3 m disc of flakes and broken cobbles round a flat anvil stone
	for k in 12:
		var a: float = k * 0.52
		var d: float = 0.7 + 0.35 * (k % 4)
		_put(r, "stones", Vector3(cos(a) * d, 0.0, sin(a) * d), a * 1.7, 1.8, rock)
	_put(r, "boulder_b", Vector3(0.0, -0.18, 0.0), 0.3, 0.8, {"tint": BASALT, "saturation": 0.5})
	_put(r, "cobbles", Vector3(-1.9, 0.0, 0.6), 0.4, 1.3, {"tint": BASALT, "saturation": 0.5})
	_put(r, "cobbles", Vector3(1.8, 0.0, -0.9), 2.4, 1.2, {"tint": BASALT, "saturation": 0.5})
	_put(r, "cobbles", Vector3(0.3, 0.0, 1.9), 1.2, 1.1, {"tint": BASALT, "saturation": 0.5})
	# cores and hammerstones drawn 4x life size so they read at RTS zoom (fun > accuracy)
	# the core scan's texture is amber; Lomekwi cores are grey-black lava
	var core := {"tint": Color(0.5, 0.5, 0.5), "saturation": 0.15}
	_put(r, "lithic_core", Vector3(0.3, 0.52, 0.1), 0.0, 4.0, core)
	_put(r, "lithic_core", Vector3(1.1, 0.0, 0.7), 1.9, 4.0, core)
	_put(r, "lithic_core", Vector3(-1.0, 0.0, -0.8), 3.1, 3.5, core)
	_put(r, "boulder_c", Vector3(-0.6, 0.0, 0.9), 0.7, 0.2, {"tint": BASALT, "saturation": 0.5})
	_put(r, "boulder_c", Vector3(0.8, 0.0, -0.5), 2.1, 0.17, {"tint": BASALT, "saturation": 0.5})
	return r


static func building(type: String) -> Node3D:
	match type:
		"home_tree":
			return home_tree()
		"nest_grove":
			return nest_grove()
		"cache":
			return cache()
		"knapping_floor":
			return knapping_floor()
	return Node3D.new()


# --- resource nodes ---


## Fig bush (food, "fruit"): a real fig (Ficus carica scan, PlantCatalog) grown to ~3.5 m with
## a younger one beside it, dark broad leaves that read as food against the straw grass.
static func fig_bush() -> Node3D:
	var r := Node3D.new()
	_put(r, "fig_bush", Vector3.ZERO, 0.0, 1.6)
	_put(r, "fig_bush", Vector3(1.1, 0.0, 0.6), 2.0, 1.0)
	return r


## Tuber patch: tubers half out of dug soil (removed one by one as it empties).
static func tuber_patch() -> Node3D:
	var r := Node3D.new()
	for k in 9:
		var a: float = k * 2.39
		var d: float = 0.4 + 0.18 * k
		var n: Node3D = _put(
			r, "tuber", Vector3(cos(a) * d, -0.05, sin(a) * d), a, 1.6, {"shadow": false}
		)
		n.rotation.z = 1.2
		n.name = "Tuber%d" % k
	_put(r, "shrub_leafy", Vector3(0.0, 0.0, -1.8), 0.4, 0.55)
	_put(r, "dead_branch", Vector3(1.3, 0.0, 0.8), 2.0, 0.8, {"shadow": false})
	return r


## Three tubers (the food icon).
static func tuber_pile() -> Node3D:
	var r := Node3D.new()
	_put(r, "tuber", Vector3(-0.08, 0.0, 0.0), 0.3, 1.0)
	_put(r, "tuber", Vector3(0.1, 0.0, 0.05), 1.9, 1.0)
	_put(r, "tuber", Vector3(0.0, 0.1, -0.08), 3.0, 0.9)
	return r


## Carcass: a scavenged skeleton lying on its side (bone material, the scan has no texture).
static func carcass() -> Node3D:
	var r := Node3D.new()
	var lie := Basis(Vector3.BACK, PI * 0.5)
	var n: Node3D = _put(
		r,
		"carcass_bones",
		Vector3(0.95, 0.12, 0.0),
		0.0,
		1.0,
		{"pre": lie, "albedo": GameConfig.BONE, "roughness": 0.65}
	)
	n.name = "Bones"
	return r


## Dead-wood heap under the woodland acacias.
static func wood_heap() -> Node3D:
	var r := Node3D.new()
	_put(r, "dead_branch", Vector3(-0.4, 0.0, 0.2), 0.3, 1.3)
	_put(r, "dry_branches", Vector3(0.5, 0.0, -0.3), 1.4, 1.6)
	_put(r, "dry_branches", Vector3(-0.2, 0.0, -0.8), 2.6, 1.3)
	return r


## Cobble bed: a heap of basalt cobbles and two boulders.
static func stone_bed() -> Node3D:
	var r := Node3D.new()
	for k in 6:
		var a: float = k * 1.05
		_put(
			r,
			"cobbles",
			Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9),
			a,
			1.1,
			{"tint": BASALT, "saturation": 0.5}
		)
	_put(r, "boulder_c", Vector3(0.0, -0.1, 0.0), 0.5, 0.55, {"tint": BASALT, "saturation": 0.5})
	_put(r, "boulder_b", Vector3(1.4, -0.15, 1.0), 2.0, 0.4, {"tint": BASALT, "saturation": 0.5})
	return r


static func resource(kind: String) -> Node3D:
	match kind:
		"fruit":
			return fig_bush()
		"tuber":
			return tuber_patch()
		"carcass":
			return carcass()
		"wood":
			return wood_heap()
		"stone":
			return stone_bed()
	return Node3D.new()


## Sets construction / ghost transparency on every mesh under n.
static func set_transparency(n: Node, t: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = t
	for c in n.get_children():
		set_transparency(c, t)


static func set_overlay(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		set_overlay(c, m)
