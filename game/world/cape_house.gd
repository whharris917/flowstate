class_name CapeHouse
extends HouseBase
## One house in the town modelled whole, inside and out: a Cape Cod of
## the 1930s on Water Street, its back to the harbour. A storey and a
## half under a 45-degree roof, pale yellow clapboard and white trim,
## black-green shutters, a red door, two gabled dormers on the front, a
## brick chimney up the west gable end.
##
## Inside, a centre hall and a steep straight stair; the living room to
## the west with a fire in the fireplace, a sofa and armchairs, a
## console radio, a bookcase, a floor lamp; the dining room and the
## kitchen to the east, the kitchen with its enamel range, a monitor-top
## refrigerator, a sink under the back window; a bath behind the hall
## with a clawfoot tub. Upstairs, two bedrooms under the slopes, each
## with its dormer and its gable windows. Every room lights at its own
## time as it gets dark; the fire burns from dusk.
##
## The walls are built as slabs round their openings, clapboard outside
## and plaster or paper inside, so the rooms are seen through the
## windows from the street and the street from the rooms. Art only: no
## records. The player walks in by the front door and up the stair.
##
## The house's frame: its front face on z = 0 facing +z, x across the
## front from -5 to 5, the back face at z = -8; the first floor's top
## at F, the walls' top at E, the upstairs floor's top at U.

const W := 10.0
const D := 8.0
const F := 0.6
const E := 3.2
const U := 3.3
const KNEE := 1.3            # knee walls stand this far in from the eaves
const PLASTER_UNDER := 0.07  # the sloped ceilings hang this far under the rafters
const COLLAR := 5.5          # the flat ceiling upstairs
const STAIR_X := Vector2(-0.95, -0.1)
const STAIR_Z := Vector2(-1.0, -4.2)
const DORMERS: Array[float] = [-2.4, 2.4]
const DORMER_HALF := 0.75
const DORMER_FACE := 0.45    # the dormers' faces stand this far back from the eaves
const DORMER_EAVE := 5.35

# The house's colours and furnishings: number 14's by default; another
# Cape on the street passes its own (build's variant).
var CLAP := Color(0.90, 0.82, 0.55)
var SHUTTER := Color(0.10, 0.16, 0.12)
var DOOR := Color(0.50, 0.09, 0.08)
var ROOF := Color(0.24, 0.27, 0.25)
var paper_living := Color(0.62, 0.70, 0.58)
var paper_dining := Color(0.80, 0.62, 0.58)
var kitchen_paint := Color(0.92, 0.88, 0.66)
var paper_bed := Color(0.86, 0.84, 0.90)
var paper_bed2 := Color(0.88, 0.84, 0.70)
var sofa_cloth := Color(0.32, 0.40, 0.30)
var chair_cloth := Color(0.62, 0.48, 0.30)
var quilt := Color(0.62, 0.25, 0.28)
var quilt2 := Color(0.3, 0.38, 0.55)
var curtains := Color(0.85, 0.82, 0.72)
var number := "14"
var with_yard := true
var open_windows: Array[int] = []
var _window_count := 0


func build(t: HarborTown, front: Vector3, yaw: float, variant: Dictionary = {}) -> void:
	name = "CapeHouse"
	for key: String in variant:
		set(key, variant[key])
	_setup(t, front, yaw, int(variant.get("seed", 1938)))
	shell()
	_shell()
	_roof()
	_dormers()
	_chimney()
	_openings()
	detail()
	_floors()
	_cape_stair()
	_partitions()
	_living_room()
	_dining_room()
	_kitchen()
	_hall()
	_bath()
	_bedrooms()
	if with_yard:
		_yard()
	_commit()


## What the street's dressing needs to know of this house.
func record() -> Dictionary:
	return {"base": transform, "w": W, "d": D, "style": 0, "door_x": 0.0, "found": F,
		"front_xs": [-3.4, -1.8, 1.8, 3.4], "f1": F + 1.475, "chimney": transform * Vector3(-5.3, 8.7, -4.0),
		"water": true, "harbour_side": true, "thr": 0.3, "detailed": true, "step_z": 1.45}


## ---- helpers -----------------------------------------------------------------

## Height of the roof's underside over a point s metres in from the
## nearer eaves wall.
static func rafter(s: float) -> float:
	return E + s


## The upstairs ceiling over a point s metres in from the front wall:
## the sloped plaster between the knee walls and the collar, flat
## between.
static func ceiling(s: float) -> float:
	var near := minf(s, D - s)
	return minf(rafter(near) - PLASTER_UNDER, COLLAR)


## Where the sloped plaster meets the flat ceiling, in from the eaves.
static func collar_s() -> float:
	return COLLAR - E + PLASTER_UNDER


## ---- the shell -------------------------------------------------------------------



## Foundation, the four outer walls (clapboard out, plaster or paper in),
## corner boards, water table and frieze.
func _shell() -> void:
	var gran := c(HarborTown.GRANITE, HarborTown.K_GRANITE)
	_box("wall", Vector3(0, -0.35, -D / 2.0), Vector3(W + 0.06, 1.7, D + 0.06), gran)   # down into the ground; its top under the floors, or they flicker
	var clap := c(CLAP, HarborTown.K_CLAP)
	var flat_e := func(_p: Vector2) -> float: return E
	var gable := func(p: Vector2) -> float: return E + minf(-p.y, D + p.y)
	var front := _front_openings()
	var back := _back_openings()
	# Outer layer: front and back full width, the ends between them.
	_wall("wall", Vector2(-W / 2.0, -T_OUT / 2.0), Vector2(W / 2.0, -T_OUT / 2.0), F - 0.1, flat_e, front, T_OUT, clap, true)
	_wall("wall", Vector2(-W / 2.0, -D + T_OUT / 2.0), Vector2(W / 2.0, -D + T_OUT / 2.0), F - 0.1, flat_e, back, T_OUT, clap, true)
	for s: float in [-1.0, 1.0]:
		var x := s * (W / 2.0 - T_OUT / 2.0)
		var ends := _end_openings(s)
		_wall("wall", Vector2(x, -T_OUT), Vector2(x, -D + T_OUT), F - 0.1, gable, ends, T_OUT, clap, true,
			[D / 2.0 - T_OUT])
	# Inner layer, room by room: paper in the living and dining rooms,
	# plaster in the hall, paint in the kitchen, tile in the bath.
	var zi := -T_OUT - T_IN / 2.0
	var ceil1 := func(_p: Vector2) -> float: return E - 0.02
	var paper_living := c(self.paper_living, HarborTown.K_PAPER)
	var paper_dining := c(self.paper_dining, HarborTown.K_PAPER)
	var hall := c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER)
	var kitchen := c(kitchen_paint, HarborTown.K_ENAMEL)
	var xi := W / 2.0 - T_OUT
	_inner_run(Vector2(-xi, zi), Vector2(xi, zi), front, [[-1.0, paper_living], [1.0, hall], [xi, paper_dining]], F, ceil1)
	_inner_run(Vector2(-xi, -D - zi), Vector2(xi, -D - zi), back, [[-1.0, paper_living], [1.0, c(Color(0.82, 0.90, 0.88), HarborTown.K_TILE)], [xi, kitchen]], F, ceil1)
	_inner_end(-1.0, [[-D + T_OUT, paper_living]], F, ceil1)
	_inner_end(1.0, [[-4.0, paper_dining], [-D + T_OUT, kitchen]], F, ceil1)
	# Upstairs: the gable ends' plaster between the knee walls, under
	# the ceiling's profile.
	var bed := c(paper_bed, HarborTown.K_PAPER)
	var bed2 := c(paper_bed2, HarborTown.K_PAPER)
	var ceil2 := func(p: Vector2) -> float: return ceiling(-p.y)
	for s: float in [-1.0, 1.0]:
		var x := s * (xi - T_IN / 2.0)
		var ends := _end_openings(s)
		var from := Vector2(x, -KNEE)
		var to := Vector2(x, -D + KNEE)
		var shifted: Array = []
		for o: Array in ends:
			shifted.append([float(o[0]) + T_OUT - KNEE, float(o[1]) + T_OUT - KNEE, o[2], o[3]])
		_wall("wall", from, to, U, ceil2, shifted, T_IN, bed if s < 0.0 else bed2, false,
			[collar_s() - KNEE, D - collar_s() - KNEE])
	# Trim: corner boards, the water table over the foundation, the
	# frieze under the eaves, rake boards up the gables.
	var trim := c(TRIM, HarborTown.K_PAINT)
	for sx: float in [-1.0, 1.0]:
		for z: float in [0.0, -D]:
			var off := Vector3(sx * (W / 2.0 - 0.06), 0, z + (0.03 if z == 0.0 else -0.03))
			_box("wall", off + Vector3(0, (F + E) / 2.0 - 0.05, 0), Vector3(0.14, E - F + 0.1, 0.08), trim)
			_box("wall", off + Vector3(sx * 0.03, (F + E) / 2.0 - 0.05, -0.04 if z == 0.0 else 0.04), Vector3(0.08, E - F + 0.1, 0.14), trim)
	for z: float in [0.02, -D - 0.02]:
		_box("wall", Vector3(0, F - 0.02, z), Vector3(W + 0.1, 0.16, 0.06), trim)
		_box("wall", Vector3(0, E - 0.12, z), Vector3(W + 0.1, 0.22, 0.06), trim)
	for sx: float in [-1.0, 1.0]:
		_box("wall", Vector3(sx * (W / 2.0 + 0.02), F - 0.02, -D / 2.0), Vector3(0.06, 0.16, D + 0.1), trim)


## An inner finish along a wall, changing at each [end x, colour] in
## turn: openings (measured along the outer wall from its start at
## x = -W/2) are carried over.
func _inner_run(p0: Vector2, p1: Vector2, openings: Array, spans: Array, y0: float, top: Callable) -> void:
	var start := p0.x
	for span: Array in spans:
		var end: float = span[0]
		var shifted: Array = []
		for o: Array in openings:
			shifted.append([float(o[0]) - (start + W / 2.0), float(o[1]) - (start + W / 2.0), o[2], o[3]])
		_wall("wall", Vector2(start, p0.y), Vector2(end, p0.y), y0, top, shifted, T_IN, span[1])
		start = end


func _inner_end(side: float, spans: Array, y0: float, top: Callable) -> void:
	var x := side * (W / 2.0 - T_OUT - T_IN / 2.0)
	var openings := _end_openings(side)
	var start := -T_OUT
	for span: Array in spans:
		var end: float = span[0]
		var shifted: Array = []
		for o: Array in openings:
			shifted.append([float(o[0]) - (-start - T_OUT), float(o[1]) - (-start - T_OUT), o[2], o[3]])
		_wall("wall", Vector2(x, start), Vector2(x, end), y0, top, shifted, T_IN, span[1])
		start = end


## The openings in the front wall, metres along from x = -W/2.
func _front_openings() -> Array:
	var out: Array = []
	for x: float in [-3.4, -1.8, 1.8, 3.4]:
		out.append([x + W / 2.0 - 0.45, x + W / 2.0 + 0.45, F + 0.75, F + 2.2])
	out.append([W / 2.0 - 0.5, W / 2.0 + 0.5, F - 0.1, F + 2.08])
	return out


func _back_openings() -> Array:
	return [
		[-3.0 + W / 2.0 - 0.45, -3.0 + W / 2.0 + 0.45, F + 0.75, F + 2.2],     # living room
		[W / 2.0 - 0.3, W / 2.0 + 0.3, F + 1.45, F + 2.2],                   # bath, high
		[2.7 + W / 2.0 - 0.45, 2.7 + W / 2.0 + 0.45, F + 1.0, F + 2.2],       # over the sink
		[3.98 + W / 2.0 - 0.42, 3.98 + W / 2.0 + 0.42, F - 0.1, F + 2.05],    # the back door
	]


## An end wall's openings, metres along from z = -T_OUT going back.
func _end_openings(side: float) -> Array:
	var out: Array = []
	var first: Array[float] = [1.7, 6.3]
	if side > 0.0:
		first = [2.0, 6.6]
	for z in first:
		out.append([z - T_OUT - 0.45, z - T_OUT + 0.45, F + 0.75, F + 2.2])
	for z: float in [2.9, 5.1]:
		out.append([z - T_OUT - 0.4, z - T_OUT + 0.4, U + 0.8, U + 1.95])
	return out


## ---- the roof -------------------------------------------------------------------

## A piece of one side's roof between s0 and s1 in from its eaves and
## x0 to x1 along the ridge, t thick, its underside on the rafters'
## line; under > 0 hangs it that far below (a ceiling).
func _roof_piece(side: float, x0: float, x1: float, s0: float, s1: float, col: Color, t := 0.15, under := 0.0,
		solid := false) -> void:
	var n := Vector3(0, 0.7071, 0.7071 * side)
	var s_mid := (s0 + s1) / 2.0
	var z_mid := -s_mid if side > 0.0 else -D + s_mid
	var centre := Vector3((x0 + x1) / 2.0, rafter(s_mid), z_mid) + n * (t / 2.0 - under)
	var bx := Vector3(1, 0, 0)
	var bz := bx.cross(n)
	m.box("wall", Transform3D(Basis(bx, n, bz), centre), Vector3(x1 - x0, t, (s1 - s0) * 1.41421), col, true)
	if solid:
		_solid(centre, Vector3(x1 - x0, t, (s1 - s0) * 1.41421), Basis(bx, n, bz))


func _roof() -> void:
	var shingle := c(ROOF, HarborTown.K_ROOF)
	var plaster := c(PLASTER, HarborTown.K_PLASTER)
	var ridge := D / 2.0
	var over := 0.35
	var xw := W / 2.0 + 0.3
	# The back slope whole; the front round the dormers' openings.
	_roof_piece(-1.0, -xw, xw, -over, ridge + 0.1, shingle, 0.15, 0.0, true)
	var hole_lo := DORMER_FACE
	var hole_hi := DORMER_EAVE - E
	var xs: Array[float] = [-xw]
	for dx in DORMERS:
		xs.append(dx - DORMER_HALF)
		xs.append(dx + DORMER_HALF)
	xs.append(xw)
	for i in range(0, xs.size(), 2):
		_roof_piece(1.0, xs[i], xs[i + 1], -over, ridge + 0.1, shingle, 0.15, 0.0, true)
	for dx in DORMERS:
		_roof_piece(1.0, dx - DORMER_HALF, dx + DORMER_HALF, -over, hole_lo, shingle, 0.15, 0.0, true)
		_roof_piece(1.0, dx - DORMER_HALF, dx + DORMER_HALF, hole_hi, ridge + 0.1, shingle, 0.15, 0.0, true)
	# The rain stops on the roof: a shelter box under each slope for the
	# drops to meet.
	for side: float in [-1.0, 1.0]:
		var n := Vector3(0, 0.7071, 0.7071 * side)
		var bx := Vector3(1, 0, 0)
		var s_mid := (ridge - over) / 2.0
		var z_mid := -s_mid if side > 0.0 else -D + s_mid
		var shelter := GPUParticlesCollisionBox3D.new()
		shelter.size = Vector3(2.0 * xw, 3.0, (ridge + over) * 1.41421 + 0.2)
		shelter.transform = Transform3D(Basis(bx, n, bx.cross(n)), Vector3(0, rafter(s_mid), z_mid) + n * (0.15 - 1.5))
		add_child(shelter)
	# The ridge cap.
	_box("wall", Vector3(0, rafter(ridge) + 0.2, -ridge), Vector3(2.0 * xw, 0.08, 0.3), shingle)
	# Upstairs: sloped plaster from the knee walls to the collar ceiling,
	# the flat ceiling, the knee walls; the front slope's plaster opens
	# for each dormer.
	var xi := W / 2.0 - T_OUT - T_IN
	var cs := collar_s()
	_roof_piece(-1.0, -xi, xi, KNEE, cs, plaster, 0.03, PLASTER_UNDER)
	var ixs: Array[float] = [-xi]
	for dx in DORMERS:
		ixs.append(dx - DORMER_HALF)
		ixs.append(dx + DORMER_HALF)
	ixs.append(xi)
	for i in range(0, ixs.size(), 2):
		_roof_piece(1.0, ixs[i], ixs[i + 1], KNEE, cs, plaster, 0.03, PLASTER_UNDER)
	var dormer_ceiling_s := DORMER_EAVE - 0.15 - E + PLASTER_UNDER
	for dx in DORMERS:
		_roof_piece(1.0, dx - DORMER_HALF, dx + DORMER_HALF, dormer_ceiling_s, cs, plaster, 0.03, PLASTER_UNDER)
	_box("wall", Vector3(0, COLLAR + 0.015, -D / 2.0), Vector3(2.0 * xi, 0.03, D - 2.0 * cs), plaster)
	var knee_top := rafter(KNEE) - PLASTER_UNDER
	var flat := func(_p: Vector2) -> float: return knee_top
	var openings: Array = []
	for dx in DORMERS:
		openings.append([dx - DORMER_HALF + xi, dx + DORMER_HALF + xi, U, U])
	_wall("wall", Vector2(-xi, -KNEE), Vector2(xi, -KNEE), U, flat, openings, 0.05, plaster, true)
	_wall("wall", Vector2(-xi, -D + KNEE), Vector2(xi, -D + KNEE), U, flat, [], 0.05, plaster, true)


## Two gabled dormers on the front slope: a face with its window, the
## cheeks down to the roof, a little roof of their own, plaster inside.
func _dormers() -> void:
	var clap := c(CLAP, HarborTown.K_CLAP)
	var trim := c(TRIM, HarborTown.K_PAINT)
	var plaster := c(PLASTER, HarborTown.K_PLASTER)
	var shingle := c(ROOF, HarborTown.K_ROOF)
	var zf := -DORMER_FACE
	var zb := -(DORMER_EAVE - 0.15 - E + PLASTER_UNDER)
	var ceil := DORMER_EAVE - 0.15
	for dx in DORMERS:
		var flat := func(_p: Vector2) -> float: return DORMER_EAVE
		var window := [[DORMER_HALF - 0.4, DORMER_HALF + 0.4, U + 0.72, U + 1.82]]
		_wall("wall", Vector2(dx - DORMER_HALF, zf - T_OUT / 2.0), Vector2(dx + DORMER_HALF, zf - T_OUT / 2.0), U, flat, window, T_OUT, clap)
		var inner := func(_p: Vector2) -> float: return ceil
		_wall("wall", Vector2(dx - DORMER_HALF + T_OUT, zf - T_OUT - 0.02), Vector2(dx + DORMER_HALF - T_OUT, zf - T_OUT - 0.02), U, inner,
			[[DORMER_HALF - T_OUT - 0.4, DORMER_HALF - T_OUT + 0.4, U + 0.72, U + 1.82]], 0.04, plaster)
		for s: float in [-1.0, 1.0]:
			var x := dx + s * (DORMER_HALF - T_OUT / 2.0)
			_slab("wall", Vector2(x, zf), Vector2(x, zb), U, DORMER_EAVE, DORMER_EAVE, T_OUT, clap)
			_slab("wall", Vector2(x - s * (T_OUT / 2.0 + 0.02), zf - T_OUT), Vector2(x - s * (T_OUT / 2.0 + 0.02), zb), U, ceil, ceil, 0.04, plaster)
		_box("wall", Vector3(dx, ceil + 0.015, (zf + zb) / 2.0), Vector3(DORMER_HALF * 2.0 - 0.2, 0.03, zf - zb), plaster)
		# Its own gable and roof, the ridge running back into the main roof.
		var span := DORMER_HALF * 2.0 + 0.1
		var rise := span / 2.0
		m.prism("wall", HarborTown.at(Vector3(dx, DORMER_EAVE, (zf + zb) / 2.0 - 0.05)), span, rise, zf - zb + 0.1, clap)
		for s: float in [-1.0, 1.0]:
			var down := Vector3(s * 0.7071, -0.7071, 0)
			var up_n := Vector3(s * 0.7071, 0.7071, 0)
			var mid := Vector3(dx + s * span / 4.0, DORMER_EAVE + rise / 2.0, (zf + zb) / 2.0 + 0.1) + up_n * 0.06 + down * 0.08
			m.box("wall", Transform3D(Basis(Vector3(0, 0, 1), -s * PI / 4.0), mid), Vector3(span * 0.7071 + 0.2, 0.1, zf - zb + 0.5), shingle, true)
		for s: float in [-1.0, 1.0]:
			_box("wall", Vector3(dx + s * (DORMER_HALF - 0.04), (U + DORMER_EAVE) / 2.0 + 0.3, zf + 0.02), Vector3(0.1, DORMER_EAVE - U - 0.6, 0.06), trim)
		_window_unit(Vector3(dx, U + 1.27, zf), 0.8, 1.1, 0.0, false, T_OUT + 0.06, curtains.lightened(0.1), _opens())
	# The dormers' floors: the upstairs floor reaches forward into them.
	for dx in DORMERS:
		_box("wall", Vector3(dx, U - 0.045, (zf + -KNEE) / 2.0 - 0.02), Vector3(DORMER_HALF * 2.0 - 0.1, 0.09, KNEE - DORMER_FACE), c(OAK, HarborTown.K_OAK), true)


## The chimney up the west gable: a broad base for the fireplace, a
## shoulder, the stack past the ridge, a cap.
func _chimney() -> void:
	var brick := c(Color(0.52, 0.26, 0.19), HarborTown.K_BRICK)
	var x0 := -W / 2.0
	_box("wall", Vector3(x0 - 0.38, 1.7, -D / 2.0), Vector3(0.76, 3.4, 1.6), brick, true)
	var shoulder := Transform3D(Basis(Vector3(0, 0, 1), 0.0), Vector3(x0 - 0.3, 3.5, -D / 2.0))
	m.box("wall", shoulder, Vector3(0.6, 0.3, 1.2), brick, true)
	_box("wall", Vector3(x0 - 0.3, 6.0, -D / 2.0), Vector3(0.6, 5.0, 0.9), brick, true)
	_box("wall", Vector3(x0 - 0.3, 8.55, -D / 2.0), Vector3(0.72, 0.12, 1.02), c(Color(0.45, 0.44, 0.42), HarborTown.K_GRANITE))
	for k in 2:
		_box("iron", Vector3(x0 - 0.3, 8.8, -D / 2.0 - 0.2 + 0.4 * k), Vector3(0.18, 0.4, 0.18), Color(0.45, 0.28, 0.2))


## ---- floors and the stair ------------------------------------------------------

func _floors() -> void:
	var xi := W / 2.0 - T_OUT
	var oak := c(OAK, HarborTown.K_OAK)
	# The first floor: oak through the living room, hall and dining
	# room, linoleum in the kitchen, a black and white check in the bath.
	_box("wall", Vector3((-xi + 1.0) / 2.0, F - 0.05, -D / 2.0), Vector3(xi + 1.0, 0.1, D - 2.0 * T_OUT), oak, true)
	_box("wall", Vector3(0, F - 0.05, (-T_OUT - 5.6) / 2.0), Vector3(2.0, 0.1, 5.6 - T_OUT), oak, true)
	_box("wall", Vector3(0, F - 0.05, (-5.6 - D + T_OUT) / 2.0), Vector3(2.0, 0.1, D - T_OUT - 5.6), c(Color(0.08, 0.08, 0.08), HarborTown.K_LINO), true)
	_box("wall", Vector3((1.0 + xi) / 2.0, F - 0.05, (-T_OUT - 4.0) / 2.0), Vector3(xi - 1.0, 0.1, 4.0 - T_OUT), oak, true)
	_box("wall", Vector3((1.0 + xi) / 2.0, F - 0.05, (-4.0 - D + T_OUT) / 2.0), Vector3(xi - 1.0, 0.1, D - T_OUT - 4.0), c(Color(0.55, 0.15, 0.12), HarborTown.K_LINO), true)
	# The upstairs floor round the stairwell, and the first floor's
	# ceiling under it.
	var plaster := c(PLASTER, HarborTown.K_PLASTER)
	var pieces: Array = [
		[Vector2(-xi, -T_OUT), Vector2(xi, STAIR_Z.x)],
		[Vector2(-xi, STAIR_Z.y), Vector2(xi, -D + T_OUT)],
		[Vector2(-xi, STAIR_Z.x), Vector2(STAIR_X.x - 0.05, STAIR_Z.y)],
		[Vector2(STAIR_X.y, STAIR_Z.x), Vector2(xi, STAIR_Z.y)],
	]
	for piece: Array in pieces:
		var a: Vector2 = piece[0]
		var b: Vector2 = piece[1]
		var centre := (a + b) / 2.0
		var size := (b - a).abs()
		_box("wall", Vector3(centre.x, U - 0.045, centre.y), Vector3(size.x, 0.09, size.y), oak, true)
		_box("wall", Vector3(centre.x, E - 0.035, centre.y), Vector3(size.x, 0.03, size.y), plaster)


## The stair: fourteen risers up a steep straight flight from the hall
## to the landing, open to the hall on its right under a handrail, the
## underside closed; a rail round the stairwell upstairs.
func _cape_stair() -> void:
	var rise := (U - F) / 14.0
	var run := (STAIR_Z.x - STAIR_Z.y) / 14.0
	var width := STAIR_X.y - STAIR_X.x
	var cx := (STAIR_X.x + STAIR_X.y) / 2.0
	var oak := c(OAK * 0.9, HarborTown.K_WOOD)
	var white := c(TRIM, HarborTown.K_ENAMEL)
	for k in 13:
		var y := F + rise * (k + 1)
		var z := STAIR_Z.x - run * (k + 0.5)
		_box("wall", Vector3(cx, y - 0.02, z - 0.015), Vector3(width, 0.04, run + 0.03), oak)
		_box("wall", Vector3(cx, y - rise / 2.0, STAIR_Z.x - run * k - 0.01), Vector3(width, rise, 0.02), white)
	_slab("wall", Vector2(STAIR_X.y + 0.02, STAIR_Z.x), Vector2(STAIR_X.y + 0.02, STAIR_Z.y), F, F + rise, U - 0.05, 0.04, white)
	_ramp(Vector3(cx, F, STAIR_Z.x + 0.05), Vector3(cx, U, STAIR_Z.y), width)
	# The newel, the handrail, a baluster on every tread.
	var rail_x := STAIR_X.y + 0.02
	_box("wall", Vector3(rail_x, F + 0.55, STAIR_Z.x + 0.05), Vector3(0.1, 1.1, 0.1), white, true)
	_box("wall", Vector3(rail_x, F + 1.12, STAIR_Z.x + 0.05), Vector3(0.13, 0.05, 0.13), oak)
	m.bar("wall", Vector3(rail_x, F + 1.0, STAIR_Z.x + 0.05), Vector3(rail_x, U + 0.9, STAIR_Z.y), 0.03, 6, oak)
	for k in 13:
		var y := F + rise * (k + 1)
		var z := STAIR_Z.x - run * (k + 0.5)
		var top := F + 1.0 + (y - F) * 1.0
		_box("wall", Vector3(rail_x, (y + top) / 2.0, z), Vector3(0.03, top - y, 0.03), white)
	# Upstairs, the rail along the stairwell's open side.
	var zs := STAIR_Z.x - 0.3
	_box("wall", Vector3(rail_x, U + 0.45, zs), Vector3(0.08, 0.9, 0.08), white)
	_box("wall", Vector3(rail_x, U + 0.45, STAIR_Z.y), Vector3(0.08, 0.9, 0.08), white)
	_box("wall", Vector3(rail_x, U + 0.9, (zs + STAIR_Z.y) / 2.0), Vector3(0.07, 0.05, zs - STAIR_Z.y), oak, true)
	var n := int((zs - STAIR_Z.y) / 0.12)
	for k in n:
		_box("wall", Vector3(rail_x, U + 0.45, zs - (k + 0.5) * (zs - STAIR_Z.y) / n), Vector3(0.025, 0.9, 0.025), white)
	_solid(Vector3(rail_x, U + 0.5, (zs + STAIR_Z.y) / 2.0), Vector3(0.1, 1.0, zs - STAIR_Z.y))
	# The stair's head: a rail across the front end of the well.
	_box("wall", Vector3(cx, U + 0.9, zs), Vector3(width, 0.05, 0.07), oak, true)


## ---- partitions ------------------------------------------------------------------

func _partitions() -> void:
	var plaster := c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER)
	var top1 := func(_p: Vector2) -> float: return E - 0.02
	var xi := W / 2.0 - T_OUT - T_IN
	var zi := -T_OUT - T_IN
	var zb := -D + T_OUT + T_IN
	# Downstairs: the hall's two walls, the dining room from the kitchen,
	# the bath from the hall.
	_wall("wall", Vector2(-1.0, zi), Vector2(-1.0, zb), F, top1, [[0.1, 0.95, F, F + 2.05]], 0.1, plaster, true)
	_wall("wall", Vector2(1.0, zi), Vector2(1.0, zb), F, top1, [[0.1, 0.95, F, F + 2.05], [4.25, 5.15, F, F + 2.05]], 0.1, plaster, true)
	_wall("wall", Vector2(1.05, -4.0), Vector2(xi, -4.0), F, top1, [[0.35, 1.55, F, F + 2.1]], 0.1, plaster, true)
	_wall("wall", Vector2(-0.95, -5.6), Vector2(0.95, -5.6), F, top1, [[1.05, 1.8, F, F + 2.0]], 0.1, plaster, true)
	# Upstairs: the bedrooms' walls either side of the landing, their
	# tops under the ceiling's profile, each with its door.
	var top2 := func(p: Vector2) -> float: return ceiling(-p.y)
	var bends := [collar_s() - KNEE, D - collar_s() - KNEE]
	for s: float in [-1.0, 1.0]:
		_wall("wall", Vector2(s * 1.0, -KNEE), Vector2(s * 1.0, -D + KNEE), U, top2, [[3.1, 4.0, U, U + 2.0]], 0.1,
			c(PLASTER, HarborTown.K_PLASTER), true, bends)


## ---- windows and doors -----------------------------------------------------------

func _openings() -> void:
	# The front: four windows with shutters, the door between.
	for x: float in [-3.4, -1.8, 1.8, 3.4]:
		_window_unit(Vector3(x, F + 1.475, 0.0), 0.9, 1.45, 0.0, true, T_OUT + T_IN, curtains, _opens(), true, SHUTTER)
	for x: float in [-3.0, 2.7]:
		var sill := F + 0.75 if x < 0.0 else F + 1.0
		_window_unit(Vector3(x, (sill + F + 2.2) / 2.0, -D), 0.9, F + 2.2 - sill, PI, false, T_OUT + T_IN, curtains, _opens(), true)
	_window_unit(Vector3(0.0, F + 1.825, -D), 0.6, 0.75, PI, false, T_OUT + T_IN, Color(0.9, 0.9, 0.9), _opens())
	for s: float in [-1.0, 1.0]:
		var yaw := s * PI / 2.0
		var first: Array[float] = [1.7, 6.3]
		if s > 0.0:
			first = [2.0, 6.6]
		for z in first:
			_window_unit(Vector3(s * W / 2.0, F + 1.475, -z), 0.9, 1.45, yaw, false, T_OUT + T_IN, curtains, _opens(), true)
		for z: float in [2.9, 5.1]:
			_window_unit(Vector3(s * W / 2.0, U + 1.375, -z), 0.8, 1.15, yaw, false, T_OUT + T_IN, curtains.lightened(0.1), _opens())
	_front_door()
	_back_door()


func _front_door() -> void:
	var trim := c(TRIM, HarborTown.K_PAINT)
	# The surround: pilasters, a frieze and a cornice over the door.
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(s * 0.62, F + 1.05, 0.06), Vector3(0.18, 2.1, 0.1), trim)
		_box("wall", Vector3(s * 0.62, F + 0.08, 0.07), Vector3(0.24, 0.16, 0.13), trim)
	_box("wall", Vector3(0, F + 2.2, 0.07), Vector3(1.5, 0.22, 0.12), trim)
	_box("wall", Vector3(0, F + 2.35, 0.1), Vector3(1.65, 0.08, 0.2), trim)
	# The jambs, the threshold, the leaf standing open into the hall.
	var inner := c(TRIM, HarborTown.K_ENAMEL)
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(s * 0.49, F + 1.03, -(T_OUT + T_IN) / 2.0), Vector3(0.02, 2.06, T_OUT + T_IN), inner)
	_box("wall", Vector3(0, F - 0.02, -0.07), Vector3(1.0, 0.04, 0.16), c(OAK, HarborTown.K_WOOD))
	var hinge := Vector3(0.46, F, -T_OUT - T_IN)
	var leaf := Transform3D(Basis(Vector3.UP, -1.35), hinge)
	var door := c(DOOR, HarborTown.K_PAINT)
	m.box("wall", leaf * HarborTown.at(Vector3(-0.46, 1.02, -0.025)), Vector3(0.92, 2.04, 0.045), door, true)
	for k in 2:
		for s: float in [-1.0, 1.0]:
			m.box("wall", leaf * HarborTown.at(Vector3(-0.46 + s * 0.2, 0.45 + 0.7 * k, 0.003)), Vector3(0.28, 0.55, 0.02), c(DOOR * 0.85, HarborTown.K_PAINT), true)
	for k in 4:
		var gx := -0.46 + (-0.27 + 0.18 * k)
		m.quad("clear", leaf * Vector3(gx - 0.07, 1.62, 0.0), leaf * Vector3(gx - 0.07, 1.9, 0.0),
			leaf * Vector3(gx + 0.07, 1.9, 0.0), leaf * Vector3(gx + 0.07, 1.62, 0.0), leaf.basis.z, Color.WHITE)
	m.sphere("iron", leaf * Transform3D(Basis(), Vector3(-0.84, 1.0, 0.04)), 0.03, 8, Color(0.72, 0.58, 0.25))
	# The granite steps and the stoop, and a slope for the feet.
	var gran := c(HarborTown.GRANITE, HarborTown.K_GRANITE)
	for k in 3:
		_box("wall", Vector3(0, 0.1 + 0.2 * k, 0.9 - 0.3 * k), Vector3(1.8, 0.2, 0.62), gran)
	_ramp(Vector3(0, 0.0, 1.35), Vector3(0, F, 0.0), 1.6)
	# The porch lantern beside the door.
	_lamp_fixture(Vector3(0.95, F + 1.9, 0.12), "porch", 0.35, 0.5)
	# The house number over the door.
	var plate := Label3D.new()
	plate.text = "14"
	plate.font_size = 64
	plate.pixel_size = 0.003
	plate.modulate = Color(0.1, 0.1, 0.1)
	plate.shaded = true
	plate.double_sided = false
	plate.position = Vector3(0, F + 2.2, 0.135)
	add_child(plate)


func _back_door() -> void:
	var x := 3.98
	var door := c(Color(0.25, 0.38, 0.30), HarborTown.K_PAINT)
	_box("wall", Vector3(x, F + 1.0, -D + 0.04), Vector3(0.84, 2.02, 0.045), door, true)
	var n := Vector3(0, 0, -1)
	m.quad("clear", Vector3(x - 0.3, F + 1.2, -D - 0.0), Vector3(x - 0.3, F + 1.85, -D - 0.0),
		Vector3(x + 0.3, F + 1.85, -D - 0.0), Vector3(x + 0.3, F + 1.2, -D - 0.0), n, Color.WHITE)
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(x + s * 0.5, F + 1.05, -D - 0.03), Vector3(0.12, 2.1, 0.06), c(TRIM, HarborTown.K_PAINT))
	_box("wall", Vector3(x, F + 2.15, -D - 0.04), Vector3(1.1, 0.14, 0.08), c(TRIM, HarborTown.K_PAINT))
	_box("wall", Vector3(x, F - 0.15, -D - 0.5), Vector3(1.4, 0.3, 1.0), c(HarborTown.GRANITE, HarborTown.K_GRANITE), true)
	_box("iron", Vector3(x + 0.36, F + 1.0, -D - 0.02), Vector3(0.04, 0.06, 0.04), Color(0.2, 0.2, 0.2))
	# The bulkhead to the cellar, slanting down the back wall.
	var bulk := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-2.0, 0.45, -D - 0.7))
	m.box("wall", bulk, Vector3(1.4, 0.06, 1.5), c(Color(0.25, 0.38, 0.30), HarborTown.K_PAINT), true)
	for s: float in [-1.0, 1.0]:
		_slab("wall", Vector2(-2.0 + s * 0.72, -D), Vector2(-2.0 + s * 0.72, -D - 1.35), 0.0, 0.85, 0.12, 0.08, c(HarborTown.GRANITE, HarborTown.K_GRANITE))


## ---- the rooms ---------------------------------------------------------------------

func _living_room() -> void:
	var xw := -W / 2.0 + T_OUT + T_IN
	var cz := -D / 2.0
	var brick := c(Color(0.55, 0.28, 0.20), HarborTown.K_BRICK)
	var wood := c(Color(0.42, 0.26, 0.14), HarborTown.K_WOOD)
	# The fireplace: a brick breast, the firebox, a hearth, a mantel, a
	# mirror over it; logs burning.
	_box("wall", Vector3(xw + 0.2, F + 0.65, cz), Vector3(0.4, 1.3, 1.7), brick, true)
	_box("wall", Vector3(xw + 0.41, F + 0.4, cz), Vector3(0.02, 0.62, 0.8), c(Color(0.05, 0.04, 0.04), HarborTown.K_ENAMEL))
	_box("wall", Vector3(xw + 0.65, F + 0.02, cz), Vector3(0.5, 0.04, 1.8), c(Color(0.3, 0.3, 0.32), HarborTown.K_GRANITE))
	_box("wall", Vector3(xw + 0.47, F + 1.32, cz), Vector3(0.22, 0.07, 1.95), wood)
	_box("wall", Vector3(xw + 0.39, F + 1.22, cz), Vector3(0.06, 0.14, 1.9), wood)
	_box("wall", Vector3(xw + 0.02, F + 1.9, cz), Vector3(0.04, 0.8, 1.2), c(Color(0.55, 0.42, 0.2), HarborTown.K_WOOD))
	m.box("steel", HarborTown.at(Vector3(xw + 0.045, F + 1.9, cz)), Vector3(0.01, 0.68, 1.08), Color.WHITE)
	_fire_at(Vector3(xw + 0.25, F + 0.02, cz), PI / 2.0)
	# Things on the mantel: a clock, two candlesticks, a vase.
	_box("wall", Vector3(xw + 0.5, F + 1.46, cz), Vector3(0.12, 0.22, 0.28), wood)
	_box("wall", Vector3(xw + 0.56, F + 1.48, cz), Vector3(0.01, 0.12, 0.12), c(Color(0.9, 0.88, 0.8), HarborTown.K_ENAMEL))
	for s: float in [-1.0, 1.0]:
		m.cylinder("iron", HarborTown.at(Vector3(xw + 0.5, F + 1.45, cz + s * 0.6)), 0.03, 0.02, 0.2, 8, Color(0.75, 0.6, 0.3))
	m.cylinder("wall", HarborTown.at(Vector3(xw + 0.5, F + 1.47, cz - 0.8)), 0.05, 0.07, 0.22, 10, c(Color(0.25, 0.4, 0.6), HarborTown.K_ENAMEL))
	# A braided rug before the fire.
	var rug := c(Color(0.55, 0.22, 0.18), HarborTown.K_CLOTH)
	m.cylinder("wall", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.35)), Vector3(-2.7, F + 0.006, cz)), 1.35, 1.35, 0.012, 24, rug)
	m.cylinder("wall", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 1.35)), Vector3(-2.7, F + 0.009, cz)), 1.0, 1.0, 0.012, 24, c(Color(0.35, 0.40, 0.28), HarborTown.K_CLOTH))
	# The sofa, facing the fire across the rug.
	var cloth := c(Color(0.32, 0.40, 0.30), HarborTown.K_CLOTH)
	var sx := -1.55
	_box("wall", Vector3(sx, F + 0.22, cz), Vector3(0.85, 0.3, 2.1), cloth, true)
	_box("wall", Vector3(sx + 0.3, F + 0.6, cz), Vector3(0.22, 0.55, 2.1), cloth)
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(sx, F + 0.42, cz + s * 1.0), Vector3(0.85, 0.34, 0.18), cloth)
		_box("wall", Vector3(sx - 0.07, F + 0.44, cz + s * 0.45), Vector3(0.7, 0.14, 0.88), c(Color(0.36, 0.45, 0.34), HarborTown.K_CLOTH))
	for k in 4:
		_box("wall", Vector3(sx + (-0.3 if k < 2 else 0.3), F + 0.04, cz + (-0.95 if k % 2 == 0 else 0.95)), Vector3(0.06, 0.08, 0.06), wood)
	# Two armchairs either side of the hearth, turned to the fire.
	for s: float in [-1.0, 1.0]:
		_armchair(Vector3(-3.55, F, cz + s * 1.55), PI / 2.0 + s * 0.6, c(Color(0.62, 0.48, 0.30), HarborTown.K_CLOTH))
	# A low table between.
	_table(Vector3(-2.6, F, cz), Vector2(0.55, 1.0), 0.42, wood)
	_box("wall", Vector3(-2.6, F + 0.45, cz + 0.2), Vector3(0.22, 0.03, 0.3), c(Color(0.85, 0.82, 0.72), HarborTown.K_ENAMEL))
	# The console radio against the back wall, its dial lit when it is on.
	var rx := -2.2
	var rz := -D + T_OUT + T_IN + 0.22
	_box("wall", Vector3(rx, F + 0.52, rz), Vector3(0.78, 1.04, 0.4), c(Color(0.36, 0.2, 0.1), HarborTown.K_WOOD), true)
	_box("wall", Vector3(rx, F + 0.42, rz + 0.205), Vector3(0.56, 0.5, 0.01), c(Color(0.55, 0.45, 0.3), HarborTown.K_CLOTH))
	for k in 5:
		_box("wall", Vector3(rx, F + 0.22 + 0.1 * k, rz + 0.212), Vector3(0.58, 0.012, 0.012), c(Color(0.3, 0.16, 0.08), HarborTown.K_WOOD))
	var dial := ViewUtil.glow(Color(1.0, 0.72, 0.35), 0.0)
	var face := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.09
	disc.bottom_radius = 0.09
	disc.height = 0.01
	face.mesh = disc
	face.material_override = dial
	face.position = Vector3(rx, F + 0.85, rz + 0.205)
	face.rotation.x = PI / 2.0
	add_child(face)
	town.lamps.append({"thr": 0.45, "mat": dial, "glow": 1.5})
	for s: float in [-1.0, 1.0]:
		m.cylinder("wall", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(rx + s * 0.25, F + 0.85, rz + 0.215)), 0.025, 0.025, 0.03, 8, c(Color(0.2, 0.12, 0.06), HarborTown.K_WOOD))
	# The bookcase in the back corner, full.
	var bx := -4.2
	var bz := -D + T_OUT + T_IN + 0.17
	_box("wall", Vector3(bx, F + 0.95, bz), Vector3(1.0, 1.9, 0.34), wood, true)
	var book_colors: Array[Color] = [Color(0.45, 0.12, 0.1), Color(0.12, 0.22, 0.4), Color(0.2, 0.32, 0.18), Color(0.55, 0.45, 0.25), Color(0.3, 0.2, 0.15), Color(0.6, 0.55, 0.45)]
	for shelf in 4:
		var y := F + 0.15 + shelf * 0.44
		_box("wall", Vector3(bx, y - 0.02, bz + 0.18), Vector3(0.94, 0.03, 0.02), wood)
		var x := bx - 0.44
		while x < bx + 0.42:
			var bw := _rng.randf_range(0.025, 0.05)
			var bh := _rng.randf_range(0.2, 0.3)
			_box("wall", Vector3(x + bw / 2.0, y + bh / 2.0, bz + 0.18), Vector3(bw, bh, 0.2), c(book_colors[_rng.randi() % book_colors.size()], HarborTown.K_CLOTH))
			x += bw + 0.003
	# A floor lamp at the sofa's end, a table lamp by a chair.
	var lx := -1.45
	var lz := cz - 1.35
	m.cylinder("iron", HarborTown.at(Vector3(lx, F + 0.02, lz)), 0.16, 0.18, 0.04, 12, Color(0.55, 0.45, 0.25))
	m.cylinder("iron", HarborTown.at(Vector3(lx, F + 0.75, lz)), 0.015, 0.015, 1.45, 6, Color(0.55, 0.45, 0.25))
	_lamp_fixture(Vector3(lx, F + 1.55, lz), "shade", 0.28, 0.8, 6.0)
	_table(Vector3(-4.2, F, cz + 2.4), Vector2(0.45, 0.45), 0.6, wood)
	m.cylinder("wall", HarborTown.at(Vector3(-4.2, F + 0.75, cz + 2.4)), 0.07, 0.09, 0.26, 10, c(Color(0.7, 0.66, 0.5), HarborTown.K_ENAMEL))
	_lamp_fixture(Vector3(-4.2, F + 1.0, cz + 2.4), "shade", 0.4, 0.5, 4.0)
	# Pictures: a harbour in oils over the sofa, two prints by the window.
	_picture(Vector3(-1.0 - 0.05 - 0.02, F + 1.6, cz), -PI / 2.0, Vector2(0.9, 0.6), Color(0.3, 0.42, 0.52))
	_picture(Vector3(-3.0, F + 1.6, -T_OUT - T_IN - 0.02), PI, Vector2(0.3, 0.4), Color(0.55, 0.5, 0.35))
	# The ceiling light.
	_lamp_fixture(Vector3(-3.0, E - 0.12, cz), "ceiling", 0.6, 0.6, 6.0)
	# Signs of the evening: the paper on a chair, a cup, the knitting, a
	# book face down on the sofa, the dog asleep before the fire.
	_newspaper(Vector3(-3.4, F + 0.49, cz + 1.5), 0.4)
	_cup(Vector3(-2.6, F + 0.42, cz - 0.2))
	_knitting(Vector3(-4.2, F, cz - 2.2))
	_book(Vector3(-1.55, F + 0.52, cz + 0.6), 0.3, true, Color(0.2, 0.3, 0.5))
	_dog(Vector3(-3.3, F, cz + 0.1), PI / 2.0, Color(0.55, 0.38, 0.2))


func _dining_room() -> void:
	var cz := -2.05
	var cx := 3.0
	var wood := c(Color(0.40, 0.22, 0.12), HarborTown.K_WOOD)
	m.box("wall", HarborTown.at(Vector3(cx, F + 0.006, cz)), Vector3(2.4, 0.012, 2.0), c(Color(0.45, 0.2, 0.2), HarborTown.K_CLOTH), true)
	_table(Vector3(cx, F, cz), Vector2(1.5, 0.9), 0.76, wood)
	for s: float in [-1.0, 1.0]:
		_chair(Vector3(cx + s * 0.4, F, cz + s * 0.62), 0.0 if s < 0.0 else PI, wood)
		_chair(Vector3(cx - s * 0.4, F, cz + s * 0.62), 0.0 if s < 0.0 else PI, wood)
	# Places laid, a bowl of apples.
	for sx: float in [-0.4, 0.4]:
		for sz: float in [-0.28, 0.28]:
			m.cylinder("wall", HarborTown.at(Vector3(cx + sx, F + 0.765, cz + sz)), 0.12, 0.1, 0.012, 14, c(Color(0.93, 0.92, 0.88), HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(Vector3(cx, F + 0.8, cz)), 0.13, 0.08, 0.08, 14, c(Color(0.6, 0.62, 0.7), HarborTown.K_ENAMEL))
	for k in 4:
		m.sphere("wall", HarborTown.at(Vector3(cx - 0.05 + 0.05 * (k % 2), F + 0.86 + 0.02 * (k / 2), cz - 0.03 + 0.05 * (k / 2))), 0.04, 8, c(Color(0.62, 0.1, 0.08), HarborTown.K_ENAMEL))
	_lamp_fixture(Vector3(cx, E - 0.95, cz), "pendant", 0.35, 0.9, 5.0)
	# The sideboard on the end wall, a china cabinet in the corner.
	var xe := W / 2.0 - T_OUT - T_IN
	_box("wall", Vector3(xe - 0.25, F + 0.45, cz), Vector3(0.5, 0.9, 1.4), wood, true)
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(xe - 0.5, F + 0.55, cz + s * 0.35), Vector3(0.01, 0.5, 0.6), c(Color(0.35, 0.18, 0.09), HarborTown.K_WOOD))
	m.cylinder("wall", HarborTown.at(Vector3(xe - 0.25, F + 1.05, cz + 0.4)), 0.07, 0.05, 0.3, 10, c(Color(0.85, 0.85, 0.9), HarborTown.K_ENAMEL))
	_box("wall", Vector3(1.4, F + 0.95, -3.6), Vector3(0.6, 1.9, 0.5), wood, true)
	_box("clear", Vector3(1.4, F + 1.3, -3.34), Vector3(0.5, 0.9, 0.01), Color.WHITE)
	for k in 3:
		for j in 3:
			m.cylinder("wall", HarborTown.at(Vector3(1.25 + 0.15 * j, F + 0.95 + 0.3 * k, -3.6)), 0.06, 0.05, 0.02, 10, c(Color(0.9, 0.9, 0.95), HarborTown.K_ENAMEL))
	_picture(Vector3(3.0, F + 1.6, -4.0 + 0.07), 0.0, Vector2(0.7, 0.5), Color(0.6, 0.45, 0.3))


func _kitchen() -> void:
	var xe := W / 2.0 - T_OUT - T_IN
	var zb := -D + T_OUT + T_IN
	var white := Color(0.92, 0.91, 0.87)
	var cab := c(Color(0.88, 0.90, 0.80), HarborTown.K_ENAMEL)
	var top := c(Color(0.25, 0.45, 0.35), HarborTown.K_LINO)
	# The sink under the window: a cabinet, the enamel sink with a
	# drainboard each side, a faucet; cabinets on the wall either side.
	_box("wall", Vector3(2.55, F + 0.43, zb + 0.3), Vector3(1.9, 0.86, 0.6), cab, true)
	_box("wall", Vector3(2.55, F + 0.88, zb + 0.3), Vector3(1.95, 0.04, 0.64), top)
	_box("iron", Vector3(2.7, F + 0.84, zb + 0.3), Vector3(0.6, 0.12, 0.45), white)
	_box("iron", Vector3(2.7, F + 0.86, zb + 0.3), Vector3(0.5, 0.1, 0.36), Color(0.75, 0.75, 0.72))
	m.bar("steel", Vector3(2.7, F + 0.9, zb + 0.06), Vector3(2.7, F + 1.12, zb + 0.08), 0.015, 6, Color.WHITE)
	m.bar("steel", Vector3(2.7, F + 1.12, zb + 0.08), Vector3(2.7, F + 1.08, zb + 0.24), 0.015, 6, Color.WHITE)
	for x: float in [1.55, 3.55]:
		_box("wall", Vector3(x, F + 1.85, zb + 0.18), Vector3(0.75, 0.75, 0.34), cab, true)
		_box("iron", Vector3(x + 0.25, F + 1.6, zb + 0.36), Vector3(0.1, 0.02, 0.02), Color(0.2, 0.2, 0.2))
	# The range on the east wall: white enamel on legs, an oven, four
	# burners, the back panel with its clock.
	var rz := -5.1
	var rx := xe - 0.34
	_box("iron", Vector3(rx, F + 0.55, rz), Vector3(0.66, 0.6, 1.0), white)
	_solid(Vector3(rx, F + 0.5, rz), Vector3(0.66, 1.0, 1.0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.cylinder("iron", HarborTown.at(Vector3(rx + sx * 0.27, F + 0.12, rz + sz * 0.44)), 0.03, 0.03, 0.24, 6, Color(0.1, 0.1, 0.1))
	for k in 4:
		m.cylinder("iron", HarborTown.at(Vector3(rx + (-0.14 if k < 2 else 0.14), F + 0.86, rz - 0.2 + 0.4 * (k % 2) - 0.2)), 0.09, 0.09, 0.02, 12, Color(0.12, 0.12, 0.12))
	_box("iron", Vector3(rx - 0.33, F + 0.52, rz + 0.25), Vector3(0.02, 0.4, 0.42), Color(0.85, 0.84, 0.8))
	_box("iron", Vector3(rx - 0.35, F + 0.7, rz + 0.25), Vector3(0.03, 0.03, 0.3), Color(0.7, 0.7, 0.7))
	_box("iron", Vector3(rx + 0.3, F + 1.1, rz), Vector3(0.06, 0.45, 1.0), white)
	m.cylinder("iron", Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(rx + 0.26, F + 1.15, rz)), 0.07, 0.07, 0.02, 14, Color(0.15, 0.15, 0.15))
	# The refrigerator, its compressor in a drum on top.
	var fx := 1.45
	var fz := zb + 0.36
	_box("iron", Vector3(fx, F + 0.72, fz), Vector3(0.66, 1.44, 0.66), white)
	_solid(Vector3(fx, F + 0.9, fz), Vector3(0.66, 1.8, 0.66))
	m.cylinder("iron", HarborTown.at(Vector3(fx, F + 1.6, fz)), 0.26, 0.26, 0.3, 16, white)
	for k in 12:
		var a := TAU * k / 12.0
		_box("iron", Vector3(fx + cos(a) * 0.265, F + 1.6, fz + sin(a) * 0.265), Vector3(0.01, 0.26, 0.01), Color(0.7, 0.7, 0.68))
	_box("iron", Vector3(fx + 0.2, F + 1.0, fz + 0.34), Vector3(0.06, 0.2, 0.04), Color(0.72, 0.72, 0.7))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.cylinder("iron", HarborTown.at(Vector3(fx + sx * 0.28, F - 0.0 + 0.02, fz + sz * 0.28)), 0.03, 0.03, 0.04, 6, Color(0.1, 0.1, 0.1))
	# The kitchen table with its oilcloth, two chairs.
	var tx := 2.6
	var tz := -5.3
	var wood := c(Color(0.72, 0.70, 0.62), HarborTown.K_ENAMEL)
	_table(Vector3(tx, F, tz), Vector2(1.0, 0.75), 0.76, wood)
	_box("wall", Vector3(tx, F + 0.765, tz), Vector3(1.04, 0.01, 0.79), c(Color(0.7, 0.12, 0.1), HarborTown.K_LINO))
	for s: float in [-1.0, 1.0]:
		_chair(Vector3(tx + s * 0.62, F, tz), -s * PI / 2.0, c(Color(0.8, 0.8, 0.72), HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(Vector3(tx + 0.2, F + 0.82, tz - 0.1)), 0.07, 0.06, 0.1, 10, c(Color(0.25, 0.45, 0.35), HarborTown.K_ENAMEL))
	_lamp_fixture(Vector3(3.0, E - 0.12, -5.9), "ceiling", 0.25, 0.9, 6.0)
	_pie(Vector3(1.9, F + 0.9, zb + 0.3))
	_bread(Vector3(2.8, F + 0.77, -5.5), 0.3)
	_apron(Vector3(1.0 + 0.06, F + 1.5, -6.6), PI / 2.0, Color(0.85, 0.75, 0.55))
	# A calendar by the door, a towel on its bar.
	_box("wall", Vector3(xe - 0.01, F + 1.5, -7.2), Vector3(0.01, 0.4, 0.3), c(Color(0.9, 0.88, 0.8), HarborTown.K_ENAMEL))


func _hall() -> void:
	var wood := c(Color(0.40, 0.22, 0.12), HarborTown.K_WOOD)
	# A runner down the hall, a table with the telephone, coat hooks.
	m.box("wall", HarborTown.at(Vector3(0.48, F + 0.005, -3.0)), Vector3(0.7, 0.01, 4.6), c(Color(0.45, 0.18, 0.15), HarborTown.K_CLOTH), true)
	_table(Vector3(0.75, F, -2.6), Vector2(0.4, 0.7), 0.78, wood)
	var phone := Vector3(0.75, F + 0.78, -2.5)
	m.cylinder("iron", HarborTown.at(phone + Vector3(0, 0.02, 0)), 0.06, 0.07, 0.04, 12, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", HarborTown.at(phone + Vector3(0, 0.17, 0)), 0.015, 0.015, 0.3, 6, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), phone + Vector3(0, 0.33, 0.02)), 0.03, 0.025, 0.05, 10, Color(0.05, 0.05, 0.05))
	m.cylinder("iron", Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), phone + Vector3(0.06, 0.22, 0)), 0.02, 0.025, 0.08, 8, Color(0.05, 0.05, 0.05))
	for k in 3:
		_box("iron", Vector3(0.93, F + 1.7, -1.3 - 0.25 * k), Vector3(0.05, 0.03, 0.03), Color(0.6, 0.5, 0.3))
	_box("wall", Vector3(0.88, F + 1.35, -1.55), Vector3(0.12, 0.7, 0.45), c(Color(0.3, 0.32, 0.4), HarborTown.K_CLOTH))
	_lamp_fixture(Vector3(0.45, E - 0.12, -1.8), "ceiling", 0.45, 0.5, 5.0)
	_hat(Vector3(0.93, F + 1.74, -1.3))
	_shoes(Vector3(-0.5, F, -0.4), PI / 2.0, Color(0.3, 0.18, 0.1))
	_lamp_fixture(Vector3(0.0, COLLAR - 0.12, -4.9), "ceiling", 0.5, 0.4, 5.0)


func _bath() -> void:
	var white := Color(0.94, 0.93, 0.9)
	var zb := -D + T_OUT + T_IN
	# The clawfoot tub along the back wall.
	var tub := Vector3(-0.1, F, zb + 0.4)
	_box("iron", tub + Vector3(0, 0.42, 0), Vector3(1.5, 0.45, 0.72), white)
	_box("iron", tub + Vector3(0, 0.55, 0), Vector3(1.36, 0.22, 0.58), Color(0.8, 0.8, 0.78))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.sphere("iron", HarborTown.at(tub + Vector3(sx * 0.6, 0.1, sz * 0.26)), 0.07, 8, Color(0.75, 0.6, 0.3))
	_solid(tub + Vector3(0, 0.35, 0), Vector3(1.5, 0.7, 0.72))
	# The pedestal sink with the medicine cabinet over it; the toilet.
	var sink := Vector3(-0.6, F, -5.95)
	m.cylinder("iron", HarborTown.at(sink + Vector3(0, 0.38, 0)), 0.1, 0.14, 0.76, 12, white)
	_box("iron", sink + Vector3(0, 0.82, 0), Vector3(0.55, 0.14, 0.42), white)
	_box("steel", sink + Vector3(0, 1.55, 0.26), Vector3(0.45, 0.6, 0.02), Color.WHITE)
	var wc := Vector3(0.55, F, -6.3)
	m.cylinder("iron", HarborTown.at(wc + Vector3(0, 0.2, 0)), 0.17, 0.13, 0.4, 14, white)
	_box("iron", wc + Vector3(0.28, 0.65, 0), Vector3(0.2, 0.42, 0.45), white)
	_box("wall", wc + Vector3(0, 0.42, 0), Vector3(0.38, 0.03, 0.42), c(Color(0.3, 0.2, 0.12), HarborTown.K_WOOD))
	_lamp_fixture(Vector3(0, E - 0.12, -6.8), "ceiling", 0.55, 0.4, 3.5)


func _bedrooms() -> void:
	var wood := c(Color(0.45, 0.28, 0.15), HarborTown.K_WOOD)
	var cz := -D / 2.0
	# West: a double bed under the slope, a quilt; a dresser; a rocker in
	# the dormer.
	_bed(Vector3(-3.6, U, cz), PI / 2.0, Vector2(1.4, 2.0), c(Color(0.62, 0.25, 0.28), HarborTown.K_CLOTH), wood)
	_box("wall", Vector3(-1.4, U + 0.5, -5.9), Vector3(0.5, 1.0, 1.0), wood, true)
	_box("steel", Vector3(-1.16, U + 1.3, -5.9), Vector3(0.02, 0.5, 0.6), Color.WHITE)
	_table(Vector3(-4.3, U, cz + 1.2), Vector2(0.4, 0.4), 0.6, wood)
	_lamp_fixture(Vector3(-4.3, U + 0.95, cz + 1.2), "shade", 0.5, 0.45, 4.0)
	m.cylinder("wall", HarborTown.at(Vector3(-4.3, U + 0.73, cz + 1.2)), 0.06, 0.08, 0.24, 10, c(Color(0.8, 0.8, 0.9), HarborTown.K_ENAMEL))
	_armchair(Vector3(-2.4, U, -0.95), PI, c(Color(0.35, 0.3, 0.45), HarborTown.K_CLOTH))
	m.cylinder("wall", Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), Vector3(-3.0, U + 0.006, cz)), 0.9, 0.9, 0.012, 20, c(Color(0.35, 0.45, 0.55), HarborTown.K_CLOTH))
	# East: a boy's room: a narrow bed, a desk under the dormer with a
	# lamp, a model airplane hung from the ceiling, a pennant.
	_bed(Vector3(3.7, U, cz - 0.4), -PI / 2.0, Vector2(0.95, 1.95), c(Color(0.3, 0.38, 0.55), HarborTown.K_CLOTH), wood)
	_table(Vector3(2.4, U, -1.05), Vector2(1.0, 0.5), 0.74, wood)
	_chair(Vector3(2.4, U, -1.55), PI, wood)
	_lamp_fixture(Vector3(2.75, U + 1.05, -1.0), "shade", 0.45, 0.4, 3.5)
	var plane := Vector3(3.4, COLLAR - 0.45, cz)
	m.bar("iron", plane + Vector3(0, 0.1, 0), plane + Vector3(0, 0.45, 0), 0.003, 3, Color(0.8, 0.8, 0.8))
	_box("wall", plane, Vector3(0.5, 0.06, 0.07), c(Color(0.75, 0.62, 0.2), HarborTown.K_ENAMEL))
	_box("wall", plane + Vector3(0.05, 0.01, 0), Vector3(0.1, 0.012, 0.6), c(Color(0.75, 0.62, 0.2), HarborTown.K_ENAMEL))
	_box("wall", plane + Vector3(-0.22, 0.05, 0), Vector3(0.06, 0.1, 0.012), c(Color(0.62, 0.1, 0.08), HarborTown.K_ENAMEL))
	_box("wall", Vector3(4.2, U + 0.45, -5.9), Vector3(0.9, 0.9, 0.45), wood, true)
	var pennant := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(W / 2.0 - T_OUT - T_IN - 0.01, U + 1.6, cz))
	m.tri("wall", pennant * Vector3(-0.4, 0.1, 0), pennant * Vector3(-0.4, -0.1, 0), pennant * Vector3(0.35, 0.0, 0), pennant.basis.z, c(Color(0.55, 0.1, 0.1), HarborTown.K_CLOTH))


## ---- the yard -----------------------------------------------------------------------

## A picket fence and gate along the front, the mailbox by the street,
## lilacs by the door, a clothesline out back with the wash on it.
func _yard() -> void:
	var white := c(TRIM, HarborTown.K_PAINT)
	var z := 3.4
	var x := -6.5
	while x <= 6.5:
		if absf(x) > 0.6:
			_box("wall", Vector3(x, 0.5, z), Vector3(0.07, 1.0, 0.025), white)
		x += 0.13
	for s: Array in [[-6.5, -0.6], [0.6, 6.5]]:
		for y: float in [0.3, 0.8]:
			_box("wall", Vector3((float(s[0]) + float(s[1])) / 2.0, y, z - 0.03), Vector3(float(s[1]) - float(s[0]), 0.07, 0.03), white)
		_solid(Vector3((float(s[0]) + float(s[1])) / 2.0, 0.5, z), Vector3(float(s[1]) - float(s[0]), 1.0, 0.1))
	for s: float in [-1.0, 1.0]:
		_box("wall", Vector3(s * 0.62, 0.6, z), Vector3(0.12, 1.2, 0.12), white)
		m.sphere("wall", HarborTown.at(Vector3(s * 0.62, 1.25, z)), 0.07, 8, white)
	# The gate stands open.
	var gate := Transform3D(Basis(Vector3.UP, 1.3), Vector3(0.55, 0, z))
	for k in 8:
		m.box("wall", gate * HarborTown.at(Vector3(-0.07 - 0.13 * k, 0.5, 0)), Vector3(0.07, 0.95, 0.025), white, true)
	for y: float in [0.3, 0.8]:
		m.box("wall", gate * HarborTown.at(Vector3(-0.53, y, -0.03)), Vector3(1.06, 0.07, 0.03), white, true)
	# A flagstone walk from the gate to the steps.
	for k in 3:
		_box("wall", Vector3(_rng.randf_range(-0.1, 0.1), 0.02, 3.0 - 0.6 * k), Vector3(0.7, 0.04, 0.45), c(HarborTown.GRANITE * 0.9, HarborTown.K_GRANITE))
	# The mailbox on its post at the street.
	_box("wall", Vector3(1.4, 0.55, z + 0.3), Vector3(0.09, 1.1, 0.09), white)
	_box("iron", Vector3(1.4, 1.2, z + 0.3), Vector3(0.2, 0.22, 0.45), Color(0.15, 0.2, 0.18))
	m.cylinder("iron", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(1.4, 1.31, z + 0.3)), 0.1, 0.1, 0.45, 10, Color(0.15, 0.2, 0.18))
	_box("iron", Vector3(1.52, 1.3, z + 0.4), Vector3(0.02, 0.2, 0.04), Color(0.6, 0.1, 0.08))
	# Lilacs either side of the steps, a hydrangea at the corner.
	for p: Vector3 in [Vector3(-2.2, 0, 0.9), Vector3(2.4, 0, 0.9), Vector3(4.6, 0, 1.0)]:
		town._trees.plant_broadleaf(global_transform * p, _rng.randf_range(2.2, 2.8), Color(0.30, 0.38, 0.16), _rng)
	# The clothesline: two T posts, three lines, sheets and a shirt.
	var yard := Vector3(0, 0, -D - 2.6)
	for s: float in [-1.0, 1.0]:
		var post := yard + Vector3(s * 3.5, 0, 0)
		var foot := global_transform * post
		post.y = town.coast.height_at(foot.x, foot.z) - global_position.y
		_box("wall", post + Vector3(0, 1.1, 0), Vector3(0.1, 2.2, 0.1), c(Color(0.5, 0.48, 0.44), HarborTown.K_TIMBER), true)
		_box("wall", post + Vector3(0, 2.1, 0), Vector3(0.1, 0.08, 1.0), c(Color(0.5, 0.48, 0.44), HarborTown.K_TIMBER))
	for k in 3:
		var lz := yard.z - 0.4 + 0.4 * k
		m.bar("iron", Vector3(-3.5, 2.12, lz), Vector3(3.5, 2.12, lz), 0.004, 3, Color(0.85, 0.85, 0.8))
	var sheet := c(Color(0.95, 0.95, 0.92), HarborTown.K_CLOTH)
	for x2: float in [-2.2, -0.9]:
		m.box("wall", Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(x2, 1.55, yard.z - 0.4)), Vector3(1.2, 1.1, 0.01), sheet)
	m.box("wall", Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(1.2, 1.75, yard.z)), Vector3(0.55, 0.7, 0.01), c(Color(0.55, 0.65, 0.8), HarborTown.K_CLOTH))
	m.box("wall", Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(2.4, 1.8, yard.z + 0.4)), Vector3(0.35, 0.6, 0.01), c(Color(0.62, 0.12, 0.1), HarborTown.K_CLOTH))


## ---- every frame -------------------------------------------------------------------


## Whether the next window is one left open.
func _opens() -> bool:
	_window_count += 1
	return open_windows.has(_window_count)
