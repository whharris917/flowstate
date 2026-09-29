class_name BuildingData
extends RefCounted
## A real building described as data (game/data/buildings/<name>.json):
## its levels, its spaces (rooms, halls, stairs, porches, balconies,
## decks, attics) as plan polygons, its openings, its roof bodies and
## chimneys, in the survey's own feet. BuildingBuilder derives the rest
## (walls, gable ends, where roofs meet, eaves, railings) from these; the
## tools in tools/building/ read the same file to lay it over the survey's
## sheets. The format is described in tools/building/model.py.
##
## Plan points are (x, z) in feet in the building's frame, heights y in
## feet over its datum; `w()` turns them into the world.

var name := ""
var raw: Dictionary = {}
var grid_x: Dictionary = {}
var grid_z: Dictionary = {}
## Levels by id: {id, floor, ceiling?}.
var levels: Dictionary = {}
## Groups by id: {id, wall (feet), material}; `rank` orders them (a wall
## between two groups belongs to the one listed first).
var groups: Dictionary = {}
var rank: Dictionary = {}
## Spaces: {id, name, level, kind, group, floor, top (feet or "roof"),
## poly (PackedVector2Array), finish?}.
var spaces: Array[Dictionary] = []
## Openings: {at (Vector2), w, sill, head, kind, shape, hood}.
var openings: Array[Dictionary] = []
## Roof bodies: {id, kind, footprint, extent, holes, planes (Array of
## Vector3: y = a x + b z + c), trim, spec}.
var roofs: Array[Dictionary] = []
var chimneys: Array[Dictionary] = []
## Wall overrides: {level, from, to (Vector2), material, thickness?}.
var walls: Array[Dictionary] = []

# The frame: the building's origin (plan feet) at the world's origin,
# its datum `first_floor_m` over the ground, x north (-world z), z east
# (+world x).
var origin := Vector2.ZERO
var datum_m := 0.0
var ft := 0.3048

const OPEN_KINDS := ["porch", "balcony", "deck"]
const NO_WALL_KINDS := ["porch", "balcony", "deck", "void"]


static func load_file(path: String) -> BuildingData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("building: cannot open %s" % path)
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		push_error("building: %s is not a building file" % path)
		return null
	var b := BuildingData.new()
	b._read(d as Dictionary)
	return b


func _read(d: Dictionary) -> void:
	raw = d
	name = str(d.get("name", ""))
	var g: Dictionary = d.get("grid", {})
	grid_x = g.get("x", {})
	grid_z = g.get("z", {})
	var wd: Dictionary = d.get("world", {})
	var o: Array = wd.get("origin", [0.0, 0.0])
	origin = Vector2(float(o[0]), float(o[1]))
	datum_m = float(wd.get("first_floor_m", 0.0))
	ft = float(wd.get("ft_to_m", 0.3048))
	for lv: Dictionary in d.get("levels", []):
		levels[str(lv["id"])] = lv
	var i := 0
	for gr: Dictionary in d.get("groups", []):
		groups[str(gr["id"])] = gr
		rank[str(gr["id"])] = i
		i += 1
	for s: Dictionary in d.get("spaces", []):
		var e := s.duplicate()
		e["poly"] = poly(s["poly"])
		if not e.has("floor"):
			e["floor"] = float(levels[str(s["level"])]["floor"])
		else:
			e["floor"] = float(e["floor"])
		e["group"] = str(s.get("group", "main"))
		spaces.append(e)
	for op: Dictionary in d.get("openings", []):
		var e := op.duplicate()
		e["at"] = point(op["at"])
		e["w"] = float(op["w"])
		e["sill"] = float(op["sill"])
		e["head"] = float(op["head"])
		e["kind"] = str(op.get("kind", "win"))
		e["shape"] = str(op.get("shape", "flat"))
		e["hood"] = bool(op.get("hood", true))
		e["id"] = openings.size()
		openings.append(e)
	for r: Dictionary in d.get("roofs", []):
		roofs.append(_roof(r))
	for c: Dictionary in d.get("chimneys", []):
		chimneys.append(c)
	for wl: Dictionary in d.get("walls", []):
		var e := wl.duplicate()
		e["from"] = point(wl["from"])
		e["to"] = point(wl["to"])
		walls.append(e)


# ---- coordinates -------------------------------------------------------------

func gx(v: Variant) -> float:
	return float(grid_x[v]) if v is String else float(v)


func gz(v: Variant) -> float:
	return float(grid_z[v]) if v is String else float(v)


func point(spec: Variant) -> Vector2:
	if spec is Dictionary and (spec as Dictionary).has("arc_pt"):
		var a: Array = spec["arc_pt"]
		var ang := deg_to_rad(float(a[3]))
		return Vector2(gx(a[0]), gz(a[1])) + Vector2(cos(ang), sin(ang)) * float(a[2])
	var p: Array = spec
	return Vector2(gx(p[0]), gz(p[1]))


## A polygon from its data: points, arcs ({"arc": [cx, cz, r, a0, a1, n]},
## {"arc_at": [cx, cz, r, [a...]]}) or a {"rect": [x0, z0, x1, z1]}.
func poly(spec: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if spec is Dictionary and (spec as Dictionary).has("rect"):
		var r: Array = spec["rect"]
		var x0 := gx(r[0])
		var z0 := gz(r[1])
		var x1 := gx(r[2])
		var z1 := gz(r[3])
		return PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	for item: Variant in spec:
		if item is Dictionary and (item as Dictionary).has("arc"):
			var a: Array = item["arc"]
			var c := Vector2(gx(a[0]), gz(a[1]))
			var n := int(a[5])
			for i in n + 1:
				var ang := deg_to_rad(lerpf(float(a[3]), float(a[4]), float(i) / n))
				out.append(c + Vector2(cos(ang), sin(ang)) * float(a[2]))
		elif item is Dictionary and (item as Dictionary).has("arc_at"):
			var a: Array = item["arc_at"]
			var c := Vector2(gx(a[0]), gz(a[1]))
			for deg: Variant in a[3]:
				var ang := deg_to_rad(float(deg))
				out.append(c + Vector2(cos(ang), sin(ang)) * float(a[2]))
		else:
			out.append(point(item))
	# Drop repeated points and a closing repeat.
	var clean := PackedVector2Array()
	for p: Vector2 in out:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 1e-4:
			clean.append(p)
	if clean.size() > 2 and clean[0].distance_to(clean[clean.size() - 1]) < 1e-4:
		clean.remove_at(clean.size() - 1)
	return clean


## The world point of a plan point (feet) at height y feet over the datum.
func w(p: Vector2, y := 0.0) -> Vector3:
	return Vector3((p.y - origin.y) * ft, datum_m + y * ft, -(p.x - origin.x) * ft)


func wy(y: float) -> float:
	return datum_m + y * ft


## A plan point from a world point.
func plan_of(v: Vector3) -> Vector2:
	return Vector2(origin.x - v.z / ft, origin.y + v.x / ft)


# ---- roofs -------------------------------------------------------------------

func _roof(r: Dictionary) -> Dictionary:
	# A roof over a space may take the space's outline ({"space": id}).
	var fps: Variant = r["footprint"]
	var fp := PackedVector2Array()
	if fps is Dictionary and (fps as Dictionary).has("space"):
		for s: Dictionary in spaces:
			if str(s["id"]) == str(fps["space"]):
				fp = s["poly"]
	else:
		fp = poly(fps)
	var over: Variant = r.get("overhang", 0.0)
	var ext: PackedVector2Array
	if over is Array:
		var o: Array = over
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q: Vector2 in fp:
			lo = lo.min(q)
			hi = hi.max(q)
		ext = PackedVector2Array([Vector2(lo.x - float(o[0]), lo.y - float(o[2])), Vector2(hi.x + float(o[1]), lo.y - float(o[2])),
			Vector2(hi.x + float(o[1]), hi.y + float(o[3])), Vector2(lo.x - float(o[0]), hi.y + float(o[3]))])
	elif absf(float(over)) > 1e-6:
		ext = BuildingGeom.grow(fp, float(over))
	else:
		ext = fp
	var holes: Array = []
	for hs: Variant in r.get("holes", []):
		if hs is Dictionary and (hs as Dictionary).has("space"):
			for sp: Dictionary in spaces:
				if str(sp["id"]) == str(hs["space"]):
					holes.append(sp["poly"])
		else:
			holes.append(poly(hs))
	# A roof that stops at a level's rooms: a porch roof runs up to the
	# house's wall and no further.
	if r.has("clear_rooms"):
		for s: Dictionary in spaces:
			if str(s["level"]) == str(r["clear_rooms"]) and not OPEN_KINDS.has(str(s["kind"])):
				holes.append(s["poly"])
	var planes := _planes(r, fp, ext)
	# A pyramid or cone: each plane owns its sector, the triangle from its
	# eave edge to the apex, whatever the footprint's shape.
	var sectors: Array = []
	if str(r["kind"]) == "pyramid":
		planes.clear()
		var ap: Array = r["apex"]
		var apex := Vector2(gx(ap[0]), gz(ap[1]))
		for i in ext.size():
			var a := ext[i]
			var bb := ext[(i + 1) % ext.size()]
			var pl := BuildingGeom.plane3(Vector3(a.x, a.y, float(r["eave"])), Vector3(bb.x, bb.y, float(r["eave"])),
				Vector3(apex.x, apex.y, float(r["peak"])))
			if is_finite(pl.x) and is_finite(pl.y) and absf(pl.x) < 1e4 and absf(pl.y) < 1e4:
				planes.append(pl)
				sectors.append(PackedVector2Array([a, bb, apex]))
	return {"id": str(r["id"]), "kind": str(r["kind"]), "footprint": fp, "extent": ext, "holes": holes,
		"planes": planes, "sectors": sectors, "trim": str(r.get("trim", "eave")), "spec": r}


func _planes(r: Dictionary, fp: PackedVector2Array, ext: PackedVector2Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var kind := str(r["kind"])
	if kind == "planes":
		for p: Array in r["planes"]:
			out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		return out
	if kind == "flat":
		out.append(Vector3(0, 0, float(r["y"])))
		return out
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for q: Vector2 in fp:
		lo = lo.min(q)
		hi = hi.max(q)
	if kind == "hip":
		var e := float(r["eave"])
		var s: Variant = r["pitch"]
		var sp: Array = [s, s, s, s] if not s is Array else s
		out.append(Vector3(float(sp[0]), 0, e - float(sp[0]) * lo.x))
		out.append(Vector3(-float(sp[1]), 0, e + float(sp[1]) * hi.x))
		out.append(Vector3(0, float(sp[2]), e - float(sp[2]) * lo.y))
		out.append(Vector3(0, -float(sp[3]), e + float(sp[3]) * hi.y))
		if r.has("top"):
			out.append(Vector3(0, 0, float(r["top"])))
		return out
	if kind == "gable":
		var e := float(r["eave"])
		var pk := float(r["peak"])
		if str(r["axis"]) == "x":
			var zc := (lo.y + hi.y) / 2.0
			var s := (pk - e) / ((hi.y - lo.y) / 2.0)
			out.append(Vector3(0, s, pk - s * zc))
			out.append(Vector3(0, -s, pk + s * zc))
		else:
			var xc := (lo.x + hi.x) / 2.0
			var s := (pk - e) / ((hi.x - lo.x) / 2.0)
			out.append(Vector3(s, 0, pk - s * xc))
			out.append(Vector3(-s, 0, pk + s * xc))
		return out
	if kind == "pyramid":
		var ap: Array = r["apex"]
		var apex := Vector2(gx(ap[0]), gz(ap[1]))
		var e := float(r["eave"])
		var pk := float(r["peak"])
		for i in ext.size():
			var a := ext[i]
			var b := ext[(i + 1) % ext.size()]
			var pl := BuildingGeom.plane3(Vector3(a.x, a.y, e), Vector3(b.x, b.y, e), Vector3(apex.x, apex.y, pk))
			if is_finite(pl.x) and is_finite(pl.y) and absf(pl.x) < 1e4 and absf(pl.y) < 1e4:
				out.append(pl)
		return out
	push_warning("building: unknown roof kind %s" % kind)
	return out


func spaces_on(level: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in spaces:
		if str(s["level"]) == level:
			out.append(s)
	return out


func is_open(s: Dictionary) -> bool:
	return OPEN_KINDS.has(str(s["kind"]))


## The levels in order of their floors.
func level_order() -> Array[String]:
	var ids: Array[String] = []
	for k: String in levels:
		ids.append(k)
	ids.sort_custom(func(a: String, b: String) -> bool: return float(levels[a]["floor"]) < float(levels[b]["floor"]))
	return ids
