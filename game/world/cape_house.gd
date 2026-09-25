class_name CapeHouse
extends Node3D
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
const T_OUT := 0.1           # clapboard and sheathing
const T_IN := 0.05           # plaster
const KNEE := 1.3            # knee walls stand this far in from the eaves
const PLASTER_UNDER := 0.07  # the sloped ceilings hang this far under the rafters
const COLLAR := 5.5          # the flat ceiling upstairs
const STAIR_X := Vector2(-0.95, -0.1)
const STAIR_Z := Vector2(-1.0, -4.2)
const DORMERS: Array[float] = [-2.4, 2.4]
const DORMER_HALF := 0.75
const DORMER_FACE := 0.45    # the dormers' faces stand this far back from the eaves
const DORMER_EAVE := 5.35

const CLAP := Color(0.90, 0.82, 0.55)
const TRIM := Color(0.93, 0.92, 0.88)
const SHUTTER := Color(0.10, 0.16, 0.12)
const DOOR := Color(0.50, 0.09, 0.08)
const ROOF := Color(0.24, 0.27, 0.25)
const PLASTER := Color(0.90, 0.88, 0.82)
const OAK := Color(0.62, 0.42, 0.24)

var town: HarborTown
var m := TownMesh.new()
var glass_mat: StandardMaterial3D
var ember_mat: StandardMaterial3D
var stats: Dictionary = {}
var _fire: OmniLight3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _lit_fire := 0.0


func build(t: HarborTown, front: Vector3, yaw: float) -> void:
	town = t
	name = "CapeHouse"
	transform = HarborTown.at(front, yaw)
	_rng.seed = 1938
	glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.80, 0.86, 0.90, 0.10)
	glass_mat.roughness = 0.04
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ember_mat = ViewUtil.glow(Color(1.0, 0.42, 0.12), 0.0)
	_shell()
	_roof()
	_dormers()
	_chimney()
	_floors()
	_stair()
	_partitions()
	_openings()
	_living_room()
	_dining_room()
	_kitchen()
	_hall()
	_bath()
	_bedrooms()
	_yard()
	m.commit(self, {"wall": town.wall_mat, "iron": town.iron_mat, "steel": town.steel_mat, "lamp": town.lamp_mat,
		"clear": glass_mat}, ["wall", "iron"])
	stats = {"triangles": m.triangles, "lights": _lights}


## ---- helpers -----------------------------------------------------------------

static func c(color: Color, kind: int) -> Color:
	return HarborTown.kc(color, kind)


## A slab along the plan segment p0 to p1 (x, z), t thick, from y0 up
## to a top that runs from top0 over p0 to top1 over p1.
func _slab(key: String, p0: Vector2, p1: Vector2, y0: float, top0: float, top1: float, t: float, col: Color,
		solid := false) -> void:
	if p0.distance_to(p1) < 0.005 or (top0 <= y0 + 0.003 and top1 <= y0 + 0.003):
		return
	var d := (p1 - p0).normalized()
	var n := Vector2(-d.y, d.x) * (t / 2.0)
	var a0 := p0 - n
	var a1 := p0 + n
	var b0 := p1 - n
	var b1 := p1 + n
	var v := func(p: Vector2, y: float) -> Vector3: return Vector3(p.x, y, p.y)
	var n3 := Vector3(n.x, 0, n.y).normalized()
	var d3 := Vector3(d.x, 0, d.y)
	m.quad(key, v.call(a0, y0), v.call(a0, top0), v.call(b0, top1), v.call(b0, y0), -n3, col)
	m.quad(key, v.call(a1, y0), v.call(a1, top0), v.call(b1, top1), v.call(b1, y0), n3, col)
	var up := (d3 * -(top1 - top0) / p0.distance_to(p1) + Vector3.UP).normalized()
	m.quad(key, v.call(a0, top0), v.call(a1, top0), v.call(b1, top1), v.call(b0, top1), up, col)
	m.quad(key, v.call(a0, y0), v.call(a0, top0), v.call(a1, top0), v.call(a1, y0), -d3, col)
	m.quad(key, v.call(b0, y0), v.call(b0, top1), v.call(b1, top1), v.call(b1, y0), d3, col)
	m.quad(key, v.call(a0, y0), v.call(a1, y0), v.call(b1, y0), v.call(b0, y0), Vector3.DOWN, col)
	if solid:
		var mid := (p0 + p1) / 2.0
		var low := minf(top0, top1)
		_solid(Vector3(mid.x, (y0 + low) / 2.0, mid.y), Vector3(t, low - y0, p0.distance_to(p1)),
			Basis(Vector3.UP, atan2(d.x, d.y)))


## A wall along p0 to p1 with openings cut in it: each [from, to, sill,
## head] in metres along the wall. top(p) gives its top over a plan
## point; breaks (metres along) are where that top bends.
func _wall(key: String, p0: Vector2, p1: Vector2, y0: float, top: Callable, openings: Array, t: float,
		col: Color, solid := false, breaks: Array = []) -> void:
	var length := p0.distance_to(p1)
	var d := (p1 - p0) / length
	var cuts: Array[float] = [0.0, length]
	for b: float in breaks:
		if b > 0.0 and b < length:
			cuts.append(b)
	for o: Array in openings:
		cuts.append(clampf(float(o[0]), 0.0, length))
		cuts.append(clampf(float(o[1]), 0.0, length))
	cuts.sort()
	for i in cuts.size() - 1:
		var u0 := cuts[i]
		var u1 := cuts[i + 1]
		if u1 - u0 < 0.002:
			continue
		var q0 := p0 + d * u0
		var q1 := p0 + d * u1
		var t0: float = top.call(q0)
		var t1: float = top.call(q1)
		var hole: Array = []
		for o: Array in openings:
			if (u0 + u1) / 2.0 > float(o[0]) and (u0 + u1) / 2.0 < float(o[1]):
				hole = o
		if hole.is_empty():
			_slab(key, q0, q1, y0, t0, t1, t, col, solid)
		else:
			_slab(key, q0, q1, y0, float(hole[2]), float(hole[2]), t, col, solid)
			_slab(key, q0, q1, float(hole[3]), maxf(t0, float(hole[3])), maxf(t1, float(hole[3])), t, col, solid)


func _box(key: String, centre: Vector3, size: Vector3, col: Color, solid := false, yaw := 0.0) -> void:
	m.box(key, HarborTown.at(centre, yaw), size, col, true)
	if solid:
		_solid(centre, size, Basis(Vector3.UP, yaw))


func _solid(centre: Vector3, size: Vector3, basis := Basis()) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, centre)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## A ramp for the player's feet from a (low) to b (high), w wide; the
## player has no step, so every stair and stoop is a slope underfoot.
func _ramp(a: Vector3, b: Vector3, w: float) -> void:
	var run := Vector2(b.x - a.x, b.z - a.z)
	var rise := b.y - a.y
	var length := sqrt(run.length_squared() + rise * rise)
	var yaw := atan2(-run.x, -run.y)
	var tilt := atan2(rise, run.length())
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var normal := basis.y
	_solid((a + b) / 2.0 - normal * 0.05, Vector3(w, 0.1, length), basis)


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

var _lights := 0


## Foundation, the four outer walls (clapboard out, plaster or paper in),
## corner boards, water table and frieze.
func _shell() -> void:
	var gran := c(HarborTown.GRANITE, HarborTown.K_GRANITE)
	_box("wall", Vector3(0, 0.3, -D / 2.0), Vector3(W + 0.06, 0.6, D + 0.06), gran)
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
	var paper_living := c(Color(0.62, 0.70, 0.58), HarborTown.K_PAPER)
	var paper_dining := c(Color(0.80, 0.62, 0.58), HarborTown.K_PAPER)
	var hall := c(Color(0.86, 0.82, 0.70), HarborTown.K_PLASTER)
	var kitchen := c(Color(0.92, 0.88, 0.66), HarborTown.K_ENAMEL)
	var xi := W / 2.0 - T_OUT
	_inner_run(Vector2(-xi, zi), Vector2(xi, zi), front, [[-1.0, paper_living], [1.0, hall], [xi, paper_dining]], F, ceil1)
	_inner_run(Vector2(-xi, -D - zi), Vector2(xi, -D - zi), back, [[-1.0, paper_living], [1.0, c(Color(0.82, 0.90, 0.88), HarborTown.K_TILE)], [xi, kitchen]], F, ceil1)
	_inner_end(-1.0, [[-D + T_OUT, paper_living]], F, ceil1)
	_inner_end(1.0, [[-4.0, paper_dining], [-D + T_OUT, kitchen]], F, ceil1)
	# Upstairs: the gable ends' plaster between the knee walls, under
	# the ceiling's profile.
	var bed := c(Color(0.86, 0.84, 0.90), HarborTown.K_PAPER)
	var bed2 := c(Color(0.88, 0.84, 0.70), HarborTown.K_PAPER)
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
func _roof_piece(side: float, x0: float, x1: float, s0: float, s1: float, col: Color, t := 0.15, under := 0.0) -> void:
	var n := Vector3(0, 0.7071, 0.7071 * side)
	var s_mid := (s0 + s1) / 2.0
	var z_mid := -s_mid if side > 0.0 else -D + s_mid
	var centre := Vector3((x0 + x1) / 2.0, rafter(s_mid), z_mid) + n * (t / 2.0 - under)
	var bx := Vector3(1, 0, 0)
	var bz := bx.cross(n)
	m.box("wall", Transform3D(Basis(bx, n, bz), centre), Vector3(x1 - x0, t, (s1 - s0) * 1.41421), col, true)


func _roof() -> void:
	var shingle := c(ROOF, HarborTown.K_ROOF)
	var plaster := c(PLASTER, HarborTown.K_PLASTER)
	var ridge := D / 2.0
	var over := 0.35
	var xw := W / 2.0 + 0.3
	# The back slope whole; the front round the dormers' openings.
	_roof_piece(-1.0, -xw, xw, -over, ridge + 0.1, shingle)
	var hole_lo := DORMER_FACE
	var hole_hi := DORMER_EAVE - E
	var xs: Array[float] = [-xw]
	for dx in DORMERS:
		xs.append(dx - DORMER_HALF)
		xs.append(dx + DORMER_HALF)
	xs.append(xw)
	for i in range(0, xs.size(), 2):
		_roof_piece(1.0, xs[i], xs[i + 1], -over, ridge + 0.1, shingle)
	for dx in DORMERS:
		_roof_piece(1.0, dx - DORMER_HALF, dx + DORMER_HALF, -over, hole_lo, shingle)
		_roof_piece(1.0, dx - DORMER_HALF, dx + DORMER_HALF, hole_hi, ridge + 0.1, shingle)
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
		_window_unit(Vector3(dx, U + 1.27, zf), 0.8, 1.1, 0.0, false, T_OUT + 0.06)
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
func _stair() -> void:
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
		_window_unit(Vector3(x, F + 1.475, 0.0), 0.9, 1.45, 0.0, true, T_OUT + T_IN)
	for x: float in [-3.0, 2.7]:
		var sill := F + 0.75 if x < 0.0 else F + 1.0
		_window_unit(Vector3(x, (sill + F + 2.2) / 2.0, -D), 0.9, F + 2.2 - sill, PI, false, T_OUT + T_IN)
	_window_unit(Vector3(0.0, F + 1.825, -D), 0.6, 0.75, PI, false, T_OUT + T_IN)
	for s: float in [-1.0, 1.0]:
		var yaw := s * PI / 2.0
		var first: Array[float] = [1.7, 6.3]
		if s > 0.0:
			first = [2.0, 6.6]
		for z in first:
			_window_unit(Vector3(s * W / 2.0, F + 1.475, -z), 0.9, 1.45, yaw, false, T_OUT + T_IN)
		for z: float in [2.9, 5.1]:
			_window_unit(Vector3(s * W / 2.0, U + 1.375, -z), 0.8, 1.15, yaw, false, T_OUT + T_IN)
	_front_door()
	_back_door()


## A double-hung window in a wall whose outer face passes through
## centre, facing out along yaw (0: +z). Casing and sill outside,
## shutters if asked, the two sashes with six lights each, a stool and
## casing inside, a radiator under it downstairs.
func _window_unit(centre: Vector3, w: float, h: float, yaw: float, shutters: bool, depth: float) -> void:
	var xf := HarborTown.at(centre, yaw)
	var trim := c(TRIM, HarborTown.K_PAINT)
	var inner := c(TRIM, HarborTown.K_ENAMEL)
	# Outside: casing round, a sill, a drip cap.
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.07, 0.03)), Vector3(w + 0.3, 0.14, 0.06), trim, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.16, 0.05)), Vector3(w + 0.36, 0.04, 0.1), trim, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.04, 0.05)), Vector3(w + 0.34, 0.06, 0.12), trim, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 + 0.07), 0, 0.03)), Vector3(0.14, h, 0.06), trim, true)
	if shutters:
		for s: float in [-1.0, 1.0]:
			var sx := s * (w / 2.0 + 0.14 + w * 0.25)
			m.box("wall", xf * HarborTown.at(Vector3(sx, 0, 0.04)), Vector3(w * 0.5, h + 0.1, 0.03), c(SHUTTER, HarborTown.K_PAINT), true)
			for k in 8:
				m.box("wall", xf * HarborTown.at(Vector3(sx, -h / 2.0 + 0.12 + k * (h - 0.2) / 8.0, 0.058)), Vector3(w * 0.42, 0.02, 0.01), c(SHUTTER * 0.8, HarborTown.K_PAINT), true)
	# The jambs through the wall's thickness.
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 - 0.01), 0, -depth / 2.0)), Vector3(0.02, h, depth), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 - 0.01, -depth / 2.0)), Vector3(w, 0.02, depth), inner, true)
	# The sashes: the lower one set in front of the upper, each a frame
	# with a meeting rail and muntins, six panes of glass.
	var zs: Array[float] = [-0.05, -0.08]
	for k in 2:
		var cy := h / 4.0 if k == 0 else -h / 4.0
		var sz := zs[k]
		var sh := h / 2.0
		var frame := c(TRIM, HarborTown.K_ENAMEL)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy + sh / 2.0 - 0.025, sz)), Vector3(w, 0.05, 0.04), frame, true)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy - sh / 2.0 + 0.03, sz)), Vector3(w, 0.06, 0.04), frame, true)
		for s: float in [-1.0, 1.0]:
			m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 - 0.025), cy, sz)), Vector3(0.05, sh, 0.04), frame, true)
		for f: float in [-1.0 / 6.0, 1.0 / 6.0]:
			m.box("wall", xf * HarborTown.at(Vector3(f * w, cy, sz)), Vector3(0.018, sh - 0.08, 0.025), frame, true)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy, sz)), Vector3(w - 0.08, 0.018, 0.025), frame, true)
		var n := (xf.basis * Vector3(0, 0, 1)).normalized()
		var lo := xf * Vector3(-w / 2.0 + 0.05, cy - sh / 2.0 + 0.05, sz)
		var hi := xf * Vector3(w / 2.0 - 0.05, cy + sh / 2.0 - 0.04, sz)
		m.quad("clear", lo, xf * Vector3(-w / 2.0 + 0.05, cy + sh / 2.0 - 0.04, sz), hi,
			xf * Vector3(w / 2.0 - 0.05, cy - sh / 2.0 + 0.05, sz), n, Color.WHITE)
	# Inside: the stool, the apron, the casing.
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.02, -depth - 0.06)), Vector3(w + 0.2, 0.035, 0.14), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.1, -depth - 0.015)), Vector3(w + 0.12, 0.1, 0.03), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.06, -depth - 0.015)), Vector3(w + 0.24, 0.12, 0.03), inner, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 + 0.05), 0, -depth - 0.015)), Vector3(0.1, h, 0.03), inner, true)
	# A cast-iron radiator under a first-floor window.
	if centre.y < E:
		var rad := xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.45, -depth - 0.14))
		for k in 9:
			m.box("iron", rad * HarborTown.at(Vector3(-0.32 + 0.08 * k, 0, 0)), Vector3(0.05, 0.55, 0.14), Color(0.72, 0.72, 0.7))
		m.cylinder("iron", rad * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, -0.2, 0)), 0.02, 0.02, 0.72, 6, Color(0.72, 0.72, 0.7))


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


## A lamp: its shade or globe glowing, a light, lighting at the
## darkness thr. kind names its fixture.
func _lamp_fixture(pos: Vector3, kind: String, thr: float, energy: float, range_m := 5.0) -> void:
	var glow := ViewUtil.glow(Color(1.0, 0.78, 0.5), 0.0)
	glow.albedo_color = Color(0.95, 0.88, 0.72)
	var shade := MeshInstance3D.new()
	match kind:
		"porch":
			var lantern := CylinderMesh.new()
			lantern.top_radius = 0.07
			lantern.bottom_radius = 0.09
			lantern.height = 0.26
			shade.mesh = lantern
			m.box("iron", HarborTown.at(pos + Vector3(0, 0.17, 0)), Vector3(0.2, 0.04, 0.2), Color(0.08, 0.08, 0.08))
			m.box("iron", HarborTown.at(pos + Vector3(0, 0.0, -0.08)), Vector3(0.04, 0.3, 0.04), Color(0.08, 0.08, 0.08))
		"ceiling":
			var bowl := SphereMesh.new()
			bowl.radius = 0.18
			bowl.height = 0.18
			bowl.is_hemisphere = true
			shade.mesh = bowl
			shade.rotation.x = PI
			m.cylinder("iron", HarborTown.at(pos + Vector3(0, 0.06, 0)), 0.04, 0.04, 0.12, 8, Color(0.7, 0.6, 0.35))
		"pendant":
			var bowl := SphereMesh.new()
			bowl.radius = 0.22
			bowl.height = 0.22
			bowl.is_hemisphere = true
			shade.mesh = bowl
			shade.rotation.x = PI
			m.bar("iron", pos + Vector3(0, 0.02, 0), pos + Vector3(0, 0.9, 0), 0.008, 4, Color(0.7, 0.6, 0.35))
		_:
			# A table or floor lamp's pleated shade.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.13
			cone.bottom_radius = 0.22
			cone.height = 0.26
			cone.cap_top = false
			cone.cap_bottom = false
			shade.mesh = cone
			glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	shade.position = pos
	shade.material_override = glow
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shade)
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, -0.12, 0)
	light.omni_range = range_m
	light.omni_attenuation = 1.3
	light.light_color = Color(1.0, 0.74, 0.45)
	light.shadow_enabled = false
	add_child(light)
	_lights += 1
	town.lamps.append({"light": light, "thr": thr, "energy": energy, "mat": glow, "glow": 2.5})


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
	for k in 3:
		m.cylinder("wall", Transform3D(Basis(Vector3.RIGHT, PI / 2.0).rotated(Vector3.UP, 0.2 * k - 0.2), Vector3(xw + 0.25, F + 0.12 + 0.08 * (k % 2), cz - 0.15 + 0.15 * k)),
			0.05, 0.05, 0.5, 6, c(Color(0.3, 0.2, 0.12), HarborTown.K_TIMBER))
	var embers := MeshInstance3D.new()
	var bed := BoxMesh.new()
	bed.size = Vector3(0.3, 0.05, 0.55)
	embers.mesh = bed
	embers.material_override = ember_mat
	embers.position = Vector3(xw + 0.25, F + 0.08, cz)
	add_child(embers)
	_fire = OmniLight3D.new()
	_fire.position = Vector3(xw + 0.7, F + 0.45, cz)
	_fire.omni_range = 5.0
	_fire.light_color = Color(1.0, 0.55, 0.25)
	_fire.light_energy = 0.0
	_fire.shadow_enabled = true
	add_child(_fire)
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


func _armchair(at_: Vector3, yaw: float, cloth: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.22, 0)), Vector3(0.75, 0.3, 0.75), cloth, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.62, -0.3)), Vector3(0.75, 0.6, 0.18), cloth, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * 0.32, 0.45, 0.02)), Vector3(0.14, 0.3, 0.7), cloth, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.42, 0.06)), Vector3(0.5, 0.12, 0.55), c(cloth * 1.1, HarborTown.K_CLOTH), true)
	_solid(xf * Vector3(0, 0.4, -0.05), Vector3(0.7, 0.8, 0.7), xf.basis)


func _table(at_: Vector3, top: Vector2, height: float, wood: Color) -> void:
	_box("wall", at_ + Vector3(0, height - 0.02, 0), Vector3(top.x, 0.04, top.y), wood, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box("wall", at_ + Vector3(sx * (top.x / 2.0 - 0.05), (height - 0.04) / 2.0, sz * (top.y / 2.0 - 0.05)), Vector3(0.04, height - 0.04, 0.04), wood)


func _chair(at_: Vector3, yaw: float, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.45, 0)), Vector3(0.42, 0.04, 0.42), wood, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.box("wall", xf * HarborTown.at(Vector3(sx * 0.18, 0.22, sz * 0.18)), Vector3(0.035, 0.45, 0.035), wood, true)
	for sx: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(sx * 0.18, 0.7, -0.19)), Vector3(0.035, 0.5, 0.035), wood, true)
	for k in 3:
		m.box("wall", xf * HarborTown.at(Vector3(0, 0.62 + 0.13 * k, -0.19)), Vector3(0.36, 0.05, 0.025), wood, true)


func _picture(centre: Vector3, yaw: float, size: Vector2, canvas: Color) -> void:
	var xf := HarborTown.at(centre, yaw)
	m.box("wall", xf, Vector3(size.x + 0.08, size.y + 0.08, 0.03), c(Color(0.5, 0.38, 0.18), HarborTown.K_WOOD), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0, 0.012)), Vector3(size.x, size.y, 0.01), c(canvas, HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -size.y * 0.2, 0.018)), Vector3(size.x, size.y * 0.25, 0.005), c(canvas * 0.6, HarborTown.K_CLOTH), true)


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


func _bed(at_: Vector3, yaw: float, size: Vector2, quilt: Color, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.3, 0)), Vector3(size.x, 0.25, size.y), c(Color(0.9, 0.9, 0.86), HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.44, 0.1)), Vector3(size.x + 0.04, 0.06, size.y - 0.2), quilt, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.46, -size.y / 2.0 + 0.22)), Vector3(size.x - 0.2, 0.12, 0.32), c(Color(0.94, 0.93, 0.9), HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.55, -size.y / 2.0 - 0.03)), Vector3(size.x + 0.08, 1.1, 0.06), wood, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.35, size.y / 2.0 + 0.03)), Vector3(size.x + 0.08, 0.7, 0.06), wood, true)
	_solid(xf * Vector3(0, 0.3, 0), Vector3(size.x, 0.6, size.y), xf.basis)


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

## The fire: lit once it is dusk, flickering on two quick cycles and a
## slow one, the embers breathing with it.
func _process(delta: float) -> void:
	_t += delta
	var night: float = town.glass_mat.get_shader_parameter("night")
	var target := 1.0 if night > 0.3 else 0.0
	_lit_fire = move_toward(_lit_fire, target, delta * 0.2)
	var flicker := 0.75 + 0.12 * sin(_t * 11.0) + 0.08 * sin(_t * 17.3 + 1.0) + 0.1 * sin(_t * 2.1)
	_fire.light_energy = 1.6 * flicker * _lit_fire
	_fire.visible = _lit_fire > 0.01
	ember_mat.emission_energy_multiplier = (2.5 + 1.5 * flicker) * _lit_fire
