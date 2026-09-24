class_name CableDrape
## The shape of a loose cable: out of each terminal a short straight
## through its gland, a droop to the floor, then along the floor
## through its corners, straight between them with each corner a
## rounded bend. Positions are plant-local.

const GLAND := 0.06        # the straight a cable leaves its terminal by
const BEND := 0.25         # how far either side of a corner its bend reaches


## The points the curve passes through: the terminal, the gland's end,
## where the cable touches down, its corners, where it lifts off, the
## far gland and terminal. `straight_a` and `straight_b` are how far
## each end runs straight before it may bend: a gland's length at a
## terminal, longer out of a conduit's mouth. `facing` drops each end
## out the way its
## terminal faces; without it, toward the next point. `floor_a` and
## `floor_b` are the floor's
## height under each end, NAN where it is not known: that end then
## runs level from its gland.
static func skeleton(from: Vector3, dir_a: Vector3, to: Vector3, dir_b: Vector3, corners: Array,
		floor_a: float, floor_b: float, radius: float, facing: bool = true,
		straight_a: float = GLAND, straight_b: float = GLAND) -> Array[Vector3]:
	var sa := from + dir_a * straight_a
	var sb := to + dir_b * straight_b
	var first: Vector3 = corners[0] if not corners.is_empty() else sb
	var last: Vector3 = corners[corners.size() - 1] if not corners.is_empty() else sa
	var out: Array[Vector3] = [from, sa]
	if not is_nan(floor_a):
		var down := _touchdown(sa, first, floor_a + radius, dir_a if facing else Vector3.ZERO)
		if down != sa:
			out.append(down)
	for corner: Vector3 in corners:
		out.append(corner)
	if not is_nan(floor_b):
		var up := _touchdown(sb, last, floor_b + radius, dir_b if facing else Vector3.ZERO)
		if up != sb:
			out.append(up)
	out.append(sb)
	out.append(to)
	return out


## Where a cable leaving a gland at `gland` meets the floor at height
## `y`: out by about half its drop, so it hangs in a curve rather than
## falling plumb, and never past half the way to the next point. The
## gland itself when the terminal is at the floor already.
static func _touchdown(gland: Vector3, toward: Vector3, y: float, dir: Vector3) -> Vector3:
	var drop := gland.y - y
	if drop < 0.03:
		return gland
	# Out the way the terminal faces, when it faces sideways, so the
	# cable clears the body it leaves; toward the next point when the
	# terminal faces up or down.
	var toward_next := Vector3(toward.x - gland.x, 0.0, toward.z - gland.z)
	var across := Vector3(dir.x, 0.0, dir.z)
	if across.length() < 0.3:
		across = toward_next
	var reach := clampf(drop * 0.6, 0.08, 0.6)
	if toward_next.length() > 0.01:
		reach = minf(reach, toward_next.length() * 0.45)
	if across.length() < 0.01:
		return Vector3(gland.x, y, gland.z)
	return Vector3(gland.x, y, gland.z) + across.normalized() * reach


## The drawn cable: straight between its points, each corner rounded
## by a bend of up to BEND metres either side of it (a quadratic curve
## with the corner as its control point), shorter where a leg is short.
## A bend stays inside the corner, so the cable never dips into the
## floor or loops out past a turn.
static func curve(points: Array[Vector3]) -> Array[Vector3]:
	var n := points.size()
	if n < 3:
		return points.duplicate()
	var out: Array[Vector3] = [points[0]]
	for i in range(1, n - 1):
		var before := points[i - 1]
		var corner := points[i]
		var after := points[i + 1]
		var len_in := before.distance_to(corner)
		var len_out := corner.distance_to(after)
		if len_in < 0.002 or len_out < 0.002:
			continue
		var d_in := (corner - before) / len_in
		var d_out := (after - corner) / len_out
		var turn := acos(clampf(d_in.dot(d_out), -1.0, 1.0))
		if turn < 0.02:
			continue   # straight on: no corner to round
		var reach := minf(BEND, 0.45 * minf(len_in, len_out))
		var enter := corner - d_in * reach
		var leave := corner + d_out * reach
		var steps := clampi(ceili(rad_to_deg(turn) / 10.0), 2, 12)
		for s in range(steps + 1):
			var t := float(s) / steps
			var p := enter.lerp(corner, t).lerp(corner.lerp(leave, t), t)
			if p.distance_to(out[out.size() - 1]) > 0.002:
				out.append(p)
	out.append(points[n - 1])
	return out


## A round tube along a curve: six sides, each ring turned from the one
## before by the least rotation, so the tube does not twist.
static func tube_mesh(path: Array[Vector3], radius: float) -> ArrayMesh:
	const SIDES := 6
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var n := path.size()
	if n < 2:
		return null
	var tangent := (path[1] - path[0]).normalized()
	var side := tangent.cross(Vector3.UP)
	if side.length() < 0.1:
		side = tangent.cross(Vector3.RIGHT)
	side = side.normalized()
	for i in n:
		var ahead := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		if ahead.length() > 0.5:
			# Carry the frame round the bend: remove what now lies along
			# the new tangent and keep the rest.
			side = (side - ahead * side.dot(ahead)).normalized()
			tangent = ahead
		var up := tangent.cross(side).normalized()
		for k in SIDES:
			var angle := TAU * float(k) / SIDES
			var normal := side * cos(angle) + up * sin(angle)
			verts.append(path[i] + normal * radius)
			normals.append(normal)
	for i in n - 1:
		for k in SIDES:
			var a := i * SIDES + k
			var b := i * SIDES + (k + 1) % SIDES
			var c := a + SIDES
			var d := b + SIDES
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
