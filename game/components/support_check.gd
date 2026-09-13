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

const SAMPLE_STEP := 0.5
const REACH := 0.65
const MAX_SPAN := 3.0
const END_GRACE := 1.0
const BRACKET_SPACING := 2.2
const SUPPORT_MASK := 1 | 4

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
	var total := 0.0
	for i in range(path.size() - 1):
		var from := path[i]
		var to := path[i + 1]
		var seg_len := from.distance_to(to)
		if seg_len < 0.001:
			continue
		var steps := maxi(1, int(ceil(seg_len / SAMPLE_STEP)))
		for s in range(steps):
			samples.append(from.lerp(to, float(s) / steps))
			arcs.append(total + seg_len * s / steps)
		total += seg_len
	if not path.is_empty():
		samples.append(path[path.size() - 1])
		arcs.append(total)

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

	return {"ok": max_span <= MAX_SPAN + 0.01, "max_span": max_span, "brackets": brackets,
		"worst_at": worst_at}


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
