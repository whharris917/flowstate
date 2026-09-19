class_name PipeRoute
## Turns a sparse waypoint list into a pipe path.
##
## Each leg between waypoints is the shortest path with vertical
## elevation changes (director, 2026-09-13: the auto-route favoured
## the world axes and looked wrong; a run should take the direct
## line, and only its risers and drops are vertical). One horizontal
## straight at whatever bearing, and one vertical, with the trade's
## convention for which comes first: a rising leg runs horizontal and
## comes up at the destination; a falling leg drops first.


const STUB := 0.35   # a run leaves its fitting straight, this far


## A full equipment-to-equipment route: leave the source fitting
## along its outward axis, approach the destination along its own,
## and take the direct line in between. Zero directions degrade to
## no stub (free endpoints).
static func routed(from: Vector3, from_dir: Vector3, to: Vector3, to_dir: Vector3,
		waypoints: Array, blocked: Callable = Callable()) -> Array[Vector3]:
	var stub_a := from + from_dir * STUB
	var stub_b := to + to_dir * STUB
	var sparse: Array = [stub_a]
	sparse.append_array(waypoints)
	sparse.append(stub_b)
	var path := lay(sparse)
	path.insert(0, from)
	path.append(to)
	return square_turns(path, blocked)


## No turn sharper than a right angle (director, 2026-09-13: "we
## should avoid acute angles"; 2026-09-18: a line arriving from behind
## a nozzle folded back through it). A corner that turns further is
## split in two: a short leg square to the way in, then the rest of
## the turn — so a line leaving a stub for a point behind it goes out,
## turns square, and turns again, and the elbows' sweeps stay clear of
## the fitting.
const SQUARE_LEG := 0.45


static func square_turns(path: Array[Vector3], blocked: Callable = Callable()) -> Array[Vector3]:
	if path.size() < 3:
		return path
	var out: Array[Vector3] = [path[0]]
	for i in range(1, path.size() - 1):
		var corner := path[i]
		var d_in := (corner - out[out.size() - 1]).normalized()
		var d_out := (path[i + 1] - corner).normalized()
		if d_in.length() < 0.5 or d_out.length() < 0.5:
			out.append(corner)
			continue
		var len_in := corner.distance_to(out[out.size() - 1])
		var len_out := corner.distance_to(path[i + 1])
		# 93 degrees or less is fine; so is a turn off a lane's short
		# sidestep, which is a jog, not a fold (a stub, 0.35 m, counts).
		if d_in.dot(d_out) >= -0.05 or minf(len_in, len_out) < 0.3:
			out.append(corner)
			continue
		# The split goes on the longer of the two legs, so a stub — the
		# short fixed leg at a fitting — stays straight: after the corner
		# when the way out is longer, before it when the way in is.
		if len_out >= len_in:
			# The way out, square to the way in; the other way if that
			# side is solid.
			var side := _square_side(d_in, d_out, corner, blocked, 1.0)
			out.append(corner)
			out.append(corner + side * SQUARE_LEG)
		else:
			# The way in, square to the way out, laid before the corner.
			var approach := _square_side(d_out, d_in, corner, blocked, -1.0)
			out.append(corner - approach * SQUARE_LEG)
			out.append(corner)
	out.append(path[path.size() - 1])
	return out


## Is a short level leg through something solid? Only when the router
## gave us its question; a plain lay has none and takes the leg as is.
static func _leg_blocked(a: Vector3, b: Vector3, blocked: Callable) -> bool:
	if not blocked.is_valid():
		return false
	for i in range(1, 4):
		if bool(blocked.call(a.lerp(b, i / 3.0), false)):
			return true
	return false


## The same route, but each leg found by search on a half-metre grid
## round whatever `blocked` says is solid (director, 2026-09-12:
## intersection avoidance for every run), then pulled straight: the
## grid walks in six directions, so its path is a staircase, and every
## stretch of it with a clear direct line collapses to one. A leg that
## cannot be found within the search budget falls back to the plain
## leg. `blocked` takes a cell centre (plant-local) and answers true
## for a cell a run must not pass through.
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
	# The open zone round the fittings is the route's two ends only, not
	# every waypoint (2026-09-18: with each leg's ends exempt, anything
	# within STUB_CLEAR of a waypoint was never checked).
	var ends: Array[Vector3] = [from, to]
	last_searched = false
	for k in range(1, sparse.size()):
		var a: Vector3 = out[out.size() - 1]
		var b: Vector3 = sparse[k]
		# The way in at the leg's start: the stub's, or the last leg's.
		var d_in := (a - out[out.size() - 2]).normalized()
		# A leg that folds back against the way in takes its square leg
		# FIRST, and is searched from its end with the way in known
		# (2026-09-19: square_turns after the search put the corner in
		# and moved the leg after it 0.45 m, back through the pump the
		# search had gone round; nothing checked the moved leg).
		var plain_dir := (_leg(a, b)[0] - a).normalized()
		if _folds(d_in, plain_dir) and a.distance_to(b) >= 0.3:
			var side := _square_side(d_in, plain_dir, a, blocked, 1.0)
			a += side * SQUARE_LEG
			_append(out, a)
			d_in = side
		var leg := _route_leg(a, b, d_in, blocked, busy, ends)
		# The arrival at the destination stub: a leg folding against it
		# gets its square leg before the stub, and is routed to that
		# corner instead, so what arrives there was checked too.
		if k == sparse.size() - 1 and to_dir.length() > 0.5 and leg.size() >= 1:
			var before_b: Vector3 = a if leg.size() < 2 else leg[leg.size() - 2]
			var arrive := (b - before_b).normalized()
			var stub_dir := (to - b).normalized()
			if _folds(arrive, stub_dir) and before_b.distance_to(b) >= 0.3:
				var approach := _square_side(stub_dir, arrive, b, blocked, -1.0)
				leg = _route_leg(a, b - approach * SQUARE_LEG, d_in, blocked, busy, ends)
				leg.append(b)
		for corner in leg:
			_append(out, corner)
	out.append(to)
	# The net under the rule: a fold the search's own fallback left
	# (a grid step against a pulled straight) is still split here.
	return _straighten(square_turns(out, blocked))


## One leg, laid plain where its plain shape is clear and searched
## round whatever it passes through otherwise; `d_in` is the way in
## at `a`, which the search and the pull-straight never fold against.
static func _route_leg(a: Vector3, b: Vector3, d_in: Vector3, blocked: Callable,
		busy: Callable, ends: Array[Vector3]) -> Array[Vector3]:
	# The plain leg first: a run laid where it was laid is the point,
	# and the search only runs where that leg passes through something.
	var plain := _leg(a, b)
	if _clear(a, plain, blocked, ends):
		return plain
	last_searched = true
	var cells := _astar(a, b, d_in, blocked, busy, ends)
	if cells.is_empty():
		return plain
	return _pull_straight(cells, b, blocked, busy, ends, d_in)


## A turn past 93 degrees: the fold the square-turn rule splits.
static func _folds(d_in: Vector3, d_out: Vector3) -> bool:
	if d_in.length() < 0.5 or d_out.length() < 0.5:
		return false
	return d_in.normalized().dot(d_out.normalized()) < -0.05


## The side a square leg takes at `corner`: the way out, square to the
## way in (any level side when the way out is straight back), turned
## round when the leg that way is solid and the other way is not.
## `sign` is which way the leg lies from the corner: +1 after it
## (corner + side), -1 before it (corner - side).
static func _square_side(d_in: Vector3, d_out: Vector3, corner: Vector3, blocked: Callable,
		sign: float) -> Vector3:
	var side := d_out - d_in * d_out.dot(d_in)
	if side.length() < 1e-3:
		side = Vector3.UP.cross(d_in)
		if side.length() < 1e-3:
			side = Vector3.RIGHT
	side = side.normalized()
	if _leg_blocked(corner, corner + side * sign * SQUARE_LEG, blocked) \
			and not _leg_blocked(corner, corner - side * sign * SQUARE_LEG, blocked):
		side = -side
	return side


## Does a polyline from `start` through `points` pass through
## something solid? Sampled every quarter metre at the run's own
## height — snapping a sample to the grid put a conduit lying on a
## tray down into the beam under it. The first and last STUB_CLEAR
## of the leg are exempt, since a stub leaves through its own
## equipment's volume; `ends` names the leg's ends when the polyline
## is only part of one.
static func _clear(start: Vector3, points: Array[Vector3], blocked: Callable,
		ends: Array[Vector3] = []) -> bool:
	var leg_a := start if ends.is_empty() else ends[0]
	var leg_b := points[points.size() - 1] if ends.is_empty() else ends[1]
	var a := start
	for b in points:
		var length := a.distance_to(b)
		var steps := maxi(1, ceili(length / 0.15))   # the oracle's own spacing: a hand valve is 0.3 m
		# `blocked` is told whether the sample is on a vertical: a run's
		# own equipment is open to a drop down its flank, not to a leg
		# through its body (2026-09-18).
		var vertical := absf(b.y - a.y) > maxf(absf(b.x - a.x), absf(b.z - a.z))
		for i in range(1, steps + 1):
			var p := a.lerp(b, float(i) / steps)
			# Near a fitting the run's own equipment is open to it (the
			# stub leaves through its volume); everything else still counts
			# (2026-09-18: the whole zone used to be unchecked, and lines
			# went through railings and neighbours beside their fittings).
			var near_end := p.distance_to(leg_a) < STUB_CLEAR or p.distance_to(leg_b) < STUB_CLEAR
			if bool(blocked.call(p, vertical or near_end)):
				last_block = p
				return false
		a = b
	return true


## A searched path pulled straight: from each corner, the farthest
## later corner (the target itself first) whose direct leg is clear
## replaces the staircase between them, so a detour becomes the few
## straights it needs and the last one ends on the target exactly.
## A straight may not lie through more of other runs' cells than the
## staircase it replaces did: the search side-stepped a neighbouring
## run at a cost, and a straight that grazes it the whole way would
## throw that away (a crossing costs both the same and stays). The
## grid's own steps are taken as passable; the search checked them.
## Returns the corners after the first cell, which is the start.
static func _pull_straight(cells: Array[Vector3], target: Vector3, blocked: Callable,
		busy: Callable, ends: Array[Vector3], d_in: Vector3 = Vector3.ZERO) -> Array[Vector3]:
	var pts: Array[Vector3] = cells.duplicate()
	if pts[pts.size() - 1].distance_to(target) > 0.001:
		pts.append(target)
	var out: Array[Vector3] = [pts[0]]
	var i := 0
	var prev_dir := d_in
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1:
			var straight := _leg(pts[i], pts[j])
			# A straight that folds against the way in is no straight:
			# the corner it would need is what the square-turn rule
			# refuses, and splitting it afterwards moves the leg.
			if not _folds(prev_dir, straight[0] - pts[i]) and _clear(pts[i], straight, blocked, ends) \
					and _busy_along(pts[i], straight, busy) <= _busy_along(pts[i], pts.slice(i + 1, j + 1), busy) + 1:
				break
			j -= 1
		var leg := _leg(pts[i], pts[j])
		for corner in leg:
			_append(out, corner)
		var before_end: Vector3 = pts[i] if leg.size() < 2 else leg[leg.size() - 2]
		prev_dir = (leg[leg.size() - 1] - before_end).normalized()
		i = j
	out.remove_at(0)
	return out


## How many quarter-metre samples of a polyline lie in cells another
## run occupies.
static func _busy_along(start: Vector3, points: Array[Vector3], busy: Callable) -> int:
	if not busy.is_valid():
		return 0
	var count := 0
	var a := start
	for b in points:
		var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
		for k in range(1, steps + 1):
			if bool(busy.call(a.lerp(b, float(k) / steps))):
				count += 1
		a = b
	return count


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


static func _astar(a: Vector3, b: Vector3, d_in: Vector3, blocked: Callable, busy: Callable,
		ends: Array[Vector3]) -> Array[Vector3]:
	var cache_key := "%.2f,%.2f,%.2f>%.2f,%.2f,%.2f|%s|%s" % [a.x, a.y, a.z, b.x, b.y, b.z, str(ends), str(d_in)]
	if _leg_cache.has(cache_key):
		return (_leg_cache[cache_key] as Array[Vector3]).duplicate()
	var t0 := Time.get_ticks_usec()
	var found := _search(a, b, d_in, blocked, busy, ends)
	search_usec += Time.get_ticks_usec() - t0
	searches += 1
	if found.is_empty():
		failures += 1
		if OS.has_environment("FLOWSTATE_ROUTE_DEBUG"):
			print("[route] search failed: %s" % cache_key)
	_leg_cache[cache_key] = found
	return found.duplicate()


## The grid is anchored at `a`: the start is a cell centre exactly, so
## the found path leaves `a` with no jog, and the goal is the cell that
## holds `b`, a quarter metre off at most, which _pull_straight takes
## up by ending its last straight on `b` itself.
static func _search(a: Vector3, b: Vector3, d_in: Vector3, blocked: Callable, busy: Callable,
		ends: Array[Vector3]) -> Array[Vector3]:
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
			# The first step never folds against the way in.
			if node == start and _folds(d_in, Vector3(step)):
				continue
			if next.x < lo.x or next.y < lo.y or next.z < lo.z or next.x > hi.x or next.y > hi.y or next.z > hi.z:
				continue
			if closed.has(next):
				continue
			var centre := a + Vector3(next) * CELL
			if next != goal and centre.y < 0.05:
				continue  # below grade
			var open_end := centre.distance_to(ends[0]) <= STUB_CLEAR or centre.distance_to(ends[1]) <= STUB_CLEAR
			if next != goal and bool(blocked.call(centre, step.y != 0 or open_end)):
				continue
			# The probe is shallow, so a vertical step also looks halfway:
			# a deck is thinner than the gap between two cells.
			if step.y != 0 and next != goal \
					and bool(blocked.call(centre - Vector3(0.0, step.y * CELL * 0.5, 0.0), true)):
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
## then the direct line to wherever the aim is.
static func routed_open(from: Vector3, from_dir: Vector3, tail: Array) -> Array[Vector3]:
	var sparse: Array = [from + from_dir * STUB]
	sparse.append_array(tail)
	var path := lay(sparse)
	path.insert(0, from)
	return square_turns(path)


## The path through a list of waypoints, each leg laid by _leg.
static func lay(waypoints: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for point: Vector3 in waypoints:
		if out.is_empty():
			out.append(point)
			continue
		var a: Vector3 = out[out.size() - 1]
		for corner in _leg(a, point):
			_append(out, corner)
	return square_turns(out)


## One leg: the direct horizontal line and a vertical, rising at the
## far end or dropping at the near one. A level leg is one straight;
## a leg straight up or down is one vertical.
static func _leg(a: Vector3, b: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var level := absf(b.y - a.y) < 0.001
	var plumb := absf(b.x - a.x) < 0.001 and absf(b.z - a.z) < 0.001
	if not level and not plumb:
		if b.y > a.y:
			pts.append(Vector3(b.x, a.y, b.z))
		else:
			pts.append(Vector3(a.x, b.y, a.z))
	pts.append(b)
	return pts


static func _append(out: Array[Vector3], point: Vector3) -> void:
	if out[out.size() - 1].distance_to(point) > 0.001:
		out.append(point)
