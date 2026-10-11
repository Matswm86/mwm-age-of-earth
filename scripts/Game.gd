# gdlint:ignore = max-public-methods
class_name Game
extends Node3D

## The Age 1 opening (GDD 2, 5, 11): resources, the player's buildings, Forager jobs (gather ->
## carry -> drop at the Home Tree or a Cache, build), training at the Home Tree and the
## Stone That Cuts at the Knapping Floor. Every number comes from data/balance.json (Balance);
## layout from GameConfig. Units (movement, drawing) stay in Units; this node only gives orders.
## Signals go up to Main/Hud for feedback (GDD 12).

signal resources_changed
signal dropped(world: Vector3, text: String)
signal banner(text: String)
signal building_placed(index: int)
signal building_finished(index: int)
signal unit_trained(unit: int)
signal tech_finished(id: String)
## A player order (kind: "move", "gather", "build"); Sfx answers with a call.
signal ordered(kind: String, ids: PackedInt32Array)

enum Job { IDLE, MOVE, GO_GATHER, GATHER, GO_DROP, DROP, GO_BUILD, BUILD }

const PLAYER: int = 0
const RIVAL: int = 1


class ResNode:
	extends RefCounted
	var kind: String = ""
	var res: String = ""
	var pos := Vector2.ZERO
	var amount: float = 0.0
	var max_amount: float = 0.0
	var radius: float = 1.5
	var node: Node3D


class Bld:
	extends RefCounted
	var type: String = ""
	var pos := Vector2.ZERO
	var done: bool = false
	var progress: float = 0.0
	var hp: float = 0.0
	var node: Node3D
	var queue: Array[String] = []
	var train_t: float = 0.0
	var research: String = ""
	var research_t: float = 0.0
	var radius: float = 2.0


var terrain: RtsTerrain
var units: Units
var dressing: Dressing
var main: Main
var res: Dictionary = {}
var pop_cap: int = 0
var time: float = 0.0
var nodes: Array[ResNode] = []
var buildings: Array[Bld] = []
var techs: Dictionary = {}
var gather_mult: Dictionary = {}
## per unit (index into Units): job, target (node/building index), carry kind, amount, timer
var job := PackedInt32Array()
var target := PackedInt32Array()
var carry_res: Array[String] = []
var carry_amt := PackedFloat32Array()
var timer := PackedFloat32Array()
## Flow fields reused per target nav cell (terrain blocking never changes during a match).
var _flows: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(m: Main) -> void:
	main = m
	terrain = m.terrain
	units = m.units
	dressing = m.dressing
	_rng.seed = 99
	var start: Dictionary = Balance.section("match").get("start_resources", {})
	for k: String in ["food", "wood", "stone", "ochre"]:
		res[k] = float(start.get(k, 0))


## Areas the vegetation scatter must leave free (camp, kit), as [centre, radius].
static func exclusions() -> Array:
	var out: Array = [
		[GameConfig.HOME, 16.0], [GameConfig.WOODLAND, 13.0], [GameConfig.RIVAL_HOME, 10.0]
	]
	for p: Vector2 in GameConfig.FIG_BUSHES:
		out.append([p, 2.5])
	for p: Vector2 in GameConfig.TUBER_PATCHES:
		out.append([p, 3.5])
	for p: Vector2 in GameConfig.CARCASSES:
		out.append([p, 3.0])
	for p: Vector2 in GameConfig.STONE_BEDS:
		out.append([p, 3.0])
	return out


## Builds the starting state: Home Tree, the resource kit, the woodland stand, 6 Foragers.
func start_match() -> void:
	var home: int = _add_building("home_tree", GameConfig.HOME, true)
	var fruit: Dictionary = Balance.kit("food", "fruit")
	var tuber: Dictionary = Balance.kit("food", "tuber")
	var carcass: Dictionary = Balance.kit("food", "carcass")
	var wood: Dictionary = Balance.kit("wood", "wood")
	var stone: Dictionary = Balance.kit("stone", "stone")
	_add_nodes("fruit", "food", GameConfig.FIG_BUSHES, float(fruit.get("amount", 600)))
	_add_nodes("tuber", "food", GameConfig.TUBER_PATCHES, float(tuber.get("amount", 500)))
	_add_nodes("carcass", "food", GameConfig.CARCASSES, float(carcass.get("amount", 300)))
	_add_nodes("wood", "wood", GameConfig.WOOD_HEAPS, float(wood.get("amount", 6000)))
	_add_nodes("stone", "stone", GameConfig.STONE_BEDS, float(stone.get("amount", 1800)))
	_woodland()
	var n: int = int(Balance.section("match").get("start_units", {}).get("forager", 6))
	for k in n:
		var a: float = TAU * k / n + 0.4
		var p: Vector2 = GameConfig.HOME + Vector2(cos(a), sin(a)) * GameConfig.START_RING_M
		add_forager(terrain.nearest_walkable(p), PLAYER, a + PI)
	# the rival band, far up the shore (no AI in this build)
	for k in GameConfig.RIVAL_COUNT:
		var p: Vector2 = (
			GameConfig.RIVAL_HOME + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
		)
		var u: int = add_forager(terrain.nearest_walkable(p), RIVAL, _rng.randf() * TAU)
		units.set_clip(u, Units.C_GATHER if k % 2 == 0 else Units.C_IDLE)
	terrain.commit_ground()
	buildings[home].hp = float(Balance.building("home_tree").get("hp", 1800))
	resources_changed.emit()


func _add_nodes(kind: String, r: String, spots: Array[Vector2], total: float) -> void:
	for p in spots:
		var nd := ResNode.new()
		nd.kind = kind
		nd.res = r
		nd.pos = p
		nd.amount = total / spots.size()
		nd.max_amount = nd.amount
		nd.radius = float(GameConfig.NODE_RADIUS.get(kind, 1.5))
		nd.node = Kit.resource(kind)
		nd.node.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
		nd.node.rotation.y = _rng.randf() * TAU
		add_child(nd.node)
		nodes.append(nd)
		if kind == "tuber":
			terrain.stamp_trample(p.x, p.y, 2.6)
		terrain.stamp_contact(p.x, p.y, nd.radius + 0.4, 0.25)


## The designed acacia stand round the woodland heaps.
static func woodland_spots() -> Array[Vector2]:
	var c: Vector2 = GameConfig.WOODLAND
	var spots: Array[Vector2] = [
		c + Vector2(-6, -7),
		c + Vector2(5, -9),
		c + Vector2(-9, 5),
		c + Vector2(4, 6),
		c + Vector2(11, -1)
	]
	return spots


## Transform of woodland acacia k (shared with Scenery so the intro matches the match).
static func woodland_xform(k: int, p: Vector2, t: RtsTerrain) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, k * 1.9).scaled(Vector3.ONE * (0.95 + 0.08 * k)),
		Vector3(p.x, t.height_at(p.x, p.y) - 0.05, p.y)
	)


func _woodland() -> void:
	var spots: Array[Vector2] = woodland_spots()
	for k in spots.size():
		var p: Vector2 = spots[k]
		add_child(ModelLib.make_node(GameConfig.WOODLAND_TREE, woodland_xform(k, p, terrain)))
		terrain.stamp_contact(p.x, p.y, 5.5, 0.35)


# --- units ---


func add_forager(p: Vector2, t: int, face: float) -> int:
	var u: int = units.add_unit(p, t, face)
	if u < 0:
		return u
	job.append(Job.IDLE)
	target.append(-1)
	carry_res.append("")
	carry_amt.append(0.0)
	timer.append(0.0)
	return u


func pop() -> int:
	var n: int = 0
	for i in units.count:
		if units.team[i] == PLAYER:
			n += 1
	return n


func idle_foragers() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in units.count:
		if units.team[i] == PLAYER and job[i] == Job.IDLE:
			out.append(i)
	return out


func flow_to(goal: Vector2) -> FlowField:
	var c: int = terrain.cell_of(terrain.nearest_walkable(goal))
	if not _flows.has(c):
		_flows[c] = main.start_flow(goal)
	return _flows[c]


## Plain move (tap on ground): the group stops as a blob.
func order_move(ids: PackedInt32Array, goal: Vector2) -> void:
	var ff: FlowField = main.start_flow(goal)
	units.order_move(ids, ff)
	for i in ids:
		_set_job(i, Job.MOVE, -1)
	ordered.emit("move", ids)


func order_gather(ids: PackedInt32Array, node_i: int) -> void:
	for i in ids:
		if units.team[i] != PLAYER:
			continue
		var nd: ResNode = nodes[node_i]
		if carry_amt[i] > 0.0 and carry_res[i] != nd.res:
			carry_amt[i] = 0.0
		_go_gather(i, node_i)
	ordered.emit("gather", ids)


func order_build(ids: PackedInt32Array, b_i: int) -> void:
	for i in ids:
		if units.team[i] == PLAYER:
			_go_build(i, b_i)
	ordered.emit("build", ids)


func stop_units(ids: PackedInt32Array) -> void:
	for i in ids:
		units.stop(i)
		_set_job(i, Job.IDLE, -1)


func _set_job(i: int, j: int, t: int) -> void:
	job[i] = j
	target[i] = t
	timer[i] = 0.0


## A spot on the rim of a circle round `c`, spread by unit index so workers do not pile up.
func _rim(c: Vector2, r: float, i: int) -> Vector2:
	var a: float = float(i) * 2.399 + 0.3
	return terrain.nearest_walkable(c + Vector2(cos(a), sin(a)) * r)


func _go_gather(i: int, node_i: int) -> void:
	var nd: ResNode = nodes[node_i]
	var spot: Vector2 = _rim(nd.pos, nd.radius + 0.35, i)
	units.order_one(i, flow_to(nd.pos), spot, 0.45)
	_set_job(i, Job.GO_GATHER, node_i)


func _go_build(i: int, b_i: int) -> void:
	var b: Bld = buildings[b_i]
	units.order_one(i, flow_to(b.pos), _rim(b.pos, b.radius * 0.8 + 0.4, i), 0.5)
	_set_job(i, Job.GO_BUILD, b_i)


## Nearest finished drop site for resource r, or -1.
func _drop_for(p: Vector2, r: String) -> int:
	var best: int = -1
	var best_d: float = INF
	for k in buildings.size():
		var b: Bld = buildings[k]
		if not b.done:
			continue
		var drops: Array = Balance.building(b.type).get("drop", [])
		if not drops.has(r):
			continue
		var d: float = p.distance_to(b.pos) - b.radius
		if d < best_d:
			best_d = d
			best = k
	return best


func _go_drop(i: int) -> void:
	var b_i: int = _drop_for(units.pos[i], carry_res[i])
	if b_i < 0:
		_set_job(i, Job.IDLE, -1)
		return
	var b: Bld = buildings[b_i]
	var from: Vector2 = (units.pos[i] - b.pos).normalized()
	var spot: Vector2 = terrain.nearest_walkable(b.pos + from * (b.radius * 0.55 + 0.3))
	var keep: int = target[i]
	units.order_one(i, flow_to(b.pos), spot, 0.6)
	job[i] = Job.GO_DROP
	timer[i] = 0.0
	target[i] = keep


## Nearest node of the same kind with something left, within RETARGET_M of p; -1 if none.
func _retarget(p: Vector2, kind: String) -> int:
	var best: int = -1
	var best_d: float = GameConfig.RETARGET_M
	for k in nodes.size():
		var nd: ResNode = nodes[k]
		if nd.kind == kind and nd.amount >= 1.0:
			var d: float = p.distance_to(nd.pos)
			if d < best_d:
				best_d = d
				best = k
	return best


func rate_of(kind: String) -> float:
	return Balance.gather_rate(kind) * float(gather_mult.get(kind, 1.0))


func game_tick(dt: float) -> void:
	time += dt
	var carry_cap: float = Balance.carry()
	for i in units.count:
		if units.team[i] != PLAYER:
			continue
		match job[i]:
			Job.MOVE:
				if units.moving[i] == 0:
					_set_job(i, Job.IDLE, -1)
				units.set_clip(i, Units.C_IDLE)
			Job.IDLE:
				units.set_clip(i, Units.C_IDLE)
			Job.GO_GATHER:
				if units.moving[i] == 0:
					job[i] = Job.GATHER
			Job.GATHER:
				var nd: ResNode = nodes[target[i]]
				units.face(i, nd.pos)
				units.set_clip(
					i, Units.C_PICKUP if nd.kind == "wood" or nd.kind == "stone" else Units.C_GATHER
				)
				if nd.amount < 0.01:
					var nxt: int = _retarget(units.pos[i], nd.kind)
					if carry_amt[i] > 0.0:
						_go_drop(i)
					elif nxt >= 0:
						_go_gather(i, nxt)
					else:
						_set_job(i, Job.IDLE, -1)
					continue
				carry_res[i] = nd.res
				var got: float = minf(rate_of(nd.kind) * dt, nd.amount)
				nd.amount -= got
				carry_amt[i] += got
				_update_node_look(target[i])
				if carry_amt[i] >= carry_cap:
					carry_amt[i] = carry_cap
					_go_drop(i)
			Job.GO_DROP:
				if units.moving[i] == 0:
					job[i] = Job.DROP
					timer[i] = 0.0
			Job.DROP:
				units.set_clip(i, Units.C_PICKUP)
				timer[i] += dt
				if timer[i] >= Balance.drop_s():
					var amt: int = int(round(carry_amt[i]))
					res[carry_res[i]] = float(res[carry_res[i]]) + carry_amt[i]
					var p: Vector2 = units.pos[i]
					dropped.emit(
						Vector3(p.x, units.hgt[i] + 2.2, p.y), "+%d %s" % [amt, carry_res[i]]
					)
					carry_amt[i] = 0.0
					resources_changed.emit()
					var back: int = target[i]
					if back >= 0 and nodes[back].amount >= 1.0:
						_go_gather(i, back)
					elif back >= 0:
						var nxt: int = _retarget(units.pos[i], nodes[back].kind)
						if nxt >= 0:
							_go_gather(i, nxt)
						else:
							_set_job(i, Job.IDLE, -1)
					else:
						_set_job(i, Job.IDLE, -1)
			Job.GO_BUILD:
				if units.moving[i] == 0:
					job[i] = Job.BUILD
			Job.BUILD:
				var b: Bld = buildings[target[i]]
				if b.done:
					_after_build(i, target[i])
					continue
				units.face(i, b.pos)
				units.set_clip(i, Units.C_GATHER)
	_tick_construction(dt)
	_tick_regrow(dt)
	_tick_training(dt)
	_tick_research(dt)


func _after_build(i: int, b_i: int) -> void:
	var b: Bld = buildings[b_i]
	# a finished Cache sends its builders to the nearest source it serves
	if b.type == "cache":
		var best: int = -1
		var best_d: float = 25.0
		for k in nodes.size():
			var d: float = nodes[k].pos.distance_to(b.pos)
			if nodes[k].amount >= 1.0 and d < best_d:
				best_d = d
				best = k
		if best >= 0:
			_go_gather(i, best)
			return
	_set_job(i, Job.IDLE, -1)


func _tick_construction(dt: float) -> void:
	for k in buildings.size():
		var b: Bld = buildings[k]
		if b.done:
			continue
		var builders: int = 0
		for i in units.count:
			if units.team[i] == PLAYER and job[i] == Job.BUILD and target[i] == k:
				builders += 1
		if builders == 0:
			continue
		var build_s: float = float(Balance.building(b.type).get("build_s", 30))
		b.progress = minf(1.0, b.progress + dt * mini(builders, GameConfig.MAX_BUILDERS) / build_s)
		Kit.set_transparency(b.node, 0.7 * (1.0 - b.progress))
		if b.progress >= 1.0:
			_finish(k)


func _finish(k: int) -> void:
	var b: Bld = buildings[k]
	b.done = true
	b.hp = float(Balance.building(b.type).get("hp", 100))
	Kit.set_transparency(b.node, 0.0)
	pop_cap = mini(
		pop_cap + int(Balance.building(b.type).get("pop", 0)),
		int(Balance.section("match").get("pop_cap_max", 75))
	)
	building_finished.emit(k)
	resources_changed.emit()


func _tick_regrow(dt: float) -> void:
	var rate: float = float(Balance.data().get("fruit_regrow_per_s_per_tree", 0.05))
	for nd in nodes:
		if nd.kind == "fruit" and nd.amount < nd.max_amount:
			nd.amount = minf(nd.max_amount, nd.amount + rate * dt)


func _update_node_look(k: int) -> void:
	var nd: ResNode = nodes[k]
	var frac: float = nd.amount / maxf(nd.max_amount, 1.0)
	if nd.kind == "tuber":
		for c in nd.node.get_children():
			if str(c.name).begins_with("Tuber"):
				var idx: int = str(c.name).trim_prefix("Tuber").to_int()
				(c as Node3D).visible = frac > float(idx) / 9.0
	elif nd.kind == "carcass" and frac <= 0.0:
		nd.node.visible = false
	elif nd.kind == "wood" or nd.kind == "stone":
		var s: float = lerpf(0.55, 1.0, frac)
		nd.node.scale = Vector3(s, s, s)


# --- buildings ---


func _add_building(type: String, p: Vector2, done: bool) -> int:
	var b := Bld.new()
	b.type = type
	b.pos = p
	b.done = done
	b.progress = 1.0 if done else 0.0
	b.radius = float(GameConfig.FOOTPRINT.get(type, 4.0)) * 0.5
	b.node = Kit.building(type)
	b.node.position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	add_child(b.node)
	buildings.append(b)
	var tr: float = float(GameConfig.TRAMPLE_R.get(type, 4.0))
	terrain.stamp_trample(p.x, p.y, tr)
	terrain.stamp_contact(p.x, p.y, b.radius * 0.9, 0.35)
	terrain.commit_ground()
	if dressing != null:
		dressing.clear_area(p, tr * 0.8)
	if done:
		pop_cap += int(Balance.building(type).get("pop", 0))
	else:
		Kit.set_transparency(b.node, 0.7)
	return buildings.size() - 1


func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		if float(res.get(k, 0.0)) + 0.001 < float(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k: String in cost:
		res[k] = float(res[k]) - float(cost[k])
	resources_changed.emit()


## Why a building cannot go at p ("" when it can).
func place_problem(type: String, p: Vector2) -> String:
	var r: float = float(GameConfig.FOOTPRINT.get(type, 4.0)) * 0.5
	if p.x < r or p.y < r or p.x > SpikeConfig.MAP_SIZE - r or p.y > SpikeConfig.MAP_SIZE - r:
		return "edge"
	for k in 9:
		var q: Vector2 = p if k == 8 else p + Vector2(cos(k * PI / 4.0), sin(k * PI / 4.0)) * r
		if terrain.is_blocked_at(q):
			return "water"
	for b in buildings:
		if p.distance_to(b.pos) < r + b.radius + 0.5:
			return "building"
	for nd in nodes:
		if p.distance_to(nd.pos) < r + nd.radius + 0.5:
			return "resource"
	return ""


## Pays for and starts a building at p; `builders` walk to it. Returns its index or -1.
func place_building(type: String, p: Vector2, builders: PackedInt32Array) -> int:
	var cost: Dictionary = Balance.cost_of(Balance.building(type))
	if not can_afford(cost) or place_problem(type, p) != "":
		return -1
	pay(cost)
	var k: int = _add_building(type, p, false)
	order_build(builders, k)
	building_placed.emit(k)
	return k


func building_at(p: Vector2) -> int:
	for k in buildings.size():
		if p.distance_to(buildings[k].pos) < buildings[k].radius + 0.6:
			return k
	return -1


func node_at(p: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for k in nodes.size():
		var nd: ResNode = nodes[k]
		var d: float = p.distance_to(nd.pos)
		if d < nd.radius + 1.2 and d < best_d and nd.amount >= 1.0:
			best_d = d
			best = k
	return best


# --- training and research ---


func can_train(b_i: int) -> String:
	var b: Bld = buildings[b_i]
	if not b.done or b.type != "home_tree":
		return "no"
	if b.research != "":
		return "busy"
	if b.queue.size() >= GameConfig.QUEUE_MAX:
		return "queue full"
	if not can_afford(Balance.cost_of(Balance.unit("forager"))):
		return "food"
	return ""


func queue_forager(b_i: int) -> bool:
	if can_train(b_i) != "":
		return false
	pay(Balance.cost_of(Balance.unit("forager")))
	buildings[b_i].queue.append("forager")
	resources_changed.emit()
	return true


## True when the head of the queue waits for housing.
func pop_blocked() -> bool:
	return pop() >= pop_cap


func _tick_training(dt: float) -> void:
	for k in buildings.size():
		var b: Bld = buildings[k]
		if b.queue.is_empty() or not b.done:
			continue
		if pop_blocked():
			continue
		var train_s: float = float(Balance.unit(b.queue[0]).get("train_s", 20))
		b.train_t += dt
		if b.train_t >= train_s:
			b.train_t = 0.0
			b.queue.pop_front()
			var a: float = _rng.randf() * TAU
			var p: Vector2 = terrain.nearest_walkable(
				b.pos + Vector2(cos(a), sin(a)) * (b.radius + 1.5)
			)
			var u: int = add_forager(p, PLAYER, a)
			if u >= 0:
				unit_trained.emit(u)
			resources_changed.emit()


func can_research(b_i: int, tech_id: String) -> String:
	var b: Bld = buildings[b_i]
	var t: Dictionary = Balance.tech(tech_id)
	if techs.has(tech_id):
		return "done"
	if not b.done or str(t.get("at", "")) != b.type:
		return "no"
	if b.research != "":
		return "busy"
	if not can_afford(Balance.cost_of(t)):
		return "cost"
	return ""


func start_research(b_i: int, tech_id: String) -> bool:
	if can_research(b_i, tech_id) != "":
		return false
	pay(Balance.cost_of(Balance.tech(tech_id)))
	buildings[b_i].research = tech_id
	buildings[b_i].research_t = 0.0
	return true


func _tick_research(dt: float) -> void:
	for k in buildings.size():
		var b: Bld = buildings[k]
		if b.research == "":
			continue
		b.research_t += dt
		var t: Dictionary = Balance.tech(b.research)
		if b.research_t >= float(t.get("time_s", 40)):
			var id: String = b.research
			b.research = ""
			techs[id] = true
			var eff: Dictionary = t.get("effect", {})
			var gm: Dictionary = eff.get("gather_mult", {})
			for kind: String in gm:
				gather_mult[kind] = float(gather_mult.get(kind, 1.0)) * float(gm[kind])
			tech_finished.emit(id)
			banner.emit("The Stone That Cuts" if id == "stone_that_cuts" else id)
			resources_changed.emit()


## Seconds left and fraction done of whatever building k is busy with ("" kind when idle).
func busy_of(k: int) -> Dictionary:
	var b: Bld = buildings[k]
	if b.research != "":
		var tt: float = float(Balance.tech(b.research).get("time_s", 40))
		return {"kind": b.research, "frac": b.research_t / tt}
	if not b.queue.is_empty():
		var ts: float = float(Balance.unit(b.queue[0]).get("train_s", 20))
		return {"kind": "forager", "frac": b.train_t / ts, "count": b.queue.size()}
	return {"kind": ""}
