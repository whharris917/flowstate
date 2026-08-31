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
