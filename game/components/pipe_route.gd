class_name PipeRoute
## Turns a sparse waypoint list into an orthogonal pipe path.
##
## Each leg between waypoints becomes axis-aligned segments with a
## consistent trade convention: rising legs run horizontal first and
## come up at the destination; falling legs drop straight down first,
## then run horizontal — the way real pipe drops are routed.


const STUB := 0.35   # a run leaves its fitting straight, this far


## A full equipment-to-equipment route: leave the source fitting
## along its outward axis, approach the destination along its own,
## and route orthogonally in between. Zero directions degrade to no
## stub (free endpoints).
static func routed(from: Vector3, from_dir: Vector3, to: Vector3, to_dir: Vector3,
		waypoints: Array) -> Array[Vector3]:
	var stub_a := from + from_dir * STUB
	var stub_b := to + to_dir * STUB
	var sparse: Array = [stub_a]
	sparse.append_array(waypoints)
	sparse.append(stub_b)
	var path := orthogonalize(sparse)
	path.insert(0, from)
	path.append(to)
	return path


## The same route, but each leg found by search on a half-metre grid
## round whatever `blocked` says is solid (director, 2026-09-12:
## intersection avoidance for every run). A leg that cannot be found
## within the search budget falls back to the plain orthogonal leg.
## `blocked` takes a cell centre (plant-local) and answers true for a
## cell a run must not pass through.
const CELL := 0.5
const CELL_Y0 := 0.35       # the y a ground run sits at is a cell centre
const SEARCH_BUDGET := 3000
const MARGIN_CELLS := 14
const STUB_CLEAR := 1.2     # a run leaves through its own equipment's volume: that much is open

## `busy` answers true for a cell another run already occupies: not a
## wall, but a detour is steered round it so a searched route lands in
## a free corridor rather than on top of a hand-laid line.
static func routed_avoiding(from: Vector3, from_dir: Vector3, to: Vector3, to_dir: Vector3,
		waypoints: Array, blocked: Callable, busy: Callable = Callable()) -> Array[Vector3]:
	var stub_a := from + from_dir * STUB
	var stub_b := to + to_dir * STUB
	var sparse: Array = [stub_a]
	sparse.append_array(waypoints)
	sparse.append(stub_b)
	var out: Array[Vector3] = [from, stub_a]
	last_searched = false
	for k in range(1, sparse.size()):
		var a: Vector3 = out[out.size() - 1]
		var b: Vector3 = sparse[k]
		# The plain leg first: a run laid where it was laid is the point,
		# and the search only runs where that leg passes through something.
		var plain := _leg(a, b)
		if _clear(a, plain, blocked):
			for corner in plain:
				_append(out, corner)
			continue
		last_searched = true
		var cells := _astar(a, b, blocked, busy)
		if cells.is_empty():
			for corner in plain:
				_append(out, corner)
			continue
		_snap_end(cells, b)
		for corner in _leg(a, cells[0]):
			_append(out, corner)
		for corner in cells:
			_append(out, corner)
		for corner in _leg(out[out.size() - 1], b):
			_append(out, corner)
	out.append(to)
	return _straighten(out)


## Does a polyline from `start` through `points` pass through
## something solid? Sampled every quarter metre at the run's own
## height — snapping a sample to the grid put a conduit lying on a
## tray down into the beam under it. The first and last STUB_CLEAR
## are exempt, since a stub leaves through its own equipment's volume.
static func _clear(start: Vector3, points: Array[Vector3], blocked: Callable) -> bool:
	var finish := points[points.size() - 1]
	var a := start
	for b in points:
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / 0.25))
		for i in range(1, steps + 1):
			var p := a.lerp(b, float(i) / steps)
			if p.distance_to(start) < STUB_CLEAR or p.distance_to(finish) < STUB_CLEAR:
				continue
			if bool(blocked.call(p)):
				last_block = p
				return false
		a = b
	return true


## Pull a searched path's last straight onto `target` so the grid's
## quarter-metre misfit does not become a pair of elbows a hand apart.
## Each off-axis difference walks back along the path until a straight
## that runs on that axis absorbs it; a difference nothing absorbs is
## left for the closing leg.
static func _snap_end(cells: Array[Vector3], target: Vector3) -> void:
	if cells.size() < 2:
		return
	var last := cells.size() - 1
	var along := _axis(cells[last] - cells[last - 1])
	for axis in 3:
		if axis == along:
			cells[last][axis] = target[axis]   # the last straight simply ends at the target
			continue
		var delta: float = target[axis] - cells[last][axis]
		if absf(delta) < 0.001 or absf(delta) > CELL * 0.51:
			continue
		var absorber := -1
		for i in range(last, 0, -1):
			if _axis(cells[i] - cells[i - 1]) == axis:
				absorber = i
				break
		if absorber < 0:
			continue
		for i in range(absorber, last + 1):
			cells[i][axis] += delta


static func _axis(v: Vector3) -> int:
	if absf(v.x) >= absf(v.y) and absf(v.x) >= absf(v.z):
		return 0
	return 1 if absf(v.y) >= absf(v.z) else 2


## Router statistics for the smoke run's cost line, and the cell that
## last failed a plain leg for FLOWSTATE_ROUTE_DEBUG.
static var last_block: Vector3 = Vector3.ZERO
static var last_searched: bool = false
static var searches: int = 0
static var failures: int = 0
static var expansions: int = 0
static var search_usec: int = 0


## A run a few centimetres above grade — a pump's inlet — is in the
## ground cell, never in the one below the floor.
static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x / CELL), maxi(0, roundi((p.y - CELL_Y0) / CELL)), roundi(p.z / CELL))


static func cell_center(c: Vector3i) -> Vector3:
	return Vector3(c.x * CELL, CELL_Y0 + c.y * CELL, c.z * CELL)


const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


## A* between the cells containing a and b: six moves, a straight
## step costs 2, a vertical one 3, a turn 2 more, and the open set is
## bucketed by score so it stays cheap in GDScript. Returns the cell
## centres from start to goal, collinear runs merged, or [] on failure.
## Identical legs — twenty feeds down one trunk — are searched once.
## Plant clears this whenever its obstacle cache clears.
static var _leg_cache: Dictionary = {}


static func clear_cache() -> void:
	_leg_cache.clear()


static func _astar(a: Vector3, b: Vector3, blocked: Callable, busy: Callable) -> Array[Vector3]:
	var cache_key := "%.2f,%.2f,%.2f>%.2f,%.2f,%.2f" % [a.x, a.y, a.z, b.x, b.y, b.z]
	if _leg_cache.has(cache_key):
		return (_leg_cache[cache_key] as Array[Vector3]).duplicate()
	var t0 := Time.get_ticks_usec()
	var found := _search(a, b, blocked, busy)
	search_usec += Time.get_ticks_usec() - t0
	searches += 1
	if found.is_empty():
		failures += 1
	_leg_cache[cache_key] = found
	return found.duplicate()


## The grid is anchored at `a`: the start is a cell centre exactly, so
## the found path leaves `a` with no jog, and the goal is the cell that
## holds `b`, a quarter metre off at most, which _snap_end absorbs.
static func _search(a: Vector3, b: Vector3, blocked: Callable, busy: Callable) -> Array[Vector3]:
	var start := Vector3i.ZERO
	var goal := Vector3i(roundi((b.x - a.x) / CELL), roundi((b.y - a.y) / CELL), roundi((b.z - a.z) / CELL))
	if goal == start:
		return [a]
	var lo := Vector3i(mini(0, goal.x) - MARGIN_CELLS, mini(0, goal.y) - 2, mini(0, goal.z) - MARGIN_CELLS)
	var hi := Vector3i(maxi(0, goal.x) + MARGIN_CELLS, maxi(0, goal.y) + MARGIN_CELLS,
		maxi(0, goal.z) + MARGIN_CELLS)
	var ceiling := maxi(0, goal.y)
	var floor_ := mini(0, goal.y)
	var g := {start: 0}
	var came := {}
	var arrived := {start: -1}
	var buckets := {}
	var f0 := 2 * (absi(goal.x) + absi(goal.y) + absi(goal.z))
	buckets[f0] = [start]
	var current_f := f0
	var expanded := 0
	var closed := {}
	while expanded < SEARCH_BUDGET:
		while not buckets.has(current_f) or (buckets[current_f] as Array).is_empty():
			buckets.erase(current_f)
			if buckets.is_empty():
				return []
			current_f = buckets.keys().min()
		var node: Vector3i = (buckets[current_f] as Array).pop_back()
		if closed.has(node):
			continue
		closed[node] = true
		expanded += 1
		expansions += 1
		if node == goal:
			return _rebuild(came, node, a)
		var last_dir: int = arrived[node]
		for d in DIRS.size():
			var step := DIRS[d]
			var next := node + step
			if next.x < lo.x or next.y < lo.y or next.z < lo.z or next.x > hi.x or next.y > hi.y or next.z > hi.z:
				continue
			if closed.has(next):
				continue
			var centre := a + Vector3(next) * CELL
			if next != goal and centre.y < 0.05:
				continue  # below grade
			var open_end := centre.distance_to(a) <= STUB_CLEAR or centre.distance_to(b) <= STUB_CLEAR
			if next != goal and not open_end and bool(blocked.call(centre)):
				continue
			# The probe is shallow, so a vertical step also looks halfway:
			# a deck is thinner than the gap between two cells.
			if step.y != 0 and next != goal and not open_end 					and bool(blocked.call(centre - Vector3(0.0, step.y * CELL * 0.5, 0.0))):
				continue
			var cost := 3 if step.y != 0 else 2
			if not open_end and busy.is_valid() and bool(busy.call(centre)):
				cost += 5   # another run lies here: go round it if there is room
			if last_dir >= 0 and last_dir != d:
				cost += 2
			if next.y > ceiling:
				cost += 6   # overhead, with nothing to carry it
			elif next.y < floor_:
				cost += 2
			elif next.y > floor_ + 1:
				cost += 1   # the low road: drop first, or run low before rising
			var tentative: int = g[node] + cost
			if g.has(next) and tentative >= int(g[next]):
				continue
			g[next] = tentative
			came[next] = node
			arrived[next] = d
			# Weighted a little past admissible: an orthogonal grid has
			# countless equal-length routes, and exploring them all is
			# what made this slow.
			var f := tentative + 3 * (absi(goal.x - next.x) + absi(goal.y - next.y) + absi(goal.z - next.z))
			if not buckets.has(f):
				buckets[f] = []
			(buckets[f] as Array).append(next)
			if f < current_f:
				current_f = f
	return []


static func _rebuild(came: Dictionary, node: Vector3i, origin: Vector3) -> Array[Vector3]:
	var cells: Array[Vector3i] = [node]
	while came.has(node):
		node = came[node]
		cells.push_front(node)
	var out: Array[Vector3] = []
	for c in cells:
		out.append(origin + Vector3(c) * CELL)
	return _straighten(out)


## Drop points that lie on the straight between their neighbours.
static func _straighten(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() < 3:
		return path
	var out: Array[Vector3] = [path[0]]
	for i in range(1, path.size() - 1):
		var before := (path[i] - out[out.size() - 1]).normalized()
		var after := (path[i + 1] - path[i]).normalized()
		if before.dot(after) < 0.999:
			out.append(path[i])
	out.append(path[path.size() - 1])
	return out


## The open-ended variant for live previews: stub out of the source,
## then orthogonal to wherever the aim is.
static func routed_open(from: Vector3, from_dir: Vector3, tail: Array) -> Array[Vector3]:
	var sparse: Array = [from + from_dir * STUB]
	sparse.append_array(tail)
	var path := orthogonalize(sparse)
	path.insert(0, from)
	return path


static func orthogonalize(waypoints: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for point: Vector3 in waypoints:
		if out.is_empty():
			out.append(point)
			continue
		var a: Vector3 = out[out.size() - 1]
		for corner in _leg(a, point):
			_append(out, corner)
	return out


static func _leg(a: Vector3, b: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if b.y >= a.y:
		pts.append(Vector3(b.x, a.y, a.z))
		pts.append(Vector3(b.x, a.y, b.z))
	else:
		pts.append(Vector3(a.x, b.y, a.z))
		pts.append(Vector3(b.x, b.y, a.z))
	pts.append(b)
	return pts


static func _append(out: Array[Vector3], point: Vector3) -> void:
	if out[out.size() - 1].distance_to(point) > 0.001:
		out.append(point)
