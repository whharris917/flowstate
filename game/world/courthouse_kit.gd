class_name CourthouseKit
extends RefCounted
## The joiner's and mason's pieces the Union County courthouse and its
## square are built from, gathered into one mesh per material
## (TownMesh) with boxes for the player's feet and shoulders: walls with
## their openings cut and the arch over each filled, sash windows with
## their frames and bars, stone hoods and archivolts, bracketed
## cornices, hip and mansard roofs, a bell roof lofted over a square,
## turned posts and balusters, iron railings.
##
## A facade is worked in its own frame: origin on the outer face at
## grade, x along the wall left to right as seen from outside, y up,
## z out of the wall. Art only: no records.

const K_PAINT := HarborTown.K_PAINT
const K_BRICK := HarborTown.K_BRICK
const K_STONE := HarborTown.K_GRANITE
const K_WOOD := HarborTown.K_WOOD
const K_OAK := HarborTown.K_OAK
const K_PLASTER := HarborTown.K_PLASTER
const K_ENAMEL := HarborTown.K_ENAMEL
const K_CLOTH := HarborTown.K_CLOTH
const K_TAR := HarborTown.K_TAR
const K_TILE := HarborTown.K_TILE
const K_SLATE := 17
const K_BEAD := 18
const K_PAVER := 19
const K_LAWN := 20

var m := TownMesh.new()
var solids: Node3D
var solid_count := 0


func _init(solid_parent: Node3D) -> void:
	solids = solid_parent


## A colour and what the surface is made of, for the wall shader.
static func kc(color: Color, kind: int) -> Color:
	return Color(color.r, color.g, color.b, kind / 20.0)


static func at(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## A box of size whose centre is at c in frame f.
func box(key: String, f: Transform3D, c: Vector3, size: Vector3, col: Color, bottom := true) -> void:
	m.box(key, f * Transform3D(Basis(), c), size, col, bottom)


## A box turned by angle about the frame's z (a voussoir, a rake).
func box_rz(key: String, f: Transform3D, c: Vector3, size: Vector3, angle: float, col: Color) -> void:
	m.box(key, f * Transform3D(Basis(Vector3.BACK, angle), c), size, col, true)


## A solid box for the player, centre c in frame f.
func solid(f: Transform3D, c: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = f * Transform3D(Basis(), c)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	shape.shape = b
	body.add_child(shape)
	solids.add_child(body)
	solid_count += 1


## Drawn and solid.
func block(key: String, f: Transform3D, c: Vector3, size: Vector3, col: Color) -> void:
	box(key, f, c, size, col)
	solid(f, c, size)


## A slope for the feet from a (low) to b (high), w wide, in frame f:
## the player has no step, so every stair is a ramp underfoot.
func ramp(f: Transform3D, a: Vector3, b: Vector3, w: float) -> void:
	var run := Vector2(b.x - a.x, b.z - a.z)
	var rise := b.y - a.y
	var length := sqrt(run.length_squared() + rise * rise)
	var yaw := atan2(-run.x, -run.y)
	var tilt := atan2(rise, run.length())
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = f * Transform3D(basis, (a + b) / 2.0 - basis.y * 0.05)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 0.1, length)
	shape.shape = bs
	body.add_child(shape)
	solids.add_child(body)
	solid_count += 1


## ---- openings ---------------------------------------------------------

## An opening in a wall: centre u, width w, sill y0, spring ys, apex yt;
## head "flat" (yt = ys), "segment" or "round" (yt = ys + w / 2).
static func opening(u: float, w: float, y0: float, ys: float, head: String, rise := 0.0) -> Dictionary:
	var yt := ys
	if head == "round":
		yt = ys + w / 2.0
	elif head == "segment":
		yt = ys + (rise if rise > 0.0 else w * 0.16)
	return {"u": u, "w": w, "y0": y0, "ys": ys, "yt": yt, "head": head}


## The points of an opening's head from its left spring to its right,
## in the facade's (u, y).
static func head_points(o: Dictionary, n: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var u := float(o["u"])
	var w := float(o["w"])
	var ys := float(o["ys"])
	var yt := float(o["yt"])
	if str(o["head"]) == "flat" or yt - ys < 0.005:
		pts.append(Vector2(u - w / 2.0, ys))
		pts.append(Vector2(u + w / 2.0, ys))
		return pts
	var h := yt - ys
	var r := (w * w / 4.0 + h * h) / (2.0 * h)
	var yc := yt - r
	var a0 := atan2(ys - yc, -w / 2.0)
	var a1 := atan2(ys - yc, w / 2.0)
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		pts.append(Vector2(u + r * cos(a), yc + r * sin(a)))
	return pts


## The arc's centre and radius for an opening's head.
static func head_circle(o: Dictionary) -> Vector3:
	var w := float(o["w"])
	var h := float(o["yt"]) - float(o["ys"])
	if h < 0.005:
		return Vector3(float(o["u"]), float(o["ys"]) - 1000.0, 1000.0)
	var r := (w * w / 4.0 + h * h) / (2.0 * h)
	return Vector3(float(o["u"]), float(o["yt"]) - r, r)


## A wall from u0 to u1 and y0 to y1, t thick behind the face, with
## its openings cut: piers full height, the wall under each sill and
## over each head, and the spandrels round an arched head filled face,
## back and soffit. Solid where a player could reach it.
func wall(key: String, f: Transform3D, u0: float, u1: float, y0: float, y1: float, t: float, col: Color,
		openings: Array, solid_below := 4.5) -> void:
	# Only the openings that cross this band, in order along it.
	var sorted: Array = []
	for o: Dictionary in openings:
		if float(o["y0"]) < y1 - 0.001 and float(o["yt"]) > y0 + 0.001 \
				and float(o["u"]) + float(o["w"]) / 2.0 > u0 and float(o["u"]) - float(o["w"]) / 2.0 < u1:
			sorted.append(o)
	# Every edge of an opening splits the band into strips; each strip is
	# filled between the openings over it, so openings may stand one over
	# another (a door and the fan over it).
	var edges: Array[float] = [u0, u1]
	for o: Dictionary in sorted:
		for e: float in [float(o["u"]) - float(o["w"]) / 2.0, float(o["u"]) + float(o["w"]) / 2.0]:
			if e > u0 and e < u1:
				edges.append(e)
	edges.sort()
	for i in edges.size() - 1:
		var ua := edges[i]
		var ub := edges[i + 1]
		if ub - ua < 0.001:
			continue
		var um := (ua + ub) / 2.0
		var over: Array = []
		for o: Dictionary in sorted:
			if absf(um - float(o["u"])) < float(o["w"]) / 2.0:
				over.append(o)
		over.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["y0"]) < float(b["y0"]))
		var y := y0
		for o: Dictionary in over:
			if float(o["y0"]) > y + 0.001:
				_piece(key, f, ua, ub, y, minf(float(o["y0"]), y1), t, col, solid_below)
			y = maxf(y, float(o["yt"]))
		if y1 > y + 0.001:
			_piece(key, f, ua, ub, maxf(y, y0), y1, t, col, solid_below)
	for o: Dictionary in sorted:
		# A band is never cut through an arch: its head lies wholly inside.
		if float(o["ys"]) >= y0 - 0.001 and float(o["yt"]) <= y1 + 0.001:
			_spandrels(key, f, o, t, col)


func _piece(key: String, f: Transform3D, ua: float, ub: float, ya: float, yb: float, t: float, col: Color,
		solid_below: float) -> void:
	var c := Vector3((ua + ub) / 2.0, (ya + yb) / 2.0, -t / 2.0)
	var size := Vector3(ub - ua, yb - ya, t)
	box(key, f, c, size, col)
	if ya < solid_below:
		solid(f, c, size)


## The fill between an arched head and the level of its apex.
func _spandrels(key: String, f: Transform3D, o: Dictionary, t: float, col: Color) -> void:
	if str(o["head"]) == "flat":
		return
	var pts := head_points(o, 14)
	var yt := float(o["yt"])
	var circ := head_circle(o)
	var nf := (f.basis * Vector3(0, 0, 1)).normalized()
	for k in pts.size() - 1:
		var p := pts[k]
		var q := pts[k + 1]
		for z: float in [0.0, -t]:
			var n := nf if z == 0.0 else -nf
			if absf(yt - p.y) < 0.002 and absf(yt - q.y) < 0.002:
				continue
			m.quad(key, f * Vector3(p.x, p.y, z), f * Vector3(q.x, q.y, z), f * Vector3(q.x, yt, z),
				f * Vector3(p.x, yt, z), n, col)
		var mid := (p + q) / 2.0
		var inward := (Vector2(circ.x, circ.y) - mid).normalized()
		m.quad(key, f * Vector3(p.x, p.y, 0.0), f * Vector3(q.x, q.y, 0.0), f * Vector3(q.x, q.y, -t),
			f * Vector3(p.x, p.y, -t), (f.basis * Vector3(inward.x, inward.y, 0.0)).normalized(), col)


## A pane of glass filling an opening at depth z: the rectangle to the
## spring and a fan to the head.
func glass(f: Transform3D, o: Dictionary, z: float, col := Color(1, 1, 1, 1), key := "glass") -> void:
	var u := float(o["u"])
	var w := float(o["w"])
	var ys := float(o["ys"])
	var y0 := float(o["y0"])
	var nf := (f.basis * Vector3(0, 0, 1)).normalized()
	m.quad(key, f * Vector3(u - w / 2.0, y0, z), f * Vector3(u - w / 2.0, ys, z), f * Vector3(u + w / 2.0, ys, z),
		f * Vector3(u + w / 2.0, y0, z), nf, col)
	if str(o["head"]) != "flat":
		var pts := head_points(o, 14)
		for k in pts.size() - 1:
			m.tri(key, f * Vector3(u, ys, z), f * Vector3(pts[k].x, pts[k].y, z), f * Vector3(pts[k + 1].x, pts[k + 1].y, z),
				nf, col)


## A band following an arc (a hood, an archivolt, a sash's curved head):
## from the circle circ (u, y, r), angle a0 to a1, width across the arc
## wd (outward from r), depth dz standing out to z_face.
func arc_band(key: String, f: Transform3D, circ: Vector3, a0: float, a1: float, wd: float, dz: float, z_face: float,
		col: Color, n := 10) -> void:
	var rm := circ.z + wd / 2.0
	for k in n:
		var a := lerpf(a0, a1, (k + 0.5) / n)
		var chord := 2.0 * (circ.z + wd) * sin(absf(a1 - a0) / n / 2.0) * 1.04
		var c := Vector3(circ.x + rm * cos(a), circ.y + rm * sin(a), z_face - dz / 2.0)
		box_rz(key, f, c, Vector3(chord, wd, dz), a - PI / 2.0, col)


## A sash window's joinery in an opening at depth z: frame, the meeting
## rail, a bar up each sash (two over two), and in an arched head the
## curved top rail and a few radial bars; the glass behind.
func sash(f: Transform3D, o: Dictionary, z: float, col: Color, meeting := -1.0, bars := 1, fan := true) -> void:
	var u := float(o["u"])
	var w := float(o["w"])
	var y0 := float(o["y0"])
	var ys := float(o["ys"])
	var fw := 0.07
	var fd := 0.08
	glass(f, o, z - 0.02)
	for s: float in [-1.0, 1.0]:
		box("wall", f, Vector3(u + s * (w / 2.0 - fw / 2.0), (y0 + ys) / 2.0, z), Vector3(fw, ys - y0, fd), col)
	box("wall", f, Vector3(u, y0 + fw / 2.0, z), Vector3(w, fw, fd), col)
	var mr := meeting if meeting > 0.0 else (y0 + ys) / 2.0
	box("wall", f, Vector3(u, mr, z), Vector3(w, 0.06, fd + 0.02), col)
	for b in bars:
		var bu := u - w / 2.0 + w * (b + 1.0) / (bars + 1.0)
		box("wall", f, Vector3(bu, (y0 + ys) / 2.0, z - 0.01), Vector3(0.03, ys - y0, 0.04), col)
	if str(o["head"]) == "flat":
		box("wall", f, Vector3(u, ys - fw / 2.0, z), Vector3(w, fw, fd), col)
		return
	box("wall", f, Vector3(u, ys, z - 0.01), Vector3(w, 0.05, 0.05), col)
	var circ := head_circle(o)
	var a0 := atan2(ys - circ.y, -w / 2.0)
	var a1 := atan2(ys - circ.y, w / 2.0)
	arc_band("wall", f, Vector3(circ.x, circ.y, circ.z - fw), a1, a0, fw, fd, z + fd / 2.0, col, 10)
	if fan and str(o["head"]) == "round":
		for k in 5:
			var a := lerpf(a1, a0, (k + 1.0) / 6.0)
			var l := circ.z * 0.9
			var c := Vector3(circ.x + cos(a) * l / 2.0, ys + sin(a) * l / 2.0, z - 0.01)
			box_rz("wall", f, c, Vector3(0.025, l, 0.035), a - PI / 2.0, col)


## A door leaf of raised panels, w by h, its face along the frame's x,
## standing in frame f with its bottom centre at c.
func door_leaf(f: Transform3D, c: Vector3, w: float, h: float, col: Color, glazed := false) -> void:
	box("wall", f, c + Vector3(0, h / 2.0, 0), Vector3(w, h, 0.05), col)
	var panel := col.darkened(0.12)
	var rows := [0.08, 0.42, 0.72] if not glazed else [0.08, 0.36]
	for k in rows.size():
		var y := h * float(rows[k])
		var ph := h * (0.26 if k < rows.size() - 1 or not glazed else 0.5)
		if glazed and k == rows.size() - 1:
			m.quad("glass", f * (c + Vector3(-w * 0.36, y + 0.05, 0.03)), f * (c + Vector3(-w * 0.36, y + ph, 0.03)),
				f * (c + Vector3(w * 0.36, y + ph, 0.03)), f * (c + Vector3(w * 0.36, y + 0.05, 0.03)),
				(f.basis * Vector3(0, 0, 1)).normalized(), Color(1, 1, 1, 1))
			continue
		for s: float in [-1.0, 1.0]:
			for side: float in [1.0, -1.0]:
				box("wall", f, c + Vector3(s * w * 0.21, y + ph / 2.0 + 0.04, side * 0.03), Vector3(w * 0.32, ph - 0.08, 0.015), panel)


## ---- cornices and trim --------------------------------------------------

## A bracketed cornice along a facade from u0 to u1, its frieze under
## y (the cornice's top), projecting out: frieze, paired brackets on the
## frieze, the soffit, the corona and its crown, a row of dentils.
func cornice(f: Transform3D, u0: float, u1: float, y: float, out: float, col: Color, pairs_every := 1.6,
		frieze := 0.55, deep := 0.55, dentils := true) -> void:
	var len := u1 - u0
	var uc := (u0 + u1) / 2.0
	# Frieze band and its bed moulding.
	box("wall", f, Vector3(uc, y - deep - frieze / 2.0, 0.03), Vector3(len, frieze, 0.06), col)
	box("wall", f, Vector3(uc, y - deep - frieze - 0.05, 0.05), Vector3(len, 0.1, 0.1), col)
	box("wall", f, Vector3(uc, y - deep + 0.04, 0.09), Vector3(len, 0.08, 0.18), col)
	# Soffit and corona.
	box("wall", f, Vector3(uc, y - 0.28, out / 2.0), Vector3(len + out * 0.1, 0.06, out), col)
	box("wall", f, Vector3(uc, y - 0.16, out - 0.05), Vector3(len + out * 0.1, 0.24, 0.1), col)
	box("wall", f, Vector3(uc, y - 0.02, out / 2.0 + 0.02), Vector3(len + out * 0.12, 0.08, out + 0.08), col)
	if dentils:
		var nd := int(len / 0.16)
		for k in nd:
			var du := u0 + (k + 0.5) * len / nd
			box("wall", f, Vector3(du, y - deep + 0.14, 0.2), Vector3(0.07, 0.1, 0.07), col)
	# The brackets in pairs, standing on the frieze, carrying the soffit.
	var n := maxi(1, int(round(len / pairs_every)))
	for k in n + 1:
		var bu := u0 + 0.18 + (len - 0.36) * k / n
		for s: float in [-0.11, 0.11]:
			_bracket(f, Vector3(bu + s, y - 0.31, 0.0), out - 0.08, deep + frieze * 0.6, col)


## One scroll bracket under a soffit at top (its top against the wall),
## depth d out and height h down.
func _bracket(f: Transform3D, top: Vector3, d: float, h: float, col: Color) -> void:
	box("wall", f, top + Vector3(0, -0.06, d / 2.0), Vector3(0.09, 0.12, d), col)
	box("wall", f, top + Vector3(0, -h / 2.0, 0.08), Vector3(0.09, h, 0.16), col)
	box("wall", f, top + Vector3(0, -0.2, d * 0.45), Vector3(0.08, 0.2, d * 0.6), col)
	box("wall", f, top + Vector3(0, -h + 0.05, 0.13), Vector3(0.1, 0.1, 0.14), col)


## A stone segmental or round hood over an opening: the band round the
## head, a keystone, and the ears at its springs; a sill under it.
func hood(f: Transform3D, o: Dictionary, col: Color, band := 0.16, ears := true, keystone := true,
		sill := true) -> void:
	var circ := head_circle(o)
	var w := float(o["w"])
	var ys := float(o["ys"])
	var yt := float(o["yt"])
	if str(o["head"]) == "flat":
		box("wall", f, Vector3(float(o["u"]), ys + band / 2.0, 0.05), Vector3(w + 0.3, band, 0.1), col)
	else:
		var a0 := atan2(ys - circ.y, -w / 2.0)
		var a1 := atan2(ys - circ.y, w / 2.0)
		arc_band("wall", f, circ, a1 - 0.03, a0 + 0.03, band, 0.1, 0.1, col, 12)
		if ears:
			for s: float in [-1.0, 1.0]:
				box("wall", f, Vector3(float(o["u"]) + s * (w / 2.0 + band * 0.9), ys + 0.02, 0.06),
					Vector3(band * 1.9, band * 1.3, 0.12), col)
	if keystone:
		box("wall", f, Vector3(float(o["u"]), yt + band * 0.55, 0.08), Vector3(0.22, band * 1.9, 0.16), col)
	if sill:
		box("wall", f, Vector3(float(o["u"]), float(o["y0"]) - 0.05, 0.07), Vector3(w + 0.24, 0.1, 0.16), col)


## ---- roofs --------------------------------------------------------------

## A hip roof over x0..x1, z0..z1 (world, in f) from eave height ye at
## slope s (rise over run): two trapezoids and two triangles, the ridge
## along the longer side.
func hip(f: Transform3D, x0: float, x1: float, z0: float, z1: float, ye: float, s: float, col: Color) -> void:
	var along_x := (x1 - x0) >= (z1 - z0)
	var hd := ((z1 - z0) if along_x else (x1 - x0)) / 2.0
	var top := ye + hd * s
	var a := Vector3(x0, ye, z0)
	var b := Vector3(x1, ye, z0)
	var c := Vector3(x1, ye, z1)
	var d := Vector3(x0, ye, z1)
	var r0: Vector3
	var r1: Vector3
	if along_x:
		r0 = Vector3(x0 + hd, top, (z0 + z1) / 2.0)
		r1 = Vector3(x1 - hd, top, (z0 + z1) / 2.0)
		_roof_quad(f, a, b, r1, r0, col)
		_roof_quad(f, c, d, r0, r1, col)
		_roof_tri(f, d, a, r0, col)
		_roof_tri(f, b, c, r1, col)
	else:
		r0 = Vector3((x0 + x1) / 2.0, top, z0 + hd)
		r1 = Vector3((x0 + x1) / 2.0, top, z1 - hd)
		_roof_quad(f, d, a, r0, r1, col)
		_roof_quad(f, b, c, r1, r0, col)
		_roof_tri(f, a, b, r0, col)
		_roof_tri(f, c, d, r1, col)


func _roof_quad(f: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	m.quad("wall", f * a, f * b, f * c, f * d, (f.basis * n).normalized(), col)


func _roof_tri(f: Transform3D, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	m.tri("wall", f * a, f * b, f * c, (f.basis * n).normalized(), col)


## A roof over a rectangle's outline climbing from the rectangle lo..hi
## at y0 to its inset by `inset` at y1 (a mansard, a curb), leaving out
## the side whose outward x or z is `open_side` (Vector2 of the side's
## normal, or zero for none).
func curb(f: Transform3D, lo: Vector2, hi: Vector2, y0: float, y1: float, inset: float, col: Color,
		open_side := Vector2.ZERO) -> void:
	var corners := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
	var inner := [Vector2(lo.x + inset, lo.y + inset), Vector2(hi.x - inset, lo.y + inset),
		Vector2(hi.x - inset, hi.y - inset), Vector2(lo.x + inset, hi.y - inset)]
	var sides := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for k in 4:
		var side: Vector2 = sides[k]
		if side == open_side:
			continue
		var p0: Vector2 = corners[k]
		var p1: Vector2 = corners[(k + 1) % 4]
		var q0: Vector2 = inner[k]
		var q1: Vector2 = inner[(k + 1) % 4]
		# Along an open side's neighbours the slope runs to the wall.
		if sides[(k + 3) % 4] == open_side:
			q0 = q0 + open_side * inset
		if sides[(k + 1) % 4] == open_side:
			q1 = q1 + open_side * inset
		_roof_quad(f, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(q1.x, y1, q1.y), Vector3(q0.x, y1, q0.y), col)


## A bell roof lofted over a rectangle 2ax by 2az at y0, h high: the
## sides swell out of the eave and close to a point, s(t) = (1 - t^1.8)^0.7.
func bell(f: Transform3D, c: Vector3, ax: float, az: float, h: float, col: Color, rings := 14) -> void:
	var prev: Array[Vector3] = []
	for k in rings + 1:
		var t := float(k) / rings
		var s := pow(maxf(1.0 - pow(t, 1.8), 0.0), 0.7)
		var y := c.y + h * t
		var ring: Array[Vector3] = [Vector3(c.x - ax * s, y, c.z - az * s), Vector3(c.x + ax * s, y, c.z - az * s),
			Vector3(c.x + ax * s, y, c.z + az * s), Vector3(c.x - ax * s, y, c.z + az * s)]
		if not prev.is_empty():
			for j in 4:
				var a := prev[j]
				var b := prev[(j + 1) % 4]
				var cc := ring[(j + 1) % 4]
				var d := ring[j]
				var mid := (a + b + cc + d) / 4.0
				var out := Vector3(mid.x - c.x, 0.0, mid.z - c.z)
				var n := (b - a).cross(d - a).normalized()
				if n.dot(out) < 0.0:
					n = -n
				if k == rings:
					m.tri("wall", f * a, f * b, f * cc, (f.basis * n).normalized(), col)
				else:
					m.quad("wall", f * a, f * b, f * cc, f * d, (f.basis * n).normalized(), col)
		prev = ring


## A gable's triangle and its raking cornices: base width w centred at
## c (the base's middle, on the face), rise h, the rakes standing out
## `out`. The face is brick (col_face), the cornices trim.
func pediment(f: Transform3D, c: Vector3, w: float, h: float, depth: float, col_face: Color, trim: Color,
		out := 0.45) -> void:
	var nf := (f.basis * Vector3(0, 0, 1)).normalized()
	m.tri("wall", f * (c + Vector3(-w / 2.0, 0, 0)), f * (c + Vector3(0, h, 0)), f * (c + Vector3(w / 2.0, 0, 0)), nf, col_face)
	var ang := atan2(h, w / 2.0)
	var rake := sqrt(h * h + w * w / 4.0)
	for s: float in [-1.0, 1.0]:
		var mid := c + Vector3(s * w / 4.0, h / 2.0, 0)
		var up := Vector3(s * sin(ang), cos(ang), 0)
		# The raking corona and its crown, standing over the roof slope.
		box_rz("wall", f, mid + up * 0.16 + Vector3(0, 0, out / 2.0 - depth / 2.0), Vector3(rake + 0.4, 0.3, out + depth), -s * ang, trim)
		box_rz("wall", f, mid + up * 0.34 + Vector3(0, 0, out / 2.0 - depth / 2.0 + 0.03), Vector3(rake + 0.5, 0.08, out + depth + 0.08), -s * ang, trim)
		# Its modillions.
		var nb := int(rake / 0.55)
		for k in nb:
			var t := (k + 0.5) / nb
			var p := c + Vector3(s * w / 2.0 * (1.0 - t), h * t, 0) - up * 0.02
			box_rz("wall", f, p + Vector3(0, -0.02, 0.18), Vector3(0.09, 0.1, 0.36), -s * ang, trim)


## ---- turned work and iron ------------------------------------------------

## A turned post or baluster from foot to foot + h along y, in frame f:
## a square base, a vase, rings, a neck and a square cap; r its greatest
## radius.
func turned(key: String, f: Transform3D, foot: Vector3, h: float, r: float, col: Color, sides := 8) -> void:
	var sq := r * 1.7
	box(key, f, foot + Vector3(0, h * 0.09, 0), Vector3(sq, h * 0.18, sq), col)
	# [from, to, r_bottom, r_top] as shares of h and r.
	for seg: Array in [[0.18, 0.22, 0.75, 0.75], [0.22, 0.48, 0.7, 1.0], [0.48, 0.66, 1.0, 0.45], [0.66, 0.70, 0.7, 0.7],
			[0.70, 0.84, 0.42, 0.55], [0.84, 0.88, 0.75, 0.75]]:
		var y0 := h * float(seg[0])
		var y1 := h * float(seg[1])
		m.cylinder(key, f * Transform3D(Basis(), foot + Vector3(0, (y0 + y1) / 2.0, 0)), r * float(seg[2]), r * float(seg[3]),
			y1 - y0, sides, col)
	box(key, f, foot + Vector3(0, h * 0.94, 0), Vector3(sq, h * 0.12, sq), col)


## A run of iron railing from a to b (feet), h tall: rails, bars, a
## finial now and then, a circle between each pair of posts.
func railing(f: Transform3D, a: Vector3, b: Vector3, h: float, col: Color, spacing := 0.11) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.05:
		return
	var dir := along / length
	m.bar("iron", f * (a + Vector3(0, h, 0)), f * (b + Vector3(0, h, 0)), 0.022, 6, col)
	m.bar("iron", f * (a + Vector3(0, 0.08, 0)), f * (b + Vector3(0, 0.08, 0)), 0.015, 6, col)
	m.bar("iron", f * (a + Vector3(0, h - 0.18, 0)), f * (b + Vector3(0, h - 0.18, 0)), 0.01, 5, col)
	var n := int(length / spacing)
	for k in n + 1:
		var p := a + dir * (length * k / maxi(n, 1))
		m.bar("iron", f * p, f * (p + Vector3(0, h, 0)), 0.008, 4, col)
		if k % 4 == 2:
			# A scroll: a ring of iron between the rails.
			var side := dir.cross(Vector3.UP).normalized()
			var cf := f * Transform3D(Basis(dir, side.cross(dir), side).orthonormalized(), p + Vector3(0, h * 0.45, 0))
			for j in 8:
				var a0 := TAU * j / 8.0
				var a1 := TAU * (j + 1) / 8.0
				m.bar("iron", cf * Vector3(cos(a0) * 0.1, sin(a0) * 0.1, 0), cf * Vector3(cos(a1) * 0.1, sin(a1) * 0.1, 0),
					0.007, 4, col)
		if k % 8 == 0:
			m.sphere("iron", f * Transform3D(Basis(), p + Vector3(0, h + 0.05, 0)), 0.04, 6, col)
