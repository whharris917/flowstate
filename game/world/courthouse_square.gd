class_name CourthouseSquare
extends Node3D
## The courthouse square in Monroe and the blocks round it. The square
## is a lawn a little over sixty metres on a side, bounded by North Main
## Street on the west, North Hayne on the east, West Jefferson on the
## north and West Franklin on the south, each with parking along its
## kerbs. Brick walks cross it: a plaza before each porch (the
## Confederate monument of 1910 stands in the western one), a walk to
## each end door, and walks out from the main block's corners. Granite
## posts hung with chain edge the lawns; magnolias and oaks shade them;
## iron lamps on posts light the walks. Round the square, the town's
## two- and three-storey brick shopfronts, and to the north the county's
## newer government buildings.
##
## Frame: the courthouse's, +x east, -z north. Art only: no records.

const CURB_W := -31.0          # the square's kerb on North Main Street
const CURB_E := 31.0           # on North Hayne
const CURB_N := -31.0          # on West Jefferson
const CURB_S := 30.6           # on West Franklin
const MAIN_W := -50.5          # North Main's far kerb
const HAYNE_E := 50.0
const JEFF_N := -50.5
const FRANK_S := 44.6
const WALK := 3.4              # the outer walks' width
const REACH := 140.0           # how far the streets run each way
const LAWN_IN := 2.4           # the square's walk inside its kerb

const BRICK_WALK := Color(0.55, 0.25, 0.18)
const GRANITE := Color(0.70, 0.69, 0.66)
const IRON := Color(0.05, 0.05, 0.055)
const LAWN := Color(0.30, 0.40, 0.17)
const SLATE := Color(0.25, 0.27, 0.30)
const TRIM := Color(0.90, 0.88, 0.82)
const BRICKS: Array[Color] = [Color(0.55, 0.27, 0.20), Color(0.60, 0.33, 0.24), Color(0.48, 0.24, 0.18), Color(0.66, 0.40, 0.30),
	Color(0.52, 0.30, 0.22), Color(0.70, 0.62, 0.52), Color(0.82, 0.80, 0.74)]
const AWNINGS: Array[Color] = [Color(0.12, 0.22, 0.14), Color(0.45, 0.10, 0.08), Color(0.12, 0.16, 0.30), Color(0.20, 0.20, 0.20)]

var k: CourthouseKit
var stats: Dictionary = {}
var lamp_mat: StandardMaterial3D
var glass_mat: ShaderMaterial
var street_mat: ShaderMaterial
var lights: Array[Dictionary] = []
var _trees: Forest
var _rng := RandomNumberGenerator.new()


func build() -> void:
	name = "CourthouseSquare"
	var t0 := Time.get_ticks_msec()
	_rng.seed = 1886
	var solids := Node3D.new()
	solids.name = "Solids"
	add_child(solids)
	k = CourthouseKit.new(solids)
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = load("res://world/town_glass.gdshader")
	street_mat = ShaderMaterial.new()
	street_mat.shader = load("res://world/street.gdshader")
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.96, 0.88)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.82, 0.58)
	var iron_mat := StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.vertex_color_is_srgb = true
	iron_mat.metallic = 0.4
	iron_mat.roughness = 0.5
	_trees = Forest.new()
	_trees.name = "SquareTrees"
	_ground()
	_streets()
	_square()
	_monument(Vector3(-22.5, 0, 0))
	_planting()
	_furniture()
	_town()
	k.m.commit(self, {"wall": wall_mat, "lamp": lamp_mat, "glass": glass_mat, "street": street_mat, "iron": iron_mat},
		["wall", "iron"])
	_trees.finish(true, false, true)
	add_child(_trees)
	stats = {"triangles": k.m.triangles, "solids": k.solid_count, "ms": Time.get_ticks_msec() - t0}


## How dark it is, 0 day to 1 night: the lamps and the shop windows.
func set_darkness(dark: float) -> void:
	var on := smoothstep(0.35, 0.6, dark)
	lamp_mat.emission_energy_multiplier = 3.0 * on
	glass_mat.set_shader_parameter("night", dark)
	for l: Dictionary in lights:
		var light := l["light"] as OmniLight3D
		light.visible = on > 0.01
		light.light_energy = float(l["energy"]) * on


func c(col: Color, kind: int) -> Color:
	return CourthouseKit.kc(col, kind)


## A flat rectangle at height y (a street, a walk, a lawn) with its UV in
## metres: across the first axis, along the second.
func _flat(key: String, x0: float, z0: float, x1: float, z1: float, y: float, col: Color, along_z := true) -> void:
	var a := Vector3(x0, y, z0)
	var b := Vector3(x1, y, z0)
	var cc := Vector3(x1, y, z1)
	var d := Vector3(x0, y, z1)
	var cx := (x0 + x1) / 2.0
	var cz := (z0 + z1) / 2.0
	if along_z:
		k.m.quad(key, a, b, cc, d, Vector3.UP, col, Vector2(x0 - cx, z0), Vector2(x1 - cx, z0), Vector2(x1 - cx, z1), Vector2(x0 - cx, z1))
	else:
		k.m.quad(key, a, b, cc, d, Vector3.UP, col, Vector2(z0 - cz, x0), Vector2(z0 - cz, x1), Vector2(z1 - cz, x1), Vector2(z1 - cz, x0))


## A flat quad through four points (x, z) at height y.
func _flat4(key: String, pts: Array, y: float, col: Color) -> void:
	var p: Array[Vector3] = []
	for q: Vector2 in pts:
		p.append(Vector3(q.x, y, q.y))
	k.m.quad(key, p[0], p[1], p[2], p[3], Vector3.UP, col, Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z),
		Vector2(p[2].x, p[2].z), Vector2(p[3].x, p[3].z))


## ---- the ground and the streets --------------------------------------------

func _ground() -> void:
	# The town's ground past the streets: worn grass, the square's lawn
	# greener, laid over it.
	_flat("wall", -600, -600, 600, 600, 0.0, c(Color(0.36, 0.40, 0.22), CourthouseKit.K_LAWN))
	_flat("wall", CURB_W, CURB_N, CURB_E, CURB_S, 0.004, c(LAWN, CourthouseKit.K_LAWN))


func _streets() -> void:
	var asphalt := Color(0, 0, 0, 0.0)
	var lined := Color(1, 0, 0, 0.0)
	# North Main and North Hayne, running north and south.
	for st: Vector2 in [Vector2(MAIN_W, CURB_W), Vector2(CURB_E, HAYNE_E)]:
		var cx := (st.x + st.y) / 2.0
		_flat("street", st.x, -REACH, cx, REACH, 0.01, asphalt)
		_flat("street", cx, -REACH, st.y, REACH, 0.01, asphalt)
		_flat("street", cx - 0.1, -REACH, cx + 0.1, REACH, 0.011, lined)
	# West Jefferson and West Franklin, east and west.
	for st: Vector2 in [Vector2(JEFF_N, CURB_N), Vector2(CURB_S, FRANK_S)]:
		var cz := (st.x + st.y) / 2.0
		_flat("street", -REACH, st.x, REACH, st.y, 0.014, asphalt, false)
		_flat("street", -REACH, cz - 0.1, REACH, cz + 0.1, 0.015, lined, false)
	# The walks: the square's own inside its kerbs, the town's outside.
	_walk_ring(Rect2(CURB_W, CURB_N, CURB_E - CURB_W, CURB_S - CURB_N), LAWN_IN, true)
	for block: Rect2 in [Rect2(-REACH, -REACH, MAIN_W + REACH, JEFF_N + REACH), Rect2(-REACH, CURB_N, MAIN_W + REACH, CURB_S - CURB_N),
			Rect2(-REACH, FRANK_S, MAIN_W + REACH, REACH - FRANK_S), Rect2(CURB_W, -REACH, CURB_E - CURB_W, JEFF_N + REACH),
			Rect2(CURB_W, FRANK_S, CURB_E - CURB_W, REACH - FRANK_S), Rect2(HAYNE_E, -REACH, REACH - HAYNE_E, JEFF_N + REACH),
			Rect2(HAYNE_E, CURB_N, REACH - HAYNE_E, CURB_S - CURB_N), Rect2(HAYNE_E, FRANK_S, REACH - HAYNE_E, REACH - FRANK_S)]:
		_walk_ring(block, WALK, false)
	# Brick crossings at the square's corners, a brick band at each kerb.
	var brick := c(BRICK_WALK, CourthouseKit.K_PAVER)
	for x: float in [CURB_W - 1.5, CURB_E + 1.5]:
		for zz: Vector2 in [Vector2(JEFF_N, CURB_N), Vector2(CURB_S, FRANK_S)]:
			_flat("wall", x - 1.5, zz.x, x + 1.5, zz.y, 0.02, brick)
	for z: float in [CURB_N - 1.5, CURB_S + 1.5]:
		for xx: Vector2 in [Vector2(MAIN_W, CURB_W), Vector2(CURB_E, HAYNE_E)]:
			_flat("wall", xx.x, z - 1.5, xx.y, z + 1.5, 0.022, brick)
	# Angled parking on North Main and North Hayne, both kerbs.
	var paint := c(Color(0.82, 0.82, 0.78), CourthouseKit.K_PAINT)
	for st: Vector2 in [Vector2(MAIN_W, CURB_W), Vector2(CURB_E, HAYNE_E)]:
		for side: float in [-1.0, 1.0]:
			var kerb := st.x if side < 0.0 else st.y
			var z := -REACH + 4.0
			while z < REACH - 4.0:
				var cross := absf(z - CURB_N) < 12.0 or absf(z - CURB_S) < 12.0 or absf(z - JEFF_N) < 4.0 or absf(z - FRANK_S) < 4.0
				if not cross:
					var a := Vector3(kerb, 0.016, z)
					var bb := Vector3(kerb - side * 5.2, 0.016, z + 3.0)
					k.m.box("wall", Transform3D(Basis(Vector3.UP, atan2(bb.x - a.x, bb.z - a.z)), (a + bb) / 2.0),
						Vector3(0.1, 0.01, a.distance_to(bb)), paint)
				z += 2.9


## A walk round the inside of a rectangle, w wide, raised 12 cm with a
## granite kerb at its outer (street) edge; square: the kerb is outside
## the rectangle's edge rather than in.
func _walk_ring(r: Rect2, w: float, square: bool) -> void:
	var y := 0.12
	var concrete := Color(0, 0, 0, 0.5)
	var kerb := c(GRANITE, CourthouseKit.K_STONE)
	var sides := [[Rect2(r.position.x, r.position.y, r.size.x, w), true], [Rect2(r.position.x, r.end.y - w, r.size.x, w), true],
		[Rect2(r.position.x, r.position.y + w, w, r.size.y - 2.0 * w), false], [Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2.0 * w), false]]
	for sd: Array in sides:
		var q := sd[0] as Rect2
		if q.size.x <= 0.0 or q.size.y <= 0.0:
			continue
		_flat("street", q.position.x, q.position.y, q.end.x, q.end.y, y, concrete, not bool(sd[1]))
	# The kerb round the outside.
	var g := Transform3D()
	k.box("wall", g, Vector3(r.get_center().x, y / 2.0, r.position.y), Vector3(r.size.x, y + 0.02, 0.16), kerb)
	k.box("wall", g, Vector3(r.get_center().x, y / 2.0, r.end.y), Vector3(r.size.x, y + 0.02, 0.16), kerb)
	k.box("wall", g, Vector3(r.position.x, y / 2.0, r.get_center().y), Vector3(0.16, y + 0.02, r.size.y), kerb)
	k.box("wall", g, Vector3(r.end.x, y / 2.0, r.get_center().y), Vector3(0.16, y + 0.02, r.size.y), kerb)
	if square:
		# The lawn inside stands at the walk's height.
		_flat("wall", r.position.x + w, r.position.y + w, r.end.x - w, r.end.y - w, y - 0.01, c(LAWN, CourthouseKit.K_LAWN))
		k.box("wall", g, Vector3(r.get_center().x, (y - 0.02) / 2.0, r.get_center().y), Vector3(r.size.x - 0.2, y - 0.02, r.size.y - 0.2),
			c(Color(0.35, 0.30, 0.24), CourthouseKit.K_TAR))


## ---- the square -----------------------------------------------------------

func _square() -> void:
	var y := 0.125
	var brick := c(BRICK_WALK, CourthouseKit.K_PAVER)
	var gx := CURB_W + LAWN_IN
	# The west plaza, from the walk to the porch steps round the monument.
	_flat("wall", gx - 0.1, -2.2, -16.0, 2.2, y, brick)
	_flat("wall", -28.0, -6.5, -17.0, 6.5, y + 0.002, brick)
	# The east plaza.
	_flat("wall", 16.0, -2.2, CURB_E - LAWN_IN + 0.1, 2.2, y, brick)
	_flat("wall", 17.0, -5.5, 26.0, 5.5, y + 0.002, brick)
	# Brick along the main block's fronts, outside the porches.
	for s: float in [-1.0, 1.0]:
		var x0 := s * 10.2
		var x1 := s * 13.9
		_flat("wall", minf(x0, x1), -9.8, maxf(x0, x1), 9.8, y + 0.001, brick)
	# The walks to the end doors.
	_flat("wall", -1.6, CURB_N + LAWN_IN - 0.1, 1.6, -24.8, y, brick)
	_flat("wall", -1.6, 24.8, 1.6, CURB_S - LAWN_IN + 0.1, y, brick)
	# The walks out from the main block's corners to the square's edges.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var a := Vector2(sx * 12.5, sz * 9.4)
			var bb := Vector2(sx * (16.5 if sz < 0.0 else 20.5), sz * (absf(CURB_N if sz < 0.0 else CURB_S) - LAWN_IN + 0.1))
			var d := (bb - a).normalized()
			var n := Vector2(-d.y, d.x) * 1.0
			_flat4("wall", [a - n, a + n, bb + n, bb - n], y + 0.003, brick)
	# A bed of brick edging round the building's base, where the hedges stand.
	var edge := c(Color(0.28, 0.20, 0.14), CourthouseKit.K_TAR)
	for e: float in [-1.0, 1.0]:
		_flat("wall", -9.6, e * 21.95, 9.6, e * 23.3, y + 0.001, edge)
		for s: float in [-1.0, 1.0]:
			var x0 := s * 8.5
			var x1 := s * 9.9
			_flat("wall", minf(x0, x1), minf(e * 8.65, e * 23.3), maxf(x0, x1), maxf(e * 8.65, e * 23.3), y + 0.001, edge)


## The monument of 1910 in the west plaza: a granite shaft on a
## stepped base and a die, a ball at its top, an iron railing round it.
func _monument(at: Vector3) -> void:
	var g := Transform3D(Basis(), at + Vector3(0, 0.125, 0))
	var stone := c(Color(0.72, 0.71, 0.68), CourthouseKit.K_STONE)
	var y := 0.0
	for tier: Vector2 in [Vector2(3.4, 0.35), Vector2(2.8, 0.35), Vector2(2.2, 0.35)]:
		k.block("wall", g, Vector3(0, y + tier.y / 2.0, 0), Vector3(tier.x, tier.y, tier.x), stone)
		y += tier.y
	k.block("wall", g, Vector3(0, y + 0.75, 0), Vector3(1.6, 1.5, 1.6), stone)
	y += 1.5
	k.box("wall", g, Vector3(0, y + 0.12, 0), Vector3(1.85, 0.24, 1.85), stone)
	y += 0.24
	k.box("wall", g, Vector3(0, y + 0.35, 0), Vector3(1.3, 0.7, 1.3), stone)
	y += 0.7
	# The shaft, tapering, in drums.
	var h := 6.0
	var n := 6
	for j in n:
		var w0 := lerpf(0.95, 0.62, float(j) / n)
		var w1 := lerpf(0.95, 0.62, float(j + 1) / n)
		k.box("wall", g, Vector3(0, y + h * (j + 0.5) / n, 0), Vector3((w0 + w1) / 2.0, h / n - 0.01, (w0 + w1) / 2.0), stone)
	y += h
	k.box("wall", g, Vector3(0, y + 0.12, 0), Vector3(0.82, 0.24, 0.82), stone)
	k.m.sphere("wall", g * Transform3D(Basis(), Vector3(0, y + 0.6, 0)), 0.36, 12, stone)
	# Relief: crossed sabres on the die, crossed rifles on the shaft.
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var f := g * UnionCourthouse.face(d, d * 0.8)
		for s: float in [-1.0, 1.0]:
			k.box_rz("wall", f, Vector3(0, 1.05 + 0.75, 0.02), Vector3(0.05, 1.0, 0.04), s * 0.7, stone)
		var f2 := g * UnionCourthouse.face(d, d * 0.46)
		for s: float in [-1.0, 1.0]:
			k.box_rz("wall", f2, Vector3(0, 4.3, 0.03), Vector3(0.06, 1.6, 0.05), s * 0.35, stone)
	# The railing: iron pipe on posts round the base.
	var r := 2.4
	for side in 4:
		var a0 := TAU * side / 4.0 + PI / 4.0
		var a1 := TAU * (side + 1) / 4.0 + PI / 4.0
		var pa := Vector3(cos(a0), 0, sin(a0)) * r * sqrt(2.0)
		var pb := Vector3(cos(a1), 0, sin(a1)) * r * sqrt(2.0)
		for q in 5:
			var p := pa.lerp(pb, q / 4.0)
			k.m.bar("iron", g * p, g * (p + Vector3(0, 0.75, 0)), 0.03, 6, IRON)
		for hh: float in [0.35, 0.72]:
			k.m.bar("iron", g * (pa + Vector3(0, hh, 0)), g * (pb + Vector3(0, hh, 0)), 0.025, 6, IRON)
	k.solid(g, Vector3(0, 0.4, 0), Vector3(4.8, 0.8, 4.8))


## ---- trees, hedges, lawns ----------------------------------------------

func _planting() -> void:
	var magnolia := Color(0.13, 0.27, 0.10)
	# [where, height, species, leaf]
	for t: Array in [[Vector3(-21.5, 0.12, -13.0), 17.0, "oak", Color(0.72, 0.42, 0.10)],
			[Vector3(-19.0, 0.12, 15.5), 15.0, "oak", magnolia],
			[Vector3(21.0, 0.12, 12.5), 17.0, "oak", Color(0.62, 0.14, 0.06)],
			[Vector3(21.5, 0.12, -11.5), 15.5, "oak", magnolia],
			[Vector3(-22.5, 0.12, -24.0), 13.0, "maple", Color(0.55, 0.50, 0.14)],
			[Vector3(24.0, 0.12, -24.5), 14.0, "elm", Color(0.24, 0.32, 0.10)],
			[Vector3(-24.0, 0.12, 25.0), 12.0, "maple", Color(0.70, 0.30, 0.08)],
			[Vector3(25.5, 0.12, 20.5), 14.0, "oak", Color(0.46, 0.40, 0.12)]]:
		_trees.plant_species(t[0], float(t[1]), str(t[2]), t[3], _rng)
	# Clipped boxwood along the building's base and the plazas' edges.
	var box := Color(0.10, 0.20, 0.08)
	for e: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			_trees.plant_species(Vector3(s * 9.2, 0.12, e * 15.6), 0.9, "hedge", box, _rng, 0.0, Vector3(1.0, 1.0, 12.5))
			_trees.plant_species(Vector3(s * 11.9, 0.12, e * 7.2), 1.0, "hedge", box, _rng, PI / 2.0, Vector3(1.0, 1.0, 3.4))
		_trees.plant_species(Vector3(e * 5.0, 0.12, 22.7), 0.9, "hedge", box, _rng, PI / 2.0, Vector3(1.0, 1.0, 6.5))
		_trees.plant_species(Vector3(e * 5.0, 0.12, -22.7), 0.9, "hedge", box, _rng, PI / 2.0, Vector3(1.0, 1.0, 6.5))
	# Low shrubs and a bed of hollies at the plazas' corners.
	for p: Vector3 in [Vector3(-26.0, 0.12, -8.5), Vector3(-26.0, 0.12, 8.5), Vector3(-15.5, 0.12, -8.0), Vector3(-15.5, 0.12, 8.0),
			Vector3(26.5, 0.12, -7.5), Vector3(26.5, 0.12, 7.5), Vector3(15.5, 0.12, -8.0), Vector3(15.5, 0.12, 8.0)]:
		_trees.plant_species(p, 1.6, "shrub", Color(0.12, 0.24, 0.09), _rng)


## ---- lamps, posts, benches ------------------------------------------------

func _furniture() -> void:
	var g := Transform3D()
	# Granite posts round the lawns with a chain slung between, broken
	# where a walk comes in.
	var gaps: Array[Vector2] = []
	var ring := Rect2(CURB_W + LAWN_IN, CURB_N + LAWN_IN, CURB_E - CURB_W - 2.0 * LAWN_IN, CURB_S - CURB_N - 2.0 * LAWN_IN)
	var sides := [[ring.position, Vector2(ring.end.x, ring.position.y)], [Vector2(ring.end.x, ring.position.y), ring.end],
		[ring.end, Vector2(ring.position.x, ring.end.y)], [Vector2(ring.position.x, ring.end.y), ring.position]]
	var openings: Array[Vector2] = [Vector2(0, ring.position.y), Vector2(0, ring.end.y), Vector2(ring.position.x, 0), Vector2(ring.end.x, 0),
		Vector2(-16.5, ring.position.y), Vector2(16.5, ring.position.y), Vector2(-20.5, ring.end.y), Vector2(20.5, ring.end.y)]
	var stone := c(Color(0.86, 0.85, 0.80), CourthouseKit.K_STONE)
	for sd: Array in sides:
		var a := sd[0] as Vector2
		var bb := sd[1] as Vector2
		var n := int(a.distance_to(bb) / 3.0)
		var prev := Vector3.INF
		for j in n + 1:
			var q := a.lerp(bb, float(j) / n)
			var blocked := false
			for o: Vector2 in openings:
				if q.distance_to(o) < 2.6:
					blocked = true
			if blocked:
				prev = Vector3.INF
				continue
			var p := Vector3(q.x, 0.12, q.y)
			k.box("wall", g, p + Vector3(0, 0.35, 0), Vector3(0.22, 0.7, 0.22), stone)
			k.m.sphere("wall", Transform3D(Basis(), p + Vector3(0, 0.72, 0)), 0.1, 6, stone)
			if prev != Vector3.INF:
				for m2 in 5:
					var t0 := m2 / 5.0
					var t1 := (m2 + 1) / 5.0
					var s0 := 0.15 * sin(PI * t0)
					var s1 := 0.15 * sin(PI * t1)
					k.m.bar("iron", prev.lerp(p, t0) + Vector3(0, 0.6 - s0, 0), prev.lerp(p, t1) + Vector3(0, 0.6 - s1, 0), 0.012, 4, IRON)
			prev = p
	# Iron lamp posts along the walks, a lantern on each.
	for p: Vector3 in [Vector3(-27.0, 0.12, -3.0), Vector3(-27.0, 0.12, 3.0), Vector3(-17.5, 0.12, -3.0), Vector3(-17.5, 0.12, 3.0),
			Vector3(27.0, 0.12, -3.0), Vector3(27.0, 0.12, 3.0), Vector3(17.5, 0.12, -3.0), Vector3(17.5, 0.12, 3.0),
			Vector3(-2.2, 0.12, -27.0), Vector3(2.2, 0.12, 27.0)]:
		_lamp_post(p, absf(p.x) > 20.0 and p.z < 0.0)
	# Benches facing the plazas.
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.0, 1.0]:
			_park_bench(Transform3D(Basis(Vector3.UP, 0.0 if e > 0.0 else PI), Vector3(s * 22.0, 0.12, e * 7.4)))
	# Granite tablets on the lawn either side of the west walk.
	for e: float in [-1.0, 1.0]:
		var tf := Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, -0.35), Vector3(-26.5, 0.4, e * 9.0))
		k.box("wall", tf, Vector3.ZERO, Vector3(1.4, 0.8, 0.22), c(Color(0.58, 0.57, 0.55), CourthouseKit.K_STONE))
	# The state's highway marker at the south-west, and street lamps at
	# the square's corners.
	var marker := Transform3D(Basis(Vector3.UP, PI), Vector3(-7.0, 0.12, 27.5))
	k.m.bar("iron", marker * Vector3(0, 0, 0), marker * Vector3(0, 2.4, 0), 0.04, 6, Color(0.1, 0.1, 0.1))
	k.box("wall", marker, Vector3(0, 2.25, 0.05), Vector3(1.15, 0.8, 0.04), c(Color(0.62, 0.64, 0.66), CourthouseKit.K_ENAMEL))
	k.box("wall", marker, Vector3(0, 2.25, 0.075), Vector3(1.05, 0.7, 0.01), c(Color(0.08, 0.08, 0.08), CourthouseKit.K_PAINT))
	for cx: float in [CURB_W - 0.8, CURB_E + 0.8]:
		for cz: float in [CURB_N - 0.8, CURB_S + 0.8]:
			_street_light(Vector3(cx + signf(cx) * -1.6, 0.12, cz + signf(cz) * -1.6), Vector3(-signf(cx), 0, -signf(cz)))


func _lamp_post(p: Vector3, lit: bool) -> void:
	var g := Transform3D()
	k.m.cylinder("iron", g * Transform3D(Basis(), p + Vector3(0, 0.25, 0)), 0.16, 0.12, 0.5, 8, IRON)
	k.m.cylinder("iron", g * Transform3D(Basis(), p + Vector3(0, 1.8, 0)), 0.06, 0.05, 2.7, 8, IRON)
	k.m.cylinder("iron", g * Transform3D(Basis(), p + Vector3(0, 3.18, 0)), 0.09, 0.09, 0.08, 8, IRON)
	k.m.cylinder("lamp", g * Transform3D(Basis(), p + Vector3(0, 3.45, 0)), 0.15, 0.2, 0.45, 8, Color(1, 1, 1))
	k.m.cylinder("iron", g * Transform3D(Basis(), p + Vector3(0, 3.72, 0)), 0.24, 0.05, 0.15, 8, IRON)
	k.m.sphere("iron", Transform3D(Basis(), p + Vector3(0, 3.83, 0)), 0.05, 6, IRON)
	k.solid(g, p + Vector3(0, 1.5, 0), Vector3(0.15, 3.0, 0.15))
	if lit:
		var light := OmniLight3D.new()
		light.position = p + Vector3(0, 3.4, 0)
		light.omni_range = 14.0
		light.light_color = Color(1.0, 0.84, 0.62)
		light.visible = false
		add_child(light)
		lights.append({"light": light, "energy": 2.0})


## A street light at a corner: a tall black pole with a curved arm out
## over the street along dir, a lantern at its end.
func _street_light(p: Vector3, dir: Vector3) -> void:
	k.m.cylinder("iron", Transform3D(Basis(), p + Vector3(0, 3.5, 0)), 0.1, 0.07, 7.0, 8, IRON)
	var prev := p + Vector3(0, 7.0, 0)
	for j in 6:
		var t := (j + 1) / 6.0
		var q := p + Vector3(0, 7.0 + sin(t * PI * 0.6) * 0.7, 0) + dir * (2.2 * t)
		k.m.bar("iron", prev, q, 0.045, 6, IRON)
		prev = q
	k.m.cylinder("lamp", Transform3D(Basis(), prev - Vector3(0, 0.25, 0)), 0.22, 0.12, 0.3, 8, Color(1, 1, 1))
	k.solid(Transform3D(), p + Vector3(0, 1.5, 0), Vector3(0.2, 3.0, 0.2))


func _park_bench(xf: Transform3D) -> void:
	var wood := c(Color(0.36, 0.24, 0.14), CourthouseKit.K_WOOD)
	for s: float in [-1.0, 1.0]:
		k.box("iron", xf, Vector3(s * 0.8, 0.4, 0.05), Vector3(0.06, 0.8, 0.6), IRON)
	for j in 4:
		k.box("wall", xf, Vector3(0, 0.44, -0.18 + j * 0.12), Vector3(1.8, 0.03, 0.09), wood)
	for j in 3:
		k.box("wall", xf, Vector3(0, 0.6 + j * 0.12, 0.3), Vector3(1.8, 0.09, 0.03), wood)
	k.solid(xf, Vector3(0, 0.4, 0.05), Vector3(1.8, 0.8, 0.6))


## ---- the town round the square ----------------------------------------

func _town() -> void:
	var z0 := CURB_N + WALK
	var z1 := CURB_S - WALK
	var x0 := CURB_W + WALK
	var x1 := CURB_E - WALK
	# Shopfronts facing the square across North Main, North Hayne and
	# West Franklin, each row between the streets that bound its block.
	_row(Vector3(MAIN_W - WALK, 0, z0), Vector3(0, 0, 1), Vector3(1, 0, 0), z1 - z0)
	_row(Vector3(HAYNE_E + WALK, 0, z0), Vector3(0, 0, 1), Vector3(-1, 0, 0), z1 - z0)
	_row(Vector3(x0, 0, FRANK_S + WALK), Vector3(1, 0, 0), Vector3(0, 0, -1), x1 - x0)
	# North of West Jefferson the county's government centre, and the
	# judicial centre across North Hayne from it.
	_government(Vector3(-6.0, 0, JEFF_N - WALK), Vector3(0, 0, 1))
	_judicial(Vector3(HAYNE_E + WALK + 14.0, 0, JEFF_N - WALK))
	# The blocks at the corners: more of the same along the two long streets.
	_row(Vector3(MAIN_W - WALK, 0, -REACH + 12.0), Vector3(0, 0, 1), Vector3(1, 0, 0), JEFF_N - WALK + REACH - 12.0)
	_row(Vector3(MAIN_W - WALK, 0, FRANK_S + WALK), Vector3(0, 0, 1), Vector3(1, 0, 0), REACH - 12.0 - FRANK_S - WALK)
	_row(Vector3(HAYNE_E + WALK, 0, -REACH + 12.0), Vector3(0, 0, 1), Vector3(-1, 0, 0), REACH - 12.0 - 90.0)
	_row(Vector3(HAYNE_E + WALK, 0, FRANK_S + WALK), Vector3(0, 0, 1), Vector3(-1, 0, 0), REACH - 12.0 - FRANK_S - WALK)


## A row of shopfronts from start along dir, their fronts facing `out`,
## length metres of them; a gap now and then for an alley.
func _row(start: Vector3, dir: Vector3, out: Vector3, length: float) -> void:
	var u := 0.0
	while u < length - 5.0:
		var w := _rng.randf_range(6.5, 13.0)
		if u + w > length:
			w = length - u
		var mid := start + dir * (u + w / 2.0)
		var f := Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), mid)
		_shop(f, w)
		u += w
		if _rng.randf() < 0.12:
			u += 4.0


## A commercial building: brick front of two or three storeys, a
## shopfront of plate glass under a sign band and sometimes an awning,
## sash windows above under hoods, a bracketed or corbelled cornice.
## Frame f: origin at the front's middle at grade, x along it, z out.
func _shop(f: Transform3D, w: float) -> void:
	var floors := 2 if _rng.randf() < 0.55 else 3
	var h := 4.8 + 3.8 * (floors - 1) + _rng.randf_range(0.6, 1.4)
	var depth := _rng.randf_range(16.0, 24.0)
	var face_col := BRICKS[_rng.randi() % BRICKS.size()]
	var kind := CourthouseKit.K_BRICK if face_col.r < 0.75 else CourthouseKit.K_PAINT
	var face := c(face_col, kind)
	k.block("wall", f, Vector3(0, h / 2.0, -depth / 2.0), Vector3(w - 0.05, h, depth), face)
	# Roof: tar over the parapet line.
	k.box("wall", f, Vector3(0, h + 0.02, -depth / 2.0), Vector3(w - 0.3, 0.04, depth - 0.3), c(Color(0.25, 0.25, 0.25), CourthouseKit.K_TAR))
	var trim := c(TRIM if _rng.randf() < 0.6 else face_col.darkened(0.3), CourthouseKit.K_PAINT)
	# Cornice.
	if _rng.randf() < 0.6:
		k.cornice(f, -w / 2.0, w / 2.0, h + 0.1, 0.45, trim, 1.2, 0.35, 0.35, false)
	else:
		for j in 3:
			k.box("wall", f, Vector3(0, h - 0.15 - j * 0.14, 0.05 + j * 0.05), Vector3(w - 0.1, 0.12, 0.1 + j * 0.1), face)
	# The shopfront: plate glass on a low panelled base, a recessed door,
	# a sign band over, an awning perhaps.
	var sf := 4.2
	var thr := _rng.randf_range(0.3, 0.7)
	for s: float in [-1.0, 1.0]:
		var gx0 := s * 0.9
		var gx1 := s * (w / 2.0 - 0.4)
		var lo := Vector3(minf(gx0, gx1), 0.7, 0.03)
		var hi := Vector3(maxf(gx0, gx1), sf - 0.9, 0.03)
		k.m.quad("glass", f * lo, f * Vector3(lo.x, hi.y, lo.z), f * hi, f * Vector3(hi.x, lo.y, lo.z), f.basis.z, Color(thr, _rng.randf(), 0.5, _rng.randf()),
			Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
		k.box("wall", f, Vector3((lo.x + hi.x) / 2.0, 0.35, 0.06), Vector3(hi.x - lo.x, 0.7, 0.12), c(Color(0.15, 0.15, 0.14), CourthouseKit.K_PAINT))
	k.m.quad("glass", f * Vector3(-0.8, 0.0, -0.6), f * Vector3(-0.8, 2.6, -0.6), f * Vector3(0.8, 2.6, -0.6), f * Vector3(0.8, 0.0, -0.6),
		f.basis.z, Color(thr, _rng.randf(), 0.5, _rng.randf()), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	for s: float in [-1.0, 1.0]:
		k.box("wall", f, Vector3(s * (w / 2.0 - 0.2), sf / 2.0, 0.08), Vector3(0.4, sf, 0.16), face)
	var band := c(Color(0.12, 0.12, 0.12) if _rng.randf() < 0.5 else face_col.darkened(0.4), CourthouseKit.K_PAINT)
	k.box("wall", f, Vector3(0, sf - 0.45, 0.08), Vector3(w - 0.2, 0.9, 0.12), band)
	if _rng.randf() < 0.45:
		var aw := c(AWNINGS[_rng.randi() % AWNINGS.size()], CourthouseKit.K_CLOTH)
		k.m.box("wall", f * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, sf - 1.15, 0.75)), Vector3(w - 0.6, 0.04, 1.6), aw)
	# Windows above: two over two under hoods.
	var bays := maxi(2, int(w / 2.4))
	var arched := _rng.randf() < 0.35
	for fl in floors - 1:
		var y0 := sf + 0.9 + fl * 3.8
		for bi in bays:
			var u := -w / 2.0 + w * (bi + 0.5) / bays
			var o := CourthouseKit.opening(u, 1.0, y0, y0 + 2.0, "round" if arched else "segment", 0.18)
			k.hood(f, o, trim, 0.12, not arched, true, true)
			var lit := 1.0 if _rng.randf() < 0.4 else _rng.randf_range(0.3, 0.85)
			var lo := Vector3(u - 0.5, y0, 0.02)
			var hi := Vector3(u + 0.5, y0 + 2.0, 0.02)
			k.m.quad("glass", f * lo, f * Vector3(lo.x, hi.y, lo.z), f * hi, f * Vector3(hi.x, lo.y, lo.z), f.basis.z,
				Color(lit, _rng.randf(), 0.15, _rng.randf()), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
			# The glass of the head, dark over the lit sash.
			var head := CourthouseKit.opening(u, 1.0, y0 + 2.0 - 0.001, y0 + 2.0, "round" if arched else "segment", 0.18)
			k.glass(f, head, 0.021, c(Color(0.08, 0.08, 0.09), CourthouseKit.K_PAINT), "wall")


## The county's government centre: a nine-storey tower of brick with
## white piers up it over a three-storey block, faced on a plaza.
func _government(at: Vector3, out: Vector3) -> void:
	var f := Transform3D(Basis(out.cross(Vector3.UP) * -1.0, Vector3.UP, out), at)
	var brick := c(Color(0.55, 0.28, 0.21), CourthouseKit.K_BRICK)
	var white := c(Color(0.88, 0.87, 0.83), CourthouseKit.K_PAINT)
	# The low block along the street.
	k.block("wall", f, Vector3(0, 6.0, -12.0), Vector3(40.0, 12.0, 24.0), brick)
	for j in 3:
		k.box("wall", f, Vector3(0, 4.0 * (j + 1) - 0.3, 0.05), Vector3(40.0, 0.6, 0.1), white)
		for bi in 16:
			var u := -20.0 + 40.0 * (bi + 0.5) / 16.0
			var lo := Vector3(u - 0.9, 4.0 * j + 1.0, 0.02)
			var hi := Vector3(u + 0.9, 4.0 * j + 3.2, 0.02)
			k.m.quad("glass", f * lo, f * Vector3(lo.x, hi.y, lo.z), f * hi, f * Vector3(hi.x, lo.y, lo.z), f.basis.z,
				Color(_rng.randf_range(0.4, 0.9), _rng.randf(), 0.5, 0.8), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	# The tower behind its east end.
	var tf := f * Transform3D(Basis(), Vector3(12.0, 0, -18.0))
	k.block("wall", tf, Vector3(0, 18.0, 0), Vector3(16.0, 36.0, 14.0), brick)
	for side in 4:
		var sf := tf * Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, 0, 7.0 if side % 2 == 0 else 8.0))
		var sw := 16.0 if side % 2 == 0 else 14.0
		for pier in 5:
			var u := -sw / 2.0 + sw * pier / 4.0
			k.box("wall", sf, Vector3(u, 18.0, 0.1), Vector3(0.6, 36.0, 0.2), white)
		for fl in 9:
			for bi in 4:
				var u := -sw / 2.0 + sw * (bi + 0.5) / 4.0
				var lo := Vector3(u - 1.2, fl * 4.0 + 1.0, 0.03)
				var hi := Vector3(u + 1.2, fl * 4.0 + 3.0, 0.03)
				k.m.quad("glass", sf * lo, sf * Vector3(lo.x, hi.y, lo.z), sf * hi, sf * Vector3(hi.x, lo.y, lo.z), sf.basis.z,
					Color(_rng.randf_range(0.3, 1.0), _rng.randf(), 0.5, 0.8), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))



## The judicial centre: four storeys of pink brick facing West Jefferson.
func _judicial(at: Vector3) -> void:
	var jf := Transform3D(Basis(), at)
	k.block("wall", jf, Vector3(0, 8.5, -14.0), Vector3(26.0, 17.0, 28.0), c(Color(0.72, 0.52, 0.46), CourthouseKit.K_BRICK))
	for fl in 4:
		for bi in 3:
			var u := -8.0 + bi * 8.0
			var lo := Vector3(u - 1.6, fl * 4.2 + 1.0, 0.02)
			var hi := Vector3(u + 1.6, fl * 4.2 + 3.4, 0.02)
			k.m.quad("glass", jf * lo, jf * Vector3(lo.x, hi.y, lo.z), jf * hi, jf * Vector3(hi.x, lo.y, lo.z), jf.basis.z,
				Color(_rng.randf_range(0.4, 0.9), _rng.randf(), 0.5, 0.8), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
