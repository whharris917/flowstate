class_name BuildingBuilder
extends Node3D
## Builds a real building from its data (BuildingData): nothing in here
## knows which building it is. From the spaces on each level it derives
## the walls: an outer wall wherever an enclosed space meets the outside or
## an open porch or deck, a partition between two rooms, a wall between
## two parts of the building (the main block and a wing) belonging to the
## part listed first. Each wall rises from its floor to whatever is over
## it: the next floor where a space stands above, otherwise the roof, so a
## gable's end, a dormer's face or a wall under a lean-to is only a wall
## under a roof. The roof is BuildingRoof's surface: slate faces, tin
## where flat, a fascia along each eave, a bargeboard up each rake and a
## brick wall where one body stands above another's edge. Floors, railings
## on the open edges of porches and decks, posts under their roofs,
## chimneys, and the rooms' finishes, which follow the roof down where it
## is lower than the ceiling.
##
## A style (a Dictionary of colours and optional Callables) dresses it:
## "dress": func(f: Transform3D, o: Dictionary, wall: Dictionary) for an
## opening's joinery; "bands": func(f, length, y0, y1, openings) over an
## outer face of brick; "ground_at": func(p: Vector2) -> float for the
## grade; "on_kit": func(k: CourthouseKit) once the kit exists;
## "extra_meshes": TownMeshes the style draws into, committed with the rest.

const SLAB := 1.0            # a floor's thickness, feet
const PART := 0.5            # a partition's thickness
const RAIL_H := 3.0

var d: BuildingData
var roof: BuildingRoof
var k: CourthouseKit
var style: Dictionary = {}
## Every wall built: {a, b (plan, on its line), inward (plan unit), thick
## (feet), y0, level, space, other, kind ("outer", "part", "group"),
## material}. The checks read these.
var walls: Array[Dictionary] = []
## Every railing: [from, to] (world, at the foot).
var rails: Array = []
## The rooms' finishes as built: {space, poly (inner faces), y0, top}.
var rooms: Array[Dictionary] = []
var stats: Dictionary = {}
var materials: Dictionary = {}
var inner_mesh: TownMesh
var _edges: Dictionary = {}          # space id -> [{a, b, other}]
## What each drawn triangle belongs to ("wall library", "roof main",
## "dress 12"...), by TownMesh.current_tag; and every opening as built
## (world centre, outward normal, width, sill, head, kind, whether on an
## outer wall), for tools/building/validity.py.
var tag_names: Array[String] = ["untagged"]
var built_openings: Array[Dictionary] = []


func _tag(label: String) -> void:
	tag_names.append(label)
	TownMesh.current_tag = tag_names.size() - 1


var _debug_on := OS.get_environment("FLOWSTATE_BLD_DEBUG") != ""
var _by_id: Dictionary = {}


func setup(data: BuildingData, st: Dictionary = {}) -> void:
	d = data
	style = st
	name = "Building_" + d.name


func col(key: String, fallback: Color) -> Color:
	return style.get(key, fallback)


func c(color: Color, kind: int) -> Color:
	return CourthouseKit.kc(color, kind)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	if style.has("on_kit"):
		(style["on_kit"] as Callable).call(k)
	inner_mesh = TownMesh.new()
	for s: Dictionary in d.spaces:
		_by_id[str(s["id"])] = s
	roof = BuildingRoof.new(d)
	_prepare_edges()
	# FLOWSTATE_BLD_SKIP=walls,floors,roof,trim,chimneys,open,rooms leaves
	# parts out, to find what drew something.
	var skip := OS.get_environment("FLOWSTATE_BLD_SKIP").split(",")
	if not skip.has("walls"):
		_walls()
	if not skip.has("floors"):
		_floors()
	if not skip.has("roof"):
		_roof_faces()
	if not skip.has("trim"):
		_roof_trim()
		_cheeks()
		_brackets()
		_gable_ends()
	if not skip.has("chimneys"):
		_chimneys()
	if not skip.has("open"):
		_open_edges()
	if not skip.has("rooms"):
		_rooms()
	_materials()
	var drawn: Array = k.m.commit(self, materials, ["wall", "iron"]).values()
	for mi: MeshInstance3D in inner_mesh.commit(self, materials, []).values():
		mi.visibility_range_end = 120.0
		drawn.append(mi)
	for tm: TownMesh in style.get("extra_meshes", []):
		var node := Node3D.new()
		add_child(node)
		drawn.append_array(tm.commit(node, materials, ["wall"]).values())
	for mi: MeshInstance3D in drawn:
		if mi.name.ends_with("glass"):
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_self_check()
	TownMesh.current_tag = 0
	if OS.get_environment("FLOWSTATE_BLD_EXPORT") != "":
		export_geometry("user://bld_%s" % d.name)
	if OS.get_environment("FLOWSTATE_BLD_DEBUG") != "":
		_debug(OS.get_environment("FLOWSTATE_BLD_DEBUG"))
	stats = {"triangles": k.m.triangles + inner_mesh.triangles, "walls": walls.size(), "faces": roof.faces.size(),
		"solids": k.solid_count, "ms": Time.get_ticks_msec() - t0}


func _materials() -> void:
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.50, 0.56, 0.58, 0.18)
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var iron := StandardMaterial3D.new()
	iron.vertex_color_use_as_albedo = true
	iron.vertex_color_is_srgb = true
	iron.metallic = 0.5
	iron.roughness = 0.45
	materials = {"wall": wall_mat, "glass": glass, "iron": iron}
	for key: String in style.get("materials", {}):
		materials[key] = style["materials"][key]


# ---- spaces' edges ------------------------------------------------------------

## Each space's polygon split wherever another space's corner on its level
## lies on it, so shared edges match end to end; each edge then learns
## what is across it.
func _prepare_edges() -> void:
	for level: String in d.level_order():
		var here := d.spaces_on(level)
		var corners := PackedVector2Array()
		for s: Dictionary in here:
			corners.append_array(s["poly"] as PackedVector2Array)
		for s: Dictionary in here:
			var p := BuildingGeom.split_at(s["poly"] as PackedVector2Array, corners)
			s["poly"] = p
			var ccw := BuildingGeom.area(p) > 0.0
			var edges: Array = []
			for i in p.size():
				var a := p[i]
				var b := p[(i + 1) % p.size()]
				if a.distance_to(b) < 0.05:
					continue
				var dir := (b - a).normalized()
				var inward := Vector2(-dir.y, dir.x) if ccw else Vector2(dir.y, -dir.x)
				var probe := (a + b) / 2.0 - inward * 0.3
				var other: Dictionary = {}
				for o: Dictionary in here:
					if o != s and float(o["floor"]) < float(s["floor"]) + 4.0 and float(o["floor"]) > float(s["floor"]) - 4.0 \
							and Geometry2D.is_point_in_polygon(probe, o["poly"] as PackedVector2Array):
						other = o
						break
				edges.append({"a": a, "b": b, "inward": inward, "other": other})
			_edges[str(s["id"])] = edges


## The floor of the lowest space above level `level` over a plan point,
## or INF when nothing stands over it.
func _above(level: String, p: Vector2) -> float:
	var fl := float(d.levels[level]["floor"])
	var best := INF
	for s: Dictionary in d.spaces:
		var f := float(s["floor"])
		if f > fl + 1.5 and f < best and Geometry2D.is_point_in_polygon(p, s["poly"] as PackedVector2Array):
			best = f
	return best


## Whether an enclosed space stands under a plan point on a lower level.
func _below(level: String, p: Vector2) -> bool:
	var fl := float(d.levels[level]["floor"])
	for s: Dictionary in d.spaces:
		if float(s["floor"]) < fl - 1.5 and not d.is_open(s) and Geometry2D.is_point_in_polygon(p, s["poly"] as PackedVector2Array):
			return true
	return false


func ground_at(p: Vector2) -> float:
	if style.has("ground_at"):
		return (style["ground_at"] as Callable).call(p)
	return -2.0


## Where a space's walls stop over a plan point: the floor of the space
## directly over it (within 3 ft of its own top), else the roof over it,
## else its own top. With `finish`, where its finish stops: its ceiling,
## or the roof's underside where that comes lower.
func _top_at(s: Dictionary, p: Vector2, finish := false) -> float:
	var fl := float(s["floor"])
	var top: Variant = s.get("top", "roof")
	var own := float(top) if not top is String else INF
	var over := _above(str(s["level"]), p)
	if own < INF and over > own + 3.0:
		over = INF
	var r := roof.height(p, true)
	# A roof over the space, even where it comes down to the floor at the
	# eaves; a porch roof well below the floor is not its roof.
	var roofed := r > fl - 3.0
	if roofed:
		r = maxf(r, fl)
	if finish:
		var t := own
		if roofed:
			t = minf(t, r - 0.35)
		if over < INF:
			t = minf(t, over - SLAB)
		if t == INF:
			t = fl + 10.0
		return t
	var t := over
	if roofed and r < t:
		t = r
	if t == INF:
		# Nothing over it: its own top, or, open to a roof that is not
		# there, no wall at all (check.py lists the space).
		t = own if own < INF else fl
	return t


# ---- walls ----------------------------------------------------------------------

func _walls() -> void:
	var order: Array = []
	for s: Dictionary in d.spaces:
		order.append(s)
	for si in order.size():
		var s: Dictionary = order[si]
		if d.is_open(s) or str(s["kind"]) == "void":
			continue
		var g: Dictionary = d.groups.get(str(s["group"]), {"wall": 1.0, "material": "brick"})
		for e: Dictionary in _edges[str(s["id"])]:
			var o: Dictionary = e["other"]
			var kind := "outer"
			var thick := float(g.get("wall", 1.0))
			if not o.is_empty() and not d.is_open(o) and str(o["kind"]) != "void":
				if str(o["group"]) == str(s["group"]):
					# A partition, built once from the space listed first.
					if order.find(o) < si:
						continue
					kind = "part"
					thick = PART
				elif int(d.rank.get(str(o["group"]), 99)) < int(d.rank.get(str(s["group"]), 99)):
					continue
				else:
					kind = "group"
			_wall(s, e, kind, thick, str(g.get("material", "brick")))


func _override(level: String, a: Vector2, b: Vector2) -> Dictionary:
	for ov: Dictionary in d.walls:
		if str(ov.get("level", level)) != level:
			continue
		var fa: Vector2 = ov["from"]
		var fb: Vector2 = ov["to"]
		var m := (a + b) / 2.0
		if BuildingGeom.seg_dist(m, fa, fb) < 0.3 and BuildingGeom.seg_dist(a, fa, fb) < 0.3 + a.distance_to(b):
			return ov
	return {}


func _wall(s: Dictionary, e: Dictionary, kind: String, thick: float, material: String) -> void:
	var a: Vector2 = e["a"]
	var b: Vector2 = e["b"]
	var inward: Vector2 = e["inward"]
	var level := str(s["level"])
	var ov := _override(level, a, b)
	if not ov.is_empty():
		material = str(ov.get("material", material))
		thick = float(ov.get("thickness", thick))
	var fl := float(s["floor"])
	# The wall stands from its floor (from the ground where nothing is
	# under it) to what is over it, sampled along it just inside.
	var mid := (a + b) / 2.0 + inward * 0.4
	var y0 := fl
	if kind != "part" and not _below(level, mid):
		y0 = minf(ground_at(mid) - 0.8, fl - SLAB)
	var o: Dictionary = e["other"]
	var n := maxi(1, int(ceil(a.distance_to(b) / 1.0)))
	var tops := PackedFloat32Array()
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		var t := _top_at(s, q + inward * 0.5)
		if kind == "part" and not o.is_empty():
			t = minf(t, _top_at(o, q - inward * 0.5))
			# A partition ends at its rooms' ceiling (the floor over it), not
			# in the attic above.
			for sp: Dictionary in [s, o]:
				var tp: Variant = sp.get("top", "roof")
				if not tp is String:
					t = minf(t, float(tp) + SLAB)
		tops.append(t)
	_tag("wall %s %s" % [kind, str(s["id"])])
	walls.append({"a": a, "b": b, "inward": inward, "thick": thick, "y0": y0, "tops": tops, "level": level,
		"space": str(s["id"]), "other": str(o.get("id", "")), "kind": kind, "material": material})
	_build_wall(walls[walls.size() - 1])


## A wall piece's frame: its face on the side facing away from `inward`
## for an outer wall (the outer face on a-b), centred on a-b for a
## partition.
func _frame(wl: Dictionary) -> Array:
	var a: Vector2 = wl["a"]
	var b: Vector2 = wl["b"]
	var inward: Vector2 = wl["inward"]
	var wa := _w2(a)
	var wb := _w2(b)
	var wi := _w2(a + inward) - wa
	var dir := (wb - wa)
	var length := dir.length()
	dir /= length
	var n := -Vector2(wi.x, wi.y).normalized()        # outward, world
	var n3 := Vector3(n.x, 0, n.y)
	var x3 := Vector3.UP.cross(n3)
	var o := wa if x3.dot(Vector3(dir.x, 0, dir.y)) > 0.0 else wb
	var origin := Vector3(o.x, 0, o.y)
	if str(wl["kind"]) == "part":
		origin += n3 * float(wl["thick"]) * d.ft / 2.0
	return [Transform3D(Basis(x3, Vector3.UP, n3), origin), length, o == wa]


func _w2(p: Vector2) -> Vector2:
	var v := d.w(p)
	return Vector2(v.x, v.z)


## The openings on a wall, in its frame's terms.
func _ops_on(wl: Dictionary, f: Transform3D, length: float, y0: float, y1: float) -> Array:
	var out: Array = []
	var a: Vector2 = wl["a"]
	var b: Vector2 = wl["b"]
	var tol := maxf(0.8, float(wl["thick"]) + 0.3)
	for op: Dictionary in d.openings:
		var at: Vector2 = op["at"]
		if BuildingGeom.seg_dist(at, a, b) > tol:
			continue
		if float(op["sill"]) >= y1 or float(op["head"]) <= y0:
			continue
		var q := d.w(at)
		var rel := Vector3(q.x, 0, q.z) - f.origin
		var u := rel.dot(f.basis.x)
		var wd := float(op["w"]) * d.ft
		if u < wd / 2.0 - 0.05 or u > length - wd / 2.0 + 0.05:
			continue
		var shape := str(op["shape"])
		var head := d.wy(float(op["head"]))
		var spring := head - wd / 2.0 if shape == "round" else (head - 0.25 if shape == "segment" else head)
		var sill := d.wy(float(op["sill"]))
		if str(op["kind"]) != "win":
			sill -= 0.03
		var ko := CourthouseKit.opening(u, wd, sill, spring, shape, 0.25)
		ko["kind"] = op["kind"]
		ko["hood"] = op["hood"]
		ko["id"] = op["id"]
		out.append(ko)
	return out


func _wall_color(material: String) -> Color:
	match material:
		"timber":
			return c(col("nogging", Color(0.64, 0.32, 0.22)), CourthouseKit.K_BRICK)
		"glass":
			return c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
		"plaster":
			return c(col("plaster", Color(0.84, 0.79, 0.68)), CourthouseKit.K_PLASTER)
		"clapboard":
			return c(col("clapboard", Color(0.52, 0.34, 0.22)), HarborTown.K_CLAP)
	return c(col("brick", Color(0.60, 0.26, 0.17)), CourthouseKit.K_BRICK)


func _build_wall(wl: Dictionary) -> void:
	var fr := _frame(wl)
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var forward: bool = fr[2]
	var tops: PackedFloat32Array = wl["tops"]
	var y0 := float(wl["y0"])
	var t := float(wl["thick"]) * d.ft
	var colr := _wall_color(str(wl["material"])) if str(wl["kind"]) != "part" else c(col("plaster", Color(0.84, 0.79, 0.68)), CourthouseKit.K_PLASTER)
	var hi := -INF
	var lo := INF
	for v: float in tops:
		hi = maxf(hi, v)
		lo = minf(lo, v)
	var mine := _ops_on(wl, f, length, y0, hi)
	var n := tops.size() - 1
	# Level along its length: one piece. Otherwise in strips whose tops
	# follow the roof (each no higher than the roof at either end).
	var key := "wall"
	if absf(hi - lo) < 0.05:
		if lo > y0 + 0.05:
			k.wall(key, f, 0.0, length, d.wy(y0), d.wy(lo), t, colr, mine, 1000.0)
	else:
		var strips := maxi(n, int(length / 0.25))
		for i in strips:
			var u0 := length * i / strips
			var u1 := length * (i + 1) / strips
			var ta := _sample(tops, (u0 / length) if forward else 1.0 - u0 / length)
			var tb := _sample(tops, (u1 / length) if forward else 1.0 - u1 / length)
			var top := minf(ta, tb)
			if top > y0 + 0.05:
				k.wall(key, f, u0, u1, d.wy(y0), d.wy(top), t, colr, mine, 1000.0)
	# The style's bands on an outer face of brick, up to its lowest top.
	if style.has("bands") and str(wl["kind"]) != "part" and str(wl["material"]) == "brick" and lo > y0 + 0.5:
		(style["bands"] as Callable).call(f, length, y0, lo, mine)
	for o: Dictionary in mine:
		_dress(f, o, wl)


func _sample(arr: PackedFloat32Array, t: float) -> float:
	var x := clampf(t, 0.0, 1.0) * (arr.size() - 1)
	var i := int(floor(x))
	if i >= arr.size() - 1:
		return arr[arr.size() - 1]
	return lerpf(arr[i], arr[i + 1], x - i)


## An opening's joinery: the style's, or a plain sash, door or nothing.
func _dress(f: Transform3D, o: Dictionary, wl: Dictionary) -> void:
	var before := TownMesh.current_tag
	_tag("dress %d" % int(o.get("id", -1)))
	built_openings.append({"c": f * Vector3(float(o["u"]), 0, 0), "n": (f.basis.z).normalized(), "along": f.basis.x.normalized(),
		"w": float(o["w"]), "y0": float(o["y0"]), "ys": float(o["ys"]), "yt": float(o["yt"]), "kind": str(o["kind"]),
		"id": int(o.get("id", -1)), "outer": str(wl["kind"]) != "part", "wall": str(wl.get("space", ""))})
	_dress_inner(f, o, wl)
	TownMesh.current_tag = before


func _dress_inner(f: Transform3D, o: Dictionary, wl: Dictionary) -> void:
	if style.has("dress"):
		(style["dress"] as Callable).call(f, o, wl)
		return
	var trim := c(col("sash", Color(0.22, 0.10, 0.07)), CourthouseKit.K_PAINT)
	var kind := str(o["kind"])
	var depth := -0.12
	if kind == "win":
		k.sash(f, o, depth, trim)
	elif kind == "door" or kind == "shut" or kind == "ishut":
		var hgt := float(o["ys"]) - float(o["y0"])
		k.door_leaf(f, Vector3(float(o["u"]), float(o["y0"]), depth), float(o["w"]) - 0.04, hgt, c(col("door", Color(0.30, 0.17, 0.09)), CourthouseKit.K_WOOD))
	elif kind == "french":
		k.sash(f, o, depth, trim)


# ---- floors ---------------------------------------------------------------------

func _floors() -> void:
	var oak := c(col("floor", Color(0.52, 0.34, 0.18)), CourthouseKit.K_OAK)
	var plank := c(col("deck", Color(0.36, 0.34, 0.31)), HarborTown.K_PLANK)
	var ceil := c(col("ceiling", Color(0.86, 0.82, 0.72)), CourthouseKit.K_PLASTER)
	var paint := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	for s: Dictionary in d.spaces:
		if str(s["kind"]) == "void":
			continue
		var open := d.is_open(s)
		var p: PackedVector2Array = s["poly"]
		var pts: Array = []
		for q: Vector2 in p:
			pts.append(q)
		var fl := float(s["floor"])
		_tag("floor %s" % str(s["id"]))
		var thick := SLAB if _below(str(s["level"]), _centre(p)) or fl > 2.0 else fl - ground_at(_centre(p)) + 0.5
		# A porch's boards on joists, its skirt of lattice under them.
		if open:
			thick = 0.5
		_floor_poly(pts, fl, plank if open else oak, paint if open else ceil, maxf(thick, 0.3), k.m if open else inner_mesh, open)


func _centre(p: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for q: Vector2 in p:
		s += q
	return s / maxf(p.size(), 1)


## A floor over a polygon at y feet: its top, its underside `thick` feet
## lower and, with `edges`, its edges; solid to the player.
func _floor_poly(pts: Array, y: float, top: Color, under: Color, thick: float, mesh: TownMesh, edges := true) -> void:
	var poly := PackedVector2Array()
	for q: Vector2 in pts:
		poly.append(q)
	var idx := Geometry2D.triangulate_polygon(poly)
	var yt := d.wy(y)
	var yb := d.wy(y - thick)
	for i in range(0, idx.size(), 3):
		var a := d.w(poly[idx[i]], y)
		var b := d.w(poly[idx[i + 1]], y)
		var cc := d.w(poly[idx[i + 2]], y)
		mesh.tri("wall", a, b, cc, Vector3.UP, top)
		mesh.tri("wall", Vector3(a.x, yb, a.z), Vector3(b.x, yb, b.z), Vector3(cc.x, yb, cc.z), Vector3.DOWN, under)
	# Its edges where no wall stands on them (a deck's, a porch's).
	for i in poly.size() if edges else 0:
		var a := d.w(poly[i], y)
		var b := d.w(poly[(i + 1) % poly.size()], y)
		var n := (b - a).cross(Vector3.UP).normalized()
		if BuildingGeom.area(poly) < 0.0:
			n = -n
		mesh.quad("wall", a, b, Vector3(b.x, yb, b.z), Vector3(a.x, yb, a.z), -n, under)
	# Solid: a thin box per triangle's bounds would overlap; the kit's
	# solid boxes follow the polygon's triangles.
	for i in range(0, idx.size(), 3):
		var q0 := poly[idx[i]]
		var q1 := poly[idx[i + 1]]
		var q2 := poly[idx[i + 2]]
		_solid_tri(q0, q1, q2, y)


func _solid_tri(q0: Vector2, q1: Vector2, q2: Vector2, y: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for q: Vector2 in [q0, q1, q2]:
		pts.append(d.w(q, y))
		pts.append(d.w(q, y - 0.3))
	hull.points = pts
	shape.shape = hull
	body.add_child(shape)
	k.solids.add_child(body)
	k.solid_count += 1


# ---- the roof -------------------------------------------------------------------

## Where a roof's underside is a room's ceiling: over the enclosed spaces,
## less the porches, decks and balconies (a deck over a room has the
## deck's roof over it).
func _footprints() -> Array:
	var out: Array = []
	for s: Dictionary in d.spaces:
		if not d.is_open(s):
			out.append(s["poly"])
	for s: Dictionary in d.spaces:
		if d.is_open(s):
			out = BuildingGeom.cut(out, s["poly"] as PackedVector2Array)
	return out


func _roof_faces() -> void:
	var courses: Array = style.get("slate_courses", [Color(0.34, 0.37, 0.43)])
	var ceil := c(col("ceiling", Color(0.86, 0.82, 0.72)), CourthouseKit.K_PLASTER)
	var soffit := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	var inside := _footprints()
	for fc: Dictionary in roof.faces:
		_tag("roof %s" % str(d.roofs[int(fc["body"])]["id"]))
		var pl: Vector3 = fc["plane"]
		var poly: PackedVector2Array = fc["poly"]
		var cover := str((d.roofs[int(fc["body"])]["spec"] as Dictionary).get("cover", ""))
		var flat := Vector2(pl.x, pl.y).length() < 0.12 or cover == "tin"
		var world := func(p: Vector2) -> Vector3: return d.w(p, BuildingGeom.ph(pl, p))
		# The plane's slope in the world's axes: plan z is world x, plan x
		# is world -z, feet and metres alike on both.
		var n := Vector3(-pl.y, 1.0, pl.x).normalized()
		# The top: slate in courses of colour by height, or the flat's tin.
		var bands: Array = []
		if flat:
			var tin_col: Color = col("tin", Color(0.30, 0.30, 0.31))
			if cover == "tin":
				tin_col = col("tin_roof", tin_col)
			bands.append([poly, c(tin_col, CourthouseKit.K_PAINT)])
		else:
			var y0 := 1e9
			var y1 := -1e9
			for p: Vector2 in poly:
				y0 = minf(y0, BuildingGeom.ph(pl, p))
				y1 = maxf(y1, BuildingGeom.ph(pl, p))
			var step := 1.6
			for kk in range(int(floor(y0 / step)), int(floor(y1 / step)) + 1):
				var strip := BuildingGeom.meet([poly], BuildingGeom.under(pl, Vector3(0, 0, (kk + 1) * step)))
				strip = BuildingGeom.meet(strip, BuildingGeom.under(Vector3(0, 0, kk * step), pl))
				for sp: PackedVector2Array in strip:
					bands.append([sp, c(courses[posmod(kk, courses.size())] as Color, CourthouseKit.K_SLATE)])
		for band: Array in bands:
			var q := band[0] as PackedVector2Array
			var idx := Geometry2D.triangulate_polygon(q)
			for i in range(0, idx.size(), 3):
				k.m.tri("wall", world.call(q[idx[i]]), world.call(q[idx[i + 1]]), world.call(q[idx[i + 2]]), n, band[1] as Color)
		# The underside: plaster over the rooms, painted where it overhangs.
		var inner: Array = []
		var outer: Array = [poly]
		for fp: PackedVector2Array in inside:
			inner.append_array(BuildingGeom.meet([poly], fp))
			outer = BuildingGeom.cut(outer, fp)
		for part: Array in [[inner, ceil], [outer, soffit]]:
			for q: PackedVector2Array in part[0]:
				var idx := Geometry2D.triangulate_polygon(q)
				for i in range(0, idx.size(), 3):
					k.m.tri("wall", (world.call(q[idx[i]]) as Vector3) - n * 0.08, (world.call(q[idx[i + 1]]) as Vector3) - n * 0.08,
						(world.call(q[idx[i + 2]]) as Vector3) - n * 0.08, -n, part[1] as Color)


## Along every edge of every face: nothing where the roof carries on at
## the same height (a ridge, a hip, a valley); where the roof ends over
## air, a fascia along an eave or a bargeboard up a rake; where the face
## stands over a lower roof inside the body, a brick wall down to it.
func _roof_trim() -> void:
	var trim := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	var brick := c(col("brick", Color(0.60, 0.26, 0.17)), CourthouseKit.K_BRICK)
	for fc: Dictionary in roof.faces:
		var pl: Vector3 = fc["plane"]
		var poly: PackedVector2Array = fc["poly"]
		var body: Dictionary = d.roofs[int(fc["body"])]
		_tag("eave %s" % str(body["id"]))
		var ext: PackedVector2Array = body["extent"]
		var ccw := BuildingGeom.area(poly) > 0.0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var L := a.distance_to(b)
			if L < 0.05:
				continue
			var dir := (b - a) / L
			var outward := Vector2(dir.y, -dir.x) if ccw else Vector2(-dir.y, dir.x)
			var n := maxi(1, int(ceil(L / 1.0)))
			# Walk the edge; where the roof drops away, trim or wall it.
			for j in n:
				var p0 := a.lerp(b, float(j) / n)
				var p1 := a.lerp(b, float(j + 1) / n)
				var pm := (p0 + p1) / 2.0
				var h0 := BuildingGeom.ph(pl, p0)
				var h1 := BuildingGeom.ph(pl, p1)
				var hm := (h0 + h1) / 2.0
				# The roof drops away beyond the edge (not only at a sliver
				# where two faces were cut apart).
				var out_h := maxf(roof.height(pm + outward * 0.1), roof.height(pm + outward * 0.6) - 0.5 * absf(h1 - h0))
				if out_h > hm - 0.3:
					continue
				var on_edge := BuildingGeom.on_boundary(pm, ext, 0.08)
				if on_edge:
					var rake := absf(h1 - h0) > 0.15 * p0.distance_to(p1)
					var w0 := d.w(p0, h0) - Vector3(0, 0.08, 0)
					var w1 := d.w(p1, h1) - Vector3(0, 0.08, 0)
					k.m.bar("wall", w0, w1, 0.13 if rake else 0.09, 4, trim)
				elif out_h > -1e30:
					# One body over another: a wall from the lower roof up.
					if _debug_on and hm - out_h > 4.0:
						print("[bld] cheek on %s from (%.1f, %.1f) to (%.1f, %.1f): %.1f up to %.1f" % [body["id"], p0.x, p0.y, p1.x, p1.y, out_h, hm])
					var wa := d.w(p0, out_h - 0.3)
					var wb := d.w(p1, out_h - 0.3)
					var nn := (d.w(pm + outward) - d.w(pm)).normalized()
					for sd: float in [1.0, -1.0]:
						k.m.quad("wall", wa, wb, d.w(p1, h1), d.w(p0, h0), nn * sd, brick)


## A dormer's or a gable's cheeks: along each roof body's footprint (its
## walls' line, inside its overhang), where the body is the roof and
## another body runs on lower under it, over a room, a wall from the
## lower roof up to this one. Not on a line where a space's wall already
## rises (a gable's front on the house's wall).
func _cheeks() -> void:
	for bi in d.roofs.size():
		var r: Dictionary = d.roofs[bi]
		var fp: PackedVector2Array = r["footprint"]
		var ext: PackedVector2Array = r["extent"]
		if absf(BuildingGeom.area(ext) - BuildingGeom.area(fp)) < 0.5:
			continue
		var material := str((r["spec"] as Dictionary).get("cheek", "brick"))
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var L := a.distance_to(b)
			if L < 0.3:
				continue
			var n := maxi(1, int(ceil(L / 0.5)))
			# Along the edge, where it is a cheek: [t0, t1, lower] runs.
			var runs: Array = []
			for j in n:
				var p0 := a.lerp(b, float(j) / n)
				var p1 := a.lerp(b, float(j + 1) / n)
				var pm := (p0 + p1) / 2.0
				var hm := roof.body_height(bi, pm)
				if hm < roof.height(pm) - 0.05 or _on_space_edge(pm) or not _room_at(pm):
					continue
				var lower := -INF
				for ci in d.roofs.size():
					if ci != bi:
						var hc := roof.body_height(ci, pm)
						if hc < hm - 0.3:
							lower = maxf(lower, hc)
				if lower == -INF:
					continue
				if not runs.is_empty() and absf(float(runs[-1][1]) - float(j) / n) < 1e-6:
					runs[-1][1] = float(j + 1) / n
					runs[-1][2] = minf(float(runs[-1][2]), lower)
				else:
					runs.append([float(j) / n, float(j + 1) / n, lower])
			for run: Array in runs:
				var ra := a.lerp(b, float(run[0]))
				var rb := a.lerp(b, float(run[1]))
				var dir := (rb - ra).normalized()
				var inward := Vector2(-dir.y, dir.x)
				if not Geometry2D.is_point_in_polygon((ra + rb) / 2.0 + inward * 0.3, fp):
					inward = -inward
				_tag("cheek %s" % str(r["id"]))
				_cheek(bi, ra, rb, inward, float(run[2]) - 0.3, material)


## A cheek or a dormer's front: a wall on the body's footprint line from
## the lower roof up under this body, its openings cut and dressed.
func _cheek(bi: int, a: Vector2, b: Vector2, inward: Vector2, y0: float, material: String) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
	var tops := PackedFloat32Array()
	for i in n + 1:
		tops.append(roof.body_height(bi, a.lerp(b, float(i) / n) + inward * 0.05) - 0.05)
	var wl := {"a": a, "b": b, "inward": inward, "thick": 0.5, "y0": y0, "tops": tops, "level": "", "space": "",
		"other": "", "kind": "cheek", "material": material}
	var fr := _frame(wl)
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var forward: bool = fr[2]
	var hi := -INF
	for v: float in tops:
		hi = maxf(hi, v)
	var mine := _ops_on(wl, f, length, y0, hi)
	var colr := _wall_color(material)
	var strips := maxi(1, int(length / 0.2))
	for i in strips:
		var u0 := length * i / strips
		var u1 := length * (i + 1) / strips
		var ta := _sample(tops, (u0 / length) if forward else 1.0 - u0 / length)
		var tb := _sample(tops, (u1 / length) if forward else 1.0 - u1 / length)
		var top := minf(ta, tb)
		if top > y0 + 0.05:
			k.wall("wall", f, u0, u1, d.wy(y0), d.wy(top), 0.5 * d.ft, colr, mine, -1000.0)
	for o: Dictionary in mine:
		_dress(f, o, wl)


## Brackets under a roof body's eaves where its data asks ("brackets":
## spacing in feet): along each footprint edge that is an eave (the roof
## level along it and standing out past it), a sawn bracket every
## spacing from the wall's top out under the soffit, and a frieze board
## on the wall under them.
func _brackets() -> void:
	var trim := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	for bi in d.roofs.size():
		var r: Dictionary = d.roofs[bi]
		var spec: Dictionary = r["spec"]
		if not spec.has("brackets"):
			continue
		var step := float(spec["brackets"])
		_tag("brackets %s" % str(r["id"]))
		var fp: PackedVector2Array = r["footprint"]
		var ext: PackedVector2Array = r["extent"]
		for i in fp.size():
			var a := fp[i]
			var b := fp[(i + 1) % fp.size()]
			var L := a.distance_to(b)
			if L < 1.0:
				continue
			var dir := (b - a) / L
			var out := Vector2(dir.y, -dir.x)
			if Geometry2D.is_point_in_polygon((a + b) / 2.0 + out * 0.3, fp):
				out = -out
			var n := maxi(1, int(L / step))
			for j in n + 1:
				var q := a.lerp(b, (float(j) + 0.0) / n)
				# The eave over this point: out to the extent's edge.
				var reach := 0.0
				while reach < 6.0 and Geometry2D.is_point_in_polygon(q + out * (reach + 0.1), ext):
					reach += 0.1
				if reach < 0.6:
					continue
				var y_eave := roof.body_height(bi, q + out * reach)
				if not is_finite(y_eave) or roof.height(q + out * 0.2) > y_eave + 1.0 or _open_at(q - out * 0.5):
					continue
				var top := d.w(q + out * 0.05, y_eave - 0.15)
				var tip := d.w(q + out * (reach - 0.3), y_eave - 0.15)
				var foot := d.w(q + out * 0.05, y_eave - 1.6)
				k.m.bar("wall", top, tip, 0.06, 4, trim)
				k.m.bar("wall", foot, tip.lerp(top, 0.35), 0.05, 4, trim)
				k.m.bar("wall", foot, top, 0.05, 4, trim)
			# The frieze board under the brackets.
			var ya := roof.body_height(bi, a + out * 0.3)
			var yb := roof.body_height(bi, b + out * 0.3)
			if is_finite(ya) and is_finite(yb) and absf(ya - yb) < 0.3 and not _open_at((a + b) / 2.0 - out * 0.5):
				k.m.bar("wall", d.w(a + out * 0.08, ya - 1.2), d.w(b + out * 0.08, yb - 1.2), 0.08, 4, trim)


## Each gable body's open ends ("trim": "gable"): a scalloped bargeboard
## down each rake, a king post and collar in the peak, a finial on the
## point; with "arch": [height at the rakes, height at the middle], an
## arched rib across the front just behind the bargeboards.
func _gable_ends() -> void:
	var trim := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	for bi in d.roofs.size():
		var r: Dictionary = d.roofs[bi]
		var spec: Dictionary = r["spec"]
		if str(r["kind"]) != "gable" or str(r["trim"]) != "gable":
			continue
		var ext: PackedVector2Array = r["extent"]
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q: Vector2 in ext:
			lo = lo.min(q)
			hi = hi.max(q)
		var along_x := str(spec["axis"]) == "x"
		_tag("gable end %s" % str(r["id"]))
		for end: float in [0.0, 1.0]:
			var out := Vector2(-1.0 if end == 0.0 else 1.0, 0.0) if along_x else Vector2(0.0, -1.0 if end == 0.0 else 1.0)
			var mid := Vector2(lerpf(lo.x, hi.x, end), (lo.y + hi.y) / 2.0) if along_x else Vector2((lo.x + hi.x) / 2.0, lerpf(lo.y, hi.y, end))
			var side := Vector2(0, (hi.y - lo.y) / 2.0) if along_x else Vector2((hi.x - lo.x) / 2.0, 0)
			var apex_h := roof.body_height(bi, mid - out * 0.05)
			if not is_finite(apex_h) or roof.height(mid + out * 0.3) > apex_h - 1.0:
				continue
			var e0 := mid - side * 0.98 - out * 0.05
			var e1 := mid + side * 0.98 - out * 0.05
			var h0 := roof.body_height(bi, e0)
			var h1 := roof.body_height(bi, e1)
			if not is_finite(h0) or not is_finite(h1):
				continue
			var apex := d.w(mid - out * 0.05, apex_h)
			for pa: Vector3 in [d.w(e0, h0), d.w(e1, h1)]:
				var n := maxi(1, int(pa.distance_to(apex) / 0.35))
				for j in n:
					var p := pa.lerp(apex, (j + 0.5) / n) - Vector3(0, 0.3, 0)
					k.m.bar("wall", p - Vector3(0, 0.06, 0), p + Vector3(0, 0.06, 0), 0.07, 4, trim)
			var rise := apex_h - minf(h0, h1)
			var collar_h := apex_h - rise * 0.22
			var cw := side.normalized() * (side.length() * 0.22)
			var inner := mid - out * 0.15
			k.m.bar("wall", d.w(inner - cw, collar_h), d.w(inner + cw, collar_h), 0.06, 4, trim)
			k.m.bar("wall", d.w(inner, collar_h), d.w(inner, apex_h - 0.1), 0.06, 4, trim)
			k.m.bar("wall", apex, apex + Vector3(0, 0.35, 0), 0.05, 6, trim)
			k.m.sphere("wall", Transform3D(Basis(), apex + Vector3(0, 0.2, 0)), 0.08, 8, trim)
			k.m.bar("wall", apex, apex - Vector3(0, 0.6, 0), 0.06, 6, trim)
			if spec.has("arch"):
				var ar: Array = spec["arch"]
				var y_end := float(ar[0])
				var y_top := float(ar[1])
				var half := side.length()
				var sg := maxf(y_top - y_end, 0.1)
				var rad := (half * half + sg * sg) / (2.0 * sg)
				var cy := y_top - rad
				var prev := Vector3.ZERO
				for j in 21:
					var u := lerpf(-half, half, j / 20.0)
					var q := inner + side.normalized() * u
					var y := minf(cy + sqrt(maxf(rad * rad - u * u, 0.0)), roof.body_height(bi, q) - 0.4)
					var p := d.w(q, y)
					if j > 0:
						k.m.bar("wall", prev, p, 0.07, 4, trim)
					prev = p


## Whether a plan point lies in a porch, deck or balcony.
func _open_at(p: Vector2) -> bool:
	for s: Dictionary in d.spaces:
		if d.is_open(s) and Geometry2D.is_point_in_polygon(p, s["poly"] as PackedVector2Array):
			return true
	return false


func _on_space_edge(p: Vector2) -> bool:
	for s: Dictionary in d.spaces:
		if not d.is_open(s) and BuildingGeom.on_boundary(p, s["poly"] as PackedVector2Array, 0.3):
			return true
	return false


func _room_at(p: Vector2) -> bool:
	for s: Dictionary in d.spaces:
		if not d.is_open(s) and Geometry2D.is_point_in_polygon(p, s["poly"] as PackedVector2Array):
			return true
	return false


# ---- chimneys -------------------------------------------------------------------

func _chimneys() -> void:
	var brick := c(col("brick", Color(0.60, 0.26, 0.17)), CourthouseKit.K_BRICK)
	var dark := c(col("brick_dark", Color(0.11, 0.09, 0.08)), CourthouseKit.K_BRICK)
	for ch: Dictionary in d.chimneys:
		_tag("chimney %s" % str(ch["id"]))
		var at := d.point(ch["at"])
		var sz: Array = ch["size"]
		var size := Vector2(float(sz[0]), float(sz[1]))
		var y0 := float(ch.get("base", 0.0))
		var y1 := float(ch["top"])
		# Inside the house only the part above the roof is drawn (a breast
		# in a room belongs to the room's finish).
		var low := INF
		for q: Vector2 in [at + size / 2.0, at - size / 2.0, at + Vector2(size.x, -size.y) / 2.0, at + Vector2(-size.x, size.y) / 2.0]:
			var r := roof.height(q)
			if r > -1e30:
				low = minf(low, r)
		if low < INF and _room_at(at):
			y0 = maxf(y0, low - 1.0)
		if style.has("chimney"):
			(style["chimney"] as Callable).call(ch, at, size, y0, y1)
			continue
		var cen := d.w(at, (y0 + y1) / 2.0)
		var box := Vector3(size.y * d.ft, (y1 - y0) * d.ft, size.x * d.ft)
		k.box("wall", Transform3D(), cen, box, brick)
		# A corbelled cap.
		var cap := d.w(at, y1 - 1.2)
		k.box("wall", Transform3D(), cap, Vector3(box.x + 0.25, 0.3, box.z + 0.25), dark)


# ---- porches, decks and balconies -----------------------------------------------

## The open edges of porches, decks and balconies: a railing where
## nothing encloses them; under a roof, posts at the corners and along
## long sides, and a plate under the roof.
func _open_edges() -> void:
	var trim := c(col("trim", Color(0.33, 0.14, 0.09)), CourthouseKit.K_PAINT)
	for s: Dictionary in d.spaces:
		if not d.is_open(s):
			continue
		var fl := float(s["floor"])
		_tag("porch %s" % str(s["id"]))
		for e: Dictionary in _edges[str(s["id"])]:
			var o: Dictionary = e["other"]
			if not o.is_empty():
				continue
			var a: Vector2 = e["a"]
			var b: Vector2 = e["b"]
			var inward: Vector2 = e["inward"]
			if _gap(a, b):
				continue
			var pa := d.w(a, fl)
			var pb := d.w(b, fl)
			_rail(pa, pb, RAIL_H * d.ft, trim)
			if str(s["kind"]) == "porch":
				_skirt(a, b, fl, trim)
		_posts(s, fl, trim)


## Posts along a porch's or deck's open edges, where a roof is over them:
## the open edges joined into runs, a post at each end of a run, at each
## corner sharper than 25 degrees and between at about every 9 ft of
## length; a plate and the braces or frieze between neighbouring posts
## under the same roof.
func _posts(s: Dictionary, fl: float, trim: Color) -> void:
	var open_edges: Array = []
	for e: Dictionary in _edges[str(s["id"])]:
		if (e["other"] as Dictionary).is_empty() and not _gap(e["a"] as Vector2, e["b"] as Vector2):
			open_edges.append(e)
	# Chain the edges end to end.
	var runs: Array = []
	for e: Dictionary in open_edges:
		if not runs.is_empty() and (runs[-1][-1]["b"] as Vector2).distance_to(e["a"] as Vector2) < 0.05:
			runs[-1].append(e)
		else:
			runs.append([e])
	if runs.size() > 1 and (runs[-1][-1]["b"] as Vector2).distance_to(runs[0][0]["a"] as Vector2) < 0.05:
		var last: Array = runs.pop_back()
		last.append_array(runs[0])
		runs[0] = last
	for run: Array in runs:
		# Stations: the run's corners that turn, spaced out between.
		var pts: Array = [[run[0]["a"], run[0]["inward"]]]
		for k_ in run.size():
			var e: Dictionary = run[k_]
			var a: Vector2 = e["a"]
			var b: Vector2 = e["b"]
			var turn := 0.0
			if k_ < run.size() - 1:
				var d0 := (b - a).normalized()
				var d1 := ((run[k_ + 1]["b"] as Vector2) - (run[k_ + 1]["a"] as Vector2)).normalized()
				turn = rad_to_deg(absf(d0.angle_to(d1)))
			if k_ == run.size() - 1 or turn > 25.0:
				pts.append([b, e["inward"]])
		var stations: Array = []
		for m in range(pts.size() - 1):
			# Along the run between two corners, the path through the edges.
			var a: Vector2 = pts[m][0]
			var b: Vector2 = pts[m + 1][0]
			var path: Array = []
			var on := false
			for e: Dictionary in run:
				if (e["a"] as Vector2).distance_to(a) < 0.05:
					on = true
				if on:
					path.append(e)
				if on and (e["b"] as Vector2).distance_to(b) < 0.05:
					break
			var total := 0.0
			for e: Dictionary in path:
				total += (e["a"] as Vector2).distance_to(e["b"] as Vector2)
			var n := maxi(1, int(round(total / 9.0)))
			for j2 in n:
				var want := total * j2 / n
				var acc := 0.0
				for e: Dictionary in path:
					var L := (e["a"] as Vector2).distance_to(e["b"] as Vector2)
					if acc + L >= want - 1e-6:
						stations.append([(e["a"] as Vector2).lerp(e["b"] as Vector2, clampf((want - acc) / maxf(L, 1e-6), 0.0, 1.0)), e["inward"]])
						break
					acc += L
		stations.append(pts[-1])
		var prev := Vector3.ZERO
		var prev_body := -1
		for st: Array in stations:
			var q: Vector2 = st[0]
			var inward: Vector2 = st[1]
			var top := roof.height(q + inward * 0.3)
			var body := roof.body_at(q + inward * 0.3)
			if top < fl + 6.0 or top > fl + 30.0:
				prev_body = -1
				continue
			var foot := d.w(q, fl)
			var head := d.w(q, top - 0.3)
			k.box("wall", Transform3D(), (foot + head) / 2.0, Vector3(0.18, head.y - foot.y, 0.18), trim)
			k.solid(Transform3D(), (foot + head) / 2.0, Vector3(0.18, head.y - foot.y, 0.18))
			if body == prev_body and absf(prev.y - head.y) < 0.6:
				k.m.bar("wall", prev - Vector3(0, 0.1, 0), head - Vector3(0, 0.1, 0), 0.1, 4, trim)
				_between_posts(prev, head, str(s["kind"]), trim)
			prev = head
			prev_body = body


## Between two posts under a roof: on a porch, a brace from each post up
## to the plate; on a deck, a band of pierced lattice under the plate
## with a fringe of drops along its foot (the Texas deck's frieze).
func _between_posts(pa: Vector3, pb: Vector3, kind: String, trim: Color) -> void:
	var length := pa.distance_to(pb)
	if kind == "deck":
		var foot := -2.5 * d.ft
		k.m.bar("wall", pa + Vector3(0, foot, 0), pb + Vector3(0, foot, 0), 0.035, 4, trim)
		var n := maxi(1, int(length / 0.16))
		for j in n:
			var t0 := float(j) / n
			var t1 := float(j + 1) / n
			k.m.bar("wall", pa.lerp(pb, t0) + Vector3(0, foot, 0), pa.lerp(pb, t1) + Vector3(0, -0.12, 0), 0.012, 3, trim)
			k.m.bar("wall", pa.lerp(pb, t0) + Vector3(0, -0.12, 0), pa.lerp(pb, t1) + Vector3(0, foot, 0), 0.012, 3, trim)
		var drops := int(length / 0.09)
		for j in drops:
			var p := pa.lerp(pb, (j + 0.5) / drops) + Vector3(0, foot, 0)
			k.m.bar("wall", p, p - Vector3(0, 0.13, 0), 0.016, 4, trim)
		return
	var t := clampf(0.9 / maxf(length, 0.1), 0.0, 0.45)
	k.m.bar("wall", pa - Vector3(0, 0.9, 0), pa.lerp(pb, t), 0.05, 4, trim)
	k.m.bar("wall", pb - Vector3(0, 0.9, 0), pb.lerp(pa, t), 0.05, 4, trim)


## A porch's lattice skirt from the ground up to under its boards along
## a-b: a rail at the top and foot, crossed laths between.
func _skirt(a: Vector2, b: Vector2, fl: float, trim: Color) -> void:
	var L := a.distance_to(b)
	var n := maxi(1, int(L / 0.6))
	for i in n:
		var q0 := a.lerp(b, float(i) / n)
		var q1 := a.lerp(b, float(i + 1) / n)
		var g0 := ground_at(q0)
		var g1 := ground_at(q1)
		if fl - maxf(g0, g1) < 0.4:
			continue
		var t0 := d.w(q0, fl - 0.35)
		var t1 := d.w(q1, fl - 0.35)
		var b0 := d.w(q0, g0)
		var b1 := d.w(q1, g1)
		k.m.bar("wall", b0, t1, 0.015, 3, trim)
		k.m.bar("wall", b1, t0, 0.015, 3, trim)
		k.m.bar("wall", t0, t1, 0.04, 4, trim)
		k.m.bar("wall", b0, b1, 0.03, 4, trim)


## Whether an opening of kind "gap" (steps down, an open side) stands on
## the segment a-b.
func _gap(a: Vector2, b: Vector2) -> bool:
	for op: Dictionary in d.openings:
		if str(op["kind"]) == "gap" and BuildingGeom.seg_dist(op["at"] as Vector2, a, b) < 0.5:
			return true
	return false


func _rail(a: Vector3, b: Vector3, ht: float, trim: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	rails.append([a, b])
	k.m.bar("wall", a + Vector3(0, ht, 0), b + Vector3(0, ht, 0), 0.05, 4, trim)
	k.m.bar("wall", a + Vector3(0, 0.12, 0), b + Vector3(0, 0.12, 0), 0.04, 4, trim)
	var panels := maxi(1, int(round(length / 0.9)))
	for i in panels:
		var p0 := a.lerp(b, float(i) / panels)
		var p1 := a.lerp(b, float(i + 1) / panels)
		k.m.bar("wall", p0 + Vector3(0, 0.12, 0), p1 + Vector3(0, ht, 0), 0.025, 4, trim)
		k.m.bar("wall", p0 + Vector3(0, ht, 0), p1 + Vector3(0, 0.12, 0), 0.025, 4, trim)
		k.m.bar("wall", p1, p1 + Vector3(0, ht, 0), 0.035, 4, trim)
	var mid := (a + b) / 2.0 + Vector3(0, ht / 2.0, 0)
	var dd := (b - a).normalized()
	k.solid(Transform3D(Basis(dd.cross(Vector3.UP).normalized(), Vector3.UP, dd), mid), Vector3.ZERO, Vector3(0.08, ht, length))


# ---- rooms -------------------------------------------------------------------------

## Each enclosed space's finish on the inner faces of its walls: plaster
## (or the space's finish) from its floor to its ceiling, or up to the roof
## where the roof comes lower; a ceiling where the space has its own top
## and nothing but roof is over it.
func _rooms() -> void:
	var plaster := c(col("plaster", Color(0.84, 0.79, 0.68)), CourthouseKit.K_PLASTER)
	for s: Dictionary in d.spaces:
		if d.is_open(s) or str(s["kind"]) == "void":
			continue
		_tag("finish %s" % str(s["id"]))
		var edges: Array = _edges[str(s["id"])]
		var p := PackedVector2Array()
		var ins := PackedFloat32Array()
		var g: Dictionary = d.groups.get(str(s["group"]), {"wall": 1.0})
		for e: Dictionary in edges:
			p.append(e["a"] as Vector2)
			var o: Dictionary = e["other"]
			var t := float(g.get("wall", 1.0))
			if not o.is_empty() and not d.is_open(o):
				if str(o["group"]) == str(s["group"]):
					t = PART / 2.0
				elif int(d.rank.get(str(o["group"]), 99)) < int(d.rank.get(str(s["group"]), 99)):
					t = 0.02
			ins.append(t + 0.02)
		if p.size() < 3:
			continue
		var inner := BuildingGeom.inset(p, ins)
		var fl := float(s["floor"])
		var finish: Dictionary = s.get("finish", {})
		var wall_c := plaster
		if finish.has("wall"):
			var wc: Array = finish["wall"]
			wall_c = c(Color(float(wc[0]), float(wc[1]), float(wc[2])), CourthouseKit.K_PLASTER)
		rooms.append({"space": str(s["id"]), "poly": inner, "y0": fl})
		for i in inner.size():
			var a := inner[i]
			var b := inner[(i + 1) % inner.size()]
			var L := a.distance_to(b)
			if L < 0.1:
				continue
			var n := maxi(1, int(ceil(L / 1.0)))
			for j in n:
				var q0 := a.lerp(b, float(j) / n)
				var q1 := a.lerp(b, float(j + 1) / n)
				var t0 := _top_at(s, q0, true)
				var t1 := _top_at(s, q1, true)
				var nn := (d.w((q0 + q1) / 2.0) - d.w((q0 + q1) / 2.0 + (q1 - q0).orthogonal())).normalized()
				inner_mesh.quad("wall", d.w(q0, fl), d.w(q1, fl), d.w(q1, t1), d.w(q0, t0), nn, wall_c)
				inner_mesh.quad("wall", d.w(q0, fl), d.w(q1, fl), d.w(q1, t1), d.w(q0, t0), -nn, wall_c)
		# Its own ceiling where only roof is over it and the space stops lower.
		var top: Variant = s.get("top", "roof")
		if not top is String:
			var cen := _centre(inner)
			if _above(str(s["level"]), cen) == INF and roof.height(cen) > float(top) + 0.3:
				var pts: Array = []
				for q: Vector2 in inner:
					pts.append(q)
				_ceiling(pts, float(top))


func _ceiling(pts: Array, y: float) -> void:
	var poly := PackedVector2Array()
	for q: Vector2 in pts:
		poly.append(q)
	var ceil := c(col("ceiling", Color(0.86, 0.82, 0.72)), CourthouseKit.K_PLASTER)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		inner_mesh.tri("wall", d.w(poly[idx[i]], y), d.w(poly[idx[i + 1]], y), d.w(poly[idx[i + 2]], y), Vector3.DOWN, ceil)


## FLOWSTATE_BLD_DEBUG=<space id>: print that space's edges and walls,
## and every roof plane steeper than 3 in 1.
func _debug(sid: String) -> void:
	for e: Dictionary in _edges.get(sid, []):
		var o: Dictionary = e["other"]
		print("[bld] %s edge %s -> %s  other %s" % [sid, e["a"], e["b"], o.get("id", "-")])
	for wl: Dictionary in walls:
		if str(wl["space"]) == sid or str(wl["other"]) == sid:
			print("[bld] wall %s %s -> %s kind %s y0 %.1f tops %s" % [wl["space"], wl["a"], wl["b"], wl["kind"], wl["y0"], wl["tops"]])
	for fc: Dictionary in roof.faces:
		var lo := INF
		var hi := -INF
		for q: Vector2 in fc["poly"]:
			lo = minf(lo, BuildingGeom.ph(fc["plane"], q))
			hi = maxf(hi, BuildingGeom.ph(fc["plane"], q))
		if hi - lo > 20.0 or lo < -5.0:
			print("[bld] face of %s from %.1f to %.1f ft: %s" % [d.roofs[int(fc["body"])]["id"], lo, hi, fc["poly"]])


## What the builder can see is wrong with what it built, printed so the
## data can be fixed: a wall whose top stands clear of every roof and
## floor over it (a wall with nothing to carry, open to the sky on both
## sides).
var findings: Array[String] = []


func _self_check() -> void:
	for wl: Dictionary in walls:
		var a: Vector2 = wl["a"]
		var b: Vector2 = wl["b"]
		var inward: Vector2 = wl["inward"]
		var tops: PackedFloat32Array = wl["tops"]
		var bad := 0
		var worst := 0.0
		var where := Vector2.ZERO
		for i in tops.size():
			var q := a.lerp(b, float(i) / maxf(tops.size() - 1, 1))
			var top := tops[i]
			var cover := -INF
			for sd: float in [-1.0, 0.0, 1.0]:
				var qq := q + inward * (float(wl["thick"]) / 2.0 + sd * 0.8)
				cover = maxf(cover, roof.height(qq, true))
				var ab := _above(str(wl["level"]), qq)
				if ab < INF:
					cover = maxf(cover, ab)
			if cover < top - 1.0:
				bad += 1
				if top - cover > worst:
					worst = top - cover
					where = q
		if bad > 0:
			findings.append("wall of %s (%s) from (%.1f, %.1f) to (%.1f, %.1f): %d ft stand up to %.1f ft clear of any roof, near (%.1f, %.1f)"
				% [wl["space"], wl["kind"], a.x, a.y, b.x, b.y, bad, worst, where.x, where.y])
	for f: String in findings:
		print("[building] " + f)
	print("[building] %s: %d findings" % [d.name, findings.size()])


## Writes the building as built for tools/building/validity.py: every
## triangle (<base>_tris.bin, 9 float32 each, world metres), its tag
## (<base>_tags.bin, int32), and <base>.json: the tag names, the
## openings as built, the spaces (plan feet, floor, top) and the frame.
func export_geometry(base: String) -> void:
	var pts := PackedFloat32Array()
	var tags := PackedInt32Array()
	var inner_tags := {}
	var meshes: Array = [k.m, inner_mesh]
	meshes.append_array(style.get("extra_meshes", []))
	for mi in meshes.size():
		var tm: TownMesh = meshes[mi]
		var dmp: Array = tm.dump(global_transform)
		pts.append_array(dmp[0] as PackedFloat32Array)
		var tg: PackedInt32Array = dmp[1]
		var keys: Array = dmp[2]
		for i in tg.size():
			# Room finishes and glass are marked so the checks can tell them.
			var t := tg[i]
			if mi == 1:
				t = -t - 1
			elif str(keys[i]) == "glass":
				t = -1000000 - t
			tags.append(t)
	var f := FileAccess.open(base + "_tris.bin", FileAccess.WRITE)
	f.store_buffer(pts.to_byte_array())
	f.close()
	f = FileAccess.open(base + "_tags.bin", FileAccess.WRITE)
	f.store_buffer(tags.to_byte_array())
	f.close()
	var ops: Array = []
	for o: Dictionary in built_openings:
		var cc: Vector3 = o["c"]
		var nn: Vector3 = o["n"]
		var al: Vector3 = o["along"]
		ops.append({"c": [cc.x, cc.y, cc.z], "n": [nn.x, nn.y, nn.z], "along": [al.x, al.y, al.z], "w": o["w"], "y0": o["y0"],
			"ys": o["ys"], "yt": o["yt"], "kind": o["kind"], "id": o["id"], "outer": o["outer"], "wall": o["wall"],
			"ground_out": d.wy(ground_at(d.plan_of(cc + nn * 0.8)))})
	var sp: Array = []
	for s: Dictionary in d.spaces:
		var poly: Array = []
		for q: Vector2 in s["poly"]:
			poly.append([q.x, q.y])
		sp.append({"id": s["id"], "kind": s["kind"], "floor": s["floor"], "top": s.get("top", "roof"), "poly": poly,
			"open": d.is_open(s)})
	# The ground round the building, every foot over its plan's bounds
	# and 40 ft beyond (feet over the datum).
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for s: Dictionary in d.spaces:
		for q: Vector2 in s["poly"]:
			lo = lo.min(q)
			hi = hi.max(q)
	lo -= Vector2(40, 40)
	hi += Vector2(40, 40)
	var gvals: Array = []
	var nx := int(hi.x - lo.x) + 1
	var nz := int(hi.y - lo.y) + 1
	for i in nx:
		for j in nz:
			gvals.append(snappedf(ground_at(lo + Vector2(i, j)), 0.01))
	var meta := {"ground": {"x0": lo.x, "z0": lo.y, "nx": nx, "nz": nz, "ft": gvals}, "tags": tag_names, "openings": ops, "spaces": sp, "origin": [d.origin.x, d.origin.y], "datum_m": d.datum_m,
		"ft": d.ft}
	f = FileAccess.open(base + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	print("[building] geometry written to %s_*" % base)
