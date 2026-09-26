class_name UnionCourthouse
extends Node3D
## The Union County Courthouse at Monroe, North Carolina (J. T. Hart,
## 1886; the outer wings 1922, their detail copied from the first), on
## its square. Two storeys of red brick under white painted trim: a main
## block of five bays with a pedimented centre pavilion on each long
## front, east and west, the wings north and south of it lower, flat
## roofed behind a panelled parapet over a bracketed cornice. Before
## each pavilion a one-storey wooden porch of three arches under a slate
## mansard crowned with iron; over it three tall round-arched windows in
## stone archivolts. The first-floor windows have segmental heads under
## eared stone hoods, the second floor of the main block round heads
## on stone imposts. A low slate hip roof with four chimneys carries the
## great cupola: a stage with paired small windows, the main stage with
## rusticated corners, fluted pilasters and a round-arched louvred vent
## on each face, a pediment, urns at the corners, and a bell roof of
## slate with a clock in a dormer on each face, the vane over all.
##
## Inside: a hall down the length of the ground floor crossed by one
## from porch to porch, the stairs at its north and south ends, offices
## and the Heritage Room off it; upstairs the courtroom fills the main
## block, five arched windows down each side, pilasters under a frieze
## of garlands and cartouches, the bench under an arched niche at the
## north end.
##
## Frame: the origin is the middle of the main block at grade, +x east,
## -z north. Measured from the county's footprint (the building about
## 44 by 20 m), the National Register nomination (1971), photographs and
## street imagery. Art only: no records. The clocks keep the world's time.

const F1 := 1.4          # the ground floor
const F2 := 6.8          # the courtroom floor
const MX := 9.7          # main block's half width, east-west
const MZ := 8.65         # main block's half length, north-south
const PX := 10.2         # the pavilion's face
const PZ := 4.6          # the pavilion's half width
const WX := 8.5          # the wings' half width
const WZ := 21.95        # the wings' ends
const T := 0.5           # an outside wall
const SKIN := 0.15       # its face of brick; the rest is finished inside
const EAVE := 14.8       # the main cornice's top
const MAIN_WALL := 14.3
const WING_TOP := 11.7   # the wings' cornice top
const PARAPET := 12.6
const WING_ROOF := 11.4
const BAND := 6.3        # between the storeys' openings
const PED_RISE := 3.4
const ROOF_SLOPE := 0.5

const BRICK := Color(0.60, 0.30, 0.22)
const TRIM := Color(0.93, 0.90, 0.79)
const SLATE := Color(0.25, 0.27, 0.30)
const GRANITE := Color(0.70, 0.69, 0.66)
const IRON := Color(0.06, 0.06, 0.065)
const PLASTER := Color(0.91, 0.83, 0.62)
const DOOR := Color(0.34, 0.20, 0.11)
const PORCH_FLOOR := Color(0.42, 0.43, 0.42)

var k: CourthouseKit
var glass_mat: StandardMaterial3D
var wall_mat: ShaderMaterial
var iron_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var dial_mat: StandardMaterial3D
## The clocks' hands, [hour, minute] per dial.
var clock_hands: Array[Array] = []
## The lights inside, which come on as the day goes: {light, energy}.
var lights: Array[Dictionary] = []
var stats: Dictionary = {}


func build() -> void:
	name = "UnionCourthouse"
	var t0 := Time.get_ticks_msec()
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	_materials()
	_foundation()
	for s: float in [-1.0, 1.0]:
		_long_side(s)
		_porch(s)
	for e: float in [-1.0, 1.0]:
		_end(e)
		_main_end_wall(e)
		_chimneys(e)
	_roofs()
	_cupola()
	# The rooms go in meshes of their own: nothing in them casts the sun's
	# shadow (the walls and roof do that), and from far off they are not
	# drawn at all.
	var outer := k.m
	k.m = TownMesh.new()
	CourthouseInterior.build(self)
	var inner := k.m
	k.m = outer
	var mats := {"wall": wall_mat, "glass": glass_mat, "iron": iron_mat, "lamp": lamp_mat, "dial": dial_mat}
	var drawn: Array = outer.commit(self, mats, ["wall", "iron"]).values()
	for mi: MeshInstance3D in inner.commit(self, mats, []).values():
		mi.visibility_range_end = 150.0
		drawn.append(mi)
	# Glass lets the sky's light into the rooms when light is traced
	# through the scene (global illumination): it takes no part in it.
	for mi: MeshInstance3D in drawn:
		if mi.name.ends_with("glass"):
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	stats = {"triangles": outer.triangles + inner.triangles, "inside": inner.triangles, "solids": k.solid_count,
		"ms": Time.get_ticks_msec() - t0}


func _materials() -> void:
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.55, 0.62, 0.64, 0.16)
	glass_mat.roughness = 0.04
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	iron_mat = StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.vertex_color_is_srgb = true
	iron_mat.metallic = 0.4
	iron_mat.roughness = 0.5
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.85)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.58)
	lamp_mat.emission_energy_multiplier = 0.0
	dial_mat = StandardMaterial3D.new()
	dial_mat.albedo_color = Color(0.95, 0.94, 0.90)
	dial_mat.roughness = 0.6
	dial_mat.emission_enabled = true
	dial_mat.emission = Color(1.0, 0.93, 0.78)
	dial_mat.emission_energy_multiplier = 0.0


## A facade's frame: origin at o on the outer face, z out along n.
static func face(n: Vector3, o: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP.cross(n), Vector3.UP, n), o)


func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


## ---- the ground under it -------------------------------------------------

## The brick base under the first floor with its stone water table,
## solid; the floor itself is laid by the interior.
func _foundation() -> void:
	var g := Transform3D()
	var stone := c(GRANITE, CourthouseKit.K_STONE)
	# The water table: a stone course round the whole base at the floor.
	for s: float in [-1.0, 1.0]:
		k.box("wall", g, Vector3(s * (MX + 0.04), F1 - 0.12, 0), Vector3(0.12, 0.2, 2.0 * MZ + 0.08), stone)
		k.box("wall", g, Vector3(s * (PX + 0.04), F1 - 0.12, 0), Vector3(0.12, 0.2, 2.0 * PZ + 0.08), stone)
		for e: float in [-1.0, 1.0]:
			k.box("wall", g, Vector3(s * (WX + 0.04), F1 - 0.12, e * (MZ + WZ) / 2.0), Vector3(0.12, 0.2, WZ - MZ), stone)
	for e: float in [-1.0, 1.0]:
		k.box("wall", g, Vector3(0, F1 - 0.12, e * (WZ + 0.04)), Vector3(2.0 * WX + 0.16, 0.2, 0.12), stone)
		for s: float in [-1.0, 1.0]:
			k.box("wall", g, Vector3(s * (MX + WX) / 2.0, F1 - 0.12, e * (MZ + 0.04)), Vector3(MX - WX + 0.08, 0.2, 0.12), stone)


## ---- the long fronts, east and west -------------------------------------

## Everything on the long side s (-1 west, 1 east): the main block's
## side bays, the pavilion, the wings' five bays each way, their
## cornices and the wings' parapets.
func _long_side(s: float) -> void:
	var n := Vector3(s, 0, 0)
	var fm := face(n, Vector3(s * MX, 0, 0))
	var fp := face(n, Vector3(s * PX, 0, 0))
	var fw := face(n, Vector3(s * WX, 0, 0))
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var stone := c(TRIM, CourthouseKit.K_STONE)
	# The main block's side bays, u = ±6.6.
	var side_u := (MZ + PZ) / 2.0
	var main_open: Array = []
	var pav_open: Array = []
	for e: float in [-1.0, 1.0]:
		main_open.append(CourthouseKit.opening(e * side_u, 1.3, 2.5, 5.15, "segment", 0.25))
		main_open.append(CourthouseKit.opening(e * side_u, 1.4, 7.9, 11.0, "round"))
		pav_open.append(CourthouseKit.opening(e * 2.9, 1.3, 2.2, 5.0, "segment", 0.25))
	pav_open.append(CourthouseKit.opening(0.0, 1.9, F1, 4.5, "round"))
	for u: float in [-2.9, 0.0, 2.9]:
		pav_open.append(CourthouseKit.opening(u, 1.55, 6.9, 11.2, "round"))
	# The main block's wall either side of the pavilion, and the pavilion.
	for e: float in [-1.0, 1.0]:
		var ua := minf(e * MZ, e * PZ)
		var ub := maxf(e * MZ, e * PZ)
		_ext_wall(fm, ua, ub, main_open, minf(e * (MZ - T), e * PZ), maxf(e * (MZ - T), e * PZ), MAIN_WALL)
		# The pavilion's return: its half metre of projection behind the
		# front's brick skin.
		var rx := s * (MX + PX - SKIN) / 2.0
		k.box("wall", Transform3D(), Vector3(rx, MAIN_WALL / 2.0, e * (PZ - 0.25)), Vector3(PX - MX - SKIN, MAIN_WALL, 0.5),
			c(BRICK, CourthouseKit.K_BRICK))
		k.solid(Transform3D(), Vector3(rx, 2.5, e * (PZ - 0.25)), Vector3(PX - MX - SKIN, 5.0, 0.5))
		# Inside, the corner where the pavilion's recess meets the side bay.
		k.block("wall", Transform3D(), Vector3(s * (MX - T / 2.0), (EAVE - 0.9) / 2.0, e * (PZ - 0.25)), Vector3(T, EAVE - 0.9, 0.5),
			c(PLASTER, CourthouseKit.K_PLASTER))
	_ext_wall(fp, -PZ, PZ, pav_open, -PZ + 0.5, PZ - 0.5, MAIN_WALL)
	# Trim on the main block: hoods and sills below, archivolts above.
	for o: Dictionary in main_open:
		if float(o["y0"]) < BAND:
			k.hood(fm, o, stone)
		else:
			_arched_trim(fm, o, stone, false)
		_window(fm, o)
	for o: Dictionary in pav_open:
		if float(o["y0"]) > BAND:
			_arched_trim(fp, o, stone, true)
			_window(fp, o)
		elif absf(float(o["u"])) > 1.0:
			k.hood(fp, o, stone)
			_window(fp, o)
		else:
			_door(fp, o, true)
	# The main cornice along the side bays and across the pavilion.
	for e: float in [-1.0, 1.0]:
		var ua := minf(e * MZ, e * PZ)
		var ub := maxf(e * MZ, e * PZ)
		k.cornice(fm, ua - (0.7 if e < 0 else 0.0), ub + (0.7 if e > 0 else 0.0), EAVE, 0.7, trim, 1.4)
		# The cornice's return on the pavilion's sides.
		var fret := face(Vector3(0, 0, e), Vector3(s * (MX + PX) / 2.0, 0, e * PZ))
		k.cornice(fret, -0.5, 0.5, EAVE, 0.7, trim, 2.0, 0.55, 0.55, false)
	k.cornice(fp, -PZ - 0.7, PZ + 0.7, EAVE, 0.7, trim, 1.4)
	# The pediment over the pavilion, its lunette in the tympanum.
	k.pediment(fp, Vector3(0, EAVE, 0.02), 2.0 * PZ + 0.9, PED_RISE, 0.3, c(BRICK, CourthouseKit.K_BRICK), trim, 0.62)
	var lun := CourthouseKit.opening(0.0, 1.7, EAVE + 0.35, EAVE + 0.35, "round")
	k.glass(fp, lun, 0.03, Color(1, 1, 1, 1), "glass")
	k.glass(fp, lun, 0.015, c(Color(0.08, 0.08, 0.09), CourthouseKit.K_PAINT), "wall")
	var lc := CourthouseKit.head_circle(lun)
	k.arc_band("wall", fp, lc, 0.0, PI, 0.16, 0.08, 0.1, trim, 14)
	k.box("wall", fp, Vector3(0, EAVE + 0.35, 0.05), Vector3(1.9, 0.08, 0.08), trim)
	for j in 5:
		var a := PI * (j + 1) / 6.0
		k.box_rz("wall", fp, Vector3(cos(a) * 0.42, EAVE + 0.35 + sin(a) * 0.42, 0.05), Vector3(0.03, 0.84, 0.03), a - PI / 2.0, trim)
	# The wings' fronts, five bays each.
	for e: float in [-1.0, 1.0]:
		var ua := minf(e * MZ, e * (WZ - SKIN))
		var ub := maxf(e * MZ, e * (WZ - SKIN))
		var bays: Array = []
		for b in 5:
			var u := e * (MZ + (WZ - MZ) * (b + 0.5) / 5.0)
			bays.append(CourthouseKit.opening(u, 1.2, 2.4, 5.0, "segment", 0.22))
			bays.append(CourthouseKit.opening(u, 1.2, 7.4, 9.9, "segment", 0.22))
		_ext_wall(fw, ua, ub, bays, minf(e * MZ, e * (WZ - T)), maxf(e * MZ, e * (WZ - T)), PARAPET)
		for o: Dictionary in bays:
			k.hood(fw, o, stone)
			_window(fw, o)
		var cu0 := minf(e * MZ, e * (WZ + 0.6))
		var cu1 := maxf(e * MZ, e * (WZ + 0.6))
		k.cornice(fw, cu0, cu1, WING_TOP, 0.6, trim, 1.33, 0.48, 0.52)
		_parapet(fw, cu0, cu1, 5)



## An outside wall in frame f from u0 to u1, 0 to top: a skin of brick
## and behind it the rest of the wall finished as the rooms are (from
## iu0 to iu1), with its openings through both.
func _ext_wall(f: Transform3D, u0: float, u1: float, openings: Array, iu0: float, iu1: float, top: float) -> void:
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var inner := c(PLASTER, CourthouseKit.K_PLASTER)
	k.wall("wall", f, u0, u1, 0.0, BAND, SKIN, brick, openings, 4.5)
	k.wall("wall", f, u0, u1, BAND, top, SKIN, brick, openings, 4.5)
	var fi := f * Transform3D(Basis(), Vector3(0, 0, -SKIN))
	k.wall("wall", fi, iu0, iu1, 0.0, BAND, T - SKIN, inner, openings, 4.5)
	k.wall("wall", fi, iu0, iu1, BAND, minf(top, EAVE - 0.9), T - SKIN, inner, openings, 11.0)
	# The inside of the wall on the second floor is solid to the player too.
	for o: Dictionary in openings:
		if float(o["y0"]) > BAND and float(o["y0"]) < F2 + 1.0:
			k.solid(f, Vector3(float(o["u"]), F2 + 0.45, -T / 2.0), Vector3(float(o["w"]), 0.9, T))


## A round-headed opening's stone: the archivolt round the head with a
## keystone, impost blocks at the springs, a sill; on the pavilion the
## archivolts are broader and stand on pilaster strips.
func _arched_trim(f: Transform3D, o: Dictionary, col: Color, grand: bool) -> void:
	var circ := CourthouseKit.head_circle(o)
	var w := float(o["w"])
	var ys := float(o["ys"])
	var band := 0.3 if grand else 0.2
	k.arc_band("wall", f, circ, 0.0, PI, band, 0.12, 0.12, col, 16)
	if grand:
		# A second, finer ring outside the first.
		k.arc_band("wall", f, Vector3(circ.x, circ.y, circ.z + band + 0.02), 0.0, PI, 0.07, 0.08, 0.16, col, 16)
	k.box("wall", f, Vector3(float(o["u"]), float(o["yt"]) + band * 0.6, 0.12), Vector3(0.28, band * 1.9, 0.22), col)
	k.box("wall", f, Vector3(float(o["u"]), float(o["yt"]) + band * 1.5, 0.16), Vector3(0.34, 0.08, 0.26), col)
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(float(o["u"]) + s * (w / 2.0 + band / 2.0), ys - 0.02, 0.08), Vector3(band + 0.14, 0.26, 0.16), col)
		if grand:
			k.box("wall", f, Vector3(float(o["u"]) + s * (w / 2.0 + band / 2.0), (float(o["y0"]) + ys) / 2.0, 0.04),
				Vector3(band, ys - float(o["y0"]), 0.08), col)
	k.box("wall", f, Vector3(float(o["u"]), float(o["y0"]) - 0.06, 0.08), Vector3(w + (0.7 if grand else 0.3), 0.12, 0.18), col)


## A sash window in an opening: two over two, an arched head's fan;
## the pavilion's floor-length windows have three sashes.
func _window(f: Transform3D, o: Dictionary) -> void:
	var tall := float(o["ys"]) - float(o["y0"]) > 3.5
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	# The sash is as solid as the wall round it.
	k.solid(f, Vector3(float(o["u"]), (float(o["y0"]) + float(o["yt"])) / 2.0, -SKIN - 0.04),
		Vector3(float(o["w"]), float(o["yt"]) - float(o["y0"]), 0.08))
	k.sash(f, o, -SKIN - 0.04, trim, float(o["y0"]) + (float(o["ys"]) - float(o["y0"])) * (0.62 if tall else 0.5), 1)
	if tall:
		k.box("wall", f, Vector3(float(o["u"]), float(o["y0"]) + (float(o["ys"]) - float(o["y0"])) * 0.3, -SKIN - 0.04),
			Vector3(float(o["w"]), 0.06, 0.1), trim)
	# Inside: the casing round the opening and a stool under it.
	var wood := c(Color(0.32, 0.20, 0.12), CourthouseKit.K_WOOD)
	var fi := f * Transform3D(Basis(), Vector3(0, 0, -T))
	var w := float(o["w"])
	for s: float in [-1.0, 1.0]:
		k.box("wall", fi, Vector3(float(o["u"]) + s * (w / 2.0 + 0.08), (float(o["y0"]) + float(o["ys"])) / 2.0, -0.02),
			Vector3(0.16, float(o["ys"]) - float(o["y0"]), 0.04), wood)
	k.box("wall", fi, Vector3(float(o["u"]), float(o["y0"]) - 0.02, 0.1), Vector3(w + 0.3, 0.05, 0.3), wood)
	if str(o["head"]) != "flat":
		var circ := CourthouseKit.head_circle(o)
		var a0 := atan2(float(o["ys"]) - circ.y, -w / 2.0)
		var a1 := atan2(float(o["ys"]) - circ.y, w / 2.0)
		k.arc_band("wall", fi, circ, a1, a0, 0.16, 0.04, -0.0, wood, 12)
	else:
		k.box("wall", fi, Vector3(float(o["u"]), float(o["ys"]) + 0.08, -0.02), Vector3(w + 0.32, 0.16, 0.04), wood)


## A pair of doors standing open in an opening, a fanlight over them.
func _door(f: Transform3D, o: Dictionary, stone_trim: bool) -> void:
	var w := float(o["w"])
	var u := float(o["u"])
	var y0 := float(o["y0"])
	var ys := float(o["ys"])
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var wood := c(DOOR, CourthouseKit.K_WOOD)
	# The frame and the transom bar at the spring.
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(u + s * (w / 2.0 - 0.05), (y0 + ys) / 2.0, -0.25), Vector3(0.1, ys - y0, 0.2), wood)
	k.box("wall", f, Vector3(u, ys - 0.06, -0.25), Vector3(w, 0.12, 0.2), wood)
	var fan := CourthouseKit.opening(u, w - 0.2, ys, ys, "round")
	k.glass(f, fan, -0.25)
	for j in 5:
		var a := PI * (j + 1) / 6.0
		var r := (w - 0.2) / 2.0
		k.box_rz("wall", f, Vector3(u + cos(a) * r / 2.0, ys + sin(a) * r / 2.0, -0.25), Vector3(0.03, r, 0.04), a - PI / 2.0, wood)
	# The leaves, swung in flat against the reveals.
	var leaf := (w - 0.2) / 2.0
	for s: float in [-1.0, 1.0]:
		var lf := f * Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(u + s * (w / 2.0 - 0.05), 0, -0.35 - leaf / 2.0))
		k.door_leaf(lf, Vector3(0, y0, 0), leaf, ys - y0 - 0.12, wood, true)
	if stone_trim:
		var stone := c(TRIM, CourthouseKit.K_STONE)
		var circ := CourthouseKit.head_circle(o)
		k.arc_band("wall", f, circ, 0.0, PI, 0.22, 0.1, 0.1, stone, 14)
		k.box("wall", f, Vector3(u, float(o["yt"]) + 0.14, 0.08), Vector3(0.26, 0.4, 0.16), stone)
	# The threshold.
	k.box("wall", f, Vector3(u, y0 + 0.02, -T / 2.0), Vector3(w, 0.04, T), c(GRANITE, CourthouseKit.K_STONE))


## The wings' parapet over their cornice: brick with a stone coping and
## a raised white panel over each bay.
func _parapet(f: Transform3D, u0: float, u1: float, panels: int) -> void:
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var len := u1 - u0
	k.box("wall", f, Vector3((u0 + u1) / 2.0, (WING_TOP + PARAPET) / 2.0, -0.2), Vector3(len, PARAPET - WING_TOP, 0.4), brick)
	k.box("wall", f, Vector3((u0 + u1) / 2.0, PARAPET + 0.05, -0.18), Vector3(len + 0.06, 0.1, 0.5), trim)
	for p in panels:
		var pu := u0 + len * (p + 0.5) / panels
		k.box("wall", f, Vector3(pu, (WING_TOP + PARAPET) / 2.0 + 0.04, 0.01), Vector3(minf(1.3, len / panels - 0.6), 0.42, 0.04), trim)


## ---- the ends, north and south ------------------------------------------

## A wing's end (e -1 north, 1 south): five openings a floor, the
## upper middle a pair, below it the door under a pedimented hood with
## the year; the cornice and parapet carried round.
func _end(e: float) -> void:
	var f := face(Vector3(0, 0, e), Vector3(0, 0, e * WZ))
	var stone := c(TRIM, CourthouseKit.K_STONE)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var opens: Array = []
	for u: float in [-5.8, -3.2, 3.2, 5.8]:
		opens.append(CourthouseKit.opening(u, 1.2, 2.4, 5.0, "segment", 0.22))
		opens.append(CourthouseKit.opening(u, 1.2, 7.4, 9.9, "segment", 0.22))
	for u: float in [-0.7, 0.7]:
		opens.append(CourthouseKit.opening(u, 1.05, 7.5, 9.9, "segment", 0.2))
	var door := CourthouseKit.opening(0.0, 1.7, F1, 4.3, "round")
	opens.append(door)
	_ext_wall(f, -WX, WX, opens, -WX + T, WX - T, PARAPET)
	for o: Dictionary in opens:
		if o == door:
			continue
		k.hood(f, o, stone)
		_window(f, o)
	_door(f, door, false)
	# The door's hood: consoles either side carrying an entablature
	# lettered with the year, a pediment over it.
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(s * 1.2, 4.95, 0.14), Vector3(0.24, 1.2, 0.28), stone)
		k.box("wall", f, Vector3(s * 1.2, 4.37, 0.1), Vector3(0.2, 0.14, 0.2), stone)
	k.box("wall", f, Vector3(0, 5.32, 0.12), Vector3(2.8, 0.5, 0.24), stone)
	k.box("wall", f, Vector3(0, 5.62, 0.2), Vector3(3.0, 0.12, 0.4), stone)
	k.pediment(f, Vector3(0, 5.68, 0.15), 3.0, 0.62, 0.3, stone, stone, 0.2)
	var year := Label3D.new()
	year.text = "1 8 8 6"
	year.font_size = 64
	year.pixel_size = 0.004
	year.modulate = Color(0.55, 0.53, 0.48)
	year.shaded = true
	year.double_sided = false
	year.transform = f * Transform3D(Basis(), Vector3(0, 5.3, 0.245))
	add_child(year)
	# The stoop: granite steps up to the door.
	_steps(f, 0.0, 2.9, 0.0, F1, 1.8)
	k.cornice(f, -WX - 0.6, WX + 0.6, WING_TOP, 0.6, trim, 1.4, 0.48, 0.52)
	_parapet(f, -WX - 0.6, WX + 0.6, 6)


## The main block's end wall (the wing's side of it): brick outside
## where the wing does not cover it, and above the wing's roof; inside,
## the arch from the hall and the courtroom's doors, and at the north
## end the niche behind the bench.
func _main_end_wall(e: float) -> void:
	var f := face(Vector3(0, 0, e), Vector3(0, 0, e * MZ))
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var inner := c(PLASTER, CourthouseKit.K_PLASTER)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var opens: Array = [CourthouseKit.opening(0.0, 2.4, F1, 4.9, "round")]
	if e < 0.0:
		# The judge's door, behind the bench on its west side (the frame's
		# u runs west here).
		opens.append(CourthouseKit.opening(5.2, 1.1, F2, F2 + 2.7, "flat"))
	else:
		opens.append(CourthouseKit.opening(0.0, 1.9, F2, F2 + 2.6, "flat"))
	# The whole wall is one thickness here; its face to the wing is the
	# wing's rooms' wall below the wing's roof.
	k.wall("wall", f, -MX + SKIN, MX - SKIN, 0.0, BAND, T, inner, opens, 4.5)
	if e < 0.0:
		# Behind the bench, a round-headed niche into the courtroom side.
		var niche := CourthouseKit.opening(0.0, 2.6, F2 + 0.7, F2 + 2.8, "round")
		k.wall("wall", f, -MX + SKIN, MX - SKIN, BAND, WING_ROOF, 0.15, inner, opens, 10.0)
		k.wall("wall", f * Transform3D(Basis(), Vector3(0, 0, -0.15)), -MX + SKIN, MX - SKIN, BAND, WING_ROOF, T - 0.15, inner,
			opens + [niche], 10.0)
	else:
		k.wall("wall", f, -MX + SKIN, MX - SKIN, BAND, WING_ROOF, T, inner, opens, 10.0)
	# Above the wing's roof: brick to the weather, plaster to the courtroom.
	k.wall("wall", f, -MX + SKIN, MX - SKIN, WING_ROOF, MAIN_WALL, SKIN, brick, [], 0.0)
	k.wall("wall", f * Transform3D(Basis(), Vector3(0, 0, -SKIN)), -MX + T, MX - T, WING_ROOF, EAVE - 0.9, T - SKIN, inner, [], 0.0)
	# Where the main block stands wider than the wing, its corners are
	# brick outside, face to the weather.
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(s * (MX + WX) / 2.0, WING_ROOF / 2.0, 0.005), Vector3(MX - WX, WING_ROOF, 0.01), brick)
	k.cornice(f, -MX - 0.7, MX + 0.7, EAVE, 0.7, trim, 1.4)


## A flight of stone steps down from a door: centre u, run out from
## the face, from ground y0 to the floor y1, w wide; a ramp for the feet.
func _steps(f: Transform3D, u: float, run: float, y0: float, y1: float, w: float) -> void:
	var n := int(round((y1 - y0) / 0.17))
	var stone := c(GRANITE, CourthouseKit.K_STONE)
	var tread := run / n
	for j in n:
		var top := y1 - (y1 - y0) * j / n
		var z0 := tread * j
		k.box("wall", f, Vector3(u, (y0 + top) / 2.0, z0 + tread / 2.0 + 0.02), Vector3(w, top - y0, tread + 0.04), stone)
	k.ramp(f, Vector3(u, y0, run + 0.05), Vector3(u, y1, 0.0), w)
	for s: float in [-1.0, 1.0]:
		k.railing(f, Vector3(u + s * (w / 2.0 - 0.05), y0 + 0.05, run - 0.1), Vector3(u + s * (w / 2.0 - 0.05), y1 + 0.05, 0.1),
			0.85, IRON, 0.5)


## ---- the porches -------------------------------------------------------

## The porch before the pavilion on side s: a stone base at the floor,
## steps across its middle, wooden posts on plinths carrying three
## arches in front and one each side, a bracketed entablature, a slate
## mansard and an iron cresting round its top.
func _porch(s: float) -> void:
	var f := face(Vector3(s, 0, 0), Vector3(s * PX, 0, 0))
	var depth := 3.6
	var half := 4.4
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var stone := c(GRANITE, CourthouseKit.K_STONE)
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	# The base: brick under a stone edge, the floor boards on it.
	for side: float in [-1.0, 1.0]:
		k.block("wall", f, Vector3(side * (half - 1.1), (F1 - 0.1) / 2.0, depth / 2.0), Vector3(2.2, F1 - 0.1, depth), brick)
	k.block("wall", f, Vector3(0, (F1 - 0.1) / 2.0, depth / 2.0 - 0.6), Vector3(2.0 * half - 4.4, F1 - 0.1, depth - 1.2), brick)
	k.box("wall", f, Vector3(0, F1 - 0.05, depth / 2.0 + 0.03), Vector3(2.0 * half + 0.1, 0.1, depth + 0.06), stone)
	k.box("wall", f, Vector3(0, F1 + 0.005, depth / 2.0), Vector3(2.0 * half - 0.1, 0.02, depth - 0.1), c(PORCH_FLOOR, CourthouseKit.K_PAINT))
	k.solid(f, Vector3(0, F1 - 0.1, depth / 2.0), Vector3(2.0 * half, 0.2, depth))
	_steps(f * Transform3D(Basis(), Vector3(0, 0, depth)), 0.0, 2.6, 0.0, F1, 4.0)
	# Posts: four across the front, one at each back corner against the wall.
	var posts: Array[Vector2] = []
	for u: float in [-half + 0.2, -1.42, 1.42, half - 0.2]:
		posts.append(Vector2(u, depth - 0.2))
	for u: float in [-half + 0.2, half - 0.2]:
		posts.append(Vector2(u, 0.2))
	var top := 5.3
	for p: Vector2 in posts:
		# Plinth, then a slender turned shaft, then a capital block.
		k.block("wall", f, Vector3(p.x, F1 + 0.45, p.y), Vector3(0.42, 0.9, 0.42), trim)
		k.box("wall", f, Vector3(p.x, F1 + 0.93, p.y), Vector3(0.48, 0.06, 0.48), trim)
		k.m.cylinder("wall", f * Transform3D(Basis(), Vector3(p.x, (F1 + 0.96 + top - 0.3) / 2.0, p.y)), 0.13, 0.11,
			top - 0.3 - F1 - 0.96, 10, trim)
		for ring: float in [F1 + 1.15, top - 0.45]:
			k.m.cylinder("wall", f * Transform3D(Basis(), Vector3(p.x, ring, p.y)), 0.16, 0.16, 0.06, 10, trim)
		k.box("wall", f, Vector3(p.x, top - 0.15, p.y), Vector3(0.36, 0.3, 0.36), trim)
		k.solid(f, Vector3(p.x, F1 + 1.5, p.y), Vector3(0.3, 3.0, 0.3))
	# The arches: front spans between the posts, one each side.
	var spans: Array = [[Vector2(-half + 0.2, depth - 0.2), Vector2(-1.42, depth - 0.2)],
		[Vector2(-1.42, depth - 0.2), Vector2(1.42, depth - 0.2)],
		[Vector2(1.42, depth - 0.2), Vector2(half - 0.2, depth - 0.2)],
		[Vector2(-half + 0.2, 0.2), Vector2(-half + 0.2, depth - 0.2)],
		[Vector2(half - 0.2, 0.2), Vector2(half - 0.2, depth - 0.2)]]
	for sp: Array in spans:
		_porch_arch(f, sp[0], sp[1], top, trim)
	# Entablature: frieze and cornice with brackets round three sides.
	var ent := 5.9
	for side: Array in [[Vector3(0, 0, depth), 0.0, 2.0 * half], [Vector3(-half, 0, depth / 2.0), -PI / 2.0, depth],
			[Vector3(half, 0, depth / 2.0), PI / 2.0, depth]]:
		var sf := f * Transform3D(Basis(Vector3.UP, float(side[1])), side[0] as Vector3)
		k.cornice(sf, -float(side[2]) / 2.0 - 0.3, float(side[2]) / 2.0 + 0.3, ent, 0.35, trim, 0.9, 0.32, 0.3, false)
		k.box("wall", sf, Vector3(0, top + 0.12, -0.05), Vector3(float(side[2]) + 0.1, 0.24, 0.22), trim)
	# The ceiling of beaded boards.
	k.box("wall", f, Vector3(0, top + 0.26, depth / 2.0), Vector3(2.0 * half, 0.04, depth), c(Color(0.88, 0.86, 0.77), CourthouseKit.K_BEAD))
	# The slate mansard, its flat top, the cresting.
	var lo := Vector2(-half - 0.35, -0.05)
	var hi := Vector2(half + 0.35, depth + 0.35)
	# Worked in the porch frame, u along and z out; open to the wall.
	k.curb(f, lo, hi, ent + 0.02, ent + 0.78, 0.42, c(SLATE, CourthouseKit.K_SLATE), Vector2(0, -1))
	k.box("wall", f, Vector3(0, ent + 0.8, (depth - 0.1) / 2.0), Vector3(2.0 * half, 0.06, depth - 0.2), c(Color(0.3, 0.3, 0.3), CourthouseKit.K_TAR))
	var rail_y := ent + 0.83
	k.railing(f, Vector3(-half + 0.05, rail_y, depth - 0.1), Vector3(half - 0.05, rail_y, depth - 0.1), 0.8, IRON)
	for side: float in [-1.0, 1.0]:
		k.railing(f, Vector3(side * (half - 0.05), rail_y, 0.1), Vector3(side * (half - 0.05), rail_y, depth - 0.1), 0.8, IRON)
	# A lantern hanging in the middle bay.
	k.m.bar("iron", f * Vector3(0, top + 0.26, depth / 2.0), f * Vector3(0, top - 0.3, depth / 2.0), 0.012, 4, IRON)
	k.m.cylinder("lamp", f * Transform3D(Basis(), Vector3(0, top - 0.5, depth / 2.0)), 0.14, 0.18, 0.35, 8, Color(1, 1, 1))
	k.m.cylinder("iron", f * Transform3D(Basis(), Vector3(0, top - 0.3, depth / 2.0)), 0.2, 0.05, 0.1, 8, IRON)
	_light(f * Vector3(0, top - 0.6, depth / 2.0), 2.0, 9.0, false, false)


## One porch arch between two post tops a and b (in the porch frame's
## u, out): a round-topped band of trim on scroll brackets, a pendant
## drop at each end, the spandrels open fretwork.
func _porch_arch(f: Transform3D, a: Vector2, b: Vector2, top: float, trim: Color) -> void:
	var along := Vector2(b.x - a.x, b.y - a.y)
	var span := along.length() - 0.36
	var yaw := atan2(-along.y, along.x)
	var mid := (a + b) / 2.0
	var af := f * Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0, mid.y))
	var rise := minf(span / 2.0, 0.75)
	var spring := top - 0.3 - rise
	var o := CourthouseKit.opening(0.0, span, spring - 1.0, spring, "segment", rise)
	var circ := CourthouseKit.head_circle(o)
	var a0 := atan2(spring - circ.y, -span / 2.0)
	var a1 := atan2(spring - circ.y, span / 2.0)
	k.arc_band("wall", af, circ, a1, a0, 0.1, 0.14, 0.07, trim, 12)
	# The spandrel over the arch: a thin board to the beam.
	var pts := CourthouseKit.head_points(o, 12)
	var nf := (af.basis * Vector3(0, 0, 1)).normalized()
	for j in pts.size() - 1:
		for side: float in [0.02, -0.02]:
			k.m.quad("wall", af * Vector3(pts[j].x, pts[j].y + 0.1, side), af * Vector3(pts[j + 1].x, pts[j + 1].y + 0.1, side),
				af * Vector3(pts[j + 1].x, top - 0.02, side), af * Vector3(pts[j].x, top - 0.02, side), nf * signf(side), trim)
	# Scroll brackets at the springs and a turned drop.
	for side: float in [-1.0, 1.0]:
		var x := side * span / 2.0
		k.box("wall", af, Vector3(x - side * 0.12, spring + 0.05, 0), Vector3(0.24, 0.5, 0.08), trim)
		k.m.cylinder("wall", af * Transform3D(Basis(), Vector3(x - side * 0.05, spring - 0.28, 0)), 0.05, 0.02, 0.22, 6, trim)
	# Pierced roundels in the spandrels.
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * span * 0.33, top - 0.22, 0.03)
		k.m.cylinder("wall", af * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), p), 0.09, 0.09, 0.02, 10, Color(0.2, 0.2, 0.2, 0.0))


## ---- chimneys, roofs, cupola ----------------------------------------------

## The two chimneys at the main block's end e, out of the hip near the
## eave: a white collar at the cornice, a corbelled cap, an arched hood.
func _chimneys(e: float) -> void:
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var g := Transform3D()
	for s: float in [-1.0, 1.0]:
		var x := s * 5.0
		var z := e * (MZ - 0.45)
		var top := 19.3
		k.box("wall", g, Vector3(x, (13.5 + top) / 2.0, z), Vector3(1.1, top - 13.5, 0.8), brick)
		k.box("wall", g, Vector3(x, 17.25, z), Vector3(1.26, 0.5, 0.96), trim)
		k.box("wall", g, Vector3(x, 17.56, z), Vector3(1.34, 0.12, 1.04), trim)
		k.box("wall", g, Vector3(x, top + 0.07, z), Vector3(1.3, 0.14, 1.0), brick)
		k.box("wall", g, Vector3(x, top + 0.24, z), Vector3(1.42, 0.2, 1.12), brick)
		# The hood: two piers and a round top over the flue.
		for side: float in [-1.0, 1.0]:
			k.box("wall", g, Vector3(x + side * 0.42, top + 0.62, z), Vector3(0.26, 0.56, 0.8), brick)
		k.m.cylinder("wall", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(x, top + 0.9, z)), 0.55, 0.55, 0.8, 12, brick)


## The slate hip over the main block, the gable of each pediment back
## into it, the wings' flat roofs behind their parapets.
func _roofs() -> void:
	var slate := c(SLATE, CourthouseKit.K_SLATE)
	var g := Transform3D()
	k.hip(g, -MX - 0.7, MX + 0.7, -MZ - 0.7, MZ + 0.7, EAVE, ROOF_SLOPE, slate)
	for s: float in [-1.0, 1.0]:
		# A prism along x: the gable's triangle faces out along x.
		var hw := PZ + 0.55
		var run := 6.0
		var x0 := s * (PX - 0.02)
		var x1 := s * (PX - run)
		var ridge := EAVE + PED_RISE + 0.2
		var a := Vector3(x0, EAVE, -hw)
		var b := Vector3(x0, ridge, 0)
		var cc := Vector3(x0, EAVE, hw)
		var a1 := Vector3(x1, EAVE, -hw)
		var b1 := Vector3(x1, ridge, 0)
		var c1 := Vector3(x1, EAVE, hw)
		k._roof_quad(g, a, b, b1, a1, slate)
		k._roof_quad(g, cc, b, b1, c1, slate)
	var tar := c(Color(0.32, 0.32, 0.31), CourthouseKit.K_TAR)
	for e: float in [-1.0, 1.0]:
		k.box("wall", g, Vector3(0, WING_ROOF + 0.06, e * (MZ + WZ) / 2.0), Vector3(2.0 * WX - 0.3, 0.12, WZ - MZ - 0.3), tar)


## The cupola over the crossing of the roof, square in plan, from the
## roof up: a broad plinth that splays in to the first stage; the first
## stage with a pair of small segmental windows on each face; a sill
## course; the main stage, each face between a rusticated corner and a
## fluted pilaster at either side with the round-arched louvred vent in
## the middle; the entablature breaking out over the pilasters; a low
## pediment on each face, an urn finial on a pedestal over each
## pilaster; the bell roof, straight-sided at first and closing to a
## point, in slate with a light band and a lozenge on each face; a clock
## in a round-hooded dormer on each face; the finial and the vane.
func _cupola() -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var dark := c(TRIM.darkened(0.3), CourthouseKit.K_PAINT)
	var slate := c(SLATE.darkened(0.1), CourthouseKit.K_SLATE)
	var g := Transform3D()
	var base0 := 17.4     # the plinth, from inside the roof
	var base1 := 19.6     # its top, where the splay begins
	var s0 := 20.3        # the first stage
	var s1 := 22.55       # the sill course
	var m0 := 22.9        # the main stage
	var m1 := 26.7        # the entablature
	var e1 := 27.6        # the cornice's top
	var half := 2.7       # the main stage's half width at its corners
	var core := 2.45      # its wall between the pilasters
	k.box("wall", g, Vector3(0, (base0 + base1) / 2.0, 0), Vector3(6.6, base1 - base0, 6.6), trim)
	k.box("wall", g, Vector3(0, base1 + 0.06, 0), Vector3(6.75, 0.12, 6.75), trim)
	k.curb(g, Vector2(-3.3, -3.3), Vector2(3.3, 3.3), base1 + 0.12, s0 - 0.05, 0.65, trim)
	k.box("wall", g, Vector3(0, (s0 + s1) / 2.0, 0), Vector3(2.0 * core, s1 - s0, 2.0 * core), trim)
	k.box("wall", g, Vector3(0, s1 + 0.1, 0), Vector3(2.0 * half + 0.3, 0.2, 2.0 * half + 0.3), trim)
	k.box("wall", g, Vector3(0, s1 + 0.27, 0), Vector3(2.0 * half + 0.15, 0.14, 2.0 * half + 0.15), trim)
	k.box("wall", g, Vector3(0, (m0 + m1) / 2.0, 0), Vector3(2.0 * core, m1 - m0, 2.0 * core), trim)
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var f := face(dir, dir * core)
		# The first stage: blocks under the corners and pilasters, the pair
		# of windows between them.
		for side: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(side * (half - 0.45), (s0 + s1) / 2.0, 0.1), Vector3(0.9, s1 - s0, 0.2), trim)
			k.box("wall", f, Vector3(side * (half - 0.45), s0 + 0.12, 0.14), Vector3(0.98, 0.24, 0.28), trim)
		for u: float in [-0.66, 0.66]:
			var o := CourthouseKit.opening(u, 0.86, 20.75, 21.7, "segment", 0.14)
			k.glass(f, o, 0.005, c(Color(0.07, 0.07, 0.08), CourthouseKit.K_PAINT), "wall")
			k.sash(f, o, 0.04, trim, 21.22, 1, false)
			k.hood(f, o, trim, 0.1, false, true, true)
		# The main stage: at each side a rusticated corner and a fluted
		# pilaster, bases on the sill course and capitals under the
		# entablature.
		for side: float in [-1.0, 1.0]:
			var ru := side * (half - 0.175)
			var row := m0
			while row < m1 - 0.1:
				k.box("wall", f, Vector3(ru, row + 0.17, 0.125), Vector3(0.35, 0.32, 0.25), trim)
				row += 0.38
			var fu := side * (half - 0.35 - 0.28)
			k.box("wall", f, Vector3(fu, (m0 + m1) / 2.0, 0.075), Vector3(0.52, m1 - m0, 0.15), trim)
			for fl in 5:
				k.box("wall", f, Vector3(fu - 0.18 + fl * 0.09, (m0 + m1) / 2.0, 0.151), Vector3(0.035, m1 - m0 - 0.7, 0.004), dark)
			k.box("wall", f, Vector3(fu, m0 + 0.12, 0.1), Vector3(0.62, 0.24, 0.2), trim)
			k.box("wall", f, Vector3(fu, m1 - 0.2, 0.1), Vector3(0.62, 0.3, 0.2), trim)
			k.box("wall", f, Vector3(fu, m1 - 0.4, 0.12), Vector3(0.56, 0.08, 0.24), trim)
		# The louvred vent in its arch, a keystone up to the architrave.
		var vent := CourthouseKit.opening(0.0, 1.3, 23.25, 25.5, "round")
		k.glass(f, vent, 0.005, c(Color(0.05, 0.05, 0.05), CourthouseKit.K_PAINT), "wall")
		var slat := 23.37
		while slat < 25.5:
			k.m.box("wall", f * Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3(0, slat, 0.04)), Vector3(1.24, 0.16, 0.02), trim)
			slat += 0.14
		k.box("wall", f, Vector3(0, (23.25 + 25.5) / 2.0, -0.01), Vector3(1.3, 25.5 - 23.25, 0.02), c(Color(0.05, 0.05, 0.05), CourthouseKit.K_PAINT))
		# The fan over the louvres: a solid panel in the arch.
		k.glass(f, CourthouseKit.opening(0.0, 1.3, 25.5 - 0.001, 25.5, "round"), 0.03, trim, "wall")
		k.box("wall", f, Vector3(0, 25.5, 0.05), Vector3(1.3, 0.08, 0.06), trim)
		_arched_trim(f, vent, trim, false)
		k.box("wall", f, Vector3(0, 26.45, 0.1), Vector3(0.36, 0.5, 0.2), trim)
		# The entablature, broken out over the pilasters.
		k.box("wall", f, Vector3(0, m1 + 0.1, 0.1), Vector3(2.0 * half, 0.2, 0.2), trim)
		k.box("wall", f, Vector3(0, m1 + 0.38, 0.12), Vector3(2.0 * half, 0.36, 0.24), trim)
		for side: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(side * (half - 0.45), m1 + 0.38, 0.22), Vector3(0.95, 0.36, 0.44), trim)
			for bk: float in [-0.25, 0.0, 0.25]:
				k.box("wall", f, Vector3(side * (half - 0.45) + bk, m1 + 0.47, 0.45), Vector3(0.08, 0.16, 0.08), trim)
		k.box("wall", f, Vector3(0, e1 - 0.15, 0.3), Vector3(2.0 * half + 0.5, 0.18, 0.6), trim)
		k.box("wall", f, Vector3(0, e1 - 0.03, 0.34), Vector3(2.0 * half + 0.6, 0.08, 0.68), trim)
		# The low pediment between the finials.
		k.pediment(f, Vector3(0, e1, 0.3), 3.6, 0.7, 0.3, trim, trim, 0.25)
		# An urn finial on a pedestal over each pilaster.
		for side: float in [-1.0, 1.0]:
			var p := Vector3(side * 2.0, e1, 0.3)
			k.box("wall", f, p + Vector3(0, 0.28, 0), Vector3(0.4, 0.56, 0.4), trim)
			k.box("wall", f, p + Vector3(0, 0.59, 0), Vector3(0.46, 0.06, 0.46), trim)
			k.m.cylinder("wall", f * Transform3D(Basis(), p + Vector3(0, 0.7, 0)), 0.1, 0.16, 0.16, 10, trim)
			k.m.sphere("wall", f * Transform3D(Basis().scaled(Vector3(1.0, 1.3, 1.0)), p + Vector3(0, 0.9, 0)), 0.17, 10, trim)
			k.m.cylinder("wall", f * Transform3D(Basis(), p + Vector3(0, 1.12, 0)), 0.05, 0.09, 0.1, 8, trim)
			k.m.cylinder("wall", f * Transform3D(Basis(), p + Vector3(0, 1.55, 0)), 0.06, 0.0, 0.76, 8, trim)
		# The clock in its dormer, out of the bell roof.
		_clock_dormer(face(dir, dir * 2.6), e1)
	# The bell roof, and the finial and vane at its point.
	var eave := e1 + 0.3
	var tip := 35.0
	_dome(Vector3(0, eave, 0), 2.42, tip - eave, slate)
	k.m.cylinder("wall", g * Transform3D(Basis(), Vector3(0, tip - 0.05, 0)), 0.3, 0.16, 0.3, 10, trim)
	k.m.cylinder("wall", g * Transform3D(Basis(), Vector3(0, tip + 0.2, 0)), 0.14, 0.2, 0.2, 10, trim)
	k.m.sphere("wall", g * Transform3D(Basis(), Vector3(0, tip + 0.45, 0)), 0.17, 10, trim)
	k.m.cylinder("wall", g * Transform3D(Basis(), Vector3(0, tip + 0.68, 0)), 0.03, 0.09, 0.14, 8, trim)
	k.m.bar("iron", Vector3(0, tip + 0.7, 0), Vector3(0, tip + 2.8, 0), 0.03, 6, IRON)
	k.m.sphere("iron", Transform3D(Basis(), Vector3(0, tip + 1.0, 0)), 0.08, 8, IRON)
	# The cross, the compass arms, the arrow.
	k.m.bar("iron", Vector3(0, tip + 1.3, -0.22), Vector3(0, tip + 1.3, 0.22), 0.03, 6, IRON)
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		k.m.bar("iron", Vector3(0, tip + 1.6, 0), dir * 0.6 + Vector3(0, tip + 1.6, 0), 0.015, 4, IRON)
	var letters := {"N": Vector3(0, 0, -1), "S": Vector3(0, 0, 1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}
	for l: String in letters:
		var d: Vector3 = letters[l]
		var lb := Label3D.new()
		lb.text = l
		lb.font_size = 96
		lb.pixel_size = 0.0035
		lb.modulate = Color(0.05, 0.05, 0.05)
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lb.position = d * 0.66 + Vector3(0, tip + 1.6, 0)
		add_child(lb)
	k.m.bar("iron", Vector3(-0.7, tip + 2.25, 0), Vector3(0.7, tip + 2.25, 0), 0.02, 4, IRON)
	k.box("iron", g, Vector3(0.75, tip + 2.25, 0), Vector3(0.2, 0.2, 0.02), IRON)
	k.box("iron", g, Vector3(-0.65, tip + 2.25, 0), Vector3(0.3, 0.34, 0.02), IRON)
	k.m.sphere("iron", Transform3D(Basis(), Vector3(0, tip + 2.8, 0)), 0.06, 8, IRON)


## The bell roof over a square of half side a from c, h high: each side
## rises almost upright and rounds over to the point, s(t) = (1 - t^2.2)^0.8; its
## slates dark with a band of pale ones and a lozenge on each face.
func _dome(cen: Vector3, a: float, h: float, slate: Color) -> void:
	var pale := c(Color(0.47, 0.41, 0.41), CourthouseKit.K_SLATE)
	var rings := 18
	var prev: Array[Vector3] = []
	for j in rings + 1:
		var t := float(j) / rings
		var s := pow(maxf(1.0 - pow(t, 2.2), 0.0), 0.8)
		var y := cen.y + h * t
		var ring: Array[Vector3] = [Vector3(cen.x - a * s, y, cen.z - a * s), Vector3(cen.x + a * s, y, cen.z - a * s),
			Vector3(cen.x + a * s, y, cen.z + a * s), Vector3(cen.x - a * s, y, cen.z + a * s)]
		if not prev.is_empty():
			var mid_t := (j - 0.5) / rings
			var col := pale if mid_t > 0.74 and mid_t < 0.8 else slate
			for q in 4:
				var p0 := prev[q]
				var p1 := prev[(q + 1) % 4]
				var p2 := ring[(q + 1) % 4]
				var p3 := ring[q]
				var m := (p0 + p1 + p2 + p3) / 4.0
				var out := Vector3(m.x - cen.x, 0.0, m.z - cen.z)
				var n := (p1 - p0).cross(p3 - p0).normalized()
				if n.dot(out) < 0.0:
					n = -n
				if j == rings:
					k.m.tri("wall", p0, p1, p2, n, col)
				else:
					k.m.quad("wall", p0, p1, p2, p3, n, col)
		prev = ring
	# The lozenges: four pale diamonds in a diamond on each face, laid on
	# the slope.
	var t := 0.58
	var s := pow(1.0 - pow(t, 2.2), 0.8)
	var slope := 0.8 * pow(1.0 - pow(t, 2.2), -0.2) * 2.2 * pow(t, 1.2) * a / h
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var f := face(dir, cen + dir * (a * s + 0.02) + Vector3(0, h * t, 0)) * Transform3D(Basis(Vector3.RIGHT, -atan(slope)), Vector3.ZERO)
		for p: Vector2 in [Vector2(0, 0.3), Vector2(0, -0.3), Vector2(0.3, 0), Vector2(-0.3, 0)]:
			k.box_rz("wall", f, Vector3(p.x, p.y, 0.0), Vector3(0.28, 0.28, 0.02), PI / 4.0, pale)


## A clock dormer on a cupola face f (its face plane at the frame's
## origin), rising from behind the pediment at y0: pilaster strips up
## its sides, a round hood with a spike over it, the dial in the arch,
## a panel under the dial.
func _clock_dormer(f: Transform3D, y0: float) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var w := 2.7
	var r := w / 2.0
	var spring := 30.45
	var cy := 30.4
	# The body back into the roof, square below the spring, round above.
	k.box("wall", f, Vector3(0, (y0 + spring) / 2.0, -0.7), Vector3(w, spring - y0, 1.4), trim)
	var o := CourthouseKit.opening(0.0, w, spring - 0.01, spring, "round")
	k.glass(f, o, 0.0, trim, "wall")
	var circ := CourthouseKit.head_circle(o)
	for z: float in [-0.35, -0.7, -1.05, -1.4]:
		k.glass(f * Transform3D(Basis(), Vector3(0, 0, z)), o, 0.0, trim, "wall")
	k.arc_band("wall", f, circ, 0.0, PI, 0.22, 1.5, 0.12, trim, 16)
	k.arc_band("wall", f, Vector3(circ.x, circ.y, circ.z + 0.22), 0.0, PI, 0.08, 1.4, 0.16, trim, 16)
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(s * (r - 0.12), (y0 + spring) / 2.0, 0.06), Vector3(0.24, spring - y0, 0.12), trim)
		k.box("wall", f, Vector3(s * (r - 0.12), spring - 0.08, 0.1), Vector3(0.32, 0.16, 0.2), trim)
	# The spike over the hood.
	k.m.cylinder("wall", f * Transform3D(Basis(), Vector3(0, spring + r + 0.3, 0.05)), 0.09, 0.14, 0.14, 8, trim)
	k.m.cylinder("wall", f * Transform3D(Basis(), Vector3(0, spring + r + 0.75, 0.05)), 0.06, 0.0, 0.8, 8, trim)
	# A panel under the dial.
	k.box("wall", f, Vector3(0, y0 + 0.75, 0.03), Vector3(1.2, 0.5, 0.06), trim)
	# The dial: a white face in a black ring, the hours in numerals, the
	# minutes marked round its edge.
	var dr := 0.86
	var df := f * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, cy, 0.1))
	k.m.cylinder("iron", df, dr + 0.08, dr + 0.08, 0.06, 40, IRON)
	k.m.cylinder("dial", df * Transform3D(Basis(), Vector3(0, 0.035, 0)), dr, dr, 0.02, 40, Color(1, 1, 1))
	for mk in 60:
		var a := TAU * mk / 60.0
		var long := mk % 5 == 0
		var p := Vector3(sin(a) * (dr - 0.07), cy + cos(a) * (dr - 0.07), 0.148)
		k.box_rz("iron", f, p, Vector3(0.03 if long else 0.012, 0.1 if long else 0.05, 0.004), -a, IRON)
	for h in 12:
		var a := TAU * h / 12.0
		var num := Label3D.new()
		num.text = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"][h]
		num.font_size = 44
		num.pixel_size = 0.0042
		num.modulate = Color(0.03, 0.03, 0.03)
		num.shaded = true
		num.double_sided = false
		num.transform = f * Transform3D(Basis(Vector3.BACK, -a), Vector3(sin(a) * 0.62, cy + cos(a) * 0.62, 0.152))
		add_child(num)
	_hands(f * Transform3D(Basis(), Vector3(0, cy, 0.16)), dr)


## A clock's hour and minute hands on a dial whose face is xf (+z out).
func _hands(xf: Transform3D, dial := 0.72) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03)
	mat.roughness = 0.5
	var pair: Array = []
	var sc := dial / 0.72
	for spec: Array in [[0.4 * sc, 0.06 * sc], [0.6 * sc, 0.035 * sc]]:
		var pivot := Node3D.new()
		pivot.transform = xf * Transform3D(Basis(), Vector3(0, 0, 0.012 * pair.size()))
		var piece := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(float(spec[1]), float(spec[0]) + 0.1, 0.012)
		bm.material = mat
		piece.mesh = bm
		piece.position = Vector3(0, float(spec[0]) / 2.0 - 0.05, 0)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(piece)
		add_child(pivot)
		pivot.set_meta("xf", pivot.transform)
		pair.append(pivot)
	clock_hands.append(pair)


## The clocks to the hour (0 to 24).
func set_clock(hours: float) -> void:
	for pair: Array in clock_hands:
		var hour := pair[0] as Node3D
		var minute := pair[1] as Node3D
		hour.transform = (hour.get_meta("xf") as Transform3D) * Transform3D(Basis(Vector3.BACK, -TAU * fmod(hours, 12.0) / 12.0), Vector3.ZERO)
		minute.transform = (minute.get_meta("xf") as Transform3D) * Transform3D(Basis(Vector3.BACK, -TAU * fmod(hours, 1.0)), Vector3.ZERO)


## How dark it is, 0 day to 1 night: the dials glow after dark. The
## lamps inside burn all day, as in a building at work, and brighter at
## night.
func set_darkness(dark: float) -> void:
	var on := smoothstep(0.35, 0.6, dark)
	dial_mat.emission_energy_multiplier = 1.4 * on
	lamp_mat.emission_energy_multiplier = 1.5 + 1.5 * on
	for l: Dictionary in lights:
		var light := l["light"] as OmniLight3D
		var indoor := bool(l.get("indoor", true))
		var level := on if not indoor else lerpf(0.55, 1.0, on)
		light.visible = level > 0.01
		light.light_energy = float(l["energy"]) * level


## A lamp's light at p, reaching range; off by day.
func _light(p: Vector3, energy: float, reach: float, shadow := false, indoor := true) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.omni_range = reach
	light.light_color = Color(1.0, 0.84, 0.62)
	light.light_energy = energy
	light.shadow_enabled = shadow
	light.visible = false
	add_child(light)
	lights.append({"light": light, "energy": energy, "indoor": indoor})
