class_name FullHouse
extends HouseBase
## A two-storey house modelled whole, inside and out, in one of two
## plans:
##
## 1  a centre-hall colonial, 11 by 8.5 m under a 33-degree roof, the
##    ridge across the front: the hall and its stair in the middle, the
##    living room with its fireplace down one side, the dining room and
##    the kitchen down the other; four bedrooms and a bath upstairs.
## 2  a gable-front house with a porch, 7.5 by 10.5 m under a 40-degree
##    roof, the gable to the street: a side hall and stair, the parlour
##    with its fireplace and piano, the dining room behind it, the
##    kitchen across the back; two bedrooms and a bath upstairs.
##
## Rooms are rectangles on a floor. Each builds its own faces (paper,
## paint, plaster or tile), its floor and its ceiling, and cuts in
## whatever doors and windows fall on its edges; where two rooms meet,
## their faces are the partition between them. The outer walls are
## clapboard slabs round the same openings; the roof, the chimney, the
## steps or the porch, the trim and the windows go on the outside. The
## furniture is placed by hand for each plan, its colours the house's.

const C1 := 3.4           # the first floor's ceiling
const U := 3.5            # the upstairs floor's top
const E := 6.2            # the eaves and the upstairs ceiling
const F := 0.6

var style := 1
var w := 11.0
var d := 8.5
var pitch := deg_to_rad(33.0)
var ridge_x := true
var door_x := 0.0
var clap := Color(0.56, 0.64, 0.70)
var clap_kind := HarborTown.K_CLAP
var shutter := Color(0.35, 0.08, 0.07)
var door_color := Color(0.12, 0.25, 0.16)
var roof := Color(0.20, 0.20, 0.21)
var curtains := Color(0.85, 0.82, 0.72)
var papers: Array[Color] = [Color(0.72, 0.66, 0.52), Color(0.58, 0.66, 0.72), Color(0.78, 0.62, 0.58),
	Color(0.62, 0.70, 0.58), Color(0.86, 0.80, 0.84), Color(0.84, 0.82, 0.66)]
var cloth := Color(0.55, 0.22, 0.2)
var wood := Color(0.42, 0.26, 0.14)
var open_windows: Array[int] = []
var rooms: Array[Dictionary] = []    # {name, floor, x0, x1, z0 (front), z1 (back), finish, floor_finish}
var windows: Array[Dictionary] = []  # {wall, at, y, w, h, floor}
var doors: Array[Dictionary] = []    # interior: {p: Vector2, axis: "x" | "z", w, h, floor}
var outer_doors: Array[Dictionary] = []   # {wall, at, w}
var stair: Dictionary = {}           # {x0, x1, z0 (bottom), z1 (top), rail_x, void: Rect2}
var chimney_top := Vector3.ZERO
var front_xs: Array[float] = []
var step_z := 1.5
var _window_count := 0


func build(t: HarborTown, front: Vector3, yaw: float, variant: Dictionary) -> void:
	name = "FullHouse"
	for key: String in variant:
		set(key, variant[key])
	_setup(t, front, yaw, int(variant.get("seed", 1950)))
	if style == 2:
		_plan_gable_front()
	else:
		_plan_colonial()
	shell()
	_outer_walls()
	_trim()
	_roof()
	_chimney()
	_entry()
	detail()
	for room in rooms:
		_room(room)
	_stair(stair["x0"], stair["x1"], stair["z0"], stair["z1"], F, U, stair["rail_x"], c(OAK * 0.9, HarborTown.K_WOOD), c(TRIM, HarborTown.K_ENAMEL))
	_well_rail(stair["rail_x"], stair["z0"] + 0.1, stair["z1"], U, c(OAK * 0.9, HarborTown.K_WOOD), c(TRIM, HarborTown.K_ENAMEL))
	# A rail across the well's head, where the floor above ends over the
	# foot of the stair.
	var well: Rect2 = stair["void"]
	_box("wall", Vector3(well.position.x + well.size.x / 2.0, U + 0.9, well.end.y + 0.03), Vector3(well.size.x, 0.05, 0.07), c(OAK * 0.9, HarborTown.K_WOOD), true)
	_solid(Vector3(well.position.x + well.size.x / 2.0, U + 0.5, well.end.y + 0.03), Vector3(well.size.x, 1.0, 0.08))
	_window_units()
	detail()
	if style == 2:
		_furnish_gable_front()
	else:
		_furnish_colonial()
	_commit()


func record() -> Dictionary:
	return {"base": transform, "w": w, "d": d, "style": style, "door_x": door_x, "found": F,
		"front_xs": front_xs, "f1": F + 1.5, "chimney": transform * chimney_top, "water": true,
		"harbour_side": true, "thr": 0.3, "detailed": true, "step_z": step_z}


## ---- plans -------------------------------------------------------------------------

static func _room_def(name_: String, fl: int, x0: float, x1: float, z0: float, z1: float, finish: Color,
		floor_finish: Color) -> Dictionary:
	return {"name": name_, "floor": fl, "x0": x0, "x1": x1, "z0": z0, "z1": z1, "finish": finish, "floor_finish": floor_finish}


func _plan_colonial() -> void:
	w = 11.0
	d = 8.5
	pitch = deg_to_rad(33.0)
	ridge_x = true
	door_x = 0.0
	var oak := c(OAK, HarborTown.K_OAK)
	var lino := c(Color(0.55, 0.15, 0.12), HarborTown.K_LINO)
	var h := w / 2.0
	rooms = [
		_room_def("living", 1, 1.1, h, 0.0, -d, c(papers[0], HarborTown.K_PAPER), oak),
		_room_def("dining", 1, -h, -1.1, 0.0, -4.25, c(papers[1], HarborTown.K_PAPER), oak),
		_room_def("kitchen", 1, -h, -1.1, -4.25, -d, c(Color(0.92, 0.9, 0.78), HarborTown.K_ENAMEL), lino),
		_room_def("hall", 1, -1.1, 1.1, 0.0, -d, c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER), oak),
		_room_def("bed1", 2, -h, -1.1, 0.0, -4.25, c(papers[4], HarborTown.K_PAPER), oak),
		_room_def("bed2", 2, -h, -1.1, -4.25, -d, c(papers[5], HarborTown.K_PAPER), oak),
		_room_def("bed3", 2, 1.1, h, 0.0, -4.25, c(papers[2], HarborTown.K_PAPER), oak),
		_room_def("bed4", 2, 1.1, h, -4.25, -d, c(papers[3], HarborTown.K_PAPER), oak),
		_room_def("hall2", 2, -1.1, 1.1, 0.0, -6.4, c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER), oak),
		_room_def("bath", 2, -1.1, 1.1, -6.4, -d, c(Color(0.82, 0.9, 0.88), HarborTown.K_TILE), c(Color(0.08, 0.08, 0.08), HarborTown.K_LINO)),
	]
	stair = {"x0": -1.0, "x1": -0.15, "z0": -1.4, "z1": -5.4, "rail_x": -0.12, "void": Rect2(-1.1, -5.45, 1.0, 4.15)}
	var y1 := F + 1.5
	var y2 := U + 1.35
	front_xs = [-4.1, -2.1, 2.1, 4.1]
	for x in front_xs:
		windows.append({"wall": "front", "at": x, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
	for x: float in [-4.1, -2.1, 0.0, 2.1, 4.1]:
		windows.append({"wall": "front", "at": x, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	for side: String in ["left", "right"]:
		for z: float in [-2.1, -6.4]:
			windows.append({"wall": side, "at": z, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
			windows.append({"wall": side, "at": z, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	windows.append({"wall": "back", "at": -3.3, "y": F + 1.7, "w": 0.9, "h": 1.1, "floor": 1})
	windows.append({"wall": "back", "at": 3.3, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
	windows.append({"wall": "back", "at": -3.3, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	windows.append({"wall": "back", "at": 3.3, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	windows.append({"wall": "back", "at": 0.0, "y": U + 1.7, "w": 0.6, "h": 0.7, "floor": 2})
	outer_doors = [{"wall": "front", "at": 0.0, "w": 0.95}, {"wall": "back", "at": 0.4, "w": 0.85}]
	doors = [
		{"p": Vector2(1.1, -0.75), "axis": "z", "w": 0.9, "floor": 1},
		{"p": Vector2(1.1, -2.3), "axis": "z", "w": 1.2, "floor": 1},
		{"p": Vector2(-1.1, -0.75), "axis": "z", "w": 0.9, "floor": 1},
		{"p": Vector2(-3.3, -4.25), "axis": "x", "w": 0.9, "floor": 1},
		{"p": Vector2(-1.1, -6.9), "axis": "z", "w": 0.9, "floor": 1},
		{"p": Vector2(-1.1, -0.7), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(-1.1, -5.95), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(1.1, -2.5), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(1.1, -5.95), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(0.4, -6.4), "axis": "x", "w": 0.75, "floor": 2},
	]
	step_z = 1.5


func _plan_gable_front() -> void:
	w = 7.5
	d = 10.5
	pitch = deg_to_rad(40.0)
	ridge_x = false
	door_x = -2.15
	var oak := c(OAK, HarborTown.K_OAK)
	var h := w / 2.0
	rooms = [
		_room_def("hall", 1, -h, -1.35, 0.0, -7.4, c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER), oak),
		_room_def("parlor", 1, -1.35, h, 0.0, -4.6, c(papers[0], HarborTown.K_PAPER), oak),
		_room_def("dining", 1, -1.35, h, -4.6, -7.4, c(papers[1], HarborTown.K_PAPER), oak),
		_room_def("kitchen", 1, -h, h, -7.4, -d, c(Color(0.9, 0.92, 0.84), HarborTown.K_ENAMEL), c(Color(0.2, 0.3, 0.5), HarborTown.K_LINO)),
		_room_def("hall2", 2, -h, -1.35, 0.0, -6.6, c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER), oak),
		_room_def("bed1", 2, -1.35, h, 0.0, -4.6, c(papers[4], HarborTown.K_PAPER), oak),
		_room_def("bed2", 2, -1.35, h, -4.6, -d, c(papers[5], HarborTown.K_PAPER), oak),
		_room_def("bath", 2, -h, -1.35, -6.6, -d, c(Color(0.82, 0.9, 0.88), HarborTown.K_TILE), c(Color(0.08, 0.08, 0.08), HarborTown.K_LINO)),
	]
	stair = {"x0": -3.6, "x1": -2.8, "z0": -1.4, "z1": -5.4, "rail_x": -2.77, "void": Rect2(-3.75, -5.45, 1.0, 4.15)}
	var y1 := F + 1.5
	var y2 := U + 1.35
	front_xs = [0.2, 2.2]
	for x in front_xs:
		windows.append({"wall": "front", "at": x, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
	for x: float in [-2.15, 0.2, 2.2]:
		windows.append({"wall": "front", "at": x, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	windows.append({"wall": "front", "at": 0.0, "y": E + 1.1, "w": 0.7, "h": 0.9, "floor": 3})
	windows.append({"wall": "back", "at": 0.0, "y": E + 1.1, "w": 0.7, "h": 0.9, "floor": 3})
	for z: float in [-1.0, -3.6, -6.0, -9.0]:
		windows.append({"wall": "right", "at": z, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
	for z: float in [-1.0, -3.6, -6.0, -9.0]:
		windows.append({"wall": "right", "at": z, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	windows.append({"wall": "left", "at": -9.0, "y": y1, "w": 0.9, "h": 1.5, "floor": 1})
	windows.append({"wall": "left", "at": -3.4, "y": U + 0.2, "w": 0.7, "h": 1.0, "floor": 1})
	windows.append({"wall": "left", "at": -8.6, "y": U + 1.7, "w": 0.6, "h": 0.7, "floor": 2})
	windows.append({"wall": "back", "at": -1.5, "y": F + 1.7, "w": 0.9, "h": 1.1, "floor": 1})
	windows.append({"wall": "back", "at": 1.5, "y": y2, "w": 0.85, "h": 1.35, "floor": 2})
	outer_doors = [{"wall": "front", "at": door_x, "w": 0.95}, {"wall": "back", "at": 1.9, "w": 0.85}]
	doors = [
		{"p": Vector2(-1.35, -1.0), "axis": "z", "w": 1.2, "floor": 1},
		{"p": Vector2(-1.35, -6.2), "axis": "z", "w": 0.9, "floor": 1},
		{"p": Vector2(2.9, -4.6), "axis": "x", "w": 1.4, "floor": 1},
		{"p": Vector2(-2.55, -7.4), "axis": "x", "w": 0.9, "floor": 1},
		{"p": Vector2(2.0, -7.4), "axis": "x", "w": 0.9, "floor": 1},
		{"p": Vector2(-1.35, -2.2), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(-1.35, -5.95), "axis": "z", "w": 0.8, "floor": 2},
		{"p": Vector2(-2.3, -6.6), "axis": "x", "w": 0.75, "floor": 2},
	]
	step_z = 3.3


## ---- the shell ---------------------------------------------------------------------

func _gable_rise(p: Vector2) -> float:
	if ridge_x:
		var s := -p.y
		return E + minf(s, d - s) * tan(pitch)
	var xl := p.x + w / 2.0
	return E + minf(xl, w - xl) * tan(pitch)


## The outer walls: clapboard, cut round every window and door, up to the
## eaves on the eaves walls and to the roof's line on the gables.
func _outer_walls() -> void:
	var col := c(clap, clap_kind)
	var flat := func(_p: Vector2) -> float: return E
	var gable := func(p: Vector2) -> float: return _gable_rise(p)
	var h := w / 2.0
	for wall: String in ["front", "back", "left", "right"]:
		var line := _outer_line(wall)
		var p0: Vector2 = line[0]
		var p1: Vector2 = line[1]
		var gabled := (wall == "left" or wall == "right") == ridge_x
		var breaks: Array = [p0.distance_to(p1) / 2.0]
		_wall("wall", p0, p1, F - 0.1, gable if gabled else flat, _openings_on(wall, p0, p1), T_OUT, col, true, breaks)
	_box("wall", Vector3(0, -0.35, -d / 2.0), Vector3(w + 0.06, 1.7, d + 0.06), c(HarborTown.GRANITE, HarborTown.K_GRANITE))   # down into the ground; its top under the floors, or they flicker


## An outer wall's centre line, from its start to its end.
func _outer_line(wall: String) -> Array:
	var h := w / 2.0
	match wall:
		"front":
			return [Vector2(-h, -T_OUT / 2.0), Vector2(h, -T_OUT / 2.0)]
		"back":
			return [Vector2(-h, -d + T_OUT / 2.0), Vector2(h, -d + T_OUT / 2.0)]
		"left":
			return [Vector2(-h + T_OUT / 2.0, -T_OUT), Vector2(-h + T_OUT / 2.0, -d + T_OUT)]
	return [Vector2(h - T_OUT / 2.0, -T_OUT), Vector2(h - T_OUT / 2.0, -d + T_OUT)]


## The window and door openings on an outer wall, as metres along p0 to p1.
func _openings_on(wall: String, p0: Vector2, p1: Vector2, fl := 0) -> Array:
	var out: Array = []
	var dir := (p1 - p0).normalized()
	for win in windows:
		if win["wall"] != wall or (fl != 0 and int(win["floor"]) != fl):
			continue
		var p := _wall_point(wall, float(win["at"]))
		var a := (p - p0).dot(dir)
		out.append([a - float(win["w"]) / 2.0, a + float(win["w"]) / 2.0, float(win["y"]) - float(win["h"]) / 2.0, float(win["y"]) + float(win["h"]) / 2.0])
	for door in outer_doors:
		if door["wall"] != wall or (fl != 0 and fl != 1):
			continue
		var p := _wall_point(wall, float(door["at"]))
		var a := (p - p0).dot(dir)
		out.append([a - float(door["w"]) / 2.0, a + float(door["w"]) / 2.0, F - 0.1, F + 2.08])
	return out


func _wall_point(wall: String, at: float) -> Vector2:
	var h := w / 2.0
	match wall:
		"front":
			return Vector2(at, 0.0)
		"back":
			return Vector2(at, -d)
		"left":
			return Vector2(-h, at)
	return Vector2(h, at)


func _trim() -> void:
	var trim := c(TRIM, HarborTown.K_PAINT)
	var h := w / 2.0
	for sx: float in [-1.0, 1.0]:
		for z: float in [0.0, -d]:
			var off := Vector3(sx * (h - 0.06), 0, z + (0.03 if z == 0.0 else -0.03))
			_box("wall", off + Vector3(0, (F + E) / 2.0 - 0.05, 0), Vector3(0.14, E - F + 0.1, 0.08), trim)
			_box("wall", off + Vector3(sx * 0.03, (F + E) / 2.0 - 0.05, -0.04 if z == 0.0 else 0.04), Vector3(0.08, E - F + 0.1, 0.14), trim)
	for z: float in [0.02, -d - 0.02]:
		_box("wall", Vector3(0, F - 0.02, z), Vector3(w + 0.1, 0.16, 0.06), trim)
	for sx: float in [-1.0, 1.0]:
		_box("wall", Vector3(sx * (h + 0.02), F - 0.02, -d / 2.0), Vector3(0.06, 0.16, d + 0.1), trim)
	# The frieze under the eaves on the eaves walls.
	if ridge_x:
		for z: float in [0.02, -d - 0.02]:
			_box("wall", Vector3(0, E - 0.12, z), Vector3(w + 0.1, 0.22, 0.06), trim)
	else:
		for sx: float in [-1.0, 1.0]:
			_box("wall", Vector3(sx * (h + 0.02), E - 0.12, -d / 2.0), Vector3(0.06, 0.22, d + 0.1), trim)
	# A belt between the floors.
	for z: float in [0.02, -d - 0.02]:
		_box("wall", Vector3(0, U - 0.05, z), Vector3(w + 0.1, 0.1, 0.05), trim)


## The roof: two slopes to a ridge, shingled, solid underfoot and to
## the rain, a cap along the ridge.
func _roof() -> void:
	var shingle := c(roof, HarborTown.K_ROOF)
	var span := d if ridge_x else w
	var length := w if ridge_x else d
	var half := span / 2.0
	var over := 0.35
	var cosp := cos(pitch)
	var sinp := sin(pitch)
	for side: float in [-1.0, 1.0]:
		var n: Vector3
		var along: Vector3
		if ridge_x:
			n = Vector3(0, cosp, sinp * side)
			along = Vector3(1, 0, 0)
		else:
			n = Vector3(sinp * side, cosp, 0)
			along = Vector3(0, 0, 1)
		var s_mid := (half + 0.05 - over) / 2.0
		var y := E + s_mid * tan(pitch)
		var centre: Vector3
		if ridge_x:
			centre = Vector3(0, y, -s_mid if side > 0.0 else -d + s_mid)
		else:
			centre = Vector3(side * (half - s_mid), y, -d / 2.0)
		centre += n * 0.075
		var basis := Basis(along, n, along.cross(n))
		var size := Vector3(length + 2.0 * over * 0.8, 0.15, (half + 0.05 + over) / cosp)
		m.box("wall", Transform3D(basis, centre), size, shingle, true)
		_solid(centre, size, basis)
		var shelter := GPUParticlesCollisionBox3D.new()
		shelter.size = Vector3(size.x, 3.0, size.z + 0.2)
		shelter.transform = Transform3D(basis, centre - n * 1.5)
		add_child(shelter)
	var ridge_y := E + half * tan(pitch) + 0.16
	if ridge_x:
		_box("wall", Vector3(0, ridge_y, -d / 2.0), Vector3(w + 0.6, 0.08, 0.3), shingle)
	else:
		_box("wall", Vector3(0, ridge_y, -d / 2.0), Vector3(0.3, 0.08, d + 0.6), shingle)
	# The upstairs ceiling, the attic's floor.
	_box("wall", Vector3(0, E - 0.01, -d / 2.0), Vector3(w - 2.0 * T_OUT, 0.02, d - 2.0 * T_OUT), c(PLASTER, HarborTown.K_PLASTER))


## The chimney: up the outside of the fireplace wall, past the roof.
func _chimney() -> void:
	var brick := c(Color(0.52, 0.26, 0.19), HarborTown.K_BRICK)
	var x := w / 2.0
	var z := -d / 2.0 if style == 1 else -2.3
	var top := E + (d / 2.0 if ridge_x else w / 2.0) * tan(pitch) + 1.0
	if not ridge_x:
		top = E + 1.6
	_box("wall", Vector3(x + 0.38, 1.7, z), Vector3(0.76, 3.4, 1.6), brick, true)
	_box("wall", Vector3(x + 0.3, 3.5, z), Vector3(0.6, 0.3, 1.2), brick, true)
	_box("wall", Vector3(x + 0.3, (3.5 + top) / 2.0, z), Vector3(0.6, top - 3.5, 0.9), brick, true)
	_box("wall", Vector3(x + 0.3, top + 0.06, z), Vector3(0.72, 0.12, 1.02), c(Color(0.45, 0.44, 0.42), HarborTown.K_GRANITE))
	for k in 2:
		_box("iron", Vector3(x + 0.3, top + 0.3, z - 0.2 + 0.4 * k), Vector3(0.18, 0.4, 0.18), Color(0.45, 0.28, 0.2))
	chimney_top = Vector3(x + 0.3, top + 0.5, z)


## The way in: granite steps (a colonial) or the porch across the front
## (a gable-front house); the front door standing open, the back door
## shut on its stoop; slopes for the feet.
func _entry() -> void:
	var trim := c(TRIM, HarborTown.K_PAINT)
	var gran := c(HarborTown.GRANITE, HarborTown.K_GRANITE)
	for door in outer_doors:
		var front: bool = door["wall"] == "front"
		var at_x: float = door["at"]
		var z := 0.0 if front else -d
		var out := 1.0 if front else -1.0
		for s: float in [-1.0, 1.0]:
			_box("wall", Vector3(at_x + s * 0.58, F + 1.05, z + out * 0.05), Vector3(0.14, 2.1, 0.08), trim)
		_box("wall", Vector3(at_x, F + 2.18, z + out * 0.06), Vector3(1.4 if front else 1.1, 0.2, 0.1), trim)
		for s: float in [-1.0, 1.0]:
			_box("wall", Vector3(at_x + s * 0.485, F + 1.03, z - out * (T_OUT + T_IN) / 2.0), Vector3(0.02, 2.06, T_OUT + T_IN), c(TRIM, HarborTown.K_ENAMEL))
		_box("wall", Vector3(at_x, F - 0.02, z - out * 0.07), Vector3(float(door["w"]) + 0.05, 0.04, 0.16), c(OAK, HarborTown.K_WOOD))
		if front:
			var hinge := Vector3(at_x + 0.46, F, -T_OUT - T_IN)
			var leaf := Transform3D(Basis(Vector3.UP, -1.35), hinge)
			var dc := c(door_color, HarborTown.K_PAINT)
			m.box("wall", leaf * HarborTown.at(Vector3(-0.46, 1.02, -0.025)), Vector3(0.92, 2.04, 0.045), dc, true)
			for k in 2:
				for s: float in [-1.0, 1.0]:
					m.box("wall", leaf * HarborTown.at(Vector3(-0.46 + s * 0.2, 0.45 + 0.7 * k, 0.003)), Vector3(0.28, 0.55, 0.02), c(door_color * 0.85, HarborTown.K_PAINT), true)
			m.sphere("iron", leaf * HarborTown.at(Vector3(-0.84, 1.0, 0.04)), 0.03, 8, Color(0.72, 0.58, 0.25))
			_lamp_fixture(Vector3(at_x + 0.85, F + 1.9, 0.12), "porch", 0.35, 0.5)
		else:
			_box("wall", Vector3(at_x, F + 1.0, z + 0.04), Vector3(0.84, 2.02, 0.045), c(Color(0.25, 0.38, 0.30), HarborTown.K_PAINT), true)
			m.quad("clear", Vector3(at_x - 0.3, F + 1.2, z - 0.07), Vector3(at_x - 0.3, F + 1.85, z - 0.07), Vector3(at_x + 0.3, F + 1.85, z - 0.07),
				Vector3(at_x + 0.3, F + 1.2, z - 0.07), Vector3(0, 0, -1), Color.WHITE)
			_box("wall", Vector3(at_x, F / 2.0 - 0.03, z - 0.45), Vector3(1.3, F, 0.9), gran, true)
	if style == 2:
		# The porch: floor, skirt, posts, a rail round it but for the
		# steps, a roof sloping off the front wall, steps down to the walk.
		var h := w / 2.0
		var deck := c(Color(0.50, 0.46, 0.40), HarborTown.K_PLANK)
		_box("wall", Vector3(0, F - 0.05, 1.2), Vector3(w, 0.2, 2.4), deck, true)
		_box("wall", Vector3(0, (F - 0.15) / 2.0, 2.38), Vector3(w, F - 0.15, 0.04), c(TRIM, HarborTown.K_PAINT))
		for k in 4:
			var px := -h + 0.15 + (w - 0.3) * k / 3.0
			_box("wall", Vector3(px, F + 1.4, 2.3), Vector3(0.14, 2.8, 0.14), trim, true)
		var roof_slab := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12.0)), Vector3(0, F + 2.95, 1.2))
		m.box("wall", roof_slab, Vector3(w + 0.3, 0.1, 2.9), c(roof, HarborTown.K_ROOF), true)
		_solid(roof_slab.origin, Vector3(w + 0.3, 0.1, 2.9), roof_slab.basis)
		_box("wall", Vector3(0, F + 2.75, 1.2), Vector3(w, 0.02, 2.4), c(PLASTER, HarborTown.K_PLASTER))
		for seg: Vector2 in [Vector2(-h + 0.2, door_x - 0.7), Vector2(door_x + 0.7, h - 0.2)]:
			var mid := (seg.x + seg.y) / 2.0
			_box("wall", Vector3(mid, F + 0.9, 2.3), Vector3(seg.y - seg.x, 0.07, 0.07), trim, true)
			_box("wall", Vector3(mid, F + 0.12, 2.3), Vector3(seg.y - seg.x, 0.05, 0.05), trim)
			var n := int((seg.y - seg.x) / 0.14)
			for k in n:
				_box("wall", Vector3(seg.x + (k + 0.5) * (seg.y - seg.x) / n, F + 0.5, 2.3), Vector3(0.04, 0.76, 0.04), trim)
			_solid(Vector3(mid, F + 0.5, 2.3), Vector3(seg.y - seg.x, 1.0, 0.1))
		for k in 3:
			_box("wall", Vector3(door_x, 0.1 + 0.18 * k, 3.05 - 0.28 * k), Vector3(1.3, 0.2, 0.3), deck)
		_ramp(Vector3(door_x, 0.0, 3.4), Vector3(door_x, F, 2.3), 1.2)
	else:
		for k in 3:
			_box("wall", Vector3(door_x, 0.1 + 0.2 * k, 0.9 - 0.3 * k), Vector3(1.8, 0.2, 0.62), gran)
		_ramp(Vector3(door_x, 0.0, 1.35), Vector3(door_x, F, 0.0), 1.6)
	for door in outer_doors:
		if door["wall"] == "back":
			_ramp(Vector3(float(door["at"]), 0.0, -d - 1.3), Vector3(float(door["at"]), F, -d - 0.1), 1.1)


## ---- rooms -------------------------------------------------------------------------

## A room: its four faces with their doors and windows, the floor, the
## ceiling; round a stairwell the floor above and the ceiling below
## leave the well open.
func _room(room: Dictionary) -> void:
	var fl: int = room["floor"]
	var y0 := F if fl == 1 else U
	var top := C1 - 0.01 if fl == 1 else E - 0.02
	var h := w / 2.0
	var xi := h - T_OUT
	var x0 := maxf(float(room["x0"]), -xi)
	var x1 := minf(float(room["x1"]), xi)
	var z0 := minf(float(room["z0"]), -T_OUT)
	var z1 := maxf(float(room["z1"]), -d + T_OUT)
	var finish: Color = room["finish"]
	var flat := func(_p: Vector2) -> float: return top
	# The four edges, each drawn just inside the room.
	var edges: Array = [
		[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1), absf(float(room["z0"])) < 0.01, "front"],
		[Vector2(x1, z1), Vector2(x0, z1), Vector2(0, 1), absf(float(room["z1"]) + d) < 0.01, "back"],
		[Vector2(x0, z1), Vector2(x0, z0), Vector2(1, 0), absf(float(room["x0"]) + h) < 0.01, "left"],
		[Vector2(x1, z0), Vector2(x1, z1), Vector2(-1, 0), absf(float(room["x1"]) - h) < 0.01, "right"],
	]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var outer: bool = e[3]
		var inset := T_IN / 2.0 if outer else 0.025
		var pa := a + inward * inset
		var pb := b + inward * inset
		var dir := (pb - pa).normalized()
		var openings: Array = []
		if outer:
			for o: Array in _openings_on(e[4], pa, pb, fl):
				openings.append(o)
		for door in doors:
			if int(door["floor"]) != fl:
				continue
			var p: Vector2 = door["p"]
			var on_line := absf((p - a).cross(dir)) < 0.05
			var along := (p - pa).dot(dir)
			if on_line and along > 0.0 and along < pa.distance_to(pb):
				openings.append([along - float(door["w"]) / 2.0, along + float(door["w"]) / 2.0, y0, y0 + 2.1])
				_casing(pa + dir * along, dir, inward, float(door["w"]), y0)
		_wall("wall", pa, pb, y0, flat, openings, 0.05 if not outer else T_IN, finish, not outer)
		# A baseboard along the face, broken at the doors.
		var base_col := c(TRIM, HarborTown.K_ENAMEL)
		var cuts: Array = []
		for o: Array in openings:
			if float(o[2]) <= y0 + 0.01:
				cuts.append([o[0], o[1], y0 + 0.15, y0 + 0.15])
		_wall("wall", pa + inward * 0.03, pb + inward * 0.03, y0, func(_p: Vector2) -> float: return y0 + 0.14, cuts, 0.015, base_col)
	# The floor and the ceiling, round the stairwell.
	var rect := Rect2(x0, z1, x1 - x0, z0 - z1)
	var void_: Rect2 = stair["void"]
	var floor_rects: Array[Rect2] = [rect]
	var ceil_rects: Array[Rect2] = [rect]
	if fl == 2:
		floor_rects = _minus(rect, void_)
	else:
		ceil_rects = _minus(rect, void_)
	for r in floor_rects:
		_box("wall", Vector3(r.position.x + r.size.x / 2.0, y0 - 0.05, r.position.y + r.size.y / 2.0), Vector3(r.size.x, 0.1, r.size.y), room["floor_finish"], true)
	if fl == 1:
		for r in ceil_rects:
			_box("wall", Vector3(r.position.x + r.size.x / 2.0, top + 0.01, r.position.y + r.size.y / 2.0), Vector3(r.size.x, 0.02, r.size.y), c(PLASTER, HarborTown.K_PLASTER))


## A door's casing on a room's face: head and jambs.
func _casing(p: Vector2, dir: Vector2, inward: Vector2, width: float, y0: float) -> void:
	var keep := m
	detail()
	var trim := c(TRIM, HarborTown.K_ENAMEL)
	var o := inward * 0.03
	for s: float in [-1.0, 1.0]:
		var j := p + dir * s * (width / 2.0 + 0.05) + o
		_slab("wall", j - dir * 0.05, j + dir * 0.05, y0, y0 + 2.18, y0 + 2.18, 0.02, trim)
	_slab("wall", p - dir * (width / 2.0 + 0.1) + o, p + dir * (width / 2.0 + 0.1) + o, y0 + 2.1, y0 + 2.22, y0 + 2.22, 0.02, trim)
	m = keep


## A rectangle less a hole, as up to four rectangles.
static func _minus(r: Rect2, v: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var cut := r.intersection(v)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		out.append(r)
		return out
	if cut.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, cut.position.y - r.position.y))
	if cut.end.y < r.end.y:
		out.append(Rect2(r.position.x, cut.end.y, r.size.x, r.end.y - cut.end.y))
	if cut.position.x > r.position.x:
		out.append(Rect2(r.position.x, cut.position.y, cut.position.x - r.position.x, cut.size.y))
	if cut.end.x < r.end.x:
		out.append(Rect2(cut.end.x, cut.position.y, r.end.x - cut.end.x, cut.size.y))
	return out


## Every window's unit: casing, sashes, curtains, a radiator downstairs.
func _window_units() -> void:
	for win in windows:
		var wall: String = win["wall"]
		var at: float = win["at"]
		var yaw := 0.0
		var centre: Vector3
		match wall:
			"front":
				centre = Vector3(at, win["y"], 0.0)
			"back":
				centre = Vector3(at, win["y"], -d)
				yaw = PI
			"left":
				centre = Vector3(-w / 2.0, win["y"], at)
				yaw = -PI / 2.0
			_:
				centre = Vector3(w / 2.0, win["y"], at)
				yaw = PI / 2.0
		_window_count += 1
		var fl: int = win["floor"]
		var curtain: Variant = curtains if fl < 3 else null
		if fl == 2:
			curtain = curtains.lightened(0.12)
		_window_unit(centre, win["w"], win["h"], yaw, wall == "front" and fl < 3, T_OUT + T_IN, curtain,
			open_windows.has(_window_count), fl == 1, shutter)


## ---- furnishing ----------------------------------------------------------------------

func _furnish_colonial() -> void:
	var h := w / 2.0
	var xi := h - T_OUT - T_IN
	var zb := -d + T_OUT + T_IN
	var cl := c(cloth, HarborTown.K_CLOTH)
	var wd := wood
	# The living room: the fire on the end wall, the sofa facing it, the
	# chairs, a rug, the radio, a bookcase, the lamps, pictures, a clock.
	_fireplace(Vector3(xi, F, -d / 2.0), -PI / 2.0, Color(0.55, 0.28, 0.20), wd)
	_rug(Vector3(3.6, F, -d / 2.0), Vector2(2.6, 3.4), cloth.darkened(0.2), Color(0.7, 0.62, 0.45))
	_sofa(Vector3(1.75, F, -d / 2.0), PI / 2.0, 2.1, cl, c(wd, HarborTown.K_WOOD))
	for s: float in [-1.0, 1.0]:
		_armchair(Vector3(3.9, F, -d / 2.0 + s * 1.55), -PI / 2.0 + s * 0.6, c(Color(0.62, 0.52, 0.35), HarborTown.K_CLOTH))
	_table(Vector3(3.0, F, -d / 2.0), Vector2(0.55, 1.0), 0.42, c(wd, HarborTown.K_WOOD))
	_box("wall", Vector3(3.0, F + 0.44, -d / 2.0 + 0.2), Vector3(0.22, 0.03, 0.3), c(Color(0.85, 0.82, 0.72), HarborTown.K_ENAMEL))
	_radio(Vector3(2.2, F, zb + 0.22), 0.0)
	_bookcase(Vector3(4.3, F, zb + 0.17), 0.0, 1.0, 1.9, wd)
	var lamp := Vector3(1.6, F, -d / 2.0 - 1.35)
	m.cylinder("iron", HarborTown.at(lamp + Vector3(0, 0.02, 0)), 0.16, 0.18, 0.04, 12, Color(0.55, 0.45, 0.25))
	m.cylinder("iron", HarborTown.at(lamp + Vector3(0, 0.75, 0)), 0.015, 0.015, 1.45, 6, Color(0.55, 0.45, 0.25))
	_lamp_fixture(lamp + Vector3(0, 1.55, 0), "shade", 0.28, 0.8, 6.0)
	_picture(Vector3(1.1 + 0.08, F + 1.7, -d / 2.0), PI / 2.0, Vector2(0.9, 0.6), Color(0.3, 0.42, 0.52))
	_wall_clock(Vector3(1.1 + 0.08, F + 2.3, -1.9), PI / 2.0)
	_lamp_fixture(Vector3(3.3, C1 - 0.12, -d / 2.0), "ceiling", 0.6, 0.6, 6.0)
	_newspaper(Vector3(3.95, F + 0.49, -d / 2.0 + 1.5), 0.4)
	_cup(Vector3(3.0, F + 0.42, -d / 2.0 - 0.25))
	_knitting(Vector3(4.2, F, -d / 2.0 - 2.2))
	_book(Vector3(1.75, F + 0.52, -d / 2.0 + 0.8), 0.3, true, Color(0.2, 0.3, 0.5))
	if _rng.randf() < 0.7:
		_dog(Vector3(3.95, F, -d / 2.0 + 0.1), -PI / 2.0, [Color(0.55, 0.38, 0.2), Color(0.12, 0.1, 0.09), Color(0.85, 0.8, 0.7)][_rng.randi() % 3])
	# The dining room.
	_dining_set(Vector3(-3.3, F, -2.1), wd, Color(0.93, 0.92, 0.88) if _rng.randf() < 0.5 else null)
	_lamp_fixture(Vector3(-3.3, C1 - 0.95, -2.1), "pendant", 0.33, 0.9, 5.0)
	_box("wall", Vector3(-xi + 0.25, F + 0.45, -2.1), Vector3(0.5, 0.9, 1.4), c(wd, HarborTown.K_WOOD), true)
	_vase(Vector3(-xi + 0.25, F + 0.9, -1.8), Color(0.85, 0.55, 0.12))
	_picture(Vector3(-4.6, F + 1.7, -4.25 + 0.08), 0.0, Vector2(0.7, 0.5), Color(0.6, 0.45, 0.3))
	_rug(Vector3(-3.3, F, -2.1), Vector2(2.4, 2.0), Color(0.45, 0.2, 0.2), Color(0.6, 0.5, 0.35))
	# The kitchen.
	_sink_counter(Vector3(-3.3, F, zb + 0.3), 0.0, 1.9, Color(0.88, 0.9, 0.8), Color(0.25, 0.45, 0.35))
	_wall_cabinets(Vector3(-4.6, F + 1.85, zb + 0.18), 0.0, 0.75, Color(0.88, 0.9, 0.8))
	_range(Vector3(-xi + 0.34, F, -5.1), PI / 2.0)
	_fridge(Vector3(-1.5, F, zb + 0.4), 0.0)
	_kitchen_table(Vector3(-3.0, F, -5.3), Color(0.7, 0.12, 0.1), Color(0.8, 0.8, 0.72))
	_wall_clock(Vector3(-3.3, F + 2.2, -4.25 - 0.08), PI)
	_lamp_fixture(Vector3(-3.3, C1 - 0.12, -6.3), "ceiling", 0.25, 0.9, 6.0)
	_pie(Vector3(-4.0, F + 0.9, zb + 0.3))
	_bread(Vector3(-2.8, F + 0.77, -5.4), 0.3)
	_apron(Vector3(-1.1 - 0.05, F + 1.5, -5.4), -PI / 2.0, Color(0.85, 0.75, 0.55))
	if _rng.randf() < 0.6:
		YardProps.cat(m, HarborTown.at(Vector3(-3.1, F + 1.15, zb + 0.06), 0.0), Color(0.12, 0.1, 0.09))
	# The hall: runner, telephone table, coat hooks, a light.
	_box("wall", Vector3(0.5, F + 0.005, -3.5), Vector3(0.7, 0.01, 5.0), c(Color(0.45, 0.18, 0.15), HarborTown.K_CLOTH))
	_table(Vector3(0.8, F, -4.6), Vector2(0.4, 0.7), 0.78, c(wd, HarborTown.K_WOOD))
	_telephone(Vector3(0.8, F + 0.78, -4.5))
	for k in 3:
		_box("iron", Vector3(0.93, F + 1.7, -7.0 - 0.25 * k), Vector3(0.05, 0.03, 0.03), Color(0.6, 0.5, 0.3))
	_box("wall", Vector3(0.88, F + 1.35, -7.3), Vector3(0.12, 0.7, 0.45), c(Color(0.3, 0.32, 0.4), HarborTown.K_CLOTH))
	_lamp_fixture(Vector3(0.45, C1 - 0.12, -1.0), "ceiling", 0.45, 0.5, 5.0)
	_hat(Vector3(0.93, F + 1.74, -7.0))
	_shoes(Vector3(-0.55, F, -0.5), PI / 2.0, Color(0.3, 0.18, 0.1))
	_shoes(Vector3(-0.55, F, -0.85), PI / 2.0, Color(0.15, 0.12, 0.1))
	_lamp_fixture(Vector3(0.45, E - 0.14, -5.9), "ceiling", 0.5, 0.4, 5.0)
	# Upstairs: the bedrooms and the bath.
	_bed(Vector3(-3.3, U, -2.8), PI, Vector2(1.4, 2.0), c(Color(0.62, 0.25, 0.28), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_nightstand(Vector3(-4.35, U, -2.0), 0.0, wd, 0.5)
	_dresser(Vector3(-xi + 0.3, U, -3.5), PI / 2.0, wd)
	_rug(Vector3(-3.3, U, -2.4), Vector2(2.0, 1.6), Color(0.35, 0.45, 0.55), Color(0.8, 0.78, 0.7))
	_lamp_fixture(Vector3(-3.3, E - 0.14, -2.1), "ceiling", 0.62, 0.4, 5.0)
	_bed(Vector3(-4.4, U, -6.2), PI / 2.0, Vector2(0.95, 1.9), c(Color(0.3, 0.38, 0.55), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_table(Vector3(-2.2, U, -7.9), Vector2(1.0, 0.5), 0.74, c(wd, HarborTown.K_WOOD))
	_chair(Vector3(-2.2, U, -7.3), PI, c(wd, HarborTown.K_WOOD))
	_lamp_fixture(Vector3(-1.9, U + 1.05, -7.95), "shade", 0.45, 0.35, 3.5)
	_toy_chest(Vector3(-3.3, U, -4.6), 0.0)
	_model_plane(Vector3(-3.3, E - 0.5, -6.3))
	_toys(Vector3(-3.3, U, -6.0))
	_bed(Vector3(3.3, U, -2.8), PI, Vector2(1.4, 2.0), c(Color(0.85, 0.82, 0.7), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_nightstand(Vector3(2.3, U, -2.0), 0.0, wd, 0.55)
	_dresser(Vector3(xi - 0.3, U, -3.5), -PI / 2.0, wd)
	_rocker_inside(Vector3(4.5, U, -0.8), PI + 0.5)
	_sewing_machine(Vector3(1.8, U, -0.5), PI)
	_bed(Vector3(3.8, U, -6.6), PI / 2.0, Vector2(0.95, 1.9), c(Color(0.55, 0.5, 0.3), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_dresser(Vector3(2.0, U, -4.6), PI, wd)
	_bath_fixtures(Vector3(0.0, U, zb + 0.4), 0.0, Vector3(-0.8, U, -7.0), PI / 2.0, Vector3(0.75, U, -6.95), -PI / 2.0)
	_lamp_fixture(Vector3(0, E - 0.14, -7.4), "ceiling", 0.55, 0.4, 3.5)
	_toothbrushes(Vector3(-0.8, U + 0.9, -7.0))


func _furnish_gable_front() -> void:
	var h := w / 2.0
	var xi := h - T_OUT - T_IN
	var zb := -d + T_OUT + T_IN
	var cl := c(cloth, HarborTown.K_CLOTH)
	var wd := wood
	# The parlour: the fire on the side wall, the piano, the sofa and a
	# chair, a lamp; lace at the windows.
	_fireplace(Vector3(xi, F, -2.3), -PI / 2.0, Color(0.5, 0.26, 0.2), wd)
	_rug(Vector3(1.2, F, -2.3), Vector2(2.4, 3.0), Color(0.3, 0.35, 0.5), Color(0.7, 0.6, 0.45))
	_sofa(Vector3(-0.8, F, -2.7), PI / 2.0, 2.0, cl, c(wd, HarborTown.K_WOOD))
	_armchair(Vector3(2.4, F, -0.8), PI + 0.4, c(Color(0.55, 0.48, 0.32), HarborTown.K_CLOTH))
	_piano(Vector3(0.9, F, -4.6 + 0.35), 0.0)
	var lamp := Vector3(-0.8, F, -0.7)
	m.cylinder("iron", HarborTown.at(lamp + Vector3(0, 0.75, 0)), 0.015, 0.015, 1.45, 6, Color(0.55, 0.45, 0.25))
	m.cylinder("iron", HarborTown.at(lamp + Vector3(0, 0.02, 0)), 0.16, 0.18, 0.04, 12, Color(0.55, 0.45, 0.25))
	_lamp_fixture(lamp + Vector3(0, 1.55, 0), "shade", 0.3, 0.8, 6.0)
	_wall_clock(Vector3(1.0, F + 2.3, -4.6 + 0.08), 0.0)
	_lamp_fixture(Vector3(1.2, C1 - 0.12, -2.3), "ceiling", 0.6, 0.6, 6.0)
	_newspaper(Vector3(2.4, F + 0.49, -0.8), 0.8)
	_knitting(Vector3(-0.8, F, -1.3))
	_book(Vector3(-0.8, F + 0.52, -3.2), 1.2, true, Color(0.5, 0.2, 0.15))
	_table(Vector3(0.4, F, -2.5), Vector2(0.5, 0.9), 0.42, c(wd, HarborTown.K_WOOD))
	_cup(Vector3(0.4, F + 0.42, -2.3))
	if _rng.randf() < 0.7:
		_dog(Vector3(2.0, F, -2.3), -PI / 2.0, [Color(0.55, 0.38, 0.2), Color(0.12, 0.1, 0.09), Color(0.85, 0.8, 0.7)][_rng.randi() % 3])
	# The dining room.
	_dining_set(Vector3(1.2, F, -6.0), wd, Color(0.93, 0.92, 0.88))
	_lamp_fixture(Vector3(1.2, C1 - 0.95, -6.0), "pendant", 0.33, 0.9, 5.0)
	_box("wall", Vector3(xi - 0.25, F + 0.45, -6.0), Vector3(0.5, 0.9, 1.3), c(wd, HarborTown.K_WOOD), true)
	_vase(Vector3(xi - 0.25, F + 0.9, -5.8), Color(0.75, 0.2, 0.2))
	# The kitchen across the back.
	_sink_counter(Vector3(-1.5, F, zb + 0.3), 0.0, 1.9, Color(0.88, 0.86, 0.72), Color(0.6, 0.15, 0.12))
	_wall_cabinets(Vector3(-2.8, F + 1.85, zb + 0.18), 0.0, 0.75, Color(0.88, 0.86, 0.72))
	_range(Vector3(xi - 0.34, F, -8.0), -PI / 2.0)
	_fridge(Vector3(-xi + 0.36, F, -7.9), PI / 2.0)
	_kitchen_table(Vector3(0.6, F, -8.8), Color(0.25, 0.45, 0.6), Color(0.85, 0.85, 0.75))
	_lamp_fixture(Vector3(0.0, C1 - 0.12, -8.9), "ceiling", 0.25, 0.9, 6.0)
	_pie(Vector3(-0.6, F + 0.9, zb + 0.3))
	_bread(Vector3(0.8, F + 0.77, -8.9), 0.3)
	_apron(Vector3(-xi + 0.01, F + 1.5, -8.2), PI / 2.0, Color(0.7, 0.3, 0.3))
	if _rng.randf() < 0.6:
		YardProps.cat(m, HarborTown.at(Vector3(-1.3, F + 1.15, zb + 0.06), 0.0), Color(0.7, 0.45, 0.2))
	# The hall.
	_box("wall", Vector3(-2.0, F + 0.005, -3.8), Vector3(0.6, 0.01, 5.5), c(Color(0.45, 0.18, 0.15), HarborTown.K_CLOTH))
	_table(Vector3(-1.6, F, -4.8), Vector2(0.4, 0.6), 0.78, c(wd, HarborTown.K_WOOD))
	_telephone(Vector3(-1.6, F + 0.78, -4.7))
	_lamp_fixture(Vector3(-2.0, C1 - 0.12, -1.0), "ceiling", 0.45, 0.5, 5.0)
	_shoes(Vector3(-2.55, F, -0.55), -PI / 2.0, Color(0.3, 0.18, 0.1))
	_hat(Vector3(-1.6, F + 0.82, -4.95))
	_lamp_fixture(Vector3(-2.0, E - 0.14, -6.0), "ceiling", 0.5, 0.4, 5.0)
	# Upstairs.
	_bed(Vector3(1.2, U, -3.5), 0.0, Vector2(1.4, 2.0), c(Color(0.5, 0.55, 0.62), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_nightstand(Vector3(2.4, U, -4.2), 0.0, wd, 0.55)
	_dresser(Vector3(xi - 0.3, U, -2.3), -PI / 2.0, wd)
	_rocker_inside(Vector3(-0.6, U, -0.8), PI - 0.4)
	_sewing_machine(Vector3(-0.7, U, -3.8), PI / 2.0)
	_lamp_fixture(Vector3(1.2, E - 0.14, -2.3), "ceiling", 0.62, 0.4, 5.0)
	_bed(Vector3(0.3, U, -8.9), 0.0, Vector2(0.95, 1.9), c(Color(0.62, 0.3, 0.2), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_bed(Vector3(2.8, U, -8.9), 0.0, Vector2(0.95, 1.9), c(Color(0.3, 0.45, 0.3), HarborTown.K_CLOTH), c(wd, HarborTown.K_WOOD))
	_toy_chest(Vector3(1.85, U, -6.2), PI)
	_dresser(Vector3(-0.9, U, -8.0), PI / 2.0, wd)
	_model_plane(Vector3(1.8, E - 0.5, -7.5))
	_toys(Vector3(1.5, U, -7.2))
	_lamp_fixture(Vector3(1.2, E - 0.14, -7.5), "ceiling", 0.5, 0.4, 5.0)
	_bath_fixtures(Vector3(-2.5, U, zb + 0.4), 0.0, Vector3(-3.45, U, -7.3), PI / 2.0, Vector3(-1.6, U, -8.4), -PI / 2.0)
	_lamp_fixture(Vector3(-2.5, E - 0.14, -8.4), "ceiling", 0.55, 0.4, 3.5)
	_toothbrushes(Vector3(-3.45, U + 0.9, -7.3))


## The candlestick telephone on its table.
func _telephone(at_: Vector3) -> void:
	m.cylinder("iron", HarborTown.at(at_ + Vector3(0, 0.02, 0)), 0.06, 0.07, 0.04, 12, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", HarborTown.at(at_ + Vector3(0, 0.17, 0)), 0.015, 0.015, 0.3, 6, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), at_ + Vector3(0, 0.33, 0.02)), 0.03, 0.025, 0.05, 10, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), at_ + Vector3(0.06, 0.22, 0)), 0.02, 0.025, 0.08, 8, Color(0.05, 0.05, 0.05))


## A toy chest with a ball and a teddy on it.
func _toy_chest(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.25, 0)), Vector3(0.8, 0.5, 0.45), c(Color(0.35, 0.5, 0.65), HarborTown.K_PAINT), true)
	_solid(xf * Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.45), xf.basis)
	m.sphere("wall", xf * HarborTown.at(Vector3(-0.2, 0.6, 0)), 0.1, 10, c(Color(0.8, 0.2, 0.15), HarborTown.K_ENAMEL))
	var bear := xf * HarborTown.at(Vector3(0.2, 0.5, 0))
	m.sphere("wall", bear * Transform3D(Basis.from_scale(Vector3(1, 1.2, 0.9)), Vector3(0, 0.1, 0)), 0.09, 8, c(Color(0.6, 0.42, 0.25), HarborTown.K_CLOTH))
	m.sphere("wall", bear * HarborTown.at(Vector3(0, 0.25, 0.01)), 0.065, 8, c(Color(0.6, 0.42, 0.25), HarborTown.K_CLOTH))
	for s: float in [-1.0, 1.0]:
		m.sphere("wall", bear * HarborTown.at(Vector3(s * 0.05, 0.31, 0)), 0.025, 6, c(Color(0.55, 0.38, 0.22), HarborTown.K_CLOTH))


## A model aeroplane hung from the ceiling on a thread.
func _model_plane(at_: Vector3) -> void:
	m.bar("iron", at_ + Vector3(0, 0.1, 0), at_ + Vector3(0, 0.45, 0), 0.003, 3, Color(0.8, 0.8, 0.8))
	_box("wall", at_, Vector3(0.5, 0.06, 0.07), c(Color(0.75, 0.62, 0.2), HarborTown.K_ENAMEL))
	_box("wall", at_ + Vector3(0.05, 0.01, 0), Vector3(0.1, 0.012, 0.6), c(Color(0.75, 0.62, 0.2), HarborTown.K_ENAMEL))
	_box("wall", at_ + Vector3(-0.22, 0.05, 0), Vector3(0.06, 0.1, 0.012), c(Color(0.62, 0.1, 0.08), HarborTown.K_ENAMEL))


## A rocking chair in a bedroom corner, a shawl over its arm.
func _rocker_inside(at_: Vector3, yaw: float) -> void:
	YardProps.rocker(m, HarborTown.at(at_, yaw), Color(0.4, 0.25, 0.14))
	m.box("wall", HarborTown.at(at_, yaw) * HarborTown.at(Vector3(0.25, 0.62, 0.05)), Vector3(0.08, 0.3, 0.4), c(Color(0.55, 0.3, 0.45), HarborTown.K_CLOTH), true)
