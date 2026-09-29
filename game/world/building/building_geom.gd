class_name BuildingGeom
extends RefCounted
## Plan geometry for buildings: polygons in feet as PackedVector2Array,
## planes as Vector3 (a, b, c) for y = a x + b z + c.


## The plane through three points given as (x, z, y).
static func plane3(p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var n := (p1 - p0).cross(p2 - p0)
	if absf(n.z) < 1e-9:
		return Vector3(INF, INF, INF)
	return Vector3(-n.x / n.z, -n.y / n.z, p0.z + (n.x * p0.x + n.y * p0.y) / n.z)


static func ph(pl: Vector3, p: Vector2) -> float:
	return pl.x * p.x + pl.y * p.y + pl.z


## The half of the plan where plane p stands at or below plane q.
static func under(p: Vector3, q: Vector3) -> PackedVector2Array:
	var d := p - q
	var g := Vector2(d.x, d.y)
	var big := 5000.0
	if g.length_squared() < 1e-10:
		if d.z <= 0.0:
			return PackedVector2Array([Vector2(-big, -big), Vector2(big, -big), Vector2(big, big), Vector2(-big, big)])
		return PackedVector2Array()
	var n := g.normalized()
	var p0 := -g * d.z / g.length_squared()
	var t := Vector2(-n.y, n.x)
	return PackedVector2Array([p0 + t * big, p0 - t * big, p0 - t * big - n * big, p0 + t * big - n * big])


## The pieces of a set of polygons inside a region.
static func meet(pieces: Array, region: PackedVector2Array) -> Array:
	var out: Array = []
	if region.size() < 3:
		return out
	for p: PackedVector2Array in pieces:
		for q: PackedVector2Array in Geometry2D.intersect_polygons(p, region):
			if q.size() >= 3 and absf(area(q)) > 1e-4:
				out.append(q)
	return out


## The pieces of a set of polygons outside a region. A hole wholly
## inside a piece splits the piece through it, so no piece has a hole.
static func cut(pieces: Array, hole: PackedVector2Array) -> Array:
	if hole.size() < 3:
		return pieces
	var out: Array = []
	for p: PackedVector2Array in pieces:
		var res := Geometry2D.clip_polygons(p, hole)
		var holed := false
		for q: PackedVector2Array in res:
			if res.size() > 1 and Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(res[0]):
				holed = true
		if holed:
			var cx := 0.0
			for q: Vector2 in hole:
				cx += q.x / hole.size()
			for half: PackedVector2Array in [under(Vector3(1, 0, -cx), Vector3.ZERO), under(Vector3.ZERO, Vector3(1, 0, -cx))]:
				out.append_array(cut(meet([p], half), hole))
			continue
		for q: PackedVector2Array in res:
			if q.size() >= 3 and absf(area(q)) > 1e-4:
				out.append(q)
	return out


## The signed area (positive anticlockwise, x right, z up).
static func area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s / 2.0


## A polygon grown outward by d feet (mitred).
static func grow(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(p, d, Geometry2D.JOIN_MITER)
	var best := PackedVector2Array()
	for q: PackedVector2Array in res:
		if absf(area(q)) > absf(area(best)):
			best = q
	return best


## The polygon with each edge moved inward by its own distance (feet):
## inset[i] for the edge from p[i] to p[i + 1]. Corners where two edges
## meet at a mitre; parallel neighbours join square.
static func inset(p: PackedVector2Array, d: PackedFloat32Array) -> PackedVector2Array:
	var n := p.size()
	var ccw := area(p) > 0.0
	var lines: Array = []        # [point on the moved line, direction]
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		var dir := (b - a).normalized()
		var inward := Vector2(-dir.y, dir.x) if ccw else Vector2(dir.y, -dir.x)
		lines.append([a + inward * d[i], dir])
	var out := PackedVector2Array()
	for i in n:
		var l0: Array = lines[(i - 1 + n) % n]
		var l1: Array = lines[i]
		var hit: Variant = Geometry2D.line_intersects_line(l0[0], l0[1], l1[0], l1[1])
		if hit == null:
			out.append(l1[0])
		else:
			var q: Vector2 = hit
			# A spike at a very sharp corner: keep it near the corner.
			if q.distance_to(p[i]) > 4.0 * maxf(absf(d[i]), absf(d[(i - 1 + n) % n])) + 0.01:
				out.append(l1[0])
			else:
				out.append(q)
	return out


## The distance from a point to the segment a-b.
static func seg_dist(q: Vector2, a: Vector2, b: Vector2) -> float:
	return q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))


## Whether a point lies on a polygon's boundary (within tol).
static func on_boundary(q: Vector2, p: PackedVector2Array, tol: float) -> bool:
	for i in p.size():
		if seg_dist(q, p[i], p[(i + 1) % p.size()]) < tol:
			return true
	return false


## A polygon with the given points inserted where they lie on its edges,
## so edges shared with a neighbour match end to end.
static func split_at(p: PackedVector2Array, points: PackedVector2Array, tol := 0.02) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		out.append(a)
		var on: Array = []
		var ab := b - a
		var L2 := ab.length_squared()
		if L2 < 1e-8:
			continue
		for q: Vector2 in points:
			var t := (q - a).dot(ab) / L2
			if t > 1e-4 and t < 1.0 - 1e-4 and seg_dist(q, a, b) < tol:
				on.append(t)
		on.sort()
		var last := -1.0
		for t: float in on:
			if t - last > 1e-4:
				out.append(a + ab * t)
				last = t
	return out
