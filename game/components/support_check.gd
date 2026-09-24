class_name SupportCheck
## The support rule for routed runs: pipe and conduit cannot cross
## long unsupported spans. A run is sampled along its length; a sample
## counts as supported when world geometry, placed structure (layer 1),
## or equipment bulk (interact volumes, layer 4) sits within REACH of
## the run line. The longest unsupported stretch must stay under
## MAX_SPAN. The first and last END_GRACE meters are free — the nozzle
## and its stub fitting carry them.
##
## evaluate() also proposes bracket points — where clamp hardware is
## drawn — every BRACKET_SPACING meters of supported run, anchored to
## the nearest surface (down, sideways, then overhead hanger).
##
## Stands: a level stretch that would fail the rule is stood
## on pipe stands every BRACKET_SPACING wherever a floor, a slab or a
## deck (layer 1, never equipment) lies within STAND_REACH below it,
## and those samples count as supported. A run higher than a stand
## reaches still needs a rack. Stands come back in the brackets with
## "stand": true, and "stands" counts them.

const SAMPLE_STEP := 0.5
const REACH := 0.65
const MAX_SPAN := 3.0
const END_GRACE := 1.0
const BRACKET_SPACING := 2.2
const SUPPORT_MASK := 1 | 4
const STAND_REACH := 6.0
const STAND_MASK := 1

const _RAY_DIRS: Array[Vector3] = [
	Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
	Vector3.FORWARD, Vector3.BACK, Vector3.UP,
]


## path: global-space polyline (a laid route). exclude
## lists collider RIDs to ignore — a run re-validating itself must not
## count as its own support.
## Returns {"ok": bool, "max_span": float, "brackets": [{from, to}]}.
static func evaluate(path: Array[Vector3], space: PhysicsDirectSpaceState3D,
		exclude: Array[RID] = []) -> Dictionary:
	var samples: Array[Vector3] = []
	var arcs: Array[float] = []
	var level: Array[bool] = []   # the sample lies on a level leg: a stand can go under it
	var seg_of: Array[int] = []   # which leg of the path the sample is on
	var total := 0.0
	for i in range(path.size() - 1):
		var from := path[i]
		var to := path[i + 1]
		var seg_len := from.distance_to(to)
		if seg_len < 0.001:
			continue
		var is_level := absf(to.y - from.y) < 0.01
		var steps := maxi(1, int(ceil(seg_len / SAMPLE_STEP)))
		for s in range(steps):
			samples.append(from.lerp(to, float(s) / steps))
			arcs.append(total + seg_len * s / steps)
			level.append(is_level)
			seg_of.append(i)
		total += seg_len
	if not path.is_empty():
		samples.append(path[path.size() - 1])
		arcs.append(total)
		level.append(false)
		seg_of.append(path.size() - 2)

	var shape := SphereShape3D.new()
	shape.radius = REACH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = SUPPORT_MASK
	query.exclude = exclude

	var supported: Array[bool] = []
	for i in range(samples.size()):
		if arcs[i] <= END_GRACE or arcs[i] >= total - END_GRACE:
			supported.append(true)
			continue
		query.transform = Transform3D(Basis.IDENTITY, samples[i])
		supported.append(not space.intersect_shape(query, 1).is_empty())

	# Stands: a stretch that would fail is stood on the floor below it,
	# a stand every BRACKET_SPACING from where the stretch begins.
	var stands: Array[Dictionary] = []
	var i0 := 0
	while i0 < samples.size():
		if supported[i0]:
			i0 += 1
			continue
		var i1 := i0
		while i1 + 1 < samples.size() and not supported[i1 + 1]:
			i1 += 1
		var stretch_start: float = arcs[maxi(0, i0 - 1)]
		var stretch_end: float = arcs[mini(samples.size() - 1, i1 + 1)]
		if stretch_end - stretch_start > MAX_SPAN + 0.01:
			# Stands stand at fixed fractions of each level straight —
			# evenly spaced, at most BRACKET_SPACING apart — so they keep
			# their place along the pipe as it rises (spaced from the
			# start of the stretch, whose risers grow with the height,
			# they would wander). A riser before the straight or
			# after it that would overrun the span with the level beside
			# it puts one more stand at that end.
			var g0 := i0
			while g0 <= i1:
				if not level[g0]:
					g0 += 1
					continue
				var g1 := g0
				while g1 + 1 <= i1 and level[g1 + 1]:
					g1 += 1
				var seg: int = seg_of[g0]
				var seg_a: Vector3 = path[seg]
				var seg_b: Vector3 = path[seg + 1]
				var seg_len := seg_a.distance_to(seg_b)
				var count := maxi(1, ceili(seg_len / BRACKET_SPACING) - 1)
				var wanted: Array[int] = []
				for k in range(1, count + 1):
					var at := seg_a.lerp(seg_b, float(k) / (count + 1))
					# The nearest sample of this stretch to the spot.
					var best := -1
					var best_d := 0.3
					for i in range(g0, g1 + 1):
						var d := samples[i].distance_to(at)
						if d < best_d:
							best_d = d
							best = i
					if best >= 0 and not wanted.has(best):
						wanted.append(best)
				wanted.sort()
				var head: float = arcs[g0] - stretch_start
				var tail: float = stretch_end - arcs[g1]
				var first_arc: float = arcs[wanted[0]] if not wanted.is_empty() else arcs[g1]
				var last_arc: float = arcs[wanted[wanted.size() - 1]] if not wanted.is_empty() else arcs[g0]
				if head + (first_arc - arcs[g0]) > MAX_SPAN and not wanted.has(g0):
					wanted.insert(0, g0)
				if (arcs[g1] - last_arc) + tail > MAX_SPAN and not wanted.has(g1):
					wanted.append(g1)
				for i in wanted:
					var floor_hit := _floor_below(samples[i], space, exclude)
					if floor_hit == Vector3.INF:
						continue
					stands.append({"from": samples[i], "to": floor_hit, "stand": true})
					supported[i] = true
				g0 = g1 + 1
		i0 = i1 + 1

	var max_span := 0.0
	var span_start := -1.0
	var worst_at := Vector3.INF
	var span_at := Vector3.INF
	for i in range(samples.size()):
		if supported[i]:
			if span_start >= 0.0:
				if arcs[i] - span_start > max_span:
					max_span = arcs[i] - span_start
					worst_at = span_at
				span_start = -1.0
		elif span_start < 0.0:
			span_start = arcs[maxi(0, i - 1)]
			span_at = samples[i]
	if span_start >= 0.0 and total - span_start > max_span:
		max_span = total - span_start
		worst_at = span_at

	var brackets: Array[Dictionary] = []
	var last_bracket := -BRACKET_SPACING
	for i in range(samples.size()):
		if not supported[i] or arcs[i] - last_bracket < BRACKET_SPACING:
			continue
		if arcs[i] <= END_GRACE or arcs[i] >= total - END_GRACE:
			continue
		var anchor := _nearest_surface(samples[i], space, exclude)
		if anchor != Vector3.INF:
			brackets.append({"from": samples[i], "to": anchor})
			last_bracket = arcs[i]
	brackets.append_array(stands)

	return {"ok": max_span <= MAX_SPAN + 0.01, "max_span": max_span, "brackets": brackets,
		"worst_at": worst_at, "stands": stands.size()}


## The floor a stand would rest on: the first surface straight below
## within STAND_REACH, world geometry or structure only.
static func _floor_below(point: Vector3, space: PhysicsDirectSpaceState3D,
		exclude: Array[RID]) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * STAND_REACH,
		STAND_MASK)
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


static func _nearest_surface(point: Vector3, space: PhysicsDirectSpaceState3D,
		exclude: Array[RID]) -> Vector3:
	for dir in _RAY_DIRS:
		var query := PhysicsRayQueryParameters3D.create(point, point + dir * (REACH + 0.15),
			SUPPORT_MASK)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit["position"]
	return Vector3.INF
