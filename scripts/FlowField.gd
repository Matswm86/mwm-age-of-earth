class_name FlowField
extends RefCounted

## One move order: the integration field (cost to reach the target from every 4 m nav cell)
## over the 128 x 128 grid, 8 neighbours, straight cost 10 and diagonal 14, no corner cutting.
## Units read the field and step toward the cheapest neighbour cell (see Units.gd), so the
## direction field is never stored. build() is exact Dijkstra with a bucket queue (Dial) and runs
## on a WorkerThreadPool task (Main.order_*); `is_built` turns true on the main thread when it is
## done, and until then units walk straight at the target.

const UNREACHED: int = 1 << 30
const DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const COST: Array[int] = [10, 10, 10, 10, 14, 14, 14, 14]
const BUCKETS: int = 15

var target: Vector2 = Vector2.ZERO
var target_cell: int = 0
var dist: PackedInt32Array = PackedInt32Array()
## Units that still follow this order (set by Units when the order is given).
var group_size: int = 1
var arrive_r: float = 1.0
var build_ms: float = 0.0
var is_built: bool = false


## Sets the target (main thread, before the task starts) so units can head straight for it.
func set_target(goal: Vector2) -> void:
	var n: int = SpikeConfig.NAV_CELLS
	target = goal
	target_cell = (
		clampi(int(goal.y / SpikeConfig.NAV_CELL_M), 0, n - 1) * n
		+ clampi(int(goal.x / SpikeConfig.NAV_CELL_M), 0, n - 1)
	)


## Fills `dist` (worker thread). Reads only `blocked`, writes only this object's fields.
func build(blocked: PackedByteArray) -> void:
	var t0: int = Time.get_ticks_usec()
	var n: int = SpikeConfig.NAV_CELLS
	var total: int = n * n
	dist.resize(total)
	dist.fill(UNREACHED)
	# Dial's algorithm: 15 cyclic buckets (max edge cost 14 + 1), each a linked list of nodes in
	# flat arrays, so every cell is expanded exactly once (exact Dijkstra, no heap).
	var bucket_head := PackedInt32Array()
	bucket_head.resize(BUCKETS)
	bucket_head.fill(-1)
	var node_cell := PackedInt32Array()
	var node_next := PackedInt32Array()
	node_cell.resize(total * 2)
	node_next.resize(total * 2)
	var used: int = 0
	var pending: int = 1
	dist[target_cell] = 0
	node_cell[0] = target_cell
	node_next[0] = -1
	bucket_head[0] = 0
	used = 1
	var cur: int = 0
	while pending > 0:
		var b: int = cur % BUCKETS
		var node: int = bucket_head[b]
		if node < 0:
			cur += 1
			continue
		bucket_head[b] = node_next[node]
		pending -= 1
		var c: int = node_cell[node]
		if dist[c] != cur:
			continue
		var cx: int = c & (n - 1)
		var cy: int = c >> SpikeConfig.NAV_SHIFT
		for k in 8:
			var nx: int = cx + DX[k]
			var ny: int = cy + DY[k]
			if nx < 0 or ny < 0 or nx >= n or ny >= n:
				continue
			var nb: int = ny * n + nx
			if blocked[nb] == 1:
				continue
			if k >= 4 and (blocked[cy * n + nx] == 1 or blocked[ny * n + cx] == 1):
				continue
			var nd: int = cur + COST[k]
			if nd < dist[nb]:
				dist[nb] = nd
				if used >= node_cell.size():
					node_cell.resize(used * 2)
					node_next.resize(used * 2)
				var nbk: int = nd % BUCKETS
				node_cell[used] = nb
				node_next[used] = bucket_head[nbk]
				bucket_head[nbk] = used
				used += 1
				pending += 1
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Centre of the cheapest neighbour of `cell` (no corner cutting), or -1 when none is cheaper.
func next_cell(cell: int, blocked: PackedByteArray) -> int:
	var n: int = SpikeConfig.NAV_CELLS
	var cx: int = cell & (n - 1)
	var cy: int = cell >> SpikeConfig.NAV_SHIFT
	var best: int = -1
	var best_d: int = dist[cell]
	for k in 8:
		var nx: int = cx + DX[k]
		var ny: int = cy + DY[k]
		if nx < 0 or ny < 0 or nx >= n or ny >= n:
			continue
		if k >= 4 and (blocked[cy * n + nx] == 1 or blocked[ny * n + cx] == 1):
			continue
		var nb: int = ny * n + nx
		if dist[nb] < best_d:
			best_d = dist[nb]
			best = nb
	return best
