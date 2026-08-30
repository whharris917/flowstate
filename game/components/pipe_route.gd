class_name PipeRoute
## Turns a sparse waypoint list into an orthogonal pipe path.
##
## Each leg between waypoints becomes axis-aligned segments with a
## consistent trade convention: rising legs run horizontal first and
## come up at the destination; falling legs drop straight down first,
## then run horizontal — the way real pipe drops are routed.


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
