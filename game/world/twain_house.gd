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
const EAVE := 24.3          # a reference height for the towers' roofs
const TOP := 43.3           # the main roof's ridge
const RIDGE_Z := 47.4       # where it runs (survey z)
const DECK_X := 64.3        # the Texas deck's well: its north wall (survey x)
const DECK_Z0 := 55.8       # and its west wall (survey z)
const WEST_EAVE := 28.0     # the long west roof's eave, a foot out from the wall
const WEST_PITCH := 1.515   # its rise per foot, from that eave to the ridge
const DECK := 35.9          # the flat deck east of the ridge
const GROUND := -11.0       # the foot of the walls: the basement's floor
# The main walls' tops, side by side, from the survey's elevations and
# section: the west front carries the third floor's wall to 26.3 ft; the
# east is hidden behind its gables at the second floor's ceiling; the
# north and the south stop lower under the roof's lower slopes.
const WEST_TOP := 26.3
const EAST_TOP := 24.0
const NORTH_TOP := 19.5
const SOUTH_TOP := 21.3
const WING_TOP := 17.2      # the service wing's walls, under its cornice
const WING_RING := 17.7     # the flat top of the wing's cornice, where its roof starts
const WING_RIDGE := 31.5    # the wing's ridge
const WING_OUT := 1.8       # the cornice's reach
const BAY_TOP := 13.7       # the drawing room's bay: its porch over it
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
## What the audit (world/twain_audit.gd) checks the model against: the
## rooms {name, poly (survey plan), y0, y1 (feet; y1 < 0 up to the roof)},
## the furniture {name, xf (world, the box's middle), size, kind: "floor"
## or "wall"}, the doorways {center, normal, width, outside}; and, when
## FLOWSTATE_TW_AUDIT is set, the meshes as built {outer, inner,
## furniture}.
var rooms: Array[Dictionary] = []
var items: Array[Dictionary] = []
var doors: Array[Dictionary] = []
var meshes: Dictionary = {}
var dressed: Array[Dictionary] = []
## Every railing as built: [from, to] (world, at the foot of the rail).
var rails: Array = []
## The dressing of the openings (sashes, glass, casings, hoods, door
## leaves), apart from the walls so the audit can look through a hole.
var dress_m := TownMesh.new()
var _dressed_ids := {}


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
	TwainInterior.build(self)
	var inner := k.m
	k.m = TownMesh.new()
	TwainInterior.furnish()
	var furniture := k.m
	k.m = outer
	if OS.get_environment("FLOWSTATE_TW_AUDIT") != "":
		meshes = {"outer": outer, "inner": inner, "furniture": furniture, "dress": dress_m}
	var mats := {"wall": wall_mat, "glass": glass_mat, "iron": iron_mat, "lamp": lamp_mat, "stencil": stencil_mat,
		"flame": flame_mat}
	var drawn: Array = outer.commit(self, mats, ["wall", "iron"]).values()
	var dress_node := Node3D.new()
	dress_node.name = "Dressing"
	add_child(dress_node)
	drawn.append_array(dress_m.commit(dress_node, mats, ["wall"]).values())
	for tm: TownMesh in [inner, furniture]:
		for mi: MeshInstance3D in tm.commit(self, mats, []).values():
			mi.visibility_range_end = 120.0
			drawn.append(mi)
	for mi: MeshInstance3D in drawn:
		if mi.name.ends_with("glass"):
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	stats = {"triangles": outer.triangles + inner.triangles + furniture.triangles, "inside": inner.triangles + furniture.triangles,
		"solids": k.solid_count,
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
	ops.append({"at": Vector2(sx, sz), "w": wd, "sill": sill, "head": head, "kind": kind, "shape": shape, "hood": hood,
		"id": ops.size()})


## The windows and doors, read off the survey's plans and elevations. A
## first-floor window stands about 3.8 to 11.3 ft, a second-floor one
## 15.8 to 21.6. Heights are over the first floor, the survey's 0'-0".
func _openings() -> void:
	# The library's alcove, west, and the school room over it.
	_op(73.2, 29.7, 3.6, 3.0, 11.3)
	_op(68.5, 31.65, 2.4, 3.8, 11.3)
	_op(77.9, 31.65, 2.4, 3.8, 11.3)
	_op(73.2, 29.7, 3.4, 15.8, 21.5)
	_op(68.5, 31.65, 2.2, 15.8, 21.5)
	_op(77.9, 31.65, 2.2, 15.8, 21.5)
	# The alcove's deck: a door and two windows in the wall behind it.
	_op(73.2, MZ0, 2.6, F3 + 0.3, 31.3, "door", "flat", false)
	_op(69.6, MZ0, 2.0, 27.3, 31.3, "win", "flat", false)
	_op(76.8, MZ0, 2.0, 27.3, 31.3, "win", "flat", false)
	# The west front: the dining room; upstairs the Langdon room, the bath.
	_op(92.65, MZ0, 3.4, 2.3, 10.4)
	# The dining room's door to the butler's pantry.
	_op(107.5, MZ0, 3.0, 0.0, 9.3, "open", "flat", false)
	_op(108.45, MZ0, 2.7, 15.4, 21.1)
	for x: float in [96.45, 93.7, 91.15]:
		_op(x, MZ0, 2.5, 15.4, 21.1, "win", "flat", x == 93.7)
	_op(84.05, MZ0, 2.9, 15.4, 21.1)
	# The west gable's pair of windows either side of its chimney.
	_op(106.1, MZ0, 2.2, 27.1, 30.8, "win", "flat", false)
	_op(98.6, MZ0, 2.2, 27.1, 30.8, "win", "flat", false)
	# The north front: the central gable's balcony door, the windows
	# either side of it and the fan in its peak; the two narrow windows
	# under it; on the ground floor the side door under its porch and the
	# leaded window beside it; the window east of the bay, both floors.
	_op(MX1, 48.8, 2.8, F3, 31.8, "shut", "flat", false)
	_op(MX1, 51.7, 1.5, 24.8, 29.8, "win", "flat", false)
	_op(MX1, 45.1, 1.5, 24.8, 29.8, "win", "flat", false)
	_op(MX1, 48.6, 4.4, 36.0, 40.2, "win", "round", false)
	_op(MX1, 51.75, 1.5, 17.5, 21.5)
	_op(MX1, 46.55, 1.5, 17.5, 21.5)
	_op(MX1, 46.9, 2.8, 0.0, 8.9, "door")
	_op(MX1, 49.9, 2.4, 4.5, 11.7)
	# The drawing room's bay, its three faces; the door from the Clemenses'
	# room out onto the porch over it.
	_op(121.0, 69.5, 3.4, 2.8, 10.2)
	_op(119.75, 65.25, 2.3, 2.8, 10.2)
	_op(119.75, 73.75, 2.3, 2.8, 10.2)
	_op(MX1, 69.5, 3.0, F2, 19.1, "shut", "flat", false)
	# The east front, under the veranda: the drawing room, the entrance,
	# the hall's window, the bath.
	_op(101.7, MZ1, 3.6, 2.7, 10.2)
	_op(110.8, MZ1, 3.6, 2.7, 10.2)
	_op(90.8, MZ1, 4.4, 0.0, 10.3, "door")
	_op(81.3, MZ1, 3.2, 3.8, 11.1)
	_op(68.4, MZ1, 2.6, 3.8, 13.6)
	_op(77.7, MZ1, 2.6, 3.8, 13.6)
	# Upstairs: two windows under the first gable, one under each small
	# gable, the three-part window under the second gable.
	_op(64.5, MZ1, 2.6, 15.8, 21.6)
	_op(72.6, MZ1, 2.6, 15.8, 21.6)
	_op(82.9, MZ1, 2.4, 15.8, 21.4)
	_op(92.1, MZ1, 2.4, 15.8, 21.4)
	for x: float in [103.2, 106.25, 109.3]:
		_op(x, MZ1, 2.6, 14.2, 20.6, "win", "flat", x == 106.25)
	# The gables' balcony doors.
	_op(68.2, MZ1, 4.0, F3, 31.3, "french", "round")
	_op(105.4, MZ1, 2.9, F3, 31.1, "french", "round")
	# The mahogany guest room's octagon: west, and the door to the ombra;
	# Clara and Jean's room over it.
	_op(48.7, 63.6, 3.6, 3.8, 11.3)
	_op(49.9, 58.1, 2.3, 3.8, 11.3)
	_op(50.0, 68.95, 3.0, 0.0, 9.8, "door")
	_op(48.7, 63.6, 3.4, 15.8, 21.5)
	_op(49.9, 58.1, 2.2, 15.8, 21.5)
	_op(50.0, 68.95, 2.2, 15.8, 21.5)
	# The octagon's deck: the door and windows in the wall behind it.
	_op(DECK_X, 64.0, 3.4, F3 + 0.5, 32.0, "french", "flat", false)
	_op(61.2, DECK_Z0, 2.6, F3 + 0.5, 31.6, "door", "flat", false)
	# The dressing room's round, and the bath over it: each at the middle of
	# a facet of the round wide enough for it.
	for a: float in [150.0, 180.0, 235.0]:
		var p := _arc_point(DRESS_C, DRESS_R, a)
		_op(p.x, p.y, 2.3, 3.8, 11.3)
	var up := _arc_point(DRESS_C, DRESS_R, 180.0)
	_op(up.x, up.y, 3.0, 15.4, 19.9)
	# The library's south wall: the opening to the conservatory; the
	# school room's three-part window over it.
	_op(MX0, 47.0, 8.0, 0.0, 11.8, "open", "segment", false)
	for z: float in [44.0, 46.9, 49.8]:
		_op(MX0, z, 2.6, 15.2, 21.4, "win", "flat", z == 46.9)
	# The butler's pantry: its windows, the door to the yard; under them
	# the basement's windows and its door.
	for a: float in [221.0, 235.0, 254.0]:
		var p := _arc_point(PANTRY_C, PANTRY_R, a)
		_op(p.x, p.y, 2.2, 2.8, 7.2, "win", "round", false)
	for a: float in [221.0, 235.0]:
		var p := _arc_point(PANTRY_C, PANTRY_R, a)
		_op(p.x, p.y, 2.0, -5.5, -2.0, "win", "segment", false)
	var d := _arc_point(PANTRY_C, PANTRY_R, 207.0)
	_op(d.x, d.y, 2.4, 0.0, 8.4, "door")
	var bd := _arc_point(PANTRY_C, PANTRY_R, 254.0)
	_op(bd.x, bd.y, 3.8, -9.1, -1.7, "shut", "flat", false)
	# The service wing: its west face (ground floor, upper floor, the
	# basement where the ground falls away), its north end, its east face
	# with the door and the windows stepping down under the back stair.
	for x: float in [150.0, 142.5]:
		_op(x, 19.8, 2.5, 2.6, 8.3)
	for x: float in [133.3, 127.7, 122.7, 117.7]:
		_op(x, 22.3, 2.5, 2.6, 8.3)
	for x: float in [149.0, 146.3, 143.6]:
		_op(x, 19.8, 2.2, 12.3, 16.1, "win", "flat", false)
	for x: float in [134.85, 132.0, 125.3, 120.1]:
		_op(x, 22.3 if x < 137.0 else 19.8, 2.1, 12.3, 16.1, "win", "flat", false)
	for x: float in [149.7, 142.8]:
		_op(x, 19.8, 2.6, -5.3, -1.3, "win", "segment", false)
	for x: float in [127.3, 123.1, 119.1]:
		_op(x, 22.3, 2.6, -5.3, -1.3, "win", "segment", false)
	# The north end: two windows below, a double window above.
	for z: float in [37.65, 24.6]:
		_op(155.5, z, 2.6, 2.8, 9.8)
	_op(155.5, 32.1, 7.4, 12.9, 15.9, "win", "flat", false)
	_op(149.0, 43.8, 2.4, 2.4, 8.0)
	_op(141.0, 43.8, 2.6, 0.0, 8.3, "door")
	for x: float in [144.25, 146.75, 149.25]:
		_op(x, 43.8, 2.2, 12.4, 15.8, "win", "flat", false)
	_op(137.2, 43.8, 2.0, 13.8, 18.5, "win", "flat", false)
	# Under the back stair's roof, stepping down with the stair.
	_op(127.2, 43.8, 2.0, 8.0, 13.5)
	_op(132.2, 43.8, 2.0, 5.0, 10.0)
	# The third floor: the billiard room's balcony door in the south
	# gable, the small windows of carved marble either side.
	_op(MX0, 46.9, 3.0, F3, 33.3, "french", "flat")
	_op(MX0, 46.9, 7.0, 33.5, 36.9, "win", "round", false)
	_op(MX0, 42.5, 1.8, 26.7, 30.3, "win", "flat", false)
	_op(MX0, 51.0, 1.8, 26.7, 30.3, "win", "flat", false)
	# The east slope's dormer: seven small arched windows.
	for i in 7:
		_op(80.1 + i * 2.45, 74.5, 1.6, 32.3, 34.8, "win", "round", false)


const DRESS_C := Vector2(54.8, 77.3)
const DRESS_R := 6.6
## The breaks round the rounds: each opening stands at the middle of a
## facet wide enough for it.
const DRESS_BREAKS: Array[float] = [90.0, 105.0, 120.0, 136.0, 164.0, 196.0, 221.0, 249.0, 250.0]
const PANTRY_BREAKS: Array[float] = [180.0, 200.0, 214.0, 228.0, 242.0, 246.0, 262.0, 270.0]
const PANTRY_C := Vector2(112.8, 38.3)
const PANTRY_R := 15.5
const CONS_C := Vector2(52.3, 47.0)
## The service wing's plan: from the pantry's wall round to the main
## block's north wall.
const WING_PLAN: Array[Vector2] = [Vector2(113.0, 22.3), Vector2(137.0, 22.3), Vector2(137.0, 19.8), Vector2(155.5, 19.8),
	Vector2(155.5, 43.8), Vector2(MX1, 43.8), Vector2(MX1, MZ0), Vector2(113.0, MZ0)]
const CONS_R := 8.5


## The ground against the house, (survey x, survey z, feet over the first
## floor), read off the four elevations' ground lines: level with the
## drive along the east front, falling along the south front to the west,
## a foot and a half lower along the west front, down to 8.5 ft under the
## service wing; on the north a sunken area before the side door.
const GRADE_POINTS: Array[Vector3] = [
	# south front
	Vector3(50.0, 14.0, -6.4), Vector3(50.0, 21.0, -4.7), Vector3(52.0, 28.0, -4.4), Vector3(52.0, 37.0, -4.2),
	Vector3(48.0, 42.0, -4.0), Vector3(46.0, 47.0, -3.6), Vector3(44.0, 52.0, -3.0), Vector3(46.0, 57.0, -2.3),
	Vector3(46.0, 62.0, -1.9), Vector3(46.0, 70.0, -2.2), Vector3(46.0, 80.0, -2.46),
	# west front
	Vector3(26.0, 40.0, -3.4), Vector3(37.0, 40.0, -3.7), Vector3(56.0, 36.0, -3.9), Vector3(66.0, 28.0, -3.9),
	Vector3(80.0, 28.0, -3.9), Vector3(86.0, 36.0, -4.2), Vector3(91.0, 36.0, -4.4), Vector3(96.0, 34.0, -5.3),
	Vector3(101.0, 30.0, -6.1), Vector3(107.0, 24.0, -7.3), Vector3(112.0, 20.0, -8.4), Vector3(118.0, 20.0, -8.3),
	Vector3(126.0, 20.0, -7.9), Vector3(136.0, 20.0, -7.6), Vector3(146.0, 18.0, -7.1), Vector3(154.0, 18.0, -6.8),
	# north end of the wing, the north front
	Vector3(158.0, 14.0, -8.5), Vector3(158.0, 22.0, -8.5), Vector3(158.0, 32.0, -8.1), Vector3(158.0, 43.0, -7.6),
	Vector3(118.0, 46.0, -6.4), Vector3(118.0, 55.0, -6.4), Vector3(118.0, 58.0, -2.46), Vector3(123.0, 67.0, -2.46),
	Vector3(118.0, 81.0, -2.46), Vector3(118.0, 95.0, -2.46), Vector3(118.0, 112.0, -2.46),
	# east front and the wing's east face
	Vector3(60.0, 90.0, -2.46), Vector3(90.0, 92.0, -2.46), Vector3(110.0, 90.0, -2.46), Vector3(130.0, 48.0, -2.8),
	Vector3(142.0, 48.0, -3.5), Vector3(147.0, 48.0, -4.4), Vector3(152.0, 48.0, -5.5), Vector3(160.0, 48.0, -5.8)]


## The lawn's height (feet over the first floor) at a plan point: the
## ground against the house blended by distance, and far from it the
## level of the drive and the street.
static func grade_at(q: Vector2) -> float:
	var sum := 0.0
	var wsum := 0.0
	var near := 1e9
	for p: Vector3 in GRADE_POINTS:
		var d2 := (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y)
		near = minf(near, d2)
		var wt := 1.0 / (d2 + 4.0)
		sum += wt * p.z
		wsum += wt
	# Beyond 60 ft from the house the ground eases back to the drive's level
	# by 160 ft; on the north it climbs to the side walk's level by 166 ft.
	var t := clampf((sqrt(near) - 60.0) / 100.0, 0.0, 1.0)
	var g := lerpf(sum / wsum, GRADE, t * t * (3.0 - 2.0 * t))
	return lerpf(GRADE, g, clampf((166.0 - q.x) / 6.0, 0.0, 1.0))


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
	for a: float in DRESS_BREAKS:
		p.append(_arc_point(DRESS_C, DRESS_R, a))
	p.append_array([Vector2(48.7, 66.8), Vector2(48.7, 60.4), Vector2(52.3, 55.8), Vector2(MX0, 55.8)])
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
		# A doorway's wall stops under the floor, clear of it.
		var sill := h(float(o["sill"]))
		var kind0 := str(o["kind"])
		if (kind0 == "door" or kind0 == "open" or kind0 == "french" or kind0 == "idoor" or kind0 == "ishut" or kind0 == "shut"):
			sill -= 0.03
		var op := CourthouseKit.opening(u, wd, sill, spring, shape, 0.25)
		op["kind"] = o["kind"]
		op["hood"] = o["hood"]
		op["id"] = int(o.get("id", -1))
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
	for split: float in [0.0, 14.0, 23.0]:
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
	for band: Array in [[GROUND, 0.2, STONE, CourthouseKit.K_STONE], [0.2, 0.8, BLACK, CourthouseKit.K_BRICK],
			[3.2, 3.7, BLACK, CourthouseKit.K_BRICK], [11.9, 12.4, VERMILION, CourthouseKit.K_BRICK],
			[13.9, 14.8, BLACK, CourthouseKit.K_BRICK], [22.9, 23.5, BLACK, CourthouseKit.K_BRICK]]:
		var b0 := maxf(float(band[0]), y0)
		var b1 := minf(float(band[1]), y1)
		if b1 - b0 < 0.05:
			continue
		k.wall("wall", skin, 0.0, length, h(b0), h(b1), 0.012 if int(band[3]) != CourthouseKit.K_STONE else 0.05,
			c(band[2] as Color, int(band[3])), mine, -1000.0)
	# The row of squares, set diamond-wise, missing where a window stands.
	if y0 < 15.6 and y1 > 16.2:
		var step := 0.5
		var n := int(length / step)
		for i in n:
			var u := (i + 0.5) * length / n
			var clear := true
			for o: Dictionary in mine:
				if absf(u - float(o["u"])) < float(o["w"]) / 2.0 + 0.15 and float(o["y0"]) < h(16.2):
					clear = false
			if clear:
				k.box_rz("wall", skin, Vector3(u, h(15.9), 0.006), Vector3(0.1, 0.1, 0.012), PI / 4.0, c(BLACK, CourthouseKit.K_BRICK))


## An opening's joinery from outside: the sash or the door, the sill, the
## head's board and, over most windows, the stepped sunburst of boards
## that marks the house.
func _dress(f: Transform3D, o: Dictionary) -> void:
	# Where two walls stand in one plane both cut the hole; only the first
	# dresses it.
	if _dressed_ids.has(int(o["id"])):
		return
	_dressed_ids[int(o["id"])] = true
	var kind := str(o["kind"])
	# Every opening as built, for tools/twain_openings.py.
	dressed.append({"c": f * Vector3(float(o["u"]), 0, 0), "n": f.basis.z, "w": float(o["w"]), "y0": float(o["y0"]),
		"yt": float(o["yt"]), "kind": kind, "id": int(o["id"])})
	var walls_m := k.m
	k.m = dress_m
	_dress_parts(f, o)
	k.m = walls_m


func _dress_parts(f: Transform3D, o: Dictionary) -> void:
	var kind := str(o["kind"])
	var u := float(o["u"])
	var wd := float(o["w"])
	var y0 := float(o["y0"])
	var yt := float(o["yt"])
	var sash := c(SASH, CourthouseKit.K_PAINT)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	if kind == "win":
		k.sash(f, o, -0.14, sash, -1.0, 0, false)
		k.box("wall", f, Vector3(u, y0 - 0.04, 0.02), Vector3(wd + 0.2, 0.1, 0.2), c(STONE, CourthouseKit.K_STONE))
	elif kind == "french":
		k.glass(f, o, -0.16)
		for s: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(u + s * (wd / 2.0 - 0.04), (y0 + float(o["ys"])) / 2.0, -0.14), Vector3(0.08, float(o["ys"]) - y0, 0.08), sash)
		k.box("wall", f, Vector3(u, (y0 + float(o["ys"])) / 2.0, -0.14), Vector3(0.06, float(o["ys"]) - y0, 0.07), sash)
	if kind == "shut":
		k.door_leaf(f, Vector3(u, y0, -0.12), wd - 0.04, yt - y0 - 0.02, c(Color(0.28, 0.14, 0.08), CourthouseKit.K_WOOD))
	if kind == "door" or kind == "french" or kind == "open":
		doors.append({"center": f * Vector3(u, (y0 + float(o["ys"])) / 2.0, -T * FT / 2.0), "normal": f.basis.z,
			"along": f.basis.x, "width": wd, "y0": y0, "y1": float(o["ys"]), "outside": true})
	if kind == "door":
		# The doors stand open, folded back inside the reveal.
		for s: float in [-1.0, 1.0]:
			var leaf := wd / 2.0 if wd > 1.1 else wd
			if wd <= 1.1 and s > 0.0:
				continue
			var hinge := Vector3(u + s * (wd / 2.0 - 0.07), y0, -T * FT + 0.05)
			var xf := f * Transform3D(Basis(Vector3.UP, s * PI / 2.0), hinge)
			k.door_leaf(xf, Vector3(-s * leaf / 2.0, 0, 0), leaf - 0.02, yt - y0 - 0.02, c(Color(0.28, 0.14, 0.08), CourthouseKit.K_WOOD), false)
		k.box("wall", f, Vector3(u, y0 + 0.02, -0.05), Vector3(wd + 0.1, 0.05, T * FT * 0.8), c(STONE, CourthouseKit.K_STONE))
	# The casing round the opening, standing a little proud.
	if str(o["head"]) == "flat":
		for s: float in [-1.0, 1.0]:
			k.box("wall", f, Vector3(u + s * (wd / 2.0 + 0.05), (y0 + yt) / 2.0, 0.026), Vector3(0.1, yt - y0, 0.05), trim)
		k.box("wall", f, Vector3(u, yt + 0.06, 0.042), Vector3(wd + 0.3, 0.12, 0.08), trim)
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
		var top := wall_top(a, b)
		run(a, b, inside_of(a, b, cw), foot(a, b), top)
		if top < F3:
			_eave(a, b, inside_of(a, b, cw), top, 1.4)
	# The decks' back walls: the third floor's door and windows out onto
	# each tower's top, under the tower's roof.
	run(Vector2(79.9, MZ0), Vector2(66.5, MZ0), Vector2(73.2, 44.0), F3 + 0.5, ALCOVE_TOP, false)
	# The wall behind the bay's porch, with the door out onto it.
	run(Vector2(MX1, 64.0), Vector2(MX1, 75.0), Vector2(108.0, 69.5), BAY_TOP, NORTH_TOP + 0.6, false)
	# The butler's pantry: a quarter round of one storey under a roof
	# falling away from the house.
	var prev := _arc_point(PANTRY_C, PANTRY_R, PANTRY_BREAKS[0])
	for i in range(1, PANTRY_BREAKS.size()):
		var q := _arc_point(PANTRY_C, PANTRY_R, PANTRY_BREAKS[i])
		run(prev, q, PANTRY_C, foot(prev, q), 9.5)
		prev = q
	run(prev, Vector2(113.0, 22.3), PANTRY_C + Vector2(0, -5), foot(prev, Vector2(113.0, 22.3)), 9.5)
	# The service wing: two storeys, lower than the house.
	var wing := [Vector2(113.0, 22.3), Vector2(137.0, 22.3), Vector2(137.0, 19.8), Vector2(155.5, 19.8), Vector2(155.5, 43.8),
		Vector2(MX1, 43.8)]
	for i in wing.size() - 1:
		run(wing[i], wing[i + 1], Vector2(135.0, 33.0), foot(wing[i], wing[i + 1]), WING_TOP)
		_eave(wing[i], wing[i + 1], Vector2(135.0, 33.0), WING_TOP, WING_OUT)


## A wall of the Texas deck's well from a to b, its face toward `open`,
## from y0 up to the roof over it: built in strips whose tops follow the
## roof, its openings cut and dressed.
func _well_wall(a: Vector2, b: Vector2, open: Vector2, y0: float) -> void:
	var mid := (a + b) / 2.0
	var fr := frame(a, b, open)
	var f: Transform3D = fr[0]
	var length: float = fr[1]
	var mine := ops_on(f, length, y0, 40.0, 0.8)
	var strips := maxi(1, int(length / 0.3))
	var o := Vector2(f.origin.x, f.origin.z)
	var from := a if o.distance_to(w2(a)) < o.distance_to(w2(b)) else b
	var to := b if from == a else a
	for i in strips:
		var t0 := float(i) / strips
		var t1 := float(i + 1) / strips
		var top := 1e9
		var back := (mid - open).normalized() * 1.2
		for t: float in [t0, t1]:
			top = minf(top, roof_y(from.lerp(to, t) + back))
		top = minf(top, DECK)
		if top < y0 + 0.5:
			continue
		k.wall("wall", f, length * t0, length * t1, h(y0 - 0.5), h(top), T * FT, c(BRICK, CourthouseKit.K_BRICK), mine, 1000.0)
	for op: Dictionary in mine:
		_dress(f, op)


## Where a wall from a to b starts: a little under the lowest ground
## along it.
static func foot(a: Vector2, b: Vector2) -> float:
	var g := 0.0
	for i in 5:
		g = minf(g, grade_at(a.lerp(b, i / 4.0)))
	return maxf(g - 0.8, GROUND)


## A main wall's top by which side of the house it stands on.
static func wall_top(a: Vector2, b: Vector2) -> float:
	var m := (a + b) / 2.0
	if m.x < MX0 - 0.1 and m.y > 55.0 and m.y < 72.5:
		return F3 + 0.5          # the octagon, to its deck
	if m.y < MZ0 - 0.1 and m.x > 66.0 and m.x < 80.5:
		return F3 + 0.5          # the alcove, to its deck
	if m.x > MX1 + 0.1:
		return BAY_TOP           # the drawing room's bay
	if absf(a.y - MZ0) < 0.1 and absf(b.y - MZ0) < 0.1:
		return WEST_TOP
	if absf(a.x - MX1) < 0.1 and absf(b.x - MX1) < 0.1:
		return NORTH_TOP
	if absf(a.y - MZ1) < 0.1 and absf(b.y - MZ1) < 0.1:
		return EAST_TOP
	return SOUTH_TOP


## A bracketed eave along a run: the frieze board, brackets on it and the
## soffit reaching `out` feet.
func _eave(a: Vector2, b: Vector2, inside: Vector2, y: float, out: float) -> void:
	# Only along the stretches where a roof starts at the wall's top: not
	# where a gable or dormer wall carries the face on up.
	var inward := (inside - (a + b) / 2.0).normalized()
	var n := maxi(1, int(a.distance_to(b) / 1.0))
	var start := -1
	for i in n + 1:
		var q := a.lerp(b, (i + 0.5) / n) + inward * 1.5
		var roofed := i < n and roof_y(q) < y + 4.0 and roof_y(q) > y - 1.0
		if roofed and start < 0:
			start = i
		elif not roofed and start >= 0:
			_eave_run(a.lerp(b, float(start) / n), a.lerp(b, float(i) / n), inside, y, out)
			start = -1


func _eave_run(a: Vector2, b: Vector2, inside: Vector2, y: float, out: float) -> void:
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
	# Each placed where the east and west elevations put it along the house
	# and the north and south ones across it; tops from the elevations.
	# The library's: broad to the east, thin to the south, its four flues
	# in a row along the house.
	_chimney(Vector2(70.6, 56.0), Vector2(6.8, 3.2), 31.3, 47.6)
	# The hall's by the east dormer, the other way about; on the west
	# gable; the kitchen's.
	_chimney(Vector2(97.25, 68.8), Vector2(1.6, 7.2), 29.3, 48.2)
	_chimney(Vector2(101.9, 37.3), Vector2(3.0, 2.0), 31.3, 47.6)
	_chimney(Vector2(137.8, 28.8), Vector2(2.4, 3.6), 20.0, 40.6)
	# The great chimney on the north front, as the north elevation draws
	# it: a base 9.2 ft across standing to 8.8 ft, drawn in to 4.7 at
	# 16 ft; the shaft 4.7 across up the wall and through the roof to a
	# corbelled crown at 33.2 to 36.5, spreading to 6 ft; over it a stack
	# 6 across to 48.3. (The narrow stack drawn beside it is the library's
	# chimney, seen end on.)
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var dark := c(BLACK, CourthouseKit.K_BRICK)
	var g := Transform3D()
	var zc := 59.3
	var xc := MX1 + 0.7
	var g0 := grade_at(Vector2(MX1 + 2.0, zc)) - 0.5
	var p0 := w(xc, zc, g0)
	var p1 := w(xc, zc, 8.8)
	k.block("wall", g, (p0 + p1) / 2.0, Vector3(9.2 * FT, p1.y - p0.y, 2.8 * FT), brick)
	var steps := 6
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var wz := lerpf(9.2, 4.7, (t0 + t1) / 2.0)
		var q0 := w(xc, zc, lerpf(8.8, 16.0, t0))
		var q1 := w(xc, zc, lerpf(8.8, 16.0, t1))
		k.block("wall", g, (q0 + q1) / 2.0, Vector3(wz * FT, q1.y - q0.y, 2.8 * FT), brick if i % 2 == 0 else dark)
	var s0 := w(xc - 0.2, zc, 16.0)
	var s1 := w(xc - 0.2, zc, 33.2)
	k.box("wall", g, (s0 + s1) / 2.0, Vector3(4.7 * FT, s1.y - s0.y, 2.6 * FT), brick)
	for i in 3:
		var c0 := w(xc - 0.2, zc, 33.2 + i * 1.1)
		var c1 := w(xc - 0.2, zc, 33.2 + (i + 1) * 1.1)
		k.box("wall", g, (c0 + c1) / 2.0, Vector3((5.0 + i * 0.5) * FT, c1.y - c0.y, 2.8 * FT), dark if i == 1 else brick)
	_chimney(Vector2(113.9, 59.3), Vector2(2.6, 5.4), 36.4, 48.3)


## A chimney standing from y0 to y1 feet: the shaft, and near its top a
## swelling of corbelled courses under a narrow neck and a capping, as the
## elevations draw them. No pots: the drawings show none.
func _chimney(at: Vector2, size: Vector2, y0: float, y1: float) -> void:
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var dark := c(BLACK, CourthouseKit.K_BRICK)
	var g := Transform3D()
	var sz := Vector3(size.y * FT, 0, size.x * FT)
	var yb := y1 - 5.5
	var base := w(at.x, at.y, y0)
	var sh := w(at.x, at.y, yb)
	k.box("wall", g, (base + sh) / 2.0, Vector3(sz.x, sh.y - base.y, sz.z), brick)
	# [from, to (feet below the top), growth in feet]
	for band: Array in [[5.5, 4.8, 0.2, brick], [4.8, 3.8, 0.45, brick], [3.8, 2.8, 0.6, dark], [2.8, 2.0, 0.45, brick],
			[2.0, 1.3, 0.1, brick], [1.3, 0.4, 0.3, brick], [0.4, 0.0, 0.45, dark]]:
		var ya := h(y1 - float(band[0]))
		var yt := h(y1 - float(band[1]))
		var grow := float(band[2]) * FT
		k.box("wall", g, Vector3(base.x, (ya + yt) / 2.0, base.z), Vector3(sz.x + grow, yt - ya, sz.z + grow), band[3])


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
func hip(x0: float, x1: float, z0: float, z1: float, y0: float, s: float, y1: float, out := 1.4,
		hole := PackedVector2Array(), crest := true, s_end := -1.0) -> void:
	# The ends (across x) may be pitched differently from the sides.
	if s_end < 0.0:
		s_end = s
	var xa := x0 - out
	var xb := x1 + out
	var za := z0 - out
	var zb := z1 + out
	var ye := y0 - out * s
	var ye_end := y0 - out * s_end
	var planes: Array[Vector3] = [Vector3(s_end, 0, ye_end - s_end * xa), Vector3(-s_end, 0, ye_end + s_end * xb), Vector3(0, s, ye - s * za),
		Vector3(0, -s, ye + s * zb), Vector3(0, 0, y1)]
	var rect := PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)])
	# Each face where it is the lowest of the planes, less any hole (where
	# the roof meets a taller block).
	for i in planes.size():
		var pieces: Array = [rect]
		for j in planes.size():
			if j != i:
				pieces = meet(pieces, under(planes[i], planes[j]))
		pieces = cut(pieces, hole)
		for p: PackedVector2Array in pieces:
			roof_piece(p, planes[i], i == 4 and crest)
	var line := PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb), Vector2(xa, za)])
	var runs: Array = [line] if hole.is_empty() else Geometry2D.clip_polyline_with_polygon(line, hole)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for run_: PackedVector2Array in runs:
		for i in run_.size() - 1:
			k.m.bar("wall", w(run_[i].x, run_[i].y, ye) - Vector3(0, 0.1, 0), w(run_[i + 1].x, run_[i + 1].y, ye) - Vector3(0, 0.1, 0), 0.09, 4, trim)


## The boarded edge of a roof round its eave corners.
func _fascia(e: Array) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in e.size():
		var a: Vector3 = e[i]
		var b: Vector3 = e[(i + 1) % e.size()]
		k.m.bar("wall", a - Vector3(0, 0.1, 0), b - Vector3(0, 0.1, 0), 0.09, 4, trim)


## ---- the roof over the main block ---------------------------------------
##
## The main block's roof is steep slopes on all four sides up to a flat
## deck; the gables stand out of it. Each is a
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
		var res := Geometry2D.clip_polygons(p, hole)
		# A hole wholly inside comes back as an outline and a hole of the
		# other winding: split the piece through the hole and cut each half.
		var holed := false
		for q: PackedVector2Array in res:
			if res.size() > 1 and Geometry2D.is_polygon_clockwise(q) != Geometry2D.is_polygon_clockwise(res[0]):
				holed = true
		if holed:
			var cx := 0.0
			for q: Vector2 in hole:
				cx += q.x / hole.size()
			for half: PackedVector2Array in [under(Vector3(1, 0, -cx), Vector3.ZERO), under(Vector3.ZERO, Vector3(1, 0, -cx))]:
				out.append_array(cut(meet([p], half), hole))
			continue
		for q: PackedVector2Array in res:
			if q.size() >= 3:
				out.append(q)
	return out


## The roof's height over a plan point (feet), or far below where there
## is none.
func roof_y(p: Vector2) -> float:
	# Over a tower or bay the main roof is cut away: its own top stands
	# there (the decks, the round's cone, the bay's porch).
	var tops: Array[float] = [F3 + 0.5, F3 + 0.5, SOUTH_TOP, BAY_TOP]
	var plans := tower_plans()
	for i in plans.size():
		if Geometry2D.is_point_in_polygon(p, plans[i] as PackedVector2Array):
			return tops[i]
	var y := -1000.0
	# The alcove's dormer stands to its flat top.
	if Geometry2D.is_point_in_polygon(p, alcove_dormer()):
		return ALCOVE_TOP
	# So does the east slope's dormer, to its eave.
	if Geometry2D.is_point_in_polygon(p, dormer7_plan()):
		return 35.2
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
	# The main roof, from the roof plan and the elevations: steep slopes
	# rising from each side's wall to a flat deck at 35.9 ft; over the west
	# half the south and north gables meet in one ridge at 43.3 ft (the
	# survey's 43'-3"). On the west the steep slope rises from the wall's
	# cornice until it meets the gables' roofs.
	hip_planes = [Vector3(0, WEST_PITCH, WEST_EAVE - WEST_PITCH * (MZ0 - 1.0)), Vector3(0, -0.86, EAST_TOP + 0.86 * MZ1),
		Vector3(1.8, 0, F3 + 0.5 - 1.8 * MX0), Vector3(-1.05, 0, NORTH_TOP + 1.05 * MX1),
		Vector3(0, 0, DECK)]
	roof_rect = PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)])
	# The gables, each at the survey's peak and eave: south over the
	# library's end, the two great east gables, the two small ones between
	# them over the second floor's windows, the north one over the dining
	# room, the small west one.
	# The west half of the main block is one long roof from the south
	# gable to the north one: its ridge the gables' peaks, its west slope
	# one plane from the west cornice, the gables' faces pitched to it.
	# The south face is 17.5 ft wide, the north 15 (the elevations).
	var first := gable_slopes.size()
	cross_gable(Vector2(MX0, RIDGE_Z - 8.75), Vector2(MX0, RIDGE_Z + 8.75), Vector2(70.0, RIDGE_Z), TOP, 1.6,
		TOP - WEST_PITCH * 8.75, SOUTH_TOP, 29.0, 3.0)
	var south_end := gable_slopes.size()
	# The two great east gables throw their roofs forward over their
	# balconies: the southern 0.4 ft, the northern 3.6 (the south and north
	# elevations' edges).
	cross_gable(Vector2(57.5, MZ1), Vector2(79.5, MZ1), Vector2(68.5, 70.0), 35.7, 1.0, 19.3, EAST_TOP, 14.5, 0.4)
	cross_gable(Vector2(96.7, MZ1), Vector2(115.3, MZ1), Vector2(106.0, 70.0), 35.7, 1.0, 19.3, EAST_TOP, 14.5, 3.6)
	cross_gable(Vector2(80.4, MZ1), Vector2(86.9, MZ1), Vector2(83.6, 70.0), 27.3, 0.6, 20.8, EAST_TOP)
	cross_gable(Vector2(88.0, MZ1), Vector2(96.3, MZ1), Vector2(92.1, 70.0), 27.3, 0.6, 20.8, EAST_TOP)
	# The north gable, its roof 5 ft forward over the balcony.
	var north_start := gable_slopes.size()
	cross_gable(Vector2(MX1, RIDGE_Z - 7.5), Vector2(MX1, RIDGE_Z + 7.5), Vector2(100.0, RIDGE_Z), TOP, 2.0,
		TOP - WEST_PITCH * 7.5, NORTH_TOP, 28.5, 5.0)
	# The gables' west slopes are the long west roof: one plane from the
	# south gable's front to the north's (the west elevation's rectangle,
	# x 55.2 to 119.2), a hair above the hip's own west face.
	for i in range(first, gable_slopes.size()):
		if i >= south_end and i < north_start:
			continue
		if (gable_slopes[i]["plane"] as Vector3).y > 0.0:
			gable_slopes[i]["poly"] = PackedVector2Array()
	var west_start := gable_slopes.size()
	cross_gable(Vector2(96.2, MZ0), Vector2(108.4, MZ0), Vector2(102.3, 50.0), 39.4, 1.4, 32.4, WEST_TOP, 8.0)
	var west_end := gable_slopes.size()
	# The long roof and the west gable's roof each show where they stand
	# higher; the long roof is open over the alcove's dormer.
	var long_plane := hip_planes[0] + Vector3(0, 0, 0.02)
	var long: Array = cut([PackedVector2Array([Vector2(55.2, MZ0 - 1.0), Vector2(119.2, MZ0 - 1.0), Vector2(119.2, RIDGE_Z),
		Vector2(55.2, RIDGE_Z)])], alcove_dormer())
	var kept_west: Array[Dictionary] = []
	for i in range(west_start, west_end):
		var g := gable_slopes[i]
		var gp := g["plane"] as Vector3
		for over_: PackedVector2Array in meet([g["poly"]], under(long_plane, gp)):
			long = cut(long, over_)
		for piece: PackedVector2Array in meet([g["poly"]], under(long_plane, gp)):
			kept_west.append({"plane": gp, "poly": piece})
	gable_slopes = gable_slopes.slice(0, west_start)
	gable_slopes.append_array(kept_west)
	for piece: PackedVector2Array in long:
		gable_slopes.append({"plane": long_plane, "poly": piece})
	# The towers and bays rise through the main roof's eaves: no roof over
	# them but their own.
	var towers := tower_plans()
	# The roof is open over the Texas deck's well, the alcove's dormer and
	# the east slope's dormer.
	towers.append(deck_well())
	towers.append(alcove_dormer())
	towers.append(dormer7_plan())
	var cap := hip_planes.size() - 1
	for i in hip_planes.size():
		var pieces: Array = [roof_rect]
		for j in hip_planes.size():
			if j != i:
				pieces = meet(pieces, under(hip_planes[i], hip_planes[j]))
		for g: Dictionary in gable_slopes:
			var hidden := meet([g["poly"]], under(hip_planes[i], g["plane"] as Vector3))
			for hole: PackedVector2Array in hidden:
				pieces = cut(pieces, hole)
		for t: PackedVector2Array in towers:
			pieces = cut(pieces, t)
		for p: PackedVector2Array in pieces:
			roof_piece(p, hip_planes[i], i == cap)
	# The gables' slopes, less where they sink under the hip.
	for g: Dictionary in gable_slopes:
		var sunk: Array = [roof_rect]
		for pl: Vector3 in hip_planes:
			sunk = meet(sunk, under(g["plane"] as Vector3, pl))
		var pieces: Array = [g["poly"]]
		for hole: PackedVector2Array in sunk:
			pieces = cut(pieces, hole)
		for t: PackedVector2Array in towers:
			pieces = cut(pieces, t)
		for p: PackedVector2Array in pieces:
			roof_piece(p, g["plane"] as Vector3, false)
	# The eaves' fascia round the hip, where the roof meets its walls.
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var eave_line := PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb), Vector2(xa, za)])
	var runs: Array = [eave_line]
	for t: PackedVector2Array in towers:
		var next: Array = []
		for line: PackedVector2Array in runs:
			next.append_array(Geometry2D.clip_polyline_with_polygon(line, t))
		runs = next
	# Foot by foot, and only where the hip is the roof at its edge: never
	# across a gable's front, where the roof is the gable's.
	for line: PackedVector2Array in runs:
		for i in line.size() - 1:
			var qa := line[i]
			var qb := line[i + 1]
			var n := maxi(1, int(qa.distance_to(qb)))
			for j in n:
				var p0 := qa.lerp(qb, float(j) / n)
				var p1 := qa.lerp(qb, float(j + 1) / n)
				var pm := (p0 + p1) / 2.0
				var hip := 1e9
				for pl: Vector3 in hip_planes:
					hip = minf(hip, ph(pl, pm))
				if roof_y(pm) > hip + 0.2:
					continue
				k.m.bar("wall", w(p0.x, p0.y, roof_y(p0)) - Vector3(0, 0.1, 0), w(p1.x, p1.y, roof_y(p1)) - Vector3(0, 0.1, 0), 0.09, 4, trim)
	# The dressing room's round under its half cone; the east dormer.
	_half_cone(DRESS_C, DRESS_R + 0.6, 40.0, 320.0, 18, Vector2(57.0, 77.3), 33.0, SOUTH_TOP - 0.3)
	_dormer7()
	var ad := alcove_dormer()
	roof_piece(ad, Vector3(0, 0, ALCOVE_TOP), true)
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	for x: float in [66.5, 79.9]:
		var zt := ad[2].y
		var n3 := (w(x + 1.0, 45.0) - w(x, 45.0)).normalized() * (1.0 if x > 70.0 else -1.0)
		var cheek := ph(hip_planes[0], Vector2(x, MZ0))
		for sd: float in [1.0, -1.0]:
			k.m.tri("wall", w(x, MZ0, cheek), w(x, MZ0, ALCOVE_TOP), w(x, zt, ALCOVE_TOP), n3 * sd, brick)
	# The service wing's roof, stopping at the house; the pantry's roof,
	# falling from the house's corner to its round's eave.
	_wing_roof()
	# The service wing's east window that rises through the cornice, in a
	# wall dormer with a small gable.
	run(Vector2(135.9, 43.8), Vector2(138.5, 43.8), Vector2(137.2, 33.0), WING_TOP, 19.0, false)
	gable(Vector2(135.6, 43.8), Vector2(138.8, 43.8), Vector2(137.2, 33.0), 3.2, 19.0, 20.6, false, true, 0.4)
	_pantry_roof()
	_pantry_steps()
	# Balconies before the gables' doors, their rails as the survey draws
	# them.
	_balcony([Vector2(MX0, 38.6), Vector2(55.2, 38.6), Vector2(55.2, 55.6), Vector2(MX0, 55.6)], 24.2, 1.1, F3)
	_balcony([Vector2(61.7, MZ1), Vector2(61.7, 86.3), Vector2(74.5, 86.3), Vector2(74.5, MZ1)], 24.0, 0.66, F3)
	_balcony([Vector2(100.5, MZ1), Vector2(100.5, 86.3), Vector2(111.4, 86.3), Vector2(111.4, MZ1)], 23.9, 0.73, F3)
	_balcony([Vector2(MX1, 45.8), Vector2(117.0, 45.8), Vector2(117.0, 53.8), Vector2(MX1, 53.8)], 23.1, 0.95, F3)
	_bay_porch()
	_side_porch()
	_back_stair()


## The east dormer's footprint on the roof (survey plan).
func dormer7_plan() -> PackedVector2Array:
	var zb := MZ1 - (35.2 - EAST_TOP) / 0.86
	return PackedVector2Array([Vector2(78.6, zb), Vector2(96.0, zb), Vector2(96.0, 74.5), Vector2(78.6, 74.5)])


## The dormer on the east slope beside the chimney: a low hipped roof
## over a face of seven arched windows, its cheeks down to the slope.
func _dormer7() -> void:
	var x0 := 78.6
	var x1 := 96.0
	var zf := 74.5
	var sill := ph(hip_planes[1], Vector2(87.0, zf))
	run(Vector2(x0, zf), Vector2(x1, zf), Vector2(87.0, 70.0), sill - 0.3, 35.2, false)
	var brick := c(BRICK, CourthouseKit.K_BRICK)
	var zb := MZ1 - (35.2 - EAST_TOP) / 0.86
	for x: float in [x0, x1]:
		var n3 := (w(x + (1.0 if x == x1 else -1.0), 72.0) - w(x, 72.0)).normalized()
		k.m.tri("wall", w(x, zf, sill - 0.3), w(x, zf, 35.2), w(x, zb, 35.2), n3, brick)
		k.m.tri("wall", w(x, zf, sill - 0.3), w(x, zf, 35.2), w(x, zb, 35.2), -n3, brick)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	k.box("wall", Transform3D(), w((x0 + x1) / 2.0, zf + 0.1, 35.0), Vector3(0.12, 0.25, (x1 - x0 + 0.6) * FT), trim)
	# The roof: hipped, from its eaves a foot out to a low ridge, and back
	# into the main roof.
	var eave := 35.2
	var planes: Array[Vector3] = [Vector3(0, -0.4, eave + 0.4 * (zf + 1.0)), Vector3(0.4, 0, eave - 0.4 * (x0 - 1.0)),
		Vector3(-0.4, 0, eave + 0.4 * (x1 + 1.0)), Vector3(0, 0, 36.4)]
	var rect := PackedVector2Array([Vector2(x0 - 1.0, zb - 1.0), Vector2(x1 + 1.0, zb - 1.0), Vector2(x1 + 1.0, zf + 1.0), Vector2(x0 - 1.0, zf + 1.0)])
	for i in planes.size():
		var pieces: Array = [rect]
		for j in planes.size():
			if j != i:
				pieces = meet(pieces, under(planes[i], planes[j]))
		for p: PackedVector2Array in pieces:
			roof_piece(p, planes[i], false)
	_fascia([w(x0 - 1.0, zf + 1.0, eave), w(x1 + 1.0, zf + 1.0, eave)])


## A small dormer of lattice on the service wing's roof at x, over the
## wall at z, facing `side` (-1 west, +1 east).
func _wing_dormer(at: Vector2, out: Vector2, wide: float, sill: float, eave: float, peak: float, over: float) -> void:
	var clap := c(Color(0.52, 0.34, 0.22), HarborTown.K_CLAP)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var side := Vector2(-out.y, out.x)
	var fr := frame(at - side * wide / 2.0, at + side * wide / 2.0, at + out)
	var f: Transform3D = fr[0]
	var width := wide * FT
	# Back into the roof far enough that the roof has risen over its eave.
	var depth := ((eave - sill) / 1.45 + 1.5) * FT
	var y0 := h(sill - 0.4)
	var y1 := h(eave)
	# The cheeks and face, running back into the roof.
	k.box("wall", f, Vector3(width / 2.0, (y0 + y1) / 2.0, -depth / 2.0), Vector3(width, y1 - y0, depth), clap)
	# Its lattice window across the face.
	var fc := Vector3(width / 2.0, (h(sill) + y1) / 2.0 - 0.05, 0.02)
	var panes := int(round(wide / 1.5))
	var pane := width / panes
	var tall := y1 - h(sill) - 0.2
	for i in panes:
		var p := fc + Vector3((i + 0.5) * pane - width / 2.0, 0, 0)
		var ang := atan2(pane, tall)
		for sd: float in [1.0, -1.0]:
			k.box_rz("wall", f, p, Vector3(0.02, sqrt(pane * pane + tall * tall) * 0.5, 0.02), sd * ang, trim)
	k.box("wall", f, Vector3(width / 2.0, h(sill), 0.04), Vector3(width + 0.1, 0.08, 0.08), trim)
	# A low gable over it with broad eaves, running back into the roof.
	var ridge := h(peak)
	var o := over * FT
	for sd: float in [-1.0, 1.0]:
		var e0 := f * Vector3(width / 2.0 + sd * (width / 2.0 + o), y1, 0.3)
		var e1 := f * Vector3(width / 2.0 + sd * (width / 2.0 + o), y1, -depth - 0.3)
		var r0 := f * Vector3(width / 2.0, ridge, 0.3)
		var r1 := f * Vector3(width / 2.0, ridge, -depth - 0.3)
		slope(e0, e1, r1, r0, false)
		k.m.bar("wall", e0, r0, 0.05, 4, trim)
	k.m.tri("wall", f * Vector3(0, y1, 0.01), f * Vector3(width, y1, 0.01), f * Vector3(width / 2.0, ridge, 0.01),
		(f.basis * Vector3(0, 0, 1)).normalized(), trim)
	# The stick truss in the gable.
	k.m.bar("wall", f * Vector3(width / 2.0, y1, 0.05), f * Vector3(width / 2.0, ridge, 0.05), 0.03, 4, trim)
	k.m.bar("wall", f * Vector3(width * 0.25, y1, 0.05), f * Vector3(width / 2.0, (y1 + ridge) / 2.0, 0.05), 0.02, 4, trim)
	k.m.bar("wall", f * Vector3(width * 0.75, y1, 0.05), f * Vector3(width / 2.0, (y1 + ridge) / 2.0, 0.05), 0.02, 4, trim)


## The service wing's roof, from the roof plan and the north, east and west
## elevations: a ridge at WING_RIDGE down the wing's middle from x 123.3
## to 144.4, falling 1.45 to its sides, 1.78 to its south end and 2.1 to
## its north end; across its north end a lower hip, its ridge at 28.7 ft
## along x 146 from z 26.9 to 37.1, falling 1.27 to north and south and
## 2.1 to the sides. Round both, the flat top of the bracketed cornice. Dormers
## with lattice windows on the west, east and north faces.
func _wing_roof() -> void:
	var outline := PackedVector2Array([Vector2(113.0, 22.3), Vector2(137.0, 22.3), Vector2(137.0, 19.8), Vector2(155.5, 19.8),
		Vector2(155.5, 43.8), Vector2(113.0, 43.8)])
	var region: PackedVector2Array = Geometry2D.offset_polygon(outline, WING_OUT, Geometry2D.JOIN_MITER)[0]
	var house := PackedVector2Array([Vector2(MX0, MZ0), Vector2(MX1, MZ0), Vector2(MX1, MZ1 + 2.0), Vector2(MX0, MZ1 + 2.0)])
	var main: Array[Vector3] = [Vector3(0, 1.45, WING_RIDGE - 1.45 * 31.2), Vector3(0, -1.45, WING_RIDGE + 1.45 * 31.2),
		Vector3(1.78, 0, WING_RIDGE - 1.78 * 123.3), Vector3(-2.1, 0, WING_RIDGE + 2.1 * 144.4)]
	var cross: Array[Vector3] = [Vector3(0, 2.1, 28.7 - 2.1 * 26.9), Vector3(0, -2.1, 28.7 + 2.1 * 37.1),
		Vector3(1.27, 0, 28.7 - 1.27 * 146.0), Vector3(-1.27, 0, 28.7 + 1.27 * 146.0)]
	var ring := Vector3(0, 0, WING_RING)
	var flat: Array = cut([region], house)
	for planes: Array[Vector3] in [main, cross]:
		# Each face where it is the lowest of its hip's planes and stands
		# above the cornice; the two hips run into each other.
		for i in planes.size():
			var pieces: Array = [region]
			for j in planes.size():
				if j != i:
					pieces = meet(pieces, under(planes[i], planes[j]))
			pieces = meet(pieces, under(ring, planes[i]))
			pieces = cut(pieces, house)
			for p: PackedVector2Array in pieces:
				roof_piece(p, planes[i], false)
		# The cornice's top stops where the hip rises from it.
		var foot_: Array = [region]
		for pl: Vector3 in planes:
			foot_ = meet(foot_, under(ring, pl))
		for p: PackedVector2Array in foot_:
			flat = cut(flat, p)
	for p: PackedVector2Array in flat:
		if not Geometry2D.is_polygon_clockwise(p):
			roof_piece(p, ring, true)
	# Each where the roof reaches its sill; sizes and heights from the
	# elevations that see it face on.
	for d: Array in [[121.2, -1.0, 6.1, 22.3, 24.6, 25.9, 2.6], [144.8, -1.0, 6.1, 22.3, 24.6, 25.9, 2.6],
			[129.1, 1.0, 5.8, 23.4, 25.7, 27.7, 1.85]]:
		var run_ := (WING_RIDGE - float(d[3])) / 1.45
		_wing_dormer(Vector2(float(d[0]), 31.2 + float(d[1]) * run_), Vector2(0, float(d[1])), float(d[2]), float(d[3]), float(d[4]),
			float(d[5]), float(d[6]))
	_wing_dormer(Vector2(146.0 + (28.7 - 22.3) / 1.27, 31.2), Vector2(1, 0), 7.0, 22.3, 24.0, 25.0, 1.5)


## The pantry's roof: a cone's quarter falling from the house's corner at
## 13.3 ft to its round's eave at 9 ft, a foot beyond the wall.
func _pantry_steps() -> void:
	var d := _arc_point(PANTRY_C, PANTRY_R, 207.0)
	var out := (d - PANTRY_C).normalized()
	var foot := d + out * 5.0
	var g := grade_at(foot)
	k.ramp(Transform3D(), w(foot.x, foot.y, g), w(d.x + out.x * 0.6, d.y + out.y * 0.6, -0.05), 3.5 * FT)
	var stone := c(STONE, CourthouseKit.K_STONE)
	for i in 6:
		var t := (i + 0.5) / 6.0
		var q := (d + out * 0.6).lerp(foot, t)
		var top := lerpf(0.0, g, t)
		k.box("wall", Transform3D(Basis(Vector3.UP, atan2(w2(out).x - w2(Vector2.ZERO).x, w2(out).y - w2(Vector2.ZERO).y)),
			w(q.x, q.y, (top + g) / 2.0 - 0.3)), Vector3.ZERO, Vector3(3.6 * FT, h(top) - h(g) + 0.2, 0.26), stone)


func _pantry_roof() -> void:
	var apex := w(PANTRY_C.x, PANTRY_C.y, 13.3)
	var prev := _arc_point(PANTRY_C, PANTRY_R + 1.0, 180.0)
	var ring: Array = []
	for i in range(1, 13):
		var q := _arc_point(PANTRY_C, PANTRY_R + 1.0, 180.0 + 90.0 * i / 12.0)
		var a := w(prev.x, prev.y, 9.0)
		var b := w(q.x, q.y, 9.0)
		ring.append(a)
		slope(a, b, apex, apex)
		prev = q
	ring.append(w(prev.x, prev.y, 9.0))
	for i in ring.size() - 1:
		k.m.bar("wall", (ring[i] as Vector3) - Vector3(0, 0.08, 0), (ring[i + 1] as Vector3) - Vector3(0, 0.08, 0), 0.08, 4,
			c(TRIM, CourthouseKit.K_PAINT))
	# The roof also covers the round's north end against the wing.
	var e0 := w(PANTRY_C.x, PANTRY_C.y - PANTRY_R - 1.0, 9.0)
	slope(e0, w(113.0, 22.3 - 1.0, 9.0), apex, apex)


## The drawing room's bay: its first floor under an open porch at the
## second, turned posts round it, a railing, and over it a cone.
func _bay_porch() -> void:
	var pts: Array = [Vector2(MX1, 64.0), Vector2(118.5, 64.0), Vector2(121.0, 66.5), Vector2(121.0, 72.5), Vector2(118.5, 75.0),
		Vector2(MX1, 75.0)]
	floor_poly(pts, BAY_TOP, c(PORCH, HarborTown.K_PLANK), c(CEIL, CourthouseKit.K_PLASTER), 0.6)
	k.ramp(Transform3D(), w(MX1 + 2.5, 69.5, BAY_TOP), w(MX1 + 0.3, 69.5, F2), 3.0 * FT)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var rise := h(21.1) - h(BAY_TOP)
	for i in range(1, pts.size() - 1):
		var p := w((pts[i] as Vector2).x, (pts[i] as Vector2).y, BAY_TOP)
		k.turned("wall", Transform3D(), p, rise, 0.1, trim)
		k.solid(Transform3D(), p + Vector3(0, rise / 2.0, 0), Vector3(0.18, rise, 0.18))
	for i in pts.size() - 1:
		var a := w((pts[i] as Vector2).x, (pts[i] as Vector2).y, BAY_TOP)
		var b := w((pts[i + 1] as Vector2).x, (pts[i + 1] as Vector2).y, BAY_TOP)
		k.m.bar("wall", a + Vector3(0, rise, 0), b + Vector3(0, rise, 0), 0.1, 4, trim)
		if i > 0 and i < pts.size() - 2 or i == 0 or i == pts.size() - 2:
			xrail(a, b, 0.6)
		for j in 5:
			var p := a.lerp(b, (j + 0.5) / 5.0) + Vector3(0, rise, 0)
			k.m.bar("wall", p, p - Vector3(0, 0.4, 0), 0.016, 4, trim)
	# The cone, its eave a foot and a half out.
	var ring: Array[Vector3] = []
	var cen := Vector2(117.6, 69.5)
	for i in 9:
		var a := deg_to_rad(-90.0 + 180.0 * i / 8.0)
		var q := Vector2(MX1, 69.5) + Vector2(cos(a), sin(a)) * 7.6
		ring.append(w(q.x, q.y, 21.1))
	var apex := w(cen.x, cen.y, 31.3)
	for i in ring.size() - 1:
		slope(ring[i], ring[i + 1], apex, apex)
		k.m.bar("wall", ring[i] - Vector3(0, 0.1, 0), ring[i + 1] - Vector3(0, 0.1, 0), 0.09, 4, trim)
	slope(ring[ring.size() - 1], ring[0], apex, apex)
	k.m.bar("wall", apex, apex + Vector3(0, 0.3, 0), 0.04, 6, trim)


## The side door on the north front: a small porch before it on posts,
## its hood, steps down to the lawn.
func _side_porch() -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var deck: Array = [Vector2(MX1, 43.9), Vector2(119.0, 43.9), Vector2(119.0, 49.8), Vector2(MX1, 49.8)]
	floor_poly(deck, -0.1, c(PORCH, HarborTown.K_PLANK), c(TRIM, CourthouseKit.K_PAINT), 0.4)
	for z: float in [44.3, 49.3]:
		var p := w(119.0, z, -0.1)
		k.turned("wall", Transform3D(), p, h(9.0) - h(-0.1), 0.08, trim)
		k.solid(Transform3D(), p + Vector3(0, 1.0, 0), Vector3(0.15, 2.0, 0.15))
	var hood: Array = [Vector2(MX1, 43.4), Vector2(119.6, 43.4), Vector2(119.6, 50.3), Vector2(MX1, 50.3)]
	floor_poly(hood, 9.9, c(SLATE, CourthouseKit.K_SLATE), c(Color(0.60, 0.50, 0.38), CourthouseKit.K_WOOD), 0.9, false)
	var a := w(119.6, 43.4, 9.1)
	var b := w(119.6, 50.3, 9.1)
	k.m.bar("wall", a, b, 0.07, 4, trim)
	# The steps down northward to the lawn.
	var g := grade_at(Vector2(123.0, 46.9))
	var s0 := w(119.0, 46.9, -0.1)
	var s1 := w(123.5, 46.9, g)
	k.ramp(Transform3D(), s1, s0, 4.0 * FT)
	for i in 5:
		var p := s0.lerp(s1, (i + 0.5) / 5.0)
		k.box("wall", Transform3D(), Vector3(p.x, (p.y + s1.y) / 2.0 - 0.1, p.z), Vector3(4.2 * FT, maxf(p.y - s1.y + 0.2, 0.1), 0.28),
			c(STONE, CourthouseKit.K_STONE))


## The back stair along the service wing's east face: its roof falling
## with the stair from the side porch to the lawn, fretwork along its
## edge, posts and lattice under it.
func _back_stair() -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var x0 := 120.2
	var x1 := 136.7
	var y0 := 19.6
	var y1 := 10.2
	var zi := 43.8
	var zo := 48.0
	var a := w(x0, zo, y0)
	var b := w(x1, zo, y1)
	var ai := w(x0, zi, y0 + 1.5)
	var bi := w(x1, zi, y1 + 1.5)
	slope(a, b, bi, ai)
	k.m.bar("wall", a, b, 0.09, 4, trim)
	var n := int(a.distance_to(b) / 0.12)
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		k.m.bar("wall", p, p - Vector3(0, 0.18 if i % 2 == 0 else 0.12, 0), 0.012, 3, trim)
	for i in 4:
		var t := float(i) / 3.0
		var x := lerpf(x0, x1, t)
		var top := lerpf(y0, y1, t)
		var g := grade_at(Vector2(x, zo))
		var foot := w(x, zo, g)
		var head := w(x, zo, top)
		k.box("wall", Transform3D(), (foot + head) / 2.0, Vector3(0.14, head.y - foot.y, 0.14), trim)
		k.solid(Transform3D(), (foot + head) / 2.0, Vector3(0.14, head.y - foot.y, 0.14))
	# Lattice panels under the roof's lower end.
	for i in 3:
		var t0 := float(i) / 3.0
		var t1 := float(i + 1) / 3.0
		var pa := w(lerpf(x0, x1, t0), zo, grade_at(Vector2(lerpf(x0, x1, t0), zo)) + 0.3)
		var pb := w(lerpf(x0, x1, t1), zo, grade_at(Vector2(lerpf(x0, x1, t1), zo)) + 0.3)
		var ha := lerpf(y0, y1, t0) - 2.0
		var hb := lerpf(y0, y1, t1) - 2.0
		var qa := Vector3(pa.x, h(ha), pa.z)
		var qb := Vector3(pb.x, h(hb), pb.z)
		k.m.bar("wall", pa, qb, 0.02, 3, trim)
		k.m.bar("wall", pb, qa, 0.02, 3, trim)


## The plans of what rises through the main roof's eaves: the library's
## alcove, the guest room's octagon, the dressing room's round, the
## drawing room's bay; each to the main walls' outer faces.
## The Texas deck's well into the main roof (survey plan), as the third
## floor plan draws it: from the octagon to the top hall's wall.
static func deck_well() -> PackedVector2Array:
	return PackedVector2Array([Vector2(MX0, DECK_Z0), Vector2(DECK_X, DECK_Z0), Vector2(DECK_X, 67.5), Vector2(60.5, 71.1),
		Vector2(MX0, 71.1)])


## The dormer behind the alcove deck, through the long west roof: from
## the deck's back wall to where the roof rises to its top.
const ALCOVE_TOP := 34.3
static func alcove_dormer() -> PackedVector2Array:
	var zb := MZ0 - 1.0 + (ALCOVE_TOP - WEST_EAVE) / WEST_PITCH
	return PackedVector2Array([Vector2(66.5, MZ0 - 1.2), Vector2(79.9, MZ0 - 1.2), Vector2(79.9, zb), Vector2(66.5, zb)])


static func tower_plans() -> Array:
	var out: Array = []
	out.append(PackedVector2Array([Vector2(66.5, MZ0), Vector2(66.5, 33.6), Vector2(70.5, 29.7), Vector2(75.9, 29.7), Vector2(79.9, 33.6),
		Vector2(79.9, MZ0)]))
	out.append(PackedVector2Array([Vector2(MX0, 55.8), Vector2(52.3, 55.8), Vector2(48.7, 60.4), Vector2(48.7, 66.8), Vector2(52.5, 71.1),
		Vector2(MX0, 71.1)]))
	var round := PackedVector2Array()
	for i in 13:
		round.append(_arc_point(DRESS_C, DRESS_R, 90.0 + 160.0 * i / 12.0))
	round.append(Vector2(MX0, DRESS_C.y - DRESS_R))
	round.append(Vector2(MX0, DRESS_C.y + DRESS_R))
	out.append(round)
	out.append(PackedVector2Array([Vector2(MX1, 64.0), Vector2(118.5, 64.0), Vector2(121.0, 66.5), Vector2(121.0, 72.5), Vector2(118.5, 75.0),
		Vector2(MX1, 75.0)]))
	return out


## The house's rooms' outline: the outer walls' inner faces at the first
## and second floors.
static func inner_plan() -> PackedVector2Array:
	var best := PackedVector2Array()
	for q: PackedVector2Array in Geometry2D.offset_polygon(perimeter(), -T, Geometry2D.JOIN_MITER):
		if absf(signed_area(q)) > absf(signed_area(best)):
			best = q
	return best


## The parts of the roof's plan where the roof stands higher than
## `level` feet: under the main roof, or under a gable.
func roof_higher(level: float) -> Array:
	var flat := Vector3(0, 0, level)
	var high: Array = [roof_rect]
	for pl: Vector3 in hip_planes:
		high = meet(high, under(flat, pl))
	var out: Array = high.duplicate()
	for g: Dictionary in gable_slopes:
		var up := meet([g["poly"]], under(flat, g["plane"] as Vector3))
		for hp: PackedVector2Array in out:
			up = cut(up, hp)
		out.append_array(up)
	return out


## A piece of the roof over a plan polygon on a plane: slate in courses of
## colour by height, or the flat's tin; a plastered
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


## A small balcony: boards over the outline (survey plan, the house side
## first and last) at y feet, a railing round its open sides.
func _balcony(pts: Array, y: float, rail := 0.95, door_y := -1000.0) -> void:
	floor_poly(pts, y, c(PORCH, HarborTown.K_PLANK), c(TRIM, CourthouseKit.K_PAINT), 0.5)
	# From a door set higher than the deck, a short ramp down onto it.
	if door_y > y + 0.1:
		var wall_mid := ((pts[0] as Vector2) + (pts[pts.size() - 1] as Vector2)) / 2.0
		var out := (((pts[1] as Vector2) + (pts[pts.size() - 2] as Vector2)) / 2.0 - wall_mid).normalized()
		var r0 := wall_mid + out * 0.3
		var r1 := wall_mid + out * 3.0
		k.ramp(Transform3D(), w(r1.x, r1.y, y), w(r0.x, r0.y, door_y), 3.0 * FT)
		var trim := c(PORCH, HarborTown.K_PLANK)
		var steps := 3
		for i in steps:
			var t := (i + 0.5) / steps
			var q := r0.lerp(r1, t)
			var top := lerpf(door_y, y, (i + 1.0) / steps)
			k.box("wall", Transform3D(Basis(Vector3.UP, atan2(w2(out).x - w2(Vector2.ZERO).x, w2(out).y - w2(Vector2.ZERO).y)),
				w(q.x, q.y, (top + y) / 2.0)), Vector3.ZERO, Vector3(3.0 * FT, h(top) - h(y) + 0.02, 0.9 * FT), trim)
	for i in range(1, pts.size() - 1):
		xrail(w(pts[i - 1].x, pts[i - 1].y, y) if i > 1 else w(pts[0].x, pts[0].y, y).lerp(w(pts[1].x, pts[1].y, y), 1.0),
			w(pts[i].x, pts[i].y, y), rail)
	for i in range(1, pts.size() - 2):
		xrail(w(pts[i].x, pts[i].y, y), w(pts[i + 1].x, pts[i + 1].y, y), rail)
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
func cross_gable(a: Vector2, b: Vector2, inward: Vector2, peak: float, over := 1.4, eave := EAVE, wall := EAVE,
		depth := -1.0, front := -1.0) -> void:
	var half := (b - a).length() / 2.0
	# A gable given its depth runs its ridge that far at full height.
	if depth > 0.0:
		if eave > wall + 0.1:
			run(a, b, inward, wall, eave, false)
		gable(a, b, inward, depth, eave, peak, true, false, over, maxf(eave, wall), front)
		return
	# The ridge must die into the main roof where the gable ends: no higher
	# than the main roof there.
	var mid := (a + b) / 2.0
	var into := (b - a).normalized().orthogonal()
	if into.dot(inward - mid) < 0.0:
		into = -into
	var end := mid + into * (half + 3.0)
	var main := 1e9
	for pl: Vector3 in hip_planes:
		main = minf(main, ph(pl, end))
	# Where the gable's eave stands over the wall, the wall rises to it.
	if eave > wall + 0.1:
		run(a, b, inward, wall, eave, false)
	gable(a, b, inward, half + 3.0 + maxf(front, 0.0), eave, minf(peak, main - 0.3), true, false, over, maxf(eave, wall), front)


## A gable: its face on the house's wall between the eave corners a and
## b (survey plan), the roof running `depth` feet back into the house
## (`inward` a point that way); from the eave y0 to the peak y1. Its two
## slopes join the main roof's planes (or, `alone`, are drawn whole with
## the far end closed). The face is brick with its openings cut in
## courses that narrow with the rakes; the rakes carry carved
## bargeboards, a king post and collar in the peak and a finial.
func gable(a: Vector2, b: Vector2, inward: Vector2, depth: float, y0: float, y1: float, face := true, alone := false,
		over := 1.8, face0 := -1000.0, front := -1.0) -> void:
	if front < 0.0:
		front = over
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
		var ea := edge - into * front
		var eb := edge + into * depth
		var ra := mid - into * front
		var rb := mid + into * depth
		if alone:
			slope(w(ea.x, ea.y, y0 - drop), w(eb.x, eb.y, y0 - drop), w(rb.x, rb.y, y1), w(ra.x, ra.y, y1))
		else:
			gable_slopes.append({"plane": plane3(Vector3(ea.x, ea.y, y0 - drop), Vector3(eb.x, eb.y, y0 - drop), Vector3(rb.x, rb.y, y1)),
				"poly": PackedVector2Array([ea, eb, rb, ra])})
	# The far end closed: whole where the gable stands alone, and inside
	# the main roof where the gable runs into it, so no slot opens between
	# the gable's end and the roof behind.
	var fa := mid + along * (half + over) + into * depth
	var fb := mid - along * (half + over) + into * depth
	var fm := mid + into * depth
	var back := w2(fm + into) - w2(fm)
	for sd: float in [1.0, -1.0] if not alone else [1.0]:
		k.m.tri("wall", w(fa.x, fa.y, y0 - drop), w(fb.x, fb.y, y0 - drop), w(fm.x, fm.y, y1), Vector3(back.x, 0, back.y).normalized() * sd,
			c(SLATE, CourthouseKit.K_SLATE) if alone else c(CEIL, CourthouseKit.K_PLASTER))
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
		# The face starts where the wall under it stops.
		if yb <= face0 + 0.01:
			continue
		ya = maxf(ya, face0)
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
	var ff := f * Transform3D(Basis(), Vector3(0, 0, front * FT - 0.05))
	for side: float in [-1.0, 1.0]:
		var cen := Vector3(length / 2.0 + side * (half + over) * FT / 2.0, (h(y0 - drop) + h(y1)) / 2.0 - 0.1, 0.0)
		k.box_rz("wall", ff, cen, Vector3(rake, 0.34, 0.06), -side * ang, trim)
		var n := int(rake / 0.35)
		for j in n:
			var t := (j + 0.5) / n
			var p := Vector3(length / 2.0 + side * (half + over) * FT * (1.0 - t), lerpf(h(y0 - drop), h(y1), t) - 0.36, 0.0)
			k.box_rz("wall", ff, p, Vector3(0.12, 0.12, 0.05), -side * ang + PI / 4.0, trim)
	var tf := f * Transform3D(Basis(), Vector3(0, 0, 0.08))
	# (in the peak only, clear of every opening in the face)
	var ty := h(y1 - (y1 - y0) * 0.2)
	var tw := half * FT * 0.2 * 2.0 * 0.9
	k.box("wall", tf, Vector3(length / 2.0, ty, 0.0), Vector3(tw, 0.12, 0.1), trim)
	k.box("wall", tf, Vector3(length / 2.0, (ty + h(y1)) / 2.0 - 0.1, 0.0), Vector3(0.12, h(y1) - ty + 0.2, 0.1), trim)
	var out3 := w2(mid - into) - w2(mid)
	var tip := w(mid.x, mid.y, y1) + Vector3(out3.x, 0, out3.y).normalized() * (front * FT - 0.05)
	k.m.bar("wall", tip, tip + Vector3(0, 0.35, 0), 0.05, 6, trim)
	k.m.sphere("wall", Transform3D(Basis(), tip + Vector3(0, 0.2, 0)), 0.08, 8, trim)
	k.m.bar("wall", tip, tip - Vector3(0, 0.6, 0), 0.06, 6, trim)


## A half cone over a round or a bay: its eave on the circle cen, r (survey
## feet) from angle a0 to a1 at the main eave, rising to a point at apex,
## y1 feet up, against the main roof.
func _half_cone(cen: Vector2, r: float, a0: float, a1: float, n: int, apex2: Vector2, y1: float, eave := EAVE + 0.1) -> void:
	var apex := w(apex2.x, apex2.y, y1)
	var ring: Array = []
	for i in n + 1:
		var q := _arc_point(cen, r, lerpf(a0, a1, float(i) / n))
		ring.append(w(q.x, q.y, eave))
	for i in n:
		slope(ring[i], ring[i + 1], apex, apex)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	for i in n:
		k.m.bar("wall", (ring[i] as Vector3) - Vector3(0, 0.1, 0), (ring[i + 1] as Vector3) - Vector3(0, 0.1, 0), 0.09, 4, trim)


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
	k.m.bar("wall", apex - Vector3(0, 0.2, 0), apex + Vector3(0, 0.25, 0), 0.05, 6, trim)


## An iron or wooden railing from a to b (world), h metres tall: a rail
## and balusters; solid to the player.
func _rail(a: Vector3, b: Vector3, ht: float, col := TRIM) -> void:
	var trim := c(col, CourthouseKit.K_PAINT)
	var length := a.distance_to(b)
	if length < 0.05:
		return
	rails.append([a, b])
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
	# The Texas deck's well: the billiard room's wall, the top hall's with
	# its doors, the storeroom's; each up under the roof round the well
	# (built after the roofs, whose height it follows).
	for wall_: Array in [[Vector2(MX0, DECK_Z0), Vector2(DECK_X, DECK_Z0)], [Vector2(DECK_X, DECK_Z0), Vector2(DECK_X, 67.5)],
			[Vector2(DECK_X, 67.5), Vector2(60.5, 71.1)], [Vector2(60.5, 71.1), Vector2(MX0, 71.1)]]:
		_well_wall(wall_[0] as Vector2, wall_[1] as Vector2, Vector2(60.0, 63.5), F3 + 0.5)
	# Each deck on its tower's own outline, open on the house's side.
	_deck_tower([Vector2(MX0, 55.8), Vector2(52.3, 55.8), Vector2(48.7, 60.4), Vector2(48.7, 66.8), Vector2(52.5, 71.1), Vector2(MX0, 71.1)],
		F3 + 0.5, 34.6, Vector2(MX0 - 1.5, 63.45), 37.1, 1.0)
	floor_poly(deck_well(), F3 + 0.5, c(PORCH, HarborTown.K_PLANK), c(CEIL, CourthouseKit.K_PLASTER), 1.0)
	_deck_tower([Vector2(66.5, MZ0), Vector2(66.5, 33.6), Vector2(70.5, 29.7), Vector2(75.9, 29.7), Vector2(79.9, 33.6), Vector2(79.9, MZ0)],
		F3 + 0.5, 33.1, Vector2(73.2, 34.2), 46.6, 2.8)


## An open deck on top of a tower whose outer walls run along `chain`
## (survey plan, from the main wall round to the main wall): boards over
## it, a post at each corner with brackets and a fret under the plate,
## crossed railings between, and a roof rising from the plate to a point
## at `apex` (plan), `peak` feet, its eaves standing out 1.6 ft.
func _deck_tower(chain: Array[Vector2], floor_y: float, eave_y: float, apex: Vector2, peak: float, eave_out := 1.6) -> void:
	floor_poly(chain, floor_y, c(PORCH, HarborTown.K_PLANK), c(CEIL, CourthouseKit.K_PLASTER), 1.0)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var rise := h(eave_y) - h(floor_y)
	for i in chain.size() - 1:
		var a := chain[i]
		var b := chain[i + 1]
		var pa := w(a.x, a.y, floor_y)
		var pb := w(b.x, b.y, floor_y)
		for post: Vector3 in [pa, pb]:
			k.box("wall", Transform3D(), post + Vector3(0, rise / 2.0, 0), Vector3(0.16, rise, 0.16), trim)
			k.solid(Transform3D(), post + Vector3(0, rise / 2.0, 0), Vector3(0.16, rise, 0.16))
		k.m.bar("wall", pa + Vector3(0, rise, 0), pb + Vector3(0, rise, 0), 0.1, 4, trim)
		for j in 7:
			var p := pa.lerp(pb, (j + 0.5) / 7.0) + Vector3(0, rise, 0)
			k.m.bar("wall", p, p - Vector3(0, 0.45, 0), 0.018, 4, trim)
		k.m.bar("wall", pa + Vector3(0, rise - 0.45, 0), pb + Vector3(0, rise - 0.45, 0), 0.03, 4, trim)
		var mid := pa.lerp(pb, 0.5)
		for post: Vector3 in [pa, pb]:
			k.m.bar("wall", post + Vector3(0, rise - 0.8, 0), post.lerp(mid, 0.3) + Vector3(0, rise, 0), 0.035, 4, trim)
		xrail(pa, pb, 0.95)
	# The roof: from the plate, standing out, up to its point.
	var top := w(apex.x, apex.y, peak)
	var ring: Array = []
	for q: Vector2 in chain:
		var out := (q - apex).normalized() * eave_out
		ring.append(w(q.x + out.x, q.y + out.y, eave_y + 0.1))
	for i in ring.size() - 1:
		slope(ring[i], ring[i + 1], top, top)
	# Closed over the house's side too.
	slope(ring[ring.size() - 1], ring[0], top, top)
	for i in ring.size() - 1:
		k.m.bar("wall", (ring[i] as Vector3) - Vector3(0, 0.1, 0), (ring[i + 1] as Vector3) - Vector3(0, 0.1, 0), 0.09, 4, trim)
	k.m.bar("wall", top - Vector3(0, 0.2, 0), top + Vector3(0, 0.3, 0), 0.05, 6, trim)
	k.m.bar("iron", top + Vector3(0, 0.3, 0), top + Vector3(0, 0.5, 0), 0.015, 4, IRON)


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
	var top_y := 10.8
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
	var ridge := w(MX0, CONS_C.y, 16.3)
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
	var deck := -0.03
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
	_porch_edge(ombra.slice(0, 6), deck, 9.7, [Vector2(22.8, 79.0)])
	var roof_o: Array[Vector2] = [Vector2(49.0, 65.5), Vector2(28.4, 65.5), Vector2(21.0, 73.6), Vector2(21.0, 84.8), Vector2(28.5, 92.0),
		Vector2(49.0, 92.0)]
	_porch_roof(roof_o, 9.9)
	# The veranda: posts along its outer edge; the steps' gap left open.
	var edge := veranda.slice(2)
	edge.reverse()
	_porch_edge(edge, deck, 9.7, [Vector2(90.5, 92.8)])
	var roof_v: Array[Vector2] = veranda.duplicate()
	for i in roof_v.size():
		var p := roof_v[i]
		if p.y > MZ1 + 0.1:
			roof_v[i] = p + Vector2(0, 1.2)
	_porch_roof(roof_v, 9.9)
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
	var o0 := w(22.6, 79.0, deck)
	var o1 := w(18.6, 79.0, GRADE)
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
	for piece: PackedVector2Array in Geometry2D.clip_polygons(PackedVector2Array(poly), perimeter()):
		var pts: Array = []
		for q: Vector2 in piece:
			pts.append(q)
		floor_poly(pts, y + 0.6, c(Color(0.30, 0.29, 0.29), CourthouseKit.K_TAR), c(Color(0.60, 0.50, 0.38), CourthouseKit.K_WOOD), 0.6, false)
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var outer := Geometry2D.clip_polygons(PackedVector2Array(poly), perimeter())
	var edge := PackedVector2Array() if outer.is_empty() else outer[0]
	for i in edge.size():
		var qa := edge[i]
		var qb := edge[(i + 1) % edge.size()]
		# An edge along the house's wall has no fascia.
		if _near_perimeter((qa + qb) / 2.0, 0.3):
			continue
		var a := w(qa.x, qa.y, y)
		var b := w(qb.x, qb.y, y)
		var n3 := (b - a).cross(Vector3.UP).normalized()
		k.m.quad("wall", a - Vector3(0, 0.02, 0), b - Vector3(0, 0.02, 0), b + Vector3(0, 0.2, 0), a + Vector3(0, 0.2, 0), n3, trim)
		k.m.quad("wall", a - Vector3(0, 0.02, 0), b - Vector3(0, 0.02, 0), b + Vector3(0, 0.2, 0), a + Vector3(0, 0.2, 0), -n3, trim)
		var n := int(a.distance_to(b) / 0.12)
		for j in n:
			var p := a.lerp(b, (j + 0.5) / n)
			k.m.bar("wall", p - Vector3(0, 0.02, 0), p - Vector3(0, 0.22 if j % 2 == 0 else 0.14, 0), 0.012, 3, trim)


## Whether a plan point lies within d feet of the house's outer wall.
static func _near_perimeter(q: Vector2, d: float) -> bool:
	var p := perimeter()
	for i in p.size():
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, p[i], p[(i + 1) % p.size()])) < d:
			return true
	return false


## The porte-cochere: a gabled roof on four posts over the drive, braced
## and bracketed, the veranda's landing under its near end.
func _porte_cochere() -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var posts := [Vector2(85.3, 95.2), Vector2(96.3, 95.2), Vector2(85.3, 108.2), Vector2(96.3, 108.2)]
	var top := 10.0
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
	# Great sawn brackets from each post out under the roof's overhang.
	for p: Vector2 in posts:
		var outs: Array[Vector2] = [Vector2(82.5 if p.x < 90.0 else 99.0, p.y)]
		if p.y > 100.0:
			outs.append(Vector2(p.x, 114.3))
		for q: Vector2 in outs:
			var a0 := w(p.x, p.y, top - 2.6)
			var a1 := w(p.x, p.y, top)
			var e := w(q.x, q.y, top) + (w(q.x, q.y) - w(p.x, p.y)).normalized() * -0.15
			var n3 := (e - a1).cross(Vector3.UP).normalized()
			for sd: float in [1.0, -1.0]:
				k.m.tri("wall", a0, a1, e, n3 * sd, trim)
	# The roof: nearly flat, from the house out over the drive, over a
	# fascia 2.3 ft deep.
	hip(82.5, 99.0, MZ1, 114.3, 12.3, 0.2, 12.9, 0.0, PackedVector2Array(), false)
	var fas: Array = [Vector2(82.5, MZ1), Vector2(82.5, 114.3), Vector2(99.0, 114.3), Vector2(99.0, MZ1)]
	for i in 3:
		var qa: Vector2 = fas[i]
		var qb: Vector2 = fas[i + 1]
		var pa := w(qa.x, qa.y, 10.0)
		var pb := w(qb.x, qb.y, 10.0)
		var n3 := (pb - pa).cross(Vector3.UP).normalized()
		var rise := h(12.3) - h(10.0)
		for sd: float in [1.0, -1.0]:
			k.m.quad("wall", pa, pb, pb + Vector3(0, rise, 0), pa + Vector3(0, rise, 0), n3 * sd, trim)
		var n := int(pa.distance_to(pb) / 0.6)
		for j in n:
			var p := pa.lerp(pb, (j + 0.5) / n)
			k.box("wall", Transform3D(), p + Vector3(0, rise * 0.55, 0) + n3 * 0.04, Vector3(0.1, 0.18, 0.1), trim)
	floor_poly([Vector2(82.5, MZ1), Vector2(82.5, 114.3), Vector2(99.0, 114.3), Vector2(99.0, MZ1)], 10.0,
		c(Color(0.60, 0.50, 0.38), CourthouseKit.K_WOOD), c(Color(0.60, 0.50, 0.38), CourthouseKit.K_WOOD), 0.05, false)
	# The wind-screen on the porte-cochere's north side: panels of glass
	# in lattice, diamonds in their lights, over a panel of herringbone.
	_windscreen(Vector2(96.3, MZ1 + 0.1), Vector2(96.3, 94.3))


## A wind-screen from a to b (survey plan): posts, a herringbone base,
## lights of glass with diamond lattice, a fret under its head.
func _windscreen(a: Vector2, b: Vector2) -> void:
	var trim := c(TRIM, CourthouseKit.K_PAINT)
	var pa := w(a.x, a.y, -0.5)
	var pb := w(b.x, b.y, -0.5)
	var along := pb - pa
	var n3 := along.cross(Vector3.UP).normalized()
	var panels := maxi(1, int(round(along.length() / 1.3)))
	var y0 := h(-0.5)
	var y_base := h(3.3)
	var y_top := h(9.1)
	var y_head := h(9.9)
	k.m.quad("wall", pa, pb, Vector3(pb.x, y_base, pb.z), Vector3(pa.x, y_base, pa.z), n3, c(Color(0.45, 0.20, 0.12), CourthouseKit.K_WOOD))
	k.m.quad("wall", pa, pb, Vector3(pb.x, y_base, pb.z), Vector3(pa.x, y_base, pa.z), -n3, c(Color(0.45, 0.20, 0.12), CourthouseKit.K_WOOD))
	var ga := Vector3(pa.x, y_base, pa.z)
	var gb := Vector3(pb.x, y_base, pb.z)
	k.m.quad("glass", ga, gb, Vector3(pb.x, y_top, pb.z), Vector3(pa.x, y_top, pa.z), n3, Color(1, 1, 1, 1))
	for i in panels + 1:
		var p := pa.lerp(pb, float(i) / panels)
		k.box("wall", Transform3D(Basis(Vector3.UP, atan2(n3.x, n3.z)), Vector3(p.x, (y0 + y_head) / 2.0, p.z)), Vector3.ZERO,
			Vector3(0.12, y_head - y0, 0.12), trim)
		if i < panels:
			var q := pa.lerp(pb, (i + 1.0) / panels)
			var mid := (p + q) / 2.0
			for j in 3:
				var cy := lerpf(y_base, y_top, (j + 0.5) / 3.0)
				var r := minf((q - p).length() * 0.3, (y_top - y_base) / 7.0)
				var u := along.normalized() * r
				var up := Vector3(0, r * 1.2, 0)
				var cen := Vector3(mid.x, cy, mid.z) + n3 * 0.02
				k.m.bar("wall", cen - u, cen + up, 0.012, 3, trim)
				k.m.bar("wall", cen + up, cen + u, 0.012, 3, trim)
				k.m.bar("wall", cen + u, cen - up, 0.012, 3, trim)
				k.m.bar("wall", cen - up, cen - u, 0.012, 3, trim)
	k.m.bar("wall", ga, gb, 0.05, 4, trim)
	k.m.bar("wall", Vector3(pa.x, y_top, pa.z), Vector3(pb.x, y_top, pb.z), 0.05, 4, trim)
	k.m.bar("wall", Vector3(pa.x, y_head, pa.z), Vector3(pb.x, y_head, pb.z), 0.07, 4, trim)
	var mid3 := (pa + pb) / 2.0
	k.solid(Transform3D(Basis(Vector3.UP, atan2(n3.x, n3.z)), Vector3(mid3.x, (y0 + y_head) / 2.0, mid3.z)), Vector3.ZERO,
		Vector3(0.1, y_head - y0, along.length()))


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
