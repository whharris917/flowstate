class_name TwainHouse
extends Node3D
## The house Samuel Clemens built at 351 Farmington Avenue, Hartford,
## Connecticut (Edward Tuckerman Potter, 1874), as the family knew it in
## the 1880s after Tiffany's Associated Artists redecorated the hall and
## the rooms off it (1881). Three storeys of orange-red brick laid in
## black and vermilion bands, woodwork painted a chocolate red, a steep
## roof of slate in coloured bands. A main block with the library at its
## south end, its alcove a bay to the west that rises into a tower and a
## spire; the dining room, the drawing room and its bay to the north; the
## mahogany guest room in an octagon to the south whose top is the open
## "Texas deck"; the conservatory, a half round of glass off the library.
## Gables east, south and north, the service wing to the north-west and
## the butler's pantry in a quarter round between. The ombra, a porch on
## posts, wraps the south-east corner and runs along the east front as a
## veranda to the entrance and the porte-cochere.
##
## Every measurement is taken from the Historic American Buildings Survey
## drawings (HABS CT-359, 1995: plans, elevations, sections, the roof)
## in their own feet: x runs north up the house, z east; y is height
## over the first floor. The survey's first-floor sheet is the base; the
## other floors are registered to it. `w()` turns those into the world:
## +x east, -z north, metres, the lawn at y = 0. Art only: no records.

const FT := 0.3048
const OX := 85.0            # the world's origin in the survey's feet: north
const OZ := 70.0            # and east (the middle of the hall)
const FL := 0.75            # the first floor over the lawn, metres
const GRADE := -2.46        # the lawn in feet over the first floor
const F2 := 13.0            # the second floor
const F3 := 24.0            # the third
const EAVE := 23.0          # the main walls' top
const TOP := 44.0           # the main roof's flat top
const SLOPE := 2.0          # the main roof's rise over run
const T := 1.0              # an outside wall

# The main block's outer faces.
const MX0 := 57.5
const MX1 := 114.5
const MZ0 := 38.3
const MZ1 := 83.9

const BRICK := Color(0.60, 0.26, 0.17)
const BLACK := Color(0.11, 0.09, 0.08)
const VERMILION := Color(0.66, 0.17, 0.10)
const TRIM := Color(0.33, 0.14, 0.09)
const SASH := Color(0.22, 0.10, 0.07)
const SLATE := Color(0.34, 0.37, 0.43)
const SLATE_RED := Color(0.46, 0.27, 0.23)
const SLATE_DARK := Color(0.24, 0.26, 0.31)
const STONE := Color(0.44, 0.34, 0.29)
const PORCH := Color(0.36, 0.34, 0.31)
const CEIL := Color(0.86, 0.82, 0.72)
const IRON := Color(0.06, 0.06, 0.065)

var k: CourthouseKit
var glass_mat: StandardMaterial3D
var wall_mat: ShaderMaterial
var stencil_mat: ShaderMaterial
var iron_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var flame_mat: StandardMaterial3D
## Every opening in the house: {at (survey x, z), w, sill, head, shape,
## kind ("win", "door", "french", "open"), hood}. Walls, their linings
## and the rooms all cut the same list.
var ops: Array[Dictionary] = []
## The gas lights, which are lit as the day goes: {light, energy}.
var lights: Array[Dictionary] = []
var stats: Dictionary = {}


## The world point of a survey point (feet: x north, z east, y over the
## first floor).
static func w(sx: float, sz: float, y := 0.0) -> Vector3:
	return Vector3((sz - OZ) * FT, FL + y * FT, -(sx - OX) * FT)


## A survey point on the ground plan in the world's (x, z).
static func w2(q: Vector2) -> Vector2:
	return Vector2((q.y - OZ) * FT, -(q.x - OX) * FT)


## A height in feet over the first floor, in the world's metres.
static func h(y: float) -> float:
	return FL + y * FT


static func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


## A colour for the stencil shader: the ground and the pattern's number.
static func st(col: Color, pattern: int) -> Color:
	return Color(col.r, col.g, col.b, pattern / 10.0)


func build() -> void:
	name = "TwainHouse"
	var t0 := Time.get_ticks_msec()
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	_materials()
	_openings()
	_walls()
	_chimneys()
	_roofs()
	_towers()
	_conservatory()
	_porches()
	# The rooms go in meshes of their own: they cast no sun shadow and
	# are not drawn from far off.
	var outer := k.m
	k.m = TownMesh.new()
	if OS.get_environment("FLOWSTATE_TW_DEBUG") != "nointerior":
		TwainInterior.build(self)
	var inner := k.m
	k.m = outer
	var mats := {"wall": wall_mat, "glass": glass_mat, "iron": iron_mat, "lamp": lamp_mat, "stencil": stencil_mat,
		"flame": flame_mat}
	var drawn: Array = outer.commit(self, mats, ["wall", "iron"]).values()
	for mi: MeshInstance3D in inner.commit(self, mats, []).values():
		mi.visibility_range_end = 120.0
		drawn.append(mi)
	for mi: MeshInstance3D in drawn:
		if mi.name.ends_with("glass"):
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	stats = {"triangles": outer.triangles + inner.triangles, "inside": inner.triangles, "solids": k.solid_count,
		"ms": Time.get_ticks_msec() - t0}


func _materials() -> void:
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	stencil_mat = ShaderMaterial.new()
	stencil_mat.shader = load("res://world/twain_stencil.gdshader")
	glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.50, 0.56, 0.58, 0.18)
	glass_mat.roughness = 0.05
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	iron_mat = StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.vertex_color_is_srgb = true
	iron_mat.metallic = 0.5
	iron_mat.roughness = 0.45
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.86)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.80, 0.52)
	lamp_mat.emission_energy_multiplier = 0.0
	flame_mat = StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.8, 0.4)
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.7, 0.3)


## ---- openings ------------------------------------------------------------

func _op(sx: float, sz: float, wd: float, sill: float, head: float, kind := "win", shape := "flat", hood := true) -> void:
	ops.append({"at": Vector2(sx, sz), "w": wd, "sill": sill, "head": head, "kind": kind, "shape": shape, "hood": hood})


## The windows and doors, read off the survey's plans and elevations. A
## first-floor window stands 2.5 to 10 ft, a second-floor one 15.5 to
## 21.5; the doors are 8.5 ft.
func _openings() -> void:
	# The library's alcove, west, and the school room over it.
	_op(73.2, 29.7, 3.6, 1.2, 10.0)
	_op(68.5, 31.65, 2.4, 2.5, 10.0)
	_op(77.9, 31.65, 2.4, 2.5, 10.0)
	_op(73.2, 29.7, 3.4, 15.5, 21.5)
	_op(68.5, 31.65, 2.2, 15.5, 21.5)
	_op(77.9, 31.65, 2.2, 15.5, 21.5)
	# The west front: the dining room; upstairs the bath, the Langdon room.
	_op(92.2, MZ0, 4.2, 2.5, 10.0)
	_op(62.5, MZ0, 3.0, 15.5, 21.5)
	_op(83.0, MZ0, 2.8, 15.5, 21.5)
	_op(90.0, MZ0, 3.0, 15.5, 21.5)
	_op(95.5, MZ0, 3.0, 15.5, 21.5)
	_op(107.5, MZ0, 2.8, 15.5, 21.5)
	# The north front: the dining room's window over its fireplace, its
	# other window; the drawing room's bay and its window; upstairs the
	# office, the Clemens bedroom's bay.
	_op(MX1, 47.7, 3.0, 5.8, 10.0, "win", "flat", false)
	_op(MX1, 54.0, 2.6, 2.5, 10.0)
	_op(121.0, 69.5, 3.4, 2.5, 10.0)
	_op(119.75, 65.25, 2.3, 2.5, 10.0)
	_op(119.75, 73.75, 2.3, 2.5, 10.0)
	_op(MX1, 79.5, 2.8, 2.5, 10.0)
	_op(MX1, 52.0, 2.8, 15.5, 21.5)
	_op(121.0, 69.5, 3.2, 15.5, 21.5)
	_op(119.75, 65.25, 2.2, 15.5, 21.5)
	_op(119.75, 73.75, 2.2, 15.5, 21.5)
	_op(MX1, 79.5, 2.8, 15.5, 21.5)
	# The east front, under the veranda: the drawing room, the entrance,
	# the hall's window, the bath; upstairs the Clemens bedroom, the small
	# room, Susy's room, the bath.
	_op(99.0, MZ1, 3.2, 2.5, 10.0)
	_op(106.8, MZ1, 3.4, 2.5, 10.0)
	_op(90.8, MZ1, 4.4, 0.0, 9.0, "door")
	_op(79.0, MZ1, 4.6, 1.5, 10.0)
	_op(66.5, MZ1, 2.6, 2.5, 10.0)
	_op(108.5, MZ1, 3.0, 15.5, 21.5)
	_op(100.5, MZ1, 3.0, 15.5, 21.5)
	_op(90.0, MZ1, 3.0, 15.5, 21.5)
	_op(79.5, MZ1, 3.2, 15.5, 21.5)
	_op(71.0, MZ1, 3.0, 15.5, 21.5)
	_op(62.0, MZ1, 2.4, 15.5, 21.5)
	# The mahogany guest room's octagon: west, and the door to the ombra;
	# Clara and Jean's room over it.
	_op(47.5, 63.6, 3.6, 2.5, 10.0)
	_op(49.9, 58.1, 2.3, 2.5, 10.0)
	_op(50.0, 68.95, 3.0, 0.0, 8.5, "door")
	_op(47.5, 63.6, 3.4, 15.5, 21.5)
	_op(49.9, 58.1, 2.2, 15.5, 21.5)
	_op(50.0, 68.95, 2.2, 15.5, 21.5)
	# The dressing room's round, and the bath over it.
	for a: float in [150.0, 195.0, 235.0]:
		var p := _arc_point(DRESS_C, DRESS_R, a)
		_op(p.x, p.y, 2.3, 2.5, 10.0)
	for a: float in [165.0, 215.0]:
		var p := _arc_point(DRESS_C, DRESS_R, a)
		_op(p.x, p.y, 2.2, 15.5, 21.5)
	# The library's south wall: the opening to the conservatory; the
	# school room's windows over it.
	_op(MX0, 47.0, 8.0, 0.0, 10.5, "open", "segment", false)
	_op(MX0, 42.5, 2.8, 15.5, 21.5)
	_op(MX0, 51.5, 2.8, 15.5, 21.5)
	# The butler's pantry and its door down to the yard.
	for a: float in [212.0, 232.0, 252.0]:
		var p := _arc_point(PANTRY_C, PANTRY_R, a)
		_op(p.x, p.y, 2.6, 3.0, 9.0)
	var d := _arc_point(PANTRY_C, PANTRY_R, 195.0)
	_op(d.x, d.y, 3.0, 0.0, 8.0, "door")
	# The service wing.
	for x: float in [118.5, 126.5, 132.5]:
		_op(x, 22.3, 2.8, 2.5, 9.5)
		_op(x, 22.3, 2.8, 14.5, 20.0)
	for x: float in [142.0, 150.0]:
		_op(x, 19.8, 3.0, 2.5, 9.5)
		_op(x, 19.8, 3.0, 14.5, 20.0)
	for z: float in [26.5, 37.0]:
		_op(155.5, z, 2.8, 2.5, 9.5)
		_op(155.5, z, 2.8, 14.5, 20.0)
	for x: float in [120.0, 128.0, 150.5]:
		_op(x, 43.8, 2.8, 2.5, 9.5)
		_op(x, 43.8, 2.8, 14.5, 20.0)
	_op(142.5, 43.8, 3.0, 0.0, 8.0, "door")
	# The third floor: the billiard room's balcony door in the south
	# gable, the small windows of carved marble either side; the east
	# gables' windows; the north gable's.
	_op(MX0, 46.8, 4.0, 24.0, 32.5, "french", "round")
	_op(MX0, 41.5, 1.6, 26.5, 30.5, "win", "flat", false)
	_op(MX0, 52.1, 1.6, 26.5, 30.5, "win", "flat", false)
	_op(65.5, MZ1, 4.4, 24.5, 33.0, "french", "round")
	_op(101.0, MZ1, 2.4, 25.0, 31.0, "win", "flat", false)
	_op(104.0, MZ1, 2.4, 25.0, 31.0, "win", "flat", false)
	_op(107.0, MZ1, 2.4, 25.0, 31.0, "win", "flat", false)
	_op(MX1, 52.0, 3.0, 25.0, 31.5, "win", "round", false)
	_op(101.0, MZ0, 2.2, 24.8, 29.2, "win", "flat", false)


const DRESS_C := Vector2(54.8, 77.3)
const DRESS_R := 6.6
const PANTRY_C := Vector2(112.8, 38.3)
const PANTRY_R := 15.5
const CONS_C := Vector2(52.3, 47.0)
const CONS_R := 8.5


## A point on a circle in the survey's plan, at an angle in degrees (0
## along +x, north; 90 along +z, east).
static func _arc_point(cen: Vector2, r: float, deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	return cen + Vector2(cos(a), sin(a)) * r


## The house's outer faces at the first floor, round from the library's
## south-west corner: the alcove, the west front, the north front with
## the drawing room's bay, the east front, the dressing room's round, the
## guest room's octagon and back along the library's south wall.
static func perimeter() -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(MX0, MZ0), Vector2(66.5, MZ0), Vector2(66.5, 33.6), Vector2(70.5, 29.7),
		Vector2(75.9, 29.7), Vector2(79.9, 33.6), Vector2(79.9, MZ0), Vector2(MX1, MZ0), Vector2(MX1, 64.0),
		Vector2(118.5, 64.0), Vector2(121.0, 66.5), Vector2(121.0, 72.5), Vector2(118.5, 75.0), Vector2(MX1, 75.0),
		Vector2(MX1, MZ1)])
	for i in 13:
		p.append(_arc_point(DRESS_C, DRESS_R, 90.0 + 160.0 * i / 12.0))
	p.append_array([Vector2(47.5, 66.8), Vector2(47.5, 60.4), Vector2(52.3, 55.8), Vector2(MX0, 55.8)])
	return p


## Twice the signed area of a polygon: positive when it runs
## anticlockwise with x to the right and the second axis up.
static func signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s


## A point just inside an edge a-b of a polygon wound `cw`.
static func inside_of(a: Vector2, b: Vector2, cw: bool) -> Vector2:
	var d := (b - a).normalized()
	var left := Vector2(-d.y, d.x)
	return (a + b) / 2.0 + (left if not cw else -left) * 2.0


## ---- faces -------------------------------------------------------------

## A face on the line a-b (survey plan), its frame's z pointing to the
## side of `toward`: [frame, length in metres]. The frame's x runs along
## the face as seen from that side, its origin at grade.
static func frame(a: Vector2, b: Vector2, toward: Vector2) -> Array:
	var wa := w2(a)
	var wb := w2(b)
	var wt := w2(toward)
	var d := wb - wa
	var length := d.length()
	d /= length
	var n := Vector2(-d.y, d.x)
	if n.dot(wt - (wa + wb) / 2.0) < 0.0:
		n = -n
	var n3 := Vector3(n.x, 0, n.y)
	var x3 := Vector3.UP.cross(n3)
	var o := wa if x3.dot(Vector3(d.x, 0, d.y)) > 0.0 else wb
	return [Transform3D(Basis(x3, Vector3.UP, n3), Vector3(o.x, 0, o.y)), length]


## The openings of the house that stand on a face (within tol feet of its
## line) and cross the band y0..y1 (feet), in the face's own terms.
func ops_on(f: Transform3D, length: float, y0: float, y1: float, tol: float) -> Array:
	var out: Array = []
	for o: Dictionary in ops:
		var q := w2(o["at"] as Vector2)
		var rel := Vector3(q.x, 0, q.y) - f.origin
		var u := rel.dot(f.basis.x)
		var off := rel.dot(f.basis.z)
		var wd := float(o["w"]) * FT
		if absf(off) > tol * FT or u < wd / 2.0 - 0.05 or u > length - wd / 2.0 + 0.05:
			continue
		if float(o["sill"]) >= y1 or float(o["head"]) <= y0:
			continue
		var shape := str(o["shape"])
		var head := h(float(o["head"]))
		var spring := head - wd / 2.0 if shape == "round" else (head - 0.25 if shape == "segment" else head)
		var op := CourthouseKit.opening(u, wd, h(float(o["sill"])), spring, shape, 0.25)
		op["kind"] = o["kind"]
		op["hood"] = o["hood"]
		out.append(op)
	return out


## A run of outside wall from a to b (survey plan, a and b on its outer
## face), `inside` a point within, from y0 to y1 feet: brick with its
## openings cut, glazed and dressed; the painted bands laid over it where
## `bands`.
func run(a: Vector2, b: Vector2, inside: Vector2, y0: float, y1: float, bands := true, col := BRICK) -> void:
	var mid := (a + b) / 2.0
	var fr := frame(a, b, mid + (mid - inside))
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var mine := ops_on(f, length, y0, y1, 0.8)
	# A storey at a time: the wall cuts one opening in a column per band.
	var cuts: Array[float] = [y0]
	for split: float in [12.5, 22.8]:
		if split > y0 + 0.1 and split < y1 - 0.1:
			cuts.append(split)
	cuts.append(y1)
	for i in cuts.size() - 1:
		k.wall("wall", f, 0.0, length, h(cuts[i]), h(cuts[i + 1]), T * FT, c(col, CourthouseKit.K_BRICK), mine, 1000.0)
	if bands:
		_bands(f, length, y0, y1, mine)
	for o: Dictionary in mine:
		_dress(f, o)


## The brick's painted bands over a face: black at the water table, under
## the sills and at each floor; vermilion over the first-floor heads; a
## row of black squares under the second-floor sills.
func _bands(f: Transform3D, length: float, y0: float, y1: float, mine: Array) -> void:
	var skin := f * Transform3D(Basis(), Vector3(0, 0, 0.012))
	for band: Array in [[GRADE, 0.2, STONE, CourthouseKit.K_STONE], [0.2, 0.8, BLACK, CourthouseKit.K_BRICK],
			[1.9, 2.4, BLACK, CourthouseKit.K_BRICK], [10.6, 11.1, VERMILION, CourthouseKit.K_BRICK],
			[12.6, 13.5, BLACK, CourthouseKit.K_BRICK], [21.6, 22.2, BLACK, CourthouseKit.K_BRICK]]:
		var b0 := maxf(float(band[0]), y0)
		var b1 := minf(float(band[1]), y1)
		if b1 - b0 < 0.05:
			continue
		k.wall("wall", skin, 0.0, length, h(b0), h(b1), 0.012 if int(band[3]) != CourthouseKit.K_STONE else 0.05,
			c(band[2] as Color, int(band[3])), mine, -1000.0)
	# The row of squares, set diamond-wise, missing where a window stands.
	if y0 < 14.3 and y1 > 14.9:
		var step := 0.5
		var n := int(length / step)
		for i in n:
			var u := (i + 0.5) * length / n
			var clear := true
			for o: Dictionary in mine:
				if absf(u - float(o["u"])) < float(o["w"]) / 2.0 + 0.15 and float(o["y0"]) < h(14.9):
					clear = false
			if clear:
				k.box_rz("wall", skin, Vector3(u, h(14.6), 0.006), Vector3(0.1, 0.1, 0.012), PI / 4.0, c(BLACK, CourthouseKit.K_BRICK))


## An opening's joinery from outside: the sash or the door, the sill, the
## head's board and, over most windows, the stepped sunburst of boards
## that marks the house.
func _dress(f: Transform3D, o: Dictionary) -> void:
	var kind := str(o["kind"])
	var u := float(o["u"])
	var wd := float(o["w"])
	var y0 := float(o["y0"])
	var yt := float(o["yt"])
	var sash := c(SASH, CourthouseKit.K_PAINT)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	if kind == "win":
		k.sash(f, o, -0.14, sash, -1.0, 0, false)
		k.box("wall", f, Vector3(u, y0 - 0.05, 0.02), Vector3(wd + 0.2, 0.1, 0.2), c(STONE, CourthouseKit.K_STONE))
	elif kind == "french":
		k.glass(f, o, -0.16)
		for s: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(u + s * (wd / 2.0 - 0.04), (y0 + float(o["ys"])) / 2.0, -0.14), Vector3(0.08, float(o["ys"]) - y0, 0.08), sash)
		k.box("wall", f, Vector3(u, (y0 + float(o["ys"])) / 2.0, -0.14), Vector3(0.06, float(o["ys"]) - y0, 0.07), sash)
	elif kind == "door":
		# The doors stand open, folded back inside the reveal.
		for s: float in [-1.0, 1.0]:
			var leaf := wd / 2.0 if wd > 1.1 else wd
			if wd <= 1.1 and s > 0.0:
				continue
			var hinge := Vector3(u + s * (wd / 2.0 - 0.03), y0, -T * FT + 0.05)
			var xf := f * Transform3D(Basis(Vector3.UP, s * PI / 2.0), hinge)
			k.door_leaf(xf, Vector3(-s * leaf / 2.0, 0, 0), leaf - 0.02, yt - y0 - 0.02, c(Color(0.28, 0.14, 0.08), CourthouseKit.K_WOOD), false)
		k.box("wall", f, Vector3(u, y0 - 0.03, -0.05), Vector3(wd + 0.1, 0.06, T * FT * 0.8), c(STONE, CourthouseKit.K_STONE))
	# The casing round the opening, standing a little proud.
	if str(o["head"]) == "flat":
		for s: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(u + s * (wd / 2.0 + 0.05), (y0 + yt) / 2.0, 0.025), Vector3(0.1, yt - y0, 0.05), trim)
		k.box("wall", f, Vector3(u, yt + 0.06, 0.03), Vector3(wd + 0.3, 0.12, 0.08), trim)
	else:
		var circ := CourthouseKit.head_circle(o)
		var a0 := atan2(float(o["ys"]) - circ.y, -wd / 2.0)
		var a1 := atan2(float(o["ys"]) - circ.y, wd / 2.0)
		k.arc_band("wall", f, circ, a1, a0, 0.12, 0.06, 0.05, trim, 10)
		for s: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(u + s * (wd / 2.0 + 0.05), (y0 + float(o["ys"])) / 2.0, 0.025), Vector3(0.1, float(o["ys"]) - y0, 0.05), trim)
	if bool(o["hood"]) and str(o["head"]) == "flat":
		_sunburst(f, u, yt + 0.12, wd)


## The hood over a window: boards standing on end, stepped up to the
## middle, between a head board and a cap; the ends cut to a point.
func _sunburst(f: Transform3D, u: float, y: float, wd: float) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var boards := 9
	var span := wd + 0.35
	for i in boards:
		var t := (i + 0.5) / boards - 0.5
		var tall := 0.18 + 0.32 * (1.0 - absf(t) * 2.0)
		k.box("wall", f, Vector3(u + t * span, y + tall / 2.0, 0.04), Vector3(span / boards - 0.02, tall, 0.05), trim)
	k.box("wall", f, Vector3(u, y + 0.52, 0.07), Vector3(0.5, 0.06, 0.12), trim)
	k.box("wall", f, Vector3(u, y - 0.02, 0.06), Vector3(span + 0.15, 0.06, 0.12), trim)


## ---- the walls -----------------------------------------------------------

func _walls() -> void:
	var p := perimeter()
	var cw := signed_area(p) < 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		run(a, b, inside_of(a, b, cw), GRADE, EAVE)
		_eave(a, b, inside_of(a, b, cw), EAVE, 1.4)
	# The octagon rises a foot more, to the Texas deck.
	var octa := [Vector2(MX0, 55.8), Vector2(52.3, 55.8), Vector2(47.5, 60.4), Vector2(47.5, 66.8), Vector2(52.5, 71.1)]
	for i in octa.size() - 1:
		run(octa[i], octa[i + 1], Vector2(54.0, 64.0), EAVE, F3 + 0.6, false)
	# The alcove likewise, to the tower's deck.
	var alcove := [Vector2(66.5, MZ0), Vector2(66.5, 33.6), Vector2(70.5, 29.7), Vector2(75.9, 29.7), Vector2(79.9, 33.6), Vector2(79.9, MZ0)]
	for i in alcove.size() - 1:
		run(alcove[i], alcove[i + 1], Vector2(73.2, 36.0), EAVE, F3 + 0.6, false)
	# The butler's pantry: a quarter round of one storey, a balcony on it.
	var prev := _arc_point(PANTRY_C, PANTRY_R, 180.0)
	for i in range(1, 10):
		var q := _arc_point(PANTRY_C, PANTRY_R, 180.0 + 90.0 * i / 9.0)
		run(prev, q, PANTRY_C, GRADE, 12.0)
		_eave(prev, q, PANTRY_C, 12.0, 0.8)
		prev = q
	run(prev, Vector2(113.0, 22.3), PANTRY_C + Vector2(0, -5), GRADE, 12.0)
	# The service wing: two storeys, lower than the house.
	var wing := [Vector2(113.0, 22.3), Vector2(137.0, 22.3), Vector2(137.0, 19.8), Vector2(155.5, 19.8), Vector2(155.5, 43.8),
		Vector2(MX1, 43.8)]
	for i in wing.size() - 1:
		run(wing[i], wing[i + 1], Vector2(135.0, 33.0), GRADE, 18.0)
		_eave(wing[i], wing[i + 1], Vector2(135.0, 33.0), 18.0, 1.4)


## A bracketed eave along a run: the frieze board, brackets on it and the
## soffit reaching `out` feet.
func _eave(a: Vector2, b: Vector2, inside: Vector2, y: float, out: float) -> void:
	var mid := (a + b) / 2.0
	var fr := frame(a, b, mid + (mid - inside))
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var o := out * FT
	k.box("wall", f, Vector3(length / 2.0, h(y) - 0.2, 0.03), Vector3(length, 0.4, 0.06), trim)
	k.box("wall", f, Vector3(length / 2.0, h(y) + 0.02, o / 2.0), Vector3(length + 0.02, 0.05, o), c(TRIM.lightened(0.1), CourthouseKit.K_PAINT))
	k.box("wall", f, Vector3(length / 2.0, h(y) + 0.02, o), Vector3(length + 0.04, 0.22, 0.05), trim)
	var n := maxi(1, int(length / 0.75))
	for i in n + 1:
		var u := length * i / n
		k.box("wall", f, Vector3(u, h(y) - 0.12, o * 0.45), Vector3(0.07, 0.24, o * 0.85), trim)
		k.box("wall", f, Vector3(u, h(y) - 0.32, 0.1), Vector3(0.07, 0.3, 0.16), trim)


## ---- chimneys ------------------------------------------------------------

## The chimneys, from the roof plan: the library's and hall's in the main
## block, the dining room's on the north front split round the window
## over its fireplace, the Langdon room's on the west front, the kitchen's.
func _chimneys() -> void:
	_chimney(Vector2(71.5, 55.6), Vector2(5.0, 3.2), 30.0, 48.5)
	_chimney(Vector2(96.0, 69.0), Vector2(3.2, 5.0), 30.0, 47.5)
	_chimney(Vector2(101.2, 38.6), Vector2(3.0, 3.2), 24.0, 45.0)
	_chimney(Vector2(133.0, 31.0), Vector2(3.0, 3.0), 20.0, 38.0)
	# The dining room's: two flues up the outside of the north wall either
	# side of the window, joined over it.
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	for z: float in [45.4, 50.0]:
		var a := w(MX1 + 1.0, z, GRADE)
		var top := w(MX1 + 1.0, z, 10.8)
		k.block("wall", Transform3D(), (a + top) / 2.0, Vector3(1.4 * FT, top.y - a.y, 2.0 * FT), brick)
	var j0 := w(MX1 + 1.0, 47.7, 10.8)
	var j1 := w(MX1 + 1.0, 47.7, EAVE + 1.0)
	k.box("wall", Transform3D(), (j0 + j1) / 2.0, Vector3(6.6 * FT, j1.y - j0.y, 2.0 * FT), brick)
	k.box("wall", Transform3D(), w(MX1 + 1.0, 47.7, 11.1), Vector3(7.2 * FT, 0.6 * FT, 2.4 * FT), c(BLACK, CourthouseKit.K_BRICK))
	_chimney(Vector2(MX1 + 0.5, 47.7), Vector2(3.0, 5.4), EAVE + 1.0, 45.5)


## A chimney standing from y0 to y1 feet: the shaft, swelling bands of
## corbelled brick, a black band, the cap.
func _chimney(at: Vector2, size: Vector2, y0: float, y1: float) -> void:
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var dark := c(BLACK, CourthouseKit.K_BRICK)
	var g := Transform3D()
	var sz := Vector3(size.y * FT, 0, size.x * FT)
	var base := w(at.x, at.y, y0)
	var top := w(at.x, at.y, y1)
	k.box("wall", g, (base + top) / 2.0, Vector3(sz.x, top.y - base.y, sz.z), brick)
	for band: Array in [[0.55, 0.25, 0.9, dark], [0.72, 0.18, 1.0, brick], [0.86, 0.12, 1.25, brick], [0.93, 0.07, 1.35, dark]]:
		var y := lerpf(base.y, top.y, float(band[0]))
		var grow := float(band[2])
		k.box("wall", g, Vector3(base.x, y, base.z), Vector3(sz.x + grow * FT, float(band[1]) * (top.y - base.y), sz.z + grow * FT), band[3])
	k.box("wall", g, Vector3(base.x, top.y + 0.05, base.z), Vector3(sz.x + 1.4 * FT, 0.1, sz.z + 1.4 * FT), c(STONE, CourthouseKit.K_STONE))
	for i in 2:
		var off := (i - 0.5) * sz.z * 0.45
		k.m.cylinder("wall", Transform3D(Basis(), Vector3(base.x, top.y + 0.35, base.z + off)), 0.12, 0.1, 0.5, 8, c(Color(0.45, 0.22, 0.14), CourthouseKit.K_TILE))


## ---- roofs ---------------------------------------------------------------

## A face of slate from the edge a-b up to d-c (d over a, c over b; c = d
## for a hip's end), laid in coloured courses as the house's roofs are,
## with a plastered underside for the rooms under it.
func slope(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, under := true) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.y < 0.0:
		n = -n
	var rise := maxf((d - a).length(), (cc - b).length())
	var strips := maxi(2, int(rise / 0.85))
	var courses: Array[Color] = [SLATE, SLATE, SLATE, SLATE_DARK, SLATE, SLATE, SLATE_RED, SLATE, SLATE, SLATE_DARK, SLATE, SLATE_RED]
	for i in strips:
		var t0 := float(i) / strips
		var t1 := float(i + 1) / strips
		var p0 := a.lerp(d, t0)
		var p1 := b.lerp(cc, t0)
		var p2 := b.lerp(cc, t1)
		var p3 := a.lerp(d, t1)
		k.m.quad("wall", p0, p1, p2, p3, n, c(courses[i % courses.size()], CourthouseKit.K_SLATE))
	if under:
		var off := -n * 0.1
		k.m.quad("wall", a + off, b + off, cc + off, d + off, -n, c(CEIL, CourthouseKit.K_PLASTER))


## A hip over the rectangle x0..x1, z0..z1 (survey feet) from the eave y0
## at slope s (rise over run), cut off flat at y1 if it would rise past
## it; eaves standing out `out` feet.
func hip(x0: float, x1: float, z0: float, z1: float, y0: float, s: float, y1: float, out := 1.4) -> void:
	var xa := x0 - out
	var xb := x1 + out
	var za := z0 - out
	var zb := z1 + out
	var ye := y0 - out * s
	var full := minf(xb - xa, zb - za) / 2.0
	var inset := minf(full, (y1 - ye) / s)
	var yt := ye + inset * s
	var e := [w(xa, za, ye), w(xb, za, ye), w(xb, zb, ye), w(xa, zb, ye)]
	var xi0 := xa + inset
	var xi1 := maxf(xb - inset, xi0)
	var zi0 := za + inset
	var zi1 := maxf(zb - inset, zi0)
	var tp := [w(xi0, zi0, yt), w(xi1, zi0, yt), w(xi1, zi1, yt), w(xi0, zi1, yt)]
	for i in 4:
		slope(e[i], e[(i + 1) % 4], tp[(i + 1) % 4], tp[i])
	if xi1 - xi0 > 0.1 and zi1 - zi0 > 0.1:
		# The flat: tinned, a railing of iron cresting round it.
		k.m.quad("wall", tp[0], tp[1], tp[2], tp[3], Vector3.UP, c(Color(0.30, 0.30, 0.31), CourthouseKit.K_TAR))
		k.m.quad("wall", tp[0] - Vector3(0, 0.1, 0), tp[1] - Vector3(0, 0.1, 0), tp[2] - Vector3(0, 0.1, 0), tp[3] - Vector3(0, 0.1, 0),
			Vector3.DOWN, c(CEIL, CourthouseKit.K_PLASTER))
		for i in 4:
			_cresting(tp[i], tp[(i + 1) % 4])
	_fascia(e)


## The boarded edge of a roof round its eave corners.
func _fascia(e: Array) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in e.size():
		var a: Vector3 = e[i]
		var b: Vector3 = e[(i + 1) % e.size()]
		k.m.bar("wall", a - Vector3(0, 0.1, 0), b - Vector3(0, 0.1, 0), 0.09, 4, trim)


## Iron cresting along a ridge or a flat's edge: a rail, pickets, a
## fleur at every fourth.
func _cresting(a: Vector3, b: Vector3) -> void:
	var col := IRON
	k.m.bar("iron", a + Vector3(0, 0.05, 0), b + Vector3(0, 0.05, 0), 0.02, 4, col)
	k.m.bar("iron", a + Vector3(0, 0.45, 0), b + Vector3(0, 0.45, 0), 0.012, 4, col)
	var n := int(a.distance_to(b) / 0.15)
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxi(n, 1))
		k.m.bar("iron", p, p + Vector3(0, 0.55 if i % 4 == 0 else 0.45, 0), 0.008, 4, col)
		if i % 4 == 0:
			k.m.sphere("iron", Transform3D(Basis(), p + Vector3(0, 0.6, 0)), 0.035, 6, col)


## ---- the roof over the main block ---------------------------------------
##
## The main block's roof is steep slopes on all four sides up to a flat
## with iron cresting round it; the gables stand out of it. Each is a
## plane over the survey's plan (y = a x + b z + c, feet), and the roof
## is whichever plane stands highest: the hip's faces are cut away where
## a gable rises over them and the gables where they sink under the hip,
## so the valleys fall where the planes meet. The same planes give a room
## under the roof its ceiling height (`roof_y`).

## The hip's footprint with its eaves, and its planes: south, north,
## west, east and the flat.
var roof_rect := PackedVector2Array()
var hip_planes: Array[Vector3] = []
## The gables' slopes: {plane, poly (plan)}.
var gable_slopes: Array[Dictionary] = []


## The plane through three points (x, z, y) as (a, b, c).
static func plane3(p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var n := (p1 - p0).cross(p2 - p0)
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


## The pieces of a set of polygons inside a convex region.
static func meet(pieces: Array, region: PackedVector2Array) -> Array:
	var out: Array = []
	if region.size() < 3:
		return out
	for p: PackedVector2Array in pieces:
		for q: PackedVector2Array in Geometry2D.intersect_polygons(p, region):
			if q.size() >= 3:
				out.append(q)
	return out


## The pieces of a set of polygons outside a region.
static func cut(pieces: Array, hole: PackedVector2Array) -> Array:
	if hole.size() < 3:
		return pieces
	var out: Array = []
	for p: PackedVector2Array in pieces:
		for q: PackedVector2Array in Geometry2D.clip_polygons(p, hole):
			if q.size() >= 3:
				out.append(q)
	return out


## The roof's height over a plan point (feet), or far below where there
## is none.
func roof_y(p: Vector2) -> float:
	var y := -1000.0
	if Geometry2D.is_point_in_polygon(p, roof_rect):
		var m := 1e9
		for pl: Vector3 in hip_planes:
			m = minf(m, ph(pl, p))
		y = m
	for g: Dictionary in gable_slopes:
		if Geometry2D.is_point_in_polygon(p, g["poly"] as PackedVector2Array):
			y = maxf(y, ph(g["plane"] as Vector3, p))
	return y


func _roofs() -> void:
	var over := 1.4
	var xa := MX0 - over
	var xb := MX1 + over
	var za := MZ0 - over
	var zb := MZ1 + over
	var ye := EAVE - over * SLOPE
	hip_planes = [Vector3(SLOPE, 0, ye - SLOPE * xa), Vector3(-SLOPE, 0, ye + SLOPE * xb), Vector3(0, SLOPE, ye - SLOPE * za),
		Vector3(0, -SLOPE, ye + SLOPE * zb), Vector3(0, 0, TOP)]
	roof_rect = PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)])
	# The gables: south over the library's end, two east, north over the
	# dining room, a small one west.
	cross_gable(Vector2(MX0, MZ0), Vector2(MX0, 56.2), Vector2(70.0, 47.0))
	cross_gable(Vector2(55.5, MZ1), Vector2(76.5, MZ1), Vector2(66.0, 70.0))
	cross_gable(Vector2(94.0, MZ1), Vector2(MX1 + 0.5, MZ1), Vector2(104.0, 70.0))
	cross_gable(Vector2(MX1, 43.0), Vector2(MX1, 61.0), Vector2(100.0, 52.0))
	cross_gable(Vector2(96.0, MZ0), Vector2(106.0, MZ0), Vector2(101.0, 50.0))
	# The hip's faces, each where it is the lowest of the hip's planes, less
	# where a gable stands over it.
	for i in hip_planes.size():
		var pieces: Array = [roof_rect]
		for j in hip_planes.size():
			if j != i:
				pieces = meet(pieces, under(hip_planes[i], hip_planes[j]))
		for g: Dictionary in gable_slopes:
			var hidden := meet([g["poly"]], under(hip_planes[i], g["plane"] as Vector3))
			for hole: PackedVector2Array in hidden:
				pieces = cut(pieces, hole)
		for p: PackedVector2Array in pieces:
			roof_piece(p, hip_planes[i], i == 4)
	# The gables' slopes, less where they sink under the hip.
	for g: Dictionary in gable_slopes:
		var sunk: Array = [roof_rect]
		for pl: Vector3 in hip_planes:
			sunk = meet(sunk, under(g["plane"] as Vector3, pl))
		var pieces: Array = [g["poly"]]
		for hole: PackedVector2Array in sunk:
			pieces = cut(pieces, hole)
		for p: PackedVector2Array in pieces:
			roof_piece(p, g["plane"] as Vector3, false)
	# The eaves' fascia round the hip.
	_fascia([w(xa, za, ye), w(xb, za, ye), w(xb, zb, ye), w(xa, zb, ye)])
	# The dressing room's round: a half cone into the main roof.
	var apex := w(58.5, 77.3, 32.0)
	var prev := _arc_point(DRESS_C, DRESS_R + 1.4, 90.0)
	for i in range(1, 13):
		var q := _arc_point(DRESS_C, DRESS_R + 1.4, 90.0 + 160.0 * i / 12.0)
		slope(w(prev.x, prev.y, EAVE - 1.2), w(q.x, q.y, EAVE - 1.2), apex, apex)
		prev = q
	# The drawing room's bay: a cone of eight sides over its half octagon.
	_cone(Vector2(117.0, 69.5), 6.2, EAVE - 1.0, 32.0, 8, PI / 8.0)
	# The service wing's hip, and the pantry's flat with its railing.
	hip(113.0, 155.5, 20.5, 43.8, 18.0, 1.4, 40.0)
	var flat: Array[Vector2] = []
	for i in 10:
		flat.append(_arc_point(PANTRY_C, PANTRY_R, 180.0 + 90.0 * i / 9.0))
	flat.append(Vector2(113.0, 22.3))
	flat.append(Vector2(113.0, MZ0))
	floor_poly(flat, 12.0, c(Color(0.30, 0.30, 0.31), CourthouseKit.K_TAR), c(CEIL, CourthouseKit.K_PLASTER), 0.6, true)
	for i in 9:
		_rail(w(flat[i].x, flat[i].y, 12.0), w(flat[i + 1].x, flat[i + 1].y, 12.0), 0.9)
	# Balconies on the south gable and the first east gable, before their
	# doors.
	_balcony([Vector2(MX0, 41.0), Vector2(55.2, 41.0), Vector2(55.2, 52.6), Vector2(MX0, 52.6)], F3)
	_balcony([Vector2(59.0, MZ1), Vector2(59.0, 86.3), Vector2(72.0, 86.3), Vector2(72.0, MZ1)], F3 + 0.5)


## A piece of the roof over a plan polygon on a plane: slate in courses of
## colour by height, or the flat's tin with its cresting; a plastered
## underside for the room beneath.
func roof_piece(poly: PackedVector2Array, pl: Vector3, flat: bool) -> void:
	var world := func(p: Vector2) -> Vector3: return w(p.x, p.y, ph(pl, p))
	var a3: Vector3 = world.call(Vector2(0, 0))
	var b3: Vector3 = world.call(Vector2(0, 1))
	var c3: Vector3 = world.call(Vector2(1, 0))
	var n := (b3 - a3).cross(c3 - a3).normalized()
	if n.y < 0.0:
		n = -n
	var courses: Array[Color] = [SLATE, SLATE, SLATE, SLATE_DARK, SLATE, SLATE, SLATE_RED, SLATE, SLATE, SLATE_DARK, SLATE, SLATE_RED]
	var bands: Array = []
	if flat:
		bands.append([poly, c(Color(0.30, 0.30, 0.31), CourthouseKit.K_TAR)])
	else:
		var y0 := 1e9
		var y1 := -1e9
		for p: Vector2 in poly:
			y0 = minf(y0, ph(pl, p))
			y1 = maxf(y1, ph(pl, p))
		var step := 1.6
		var k0 := int(floor(y0 / step))
		var k1 := int(floor(y1 / step))
		for kk in range(k0, k1 + 1):
			var strip := meet([poly], under(pl, Vector3(0, 0, (kk + 1) * step)))
			strip = meet(strip, under(Vector3(0, 0, kk * step), pl))
			for s: PackedVector2Array in strip:
				bands.append([s, c(courses[posmod(kk, courses.size())], CourthouseKit.K_SLATE)])
	var ceil := c(CEIL, CourthouseKit.K_PLASTER)
	for b: Array in bands:
		var p := b[0] as PackedVector2Array
		var idx := Geometry2D.triangulate_polygon(p)
		for i in range(0, idx.size(), 3):
			var t0: Vector3 = world.call(p[idx[i]])
			var t1: Vector3 = world.call(p[idx[i + 1]])
			var t2: Vector3 = world.call(p[idx[i + 2]])
			k.m.tri("wall", t0, t1, t2, n, b[1] as Color)
			k.m.tri("wall", t0 - n * 0.1, t1 - n * 0.1, t2 - n * 0.1, -n, ceil)
	if flat:
		for i in poly.size():
			_cresting(world.call(poly[i]), world.call(poly[(i + 1) % poly.size()]))


## A small balcony: boards over the outline (survey plan, the house side
## first and last) at y feet, a railing round its open sides.
func _balcony(pts: Array, y: float) -> void:
	floor_poly(pts, y, c(PORCH, HarborTown.K_PLANK), c(TRIM, CourthouseKit.K_PAINT), 0.5)
	for i in range(1, pts.size() - 1):
		xrail(w(pts[i - 1].x, pts[i - 1].y, y) if i > 1 else w(pts[0].x, pts[0].y, y).lerp(w(pts[1].x, pts[1].y, y), 1.0),
			w(pts[i].x, pts[i].y, y), 0.95)
	for i in range(1, pts.size() - 2):
		xrail(w(pts[i].x, pts[i].y, y), w(pts[i + 1].x, pts[i + 1].y, y), 0.95)
	# Brackets under it.
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in range(1, pts.size() - 1):
		var p := w(pts[i].x, pts[i].y, y - 0.5)
		var back := w(pts[0].x if i == 1 else pts[pts.size() - 1].x, pts[0].y if i == 1 else pts[pts.size() - 1].y, y - 4.0)
		k.m.bar("wall", p, Vector3(p.x, back.y, p.z).lerp(back, 0.8), 0.05, 4, trim)


## A gable standing out of the main roof: pitched as the main roof is,
## its eaves level with the main eaves, so its slopes die into the main
## roof's in valleys and its ridge runs out onto it; as wide as a-b on
## the wall, `inward` a point inside.
func cross_gable(a: Vector2, b: Vector2, inward: Vector2) -> void:
	var half := (b - a).length() / 2.0
	gable(a, b, inward, half + 3.0, EAVE, EAVE + SLOPE * half, true, false, 1.4)


## A gable: its face on the house's wall between the eave corners a and
## b (survey plan), the roof running `depth` feet back into the house
## (`inward` a point that way); from the eave y0 to the peak y1. Its two
## slopes join the main roof's planes (or, `alone`, are drawn whole with
## the far end closed). The face is brick with its openings cut in
## courses that narrow with the rakes; the rakes carry carved
## bargeboards, a truss of sticks in the peak and a finial.
func gable(a: Vector2, b: Vector2, inward: Vector2, depth: float, y0: float, y1: float, face := true, alone := false,
		over := 1.8) -> void:
	var along := (b - a).normalized()
	var half := (b - a).length() / 2.0
	var mid := (a + b) / 2.0
	var into := Vector2(-along.y, along.x)
	if into.dot(inward - mid) < 0.0:
		into = -into
	var s := (y1 - y0) / half
	var drop := over * s
	for side: float in [-1.0, 1.0]:
		var edge := mid + along * side * (half + over)
		var ea := edge - into * over
		var eb := edge + into * depth
		var ra := mid - into * over
		var rb := mid + into * depth
		if alone:
			slope(w(ea.x, ea.y, y0 - drop), w(eb.x, eb.y, y0 - drop), w(rb.x, rb.y, y1), w(ra.x, ra.y, y1))
		else:
			gable_slopes.append({"plane": plane3(Vector3(ea.x, ea.y, y0 - drop), Vector3(eb.x, eb.y, y0 - drop), Vector3(rb.x, rb.y, y1)),
				"poly": PackedVector2Array([ea, eb, rb, ra])})
	if alone:
		var fa := mid + along * (half + over) + into * depth
		var fb := mid - along * (half + over) + into * depth
		var fm := mid + into * depth
		var back := w2(fm + into) - w2(fm)
		k.m.tri("wall", w(fa.x, fa.y, y0 - drop), w(fb.x, fb.y, y0 - drop), w(fm.x, fm.y, y1), Vector3(back.x, 0, back.y).normalized(),
			c(SLATE, CourthouseKit.K_SLATE))
	if not face:
		return
	# The face in courses, each as wide as the rakes allow at its middle.
	var fr := frame(a, b, mid - into)
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var courses := int((y1 - y0) / 1.0)
	for i in courses:
		var ya := y0 + (y1 - y0) * i / courses
		var yb := y0 + (y1 - y0) * (i + 1) / courses
		var half_w := half * (1.0 - ((ya + yb) / 2.0 - y0) / (y1 - y0)) * FT
		var mine := ops_on(f, length, ya, yb, 0.8)
		k.wall("wall", f, length / 2.0 - half_w, length / 2.0 + half_w, h(ya), h(yb), T * FT, c(BRICK, CourthouseKit.K_BRICK), mine, 1000.0)
		if i % 4 == 2:
			k.wall("wall", f * Transform3D(Basis(), Vector3(0, 0, 0.012)), length / 2.0 - half_w, length / 2.0 + half_w, h(ya), h(ya) + 0.12,
				0.012, c(BLACK, CourthouseKit.K_BRICK), mine, -1000.0)
	for o: Dictionary in ops_on(f, length, y0, y1, 0.8):
		_dress(f, o)
	# The bargeboards along the rakes, scalloped; the truss; a finial.
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var ang := atan2((y1 - y0 + drop) * FT, (half + over) * FT)
	var rake := sqrt(pow((half + over) * FT, 2) + pow((y1 - y0 + drop) * FT, 2))
	var ff := f * Transform3D(Basis(), Vector3(0, 0, over * FT * 0.9))
	for side: float in [-1.0, 1.0]:
		var cen := Vector3(length / 2.0 + side * (half + over) * FT / 2.0, (h(y0 - drop) + h(y1)) / 2.0 - 0.1, 0.0)
		k.box_rz("wall", ff, cen, Vector3(rake, 0.34, 0.06), -side * ang, trim)
		var n := int(rake / 0.35)
		for j in n:
			var t := (j + 0.5) / n
			var p := Vector3(length / 2.0 + side * (half + over) * FT * (1.0 - t), lerpf(h(y0 - drop), h(y1), t) - 0.36, 0.0)
			k.box_rz("wall", ff, p, Vector3(0.12, 0.12, 0.05), -side * ang + PI / 4.0, trim)
	var tf := f * Transform3D(Basis(), Vector3(0, 0, 0.08))
	var ty := h(y0 + (y1 - y0) * 0.5)
	var tw := half * FT * 0.5 * 2.0
	k.box("wall", tf, Vector3(length / 2.0, ty, 0.0), Vector3(tw, 0.14, 0.1), trim)
	k.box("wall", tf, Vector3(length / 2.0, (ty + h(y1)) / 2.0, 0.0), Vector3(0.14, h(y1) - ty, 0.1), trim)
	for side: float in [-1.0, 1.0]:
		var p0 := Vector3(length / 2.0, ty + 0.1, 0.0)
		var p1 := Vector3(length / 2.0 + side * tw / 2.0, ty - 0.9, 0.0)
		k.box_rz("wall", tf, (p0 + p1) / 2.0, Vector3(0.12, p0.distance_to(p1), 0.09), side * atan2(tw / 2.0, 1.0), trim)
	var out3 := w2(mid - into) - w2(mid)
	var tip := w(mid.x, mid.y, y1) + Vector3(out3.x, 0, out3.y).normalized() * over * FT * 0.9
	k.m.bar("wall", tip, tip + Vector3(0, 1.1, 0), 0.05, 6, trim)
	k.m.sphere("wall", Transform3D(Basis(), tip + Vector3(0, 0.55, 0)), 0.1, 8, trim)
	k.m.bar("wall", tip, tip - Vector3(0, 0.6, 0), 0.06, 6, trim)


## An octagonal cone or spire from ring y0 to point y1 (feet), radius r
## feet at the ring, turned by `turn`.
func _cone(cen: Vector2, r: float, y0: float, y1: float, sides: int, turn: float) -> void:
	var apex := w(cen.x, cen.y, y1)
	var ring: Array[Vector3] = []
	for i in sides:
		var a := turn + TAU * i / sides
		ring.append(w(cen.x + cos(a) * r, cen.y + sin(a) * r, y0))
	for i in sides:
		slope(ring[i], ring[(i + 1) % sides], apex, apex)
	_fascia(ring)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	k.m.bar("wall", apex - Vector3(0, 0.2, 0), apex + Vector3(0, 1.4, 0), 0.05, 6, trim)
	k.m.sphere("wall", Transform3D(Basis(), apex + Vector3(0, 0.7, 0)), 0.12, 8, trim)
	k.m.bar("iron", apex + Vector3(0, 1.4, 0), apex + Vector3(0, 2.2, 0), 0.015, 4, IRON)


## An iron or wooden railing from a to b (world), h metres tall: a rail
## and balusters; solid to the player.
func _rail(a: Vector3, b: Vector3, ht: float, col := TRIM) -> void:
	var trim := c(col, CourthouseKit.K_PAINT)
	var length := a.distance_to(b)
	if length < 0.05:
		return
	k.m.bar("wall", a + Vector3(0, ht, 0), b + Vector3(0, ht, 0), 0.05, 4, trim)
	k.m.bar("wall", a + Vector3(0, 0.08, 0), b + Vector3(0, 0.08, 0), 0.04, 4, trim)
	var n := int(length / 0.14)
	for i in n + 1:
		var p := a.lerp(b, float(i) / maxi(n, 1))
		k.m.bar("wall", p, p + Vector3(0, ht, 0), 0.018, 4, trim)
	var mid := (a + b) / 2.0 + Vector3(0, ht / 2.0, 0)
	var d := (b - a).normalized()
	var body := Transform3D(Basis(d.cross(Vector3.UP).normalized(), Vector3.UP, d), mid)
	k.solid(body, Vector3.ZERO, Vector3(0.08, ht, length))


## A crossed railing between posts, as round the porches: rails top and
## bottom, an X in each panel.
func xrail(a: Vector3, b: Vector3, ht: float) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var length := a.distance_to(b)
	if length < 0.1:
		return
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
	var d := (b - a).normalized()
	k.solid(Transform3D(Basis(d.cross(Vector3.UP).normalized(), Vector3.UP, d), mid), Vector3.ZERO, Vector3(0.08, ht, length))


## ---- floors --------------------------------------------------------------

## A floor over a polygon (survey plan) at y feet: its top in `top`, its
## underside `thick` feet lower in `under`, solid to the player unless
## `hollow`. Concave outlines are cut into triangles.
func floor_poly(pts: Array, y: float, top: Color, under: Color, thick := 0.8, solid := true, key := "wall") -> void:
	var flat := PackedVector2Array()
	for p: Vector2 in pts:
		flat.append(w2(p))
	var idx := Geometry2D.triangulate_polygon(flat)
	var yt := h(y) + 0.002
	var yb := h(y - thick)
	for i in range(0, idx.size(), 3):
		var a := flat[idx[i]]
		var b := flat[idx[i + 1]]
		var cc := flat[idx[i + 2]]
		k.m.tri(key, Vector3(a.x, yt, a.y), Vector3(b.x, yt, b.y), Vector3(cc.x, yt, cc.y), Vector3.UP, top)
		if under.a >= 0.0 and thick > 0.0:
			k.m.tri("wall", Vector3(a.x, yb, a.y), Vector3(b.x, yb, b.y), Vector3(cc.x, yb, cc.y), Vector3.DOWN, under)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionPolygon3D.new()
		shape.polygon = flat
		var depth := maxf(thick * FT, 0.1)
		shape.depth = depth
		shape.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, h(y) - depth / 2.0, 0))
		body.add_child(shape)
		k.solids.add_child(body)
		k.solid_count += 1


## ---- towers --------------------------------------------------------------

## The two towers' open tops: over the guest room's octagon the Texas
## deck, eight posts under a low pyramid; over the library's alcove a
## smaller deck under a tall spire. Railings round both, open to the
## house on its side.
func _towers() -> void:
	_deck_tower(Vector2(54.0, 63.5), 8.8, F3 + 0.6, 34.0, 37.5, [7, 0])
	_deck_tower(Vector2(73.2, 34.0), 6.0, F3 + 0.6, 33.0, 48.5, [1])


func _deck_tower(cen: Vector2, r: float, floor_y: float, eave_y: float, peak: float, open_sides: Array) -> void:
	var sides := 8
	var turn := PI / 8.0
	var ring: Array[Vector2] = []
	for i in sides:
		var a := turn + TAU * i / sides
		ring.append(cen + Vector2(cos(a), sin(a)) * r)
	floor_poly(ring, floor_y, c(PORCH, HarborTown.K_PLANK), c(CEIL, CourthouseKit.K_PLASTER), 1.0)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		var pa := w(a.x, a.y, floor_y)
		var pb := w(b.x, b.y, floor_y)
		# The posts, their brackets up to the plate.
		k.box("wall", Transform3D(), (pa + w(a.x, a.y, eave_y)) / 2.0, Vector3(0.16, h(eave_y) - h(floor_y), 0.16), trim)
		k.solid(Transform3D(), (pa + w(a.x, a.y, eave_y)) / 2.0, Vector3(0.16, h(eave_y) - h(floor_y), 0.16))
		k.m.bar("wall", w(a.x, a.y, eave_y), w(b.x, b.y, eave_y), 0.1, 4, trim)
		# A fret of sticks under the plate.
		for j in 7:
			var t := (j + 0.5) / 7.0
			var p := w(a.x, a.y, eave_y).lerp(w(b.x, b.y, eave_y), t)
			k.m.bar("wall", p, p - Vector3(0, 0.45, 0), 0.018, 4, trim)
		k.m.bar("wall", pa.lerp(pb, 0.0) + Vector3(0, h(eave_y) - h(floor_y) - 0.45, 0), pb + Vector3(0, h(eave_y) - h(floor_y) - 0.45, 0), 0.03, 4, trim)
		var mid := pa.lerp(pb, 0.5)
		for s: float in [0.0, 1.0]:
			var post := pa if s == 0.0 else pb
			k.m.bar("wall", post + Vector3(0, h(eave_y) - h(floor_y) - 0.8, 0), post.lerp(mid, 0.3) + Vector3(0, h(eave_y) - h(floor_y), 0), 0.035, 4, trim)
		if not open_sides.has(i):
			xrail(pa, pb, 0.95)
	_cone(cen, r + 1.6, eave_y, peak, 8, turn)


## ---- the conservatory --------------------------------------------------

## A half round of glass off the library's south end: a brick base, walls
## of glass in white-painted frames, a glass roof on ribs rising to the
## library's wall, a fountain in a round basin in the middle.
func _conservatory() -> void:
	var outline: Array[Vector2] = [Vector2(MX0, MZ0 + 0.2)]
	for i in 13:
		outline.append(_arc_point(CONS_C, CONS_R, -90.0 - 180.0 * i / 12.0))
	outline.append(Vector2(MX0, 55.5))
	var white := c(Color(0.88, 0.86, 0.80), CourthouseKit.K_PAINT)
	var base_y := 2.2
	var top_y := 9.5
	for i in outline.size() - 1:
		var a := outline[i]
		var b := outline[i + 1]
		if a.x >= MX0 - 0.01 and b.x >= MX0 - 0.01:
			continue
		run(a, b, CONS_C, GRADE, base_y, false)
		var pa := w(a.x, a.y, base_y)
		var pb := w(b.x, b.y, base_y)
		var qa := w(a.x, a.y, top_y)
		var qb := w(b.x, b.y, top_y)
		var n3 := (pb - pa).cross(Vector3.UP).normalized()
		k.m.quad("glass", pa, pb, qb, qa, n3, Color(1, 1, 1, 1))
		k.m.bar("wall", pa, qa, 0.05, 4, white)
		k.m.bar("wall", qa, qb, 0.06, 4, white)
		k.m.bar("wall", pa.lerp(pb, 0.5), qa.lerp(qb, 0.5), 0.025, 4, white)
		k.m.bar("wall", pa + Vector3(0, 0.9, 0), pb + Vector3(0, 0.9, 0), 0.02, 4, white)
		var mid := (pa + qb) / 2.0
		var d := (pb - pa).normalized()
		k.solid(Transform3D(Basis(d.cross(Vector3.UP).normalized(), Vector3.UP, d), mid), Vector3.ZERO, Vector3(0.06, qb.y - pa.y, pa.distance_to(pb)))
	# The roof: glass from the ring up to a ridge against the library.
	var ridge := w(MX0, CONS_C.y, 15.0)
	for i in outline.size() - 1:
		var a := w(outline[i].x, outline[i].y, top_y)
		var b := w(outline[i + 1].x, outline[i + 1].y, top_y)
		var n := (b - a).cross(ridge - a).normalized()
		if n.y < 0.0:
			n = -n
		k.m.tri("glass", a, b, ridge, n, Color(1, 1, 1, 1))
		k.m.bar("wall", a, ridge, 0.04, 4, white)
	_fascia(_ring3(outline, top_y))


func _ring3(pts: Array[Vector2], y: float) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append(w(p.x, p.y, y))
	return out


## ---- porches -------------------------------------------------------------

## The ombra wrapping the south-east corner, the veranda along the east
## front to the entrance, the porte-cochere over the drive: decks of
## boards on a latticed skirt, posts with braces, crossed railings, flat
## roofs on a bracketed plate; steps down to the drive.
func _porches() -> void:
	var deck := -0.6
	var ombra: Array[Vector2] = [Vector2(48.4, 67.3), Vector2(29.2, 67.3), Vector2(22.8, 74.4), Vector2(22.8, 84.0), Vector2(29.3, 90.2),
		Vector2(48.4, 90.2)]
	var veranda: Array[Vector2] = [Vector2(48.4, 81.5), Vector2(96.3, MZ1 - 0.5), Vector2(96.3, 92.8), Vector2(84.8, 92.8), Vector2(84.8, 90.0),
		Vector2(75.6, 90.0)]
	# The bow before the guest room's bath and Susy's room.
	var bow_c := Vector2(66.8, 83.65)
	for i in range(1, 12):
		var a := deg_to_rad(35.8 + 108.4 * i / 12.0)
		veranda.append(bow_c + Vector2(cos(a), sin(a)) * 10.85)
	veranda.append_array([Vector2(58.0, 90.0), Vector2(56.0, 90.0), Vector2(56.0, 93.0), Vector2(50.0, 93.0), Vector2(50.0, 90.2),
		Vector2(48.4, 90.2)])
	var boards := c(PORCH, HarborTown.K_PLANK)
	var under := c(Color(0.62, 0.56, 0.46), CourthouseKit.K_PAINT)
	floor_poly(ombra, deck, boards, under, 0.5)
	floor_poly(veranda, deck, boards, under, 0.5)
	for poly: Array in [ombra, veranda]:
		_skirt(poly, deck)
	# The ombra: posts round its outer edge, the house side open.
	_porch_edge(ombra.slice(0, 6), deck, 10.2, [])
	var roof_o: Array[Vector2] = [Vector2(49.0, 65.5), Vector2(28.4, 65.5), Vector2(21.0, 73.6), Vector2(21.0, 84.8), Vector2(28.5, 92.0),
		Vector2(49.0, 92.0)]
	_porch_roof(roof_o, 10.8)
	# The veranda: posts along its outer edge; the steps' gap left open.
	var edge := veranda.slice(2)
	edge.reverse()
	_porch_edge(edge, deck, 9.8, [Vector2(90.5, 92.8)])
	var roof_v: Array[Vector2] = veranda.duplicate()
	for i in roof_v.size():
		var p := roof_v[i]
		if p.y > MZ1 + 0.1:
			roof_v[i] = p + Vector2(0, 1.2)
	_porch_roof(roof_v, 10.3)
	# The steps from the entrance landing down to the drive.
	var s0 := w(90.5, 92.8, deck)
	var s1 := w(90.5, 96.6, GRADE)
	var stone := c(Color(0.50, 0.46, 0.42), CourthouseKit.K_STONE)
	for i in 4:
		var t := (i + 0.5) / 4.0
		var p := s0.lerp(s1, t)
		k.box("wall", Transform3D(), Vector3(p.x, p.y / 2.0, p.z), Vector3(0.3, maxf(p.y, 0.05), 10.0 * FT), stone)
	k.ramp(Transform3D(), Vector3(s1.x, 0.0, s1.z), Vector3(s0.x, s0.y, s0.z), 10.0 * FT)
	_porte_cochere()
	# The steps from the ombra down to the lawn, south.
	var o0 := w(24.0, 79.0, deck)
	var o1 := w(19.5, 79.0, GRADE)
	k.ramp(Transform3D(), Vector3(o1.x, 0.0, o1.z), o0, 5.0 * FT)
	for i in 4:
		var p := o0.lerp(o1, (i + 0.5) / 4.0)
		k.box("wall", Transform3D(), Vector3(p.x, p.y / 2.0, p.z), Vector3(5.0 * FT, maxf(p.y, 0.05), 0.3), stone)


## The lattice skirt round a deck's edge, from the lawn to the boards.
func _skirt(poly: Array, deck: float) -> void:
	var lattice := c(TRIM, CourthouseKit.K_PAINT)
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var pa := w(a.x, a.y, GRADE)
		var pb := w(b.x, b.y, GRADE)
		var n3 := (pb - pa).cross(Vector3.UP).normalized()
		var top := h(deck - 0.5)
		k.m.quad("wall", pa, pb, Vector3(pb.x, top, pb.z), Vector3(pa.x, top, pa.z), n3, c(Color(0.16, 0.08, 0.05), CourthouseKit.K_TAR))
		k.m.quad("wall", pa, pb, Vector3(pb.x, top, pb.z), Vector3(pa.x, top, pa.z), -n3, c(Color(0.16, 0.08, 0.05), CourthouseKit.K_TAR))
		var length := pa.distance_to(pb)
		var n := int(length / 0.3)
		for j in n:
			var q0 := pa.lerp(pb, float(j) / maxi(n, 1)) + n3 * 0.02
			var q1 := pa.lerp(pb, float(j + 1) / maxi(n, 1)) + n3 * 0.02
			k.m.bar("wall", q0, Vector3(q1.x, top, q1.z), 0.012, 3, lattice)
			k.m.bar("wall", q1, Vector3(q0.x, top, q0.z), 0.012, 3, lattice)
		k.m.bar("wall", Vector3(pa.x, top, pa.z) + n3 * 0.04, Vector3(pb.x, top, pb.z) + n3 * 0.04, 0.05, 4, lattice)


## Posts along a porch's outer edge (survey points in order), a plate
## over them at top feet, braces from each post to the plate both ways,
## crossed railings between; none across a gap at any of `gaps`.
func _porch_edge(edge: Array, deck: float, top: float, gaps: Array) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var posts: Array[Vector3] = []
	for i in edge.size() - 1:
		var a := w(edge[i].x, edge[i].y, deck)
		var b := w(edge[i + 1].x, edge[i + 1].y, deck)
		var n := maxi(1, int(round(a.distance_to(b) / 2.6)))
		for j in n:
			posts.append(a.lerp(b, float(j) / n))
	posts.append(w(edge[edge.size() - 1].x, edge[edge.size() - 1].y, deck))
	var rise := h(top) - h(deck)
	for p: Vector3 in posts:
		k.box("wall", Transform3D(), p + Vector3(0, rise / 2.0, 0), Vector3(0.15, rise, 0.15), trim)
		k.box("wall", Transform3D(), p + Vector3(0, 0.12, 0), Vector3(0.22, 0.24, 0.22), trim)
		k.box("wall", Transform3D(), p + Vector3(0, rise - 0.2, 0), Vector3(0.2, 0.12, 0.2), trim)
		k.solid(Transform3D(), p + Vector3(0, rise / 2.0, 0), Vector3(0.15, rise, 0.15))
	for i in posts.size() - 1:
		var a := posts[i]
		var b := posts[i + 1]
		k.m.bar("wall", a + Vector3(0, rise, 0), b + Vector3(0, rise, 0), 0.09, 4, trim)
		k.m.bar("wall", a + Vector3(0, rise - 0.9, 0), a.lerp(b, 0.3) + Vector3(0, rise - 0.05, 0), 0.04, 4, trim)
		k.m.bar("wall", b + Vector3(0, rise - 0.9, 0), b.lerp(a, 0.3) + Vector3(0, rise - 0.05, 0), 0.04, 4, trim)
		# A small fretted bracket where brace meets plate.
		k.box("wall", Transform3D(), a.lerp(b, 0.5) + Vector3(0, rise - 0.12, 0), Vector3(0.08, 0.2, 0.08), trim)
		var gap := false
		for g: Vector2 in gaps:
			var gw := w(g.x, g.y, deck)
			if Vector2(gw.x, gw.z).distance_to(Vector2((a.x + b.x) / 2.0, (a.z + b.z) / 2.0)) < a.distance_to(b) * 0.6 + 0.3:
				gap = true
		if not gap:
			xrail(a, b, 0.85)


## A porch's roof: flat, boarded under, a deep fascia with a fret of
## sticks along it, over the outline at y feet.
func _porch_roof(poly: Array, y: float) -> void:
	floor_poly(poly, y + 0.6, c(Color(0.30, 0.29, 0.29), CourthouseKit.K_TAR), c(Color(0.60, 0.50, 0.38), CourthouseKit.K_WOOD), 0.6, false)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in poly.size():
		var a := w(poly[i].x, poly[i].y, y)
		var b := w(poly[(i + 1) % poly.size()].x, poly[(i + 1) % poly.size()].y, y)
		if poly[i].y < MZ1 + 0.1 and poly[(i + 1) % poly.size()].y < MZ1 + 0.1 and poly[i].x > 48.0 and poly[(i + 1) % poly.size()].x > 48.0:
			continue
		var n3 := (b - a).cross(Vector3.UP).normalized()
		k.m.quad("wall", a - Vector3(0, 0.02, 0), b - Vector3(0, 0.02, 0), b + Vector3(0, 0.2, 0), a + Vector3(0, 0.2, 0), n3, trim)
		k.m.quad("wall", a - Vector3(0, 0.02, 0), b - Vector3(0, 0.02, 0), b + Vector3(0, 0.2, 0), a + Vector3(0, 0.2, 0), -n3, trim)
		var n := int(a.distance_to(b) / 0.12)
		for j in n:
			var p := a.lerp(b, (j + 0.5) / n)
			k.m.bar("wall", p - Vector3(0, 0.02, 0), p - Vector3(0, 0.22 if j % 2 == 0 else 0.14, 0), 0.012, 3, trim)


## The porte-cochere: a gabled roof on four posts over the drive, braced
## and bracketed, the veranda's landing under its near end.
func _porte_cochere() -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var posts := [Vector2(85.3, 97.0), Vector2(96.3, 97.0), Vector2(85.3, 109.5), Vector2(96.3, 109.5)]
	var top := 10.2
	for p: Vector2 in posts:
		var foot := w(p.x, p.y, GRADE)
		var head := w(p.x, p.y, top)
		k.block("wall", Transform3D(), Vector3(foot.x, 0.2, foot.z), Vector3(0.5, 0.4, 0.5), c(Color(0.50, 0.46, 0.42), CourthouseKit.K_STONE))
		k.turned("wall", Transform3D(), foot + Vector3(0, 0.4, 0), head.y - 0.4, 0.14, trim)
		k.solid(Transform3D(), (foot + head) / 2.0, Vector3(0.25, head.y, 0.25))
	for pair: Array in [[0, 1], [2, 3], [0, 2], [1, 3]]:
		var a := w((posts[pair[0]] as Vector2).x, (posts[pair[0]] as Vector2).y, top)
		var b := w((posts[pair[1]] as Vector2).x, (posts[pair[1]] as Vector2).y, top)
		k.m.bar("wall", a, b, 0.11, 4, trim)
		k.m.bar("wall", a - Vector3(0, 1.0, 0), a.lerp(b, 0.25), 0.05, 4, trim)
		k.m.bar("wall", b - Vector3(0, 1.0, 0), b.lerp(a, 0.25), 0.05, 4, trim)
	# The roof, its ridge running out from the house over the drive.
	gable(Vector2(99.0, 112.0), Vector2(82.5, 112.0), Vector2(90.75, 90.0), 21.0, top + 0.2, 16.0, false, true)
	# Its open gable end: a truss of sticks and a fan.
	var fa := w(99.0, 112.2, top + 0.2)
	var fb := w(82.5, 112.2, top + 0.2)
	var fm := w(90.75, 112.2, 16.0)
	k.m.bar("wall", fa, fb, 0.08, 4, trim)
	k.m.bar("wall", (fa + fb) / 2.0, fm, 0.07, 4, trim)
	for i in 7:
		var t := (i + 0.5) / 7.0
		k.m.bar("wall", (fa + fb) / 2.0 + Vector3(0, 0.3, 0), fa.lerp(fm, t) if i < 4 else fb.lerp(fm, 1.0 - t + 0.5 / 7.0), 0.025, 3, trim)


## ---- lights --------------------------------------------------------------

## How dark it is, 0 day to 1 night: the gas is lit low by day in the
## darker rooms and full after dark.
func set_darkness(dark: float) -> void:
	var on := smoothstep(0.35, 0.6, dark)
	lamp_mat.emission_energy_multiplier = 0.6 + 2.2 * on
	flame_mat.emission_energy_multiplier = 1.0 + 2.0 * on
	for l: Dictionary in lights:
		var light := l["light"] as OmniLight3D
		var level := lerpf(float(l.get("day", 0.35)), 1.0, on)
		light.visible = level > 0.01
		light.light_energy = float(l["energy"]) * level


## A gas light's glow at p, reaching `reach` metres.
func gaslight(p: Vector3, energy: float, reach: float, day := 0.35) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.omni_range = reach
	light.light_color = Color(1.0, 0.80, 0.55)
	light.light_energy = energy
	light.shadow_enabled = false
	light.visible = false
	add_child(light)
	lights.append({"light": light, "energy": energy, "day": day})
