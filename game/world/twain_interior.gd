class_name TwainInterior
extends RefCounted
## Inside the Clemens house as the family lived in it in the 1880s.
##
## The first floor: the hall, its walls stencilled silver on red over a
## high dado of carved walnut, its ceiling a lattice of stars, the stair
## rising in its south-west corner round a landing to the gallery above;
## the library to the west of it with the carved mantel from Ayton Castle
## across its east wall, shelves round it, the alcove's window seat and
## the conservatory beyond its glazed south end; the dining room, its
## walls in gilt paper like tooled leather, the window over its
## fireplace; the drawing room, salmon pink stencilled in silver, the
## piano and the pier glass; the mahogany guest room in the octagon with
## its dressing room and bath.
##
## The second floor: the Clemenses' bedroom with the carved bed from
## Venice, the school room over the library, Susy's room, Clara and
## Jean's, the Langdon guest room. The third: the billiard room under
## the south gable where Clemens wrote, its balcony door, and the stair
## hall. Doors into the rooms not furnished (the baths, the offices over
## the kitchen, the servants' rooms) stand shut.
##
## All in the survey's feet and frame (see TwainHouse). Art only.

const FT := TwainHouse.FT
const F2 := TwainHouse.F2
const F3 := TwainHouse.F3

const WALNUT := Color(0.30, 0.17, 0.09)
const MAHOGANY := Color(0.36, 0.13, 0.07)
const OAK := Color(0.52, 0.34, 0.18)
const CEIL := Color(0.86, 0.82, 0.72)
const PLASTER := Color(0.84, 0.79, 0.68)
const GILT := Color(0.76, 0.60, 0.30)
const BRASS := Color(0.72, 0.58, 0.30)
const MARBLE := Color(0.84, 0.82, 0.77)
const LINEN := Color(0.92, 0.90, 0.84)
const PLUSH := Color(0.40, 0.08, 0.08)
const GREEN_BAIZE := Color(0.10, 0.34, 0.16)
const DOOR_H := 8.0
const BASEMENT := -9.44       # the basement's floor (the survey's -9'-5 1/4")
const TO_ROOF := -1.0         # a room's or wall's top given as this: up to the roof
const ATTIC := 34.75          # the third floor's ceiling, where the roof allows

## The stair's geometry: its well in the hall's south-west corner, the
## flights running north and south in two bands either side of a narrow
## gap, a landing at the south end at each half storey: up south on the
## east band, up north on the west.
const WELL_X0 := 72.65
const WELL_X1 := 85.4
const LAND_X := 76.4
const BAND_W := Vector2(56.2, 60.2)     # the west band (going up north)
const BAND_E := Vector2(61.2, 65.2)     # the east band (going up south)

static var hs: TwainHouse
static var k: CourthouseKit


static func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


static func w(sx: float, sz: float, y := 0.0) -> Vector3:
	return TwainHouse.w(sx, sz, y)


static func h(y: float) -> float:
	return TwainHouse.h(y)


## A frame standing at a survey point, y feet up, its local +z facing
## the survey direction `face`.
static func at(sx: float, sz: float, y: float, face: Vector2) -> Transform3D:
	var d := TwainHouse.w2(face) - TwainHouse.w2(Vector2.ZERO)
	return Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), w(sx, sz, y))


static func build(house: TwainHouse) -> void:
	hs = house
	k = house.k
	_floors()
	_partitions()
	_rooms()
	_stairs()


## The furniture, into a mesh of its own.
static func furnish() -> void:
	_hall()
	_library()
	_dining_room()
	_drawing_room()
	_guest_rooms()
	_conservatory()
	_bedrooms()
	_billiard_room()


## ---- floors ----------------------------------------------------------------

static func _floors() -> void:
	var oak := c(OAK, CourthouseKit.K_OAK)
	var ceil := c(CEIL, CourthouseKit.K_PLASTER)
	var p := TwainHouse.perimeter()
	var outline: Array[Vector2] = []
	for q: Vector2 in p:
		outline.append(q)
	# The first floor on its fill, down to the lawn.
	hs.floor_poly(outline, 0.0, oak, c(TwainHouse.STONE, CourthouseKit.K_STONE), -TwainHouse.GROUND)
	# The conservatory's, the pantry's, the service wing's.
	var cons: Array[Vector2] = [Vector2(TwainHouse.MX0, TwainHouse.MZ0 + 0.2)]
	for i in 13:
		cons.append(TwainHouse._arc_point(TwainHouse.CONS_C, TwainHouse.CONS_R, -90.0 - 180.0 * i / 12.0))
	cons.append(Vector2(TwainHouse.MX0, 55.5))
	hs.floor_poly(cons, 0.0, c(Color(0.62, 0.30, 0.22), CourthouseKit.K_TILE), ceil, -TwainHouse.GROUND)
	var pantry: Array[Vector2] = []
	for i in 10:
		pantry.append(TwainHouse._arc_point(TwainHouse.PANTRY_C, TwainHouse.PANTRY_R, 180.0 + 90.0 * i / 9.0))
	pantry.append(Vector2(113.0, 22.3))
	pantry.append(Vector2(113.0, TwainHouse.MZ0))
	hs.floor_poly(pantry, 0.0, oak, ceil, 1.0)
	hs.floor_poly(pantry, BASEMENT, c(TwainHouse.STONE, CourthouseKit.K_STONE), c(TwainHouse.STONE, CourthouseKit.K_STONE),
		BASEMENT - TwainHouse.GROUND)
	var wing: Array = TwainHouse.WING_PLAN.duplicate()
	hs.floor_poly(wing, 0.0, oak, ceil, 1.0)
	hs.floor_poly(wing, BASEMENT, c(TwainHouse.STONE, CourthouseKit.K_STONE), c(TwainHouse.STONE, CourthouseKit.K_STONE),
		BASEMENT - TwainHouse.GROUND)
	hs.floor_poly(wing, 10.8, oak, ceil, 1.0)
	# The upper floors, their stair well cut: each in two halves, split
	# through the well, so neither has a hole in it.
	var hole := PackedVector2Array([Vector2(WELL_X0, BAND_W.x - 0.3), Vector2(WELL_X1, BAND_W.x - 0.3), Vector2(WELL_X1, BAND_E.y),
		Vector2(WELL_X0, BAND_E.y)])
	var rect := PackedVector2Array([Vector2(TwainHouse.MX0, TwainHouse.MZ0), Vector2(TwainHouse.MX1, TwainHouse.MZ0),
		Vector2(TwainHouse.MX1, TwainHouse.MZ1), Vector2(TwainHouse.MX0, TwainHouse.MZ1)])
	# The third floor stops at the walls' inner faces, under the eaves.
	var attic := PackedVector2Array([Vector2(TwainHouse.MX0 + 1.0, TwainHouse.MZ0 + 1.0), Vector2(TwainHouse.MX1 - 1.0, TwainHouse.MZ0 + 1.0),
		Vector2(TwainHouse.MX1 - 1.0, TwainHouse.MZ1 - 1.0), Vector2(TwainHouse.MX0 + 1.0, TwainHouse.MZ1 - 1.0)])
	var third: Array = TwainHouse.meet(hs.roof_higher(F3 + 1.0), attic)
	for level: Array in [[F2, [p]], [F3, third]]:
		var y := float(level[0])
		var shapes: Array = level[1]
		for half: PackedVector2Array in [TwainHouse.under(Vector3(1, 0, -78.9), Vector3.ZERO), TwainHouse.under(Vector3.ZERO, Vector3(1, 0, -78.9))]:
			for piece: PackedVector2Array in TwainHouse.cut(TwainHouse.meet(shapes, half), hole):
				var pts: Array[Vector2] = []
				for q: Vector2 in piece:
					pts.append(q)
				hs.floor_poly(pts, y, oak, ceil, 1.0)
	# Ceilings over the drawing room's bay and the dressing room's round,
	# under their roofs.
	var towers := TwainHouse.tower_plans()
	# The dressing room's round, under its cone.
	var pts: Array = []
	for q: Vector2 in towers[2]:
		pts.append(q)
	hs.floor_poly(pts, TwainHouse.SOUTH_TOP - 0.05, ceil, ceil, 0.4)


## ---- walls between rooms ----------------------------------------------------

## A partition from a to b (survey plan) from y0 to y1 feet (y1 TO_ROOF: up
## to the roof), t feet thick, plastered; its doors [survey point, width,
## open]: an open door stands swung back into the room, a shut one fills
## its opening. The doors join the house's openings, so the rooms either
## side case them.
static func part(a: Vector2, b: Vector2, y0: float, y1: float, doors: Array = [], t := 0.5) -> void:
	for d: Array in doors:
		var p := d[0] as Vector2
		hs.ops.append({"at": p, "w": float(d[1]), "sill": y0, "head": y0 + DOOR_H, "kind": "idoor" if bool(d[2]) else "ishut",
			"shape": "flat", "hood": false, "id": hs.ops.size()})
	var side := a + (b - a).normalized().orthogonal()
	var fr := TwainHouse.frame(a, b, side)
	var f: Transform3D = (fr[0] as Transform3D) * Transform3D(Basis(), Vector3(0, 0, t * FT / 2.0))
	var length: float = fr[1]
	var plaster := c(PLASTER, CourthouseKit.K_PLASTER)
	var mine := hs.ops_on(fr[0] as Transform3D, length, y0, y0 + DOOR_H + 0.5, 0.4)
	if y1 != TO_ROOF and not _roof_low(a, b, y1):
		k.wall("wall", f, 0.0, length, h(y0), h(y1), t * FT, plaster, mine, 1000.0)
	else:
		_to_roof(f, a, b, length, y0, t * FT, plaster, mine, "wall", true, h(y1) if y1 != TO_ROOF else INF)
	for o: Dictionary in mine:
		var kind := str(o["kind"])
		if kind != "idoor" and kind != "ishut":
			continue
		var u := float(o["u"])
		var wd := float(o["w"])
		var y := float(o["y0"])
		var leaf_h := float(o["yt"]) - y - 0.02
		var wood := c(WALNUT.lightened(0.05), CourthouseKit.K_WOOD)
		hs.doors.append({"center": f * Vector3(u, y + (float(o["yt"]) - y) / 2.0, -t * FT / 2.0), "normal": f.basis.z, "along": f.basis.x,
			"width": wd, "y0": y, "y1": float(o["yt"]), "outside": false, "open": kind == "idoor"})
		if kind == "ishut":
			k.door_leaf(f, Vector3(u, y, -t * FT / 2.0), wd - 0.04, leaf_h, wood)
			k.solid(f, Vector3(u, y + leaf_h / 2.0, -t * FT / 2.0), Vector3(wd, leaf_h, t * FT))
		elif wd > 1.4:
			# A wide opening has pocket doors, slid into the wall: only their
			# edges show in the jambs.
			for sd: float in [-1.0, 1.0]:
				k.box("wall", f, Vector3(u + sd * (wd / 2.0 - 0.03), y + leaf_h / 2.0, -t * FT / 2.0), Vector3(0.06, leaf_h, 0.04), wood)
		else:
			var hinge := Vector3(u - wd / 2.0 + 0.06, y, 0.0)
			var leaf := f * Transform3D(Basis(Vector3.UP, -PI / 2.0), hinge)
			k.door_leaf(leaf, Vector3(wd / 2.0, 0, 0), wd - 0.04, leaf_h, wood)
			hs.items.append({"name": "door", "xf": leaf * Transform3D(Basis(), Vector3(wd / 2.0, leaf_h / 2.0, 0)),
				"size": Vector3(wd - 0.04, leaf_h, 0.06), "kind": "door", "backed": false})


## A wall on frame f from u 0 to length whose top follows the roof over
## the line a-b: built in strips a foot wide.
static func _to_roof(f: Transform3D, a: Vector2, b: Vector2, length: float, y0: float, t: float, col: Color, mine: Array, key: String,
		solid: bool, cap := INF) -> void:
	var strips := maxi(1, int(length / (FT * 0.4)))
	# The frame runs from whichever end its x points away from.
	var o := Vector2(f.origin.x, f.origin.z)
	if o.distance_to(TwainHouse.w2(b)) < o.distance_to(TwainHouse.w2(a)):
		var swap := a
		a = b
		b = swap
	for i in strips:
		var u0 := length * i / strips
		var u1 := length * (i + 1) / strips
		var t0 := float(i) / strips
		var t1 := float(i + 1) / strips
		var side := (b - a).normalized().orthogonal() * (t / FT / 2.0 + 0.1)
		var roof := ATTIC
		for tt: float in [t0, (t0 + t1) / 2.0, t1]:
			for sd: float in [-1.0, 1.0]:
				roof = minf(roof, hs.roof_y(a.lerp(b, tt) + side * sd))
		roof -= 0.1
		if roof < y0 + 0.2:
			continue
		k.wall(key, f, u0, u1, h(y0), minf(h(roof) - 0.03, cap), t, col, mine, 1000.0 if solid else -1000.0)


## Whether the roof comes lower than y1 feet anywhere along a-b (or just
## either side of it).
static func _roof_low(a: Vector2, b: Vector2, y1: float) -> bool:
	var n := (b - a).normalized().orthogonal() * 0.6
	var steps := maxi(2, int(a.distance_to(b) / 1.0))
	for i in steps + 1:
		var q := a.lerp(b, float(i) / steps)
		for sd: float in [-1.0, 0.0, 1.0]:
			var r := hs.roof_y(q + n * sd)
			if r > -100.0 and r < y1 + 0.3:
				return true
	return false


static func _partitions() -> void:
	var X0 := TwainHouse.MX0 + 1.0
	var X1 := TwainHouse.MX1 - 1.0
	var Z0 := TwainHouse.MZ0 + 1.0
	var Z1 := TwainHouse.MZ1 - 1.0
	var zp := 55.95
	var cy := F2 - 1.0
	# The first floor.
	part(Vector2(X0, zp), Vector2(X1, zp), 0.0, cy, [[Vector2(61.0, zp), 3.0, true], [Vector2(84.3, zp), 4.4, true],
		[Vector2(92.0, zp), 3.6, true], [Vector2(103.5, zp), 7.0, true]])
	part(Vector2(88.0, Z0), Vector2(88.0, zp), 0.0, cy, [[Vector2(88.0, 47.6), 8.0, true]])
	part(Vector2(95.95, zp), Vector2(95.95, Z1), 0.0, cy, [[Vector2(95.95, 61.2), 3.2, true], [Vector2(95.95, 78.0), 3.2, true]])
	part(Vector2(WELL_X0, zp), Vector2(WELL_X0, 70.8), 0.0, cy, [[Vector2(WELL_X0, 68.6), 3.0, true]])
	part(Vector2(52.2, 70.8), Vector2(75.5, 70.8), 0.0, cy, [[Vector2(57.5, 70.8), 2.8, true]])
	part(Vector2(75.5, 70.8), Vector2(75.5, Z1), 0.0, cy, [[Vector2(75.5, 74.2), 2.6, true]])
	part(Vector2(61.5, 70.8), Vector2(61.5, Z1), 0.0, cy, [[Vector2(61.5, 77.0), 2.6, true]])
	# The butler's pantry's wall to the kitchen, its door.
	part(Vector2(112.8, 22.6), Vector2(112.8, TwainHouse.MZ0), 0.0, 7.6, [[Vector2(112.8, 35.0), 3.0, true]])
	# The second floor.
	var y2 := F2
	var cy2 := F3 - 1.0
	part(Vector2(X0, zp), Vector2(X1, zp), y2, cy2, [[Vector2(62.6, zp), 2.8, true],
		[Vector2(91.0, zp), 3.0, true], [Vector2(106.0, zp), 2.8, false]])
	part(Vector2(79.3, Z0), Vector2(79.3, zp), y2, cy2)
	part(Vector2(87.0, Z0), Vector2(87.0, zp), y2, cy2, [[Vector2(87.0, 51.5), 2.6, true]])
	part(Vector2(100.75, Z0), Vector2(100.75, zp), y2, cy2)
	part(Vector2(WELL_X0, zp), Vector2(WELL_X0, 70.8), y2, cy2, [[Vector2(WELL_X0, 68.6), 3.0, true]])
	part(Vector2(52.2, 70.8), Vector2(96.95, 70.8), y2, cy2, [[Vector2(60.0, 70.8), 2.6, false], [Vector2(80.0, 70.8), 3.0, true],
		[Vector2(91.0, 70.8), 2.8, false]])
	part(Vector2(67.7, 70.8), Vector2(67.7, Z1), y2, cy2)
	part(Vector2(85.65, 70.8), Vector2(85.65, Z1), y2, cy2)
	part(Vector2(96.95, zp), Vector2(96.95, Z1), y2, cy2, [[Vector2(96.95, 62.6), 3.2, true]])
	part(Vector2(96.95, 58.5), Vector2(X1, 58.5), y2, cy2, [[Vector2(108.3, 58.5), 2.6, false]])
	# The third floor: the billiard room's end, its wall to the stair
	# hall, the hall's walls, each up to the roof; the billiard room's
	# knee walls under the slopes.
	var y3 := F3
	part(Vector2(89.5, Z0), Vector2(89.5, zp), y3, -1.0)
	part(Vector2(TwainHouse.DECK_X, zp), Vector2(97.0, zp), y3, -1.0, [[Vector2(80.0, zp), 2.8, true], [Vector2(93.5, zp), 2.8, true]])
	part(Vector2(WELL_X0, zp), Vector2(WELL_X0, 67.45), y3, -1.0)
	part(Vector2(TwainHouse.DECK_X, 67.45), Vector2(WELL_X0, 67.45), y3, -1.0, [[Vector2(69.0, 67.45), 2.6, false]])
	part(Vector2(WELL_X0, 67.45), Vector2(WELL_X0, Z1), y3, -1.0)
	part(Vector2(WELL_X0, 70.6), Vector2(97.0, 70.6), y3, -1.0, [[Vector2(86.0, 70.6), 2.6, false]])
	part(Vector2(WELL_X0, 76.25), Vector2(97.0, 76.25), y3, -1.0)
	part(Vector2(97.0, zp), Vector2(97.0, Z1), y3, -1.0, [[Vector2(97.0, 64.0), 2.8, false]])


## ---- the rooms' finishes ------------------------------------------------------

## The finish round a room: poly (survey plan, its inner faces) from y0 to
## y1 feet (y1 TO_ROOF: up to the roof). Its walls in `wall` on `key` (the
## stencil or the plain wall), a dado `dado` feet high in `dado_col`, a
## skirting and a picture moulding; each opening on its sides cased and
## its reveal lined.
static func room(poly: Array, y0: float, y1: float, key: String, wall: Color, dado := 0.0, dado_col := WALNUT, label := "") -> void:
	if label != "":
		hs.rooms.append({"name": label, "poly": PackedVector2Array(poly), "y0": y0, "y1": y1})
	var p := PackedVector2Array(poly)
	var cw := TwainHouse.signed_area(p) < 0.0
	var wood := c(dado_col, CourthouseKit.K_WOOD)
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		if a.distance_to(b) < 0.3:
			continue
		var fr := TwainHouse.frame(a, b, TwainHouse.inside_of(a, b, cw))
		var f0: Transform3D = fr[0]
		var length: float = fr[1]
		var f := f0 * Transform3D(Basis(), Vector3(0, 0, 0.012))
		var top := y1
		# The openings of this storey only: up to the ceiling, or under the roof.
		var mine := hs.ops_on(f0, length, y0, y1 if y1 != TO_ROOF else ATTIC, 1.6)
		var low := y1 != TO_ROOF and _roof_low(a, b, y1)
		if y1 != TO_ROOF and not low:
			k.wall(key, f, 0.0, length, h(y0), h(y1), 0.02, wall, mine, -1000.0)
		else:
			_to_roof(f, a, b, length, y0, 0.02, wall, mine, key, false, h(y1) if y1 != TO_ROOF else INF)
			top = ATTIC
		if dado > 0.0 and y1 == TO_ROOF:
			# Under the roof the dado follows it down where it is low; its
			# cap and panels are left out there.
			_to_roof(f0 * Transform3D(Basis(), Vector3(0, 0, 0.03)), a, b, length, y0, 0.03, wood, mine, "wall", false, h(y0 + dado))
		elif dado > 0.0:
			var fd := f0 * Transform3D(Basis(), Vector3(0, 0, 0.03))
			k.wall("wall", fd, 0.0, length, h(y0), h(y0 + dado), 0.03, wood, mine, -1000.0)
			k.wall("wall", f0 * Transform3D(Basis(), Vector3(0, 0, 0.06)), 0.0, length, h(y0 + dado) - 0.06, h(y0 + dado) + 0.012, 0.05,
				c(dado_col.darkened(0.2), CourthouseKit.K_WOOD), mine, -1000.0)
			# Panels on the dado: a raised field every two feet.
			var n := int(length / (2.2 * FT))
			for j in n:
				var u := (j + 0.5) * length / n
				var clear := true
				for o: Dictionary in mine:
					if absf(u - float(o["u"])) < float(o["w"]) / 2.0 + 0.35 and float(o["y0"]) < h(y0 + dado):
						clear = false
				if clear:
					k.box("wall", f0, Vector3(u, h(y0 + dado / 2.0), 0.045), Vector3(length / n - 0.14, dado * FT - 0.28, 0.02),
						c(dado_col.lightened(0.08), CourthouseKit.K_WOOD))
		# The skirting and, near the ceiling, a picture moulding.
		k.wall("wall", f0 * Transform3D(Basis(), Vector3(0, 0, 0.05)), 0.0, length, h(y0), h(y0) + 0.18, 0.04,
			c(dado_col, CourthouseKit.K_WOOD), mine, -1000.0)
		if y1 != TO_ROOF and not low:
			k.box("wall", f0, Vector3(length / 2.0, h(y1) - 0.35, 0.03), Vector3(length, 0.05, 0.04), c(GILT.darkened(0.2), CourthouseKit.K_PAINT))
			k.box("wall", f0, Vector3(length / 2.0, h(y1) - 0.06, 0.05), Vector3(length, 0.12, 0.1), c(dado_col, CourthouseKit.K_WOOD))
		for o: Dictionary in mine:
			_casing(f0, o, dado_col)


## The casing round an opening from the room's side, and its reveal
## through the wall lined in the same wood.
static func _casing(f: Transform3D, o: Dictionary, wood_col: Color) -> void:
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	var u := float(o["u"])
	var wd := float(o["w"])
	var y0 := float(o["y0"])
	var yt := float(o["yt"])
	var ys := float(o["ys"])
	# A room lines its half of the opening's depth: the other half is the
	# next room's, or outside the sash.
	var inner := str(o["kind"]) == "idoor" or str(o["kind"]) == "ishut"
	var depth := (0.5 * FT if inner else TwainHouse.T * FT) / 2.0 - 0.01
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(u + s * (wd / 2.0 + 0.06), (y0 + ys) / 2.0, 0.05), Vector3(0.12, ys - y0 + 0.02, 0.05), wood)
		# The lining stands 5 mm inside the opening, clear of the wall's cut end.
		k.box("wall", f, Vector3(u + s * (wd / 2.0 - 0.015), (y0 + ys) / 2.0, -depth / 2.0 + 0.02), Vector3(0.02, ys - y0, depth), wood)
	if str(o["head"]) == "flat":
		k.box("wall", f, Vector3(u, yt + 0.08, 0.05), Vector3(wd + 0.36, 0.16, 0.06), wood)
		k.box("wall", f, Vector3(u, yt + 0.19, 0.07), Vector3(wd + 0.46, 0.06, 0.1), wood)
		k.box("wall", f, Vector3(u, yt - 0.015, -depth / 2.0 + 0.02), Vector3(wd - 0.01, 0.02, depth), wood)
	if str(o["kind"]) == "win":
		k.box("wall", f, Vector3(u, y0 - 0.03, 0.04), Vector3(wd + 0.3, 0.05, 0.14), wood)


## A room's ceiling decoration: a flat of the stencil's pattern under the
## floor above, at y feet, ribbed in wood where `ribs`.
static func ceiling(poly: Array, y: float, col: Color, ribs := 0.0) -> void:
	var flat := PackedVector2Array()
	for q: Vector2 in poly:
		flat.append(TwainHouse.w2(q))
	var idx := Geometry2D.triangulate_polygon(flat)
	var yy := h(y) - 0.012
	for i in range(0, idx.size(), 3):
		var a := flat[idx[i]]
		var b := flat[idx[i + 1]]
		var cc := flat[idx[i + 2]]
		k.m.tri("stencil", Vector3(a.x, yy, a.y), Vector3(b.x, yy, b.y), Vector3(cc.x, yy, cc.y), Vector3.DOWN, col)
	if ribs > 0.0:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q: Vector2 in poly:
			lo = lo.min(q)
			hi = hi.max(q)
		var wood := c(WALNUT, CourthouseKit.K_WOOD)
		var x := lo.x + ribs
		while x < hi.x - 0.5:
			k.box("wall", Transform3D(), (w(x, lo.y, y) + w(x, hi.y, y)) / 2.0 - Vector3(0, 0.07, 0), Vector3((hi.y - lo.y) * FT, 0.12, 0.1), wood)
			x += ribs
		var z := lo.y + ribs
		while z < hi.y - 0.5:
			k.box("wall", Transform3D(), (w(lo.x, z, y) + w(hi.x, z, y)) / 2.0 - Vector3(0, 0.07, 0), Vector3(0.1, 0.12, (hi.x - lo.x) * FT), wood)
			z += ribs


## A room's outline: the part of the rectangle x0..x1, z0..z1 (survey
## feet, from the partitions' faces) inside the outer walls.
static func region(x0: float, x1: float, z0: float, z1: float) -> Array:
	var r := PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	var best := PackedVector2Array()
	for q: PackedVector2Array in Geometry2D.intersect_polygons(r, _inner):
		if absf(TwainHouse.signed_area(q)) > absf(TwainHouse.signed_area(best)):
			best = q
	var out: Array = []
	for p: Vector2 in best:
		out.append(p)
	return out


static var _inner := PackedVector2Array()


static func _rooms() -> void:
	_inner = TwainHouse.inner_plan()
	var Z1 := TwainHouse.MZ1 - 1.0
	var cy := F2 - 1.0
	# The library: the alcove west, the south end open to the conservatory.
	room(region(0.0, 87.75, 0.0, 55.7), 0.0, cy, "stencil", TwainHouse.st(Color(0.14, 0.26, 0.28), 3), 3.0, WALNUT, "library")
	room(region(88.25, 200.0, 0.0, 55.7), 0.0, cy, "stencil", TwainHouse.st(Color(0.36, 0.13, 0.08), 4), 3.2, WALNUT, "dining room")
	var hall: Array[Vector2] = [Vector2(72.9, 56.2), Vector2(95.7, 56.2), Vector2(95.7, Z1), Vector2(75.75, Z1), Vector2(75.75, 71.05),
		Vector2(72.9, 71.05)]
	room(hall, 0.0, cy, "stencil", TwainHouse.st(Color(0.46, 0.10, 0.07), 1), 4.6, WALNUT, "hall")
	ceiling(hall, cy, TwainHouse.st(Color(0.40, 0.12, 0.08), 5), 4.0)
	var drawing := region(96.2, 200.0, 56.2, 100.0)
	room(drawing, 0.0, cy, "stencil", TwainHouse.st(Color(0.80, 0.52, 0.44), 2), 0.0, Color(0.55, 0.42, 0.30), "drawing room")
	ceiling(drawing, cy, TwainHouse.st(Color(0.86, 0.72, 0.62), 2))
	var octagon := region(0.0, 72.4, 56.2, 70.55)
	room(octagon, 0.0, cy, "stencil", TwainHouse.st(Color(0.48, 0.20, 0.14), 6), 0.0, MAHOGANY, "mahogany guest room")
	room(region(0.0, 61.25, 71.05, 100.0), 0.0, cy, "stencil", TwainHouse.st(Color(0.62, 0.58, 0.46), 6), 0.0, MAHOGANY, "dressing room")
	room(region(61.75, 75.25, 71.05, 100.0), 0.0, cy, "wall", c(Color(0.80, 0.78, 0.70), CourthouseKit.K_TILE), 4.0, WALNUT.lightened(0.1), "guest bath")
	# The second floor.
	var cy2 := F3 - 1.0
	room(region(0.0, 79.05, 0.0, 55.7), F2, cy2, "stencil", TwainHouse.st(Color(0.58, 0.60, 0.46), 6), 3.0, OAK.darkened(0.2), "school room")
	room(region(87.25, 100.5, 0.0, 55.7), F2, cy2, "stencil", TwainHouse.st(Color(0.50, 0.56, 0.62), 6), 0.0, WALNUT, "Langdon guest room")
	room(octagon, F2, cy2, "stencil", TwainHouse.st(Color(0.70, 0.60, 0.50), 6), 0.0, OAK.darkened(0.15), "Clara and Jean's room")
	room(region(67.95, 85.4, 71.05, 100.0), F2, cy2, "stencil", TwainHouse.st(Color(0.62, 0.52, 0.56), 6), 0.0, WALNUT, "Susy's room")
	room(region(97.2, TwainHouse.MX1 - 1.0, 58.75, 100.0), F2, cy2, "stencil", TwainHouse.st(Color(0.50, 0.36, 0.30), 6), 0.0, WALNUT, "the Clemenses' bedroom")
	var hall2: Array[Vector2] = [Vector2(72.9, 56.2), Vector2(96.7, 56.2), Vector2(96.7, 70.55), Vector2(72.9, 70.55)]
	# The rooms behind shut doors, and the west bath, finished plain.
	var paint := c(Color(0.80, 0.78, 0.70), CourthouseKit.K_PLASTER)
	room(region(79.55, 86.75, 0.0, 55.7), F2, cy2, "wall", c(Color(0.82, 0.82, 0.78), CourthouseKit.K_TILE), 4.0, WALNUT.lightened(0.1), "west bath")
	room(region(101.0, 200.0, 0.0, 55.7), F2, cy2, "wall", paint, 0.0, WALNUT, "the office")
	room(region(0.0, 67.45, 71.05, 100.0), F2, cy2, "wall", c(Color(0.82, 0.82, 0.78), CourthouseKit.K_TILE), 4.0, WALNUT.lightened(0.1), "south-east bath")
	room(region(85.9, 96.7, 71.05, 100.0), F2, cy2, "wall", paint, 0.0, WALNUT, "the small room")
	room(hall2, F2, cy2, "stencil", TwainHouse.st(Color(0.46, 0.10, 0.07), 1), 4.6, WALNUT, "upstairs hall")
	ceiling(hall2, cy2, TwainHouse.st(Color(0.40, 0.12, 0.08), 5), 4.0)
	# The third floor, as its plan draws it: the billiard room and the
	# guest room along the west front, the top hall round the stair well
	# with the Texas deck's doors, the storerooms and the servants' room
	# along the east front.
	var billiard: Array = [Vector2(TwainHouse.MX0 + 1.0, 39.3), Vector2(89.25, 39.3), Vector2(89.25, 55.45), Vector2(TwainHouse.MX0 + 1.0, 55.45)]
	var guest3: Array = [Vector2(89.75, 39.3), Vector2(TwainHouse.MX1 - 1.0, 39.3), Vector2(TwainHouse.MX1 - 1.0, 55.7), Vector2(89.75, 55.7)]
	var hall3: Array = [Vector2(TwainHouse.DECK_X + 0.5, 56.2), Vector2(96.75, 56.2), Vector2(96.75, 70.35), Vector2(72.9, 70.35),
		Vector2(72.9, 67.2), Vector2(TwainHouse.DECK_X + 0.5, 67.2)]
	var store_s: Array = [Vector2(TwainHouse.DECK_X + 0.5, 67.7), Vector2(72.4, 67.7), Vector2(72.4, TwainHouse.MZ1 - 1.0),
		Vector2(TwainHouse.DECK_X + 0.5, TwainHouse.MZ1 - 1.0)]
	var store_e: Array = [Vector2(72.9, 70.85), Vector2(96.75, 70.85), Vector2(96.75, 76.0), Vector2(72.9, 76.0)]
	var servants3: Array = [Vector2(97.25, 56.2), Vector2(TwainHouse.MX1 - 1.0, 56.2), Vector2(TwainHouse.MX1 - 1.0, TwainHouse.MZ1 - 1.0),
		Vector2(97.25, TwainHouse.MZ1 - 1.0)]
	var plain := c(Color(0.80, 0.78, 0.70), CourthouseKit.K_PLASTER)
	room(billiard, F3, -1.0, "stencil", TwainHouse.st(Color(0.62, 0.50, 0.30), 3), 3.0, WALNUT, "billiard room")
	room(guest3, F3, -1.0, "wall", plain, 0.0, WALNUT, "top guest room")
	room(hall3, F3, -1.0, "stencil", TwainHouse.st(Color(0.46, 0.10, 0.07), 1), 3.0, WALNUT, "top hall")
	room(store_s, F3, -1.0, "wall", plain, 0.0, WALNUT, "south storeroom")
	room(store_e, F3, -1.0, "wall", plain, 0.0, WALNUT, "east storeroom")
	room(servants3, F3, -1.0, "wall", plain, 0.0, WALNUT, "servants' room")
	for r: Array in [billiard, guest3, hall3, store_s, store_e, servants3]:
		_attic_ceiling(PackedVector2Array(r))
	# The service wing's rooms, seen through its windows.
	var wing: Array = []
	for q: Vector2 in Geometry2D.offset_polygon(PackedVector2Array(TwainHouse.WING_PLAN), -1.0, Geometry2D.JOIN_MITER)[0]:
		wing.append(q)
	# The wing's upper floor stands at 12 ft, a foot under the house's.
	room(wing, 0.0, 9.8, "wall", c(Color(0.78, 0.74, 0.64), CourthouseKit.K_PLASTER), 3.5, Color(0.40, 0.30, 0.20), "kitchen wing")
	hs.floor_poly(wing, 16.9, c(CEIL, CourthouseKit.K_PLASTER), c(CEIL, CourthouseKit.K_PLASTER), 0.3)
	room(wing, 10.8, 16.6, "wall", c(Color(0.78, 0.74, 0.64), CourthouseKit.K_PLASTER), 0.0, Color(0.40, 0.30, 0.20), "servants' rooms")
	var pantry: Array[Vector2] = [Vector2(112.8 - 14.5, TwainHouse.MZ0 - 0.2)]
	for a: float in TwainHouse.PANTRY_BREAKS:
		if a > 180.0:
			pantry.append(TwainHouse._arc_point(TwainHouse.PANTRY_C, TwainHouse.PANTRY_R - 1.0, a))
	pantry.append(Vector2(112.0, TwainHouse.MZ0 - 0.2))
	var below: Array = []
	for q: Vector2 in Geometry2D.offset_polygon(PackedVector2Array(TwainHouse.WING_PLAN), -1.0, Geometry2D.JOIN_MITER)[0]:
		below.append(q)
	room(below, BASEMENT, -1.0 - 0.01, "wall", c(Color(0.70, 0.66, 0.58), CourthouseKit.K_PLASTER), 0.0, Color(0.40, 0.30, 0.20),
		"basement")
	room(pantry, BASEMENT, -1.0 - 0.01, "wall", c(Color(0.70, 0.66, 0.58), CourthouseKit.K_PLASTER), 0.0, Color(0.40, 0.30, 0.20),
		"pantry basement")
	room(pantry, 0.0, 7.6, "wall", c(Color(0.80, 0.76, 0.64), CourthouseKit.K_PLASTER), 3.0, Color(0.40, 0.30, 0.20), "butler's pantry")


## A third-floor room's flat ceiling at ATTIC: where the roof stands
## higher than it (under the flat of the hip, or a gable's ridge).
static func _attic_ceiling(room_poly: PackedVector2Array) -> void:
	# Where the roof stands at least half a foot over the ceiling.
	var flat := Vector3(0, 0, ATTIC + 0.5)
	var high: Array = [hs.roof_rect]
	for pl: Vector3 in hs.hip_planes:
		high = TwainHouse.meet(high, TwainHouse.under(flat, pl))
	var pieces: Array = TwainHouse.meet(high, room_poly)
	for g: Dictionary in hs.gable_slopes:
		var up := TwainHouse.meet([g["poly"]], TwainHouse.under(flat, g["plane"] as Vector3))
		for hp: PackedVector2Array in high:
			up = TwainHouse.cut(up, hp)
		pieces.append_array(TwainHouse.meet(up, room_poly))
	var ceil := c(CEIL, CourthouseKit.K_PLASTER)
	for p: PackedVector2Array in pieces:
		var pts: Array = []
		for q: Vector2 in p:
			pts.append(q)
		hs.floor_poly(pts, ATTIC + 0.1, ceil, ceil, 0.1, false)


## ---- the stair ------------------------------------------------------------------

## Four flights round the well in the hall's south-west corner: up south
## along the west band to a landing at the south end, up north along the
## east band to the gallery; again from the second floor to the third.
## Walnut: moulded treads, a panelled string, turned balusters under a
## heavy rail, twisted columns at the well's corners rising floor to
## floor, a newel with a gas lamp at the foot.
static func _stairs() -> void:
	var half2 := F2 / 2.0
	var half3 := F2 + (F3 - F2) / 2.0
	_flight(WELL_X1, LAND_X, BAND_E, 0.0, half2)
	_flight(LAND_X, WELL_X1, BAND_W, half2, F2)
	_flight(WELL_X1, LAND_X, BAND_E, F2, half3)
	_flight(LAND_X, WELL_X1, BAND_W, half3, F3)
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	for y: float in [half2, half3]:
		var land: Array[Vector2] = [Vector2(WELL_X0, BAND_W.x), Vector2(LAND_X, BAND_W.x), Vector2(LAND_X, BAND_E.y), Vector2(WELL_X0, BAND_E.y)]
		hs.floor_poly(land, y, c(OAK, CourthouseKit.K_OAK), wood, 0.8)
		# The landing's rails: across the gap between the flights, along its
		# open side over the hall.
		_balustrade(w(LAND_X, BAND_W.y, y), w(LAND_X, BAND_E.x, y))
		_balustrade(w(WELL_X0, BAND_E.y, y), w(LAND_X, BAND_E.y, y))
	# The panelled block under the first landing.
	var b0 := w(WELL_X0, BAND_W.x, 0.0)
	var b1 := w(LAND_X, BAND_E.y, half2 - 0.8)
	k.block("wall", Transform3D(), (b0 + b1) / 2.0, (b1 - b0).abs(), wood)
	# The galleries' rails round the well at the second and third floors.
	for y: float in [F2, F3]:
		_balustrade(w(WELL_X0, BAND_E.y, y), w(WELL_X1, BAND_E.y, y))
	_balustrade(w(WELL_X1, BAND_W.y, F2), w(WELL_X1, BAND_E.x, F2))
	_balustrade(w(WELL_X1, BAND_W.y, F3), w(WELL_X1, BAND_E.y, F3))
	# The twisted columns at the well's corners, floor to floor.
	for y: Vector2 in [Vector2(0.0, F2 - 1.0), Vector2(F2, F3 - 1.0)]:
		for p: Vector2 in [Vector2(WELL_X1, BAND_W.y), Vector2(WELL_X1, BAND_E.x), Vector2(LAND_X, BAND_W.y), Vector2(LAND_X, BAND_E.x)]:
			_twist(w(p.x, p.y, y.x), h(y.y) - h(y.x))
	# The newel at the foot, its gas lamp of five globes.
	var foot := w(WELL_X1 + 0.5, BAND_E.y + 0.3, 0.0)
	k.block("wall", Transform3D(), foot + Vector3(0, 0.6, 0), Vector3(0.36, 1.2, 0.36), wood)
	k.box("wall", Transform3D(), foot + Vector3(0, 1.25, 0), Vector3(0.44, 0.1, 0.44), wood)
	_gasolier(foot + Vector3(0, 2.3, 0), 5, 0.3, false)
	k.m.bar("iron", foot + Vector3(0, 1.3, 0), foot + Vector3(0, 2.3, 0), 0.03, 6, c(BRASS, CourthouseKit.K_PAINT))


## One flight from x0 to x1 (survey feet, along the house) in the band
## (z0, z1), from y0 to y1 feet: a ramp underfoot, the treads drawn over
## it, a string each side, a rail on the open side.
static func _flight(x0: float, x1: float, band: Vector2, y0: float, y1: float) -> void:
	var zc := (band.x + band.y) / 2.0
	var wd := (band.y - band.x) * FT
	var a := w(x0, zc, y0)
	var b := w(x1, zc, y1)
	k.ramp(Transform3D(), a, b, wd - 0.05)
	var risers := int(round((y1 - y0) / 0.6))
	var tread_c := c(Color(0.42, 0.10, 0.08), CourthouseKit.K_CLOTH)
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var run := (b - a)
	var flat := Vector3(run.x, 0, run.z)
	var along := flat.normalized()
	var basis := Basis(Vector3.UP.cross(along).normalized(), Vector3.UP, along)
	for i in risers:
		var t := (i + 0.5) / risers
		var p := a.lerp(b, (i + 1.0) / risers)
		var step := Vector3(p.x, 0, p.z) - along * flat.length() / risers / 2.0
		var top := a.y + (b.y - a.y) * (i + 1.0) / risers
		var tall := (b.y - a.y) / risers
		k.box("wall", Transform3D(basis, Vector3(step.x, top - tall / 2.0, step.z)), Vector3.ZERO, Vector3(wd, tall, flat.length() / risers), tread_c)
		k.box("wall", Transform3D(basis, Vector3(step.x, top + 0.01, step.z) + along * 0.02), Vector3.ZERO, Vector3(wd + 0.04, 0.03,
			flat.length() / risers + 0.04), wood)
		t = t
	# The strings, and the flight's underside.
	var side := basis.x
	for s: float in [-1.0, 1.0]:
		var o := side * s * (wd / 2.0 + 0.04)
		var mid := (a + b) / 2.0 + o
		var tilt := Basis(side, -atan2(b.y - a.y, flat.length()))
		k.box("wall", Transform3D(tilt * basis, mid), Vector3.ZERO, Vector3(0.06, 0.4, a.distance_to(b)), wood)
	var under := Transform3D(Basis(side, -atan2(b.y - a.y, flat.length())) * basis, (a + b) / 2.0 - Vector3(0, 0.3, 0))
	k.box("wall", under, Vector3.ZERO, Vector3(wd, 0.05, a.distance_to(b)), c(CEIL, CourthouseKit.K_PLASTER))
	# The rails: on the east band both sides, on the west band the well's
	# side (its other side is the wall).
	var sides: Array[float] = [band.y]
	if band.x >= BAND_E.x:
		sides.append(band.x)
	for z: float in sides:
		_balustrade(w(x0, z, y0), w(x1, z, y1))


## A walnut balustrade from a to b (world, on the floor or the flight):
## turned balusters, a moulded rail, solid to the player.
static func _balustrade(a: Vector3, b: Vector3) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var rail_h := 0.95
	var length := a.distance_to(b)
	if length < 0.05:
		return
	k.m.bar("wall", a + Vector3(0, rail_h, 0), b + Vector3(0, rail_h, 0), 0.05, 6, wood)
	k.m.bar("wall", a + Vector3(0, 0.06, 0), b + Vector3(0, 0.06, 0), 0.04, 4, wood)
	var n := int(length / 0.16)
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxi(n, 1))
		k.turned("wall", Transform3D(), p + Vector3(0, 0.06, 0), rail_h - 0.06, 0.03, wood, 6)
	var d := (b - a).normalized()
	var flat := Vector3(d.x, 0, d.z).normalized()
	var basis := Basis(Vector3.UP.cross(flat).normalized(), Vector3.UP, flat)
	var tilt := Basis(basis.x, -asin(clampf(d.y, -1.0, 1.0)))
	k.solid(Transform3D(tilt * basis, (a + b) / 2.0 + Vector3(0, rail_h / 2.0, 0)), Vector3.ZERO, Vector3(0.1, rail_h, length))


## A twisted column of walnut from foot up `tall` metres: a square base,
## a shaft of two strands wound round a core, a carved capital.
static func _twist(foot: Vector3, tall: float) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	k.box("wall", Transform3D(), foot + Vector3(0, 0.45, 0), Vector3(0.24, 0.9, 0.24), wood)
	var y0 := 0.9
	var y1 := tall - 0.45
	k.m.cylinder("wall", Transform3D(Basis(), foot + Vector3(0, (y0 + y1) / 2.0, 0)), 0.035, 0.035, y1 - y0, 6, wood, false)
	var pitch := 0.28
	var steps := int((y1 - y0) / pitch * 10.0)
	for strand in 2:
		var prev := Vector3.ZERO
		for i in steps + 1:
			var t := float(i) / steps
			var a := TAU * (y1 - y0) * t / pitch + PI * strand
			var p := foot + Vector3(cos(a) * 0.04, y0 + (y1 - y0) * t, sin(a) * 0.04)
			if i > 0:
				k.m.bar("wall", prev, p, 0.032, 5, wood)
			prev = p
	k.box("wall", Transform3D(), foot + Vector3(0, tall - 0.3, 0), Vector3(0.22, 0.3, 0.22), wood)
	k.box("wall", Transform3D(), foot + Vector3(0, tall - 0.08, 0), Vector3(0.3, 0.16, 0.3), wood)
	k.solid(Transform3D(), foot + Vector3(0, tall / 2.0, 0), Vector3(0.16, tall, 0.16))


## ---- lamps -------------------------------------------------------------------------

## A gas chandelier hung from a ceiling point `top` (or standing, when
## `hanging` is false, its stem below): a brass stem, `arms` arms, each
## ending in a frosted tulip glass with its flame.
static func _gasolier(top: Vector3, arms: int, reach: float, hanging := true, drop := 0.9) -> void:
	var brass := c(BRASS, CourthouseKit.K_PAINT)
	var hub := top - Vector3(0, drop, 0) if hanging else top
	if hanging:
		item("gasolier", Transform3D(), top - Vector3(0, (drop + 0.15) / 2.0, 0), Vector3(reach * 2.0 + 0.1, drop + 0.15, reach * 2.0 + 0.1), "hanging")
		k.m.bar("iron", top, hub, 0.02, 6, brass)
		k.m.cylinder("iron", Transform3D(Basis(), top - Vector3(0, 0.04, 0)), 0.09, 0.12, 0.08, 10, brass)
	k.m.sphere("iron", Transform3D(Basis().scaled(Vector3(1, 0.7, 1)), hub), 0.08, 10, brass)
	for i in arms:
		var a := TAU * i / arms
		var out := Vector3(cos(a), 0, sin(a)) * reach
		k.m.bar("iron", hub, hub + out * 0.6 - Vector3(0, 0.06, 0), 0.012, 5, brass)
		k.m.bar("iron", hub + out * 0.6 - Vector3(0, 0.06, 0), hub + out + Vector3(0, 0.06, 0), 0.012, 5, brass)
		var cup := hub + out + Vector3(0, 0.1, 0)
		k.m.cylinder("lamp", Transform3D(Basis(), cup + Vector3(0, 0.07, 0)), 0.035, 0.07, 0.12, 8, Color(1, 1, 1))
		k.m.sphere("flame", Transform3D(Basis().scaled(Vector3(0.6, 1.4, 0.6)), cup + Vector3(0, 0.06, 0)), 0.018, 6, Color(1, 1, 1))
	hs.gaslight(hub + Vector3(0, 0.1, 0), 0.6 + 0.25 * arms, 7.0 + arms * 0.6)


## A gas bracket on a wall face: frame f (z into the room), at u, y metres.
static func _bracket_lamp(f: Transform3D, u: float, y: float) -> void:
	var brass := c(BRASS, CourthouseKit.K_PAINT)
	var p0 := f * Vector3(u, y, 0.02)
	var p1 := f * Vector3(u, y + 0.08, 0.28)
	k.m.cylinder("iron", Transform3D(f.basis * Basis(Vector3.RIGHT, PI / 2.0), f * Vector3(u, y, 0.02)), 0.06, 0.06, 0.03, 8, brass)
	k.m.bar("iron", p0, p1, 0.014, 5, brass)
	k.m.cylinder("lamp", Transform3D(Basis(), p1 + Vector3(0, 0.09, 0)), 0.035, 0.07, 0.12, 8, Color(1, 1, 1))
	k.m.sphere("flame", Transform3D(Basis().scaled(Vector3(0.6, 1.4, 0.6)), p1 + Vector3(0, 0.08, 0)), 0.018, 6, Color(1, 1, 1))
	hs.gaslight(p1 + Vector3(0, 0.15, 0), 0.5, 5.0, 0.2)


## ---- furniture --------------------------------------------------------------------

## A piece of furniture for the audit: its box (frame xf, middle c3,
## size), what it rests on ("floor", "wall" for what hangs on a wall,
## "rug", "hanging" from a ceiling), and whether its back stands against
## a wall.
static func item(label: String, xf: Transform3D, c3: Vector3, size: Vector3, kind := "floor", backed := false) -> void:
	hs.items.append({"name": label, "xf": xf * Transform3D(Basis(), c3), "size": size, "kind": kind, "backed": backed})


## What already stands against each wall: {wall key: [[from, to], ...]}
## along it, in metres.
static var _spans: Dictionary = {}


## A piece that backs onto a wall, set by rule rather than by hand: from
## its rough place and the way it faces (xf), the wall behind it is found
## among the rooms' outlines on that floor; the piece is turned square to
## it and set with its back (`back` metres behind its origin) against the
## wall's dado; then slid along the wall, the least distance, until it is
## clear of the doors and windows in that wall below its top and of what
## already stands there. `width` is its breadth along the wall, `top` its
## height in metres. The frame it ends in is returned; a piece with no
## wall behind it within 3 m, or no room on its wall, is left and noted.
static func snap(xf: Transform3D, back: float, width: float, top: float) -> Transform3D:
	var p := Vector2(xf.origin.x, xf.origin.z)
	var fwd := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
	var y_ft := (xf.origin.y - TwainHouse.FL) / FT
	var best := 1e9
	var wa := Vector2.ZERO
	var wb := Vector2.ZERO
	var q := Vector2.ZERO
	for r: Dictionary in hs.rooms:
		if absf(float(r["y0"]) - y_ft) > 0.5:
			continue
		var poly := r["poly"] as PackedVector2Array
		for i in poly.size():
			var a := TwainHouse.w2(poly[i])
			var b := TwainHouse.w2(poly[(i + 1) % poly.size()])
			var hit: Variant = Geometry2D.segment_intersects_segment(p + fwd * 0.3, p - fwd * 3.0, a, b)
			if hit == null:
				continue
			var d := p.distance_to(hit as Vector2)
			if d < best:
				best = d
				wa = a
				wb = b
				q = hit as Vector2
	if best > 1e8:
		push_warning("twain: no wall behind the piece at %s" % str(TwainAudit_where(xf.origin)))
		return xf
	var along := (wb - wa).normalized()
	var n := Vector2(-along.y, along.x)
	if n.dot(p - q) < 0.0:
		n = -n
	var length := wa.distance_to(wb)
	var t := (q - wa).dot(along)
	# What is in the way along this wall: openings (a door and its swing
	# with room to pass), and what already stands here.
	var blocks: Array = []
	for o: Dictionary in hs.ops:
		var op := TwainHouse.w2(o["at"] as Vector2)
		var off := absf((op - wa).dot(n))
		if off > 0.5:
			continue
		if float(o["sill"]) > y_ft + top / FT or float(o["head"]) < y_ft + 0.3:
			continue
		var ot := (op - wa).dot(along)
		var half := float(o["w"]) * FT / 2.0
		var kind := str(o["kind"])
		var margin := 0.45 if kind == "idoor" or kind == "door" or kind == "french" or kind == "open" else 0.08
		blocks.append([ot - half - margin, ot + half + margin])
	var key := "%.2f,%.2f,%.2f,%.2f,%d" % [wa.x, wa.y, wb.x, wb.y, roundi(y_ft)]
	for sp: Array in _spans.get(key, []):
		blocks.append([float(sp[0]) - 0.05, float(sp[1]) + 0.05])
	var fits := func(c: float) -> bool:
		if c - width / 2.0 < 0.03 or c + width / 2.0 > length - 0.03:
			return false
		for bl: Array in blocks:
			if c + width / 2.0 > float(bl[0]) and c - width / 2.0 < float(bl[1]):
				return false
		return true
	var tries: Array[float] = [t, width / 2.0 + 0.03, length - width / 2.0 - 0.03]
	for bl: Array in blocks:
		tries.append(float(bl[0]) - width / 2.0)
		tries.append(float(bl[1]) + width / 2.0)
	var chosen := INF
	for c: float in tries:
		if fits.call(c) and (chosen == INF or absf(c - t) < absf(chosen - t)):
			chosen = c
	if chosen == INF:
		push_warning("twain: no room on the wall for the piece at %s: wall %.2f m, wanted at %.2f, width %.2f, in the way %s"
			% [str(TwainAudit_where(xf.origin)), length, t, width, str(blocks)])
		chosen = t
	if not _spans.has(key):
		_spans[key] = []
	_spans[key].append([chosen - width / 2.0, chosen + width / 2.0])
	var o2 := wa + along * chosen + n * (back + 0.07)
	return Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(o2.x, xf.origin.y, o2.y))


static func TwainAudit_where(p: Vector3) -> String:
	return "(%.1f, %.1f) ft" % [TwainHouse.OX - p.z / FT, TwainHouse.OZ + p.x / FT]


## A box of furniture in a frame, drawn only.
static func fb(xf: Transform3D, c3: Vector3, size: Vector3, col: Color) -> void:
	k.box("wall", xf, c3, size, col)


## A box of furniture that the player cannot walk through.
static func fs(xf: Transform3D, c3: Vector3, size: Vector3, col: Color) -> void:
	k.block("wall", xf, c3, size, col)


static func table(xf: Transform3D, wd: float, dp: float, ht: float, wood_col: Color, cloth := Color(0, 0, 0, 0), round_top := false) -> void:
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	if round_top:
		k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(0, ht - 0.02, 0)), wd / 2.0, wd / 2.0, 0.04, 20, wood)
		k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(0, ht / 2.0, 0)), 0.06, 0.06, ht, 8, wood)
		k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.25, 0.12, 0.12, 8, wood)
		if cloth.a > 0.0:
			k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(0, ht - 0.12, 0)), wd / 2.0 + 0.1, wd / 2.0 + 0.02, 0.22, 20, cloth)
	else:
		fb(xf, Vector3(0, ht - 0.03, 0), Vector3(wd, 0.05, dp), wood)
		fb(xf, Vector3(0, ht - 0.12, 0), Vector3(wd - 0.1, 0.12, dp - 0.1), wood)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				k.turned("wall", xf, Vector3(sx * (wd / 2.0 - 0.07), 0, sz * (dp / 2.0 - 0.07)), ht - 0.15, 0.04, wood, 6)
		if cloth.a > 0.0:
			fb(xf, Vector3(0, ht + 0.005, 0), Vector3(wd + 0.3, 0.012, dp + 0.3), cloth)
			for s: float in [-1.0, 1.0]:
				fb(xf, Vector3(s * (wd / 2.0 + 0.15), ht - 0.12, 0), Vector3(0.012, 0.25, dp + 0.3), cloth)
				fb(xf, Vector3(0, ht - 0.12, s * (dp / 2.0 + 0.15)), Vector3(wd + 0.3, 0.25, 0.012), cloth)
	k.solid(xf, Vector3(0, ht / 2.0, 0), Vector3(wd, ht, dp))
	item("table", xf, Vector3(0, ht / 2.0, 0), Vector3(wd, ht, dp))


## A chair facing +z: legs, seat, a carved back.
static func chair(xf: Transform3D, wood_col: Color, seat_col: Color, tall := 1.05) -> void:
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			fb(xf, Vector3(sx * 0.2, 0.22, sz * 0.2), Vector3(0.04, 0.44, 0.04), wood)
	fb(xf, Vector3(0, 0.46, 0), Vector3(0.46, 0.06, 0.46), c(seat_col, CourthouseKit.K_CLOTH))
	fb(xf, Vector3(0, (0.46 + tall) / 2.0, -0.21), Vector3(0.44, tall - 0.46, 0.04), wood)
	fb(xf, Vector3(0, tall - 0.2, -0.19), Vector3(0.34, 0.26, 0.03), c(seat_col, CourthouseKit.K_CLOTH))
	k.m.sphere("wall", xf * Transform3D(Basis(), Vector3(-0.2, tall + 0.03, -0.21)), 0.035, 6, wood)
	k.m.sphere("wall", xf * Transform3D(Basis(), Vector3(0.2, tall + 0.03, -0.21)), 0.035, 6, wood)
	k.solid(xf, Vector3(0, 0.3, 0), Vector3(0.44, 0.6, 0.44))
	item("chair", xf, Vector3(0, tall / 2.0 + 0.02, -0.01), Vector3(0.46, tall + 0.04, 0.48))


## An armchair or a sofa facing +z, wd wide, in plush.
static func sofa(xf: Transform3D, wd: float, cloth: Color, wood_col := WALNUT) -> void:
	var cl := c(cloth, CourthouseKit.K_CLOTH)
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	fb(xf, Vector3(0, 0.22, 0), Vector3(wd, 0.24, 0.72), wood)
	fb(xf, Vector3(0, 0.4, 0.03), Vector3(wd - 0.1, 0.14, 0.66), cl)
	fb(xf, Vector3(0, 0.7, -0.3), Vector3(wd - 0.06, 0.62, 0.14), cl)
	for s: float in [-1.0, 1.0]:
		fb(xf, Vector3(s * (wd / 2.0 - 0.06), 0.56, 0.0), Vector3(0.12, 0.3, 0.7), cl)
		k.m.sphere("wall", xf * Transform3D(Basis(), Vector3(s * (wd / 2.0 - 0.06), 0.72, 0.28)), 0.07, 8, wood)
	k.solid(xf, Vector3(0, 0.45, 0), Vector3(wd, 0.9, 0.75))
	item("sofa" if wd > 1.0 else "armchair", xf, Vector3(0, 0.505, 0), Vector3(wd, 1.01, 0.74))


## Shelves of books against a wall, facing +z: a cornice over them.
static func bookcase(xf: Transform3D, wd: float, ht: float, rng: RandomNumberGenerator, wood_col := WALNUT) -> void:
	var dp := 0.38
	xf = snap(xf, dp / 2.0, wd + 0.12, ht + 0.12)
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	fs(xf, Vector3(0, ht / 2.0, -dp / 2.0 + 0.02), Vector3(wd, ht, 0.04), wood)
	for s: float in [-1.0, 1.0]:
		fb(xf, Vector3(s * (wd / 2.0 - 0.03), ht / 2.0, 0), Vector3(0.06, ht, dp), wood)
	fb(xf, Vector3(0, ht + 0.06, 0.02), Vector3(wd + 0.12, 0.12, dp + 0.08), wood)
	var shelves := int(ht / 0.36)
	var book_cols: Array[Color] = [Color(0.40, 0.08, 0.06), Color(0.12, 0.18, 0.12), Color(0.30, 0.20, 0.10), Color(0.10, 0.12, 0.22),
		Color(0.55, 0.40, 0.20), Color(0.20, 0.06, 0.05)]
	for i in shelves:
		var y := 0.1 + i * (ht - 0.1) / shelves
		fb(xf, Vector3(0, y, 0), Vector3(wd - 0.1, 0.03, dp - 0.02), wood)
		if i == 0:
			continue
		var x := -wd / 2.0 + 0.08
		while x < wd / 2.0 - 0.1:
			var bw := rng.randf_range(0.025, 0.06)
			var bh := rng.randf_range(0.2, 0.3)
			fb(xf, Vector3(x + bw / 2.0, y + 0.015 + bh / 2.0, 0.02), Vector3(bw - 0.004, bh, dp - 0.12),
				c(book_cols[rng.randi() % book_cols.size()].lightened(rng.randf_range(-0.05, 0.1)), CourthouseKit.K_CLOTH))
			x += bw
	k.solid(xf, Vector3(0, ht / 2.0, 0), Vector3(wd, ht, dp))
	item("bookcase", xf, Vector3(0, (ht + 0.12) / 2.0, 0.0), Vector3(wd + 0.12, ht + 0.12, dp), "floor", true)


## A fireplace against a wall, facing +z: hearth, the opening's iron and
## a coal fire, the mantel shelf on pilasters, an overmantel of `over`
## metres with a glass or panels.
static func fireplace(xf: Transform3D, wd: float, wood_col: Color, over: float, mirror := true, lit := true) -> void:
	var tall := 1.29 + (over + 0.07 if over > 0.0 else 0.0)
	xf = snap(xf, 0.13, wd + 0.3, tall)
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	var iron := c(Color(0.08, 0.07, 0.07), CourthouseKit.K_PAINT)
	item("fireplace", xf, Vector3(0, tall / 2.0, 0.0), Vector3(wd + 0.2, tall, 0.26), "floor", true)
	fs(xf, Vector3(0, 0.03, 0.3), Vector3(wd + 0.3, 0.06, 0.6), c(Color(0.45, 0.30, 0.22), CourthouseKit.K_TILE))
	for s: float in [-1.0, 1.0]:
		fs(xf, Vector3(s * (wd / 2.0 - 0.14), 0.6, 0.0), Vector3(0.28, 1.2, 0.26), wood)
	fb(xf, Vector3(0, 1.12, 0.0), Vector3(wd, 0.2, 0.26), wood)
	fb(xf, Vector3(0, 1.26, 0.05), Vector3(wd + 0.2, 0.06, 0.36), wood)
	fb(xf, Vector3(0, 0.5, -0.1), Vector3(wd - 0.56, 1.0, 0.04), iron)
	fb(xf, Vector3(0, 0.25, -0.02), Vector3(wd - 0.7, 0.18, 0.12), iron)
	if lit:
		k.m.sphere("flame", xf * Transform3D(Basis().scaled(Vector3(2.6, 0.9, 0.8)), Vector3(0, 0.38, -0.04)), 0.1, 8, Color(1, 1, 1))
		hs.gaslight(xf * Vector3(0, 0.5, 0.35), 0.5, 4.0, 0.15)
	# The brass fender.
	k.m.bar("iron", xf * Vector3(-wd / 2.0, 0.1, 0.55), xf * Vector3(wd / 2.0, 0.1, 0.55), 0.02, 6, c(BRASS, CourthouseKit.K_PAINT))
	if over > 0.0:
		for s: float in [-1.0, 1.0]:
			fb(xf, Vector3(s * (wd / 2.0 - 0.08), 1.29 + over / 2.0, 0.0), Vector3(0.12, over, 0.12), wood)
		fb(xf, Vector3(0, 1.29 + over, 0.02), Vector3(wd + 0.1, 0.14, 0.2), wood)
		if mirror:
			fb(xf, Vector3(0, 1.29 + over / 2.0, -0.02), Vector3(wd - 0.3, over - 0.2, 0.02), c(Color(0.20, 0.23, 0.24), CourthouseKit.K_ENAMEL))
		else:
			for i in 3:
				fb(xf, Vector3((i - 1) * (wd - 0.3) / 3.0, 1.29 + over / 2.0, -0.02), Vector3((wd - 0.4) / 3.0, over - 0.25, 0.04),
					c(wood_col.lightened(0.08), CourthouseKit.K_WOOD))
		# A clock and a pair of vases on the shelf.
		fb(xf, Vector3(0, 1.45, 0.08), Vector3(0.24, 0.3, 0.12), c(Color(0.12, 0.10, 0.08), CourthouseKit.K_ENAMEL))
		for s: float in [-1.0, 1.0]:
			k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(s * wd * 0.35, 1.42, 0.08)), 0.05, 0.03, 0.26, 10,
				c(Color(0.18, 0.28, 0.40), CourthouseKit.K_ENAMEL))


## A bed facing +z (its head at -z): wd wide, ln long, a headboard ht
## high, carved posts where `posts`.
static func bed(xf: Transform3D, wd: float, ln: float, ht: float, wood_col: Color, spread: Color, posts := 0.0) -> void:
	var top := maxf(ht + 0.16, posts + 0.21)
	xf = snap(xf, ln / 2.0 + 0.07, wd + 0.25, top)
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	item("bed", xf, Vector3(0, top / 2.0, 0.0), Vector3(wd + 0.2, top, ln + 0.14), "floor", true)
	fs(xf, Vector3(0, 0.3, 0), Vector3(wd, 0.3, ln), wood)
	fb(xf, Vector3(0, 0.55, 0.05), Vector3(wd - 0.06, 0.22, ln - 0.12), c(LINEN, CourthouseKit.K_CLOTH))
	fb(xf, Vector3(0, 0.62, 0.25), Vector3(wd + 0.04, 0.1, ln - 0.5), c(spread, CourthouseKit.K_CLOTH))
	for s: float in [-1.0, 1.0]:
		fb(xf, Vector3(s * (wd / 2.0 + 0.02), 0.48, 0.25), Vector3(0.02, 0.32, ln - 0.5), c(spread, CourthouseKit.K_CLOTH))
	fb(xf, Vector3(0, 0.62, 0.25 + (ln - 0.5) / 2.0 + 0.01), Vector3(wd + 0.04, 0.3, 0.02), c(spread, CourthouseKit.K_CLOTH))
	fb(xf, Vector3(0, 0.72, -ln / 2.0 + 0.3), Vector3(wd - 0.2, 0.14, 0.4), c(LINEN, CourthouseKit.K_CLOTH))
	fs(xf, Vector3(0, ht / 2.0, -ln / 2.0), Vector3(wd + 0.1, ht, 0.1), wood)
	fb(xf, Vector3(0, ht + 0.08, -ln / 2.0), Vector3(wd + 0.2, 0.16, 0.14), wood)
	fb(xf, Vector3(0, ht * 0.62, -ln / 2.0 + 0.06), Vector3(wd * 0.7, ht * 0.4, 0.03), c(wood_col.lightened(0.08), CourthouseKit.K_WOOD))
	fb(xf, Vector3(0, 0.55, ln / 2.0), Vector3(wd + 0.1, 0.6, 0.08), wood)
	if posts > 0.0:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var foot := Vector3(sx * (wd / 2.0 + 0.05), 0.0, sz * (ln / 2.0))
				k.turned("wall", xf, foot, posts, 0.07, wood, 8)
				k.m.sphere("wall", xf * Transform3D(Basis(), foot + Vector3(0, posts + 0.12, 0)), 0.09, 8, c(GILT, CourthouseKit.K_PAINT))


## A tall piece against a wall, facing +z (a wardrobe, a dresser with its
## glass, a sideboard): carcass, doors or drawers, a cornice.
static func cabinet(xf: Transform3D, wd: float, dp: float, ht: float, wood_col: Color, glass := 0.0, drawers := 3) -> void:
	var top := ht + (glass + 0.1 if glass > 0.0 else 0.1)
	xf = snap(xf, dp / 2.0, wd + 0.08, top)
	var wood := c(wood_col, CourthouseKit.K_WOOD)
	item("cabinet", xf, Vector3(0, top / 2.0, 0.0), Vector3(wd + 0.08, top, dp), "floor", true)
	fs(xf, Vector3(0, ht / 2.0, 0), Vector3(wd, ht, dp), wood)
	fb(xf, Vector3(0, ht + 0.05, 0.02), Vector3(wd + 0.08, 0.1, dp + 0.06), wood)
	for i in drawers:
		var y := 0.15 + (i + 0.5) * (ht - 0.25) / drawers
		fb(xf, Vector3(0, y, dp / 2.0 + 0.01), Vector3(wd - 0.1, (ht - 0.25) / drawers - 0.05, 0.02), c(wood_col.lightened(0.07), CourthouseKit.K_WOOD))
		for s: float in [-1.0, 1.0]:
			k.m.sphere("iron", xf * Transform3D(Basis(), Vector3(s * wd * 0.25, y, dp / 2.0 + 0.03)), 0.015, 6, c(BRASS, CourthouseKit.K_PAINT))
	if glass > 0.0:
		fb(xf, Vector3(0, ht + glass / 2.0 + 0.1, -dp / 2.0 + 0.04), Vector3(wd * 0.7, glass, 0.05), wood)
		fb(xf, Vector3(0, ht + glass / 2.0 + 0.1, -dp / 2.0 + 0.07), Vector3(wd * 0.6, glass - 0.12, 0.01), c(Color(0.55, 0.60, 0.62), CourthouseKit.K_ENAMEL))


## A rug on the floor at a survey point, y feet: a field, a border.
static func rug(sx: float, sz: float, y: float, size: Vector2, field: Color, border: Color) -> void:
	var p := w(sx, sz, y)
	var sz3 := Vector3(size.y * FT, 0.01, size.x * FT)
	item("rug", Transform3D(), p + Vector3(0, 0.006, 0), sz3, "rug")
	# Border, field and medallion stepped 8 mm apart, so none flickers
	# through another from across the room.
	k.box("wall", Transform3D(), p + Vector3(0, 0.008, 0), Vector3(sz3.x, 0.012, sz3.z), c(border, CourthouseKit.K_CLOTH))
	k.box("wall", Transform3D(), p + Vector3(0, 0.016, 0), Vector3(sz3.x - 0.35, 0.012, sz3.z - 0.35), c(field, CourthouseKit.K_CLOTH))
	k.box("wall", Transform3D(), p + Vector3(0, 0.024, 0), Vector3(sz3.x * 0.3, 0.012, sz3.z * 0.3), c(border.lightened(0.15), CourthouseKit.K_CLOTH))


## A plant in a pot at a survey point: a pot, a mound of leaves, fronds.
static func plant(sx: float, sz: float, y: float, tall: float, rng: RandomNumberGenerator) -> void:
	var p := w(sx, sz, y)
	item("plant", Transform3D(), p + Vector3(0, 0.2, 0), Vector3(0.48, 0.4, 0.48))
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.2, 0)), 0.18, 0.24, 0.4, 10, c(Color(0.55, 0.28, 0.18), CourthouseKit.K_TILE))
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.405, 0)), 0.17, 0.17, 0.01, 10, c(Color(0.22, 0.15, 0.10), CourthouseKit.K_TAR))
	var fronds := rng.randi_range(9, 14)
	for i in fronds:
		var a := TAU * i / fronds + rng.randf_range(-0.2, 0.2)
		var lift := rng.randf_range(0.5, 1.2)
		var reach := tall * rng.randf_range(0.7, 1.1)
		var tone := Color(0.14, 0.30, 0.10).lightened(rng.randf_range(-0.05, 0.1))
		var leaf := c(tone, CourthouseKit.K_PAINT)
		var prev := p + Vector3(0, 0.4, 0)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var segs := 5
		for j in segs:
			var t := float(j + 1) / segs
			var next := p + Vector3(0, 0.4, 0) + dir * reach * t + Vector3(0, reach * (lift * t - 0.9 * t * t), 0)
			var wide := 0.07 * sin(PI * (t - 0.5 / segs)) + 0.015
			var n := (next - prev).cross(side).normalized()
			if n.y < 0.0:
				n = -n
			k.m.quad("wall", prev - side * wide, prev + side * wide, next + side * wide * 0.8, next - side * wide * 0.8, n, leaf)
			k.m.quad("wall", prev - side * wide, prev + side * wide, next + side * wide * 0.8, next - side * wide * 0.8, -n, leaf)
			prev = next
	k.solid(Transform3D(), p + Vector3(0, 0.3, 0), Vector3(0.45, 0.6, 0.45))


## A framed picture on a wall face (frame f, z into the room) at u, y.
static func picture(f: Transform3D, u: float, y: float, wd: float, ht: float, tone: Color) -> void:
	item("picture", f, Vector3(u, y, 0.035), Vector3(wd, ht, 0.04), "wall", true)
	k.box("wall", f, Vector3(u, y, 0.035), Vector3(wd, ht, 0.04), c(GILT, CourthouseKit.K_PAINT))
	k.box("wall", f, Vector3(u, y, 0.06), Vector3(wd - 0.12, ht - 0.12, 0.01), c(tone, CourthouseKit.K_ENAMEL))
	k.box("wall", f, Vector3(u, y - ht * 0.15, 0.07), Vector3(wd - 0.3, ht * 0.3, 0.005), c(tone.darkened(0.35), CourthouseKit.K_ENAMEL))


## A place on a wall for something hung on it: the face of the survey
## line a-b seen from `toward`, and how far along it (u, metres) the
## survey point `at` stands.
static func on_wall(a: Vector2, b: Vector2, toward: Vector2, at_: Vector2) -> Array:
	var f := face(a, b, toward)
	var p := TwainHouse.w2(at_)
	return [f, (Vector3(p.x, 0, p.y) - f.origin).dot(f.basis.x)]


## A wall face's frame from the survey line a-b, z toward `toward`.
static func face(a: Vector2, b: Vector2, toward: Vector2) -> Transform3D:
	return TwainHouse.frame(a, b, toward)[0]


## ---- the rooms' contents ------------------------------------------------------

## The hall: its fireplace on the north wall, the bust of Clemens by Karl
## Gerhardt on a pedestal, a carved settle and a hall table, the rug, the
## gas chandelier; pictures up the stair.
static func _hall() -> void:
	var cy := F2 - 1.0
	fireplace(at(95.4, 69.0, 0.0, Vector2(-1, 0)), 1.9, WALNUT, 1.4, true)
	rug(84.5, 74.0, 0.0, Vector2(12.0, 8.0), Color(0.35, 0.08, 0.06), Color(0.12, 0.10, 0.18))
	_gasolier(w(86.0, 71.0, cy), 6, 0.4)
	_gasolier(w(78.0, 76.5, cy), 4, 0.32)
	# The bust on its pedestal by the drawing room door.
	var ped := at(94.2, 75.5, 0.0, Vector2(-1, 0))
	item("pedestal and bust", ped, Vector3(0, 0.78, 0), Vector3(0.4, 1.56, 0.4))
	fs(ped, Vector3(0, 0.55, 0), Vector3(0.4, 1.1, 0.4), c(Color(0.20, 0.12, 0.08), CourthouseKit.K_WOOD))
	k.m.sphere("wall", ped * Transform3D(Basis().scaled(Vector3(0.85, 1.1, 0.9)), Vector3(0, 1.42, 0)), 0.13, 10, c(Color(0.35, 0.26, 0.14), CourthouseKit.K_PAINT))
	fb(ped, Vector3(0, 1.22, 0), Vector3(0.3, 0.16, 0.2), c(Color(0.35, 0.26, 0.14), CourthouseKit.K_PAINT))
	# The settle against the west wall under the stair's landing.
	sofa(snap(at(73.4, 62.0, 0.0, Vector2(1, 0)), 0.37, 1.4, 1.0), 1.4, PLUSH, WALNUT)
	table(at(89.0, 57.3, 0.0, Vector2(0, 1)), 1.2, 0.45, 0.8, WALNUT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1874


## The library: the mantel across the east wall, the shelves, the alcove's
## seat, the table in the middle with its lamp, the sofa and chairs, the
## rug; the doors open to the conservatory at the south end.
static func _library() -> void:
	var cy := F2 - 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1881
	# The Ayton Castle mantel: the width of a room's end, carved oak up to
	# the ceiling, its brass plate.
	var m := at(72.0, 55.4, 0.0, Vector2(0, -1))
	fireplace(m, 2.6, Color(0.36, 0.22, 0.11), 1.9, false)
	var oak := c(Color(0.36, 0.22, 0.11), CourthouseKit.K_WOOD)
	fb(m, Vector3(0, 3.35, 0.05), Vector3(3.2, 0.3, 0.4), oak)
	for s: float in [-1.0, 1.0]:
		fs(m, Vector3(s * 1.5, 1.7, 0.08), Vector3(0.3, 3.4, 0.3), oak)
		for j in 6:
			k.m.sphere("wall", m * Transform3D(Basis(), Vector3(s * 1.5, 0.5 + j * 0.5, 0.25)), 0.07, 6, oak)
	fb(m, Vector3(0, 1.1, 0.15), Vector3(0.9, 0.08, 0.02), c(BRASS, CourthouseKit.K_PAINT))
	# Shelves along the west wall either side of the alcove and on the north.
	bookcase(at(62.5, 39.5, 0.0, Vector2(0, 1)), 2.2, 2.3, rng)
	bookcase(at(83.3, 39.5, 0.0, Vector2(0, 1)), 2.4, 2.3, rng)
	bookcase(at(65.4, 55.5, 0.0, Vector2(0, -1)), 0.8, 2.1, rng)
	bookcase(at(78.8, 55.5, 0.0, Vector2(0, -1)), 0.9, 2.1, rng)
	# The window seat round the alcove.
	var seat := c(Color(0.30, 0.10, 0.08), CourthouseKit.K_CLOTH)
	for p: Array in [[Vector2(73.2, 31.3), Vector2(0, 1), 1.2], [Vector2(69.6, 32.9), Vector2(1, 1), 0.72], [Vector2(76.8, 32.9), Vector2(-1, 1), 0.72]]:
		var q := p[0] as Vector2
		var sw := float(p[2])
		var xf := snap(at(q.x, q.y, 0.0, p[1] as Vector2), 0.25, sw, 0.3)
		item("window seat", xf, Vector3(0, 0.255, 0), Vector3(sw, 0.51, 0.5), "floor", true)
		fs(xf, Vector3(0, 0.22, 0), Vector3(sw, 0.44, 0.5), c(WALNUT, CourthouseKit.K_WOOD))
		fb(xf, Vector3(0, 0.47, 0.02), Vector3(sw, 0.08, 0.48), seat)
	# The table, its lamp, the chairs and the sofa before the fire.
	table(at(72.0, 46.5, 0.0, Vector2(0, 1)), 1.6, 0.95, 0.76, WALNUT, Color(0.30, 0.12, 0.10, 1.0))
	var lamp := w(72.0, 46.5, 0.0) + Vector3(0, 0.78, 0)
	k.m.cylinder("wall", Transform3D(Basis(), lamp + Vector3(0, 0.1, 0)), 0.08, 0.1, 0.2, 10, c(BRASS, CourthouseKit.K_PAINT))
	k.m.sphere("lamp", Transform3D(Basis(), lamp + Vector3(0, 0.42, 0)), 0.14, 10, Color(1, 1, 1))
	hs.gaslight(lamp + Vector3(0, 0.45, 0), 0.7, 5.0, 0.25)
	for p: Array in [[Vector2(68.3, 46.5), Vector2(1, 0)], [Vector2(75.7, 46.5), Vector2(-1, 0)], [Vector2(72.0, 43.4), Vector2(0, 1)]]:
		var q := p[0] as Vector2
		chair(at(q.x, q.y, 0.0, p[1] as Vector2), WALNUT, PLUSH)
	sofa(at(72.0, 51.5, 0.0, Vector2(0, 1)), 2.0, Color(0.18, 0.22, 0.30))
	sofa(at(66.0, 52.3, 0.0, Vector2(0.5, 1)), 0.9, PLUSH)
	sofa(at(78.0, 52.3, 0.0, Vector2(-0.5, 1)), 0.9, PLUSH)
	rug(72.0, 47.0, 0.0, Vector2(18.0, 10.0), Color(0.22, 0.10, 0.12), Color(0.10, 0.14, 0.22))
	_gasolier(w(72.0, 46.5, cy), 6, 0.45)
	# The globe by the alcove.
	var g := w(79.5, 41.5, 0.0)
	item("globe", Transform3D(), g + Vector3(0, 0.585, 0), Vector3(0.46, 1.17, 0.46))
	k.m.cylinder("wall", Transform3D(Basis(), g + Vector3(0, 0.4, 0)), 0.04, 0.04, 0.8, 6, c(WALNUT, CourthouseKit.K_WOOD))
	k.m.sphere("wall", Transform3D(Basis(), g + Vector3(0, 0.95, 0)), 0.22, 14, c(Color(0.60, 0.52, 0.34), CourthouseKit.K_ENAMEL))


## The dining room: the table laid for eight, the chairs, the sideboard,
## the fireplace under its window on the north wall, the gasolier.
static func _dining_room() -> void:
	var cy := F2 - 1.0
	table(at(100.5, 47.5, 0.0, Vector2(0, 1)), 3.0, 1.3, 0.76, WALNUT, Color(0.94, 0.93, 0.88, 1.0))
	var plate := c(Color(0.95, 0.94, 0.90), CourthouseKit.K_ENAMEL)
	for i in 3:
		for s: float in [-1.0, 1.0]:
			var q := Vector2(96.5 + i * 4.0, 47.5 + s * 3.1)
			chair(at(q.x, q.y, 0.0, Vector2(0, -s)), WALNUT, Color(0.30, 0.10, 0.06))
			var pp := w(96.5 + i * 4.0, 47.5 + s * 1.7, 0.0) + Vector3(0, 0.79, 0)
			k.m.cylinder("wall", Transform3D(Basis(), pp), 0.12, 0.13, 0.015, 14, plate)
	for s: float in [-1.0, 1.0]:
		var q := Vector2(100.5 + s * 7.0, 47.5)
		chair(at(q.x, q.y, 0.0, Vector2(-s, 0)), WALNUT, Color(0.30, 0.10, 0.06), 1.2)
	k.m.cylinder("wall", Transform3D(Basis(), w(100.5, 47.5, 0.0) + Vector3(0, 0.9, 0)), 0.14, 0.08, 0.25, 12, c(Color(0.75, 0.75, 0.72), CourthouseKit.K_ENAMEL))
	cabinet(at(97.5, 55.2, 0.0, Vector2(0, -1)), 2.0, 0.6, 1.0, WALNUT, 1.0, 2)
	fireplace(at(100.8, 39.6, 0.0, Vector2(0, 1)), 1.6, WALNUT, 0.0, false)
	rug(100.5, 47.5, 0.0, Vector2(16.0, 11.0), Color(0.30, 0.10, 0.06), Color(0.12, 0.08, 0.06))
	_gasolier(w(100.5, 47.5, cy), 6, 0.45)


## The drawing room: the fireplace on its south wall, the piano in the
## bay's corner, the pier glass between the east windows, chairs and a
## settee round a small table, the rug, the gasolier.
static func _drawing_room() -> void:
	var cy := F2 - 1.0
	fireplace(at(96.5, 69.0, 0.0, Vector2(1, 0)), 1.8, Color(0.85, 0.82, 0.76), 1.5, true)
	# The piano: a grand, its lid raised, in the north-east corner, its
	# keys to the west.
	var pno := at(109.6, 78.4, 0.0, Vector2(0, 1))
	var black := c(Color(0.05, 0.04, 0.04), CourthouseKit.K_ENAMEL)
	item("piano", pno, Vector3(0, 0.5, 0.2), Vector3(1.5, 1.0, 1.9))
	fs(pno, Vector3(0, 0.85, 0.2), Vector3(1.5, 0.3, 1.9), black)
	for p: Vector3 in [Vector3(-0.6, 0, -0.55), Vector3(0.6, 0, -0.55), Vector3(0, 0, 0.95)]:
		k.m.cylinder("wall", pno * Transform3D(Basis(), p + Vector3(0, 0.36, 0)), 0.07, 0.05, 0.72, 8, black)
	fb(pno, Vector3(0, 0.74, -0.8), Vector3(1.3, 0.04, 0.28), c(Color(0.92, 0.90, 0.84), CourthouseKit.K_ENAMEL))
	k.box_rz("wall", pno, Vector3(0.35, 1.3, 0.3), Vector3(0.02, 0.9, 1.6), 0.55, black)
	chair(at(109.6, 74.4, 0.0, Vector2(0, 1)), Color(0.05, 0.04, 0.04), Color(0.30, 0.10, 0.08), 0.6)
	# The pier glass between the east windows.
	var fe := face(Vector2(96.2, TwainHouse.MZ1 - 1.0), Vector2(113.5, TwainHouse.MZ1 - 1.0), Vector2(105.0, 70.0))
	var pier := TwainHouse.w2(Vector2(106.25, 82.9))
	var u := (Vector3(pier.x, 0, pier.y) - fe.origin).dot(fe.basis.x)
	item("pier glass", fe, Vector3(u, h(5.5), 0.04), Vector3(0.95, 2.9, 0.06), "wall", true)
	k.box("wall", fe, Vector3(u, h(5.5), 0.04), Vector3(0.95, 2.9, 0.06), c(GILT, CourthouseKit.K_PAINT))
	k.box("wall", fe, Vector3(u, h(5.5), 0.075), Vector3(0.8, 2.7, 0.01), c(Color(0.60, 0.64, 0.66), CourthouseKit.K_ENAMEL))
	k.box("wall", fe, Vector3(u, h(0.9), 0.2), Vector3(1.1, 0.06, 0.36), c(Color(0.90, 0.88, 0.84), CourthouseKit.K_TILE))
	# Before the fire: a settee facing it across a small table, an armchair
	# either side; a third chair by the west window.
	var plush := Color(0.55, 0.34, 0.30)
	var frame := Color(0.40, 0.28, 0.18)
	sofa(at(105.2, 69.0, 0.0, Vector2(-1, 0)), 1.8, plush, frame)
	table(at(102.2, 69.0, 0.0, Vector2(0, 1)), 0.7, 0.7, 0.7, frame, Color(0.0, 0, 0, 0), true)
	sofa(at(100.8, 62.6, 0.0, Vector2(0.3, 1)), 0.85, plush, frame)
	sofa(at(100.8, 75.4, 0.0, Vector2(0.3, -1)), 0.85, plush, frame)
	sofa(at(110.5, 60.2, 0.0, Vector2(-0.6, 1)), 0.85, plush, frame)
	rug(105.0, 69.5, 0.0, Vector2(15.0, 20.0), Color(0.62, 0.40, 0.32), Color(0.30, 0.18, 0.16))
	_gasolier(w(105.0, 69.5, cy), 8, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1882
	plant(119.0, 69.5, 0.0, 0.6, rng)


## The mahogany guest room, its dressing room and bath.
static func _guest_rooms() -> void:
	var cy := F2 - 1.0
	var mah := MAHOGANY
	bed(at(67.5, 56.9, 0.0, Vector2(0, 1)), 1.5, 2.1, 1.9, mah, Color(0.55, 0.12, 0.10), 0.0)
	cabinet(at(55.0, 57.8, 0.0, Vector2(0.6, 1)), 1.0, 0.5, 0.85, mah, 0.9, 3)
	sofa(at(51.5, 64.0, 0.0, Vector2(1, 0)), 0.8, Color(0.50, 0.14, 0.10), mah)
	chair(at(60.0, 68.0, 0.0, Vector2(0, -1)), mah, Color(0.50, 0.14, 0.10))
	rug(61.0, 63.5, 0.0, Vector2(14.0, 9.0), Color(0.40, 0.10, 0.08), Color(0.14, 0.12, 0.10))
	_gasolier(w(61.0, 63.5, cy), 3, 0.3)
	# The dressing room.
	chair(at(54.0, 76.0, 0.0, Vector2(1, 0)), mah, Color(0.50, 0.14, 0.10))
	# The bath: a tub cased in wood, a basin on its stand.
	var tub := snap(at(69.0, 81.3, 0.0, Vector2(0, -1)), 0.375, 1.7, 0.6)
	item("bath tub", tub, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.75), "floor", true)
	fs(tub, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.75), c(WALNUT, CourthouseKit.K_WOOD))
	fb(tub, Vector3(0, 0.58, 0), Vector3(1.5, 0.05, 0.55), c(Color(0.90, 0.90, 0.88), CourthouseKit.K_ENAMEL))
	var basin := snap(at(64.5, 72.0, 0.0, Vector2(0, 1)), 0.25, 0.8, 0.9)
	item("wash stand", basin, Vector3(0, 0.44, 0), Vector3(0.8, 0.88, 0.5), "floor", true)
	fs(basin, Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.5), c(Color(0.86, 0.84, 0.80), CourthouseKit.K_TILE))
	k.m.cylinder("wall", basin * Transform3D(Basis(), Vector3(0, 0.84, 0)), 0.2, 0.15, 0.08, 12, c(Color(0.94, 0.94, 0.92), CourthouseKit.K_ENAMEL))


## The conservatory: the fountain in its basin, palms and ferns in pots
## round the glass, a pair of cane chairs.
static func _conservatory() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1874
	var cen := TwainHouse.CONS_C
	var p := w(cen.x, cen.y, 0.0)
	var stone := c(Color(0.80, 0.78, 0.72), CourthouseKit.K_STONE)
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.2, 0)), 0.75, 0.8, 0.4, 20, stone)
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.405, 0)), 0.68, 0.68, 0.01, 20, c(Color(0.16, 0.24, 0.25), CourthouseKit.K_ENAMEL))
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.65, 0)), 0.06, 0.08, 0.6, 8, stone)
	k.m.cylinder("wall", Transform3D(Basis(), p + Vector3(0, 0.98, 0)), 0.3, 0.1, 0.08, 14, stone)
	k.m.bar("glass", p + Vector3(0, 1.0, 0), p + Vector3(0, 1.35, 0), 0.015, 5, Color(1, 1, 1, 1))
	k.solid(Transform3D(), p + Vector3(0, 0.2, 0), Vector3(1.5, 0.4, 1.5))
	item("fountain", Transform3D(), p + Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.6))
	for i in 9:
		var a := -80.0 - 160.0 * i / 8.0
		var q := TwainHouse._arc_point(cen, TwainHouse.CONS_R - 2.6, a)
		plant(q.x, q.y, 0.0, rng.randf_range(0.45, 0.6), rng)
	var cane := Color(0.66, 0.54, 0.32)
	chair(at(55.5, 43.0, 0.0, Vector2(-1, 0.4)), cane, Color(0.50, 0.56, 0.40), 0.9)
	chair(at(55.5, 51.0, 0.0, Vector2(-1, -0.4)), cane, Color(0.50, 0.56, 0.40), 0.9)


## The bedrooms upstairs.
static func _bedrooms() -> void:
	var cy := F3 - 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1879
	# The Clemenses' bedroom: the Venetian bed, carved, its posts crowned;
	# they slept with their heads at its foot, to face the carving.
	var vb := at(105.5, 60.0, F2, Vector2(0, 1))
	bed(vb, 1.9, 2.3, 2.3, Color(0.22, 0.12, 0.07), Color(0.40, 0.14, 0.12), 2.2)
	var dark := c(Color(0.22, 0.12, 0.07), CourthouseKit.K_WOOD)
	for s: float in [-1.0, 1.0]:
		k.m.sphere("wall", vb * Transform3D(Basis().scaled(Vector3(0.7, 1.2, 0.7)), Vector3(s * 0.5, 2.55, -1.15)), 0.14, 8, c(GILT, CourthouseKit.K_PAINT))
	fb(vb, Vector3(0, 2.0, -1.12), Vector3(1.4, 0.5, 0.06), dark)
	fireplace(at(97.3, 69.0, F2, Vector2(1, 0)), 1.7, Color(0.22, 0.12, 0.07), 1.3, true)
	cabinet(at(104.4, 82.5, F2, Vector2(0, -1)), 1.1, 0.5, 0.9, Color(0.22, 0.12, 0.07), 0.9, 3)
	sofa(at(117.0, 69.5, F2, Vector2(-1, 0)), 1.6, Color(0.40, 0.20, 0.16))
	rug(105.0, 72.0, F2, Vector2(14.0, 18.0), Color(0.35, 0.14, 0.10), Color(0.14, 0.12, 0.18))
	_gasolier(w(105.0, 72.0, cy), 3, 0.3)
	# The school room: desks for the girls, the table, a map and a board.
	for i in 3:
		var q := Vector2(65.5 + i * 4.0, 47.0)
		table(at(q.x, q.y, F2, Vector2(0, 1)), 0.9, 0.55, 0.7, OAK.darkened(0.2))
		chair(at(q.x, q.y - 1.6, F2, Vector2(0, 1)), OAK.darkened(0.2), Color(0.25, 0.30, 0.20), 0.9)
	table(at(75.0, 50.5, F2, Vector2(-1, 0)), 1.4, 0.8, 0.76, OAK.darkened(0.2), Color(0.20, 0.30, 0.22, 1.0))
	bookcase(at(78.8, 44.0, F2, Vector2(-1, 0)), 1.4, 2.0, rng, OAK.darkened(0.2))
	var bw := on_wall(Vector2(TwainHouse.MX0 + 1.0, 55.7), Vector2(79.05, 55.7), Vector2(70.0, 45.0), Vector2(69.0, 55.7))
	var fs2: Transform3D = bw[0]
	item("blackboard", fs2, Vector3(bw[1], h(F2 + 5.4), 0.045), Vector3(2.2, 0.9, 0.03), "wall", true)
	k.box("wall", fs2, Vector3(bw[1], h(F2 + 5.4), 0.045), Vector3(2.2, 0.9, 0.03), c(Color(0.10, 0.12, 0.10), CourthouseKit.K_ENAMEL))
	var pw := on_wall(Vector2(TwainHouse.MX0 + 1.0, 55.7), Vector2(79.05, 55.7), Vector2(70.0, 45.0), Vector2(75.5, 55.7))
	picture(pw[0], pw[1], h(F2 + 5.5), 1.2, 0.9, Color(0.62, 0.58, 0.42))
	_gasolier(w(68.0, 47.0, cy), 3, 0.3)
	# Susy's room.
	bed(at(83.0, 79.0, F2, Vector2(-1, 0)), 1.1, 2.0, 1.5, WALNUT, Color(0.70, 0.66, 0.58))
	cabinet(at(68.3, 75.0, F2, Vector2(1, 0)), 1.0, 0.5, 0.85, WALNUT, 0.8)
	table(at(75.4, 81.7, F2, Vector2(0, -1)), 1.0, 0.55, 0.72, WALNUT)
	chair(at(75.4, 79.9, F2, Vector2(0, 1)), WALNUT, Color(0.40, 0.30, 0.40))
	_bracket_lamp(face(Vector2(67.95, 71.05), Vector2(67.95, 82.9), Vector2(76.0, 77.0)), 1.8, h(F2 + 5.5))
	# Clara and Jean's: two small beds, a chest of toys.
	bed(at(55.8, 56.9, F2, Vector2(0, 1)), 1.0, 1.9, 1.3, OAK.darkened(0.15), Color(0.70, 0.62, 0.60))
	bed(at(68.6, 56.9, F2, Vector2(0, 1)), 1.0, 1.9, 1.3, OAK.darkened(0.15), Color(0.60, 0.66, 0.72))
	rug(60.0, 64.0, F2, Vector2(10.0, 8.0), Color(0.50, 0.30, 0.24), Color(0.20, 0.24, 0.30))
	_gasolier(w(61.0, 63.0, cy), 3, 0.3)
	# The Langdon guest room.
	bed(at(99.5, 48.0, F2, Vector2(-1, 0)), 1.5, 2.1, 1.9, WALNUT, Color(0.30, 0.34, 0.44), 0.0)
	cabinet(at(96.5, 55.3, F2, Vector2(0, -1)), 1.1, 0.5, 0.9, WALNUT, 0.9)
	_gasolier(w(90.5, 47.5, cy), 3, 0.3)
	# The west bath: a tub cased in walnut, a marble basin on its stand.
	var wt := snap(at(86.2, 50.0, F2, Vector2(-1, 0)), 0.375, 1.7, 0.6)
	item("bath tub", wt, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.75), "floor", true)
	fs(wt, Vector3(0, 0.3, 0), Vector3(1.7, 0.6, 0.75), c(WALNUT, CourthouseKit.K_WOOD))
	fb(wt, Vector3(0, 0.58, 0), Vector3(1.5, 0.05, 0.55), c(Color(0.90, 0.90, 0.88), CourthouseKit.K_ENAMEL))
	var wb := snap(at(80.0, 51.0, F2, Vector2(1, 0)), 0.25, 0.8, 0.9)
	item("wash stand", wb, Vector3(0, 0.44, 0), Vector3(0.8, 0.88, 0.5), "floor", true)
	fs(wb, Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.5), c(MARBLE, CourthouseKit.K_TILE))
	k.m.cylinder("wall", wb * Transform3D(Basis(), Vector3(0, 0.84, 0)), 0.2, 0.15, 0.08, 12, c(Color(0.94, 0.94, 0.92), CourthouseKit.K_ENAMEL))
	# The upstairs hall: a carved bench by the well, a rug, a gasolier.
	sofa(snap(at(95.8, 67.5, F2, Vector2(-1, 0)), 0.37, 1.4, 1.0), 1.4, PLUSH)
	rug(90.0, 63.0, F2, Vector2(10.0, 8.0), Color(0.32, 0.08, 0.06), Color(0.12, 0.10, 0.18))
	_gasolier(w(88.0, 63.0, cy), 4, 0.32)


## The billiard room under the south gable: the table under its lamp, the
## rack of cues, the writing table by the balcony door where the books
## were finished, a sofa, the shelves.
static func _billiard_room() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1884
	var bt := at(73.0, 47.6, F3, Vector2(1, 0))
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	item("billiard table", bt, Vector3(0, 0.39, 0), Vector3(1.45, 0.78, 2.7))
	fs(bt, Vector3(0, 0.62, 0), Vector3(1.45, 0.16, 2.7), wood)
	fb(bt, Vector3(0, 0.71, 0), Vector3(1.27, 0.03, 2.52), c(GREEN_BAIZE, CourthouseKit.K_CLOTH))
	for s: float in [-1.0, 1.0]:
		fb(bt, Vector3(s * 0.68, 0.75, 0), Vector3(0.1, 0.06, 2.7), wood)
		fb(bt, Vector3(0, 0.75, s * 1.32), Vector3(1.45, 0.06, 0.1), wood)
	for p: Vector3 in [Vector3(-0.6, 0, -1.2), Vector3(0.6, 0, -1.2), Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(-0.6, 0, 1.2), Vector3(0.6, 0, 1.2)]:
		k.turned("wall", bt, p, 0.56, 0.08, wood, 8)
	for i in 3:
		k.m.sphere("wall", bt * Transform3D(Basis(), Vector3(-0.2 + i * 0.2, 0.755, 0.5 - i * 0.3)), 0.03, 8,
			c([Color(0.95, 0.94, 0.88), Color(0.80, 0.10, 0.08), Color(0.95, 0.90, 0.60)][i], CourthouseKit.K_ENAMEL))
	var roof := hs.roof_y(Vector2(73.0, 47.6))
	var top := minf(roof - 1.0, F3 + 10.0)
	var lamp := w(73.0, 47.6, top)
	k.m.bar("iron", lamp, lamp - Vector3(0, h(top) - h(F3) - 1.4, 0), 0.02, 6, c(BRASS, CourthouseKit.K_PAINT))
	var hub := w(73.0, 47.6, F3) + Vector3(0, 1.4, 0)
	var along := (w(78.0, 47.6, 0) - w(68.0, 47.6, 0)).normalized()
	k.m.bar("iron", hub - along * 0.8, hub + along * 0.8, 0.018, 6, c(BRASS, CourthouseKit.K_PAINT))
	for s: float in [-1.0, 1.0]:
		var sh := hub + along * s * 0.8
		k.m.cylinder("lamp", Transform3D(Basis(), sh - Vector3(0, 0.1, 0)), 0.2, 0.08, 0.16, 12, Color(1, 1, 1))
		hs.gaslight(sh - Vector3(0, 0.25, 0), 1.0, 6.0, 0.45)
	# The cue rack on the end wall, the writing table by the balcony door.
	var rack := face(Vector2(89.25, 41.2), Vector2(89.25, 55.7), Vector2(70.0, 47.0))
	var fu := (TwainHouse.w2(Vector2(89.25, 51.0)) - TwainHouse.w2(Vector2(89.25, 41.2))).length()
	item("cue rack", rack, Vector3(fu, (h(F3 + 0.5) + h(F3 + 4.6)) / 2.0, 0.05), Vector3(1.2, h(F3 + 4.6) - h(F3 + 0.4), 0.1), "wall", true)
	k.box("wall", rack, Vector3(fu, h(F3 + 4.0), 0.03), Vector3(1.2, 0.12, 0.08), wood)
	k.box("wall", rack, Vector3(fu, h(F3 + 0.5), 0.05), Vector3(1.2, 0.1, 0.1), wood)
	for i in 10:
		var u := fu - 0.55 + i * 0.12
		k.m.bar("wall", rack * Vector3(u, h(F3 + 0.55), 0.06), rack * Vector3(u, h(F3 + 4.6), 0.05), 0.012, 4, c(Color(0.62, 0.46, 0.26), CourthouseKit.K_WOOD))
	table(at(61.5, 44.0, F3, Vector2(1, 0.3)), 1.2, 0.7, 0.74, WALNUT)
	chair(at(63.3, 44.5, F3, Vector2(-1, -0.3)), WALNUT, Color(0.30, 0.20, 0.12))
	var paper := c(Color(0.92, 0.90, 0.82), HarborTown.K_PAPER)
	for i in 5:
		k.box("wall", at(61.5, 44.0, F3, Vector2(1, 0.3 + i * 0.1)), Vector3(-0.2 + i * 0.1, 0.77 + i * 0.004, 0.05 * i - 0.1), Vector3(0.21, 0.004, 0.28), paper)
	sofa(at(67.0, 52.3, F3, Vector2(0, -1)), 1.7, Color(0.26, 0.20, 0.14))
	bookcase(at(88.0, 44.0, F3, Vector2(-1, 0)), 1.2, 1.05, rng)
	rug(73.0, 47.6, F3, Vector2(16.0, 10.0), Color(0.34, 0.20, 0.10), Color(0.14, 0.10, 0.08))
	# The stair hall at the top.
	_gasolier(w(88.0, 63.0, minf(hs.roof_y(Vector2(88.0, 63.0)), F3 + 11.0) - 0.5), 3, 0.3)
