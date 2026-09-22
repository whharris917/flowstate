class_name SimNetwork
extends RefCounted
## Nodes, branches, and the solve that reconciles them. Mirrors
## sim/hydraulics.py Network.
##
## Method: nodal Newton-Raphson. Each free node carries one unknown
## pressure and one equation -- that the flows into it sum to zero.
## Every branch can state its flow given the pressure across it, and
## the slope of that relation, which is all Newton needs. Warm-started
## from the previous tick the state barely moves between scans, so it
## converges in two or three iterations.
##
## GDScript divergence from the reference: the Python solves the
## Newton system with a dense pivoting elimination, which is fine in
## CPython and costs 15 ms a scan here. A plant network is a sparse
## graph -- every node touches two or three branches -- so the free
## nodes are ordered once per topology to keep the matrix narrow
## (reverse Cuthill-McKee) and the system is solved within that band.
## No pivoting is needed: the Jacobian is symmetric and diagonally
## dominant, and a dead node is a bare -1 on the diagonal. Same
## equations, same answer, a tenth of the arithmetic.

const MAX_ITERATIONS := 20
## A node is converged when its imbalance is below this, or below a
## thousandth of what passes through it, whichever is smaller: a drip
## line moving a tenth of a millilitre a second cannot be judged by an
## absolute tenth of a millilitre (2026-09-20: the open end reported
## three times the rotameter upstream of it, both "converged"). Never
## looser than the absolute figure, never tighter than the floor.
const TOLERANCE_LPS := 1e-4
const TOLERANCE_REL := 1e-3
const TOLERANCE_FLOOR_LPS := 1e-8
var _throughput: PackedFloat64Array = PackedFloat64Array()   # per free node, from _residuals
## Newton on a square-law branch is badly behaved far from the answer:
## the slope of sqrt goes flat, so an undamped step can overshoot by a
## factor of ten and sit there oscillating. Capping how far a node may
## move in one iteration costs a few iterations on the first solve and
## nothing at all afterwards, because a warm start is already within a
## few hundred pascals.
const MAX_STEP_PA := 150000.0
## How many times to halve a step that is not helping before giving up
## on it and re-linearising.
const MAX_HALVINGS := 8
## Scales tried when no halving helps: a step that stopped short of a
## plateau's edge (a dry nozzle, a shut check) is lengthened before the
## solve gives up.
const LENGTHENINGS: Array[float] = [1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0]

var pressures: PackedFloat64Array = PackedFloat64Array()
var fixed: Array[bool] = []
var branches: Array[SimBranch] = []
var iterations: int = 0
var residual_lps: float = 0.0
## The node carrying residual_lps, for diagnosing a solve that did
## not land.
var worst_node: int = -1

var _solved_once: bool = false
var _islanded: Dictionary = {}       # node -> true
var _adjacency: Array = []           # node -> Array of neighbour nodes (conducting)
# The banded ordering, computed once per free-node set.
var _order_n: int = -1
var _perm: PackedInt32Array = PackedInt32Array()   # free slot -> banded row
var _band: int = 0


func add_node(pressure_pa: float = SimHydraulics.ATMOSPHERIC_PA, fixed_: bool = false) -> int:
	pressures.append(pressure_pa)
	fixed.append(fixed_)
	return pressures.size() - 1


func set_pressure(node: int, pressure_pa: float, fixed_: bool = true) -> void:
	pressures[node] = pressure_pa
	fixed[node] = fixed_


func add_branch(branch: SimBranch) -> SimBranch:
	branches.append(branch)
	return branch


func node_count() -> int:
	return pressures.size()


## Half-bandwidth of the ordered Jacobian: how far apart the rows of a
## branch's two ends sit. The banded solve costs n times its square.
func bandwidth() -> int:
	return _band


# -- the solve ---------------------------------------------------------

## Find node pressures that balance every node, then record the flow
## in each branch. Warm-started: pressures keep whatever the previous
## tick left them at, which is nearly the answer already.
func solve() -> void:
	var count := pressures.size()
	var free := PackedInt32Array()
	var index_of := PackedInt32Array()
	index_of.resize(count)
	for i in count:
		if fixed[i]:
			index_of[i] = -1
		else:
			index_of[i] = free.size()
			free.append(i)
	var n := free.size()
	iterations = 0
	if n == 0:
		_islanded.clear()
		_record_flows()
		residual_lps = 0.0
		return

	# Cold start: put the free nodes somewhere plausible rather than at
	# zero, which may be a long way from any pressure in the plant.
	# Every scan after the first is warm-started from the last answer
	# and this does not run.
	if not _solved_once:
		var total := 0.0
		var known := 0
		for i in count:
			if fixed[i]:
				total += pressures[i]
				known += 1
		if known > 0:
			var seed := total / known
			for node in free:
				pressures[node] = seed
		_solved_once = true

	_ensure_ordering(index_of, n)
	var band := _band
	var w := 2 * band + 1
	var matrix := PackedFloat64Array()
	matrix.resize(n * w)
	var rhs := PackedFloat64Array()
	rhs.resize(n)
	var saved := PackedFloat64Array()
	saved.resize(n)
	_evaluate_all()
	for _iteration in MAX_ITERATIONS:
		iterations += 1
		# What is actually connected decides two things at once: which
		# nodes have an equation to satisfy, and therefore which
		# imbalances are worth converging on. A node adrift from every
		# fixed pressure has neither -- and counting its residual anyway
		# means the loop never breaks early and burns the full iteration
		# cap every scan for the rest of the run.
		var reachable := _reachable_from_fixed(index_of, n)
		var residual := _residuals(index_of, n)
		var converged := true
		for i in n:
			if reachable[i] == 1 and absf(residual[i]) >= _tolerance_at(i):
				converged = false
				break
		if converged:
			break

		# The Jacobian, assembled straight into the band in permuted
		# order. dQ/dP of every branch lands on both its end nodes.
		matrix.fill(0.0)
		for branch in branches:
			var g := branch.g
			var gb := branch.gb if branch.two_sided else g
			var ia := index_of[branch.node_a]
			var ib := index_of[branch.node_b]
			if ia >= 0:
				var pa := _perm[ia]
				matrix[pa * w + band] -= g
				if ib >= 0:
					matrix[pa * w + (_perm[ib] - pa + band)] += gb
			if ib >= 0:
				var pb := _perm[ib]
				matrix[pb * w + band] -= gb
				if ia >= 0:
					matrix[pb * w + (_perm[ia] - pb + band)] += g
		for i in n:
			rhs[_perm[i]] = -residual[i]

		# Nodes with no conductive path back to a fixed pressure have no
		# equation to satisfy. That covers a dead-ended nozzle, but also
		# a whole island cut off by a shut valve at one end and a blocked
		# check valve at the other. Such an island makes the matrix
		# singular, and a solver that gives up on the whole system
		# because one corner of it is adrift will leave real flows
		# uncorrected everywhere else. So find what is actually
		# connected, and let the rest equalise with its neighbours the
		# way a dead leg does.
		for i in n:
			var pi := _perm[i]
			if reachable[i] == 0 or absf(matrix[pi * w + band]) < 1e-12:
				for k in range(-band, band + 1):
					var other := pi + k
					if other < 0 or other >= n:
						continue
					matrix[pi * w + (k + band)] = 0.0
					matrix[other * w + (-k + band)] = 0.0
				matrix[pi * w + band] = -1.0
				rhs[pi] = 0.0

		if not _solve_banded(matrix, rhs, n, band):
			break

		# Damped step. An undamped Newton step on a square law will
		# happily leap clean over the answer and land the same distance
		# the other side, then leap back, forever -- which is exactly
		# what a dead-ended drain does at zero flow. Try the full step,
		# and keep halving until the imbalance actually improves.
		var before := _norm(residual)
		var biggest := 0.0
		for i in n:
			biggest = maxf(biggest, absf(rhs[i]))
		if biggest < 1e-9:
			break
		for slot in n:
			saved[slot] = pressures[free[slot]]
		var scale := 1.0
		var shortest := 1.0
		var improved := false
		for _attempt in MAX_HALVINGS:
			shortest = scale
			for slot in n:
				var move := clampf(rhs[_perm[slot]] * scale, -MAX_STEP_PA, MAX_STEP_PA)
				pressures[free[slot]] = maxf(saved[slot] + move, SimHydraulics.MIN_PRESSURE_PA)
			_evaluate_all()
			if _norm(_residuals(index_of, n)) < before:
				improved = true
				break
			scale *= 0.5
		if not improved:
			# No shorter step helps. Before giving up, try a longer one:
			# a node on a plateau -- liquid arriving at a dry nozzle or a
			# shut check, whose flow is flat until the pressure reaches
			# the crack point -- gets a step sized by the open side's
			# slope, and that step reaches the crack only when the flow
			# to push is large against the gap (2026-09-22: a Cv-sized
			# nozzle fell 300 Pa short where the old fixed stub cleared
			# it, and the solve stopped with 1.6 L/s unbalanced). The
			# ladder climbs by 1.5 and 2 in turn, since the window of
			# scales that improves the norm opens at the crack and closes
			# where the open side overshoots, and doubling alone stepped
			# over it. Each rung costs one evaluation of the branches.
			for scale_up: float in LENGTHENINGS:
				if biggest * scale_up > 2.0 * MAX_STEP_PA:
					break
				for slot in n:
					var move := clampf(rhs[_perm[slot]] * scale_up, -MAX_STEP_PA, MAX_STEP_PA)
					pressures[free[slot]] = maxf(saved[slot] + move, SimHydraulics.MIN_PRESSURE_PA)
				_evaluate_all()
				if _norm(_residuals(index_of, n)) < before:
					improved = true
					break
		if not improved:
			# No scale of this step helps, so re-linearising will not
			# either: a trickle into a shut check valve, whose crack
			# point is tens of kPa away and whose slope says otherwise.
			# The imbalance is below anything the plant can see; stop
			# rather than grind out the cap every scan -- at the shortest
			# step tried, not back at the start: that nudge is what lets
			# the next scan leave a plateau whose slope reads zero (a
			# regulator shut a hair above its setpoint, 2026-09-22:
			# restored exactly, the drip demo never reopened it).
			for slot in n:
				var move := clampf(rhs[_perm[slot]] * shortest, -MAX_STEP_PA, MAX_STEP_PA)
				pressures[free[slot]] = maxf(saved[slot] + move, SimHydraulics.MIN_PRESSURE_PA)
			_evaluate_all()
			break

	# Flows are what the converged pressures say, recorded BEFORE any
	# island is settled: settling averages stale pressures, and reading
	# a check valve at the average can open it on paper and push
	# material into a vessel from nowhere.
	_record_flows()
	_settle_islands(free, index_of, n)
	residual_lps = _worst_imbalance(index_of, n)


## Order the free nodes so that every branch joins two rows close
## together: reverse Cuthill-McKee over the topological graph (every
## branch, conducting or not, so one ordering serves every iteration).
## The bandwidth that falls out is what the banded solve works within.
func _ensure_ordering(index_of: PackedInt32Array, n: int) -> void:
	if _order_n == n:
		return
	var adjacency: Array = []
	for _i in n:
		adjacency.append([])
	for branch in branches:
		var ia := index_of[branch.node_a]
		var ib := index_of[branch.node_b]
		if ia >= 0 and ib >= 0 and ia != ib:
			(adjacency[ia] as Array).append(ib)
			(adjacency[ib] as Array).append(ia)
	var degree := PackedInt32Array()
	degree.resize(n)
	for i in n:
		degree[i] = (adjacency[i] as Array).size()
	var visited := PackedByteArray()
	visited.resize(n)
	visited.fill(0)
	var order := PackedInt32Array()
	while order.size() < n:
		# Start each component from its lowest-degree node.
		var start := -1
		for i in n:
			if visited[i] == 0 and (start < 0 or degree[i] < degree[start]):
				start = i
		visited[start] = 1
		var queue := PackedInt32Array([start])
		var head := 0
		while head < queue.size():
			var node := queue[head]
			head += 1
			order.append(node)
			var next: Array = (adjacency[node] as Array).duplicate()
			next.sort_custom(func(x: int, y: int) -> bool: return degree[x] < degree[y])
			for neighbour: int in next:
				if visited[neighbour] == 0:
					visited[neighbour] = 1
					queue.append(neighbour)
	order.reverse()
	_perm = PackedInt32Array()
	_perm.resize(n)
	for position in n:
		_perm[order[position]] = position
	_band = 0
	for branch in branches:
		var ia := index_of[branch.node_a]
		var ib := index_of[branch.node_b]
		if ia >= 0 and ib >= 0:
			_band = maxi(_band, absi(_perm[ia] - _perm[ib]))
	_order_n = n


## Anything cut off from every fixed pressure settles to one common
## value and stops flowing.
##
## Run once, after the iteration: moving pressures behind Newton's
## back mid-solve stops it converging at all. Follow only branches
## that conduct. Averaging across a stopped pump would drag the island
## toward the header it is isolated from, and the difference that
## leaves behind keeps pushing material through the pipe between them,
## material nothing supplied.
func _settle_islands(free: PackedInt32Array, index_of: PackedInt32Array, n: int) -> void:
	# The branches were last evaluated at the pressures the loop left
	# behind, so the connectivity here is current.
	var reachable := _reachable_from_fixed(index_of, n)
	var settled: Dictionary = {}
	for slot in n:
		if reachable[slot] == 1:
			continue
		var start := free[slot]
		if settled.has(start):
			continue
		var island := PackedInt32Array([start])
		settled[start] = true
		var queue := PackedInt32Array([start])
		while queue.size() > 0:
			var node := queue[queue.size() - 1]
			queue.resize(queue.size() - 1)
			for neighbour: int in _adjacency[node]:
				if settled.has(neighbour) or index_of[neighbour] < 0:
					continue
				if reachable[index_of[neighbour]] == 1:
					continue
				settled[neighbour] = true
				island.append(neighbour)
				queue.append(neighbour)
		var common := 0.0
		for node in island:
			common += pressures[node]
		common /= island.size()
		for node in island:
			pressures[node] = common
	_islanded = settled
	# Nothing inside an island can be flowing. An island is cut off
	# from every fixed pressure, so there is nowhere for material to
	# come from or go to -- and settling it to one common pressure
	# leaves a RUNNING pump reading its shutoff flow, which is a litre
	# a second of nothing arriving from nowhere.
	for branch in branches:
		if settled.has(branch.node_a) and settled.has(branch.node_b):
			branch.flow_lps = 0.0


## Which free nodes can actually feel a fixed pressure, through
## branches that are currently conducting (per the last evaluate). A
## shut valve or a blocked check valve is a wall: whatever is behind it
## is hydraulically adrift and has nothing to solve. Leaves the
## conducting adjacency in _adjacency for the island pass.
func _reachable_from_fixed(index_of: PackedInt32Array, n: int) -> PackedByteArray:
	var count := pressures.size()
	if _adjacency.size() != count:
		_adjacency.resize(count)
		for i in count:
			_adjacency[i] = []
	else:
		for i in count:
			(_adjacency[i] as Array).clear()
	for branch in branches:
		if not branch.conducting:
			continue
		(_adjacency[branch.node_a] as Array).append(branch.node_b)
		(_adjacency[branch.node_b] as Array).append(branch.node_a)
	var seen := PackedByteArray()
	seen.resize(count)
	seen.fill(0)
	var frontier := PackedInt32Array()
	for i in count:
		if fixed[i]:
			seen[i] = 1
			frontier.append(i)
	while frontier.size() > 0:
		var node := frontier[frontier.size() - 1]
		frontier.resize(frontier.size() - 1)
		for neighbour: int in _adjacency[node]:
			if seen[neighbour] == 0:
				seen[neighbour] = 1
				frontier.append(neighbour)
	var reachable := PackedByteArray()
	reachable.resize(n)
	for node in count:
		var slot := index_of[node]
		if slot >= 0:
			reachable[slot] = seen[node]
	return reachable


## Net flow into each free node. Zero everywhere is the answer.
func _residuals(index_of: PackedInt32Array, n: int) -> PackedFloat64Array:
	var residual := PackedFloat64Array()
	residual.resize(n)
	residual.fill(0.0)
	_throughput.resize(n)
	_throughput.fill(0.0)
	for branch in branches:
		var q := branch.q
		var ia := index_of[branch.node_a]
		var ib := index_of[branch.node_b]
		if ia >= 0:
			residual[ia] -= q
			_throughput[ia] += absf(q)
		if ib >= 0:
			residual[ib] += q
			_throughput[ib] += absf(q)
	return residual


## The imbalance a free node may keep: relative to what it passes.
func _tolerance_at(slot: int) -> float:
	return minf(TOLERANCE_LPS, maxf(TOLERANCE_FLOOR_LPS, TOLERANCE_REL * _throughput[slot]))


## Ask every branch its flow, slope and connectivity at the current
## pressures, once. Everything else in the iteration reads the fields.
func _evaluate_all() -> void:
	for branch in branches:
		branch.evaluate(pressures[branch.node_a], pressures[branch.node_b])


## Every branch's flow at the current pressures. Called before islands
## are settled, so a shut check valve stays shut in the record.
func _record_flows() -> void:
	for branch in branches:
		branch.flow_lps = branch.flow_at(pressures[branch.node_a], pressures[branch.node_b])


## The largest flow imbalance left at any free node, reported after
## the last update rather than before it, so a caller can trust it as
## a measure of the answer it actually got.
func _worst_imbalance(index_of: PackedInt32Array, n: int) -> float:
	if n == 0:
		return 0.0
	var totals := PackedFloat64Array()
	totals.resize(n)
	totals.fill(0.0)
	for branch in branches:
		var ia := index_of[branch.node_a]
		var ib := index_of[branch.node_b]
		if ia >= 0:
			totals[ia] -= branch.flow_lps
		if ib >= 0:
			totals[ib] += branch.flow_lps
	var worst := 0.0
	worst_node = -1
	for i in n:
		if absf(totals[i]) > worst:
			worst = absf(totals[i])
			for node in pressures.size():
				if index_of[node] == i:
					worst_node = node
	return worst


## The branches meeting at a node, with their solved flows and the
## node's pressure: what to read when a scan hits the iteration cap.
func describe_node(node: int) -> String:
	if node < 0 or node >= pressures.size():
		return "no node"
	var parts: Array[String] = []
	for branch in branches:
		if branch.node_a == node:
			parts.append("%s ->%.3f" % [branch.branch_name, branch.flow_lps])
		elif branch.node_b == node:
			parts.append("%s <-%.3f" % [branch.branch_name, branch.flow_lps])
	return "node %d at %.0f Pa: %s" % [node, pressures[node], ", ".join(parts)]


static func _norm(values: PackedFloat64Array) -> float:
	var total := 0.0
	for v in values:
		total += v * v
	return sqrt(total)


## Gaussian elimination within the band, in place: on return rhs holds
## the solution. No pivoting, which the matrix earns by being
## symmetric and diagonally dominant with every dead row already
## replaced by a bare -1. Entry (i, j) lives at i*w + (j - i + b).
## False if a pivot vanishes, which the caller treats as "keep last
## tick's answer" rather than crashing the plant.
static func _solve_banded(matrix: PackedFloat64Array, rhs: PackedFloat64Array,
		n: int, b: int) -> bool:
	var w := 2 * b + 1
	for col in n:
		var crow := col * w
		var diag := matrix[crow + b]
		if absf(diag) < 1e-14:
			return false
		var inv := 1.0 / diag
		var last := mini(col + b, n - 1)
		for row in range(col + 1, last + 1):
			var rrow := row * w
			var factor := matrix[rrow + (col - row + b)] * inv
			if factor == 0.0:
				continue
			for k in range(col, last + 1):
				matrix[rrow + (k - row + b)] -= factor * matrix[crow + (k - col + b)]
			rhs[row] -= factor * rhs[col]
	for row in range(n - 1, -1, -1):
		var rrow := row * w
		var total := rhs[row]
		var last := mini(row + b, n - 1)
		for k in range(row + 1, last + 1):
			total -= matrix[rrow + (k - row + b)] * rhs[k]
		rhs[row] = total / matrix[rrow + b]
	return true
