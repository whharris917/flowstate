class_name BuildingRoof
extends RefCounted
## A building's roof as one surface: over each plan point the highest of
## the roof bodies there, each body's own surface the lowest of its
## planes (as a hip or a gable is). So a gable dies into a hip in valleys,
## a dormer's cheeks rise where it stands over the slope, a lower roof
## runs under a higher one's eaves, with no rule for any of them. Faces
## are cut from the bodies' planes as plan polygons; `height()` answers
## the surface's height anywhere, which the walls and rooms follow.

var b: BuildingData
## The visible faces: {body (index), plane (Vector3), poly (plan)}.
var faces: Array[Dictionary] = []


func _init(data: BuildingData) -> void:
	b = data
	_faces()


static func _same(p: Vector3, q: Vector3) -> bool:
	return absf(p.x - q.x) < 1e-6 and absf(p.y - q.y) < 1e-6 and absf(p.z - q.z) < 1e-4


## The body's own surface over a plan point, or -INF outside it. With
## `walls`, only over the body's footprint (inside its walls, not under
## its overhang): what a wall rises to.
func body_height(bi: int, p: Vector2, walls := false) -> float:
	var r: Dictionary = b.roofs[bi]
	if not Geometry2D.is_point_in_polygon(p, r["footprint" if walls else "extent"] as PackedVector2Array):
		return -INF
	for h: PackedVector2Array in r["holes"]:
		if Geometry2D.is_point_in_polygon(p, h):
			return -INF
	var sectors: Array = r["sectors"]
	if not sectors.is_empty():
		for i in sectors.size():
			if Geometry2D.is_point_in_polygon(p, sectors[i] as PackedVector2Array):
				return BuildingGeom.ph((r["planes"] as Array)[i], p)
		return -INF
	var y := INF
	for pl: Vector3 in r["planes"]:
		y = minf(y, BuildingGeom.ph(pl, p))
	return y


## The heights of every roof surface drawn over a plan point, highest
## first: the roof, and under a higher roof's eave the lower roof that
## runs on beneath it.
func surfaces_at(p: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for fc: Dictionary in faces:
		if Geometry2D.is_point_in_polygon(p, fc["poly"] as PackedVector2Array):
			out.append(BuildingGeom.ph(fc["plane"] as Vector3, p))
	out.sort()
	out.reverse()
	return out


## The roof's height over a plan point (feet), or -INF where none is.
## With `walls`, the roof a wall there rises to: a higher roof's overhang
## over a lower roof does not count.
func height(p: Vector2, walls := false) -> float:
	var y := -INF
	for bi in b.roofs.size():
		y = maxf(y, body_height(bi, p, walls))
	return y


## Which body is the roof over a plan point (-1 for none).
func body_at(p: Vector2) -> int:
	var y := -INF
	var at := -1
	for bi in b.roofs.size():
		var h := body_height(bi, p)
		if h > y + 1e-6:
			y = h
			at = bi
	return at


## The body's region (extent less its holes) as pieces.
func _region(bi: int) -> Array:
	var r: Dictionary = b.roofs[bi]
	var pieces: Array = [r["extent"]]
	for h: PackedVector2Array in r["holes"]:
		pieces = BuildingGeom.cut(pieces, h)
	return pieces


## Where a body's surface is the plane `pl` (its i-th): the plane's sector
## on a pyramid, else where it is the lowest of the body's planes.
func _own(bi: int, i: int) -> Array:
	var key := bi * 1000 + i
	if _own_cache.has(key):
		return _own_cache[key]
	var out := _own_uncached(bi, i)
	_own_cache[key] = out
	return out


var _own_cache: Dictionary = {}


func _own_uncached(bi: int, i: int) -> Array:
	var r: Dictionary = b.roofs[bi]
	var planes: Array = r["planes"]
	var pl: Vector3 = planes[i]
	var pieces := _region(bi)
	var sectors: Array = r["sectors"]
	if not sectors.is_empty():
		return BuildingGeom.meet(pieces, sectors[i] as PackedVector2Array)
	for j in planes.size():
		if j == i:
			continue
		var q: Vector3 = planes[j]
		if _same(pl, q):
			if j < i:
				return []
			continue
		pieces = BuildingGeom.meet(pieces, BuildingGeom.under(pl, q))
	return pieces


## Where body ci stands higher than plane pl of body bi (ties go to the
## body listed first).
func _higher(ci: int, pl: Vector3, bi: int) -> Array:
	var r: Dictionary = b.roofs[ci]
	var planes: Array = r["planes"]
	var out: Array = []
	for k in planes.size():
		var q: Vector3 = planes[k]
		var own := _own(ci, k)
		if _same(pl, q):
			if ci < bi:
				out.append_array(own)
			continue
		out.append_array(BuildingGeom.meet(own, BuildingGeom.under(pl, q)))
	# A higher body's eaves stand over a lower roof without cutting it where
	# the lower roof is over its own footprint (a dormer's eaves over the
	# slope, the main eave over a porch roof): the lower roof runs on
	# underneath to its wall. Where the lower roof is itself only eave, the
	# higher one's eave takes over. A body's footprint (inside its walls)
	# always cuts.
	var fp: PackedVector2Array = r["footprint"]
	var kept: Array = BuildingGeom.meet(out, fp)
	var eaves: Array = BuildingGeom.cut(out, fp)
	eaves = BuildingGeom.cut(eaves, b.roofs[bi]["footprint"] as PackedVector2Array)
	kept.append_array(eaves)
	return kept


var _rooms_cache: Array = []


func _rooms() -> Array:
	if _rooms_cache.is_empty():
		for s: Dictionary in b.spaces:
			if not b.is_open(s):
				_rooms_cache.append(s["poly"])
	return _rooms_cache


func _faces() -> void:
	for bi in b.roofs.size():
		var planes: Array = b.roofs[bi]["planes"]
		for i in planes.size():
			var pl: Vector3 = planes[i]
			var pieces := _own(bi, i)
			if pieces.is_empty():
				continue
			# Less where another body stands higher.
			for ci in b.roofs.size():
				if ci == bi:
					continue
				for hp: PackedVector2Array in _higher(ci, pl, bi):
					pieces = BuildingGeom.cut(pieces, hp)
				if pieces.is_empty():
					break
			for p: PackedVector2Array in pieces:
				faces.append({"body": bi, "plane": pl, "poly": p})
