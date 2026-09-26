class_name CourthouseInterior
extends RefCounted
## Inside the Union County courthouse. The ground floor: a hall down the
## building's length from door to door, crossed in the main block by
## the hall from porch to porch; offices off it, the Heritage Room in the
## main block's north-west corner. Plastered walls over a wainscot of
## upright beaded boards stained dark, oak floors, globes hanging on
## chains. The stairs rise at the hall's north and south ends, each in
## two flights round a landing, with massive newels, turned balusters and
## a moulded rail. Upstairs the courtroom fills the main block: five
## arched windows down each side between pilasters that carry a full
## entablature, its frieze hung with garlands and cartouches; the bench
## under an arched niche at the north end with the flags, the clerk
## below it, the witness stand, the jury box on the east side; counsel
## tables, the bar with its gate, and the public's pews. Off the
## upstairs halls the judge's chambers, the jury room and offices.
##
## The north wing is laid out here and the south wing is the same turned
## half round about the middle: its stair on the west side.

const F1 := UnionCourthouse.F1
const F2 := UnionCourthouse.F2
const MX := UnionCourthouse.MX
const MZ := UnionCourthouse.MZ
const PX := UnionCourthouse.PX
const PZ := UnionCourthouse.PZ
const WX := UnionCourthouse.WX
const WZ := UnionCourthouse.WZ
const T := UnionCourthouse.T
const C1 := F2 - 0.45          # the ground floor's ceiling
const C2 := 13.7               # the courtroom's ceiling
const C3 := 11.2               # the wings' upstairs ceilings
const IX := MX - T             # the main block's inside faces
const IZ := MZ - T
const WIX := WX - T            # the wings'
const WIZ := WZ - T
const HALL := 1.4              # the hall's half width
const LANDING := F1 + (F2 - F1) / 2.0
const WAINSCOT := 0.95
const DOOR_H := 2.4
const OPEN_H := 3.05           # a door's opening, its transom over it

const OAK := Color(0.52, 0.34, 0.19)
const PLASTER := UnionCourthouse.PLASTER
const CEILING := Color(0.93, 0.91, 0.86)
const STAIN := Color(0.27, 0.16, 0.09)
const WALNUT := Color(0.33, 0.20, 0.11)
const FRIEZE := Color(0.33, 0.42, 0.30)
const GILT := Color(0.78, 0.63, 0.32)
const LEATHER := Color(0.22, 0.10, 0.07)
const IRON := UnionCourthouse.IRON

static var k: CourthouseKit
static var b: UnionCourthouse


static func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


static func build(building: UnionCourthouse) -> void:
	b = building
	k = building.k
	_floors()
	_ground_floor()
	_courtroom()
	for e: float in [-1.0, 1.0]:
		var w := Transform3D() if e < 0.0 else Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		_wing(w, e)
	_outside_wainscot()


## ---- floors and ceilings -------------------------------------------------

static func _floors() -> void:
	var g := Transform3D()
	var oak := c(OAK, CourthouseKit.K_OAK)
	var ceil := c(CEILING, CourthouseKit.K_PLASTER)
	# The ground floor on its fill, solid.
	k.block("wall", g, Vector3(0, F1 / 2.0, 0), Vector3(2.0 * MX - 0.02, F1, 2.0 * MZ - 0.02), oak)
	for s: float in [-1.0, 1.0]:
		k.block("wall", g, Vector3(s * (MX + PX) / 2.0 - s * 0.01, F1 / 2.0, 0), Vector3(PX - MX - 0.02, F1, 2.0 * PZ - 1.0), oak)
	for e: float in [-1.0, 1.0]:
		k.block("wall", g, Vector3(0, F1 / 2.0, e * (MZ + WZ) / 2.0), Vector3(2.0 * WX - 0.02, F1, WZ - MZ), oak)
	# The courtroom floor over the main block: the ground floor's ceiling
	# under it.
	_slab(Rect2(-IX - 0.5, -IZ, 2.0 * IX + 1.0, 2.0 * IZ), oak, ceil)
	# The wings' upstairs floors, round each stair's well.
	for e: float in [-1.0, 1.0]:
		var sx := -e      # the stair's side: east in the north wing
		var well_x0 := minf(sx * 2.0, sx * WIX)
		var well_x1 := maxf(sx * 2.0, sx * WIX)
		var z0 := minf(e * MZ, e * WIZ)
		var z1 := maxf(e * MZ, e * WIZ)
		# West of the well (north wing), all its length; east of the well
		# from its end to the wing's end.
		var ox0 := minf(-sx * WIX, sx * 2.0)
		var ox1 := maxf(-sx * WIX, sx * 2.0)
		_slab(Rect2(ox0, z0, ox1 - ox0, z1 - z0), oak, ceil)
		var ez0 := minf(e * 12.3, e * WIZ)
		var ez1 := maxf(e * 12.3, e * WIZ)
		_slab(Rect2(well_x0, ez0, well_x1 - well_x0, ez1 - ez0), oak, ceil)
		# The wings' upstairs ceilings under the flat roofs.
		k.box("wall", g, Vector3(0, C3 + 0.05, e * (MZ + WIZ) / 2.0), Vector3(2.0 * WIX, 0.1, WIZ - MZ), ceil)
	# The courtroom's ceiling.
	k.box("wall", g, Vector3(0, C2 + 0.05, 0), Vector3(2.0 * IX + 1.0, 0.1, 2.0 * IZ), ceil)


## A floor slab over rect (x, z) from C1 to F2: oak on top, ceiling under.
static func _slab(r: Rect2, top: Color, under: Color) -> void:
	var g := Transform3D()
	var cen := Vector3(r.position.x + r.size.x / 2.0, (C1 + F2) / 2.0, r.position.y + r.size.y / 2.0)
	k.box("wall", g, cen, Vector3(r.size.x, F2 - C1, r.size.y), under)
	k.solid(g, cen, Vector3(r.size.x, F2 - C1, r.size.y))
	var y := F2 + 0.003
	k.m.quad("wall", Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y),
		Vector3(r.position.x, y, r.end.y), Vector3.UP, top)


## ---- walls ---------------------------------------------------------------

## A partition from a to b (x, z) between y0 and y1, 0.16 thick: plaster
## both faces over the wainscot and its chair rail; doors at the given
## distances along it, each cased both sides with a transom over it and
## its door standing open. Solid.
static func iwall(a: Vector2, bb: Vector2, y0: float, y1: float, doors: Array = [], door_w := 1.0) -> void:
	var t := 0.16
	var along := bb - a
	var length := along.length()
	var dir := along / length
	var x_axis := Vector3(dir.x, 0, dir.y)
	var f := Transform3D(Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP)), Vector3(a.x, 0, a.y))
	# The frame's z is x × up; the wall's front face stands t/2 along it.
	var nz := f.basis.z
	var front := Transform3D(f.basis, f.origin + nz * t / 2.0)
	var opens: Array = []
	for d: float in doors:
		opens.append(CourthouseKit.opening(d, door_w, y0, y0 + OPEN_H, "flat"))
	var plaster := c(PLASTER, CourthouseKit.K_PLASTER)
	k.wall("wall", front, 0.0, length, y0, y1, t, plaster, opens, y1 + 1.0)
	var back := Transform3D(Basis(-x_axis, Vector3.UP, -nz), f.origin - nz * t / 2.0 + x_axis * length)
	var back_opens: Array = []
	for d: float in doors:
		back_opens.append(CourthouseKit.opening(length - d, door_w, y0, y0 + OPEN_H, "flat"))
	for side: Array in [[front, opens], [back, back_opens]]:
		_wainscot(side[0] as Transform3D, 0.0, length, y0, side[1] as Array)
		for o: Dictionary in side[1]:
			_casing(side[0] as Transform3D, o)
	# A door opens into the room, the side away from the middle of the
	# building: the leaves swing behind the face they are hung from.
	var mid := (a + bb) / 2.0
	var hung_front := nz.dot(Vector3(mid.x, 0, mid.y)) < 0.0
	for o: Dictionary in (opens if hung_front else back_opens):
		_door_in(front if hung_front else back, o, t)


## The wainscot along a face (frame f: z out of the face into the room)
## from u0 to u1: beaded boards to WAINSCOT with a chair rail, a base.
static func _wainscot(f: Transform3D, u0: float, u1: float, y0: float, opens: Array) -> void:
	var bead := c(STAIN, 18)
	var ff := f * Transform3D(Basis(), Vector3(0, 0, 0.02))
	k.wall("wall", ff, u0, u1, y0, y0 + WAINSCOT, 0.02, bead, opens, -1.0)
	var rail := Transform3D(ff.basis, ff * Vector3(0, 0, 0.03))
	k.wall("wall", rail, u0, u1, y0 + WAINSCOT - 0.02, y0 + WAINSCOT + 0.06, 0.05, c(STAIN, CourthouseKit.K_WOOD), opens, -1.0)
	var base := Transform3D(ff.basis, ff * Vector3(0, 0, 0.015))
	k.wall("wall", base, u0, u1, y0, y0 + 0.2, 0.035, c(STAIN.darkened(0.2), CourthouseKit.K_WOOD), opens, -1.0)


## A door's casing on a face: jambs, the head over the transom.
static func _casing(f: Transform3D, o: Dictionary) -> void:
	var wood := c(STAIN, CourthouseKit.K_WOOD)
	var u := float(o["u"])
	var w := float(o["w"])
	var y0 := float(o["y0"])
	var ys := float(o["ys"])
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(u + s * (w / 2.0 + 0.07), (y0 + ys) / 2.0, 0.025), Vector3(0.14, ys - y0, 0.05), wood)
	k.box("wall", f, Vector3(u, ys + 0.09, 0.03), Vector3(w + 0.4, 0.18, 0.06), wood)
	k.box("wall", f, Vector3(u, ys + 0.2, 0.05), Vector3(w + 0.48, 0.05, 0.1), wood)


## The door in an opening of a wall t thick: its frame and transom bar,
## the transom's glass, the leaf standing open into the room behind.
static func _door_in(f: Transform3D, o: Dictionary, t: float) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var u := float(o["u"])
	var w := float(o["w"])
	var y0 := float(o["y0"])
	k.box("wall", f, Vector3(u, y0 + DOOR_H + 0.04, -t / 2.0), Vector3(w, 0.08, t), wood)
	var tr := CourthouseKit.opening(u, w, y0 + DOOR_H + 0.08, y0 + OPEN_H, "flat")
	k.glass(f, tr, -t / 2.0)
	var lf := f * Transform3D(Basis(Vector3.UP, -PI / 2.0 + 0.25), Vector3(u + w / 2.0 - 0.03, 0, -t - 0.02))
	k.door_leaf(lf, Vector3(-w / 2.0 + 0.02, y0, 0), w - 0.06, DOOR_H - 0.02, wood, false)
	# A brass knob.
	k.m.sphere("iron", lf * Transform3D(Basis(), Vector3(-w + 0.12, y0 + 0.95, 0.05)), 0.03, 6, GILT)


## The wainscot round the inside of the outer walls, both floors: along
## each outside wall's inner face, cut round its doors and low windows.
static func _outside_wainscot() -> void:
	for s: float in [-1.0, 1.0]:
		var n := Vector3(-s, 0, 0)
		# Inside faces look back into the building.
		var side_u := (MZ + PZ) / 2.0
		for y0: float in [F1, F2]:
			var opens: Array = []
			if y0 == F2:
				for u: float in [-2.9, 0.0, 2.9]:
					opens.append(CourthouseKit.opening(u, 1.55, 6.9, 11.2, "round"))
			else:
				opens.append(CourthouseKit.opening(0.0, 1.9, F1, 4.5, "round"))
				for u: float in [-2.9, 2.9]:
					opens.append(CourthouseKit.opening(u, 1.3, 2.2, 5.0, "segment", 0.25))
			var fp := UnionCourthouse.face(n, Vector3(s * (PX - T), 0, 0))
			_wainscot(fp, -PZ + 0.02, PZ - 0.02, y0, opens)
			for e: float in [-1.0, 1.0]:
				var fm := UnionCourthouse.face(n, Vector3(s * IX, 0, 0))
				var ua := minf(e * IZ, e * PZ)
				var ub := maxf(e * IZ, e * PZ)
				_wainscot(fm, ua, ub, y0, [])
				var fw := UnionCourthouse.face(n, Vector3(s * WIX, 0, 0))
				var wopen: Array = []
				for bay in 5:
					var bu := e * (MZ + (WZ - MZ) * (bay + 0.5) / 5.0)
					wopen.append(CourthouseKit.opening(bu, 1.2, 7.4 if y0 == F2 else 2.4, 9.9 if y0 == F2 else 5.0, "segment", 0.22))
				_wainscot(fw, minf(e * MZ, e * WIZ), maxf(e * MZ, e * WIZ), y0, wopen)
				# The pavilion's returns.
				var fr := UnionCourthouse.face(Vector3(0, 0, -e), Vector3(s * (IX + PX - T) / 2.0, 0, e * (PZ - T)))
				_wainscot(fr, -0.25, 0.25, y0, [])
	for e: float in [-1.0, 1.0]:
		var fe := UnionCourthouse.face(Vector3(0, 0, -e), Vector3(0, 0, e * WIZ))
		for y0: float in [F1, F2]:
			var opens: Array = []
			if y0 == F1:
				opens.append(CourthouseKit.opening(0.0, 1.7, F1, 4.3, "round"))
			else:
				for u: float in [-5.8, -3.2, 3.2, 5.8]:
					opens.append(CourthouseKit.opening(u, 1.2, 7.4, 9.9, "segment", 0.22))
				for u: float in [-0.7, 0.7]:
					opens.append(CourthouseKit.opening(u, 1.05, 7.5, 9.9, "segment", 0.2))
			_wainscot(fe, -WIX, WIX, y0, opens)
		# The main block's end wall: its face to the wing, its face to the
		# main block's rooms and the courtroom.
		var to_wing := UnionCourthouse.face(Vector3(0, 0, e), Vector3(0, 0, e * MZ))
		var to_main := UnionCourthouse.face(Vector3(0, 0, -e), Vector3(0, 0, e * IZ))
		var hall_arch := CourthouseKit.opening(0.0, 2.4, F1, 4.9, "round")
		# Upstairs: the judge's door west of the bench and the niche behind
		# it at the north end, the public's double door at the south. The
		# two faces' u run opposite ways.
		var wing_side: Array = []
		var court_side: Array = []
		if e < 0.0:
			wing_side.append(CourthouseKit.opening(5.2, 1.1, F2, F2 + 2.7, "flat"))
			court_side.append(CourthouseKit.opening(-5.2, 1.1, F2, F2 + 2.7, "flat"))
			court_side.append(CourthouseKit.opening(0.0, 2.6, F2 + 0.7, F2 + 2.8, "round"))
		else:
			wing_side.append(CourthouseKit.opening(0.0, 1.9, F2, F2 + 2.6, "flat"))
			court_side.append(CourthouseKit.opening(0.0, 1.9, F2, F2 + 2.6, "flat"))
		_wainscot(to_wing, -WIX, WIX, F1, [hall_arch])
		_wainscot(to_wing, -WIX, WIX, F2, wing_side)
		_wainscot(to_main, -IX, IX, F1, [hall_arch])
		_wainscot(to_main, -IX, IX, F2, court_side)


## ---- the ground floor ------------------------------------------------------

static func _ground_floor() -> void:
	var y0 := F1
	var y1 := C1
	# The axial hall's walls in the main block, the cross hall's.
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			var za := e * IZ
			var zb := e * 1.5
			iwall(Vector2(s * HALL, za), Vector2(s * HALL, zb), y0, y1, [absf(za - zb) / 2.0])
			var xa := s * HALL
			var xb := s * (PX - T)
			iwall(Vector2(xa, e * 1.5), Vector2(xb, e * 1.5), y0, y1, [3.8])
	# Lamps down the halls.
	for p: Vector3 in [Vector3(0, 0, 0), Vector3(-6.0, 0, 0), Vector3(6.0, 0, 0), Vector3(0, 0, -5.5), Vector3(0, 0, 5.5)]:
		_pendant(Vector3(p.x, y1, p.z), 1.4, p == Vector3.ZERO)
	# Benches along the axial hall, portraits over them.
	for e: float in [-1.0, 1.0]:
		_bench(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-HALL + 0.35, y0, e * 4.8 + 1.5 * e)), 1.8)
		_portrait(UnionCourthouse.face(Vector3(1, 0, 0), Vector3(-HALL + 0.08, 0, e * 6.4)), y0 + 2.1, 0.7, 0.9, e)
		_portrait(UnionCourthouse.face(Vector3(-1, 0, 0), Vector3(HALL - 0.08, 0, e * 3.2)), y0 + 2.1, 0.8, 1.0, -e)
	# A glass case of the county's things in the cross hall.
	for s: float in [-1.0, 1.0]:
		_case(Transform3D(Basis(), Vector3(s * 5.5, y0, -1.1)), 1.6, 0.5, 1.0)
	_heritage_room()
	# The other three rooms of the main block: offices.
	_office(Transform3D(Basis(Vector3.UP, PI), Vector3(5.3, y0, -4.8)), 0)
	_office(Transform3D(Basis(), Vector3(-5.3, y0, 4.8)), 1)
	_office(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(5.3, y0, 4.8)), 2)


## The Heritage Room, the main block's north-west corner: cases down its
## middle, shelves of county records on the walls, a reading table, maps.
static func _heritage_room() -> void:
	var y0 := F1
	for z: float in [-6.2, -3.6]:
		_case(Transform3D(Basis(), Vector3(-5.8, y0, z)), 2.2, 0.8, 0.95)
	for x: float in [-8.2, -6.4, -4.6, -2.8]:
		_bookcase(Transform3D(Basis(), Vector3(x, y0, -IZ + 0.22)), 1.7, 2.3)
	_table(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-3.0, y0, -4.3)), 2.4, 1.0, 0.76, WALNUT)
	for j in 3:
		for s: float in [-1.0, 1.0]:
			_chair(Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(-3.0 + s * 0.8, y0, -5.1 + j * 0.8)))
	# An old county map framed on the cross hall's wall.
	_map(UnionCourthouse.face(Vector3(0, 0, -1), Vector3(-5.0, 0, -1.5 - 0.08)), y0 + 2.2, 1.6, 1.1)
	var label := Label3D.new()
	label.text = "HERITAGE ROOM"
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.75, 0.45)
	label.shaded = true
	label.double_sided = false
	label.transform = UnionCourthouse.face(Vector3(0, 0, 1), Vector3(-HALL - 1.2, 0, -1.5 + 0.09)) * Transform3D(Basis(), Vector3(0, y0 + 3.35, 0))
	b.add_child(label)


## An office: a desk and its chair, a visitor's chair, a filing cabinet,
## a bookcase. xf: its middle, the desk facing +z.
static func _office(xf: Transform3D, kind: int) -> void:
	_desk(xf * Transform3D(Basis(), Vector3(0, 0, -0.6)))
	_chair(xf * Transform3D(Basis(), Vector3(0, 0, -1.4)))
	_chair(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0.3, 0, 0.3)))
	_cabinet(xf * Transform3D(Basis(), Vector3(-2.2 + kind * 0.3, 0, -2.3)))
	_bookcase(xf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-3.0, 0, 0.5)), 1.6, 2.1)
	_pendant(xf * Vector3(0, C1 - F1, 0), 1.0, false)


## ---- the wings ----------------------------------------------------------

## A wing laid out as the north one; w turns it for the south.
static func _wing(w: Transform3D, e: float) -> void:
	var p := func(x: float, z: float) -> Vector2:
		var q := w * Vector3(x, 0, z)
		return Vector2(q.x, q.z)
	# Ground floor.
	var y0 := F1
	var y1 := C1
	iwall(p.call(-HALL, -MZ), p.call(-HALL, -15.0), y0, y1, [3.15])
	iwall(p.call(-HALL, -15.0), p.call(-HALL, -WIZ), y0, y1, [3.2])
	iwall(p.call(-WIX, -15.0), p.call(-HALL, -15.0), y0, y1)
	iwall(p.call(HALL, -12.3), p.call(HALL, -WIZ), y0, y1, [4.7])
	iwall(p.call(HALL, -12.3), p.call(WIX, -12.3), y0, y1)
	# Upstairs.
	y0 = F2
	y1 = C3
	iwall(p.call(-HALL, -MZ), p.call(-HALL, -15.0), y0, y1, [3.35])
	iwall(p.call(-WIX, -15.0), p.call(WIX, -15.0), y0, y1, [WIX])
	iwall(p.call(2.0, -12.3), p.call(2.0, -15.0), y0, y1, [1.35])
	iwall(p.call(2.0, -12.3), p.call(WIX, -12.3), y0, y1)
	_stair(w)
	# Lamps in the halls.
	for z: float in [-11.0, -17.5]:
		_pendant(w * Vector3(0, C1, z), 1.3, z < -12.0)
	_pendant(w * Vector3(0, C3, -11.5), 1.0, false)
	_pendant(w * Vector3(0, C1, -10.6) + (w.basis * Vector3(4.6, 0, 0)), 1.0, false)
	# Rooms. Ground floor: two offices west, one east.
	_office(w * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-4.8, F1, -11.8)), 0)
	_office(w * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-4.8, F1, -18.2)), 1)
	_office(w * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(4.8, F1, -17.0)), 2)
	if e < 0.0:
		# Upstairs north: the judge's chambers, the jury room, an office.
		_chambers(w * Transform3D(Basis(), Vector3(-4.7, F2, -11.8)))
		_jury_room(w * Transform3D(Basis(), Vector3(0, F2, -18.2)))
		_office(w * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(5.0, F2, -13.7)), 1)
	else:
		# Upstairs south: the law library and two offices.
		_library(w * Transform3D(Basis(), Vector3(0, F2, -18.2)))
		_office(w * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-4.7, F2, -11.8)), 2)
		_office(w * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(5.0, F2, -13.7)), 0)
	# Benches in the upstairs hall outside the courtroom.
	_bench(w * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-HALL + 0.35, F2, -13.2)), 1.6)


## The stair in a wing (the north one's frame): the first flight east
## along the main block's wall from the hall to the landing, the second
## back west to the upstairs hall; a newel at each turn, balusters, the
## rail, and a balustrade round the well upstairs.
static func _stair(w: Transform3D) -> void:
	var tread := c(OAK.darkened(0.1), CourthouseKit.K_OAK)
	var white := c(PLASTER, CourthouseKit.K_PLASTER)
	var x0 := 2.0
	var x1 := 6.2
	var n := 15
	var run := (x1 - x0) / n
	# Flight one: z from -8.7 to -10.4, rising east from the hall.
	var f1z := Vector2(-10.4, -8.7)
	var f2z := Vector2(-12.2, -10.6)
	for j in n:
		var rise := (LANDING - F1) * (j + 1) / n
		var x := x0 + run * (j + 0.5)
		k.box("wall", w, Vector3(x, F1 + rise - 0.02, (f1z.x + f1z.y) / 2.0), Vector3(run + 0.03, 0.05, f1z.y - f1z.x), tread)
		k.box("wall", w, Vector3(x - run / 2.0 + 0.01, F1 + rise - (LANDING - F1) / n / 2.0, (f1z.x + f1z.y) / 2.0),
			Vector3(0.02, (LANDING - F1) / n, f1z.y - f1z.x), white)
	# Its open string with the balusters, and the wall's closed string.
	_flight_rail(w, Vector3(x0, F1, f1z.x - 0.05), Vector3(x1, LANDING, f1z.x - 0.05), n)
	k.ramp(w, Vector3(x0 - 0.1, F1, (f1z.x + f1z.y) / 2.0), Vector3(x1, LANDING, (f1z.x + f1z.y) / 2.0), f1z.y - f1z.x)
	# The soffit under it.
	var mid1 := Vector3((x0 + x1) / 2.0, (F1 + LANDING) / 2.0 - 0.25, (f1z.x + f1z.y) / 2.0)
	k.m.box("wall", w * Transform3D(Basis(Vector3.BACK, atan2(LANDING - F1, x1 - x0)), mid1),
		Vector3(sqrt(pow(x1 - x0, 2.0) + pow(LANDING - F1, 2.0)), 0.3, f1z.y - f1z.x), white)
	# The landing across the wing's east end of the stair hall.
	k.block("wall", w, Vector3((x1 + WIX) / 2.0, LANDING - 0.15, (f2z.x + f1z.y) / 2.0), Vector3(WIX - x1, 0.3, f1z.y - f2z.x), white)
	k.box("wall", w, Vector3((x1 + WIX) / 2.0, LANDING + 0.003, (f2z.x + f1z.y) / 2.0), Vector3(WIX - x1, 0.006, f1z.y - f2z.x), tread)
	# Flight two: back west, rising to the upstairs floor.
	for j in n:
		var rise := (F2 - LANDING) * (j + 1) / n
		var x := x1 - run * (j + 0.5)
		k.box("wall", w, Vector3(x, LANDING + rise - 0.02, (f2z.x + f2z.y) / 2.0), Vector3(run + 0.03, 0.05, f2z.y - f2z.x), tread)
		k.box("wall", w, Vector3(x + run / 2.0 - 0.01, LANDING + rise - (F2 - LANDING) / n / 2.0, (f2z.x + f2z.y) / 2.0),
			Vector3(0.02, (F2 - LANDING) / n, f2z.y - f2z.x), white)
	_flight_rail(w, Vector3(x1, LANDING, f2z.y + 0.05), Vector3(x0, F2, f2z.y + 0.05), n)
	k.ramp(w, Vector3(x1, LANDING, (f2z.x + f2z.y) / 2.0), Vector3(x0, F2, (f2z.x + f2z.y) / 2.0), f2z.y - f2z.x)
	var mid2 := Vector3((x0 + x1) / 2.0, (LANDING + F2) / 2.0 - 0.25, (f2z.x + f2z.y) / 2.0)
	k.m.box("wall", w * Transform3D(Basis(Vector3.BACK, -atan2(F2 - LANDING, x1 - x0)), mid2),
		Vector3(sqrt(pow(x1 - x0, 2.0) + pow(F2 - LANDING, 2.0)), 0.3, f2z.y - f2z.x), white)
	# The well's balustrade upstairs: along its hall side over flight one,
	# and between the flights.
	_balustrade(w, Vector3(x0, F2, -MZ - 0.05), Vector3(x0, F2, f2z.y + 0.1))
	# The massive newels: at the foot, at the landing, at the head.
	for p: Vector3 in [Vector3(x0 - 0.1, F1, f1z.x - 0.05), Vector3(x1 + 0.05, LANDING, f1z.x - 0.05),
			Vector3(x1 + 0.05, LANDING, f2z.y + 0.05), Vector3(x0 - 0.1, F2, f2z.y + 0.05)]:
		_newel(w, p)
	# A wall between the flights, below the landing: the stair hall's
	# closet under the second flight.
	k.box("wall", w, Vector3((x0 + x1) / 2.0 + 0.5, (F1 + LANDING) / 2.0, (f1z.x + f2z.y) / 2.0),
		Vector3(x1 - x0 - 1.0, LANDING - F1, 0.12), c(WALNUT, 18))
	k.solid(w, Vector3((x0 + x1) / 2.0 + 0.5, (F1 + LANDING) / 2.0, (f1z.x + f2z.y) / 2.0), Vector3(x1 - x0 - 1.0, LANDING - F1, 0.12))
	# A globe over the landing.
	_pendant(w * Vector3((x1 + WIX) / 2.0, C3, (f1z.x + f2z.x) / 2.0), 3.0, false)


## A flight's balustrade from a (foot) to b (head): balusters two to a
## tread, the moulded rail over them.
static func _flight_rail(w: Transform3D, a: Vector3, bb: Vector3, n: int) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var h := 0.85
	var rise := (bb.y - a.y) / n
	for j in 2 * n:
		var t := (j + 0.5) / (2.0 * n)
		var p := a.lerp(bb, t)
		var step := floorf(t * n) + 1.0
		var foot := Vector3(p.x, a.y + rise * step, p.z)
		k.turned("wall", w, foot, h + (p.y - foot.y) + rise * 0.5, 0.035, wood, 6)
	k.m.box("wall", w * Transform3D(Basis(Vector3.BACK, atan2(bb.y - a.y, bb.x - a.x)) if absf(bb.x - a.x) > 0.01 else Transform3D(),
		(a + bb) / 2.0 + Vector3(0, h + 0.05, 0)), Vector3(a.distance_to(bb) + 0.1, 0.1, 0.09), wood)
	k.solid(w, (a + bb) / 2.0 + Vector3(0, 0.6, 0), Vector3(absf(bb.x - a.x) + 0.05, 1.2 + absf(bb.y - a.y), 0.08))


## A level balustrade from a to b.
static func _balustrade(w: Transform3D, a: Vector3, bb: Vector3) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var length := a.distance_to(bb)
	var n := int(length / 0.14)
	for j in n:
		k.turned("wall", w, a.lerp(bb, (j + 0.5) / n), 0.9, 0.035, wood, 6)
	var mid := (a + bb) / 2.0
	var along := (bb - a).normalized()
	var size := Vector3(absf(along.x) * length + 0.1, 0.1, absf(along.z) * length + 0.1)
	k.box("wall", w, mid + Vector3(0, 0.95, 0), Vector3(maxf(size.x, 0.09), 0.1, maxf(size.z, 0.09)), wood)
	k.box("wall", w, mid + Vector3(0, 0.03, 0), Vector3(maxf(size.x, 0.07), 0.06, maxf(size.z, 0.07)), wood)
	k.solid(w, mid + Vector3(0, 0.55, 0), Vector3(maxf(size.x, 0.1), 1.1, maxf(size.z, 0.1)))


## A newel post: a panelled shaft on a plinth under a moulded cap and a
## turned finial.
static func _newel(w: Transform3D, foot: Vector3) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var dark := c(WALNUT.darkened(0.25), CourthouseKit.K_WOOD)
	k.box("wall", w, foot + Vector3(0, 0.1, 0), Vector3(0.34, 0.2, 0.34), wood)
	k.box("wall", w, foot + Vector3(0, 0.6, 0), Vector3(0.28, 0.8, 0.28), wood)
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		k.box("wall", w, foot + Vector3(0, 0.6, 0) + d * 0.141, Vector3(0.16 if d.z != 0.0 else 0.005, 0.6, 0.16 if d.x != 0.0 else 0.005), dark)
	k.box("wall", w, foot + Vector3(0, 1.05, 0), Vector3(0.36, 0.1, 0.36), wood)
	k.box("wall", w, foot + Vector3(0, 1.13, 0), Vector3(0.3, 0.06, 0.3), wood)
	k.m.cylinder("wall", w * Transform3D(Basis(), foot + Vector3(0, 1.24, 0)), 0.1, 0.05, 0.16, 8, wood)
	k.m.sphere("wall", w * Transform3D(Basis(), foot + Vector3(0, 1.36, 0)), 0.07, 8, wood)
	k.solid(w, foot + Vector3(0, 0.6, 0), Vector3(0.3, 1.2, 0.3))


## ---- the courtroom ------------------------------------------------------

static func _courtroom() -> void:
	var y := F2
	var g := Transform3D()
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var panel := c(WALNUT.darkened(0.15), CourthouseKit.K_WOOD)
	# Pilasters between the bays down each side, the entablature round the
	# room, garlands and cartouches in its frieze.
	var ent0 := 12.35
	for s: float in [-1.0, 1.0]:
		for u: float in [-7.95, -5.3, -4.35, -1.45, 1.45, 4.35, 5.3, 7.95]:
			var x := s * (IX if absf(u) > PZ else PX - T)
			_pilaster(Vector3(x, 0, u), Vector3(-s, 0, 0), y + WAINSCOT + 0.06, ent0)
	for e: float in [-1.0, 1.0]:
		for x: float in [-7.0, -3.4, 3.4, 7.0]:
			_pilaster(Vector3(x, 0, e * IZ), Vector3(0, 0, -e), y + WAINSCOT + 0.06, ent0)
	_entablature(ent0, C2)
	# The bench at the north end: a dais, the panelled desk, the chair,
	# the flags either side of the niche.
	var dais := 0.55
	k.block("wall", g, Vector3(0, y + dais / 2.0, -IZ + 1.2), Vector3(6.6, dais, 2.4), wood)
	k.box("wall", g, Vector3(0, y + dais + 0.003, -IZ + 1.2), Vector3(6.5, 0.006, 2.3), c(Color(0.35, 0.12, 0.10), CourthouseKit.K_CLOTH))
	for s: float in [-1.0, 1.0]:
		k.ramp(g, Vector3(s * 4.3, y, -IZ + 0.6), Vector3(s * 3.3, y + dais, -IZ + 0.6), 0.9)
	var desk_z := -IZ + 2.1
	_panelled(Transform3D(Basis(), Vector3(0, y + dais, desk_z)), 5.2, 1.2, wood, panel, 5)
	k.block("wall", g, Vector3(0, y + dais + 1.22, desk_z - 0.35), Vector3(5.5, 0.06, 0.9), wood)
	for s: float in [-1.0, 1.0]:
		k.box("wall", g, Vector3(s * 2.6, y + dais + 0.6, desk_z - 0.4), Vector3(0.08, 1.2, 0.8), wood)
	_high_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + dais, -IZ + 0.7)))
	for s: float in [-1.0, 1.0]:
		_flag(Vector3(s * 2.1, y + dais, -IZ + 0.4), s < 0.0)
	# A seal in the niche.
	var nf := UnionCourthouse.face(Vector3(0, 0, 1), Vector3(0, 0, -MZ + 0.15))
	k.box("wall", nf, Vector3(0, y + 2.6, 0.02), Vector3(0.9, 1.1, 0.04), c(Color(0.12, 0.10, 0.08), CourthouseKit.K_WOOD))
	k.box("wall", nf, Vector3(0, y + 2.6, 0.045), Vector3(0.75, 0.95, 0.01), c(GILT.darkened(0.3), CourthouseKit.K_PAINT))
	# The clerk's desk below the bench.
	_panelled(Transform3D(Basis(), Vector3(0, y, desk_z + 0.9)), 3.6, 1.05, wood, panel, 4)
	k.block("wall", g, Vector3(0, y + 1.07, desk_z + 0.6), Vector3(3.8, 0.05, 0.75), wood)
	_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(-0.8, y, desk_z + 0.1)))
	_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(0.8, y, desk_z + 0.1)))
	# The witness stand, east of the bench.
	var wx := 4.3
	var wz := -IZ + 1.7
	k.block("wall", g, Vector3(wx, y + 0.15, wz), Vector3(1.6, 0.3, 1.6), wood)
	_panelled(Transform3D(Basis(), Vector3(wx, y + 0.3, wz + 0.78)), 1.6, 0.95, wood, panel, 2)
	_panelled(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(wx - 0.78, y + 0.3, wz)), 1.6, 0.95, wood, panel, 2)
	_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(wx, y + 0.3, wz - 0.2)))
	# The jury box along the east wall: two rows, the back one raised.
	var jx := IX - 1.6
	for row in 2:
		var ry := 0.15 + 0.3 * row
		var rx := jx + 0.1 + row * 0.95
		k.block("wall", g, Vector3(rx, y + ry / 2.0, -3.4), Vector3(0.95, ry, 5.6), wood)
		for j in 6:
			_chair(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(rx + 0.1, y + ry, -5.6 + j * 0.88)))
	_panelled(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(jx - 0.45, y, -3.4)), 5.6, 1.0, wood, panel, 6)
	k.block("wall", g, Vector3(jx - 0.45, y + 1.02, -3.4), Vector3(0.14, 0.05, 5.7), wood)
	_panelled(Transform3D(Basis(), Vector3(jx + 0.5, y, -0.55)), 2.1, 1.0, wood, panel, 2)
	# Counsel tables, their chairs, a lectern between.
	for s: float in [-1.0, 1.0]:
		_table(Transform3D(Basis(), Vector3(s * 2.6, y, -1.7)), 2.4, 1.0, 0.78, WALNUT)
		for j in 3:
			_chair(Transform3D(Basis(Vector3.UP, PI), Vector3(s * 2.6 - 0.8 + j * 0.8, y, -0.95)))
	_lectern(Transform3D(Basis(), Vector3(0, y, -2.9)))
	# The bar across the room, its gate in the aisle.
	var bar_z := 0.6
	for s: float in [-1.0, 1.0]:
		_balustrade(g, Vector3(s * 0.65, y, bar_z), Vector3(s * (IX - 0.05), y, bar_z))
		_newel(g, Vector3(s * 0.65, y, bar_z))
		# The gate leaf, swung shut.
		k.box("wall", g, Vector3(s * 0.33, y + 0.5, bar_z), Vector3(0.6, 0.8, 0.05), panel)
		k.box("wall", g, Vector3(s * 0.33, y + 0.93, bar_z), Vector3(0.62, 0.06, 0.08), wood)
	# The public's pews, two blocks either side of the aisle, running
	# back under the balcony.
	_balcony()
	for j in 6:
		var pz := 1.9 + j * 0.92
		for s: float in [-1.0, 1.0]:
			_pew(Transform3D(Basis(), Vector3(s * 4.7, y, pz)), 7.0)
	# The lamps: four pendants over the room, and their light after dark.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_chandelier(Vector3(sx * 4.2, C2, -4.6 if sz < 0.0 else 0.8))
	# Radiators under the side windows.
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			_radiator(Transform3D(Basis(Vector3.UP, -s * PI / 2.0), Vector3(s * (IX - 0.18), y, e * 6.6)), 1.1)


## The gallery across the courtroom's south end: four tiers of pews
## rising to an aisle along the back wall, a panelled front with a pipe
## rail on posts over it, iron columns under its front, a sloping aisle
## down its middle; a stair in each back corner rising along the south
## wall, under the gallery, to the back aisle.
static func _balcony() -> void:
	var y := F2
	var g := Transform3D()
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var panel := c(WALNUT.darkened(0.15), CourthouseKit.K_WOOD)
	var oak := c(OAK, CourthouseKit.K_OAK)
	var soffit := c(CEILING, CourthouseKit.K_PLASTER)
	var front := 3.4          # the gallery's front, z
	var under := y + 2.7      # its soffit
	var tier := 0.95
	var aisle_x := 0.6
	var well := Vector2(2.5, 7.4)    # each stair's opening in the back aisle, |x|
	var back := front + 4.0 * tier   # the back aisle, z
	# The tiers, each side of the middle aisle.
	for t in 4:
		var top := y + 3.0 + 0.3 * t
		var z0 := front + tier * t
		for sx: float in [-1.0, 1.0]:
			var cx := sx * (aisle_x + IX) / 2.0
			var cen := Vector3(cx, (under + top) / 2.0, z0 + tier / 2.0)
			var size := Vector3(IX - aisle_x, top - under, tier)
			k.block("wall", g, cen, size, wood)
			k.box("wall", g, Vector3(cx, top + 0.003, z0 + tier / 2.0), Vector3(IX - aisle_x, 0.006, tier), oak)
			_pew(Transform3D(Basis(), Vector3(cx, top, z0 + 0.35)), IX - aisle_x - 0.3)
	# The back aisle along the south wall, open over each stair.
	var top_b := y + 3.9
	for seg: Vector2 in [Vector2(-IX, -well.y), Vector2(-well.x, well.x), Vector2(well.y, IX)]:
		var cen := Vector3((seg.x + seg.y) / 2.0, (under + top_b) / 2.0, (back + IZ) / 2.0)
		var size := Vector3(seg.y - seg.x, top_b - under, IZ - back)
		k.block("wall", g, cen, size, wood)
		k.box("wall", g, Vector3(cen.x, top_b + 0.003, cen.z), Vector3(size.x, 0.006, size.z), oak)
	# The middle aisle: a slope underfoot, shallow steps to the eye.
	k.ramp(g, Vector3(0, y + 3.0, front), Vector3(0, top_b, back), 2.0 * aisle_x)
	for j in 8:
		var z := front + (back - front) * (j + 0.5) / 8.0
		var st := y + 3.0 + 0.9 * (j + 1) / 8.0
		k.box("wall", g, Vector3(0, (under + st) / 2.0, z), Vector3(2.0 * aisle_x, st - under, (back - front) / 8.0), oak)
	# The soffit under it all.
	k.box("wall", g, Vector3(0, under - 0.03, (front + back) / 2.0), Vector3(2.0 * IX, 0.06, back - front), soffit)
	# The front: panels, a moulded cap, the pipe rail on posts.
	var fy := y + 3.0
	_panelled(Transform3D(Basis(Vector3.UP, PI), Vector3(0, fy, front)), 2.0 * IX, 1.0, wood, panel, 14)
	k.box("wall", g, Vector3(0, (under + fy) / 2.0, front - 0.02), Vector3(2.0 * IX, fy - under, 0.06), panel)
	k.box("wall", g, Vector3(0, fy + 1.03, front), Vector3(2.0 * IX, 0.07, 0.2), wood)
	var brass := GILT.darkened(0.35)
	for j in 11:
		var x := -IX + 0.3 + (2.0 * IX - 0.6) * j / 10.0
		k.m.bar("iron", Vector3(x, fy + 1.06, front), Vector3(x, fy + 1.34, front), 0.02, 6, brass)
	k.m.bar("iron", Vector3(-IX + 0.1, fy + 1.34, front), Vector3(IX - 0.1, fy + 1.34, front), 0.028, 8, brass)
	# Iron columns under the front.
	for x: float in [-7.2, -3.4, 3.4, 7.2]:
		k.m.cylinder("iron", Transform3D(Basis(), Vector3(x, (y + under) / 2.0, front + 0.15)), 0.08, 0.08, under - y, 10, IRON)
		k.m.cylinder("iron", Transform3D(Basis(), Vector3(x, under - 0.1, front + 0.15)), 0.16, 0.09, 0.2, 10, IRON)
		k.m.cylinder("iron", Transform3D(Basis(), Vector3(x, y + 0.08, front + 0.15)), 0.12, 0.14, 0.16, 10, IRON)
		k.solid(g, Vector3(x, y + 1.3, front + 0.15), Vector3(0.18, 2.6, 0.18))
	# The stairs: from the foot by each side wall, east or west along the
	# south wall to the back aisle, a balustrade on their open side, and
	# round each opening in the aisle.
	var sz := Vector2(back, IZ)
	for sx: float in [-1.0, 1.0]:
		var x0 := sx * (IX - 1.0)
		var x1 := sx * well.x
		var n := 22
		var run := absf(x1 - x0) / n
		for j in n:
			var rise := (top_b - y) * (j + 1) / n
			var x := x0 - sx * run * (j + 0.5)
			k.box("wall", g, Vector3(x, y + rise - 0.02, (sz.x + sz.y) / 2.0), Vector3(run + 0.03, 0.05, sz.y - sz.x), oak)
			k.box("wall", g, Vector3(x + sx * run / 2.0, y + rise - (top_b - y) / n / 2.0, (sz.x + sz.y) / 2.0),
				Vector3(0.02, (top_b - y) / n, sz.y - sz.x), c(PLASTER, CourthouseKit.K_PLASTER))
		k.ramp(g, Vector3(x0, y, (sz.x + sz.y) / 2.0), Vector3(x1, top_b, (sz.x + sz.y) / 2.0), sz.y - sz.x)
		_flight_rail(g, Vector3(x0, y, sz.x - 0.04), Vector3(x1, top_b, sz.x - 0.04), n)
		_newel(g, Vector3(x0, y, sz.x - 0.04))
		# The opening's rail on the gallery, along the back tier.
		_balustrade(g, Vector3(sx * well.y, top_b, sz.x - 0.05), Vector3(sx * (well.x + 0.3), top_b, sz.x - 0.05))
	# Lamps under the gallery.
	for x: float in [-4.5, 4.5]:
		_pendant(Vector3(x, under - 0.06, (front + IZ) / 2.0), 0.4, false)


## A pilaster on a wall at base (x, z on the wall's face) standing out
## along n from y0 to y1: plinth, shaft with its flutes, capital.
static func _pilaster(base: Vector3, n: Vector3, y0: float, y1: float) -> void:
	var f := UnionCourthouse.face(n, Vector3(base.x, 0, base.z))
	var col := c(PLASTER.lightened(0.15), CourthouseKit.K_PLASTER)
	var dark := c(PLASTER.darkened(0.15), CourthouseKit.K_PLASTER)
	k.box("wall", f, Vector3(0, (y0 + y1) / 2.0, 0.05), Vector3(0.5, y1 - y0, 0.1), col)
	for fl: float in [-0.14, -0.07, 0.0, 0.07, 0.14]:
		k.box("wall", f, Vector3(fl, (y0 + y1) / 2.0, 0.101), Vector3(0.025, y1 - y0 - 0.8, 0.003), dark)
	k.box("wall", f, Vector3(0, y0 + 0.12, 0.07), Vector3(0.6, 0.24, 0.14), col)
	k.box("wall", f, Vector3(0, y1 - 0.2, 0.08), Vector3(0.62, 0.4, 0.16), col)
	k.box("wall", f, Vector3(0, y1 - 0.44, 0.07), Vector3(0.56, 0.08, 0.14), c(GILT, CourthouseKit.K_PAINT))


## The courtroom's entablature from y0 to the ceiling at y1, round all
## four walls: architrave, the frieze of garlands between cartouches,
## the cornice coved to the ceiling.
static func _entablature(y0: float, y1: float) -> void:
	var trim := c(PLASTER.lightened(0.15), CourthouseKit.K_PLASTER)
	var frieze := c(FRIEZE, CourthouseKit.K_PAINT)
	var gilt := c(GILT, CourthouseKit.K_PAINT)
	var green := c(Color(0.24, 0.34, 0.18), CourthouseKit.K_PAINT)
	# The walls: [frame, length]; the frame's x runs along the face.
	var walls: Array = []
	for s: float in [-1.0, 1.0]:
		walls.append([UnionCourthouse.face(Vector3(-s, 0, 0), Vector3(s * IX, 0, 0)), 2.0 * IZ])
	for e: float in [-1.0, 1.0]:
		walls.append([UnionCourthouse.face(Vector3(0, 0, -e), Vector3(0, 0, e * IZ)), 2.0 * IX])
	for wl: Array in walls:
		var f := wl[0] as Transform3D
		var len := float(wl[1])
		k.box("wall", f, Vector3(0, y0 + 0.14, 0.08), Vector3(len, 0.28, 0.16), trim)
		k.box("wall", f, Vector3(0, y0 + 0.6, 0.05), Vector3(len, 0.64, 0.1), frieze)
		k.box("wall", f, Vector3(0, y0 + 0.95, 0.14), Vector3(len, 0.08, 0.28), trim)
		k.box("wall", f, Vector3(0, y0 + 1.1, 0.24), Vector3(len, 0.22, 0.48), trim)
		k.box("wall", f, Vector3(0, (y0 + 1.21 + y1) / 2.0, 0.12), Vector3(len, y1 - y0 - 1.21, 0.24), trim)
		# Cartouches every 2.3 m, a garland swagged between each pair.
		var n := int(len / 2.3)
		for j in n + 1:
			var u := -len / 2.0 + 0.3 + (len - 0.6) * j / n
			k.m.sphere("wall", f * Transform3D(Basis().scaled(Vector3(0.7, 1.0, 0.25)), Vector3(u, y0 + 0.6, 0.12)), 0.24, 10, gilt)
			if j == n:
				continue
			var nxt := -len / 2.0 + 0.3 + (len - 0.6) * (j + 1) / n
			for q in 9:
				var t := (q + 0.5) / 9.0
				var gu := lerpf(u + 0.25, nxt - 0.25, t)
				var sag := 0.18 * sin(PI * t)
				k.m.sphere("wall", f * Transform3D(Basis(), Vector3(gu, y0 + 0.78 - sag, 0.12)), 0.075, 6, green)
			for end: float in [u + 0.25, nxt - 0.25]:
				k.box("wall", f, Vector3(end, y0 + 0.7, 0.13), Vector3(0.05, 0.2, 0.04), gilt)


## ---- furniture -------------------------------------------------------------

## A hanging globe on a chain from a ceiling at top; drop: its chain.
## lit: it throws light after dark (the others only glow).
static func _pendant(top: Vector3, drop: float, lit: bool) -> void:
	k.m.bar("iron", top, top - Vector3(0, drop, 0), 0.008, 4, GILT.darkened(0.3))
	k.m.cylinder("iron", Transform3D(Basis(), top - Vector3(0, drop + 0.04, 0)), 0.08, 0.1, 0.08, 10, GILT.darkened(0.2))
	k.m.sphere("lamp", Transform3D(Basis(), top - Vector3(0, drop + 0.25, 0)), 0.2, 12, Color(1, 1, 1))
	if lit:
		b._light(top - Vector3(0, drop + 0.4, 0), 2.2, 11.0)


## A brass chandelier: a stem, a ring of six arms each with a globe.
static func _chandelier(top: Vector3) -> void:
	var brass := GILT.darkened(0.15)
	var hub := top - Vector3(0, 2.4, 0)
	k.m.bar("iron", top, hub, 0.02, 6, brass)
	k.m.sphere("iron", Transform3D(Basis(), hub), 0.12, 10, brass)
	for j in 6:
		var a := TAU * j / 6.0
		var tip := hub + Vector3(cos(a) * 0.6, 0.1, sin(a) * 0.6)
		k.m.bar("iron", hub, tip, 0.015, 5, brass)
		k.m.sphere("lamp", Transform3D(Basis(), tip + Vector3(0, 0.15, 0)), 0.11, 10, Color(1, 1, 1))
	b._light(hub, 3.0, 13.0)


## A panelled front w wide and h high, its face along the frame's x,
## facing +z, bottom centre at the frame's origin; solid.
static func _panelled(xf: Transform3D, w: float, h: float, wood: Color, panel: Color, n: int) -> void:
	k.box("wall", xf, Vector3(0, h / 2.0, 0), Vector3(w, h, 0.06), wood)
	for j in n:
		var u := -w / 2.0 + w * (j + 0.5) / n
		k.box("wall", xf, Vector3(u, h * 0.55, 0.035), Vector3(w / n - 0.16, h * 0.6, 0.015), panel)
	k.box("wall", xf, Vector3(0, h - 0.03, 0.02), Vector3(w + 0.06, 0.06, 0.1), wood)
	k.box("wall", xf, Vector3(0, 0.07, 0.02), Vector3(w + 0.02, 0.14, 0.09), wood)
	k.solid(xf, Vector3(0, h / 2.0, 0), Vector3(w, h, 0.1))


static func _table(xf: Transform3D, w: float, d: float, h: float, col: Color) -> void:
	var wood := c(col, CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, h - 0.025, 0), Vector3(w, 0.05, d), wood)
	k.box("wall", xf, Vector3(0, h - 0.12, 0), Vector3(w - 0.1, 0.14, d - 0.1), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(sx * (w / 2.0 - 0.1), (h - 0.05) / 2.0, sz * (d / 2.0 - 0.1))),
				0.035, 0.05, h - 0.05, 6, wood)
	k.solid(xf, Vector3(0, h / 2.0, 0), Vector3(w, h, d))


## A bentwood office chair facing -z (its back at +z).
static func _chair(xf: Transform3D) -> void:
	var wood := c(WALNUT.lightened(0.1), CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.46, 0), Vector3(0.44, 0.04, 0.42), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box("wall", xf, Vector3(sx * 0.19, 0.23, sz * 0.18), Vector3(0.035, 0.46, 0.035), wood)
		k.box("wall", xf, Vector3(sx * 0.19, 0.72, 0.2), Vector3(0.035, 0.52, 0.035), wood)
	k.box("wall", xf, Vector3(0, 0.82, 0.2), Vector3(0.42, 0.16, 0.025), wood)
	k.box("wall", xf, Vector3(0, 0.6, 0.2), Vector3(0.42, 0.05, 0.02), wood)


## The judge's chair: high backed, buttoned leather.
static func _high_chair(xf: Transform3D) -> void:
	var hide := c(LEATHER, CourthouseKit.K_CLOTH)
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.25, 0), Vector3(0.6, 0.5, 0.56), wood)
	k.box("wall", xf, Vector3(0, 0.55, 0), Vector3(0.58, 0.12, 0.54), hide)
	k.box("wall", xf, Vector3(0, 1.05, 0.26), Vector3(0.62, 1.0, 0.12), hide)
	for s: float in [-1.0, 1.0]:
		k.box("wall", xf, Vector3(s * 0.32, 0.75, 0.0), Vector3(0.08, 0.3, 0.5), hide)


## A long bench of wood with a slatted back, len long, facing -z.
static func _bench(xf: Transform3D, len: float) -> void:
	var wood := c(OAK.darkened(0.25), CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.44, 0), Vector3(len, 0.05, 0.42), wood)
	for s: float in [-1.0, 1.0]:
		k.box("wall", xf, Vector3(s * (len / 2.0 - 0.05), 0.45, 0.05), Vector3(0.06, 0.9, 0.5), wood)
	for j in 3:
		k.box("wall", xf, Vector3(0, 0.6 + j * 0.13, 0.21), Vector3(len - 0.1, 0.08, 0.025), wood)
	k.solid(xf, Vector3(0, 0.3, 0), Vector3(len, 0.6, 0.45))


## A pew facing -z: seat, a raked back, scrolled ends, len long.
static func _pew(xf: Transform3D, len: float) -> void:
	var wood := c(OAK.darkened(0.3), CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.44, 0.02), Vector3(len, 0.05, 0.42), wood)
	k.m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 0.72, 0.26)), Vector3(len, 0.55, 0.035), wood)
	k.box("wall", xf, Vector3(0, 0.22, 0.2), Vector3(len, 0.44, 0.03), wood)
	for s: float in [-1.0, 1.0]:
		k.box("wall", xf, Vector3(s * (len / 2.0 + 0.03), 0.48, 0.12), Vector3(0.06, 0.96, 0.62), wood)
		k.m.cylinder("wall", xf * Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(s * (len / 2.0 + 0.03), 0.96, 0.2)), 0.08, 0.08, 0.07, 10, wood)
	k.solid(xf, Vector3(0, 0.45, 0.12), Vector3(len, 0.9, 0.6))


## A glass-topped case on a wooden base, its contents a few objects.
static func _case(xf: Transform3D, w: float, d: float, h: float) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, h * 0.4, 0), Vector3(w, h * 0.8, d), wood)
	k.box("wall", xf, Vector3(0, h * 0.8 + 0.01, 0), Vector3(w - 0.08, 0.02, d - 0.08), c(Color(0.35, 0.12, 0.10), CourthouseKit.K_CLOTH))
	var gf := xf * Transform3D(Basis(), Vector3(0, 0, 0))
	for s: float in [-1.0, 1.0]:
		k.m.quad("glass", gf * Vector3(-w / 2.0, h * 0.8, s * d / 2.0), gf * Vector3(-w / 2.0, h + 0.2, s * d / 2.0),
			gf * Vector3(w / 2.0, h + 0.2, s * d / 2.0), gf * Vector3(w / 2.0, h * 0.8, s * d / 2.0), gf.basis.z * s, Color(1, 1, 1))
		k.m.quad("glass", gf * Vector3(s * w / 2.0, h * 0.8, -d / 2.0), gf * Vector3(s * w / 2.0, h + 0.2, -d / 2.0),
			gf * Vector3(s * w / 2.0, h + 0.2, d / 2.0), gf * Vector3(s * w / 2.0, h * 0.8, d / 2.0), gf.basis.x * s, Color(1, 1, 1))
	k.m.quad("glass", gf * Vector3(-w / 2.0, h + 0.2, -d / 2.0), gf * Vector3(w / 2.0, h + 0.2, -d / 2.0),
		gf * Vector3(w / 2.0, h + 0.2, d / 2.0), gf * Vector3(-w / 2.0, h + 0.2, d / 2.0), gf.basis.y, Color(1, 1, 1))
	k.box("wall", xf, Vector3(0, h + 0.21, 0), Vector3(w + 0.02, 0.03, d + 0.02), wood)
	# The things in it: a ledger, a gavel, papers.
	k.box("wall", xf, Vector3(-w * 0.25, h * 0.8 + 0.05, 0), Vector3(0.36, 0.06, 0.26), c(Color(0.4, 0.14, 0.08), CourthouseKit.K_CLOTH))
	k.box("wall", xf, Vector3(w * 0.1, h * 0.8 + 0.03, 0.05), Vector3(0.3, 0.01, 0.22), c(Color(0.86, 0.82, 0.70), CourthouseKit.K_PAINT))
	k.m.cylinder("wall", xf * Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(w * 0.3, h * 0.8 + 0.06, -0.05)), 0.04, 0.04, 0.14, 8, wood)
	k.solid(xf, Vector3(0, h / 2.0, 0), Vector3(w, h, d))


## A bookcase against a wall, its back at the frame's -z: shelves of
## bound volumes in a few colours.
static func _bookcase(xf: Transform3D, w: float, h: float) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	var d := 0.36
	k.box("wall", xf, Vector3(0, h / 2.0, -0.02), Vector3(w, h, 0.03), wood)
	for s: float in [-1.0, 1.0]:
		k.box("wall", xf, Vector3(s * w / 2.0, h / 2.0, d / 2.0 - 0.02), Vector3(0.04, h, d), wood)
	var shelves := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(xf.origin.x * 131.0 + xf.origin.z * 17.0))
	var bindings: Array[Color] = [Color(0.35, 0.10, 0.08), Color(0.12, 0.20, 0.12), Color(0.14, 0.14, 0.24), Color(0.45, 0.32, 0.16),
		Color(0.25, 0.17, 0.10)]
	for j in shelves + 1:
		var sy := 0.08 + (h - 0.12) * j / shelves
		k.box("wall", xf, Vector3(0, sy, d / 2.0 - 0.02), Vector3(w, 0.03, d), wood)
		if j == shelves:
			continue
		var u := -w / 2.0 + 0.05
		while u < w / 2.0 - 0.12:
			var bw := rng.randf_range(0.04, 0.08)
			var bh := rng.randf_range(0.24, 0.33)
			k.box("wall", xf, Vector3(u + bw / 2.0, sy + 0.015 + bh / 2.0, d / 2.0 - 0.04), Vector3(bw - 0.004, bh, 0.26),
				c(bindings[rng.randi() % bindings.size()], CourthouseKit.K_CLOTH))
			u += bw
	k.solid(xf, Vector3(0, h / 2.0, d / 2.0), Vector3(w, h, d))


static func _desk(xf: Transform3D) -> void:
	var wood := c(OAK.darkened(0.1), CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.76, 0), Vector3(1.5, 0.05, 0.8), wood)
	for s: float in [-1.0, 1.0]:
		k.box("wall", xf, Vector3(s * 0.52, 0.37, 0), Vector3(0.42, 0.74, 0.76), wood)
		for j in 3:
			k.box("wall", xf, Vector3(s * 0.52, 0.15 + j * 0.22, -0.385), Vector3(0.36, 0.18, 0.01), c(OAK.darkened(0.25), CourthouseKit.K_WOOD))
	# A blotter, a lamp, papers.
	k.box("wall", xf, Vector3(0, 0.79, 0.05), Vector3(0.6, 0.01, 0.45), c(Color(0.14, 0.22, 0.14), CourthouseKit.K_CLOTH))
	k.m.cylinder("wall", xf * Transform3D(Basis(), Vector3(0.55, 0.82, 0.25)), 0.08, 0.08, 0.03, 8, c(GILT, CourthouseKit.K_PAINT))
	k.m.bar("iron", xf * Vector3(0.55, 0.82, 0.25), xf * Vector3(0.55, 1.15, 0.25), 0.01, 4, GILT)
	k.m.cylinder("wall", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.55, 1.15, 0.2)), 0.07, 0.07, 0.25, 8,
		c(Color(0.12, 0.30, 0.16), CourthouseKit.K_ENAMEL))
	k.solid(xf, Vector3(0, 0.4, 0), Vector3(1.5, 0.8, 0.8))


static func _cabinet(xf: Transform3D) -> void:
	var steel := c(Color(0.36, 0.38, 0.34), CourthouseKit.K_ENAMEL)
	k.box("wall", xf, Vector3(0, 0.66, 0), Vector3(0.46, 1.32, 0.62), steel)
	for j in 4:
		k.box("wall", xf, Vector3(0, 0.18 + j * 0.32, 0.315), Vector3(0.4, 0.28, 0.01), c(Color(0.42, 0.44, 0.40), CourthouseKit.K_ENAMEL))
		k.box("wall", xf, Vector3(0, 0.25 + j * 0.32, 0.325), Vector3(0.12, 0.02, 0.02), c(GILT, CourthouseKit.K_PAINT))
	k.solid(xf, Vector3(0, 0.66, 0), Vector3(0.46, 1.32, 0.62))


static func _lectern(xf: Transform3D) -> void:
	var wood := c(WALNUT, CourthouseKit.K_WOOD)
	k.box("wall", xf, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4), wood)
	k.m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 1.15, 0)), Vector3(0.62, 0.04, 0.5), wood)
	k.solid(xf, Vector3(0, 0.55, 0), Vector3(0.5, 1.1, 0.4))


## A flag on its pole with a gilt eagle: the national colours or the
## state's, hanging in folds.
static func _flag(foot: Vector3, national: bool) -> void:
	var g := Transform3D()
	k.m.cylinder("iron", g * Transform3D(Basis(), foot + Vector3(0, 0.05, 0)), 0.18, 0.2, 0.1, 10, GILT.darkened(0.3))
	k.m.bar("wall", foot, foot + Vector3(0, 2.6, 0), 0.02, 6, c(WALNUT, CourthouseKit.K_WOOD))
	k.m.sphere("iron", Transform3D(Basis(), foot + Vector3(0, 2.68, 0)), 0.07, 8, GILT)
	# The cloth: bands down from the top of the pole, in folds.
	var bands: Array[Color] = []
	if national:
		for j in 13:
			bands.append(Color(0.62, 0.08, 0.10) if j % 2 == 0 else Color(0.92, 0.90, 0.86))
	else:
		bands = [Color(0.14, 0.18, 0.40), Color(0.14, 0.18, 0.40), Color(0.62, 0.08, 0.10), Color(0.62, 0.08, 0.10),
			Color(0.92, 0.90, 0.86), Color(0.92, 0.90, 0.86)]
	var top := foot.y + 2.5
	var h := 1.5
	for j in bands.size():
		var y := top - h * (j + 0.5) / bands.size()
		for q in 4:
			var fx := foot.x + 0.04 + 0.05 * (q % 2)
			var fz := foot.z - 0.16 + q * 0.1
			k.box("wall", g, Vector3(fx, y, fz), Vector3(0.03, h / bands.size() + 0.002, 0.11), c(bands[j], CourthouseKit.K_CLOTH))
	if national:
		k.box("wall", g, Vector3(foot.x + 0.1, top - 0.35, foot.z - 0.08), Vector3(0.04, 0.7, 0.24), c(Color(0.12, 0.14, 0.34), CourthouseKit.K_CLOTH))


## A portrait on a wall face f, centre height y, in a gilt frame.
static func _portrait(f: Transform3D, y: float, w: float, h: float, seed_: float) -> void:
	k.box("wall", f, Vector3(0, y, 0.02), Vector3(w + 0.12, h + 0.12, 0.04), c(GILT.darkened(0.2), CourthouseKit.K_PAINT))
	k.box("wall", f, Vector3(0, y, 0.043), Vector3(w, h, 0.01), c(Color(0.16, 0.13, 0.10), CourthouseKit.K_PAINT))
	# A sitter: a pale face over a dark coat.
	k.box("wall", f, Vector3(0, y - h * 0.22, 0.05), Vector3(w * 0.6, h * 0.45, 0.004), c(Color(0.08, 0.07, 0.07), CourthouseKit.K_PAINT))
	k.m.sphere("wall", f * Transform3D(Basis().scaled(Vector3(1.0, 1.25, 0.2)), Vector3(0.02 * seed_, y + h * 0.12, 0.05)), w * 0.14, 8,
		c(Color(0.72, 0.58, 0.46), CourthouseKit.K_PAINT))


## A framed map of the county.
static func _map(f: Transform3D, y: float, w: float, h: float) -> void:
	k.box("wall", f, Vector3(0, y, 0.02), Vector3(w + 0.1, h + 0.1, 0.04), c(WALNUT.darkened(0.3), CourthouseKit.K_WOOD))
	k.box("wall", f, Vector3(0, y, 0.043), Vector3(w, h, 0.01), c(Color(0.86, 0.80, 0.64), CourthouseKit.K_PAINT))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1842
	for j in 14:
		var p := Vector3(rng.randf_range(-w * 0.4, w * 0.4), y + rng.randf_range(-h * 0.4, h * 0.4), 0.05)
		k.box_rz("wall", f, p, Vector3(rng.randf_range(0.2, 0.5), 0.008, 0.002), rng.randf_range(0.0, PI), c(Color(0.45, 0.30, 0.2), CourthouseKit.K_PAINT))
	k.box("wall", f, Vector3(0, y, 0.049), Vector3(w * 0.8, h * 0.8, 0.001), c(Color(0.80, 0.74, 0.58), CourthouseKit.K_PAINT))


## A cast-iron radiator against a wall, its back at the frame's +z.
static func _radiator(xf: Transform3D, w: float) -> void:
	var iron := c(Color(0.62, 0.58, 0.50), CourthouseKit.K_ENAMEL)
	var n := int(w / 0.07)
	for j in n:
		k.box("wall", xf, Vector3(-w / 2.0 + (j + 0.5) * w / n, 0.45, 0), Vector3(0.05, 0.8, 0.2), iron)
	k.box("wall", xf, Vector3(0, 0.1, 0), Vector3(w, 0.06, 0.16), iron)
	k.box("wall", xf, Vector3(0, 0.82, 0), Vector3(w, 0.05, 0.16), iron)


## The judge's chambers: a partners' desk, chairs, a sofa, bookcases.
static func _chambers(xf: Transform3D) -> void:
	_desk(xf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.5, 0, 0)))
	_high_chair(xf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1.4, 0, 0)))
	_chair(xf * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-0.6, 0, 0.4)))
	_chair(xf * Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-0.6, 0, -0.4)))
	for z: float in [-2.2, -0.4, 1.4]:
		_bookcase(xf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-3.1, 0, z)), 1.7, 2.4)
	var hide := c(LEATHER, CourthouseKit.K_CLOTH)
	var sofa := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0, 2.6))
	k.box("wall", sofa, Vector3(0, 0.22, 0), Vector3(2.0, 0.44, 0.8), hide)
	k.box("wall", sofa, Vector3(0, 0.6, 0.32), Vector3(2.0, 0.5, 0.2), hide)
	for s: float in [-1.0, 1.0]:
		k.box("wall", sofa, Vector3(s * 0.95, 0.5, 0), Vector3(0.14, 0.3, 0.8), hide)
	k.solid(sofa, Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 0.8))
	_pendant(xf * Vector3(0, C3 - F2, 0), 1.0, false)


## The jury room: a long table and its twelve chairs.
static func _jury_room(xf: Transform3D) -> void:
	_table(xf, 5.0, 1.3, 0.76, WALNUT)
	for j in 6:
		for s: float in [-1.0, 1.0]:
			_chair(xf * Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(-2.1 + j * 0.84, 0, s * 1.0)))
	for s: float in [-1.0, 1.0]:
		_pendant(xf * Vector3(s * 1.6, C3 - F2, 0), 1.2, false)


## The law library: shelves round the walls, reading tables.
static func _library(xf: Transform3D) -> void:
	for x: float in [-6.5, -4.7, -2.9, 2.9, 4.7, 6.5]:
		_bookcase(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, 3.0)), 1.7, 2.5)
	for s: float in [-1.0, 1.0]:
		_table(xf * Transform3D(Basis(), Vector3(s * 3.0, 0, -0.2)), 2.4, 1.1, 0.76, OAK.darkened(0.15))
		for j in 3:
			_chair(xf * Transform3D(Basis(), Vector3(s * 3.0 - 0.8 + j * 0.8, 0, -1.0)))
			_chair(xf * Transform3D(Basis(Vector3.UP, PI), Vector3(s * 3.0 - 0.8 + j * 0.8, 0, 0.6)))
	_pendant(xf * Vector3(0, C3 - F2, 0), 1.2, false)
