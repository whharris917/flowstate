class_name YardProps
extends RefCounted
## The small things of a lived-in yard, each drawn into a town's merged
## meshes at a transform whose origin is on the ground (or the floor it
## stands on), its front along +z. Art only; the few big enough to walk
## into are solid, through the solid callable the caller passes.



static func c(color: Color, kind: int) -> Color:
	return HarborTown.kc(color, kind)


static func _at(p: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


## A boy's bicycle, x along its length, leaning lean radians onto its
## right side (+z) against whatever it rests on.
static func bicycle(m: TownMesh, xf: Transform3D, frame: Color, lean := 0.26) -> void:
	var t := xf * Transform3D(Basis(Vector3(1, 0, 0), -lean), Vector3.ZERO)
	var tyre := Color(0.08, 0.08, 0.08)
	var steel := Color(0.72, 0.72, 0.7)
	for wx: float in [-0.52, 0.52]:
		var hub := Vector3(wx, 0.34, 0)
		var prev := hub + Vector3(0.34, 0, 0)
		for k in range(1, 17):
			var a := TAU * k / 16.0
			var p := hub + Vector3(cos(a) * 0.34, sin(a) * 0.34, 0)
			m.bar("iron", t * prev, t * p, 0.022, 4, tyre)
			prev = p
		for k in 6:
			var a := TAU * k / 6.0 + 0.2
			m.bar("iron", t * hub, t * (hub + Vector3(cos(a) * 0.32, sin(a) * 0.32, 0)), 0.004, 3, steel)
	var bb := Vector3(-0.05, 0.3, 0)
	var seat := Vector3(-0.22, 0.82, 0)
	var head := Vector3(0.36, 0.82, 0)
	var joints: Array = [[Vector3(-0.52, 0.34, 0), bb], [bb, seat], [seat, Vector3(-0.52, 0.34, 0)],
		[bb, head + Vector3(0.02, -0.12, 0)], [seat + Vector3(0.02, -0.05, 0), head], [head, Vector3(0.52, 0.34, 0)]]
	for j: Array in joints:
		m.bar("iron", t * (j[0] as Vector3), t * (j[1] as Vector3), 0.018, 5, frame)
	m.box("iron", t * _at(seat + Vector3(0, 0.05, 0)), Vector3(0.22, 0.05, 0.1), Color(0.2, 0.12, 0.08))
	m.bar("iron", t * (head + Vector3(0, 0.12, -0.24)), t * (head + Vector3(0, 0.12, 0.24)), 0.012, 4, steel)
	m.bar("iron", t * head, t * (head + Vector3(0, 0.12, 0)), 0.014, 4, steel)
	m.box("iron", t * _at(Vector3(0.62, 0.62, 0)), Vector3(0.22, 0.12, 0.3), Color(0.35, 0.3, 0.2))


## A red wagon, its handle down in front.
static func wagon(m: TownMesh, xf: Transform3D) -> void:
	var red := Color(0.62, 0.1, 0.08)
	m.box("iron", xf * _at(Vector3(0, 0.28, 0)), Vector3(0.9, 0.16, 0.42), red)
	m.box("iron", xf * _at(Vector3(0, 0.22, 0)), Vector3(0.86, 0.03, 0.38), Color(0.3, 0.3, 0.3))
	for sx: float in [-0.32, 0.32]:
		for sz: float in [-0.23, 0.23]:
			m.cylinder("iron", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(sx, 0.1, sz)), 0.1, 0.1, 0.04, 10, Color(0.1, 0.1, 0.1))
	m.bar("iron", xf * Vector3(0.45, 0.2, 0), xf * Vector3(1.05, 0.05, 0.1), 0.012, 4, Color(0.1, 0.1, 0.1))


## A clay pot of chrysanthemums, the autumn's flower.
static func flower_pot(m: TownMesh, xf: Transform3D, bloom: Color, size := 1.0) -> void:
	m.cylinder("wall", xf * _at(Vector3(0, 0.12 * size, 0)), 0.1 * size, 0.14 * size, 0.24 * size, 10, c(Color(0.62, 0.32, 0.2), HarborTown.K_PAINT))
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1, 0.75, 1)), Vector3(0, 0.3 * size, 0)), 0.17 * size, 8, c(Color(0.2, 0.3, 0.12), HarborTown.K_CLOTH))
	for k in 7:
		var a := TAU * k / 7.0
		m.sphere("wall", xf * _at(Vector3(cos(a) * 0.1 * size, 0.36 * size + 0.02 * (k % 2), sin(a) * 0.1 * size)), 0.05 * size, 6, c(bloom, HarborTown.K_CLOTH))


## A pumpkin; carved, its face glows from dusk like a street lamp.
static func pumpkin(m: TownMesh, xf: Transform3D, size: float, carved: bool, delay: float) -> void:
	var orange := c(Color(0.85, 0.42, 0.08), HarborTown.K_ENAMEL)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.78, 1.0)), Vector3(0, size * 0.75, 0)), size, 10, orange)
	m.cylinder("wall", xf * _at(Vector3(0, size * 1.5, 0)), 0.02, 0.015, 0.08, 5, c(Color(0.3, 0.3, 0.12), HarborTown.K_WOOD))
	if carved:
		var glow := Color(delay, 0, 0, 1)
		var face := size * 0.97
		for s: float in [-1.0, 1.0]:
			m.box("lamp", xf * _at(Vector3(s * size * 0.35, size * 0.9, face)), Vector3(size * 0.2, size * 0.18, 0.02), glow, true)
		m.box("lamp", xf * _at(Vector3(0, size * 0.5, face * 0.96)), Vector3(size * 0.6, size * 0.14, 0.02), glow, true)


## A rocking chair, painted.
static func rocker(m: TownMesh, xf: Transform3D, paint: Color) -> void:
	var p := c(paint, HarborTown.K_PAINT)
	m.box("wall", xf * _at(Vector3(0, 0.42, 0)), Vector3(0.48, 0.04, 0.46), p, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(s * 0.22, 0.05, 0.02)), Vector3(0.04, 0.04, 0.8), p, true)
		m.box("wall", xf * _at(Vector3(s * 0.22, 0.24, 0.18)), Vector3(0.04, 0.4, 0.04), p, true)
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(s * 0.22, 0.72, -0.24)), Vector3(0.04, 1.0, 0.04), p, true)
		m.box("wall", xf * _at(Vector3(s * 0.25, 0.64, 0.0)), Vector3(0.05, 0.03, 0.44), p, true)
	for k in 5:
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(-0.16 + 0.08 * k, 0.75, -0.25)), Vector3(0.03, 0.7, 0.02), p, true)
	m.box("wall", xf * _at(Vector3(0, 0.46, 0.0)), Vector3(0.4, 0.05, 0.38), c(Color(0.6, 0.15, 0.12), HarborTown.K_CLOTH), true)


## A porch swing hung on chains from a ceiling at height top.
static func porch_swing(m: TownMesh, xf: Transform3D, top: float, paint: Color) -> void:
	var p := c(paint, HarborTown.K_PAINT)
	m.box("wall", xf * _at(Vector3(0, 0.45, 0)), Vector3(1.3, 0.05, 0.45), p, true)
	m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.72, -0.22)), Vector3(1.3, 0.45, 0.04), p, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * _at(Vector3(s * 0.64, 0.6, 0)), Vector3(0.04, 0.26, 0.45), p, true)
		for zz: float in [-0.2, 0.2]:
			m.bar("iron", xf * Vector3(s * 0.62, 0.62, zz), xf * Vector3(s * 0.62, top, zz * 0.3), 0.006, 3, Color(0.25, 0.25, 0.25))
	m.box("wall", xf * _at(Vector3(-0.3, 0.52, 0.02)), Vector3(0.32, 0.12, 0.3), c(Color(0.25, 0.4, 0.55), HarborTown.K_CLOTH), true)


## An Adirondack chair, its back raked, broad arms.
static func adirondack(m: TownMesh, xf: Transform3D, paint: Color) -> void:
	var p := c(paint, HarborTown.K_PAINT)
	for k in 5:
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 0.36, -0.22 + 0.1 * k)), Vector3(0.52, 0.025, 0.08), p, true)
	for k in 5:
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(-0.2 + 0.1 * k, 0.72, -0.42)), Vector3(0.08, 0.85 + 0.08 * (2 - absi(k - 2)), 0.025), p, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * _at(Vector3(s * 0.33, 0.6, -0.02)), Vector3(0.13, 0.025, 0.72), p, true)
		m.box("wall", xf * _at(Vector3(s * 0.3, 0.3, 0.26)), Vector3(0.04, 0.6, 0.05), p, true)
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(s * 0.28, 0.2, -0.05)), Vector3(0.04, 0.12, 0.8), p, true)


## A bird bath: a pedestal, a shallow basin, water that takes the sky.
static func bird_bath(m: TownMesh, xf: Transform3D) -> void:
	var stone := c(Color(0.62, 0.6, 0.56), HarborTown.K_GRANITE)
	m.cylinder("wall", xf * _at(Vector3(0, 0.05, 0)), 0.22, 0.24, 0.1, 12, stone)
	m.cylinder("wall", xf * _at(Vector3(0, 0.4, 0)), 0.08, 0.12, 0.6, 10, stone)
	m.cylinder("wall", xf * _at(Vector3(0, 0.74, 0)), 0.36, 0.16, 0.1, 16, stone)
	m.cylinder("steel", xf * _at(Vector3(0, 0.79, 0)), 0.31, 0.31, 0.005, 16, Color.WHITE)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.4)), Vector3(0.24, 0.84, 0.05)), 0.04, 6, c(Color(0.35, 0.3, 0.3), HarborTown.K_CLOTH))


## A bird feeder on a post, a little roof over the seed.
static func bird_feeder(m: TownMesh, xf: Transform3D) -> void:
	var wood := c(Color(0.45, 0.36, 0.26), HarborTown.K_TIMBER)
	m.cylinder("wall", xf * _at(Vector3(0, 0.8, 0)), 0.04, 0.04, 1.6, 6, wood)
	m.box("wall", xf * _at(Vector3(0, 1.62, 0)), Vector3(0.36, 0.04, 0.36), wood, true)
	m.box("clear", xf * _at(Vector3(0, 1.75, 0)), Vector3(0.18, 0.22, 0.18), Color.WHITE, true)
	m.box("wall", xf * _at(Vector3(0, 1.72, 0)), Vector3(0.14, 0.14, 0.14), c(Color(0.55, 0.45, 0.25), HarborTown.K_CLOTH), true)
	m.prism("wall", xf * _at(Vector3(0, 1.87, 0)), 0.42, 0.14, 0.4, c(Color(0.25, 0.35, 0.28), HarborTown.K_PAINT))


## A raised bed of the season's end: cabbages, staked tomatoes with the
## last fruit, corn stalks gone tan, a pumpkin or two.
static func vegetable_bed(m: TownMesh, xf: Transform3D, size: Vector2, rng: RandomNumberGenerator) -> void:
	var board := c(Color(0.42, 0.34, 0.24), HarborTown.K_TIMBER)
	var soil := c(Color(0.22, 0.16, 0.11), HarborTown.K_TAR)
	m.box("wall", xf * _at(Vector3(0, 0.12, 0)), Vector3(size.x, 0.24, size.y), soil)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * _at(Vector3(s * size.x / 2.0, 0.14, 0)), Vector3(0.05, 0.28, size.y + 0.05), board)
		m.box("wall", xf * _at(Vector3(0, 0.14, s * size.y / 2.0)), Vector3(size.x, 0.28, 0.05), board)
	var rows := int(size.y / 0.5)
	for r in rows:
		var z := -size.y / 2.0 + (r + 0.5) * size.y / rows
		var kind := r % 3
		var x := -size.x / 2.0 + 0.3
		while x < size.x / 2.0 - 0.2:
			var p := Vector3(x + rng.randf_range(-0.05, 0.05), 0.24, z)
			match kind:
				0:
					m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), p + Vector3(0, 0.1, 0)), 0.14, 8, c(Color(0.35, 0.5, 0.3), HarborTown.K_CLOTH))
				1:
					m.cylinder("wall", xf * _at(p + Vector3(0, 0.55, 0)), 0.015, 0.015, 1.1, 4, c(Color(0.5, 0.42, 0.3), HarborTown.K_TIMBER))
					for k in 6:
						var a := rng.randf_range(0.0, TAU)
						var y := 0.2 + 0.14 * k
						m.sphere("wall", xf * _at(p + Vector3(cos(a) * 0.08, y, sin(a) * 0.08)), rng.randf_range(0.08, 0.12), 7,
							c(Color(0.22, 0.32, 0.12).lightened(rng.randf_range(-0.05, 0.1)), HarborTown.K_CLOTH))
					for k in 3:
						m.sphere("wall", xf * _at(p + Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.3, 0.8), 0.14)), 0.035, 6, c(Color(0.72, 0.12, 0.06), HarborTown.K_ENAMEL))
				_:
					m.cylinder("wall", xf * _at(p + Vector3(0, 0.8, 0)), 0.015, 0.012, 1.6, 4, c(Color(0.62, 0.55, 0.32), HarborTown.K_CLOTH))
					for k in 3:
						var a := rng.randf_range(0.0, TAU)
						m.box("wall", xf * Transform3D(Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), -0.8), p + Vector3(0, 0.5 + 0.35 * k, 0)), Vector3(0.45, 0.01, 0.06), c(Color(0.66, 0.58, 0.34), HarborTown.K_CLOTH))
			x += 0.45


## A bed of chrysanthemums along a foundation, len long.
static func mum_bed(m: TownMesh, xf: Transform3D, length: float, rng: RandomNumberGenerator) -> void:
	var blooms: Array[Color] = [Color(0.85, 0.55, 0.12), Color(0.75, 0.2, 0.2), Color(0.85, 0.75, 0.25), Color(0.55, 0.3, 0.6)]
	m.box("wall", xf * _at(Vector3(0, 0.03, 0)), Vector3(length, 0.06, 0.6), c(Color(0.25, 0.18, 0.12), HarborTown.K_TAR))
	var x := -length / 2.0 + 0.3
	while x < length / 2.0 - 0.2:
		var bloom := blooms[rng.randi() % blooms.size()]
		var p := Vector3(x, 0.0, rng.randf_range(-0.12, 0.12))
		m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1, 0.7, 1)), p + Vector3(0, 0.2, 0)), 0.22, 8, c(Color(0.2, 0.3, 0.12), HarborTown.K_CLOTH))
		for k in 6:
			var a := TAU * k / 6.0 + rng.randf()
			m.sphere("wall", xf * _at(p + Vector3(cos(a) * 0.13, 0.3, sin(a) * 0.13)), 0.06, 5, c(bloom, HarborTown.K_CLOTH))
		x += 0.5


## A window box under a window w wide at a facade's face, flowering.
static func window_box(m: TownMesh, xf: Transform3D, w: float, rng: RandomNumberGenerator) -> void:
	var box := c(Color(0.92, 0.91, 0.87), HarborTown.K_PAINT)
	m.box("wall", xf * _at(Vector3(0, 0, 0.13)), Vector3(w + 0.2, 0.18, 0.22), box, true)
	var blooms: Array[Color] = [Color(0.8, 0.15, 0.12), Color(0.85, 0.6, 0.15), Color(0.9, 0.9, 0.85)]
	var bloom := blooms[rng.randi() % blooms.size()]
	var x := -w / 2.0
	while x <= w / 2.0:
		m.sphere("wall", xf * _at(Vector3(x, 0.15, 0.13)), 0.09, 6, c(Color(0.2, 0.32, 0.12), HarborTown.K_CLOTH))
		m.sphere("wall", xf * _at(Vector3(x + 0.04, 0.22, 0.17)), 0.04, 5, c(bloom, HarborTown.K_CLOTH))
		x += 0.16


## A cord of stove wood stacked between two stakes, the ends showing.
static func woodpile(m: TownMesh, xf: Transform3D, length: float) -> void:
	var bark := c(Color(0.35, 0.28, 0.2), HarborTown.K_TIMBER)
	var rows := 5
	var n := int(length / 0.16)
	for r in rows:
		for k in n:
			var p := Vector3(-length / 2.0 + (k + 0.5) * length / n + (0.04 if r % 2 == 1 else 0.0), 0.08 + r * 0.145, 0)
			m.cylinder("wall", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), p), 0.075, 0.075, 0.45, 6, bark)
	for s: float in [-1.0, 1.0]:
		m.cylinder("wall", xf * _at(Vector3(s * (length / 2.0 + 0.06), 0.45, 0)), 0.03, 0.03, 0.9, 5, bark)


## A dory turned over on two sawhorses for the winter.
static func dory_on_horses(m: TownMesh, xf: Transform3D, hull: Color) -> void:
	var wood := c(Color(0.62, 0.55, 0.42), HarborTown.K_TIMBER)
	for s: float in [-1.0, 1.0]:
		var hx := xf * _at(Vector3(s * 1.2, 0, 0))
		m.box("wall", hx * _at(Vector3(0, 0.62, 0)), Vector3(0.1, 0.08, 1.0), wood, true)
		for sz: float in [-1.0, 1.0]:
			m.box("wall", hx * Transform3D(Basis(Vector3.RIGHT, sz * 0.25), Vector3(0, 0.3, sz * 0.38)), Vector3(0.06, 0.66, 0.06), wood, true)
	var boat := xf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0.66, 0))
	m.prism("wall", boat, 1.3, 0.42, 4.2, c(hull, HarborTown.K_PAINT))
	m.box("wall", boat * _at(Vector3(0, 0.02, 0)), Vector3(1.32, 0.05, 4.2), c(Color(0.9, 0.88, 0.8), HarborTown.K_PAINT), true)


## A clothesline between two T-posts, span long, and the wash on it.
static func clothesline(m: TownMesh, xf: Transform3D, span: float, rng: RandomNumberGenerator) -> void:
	var post := c(Color(0.5, 0.48, 0.44), HarborTown.K_TIMBER)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * _at(Vector3(s * span / 2.0, 1.1, 0)), Vector3(0.09, 2.2, 0.09), post, true)
		m.box("wall", xf * _at(Vector3(s * span / 2.0, 2.1, 0)), Vector3(0.09, 0.07, 0.9), post, true)
	for k in 3:
		m.bar("iron", xf * Vector3(-span / 2.0, 2.12, -0.35 + 0.35 * k), xf * Vector3(span / 2.0, 2.12, -0.35 + 0.35 * k), 0.004, 3, Color(0.85, 0.85, 0.8))
	var cloths: Array[Color] = [Color(0.95, 0.95, 0.92), Color(0.95, 0.95, 0.92), Color(0.55, 0.65, 0.8), Color(0.75, 0.3, 0.25), Color(0.9, 0.85, 0.6)]
	var x := -span / 2.0 + 0.5
	while x < span / 2.0 - 0.5:
		var wide := rng.randf_range(0.35, 1.2)
		var tall := wide * rng.randf_range(0.8, 1.2) if wide < 0.8 else rng.randf_range(0.9, 1.2)
		var line := -0.35 + 0.35 * (rng.randi() % 3)
		m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, rng.randf_range(0.03, 0.12)), Vector3(x + wide / 2.0, 2.12 - tall / 2.0, line)),
			Vector3(wide, tall, 0.01), c(cloths[rng.randi() % cloths.size()], HarborTown.K_CLOTH), true)
		x += wide + rng.randf_range(0.15, 0.5)


## A garden wheelbarrow, its handles down.
static func wheelbarrow(m: TownMesh, xf: Transform3D) -> void:
	var tray := Color(0.3, 0.42, 0.35)
	m.box("iron", xf * Transform3D(Basis(Vector3(0, 0, 1), 0.12), Vector3(0.1, 0.45, 0)), Vector3(0.8, 0.28, 0.55), tray)
	m.cylinder("iron", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.55, 0.18, 0)), 0.18, 0.18, 0.07, 12, Color(0.1, 0.1, 0.1))
	for s: float in [-1.0, 1.0]:
		m.bar("wall", xf * Vector3(0.55, 0.18, s * 0.05), xf * Vector3(-0.9, 0.45, s * 0.28), 0.02, 4, c(Color(0.5, 0.38, 0.24), HarborTown.K_WOOD))
		m.bar("iron", xf * Vector3(-0.35, 0.32, s * 0.2), xf * Vector3(-0.35, 0.0, s * 0.22), 0.012, 4, Color(0.2, 0.2, 0.2))


## A pile of raked leaves and the rake leaning on it.
static func leaf_pile(m: TownMesh, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var leaves: Array[Color] = [Color(0.72, 0.36, 0.08), Color(0.6, 0.15, 0.06), Color(0.75, 0.58, 0.14), Color(0.45, 0.3, 0.12)]
	for k in 9:
		var p := Vector3(rng.randf_range(-0.45, 0.45), 0.0, rng.randf_range(-0.35, 0.35))
		m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1.3, 0.55, 1.2)), p + Vector3(0, 0.12, 0)), rng.randf_range(0.22, 0.35), 7, c(leaves[k % leaves.size()], HarborTown.K_CLOTH))
	m.bar("wall", xf * Vector3(0.6, 0.0, 0.2), xf * Vector3(0.2, 1.4, -0.1), 0.015, 4, c(Color(0.55, 0.45, 0.3), HarborTown.K_WOOD))
	for k in 7:
		m.bar("iron", xf * Vector3(0.55, 0.02, 0.05 + 0.05 * k), xf * Vector3(0.7, 0.02, -0.05 + 0.08 * k), 0.004, 3, Color(0.3, 0.3, 0.3))


## A cat sitting, tail round its feet.
static func cat(m: TownMesh, xf: Transform3D, fur: Color) -> void:
	var f := c(fur, HarborTown.K_CLOTH)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(0.8, 1.2, 1.0)), Vector3(0, 0.13, 0)), 0.11, 8, f)
	m.sphere("wall", xf * _at(Vector3(0, 0.3, 0.04)), 0.07, 8, f)
	for s: float in [-1.0, 1.0]:
		m.tri("wall", xf * Vector3(s * 0.02, 0.35, 0.05), xf * Vector3(s * 0.065, 0.35, 0.04), xf * Vector3(s * 0.05, 0.41, 0.04), (xf.basis * Vector3(0, 0, 1)).normalized(), f)
	m.bar("wall", xf * Vector3(-0.05, 0.03, -0.08), xf * Vector3(0.12, 0.02, 0.05), 0.02, 4, f)


## A milk crate's worth on the step: two bottles, a folded paper.
static func milk_and_paper(m: TownMesh, xf: Transform3D) -> void:
	for s: float in [-0.05, 0.05]:
		m.cylinder("clear", xf * _at(Vector3(s, 0.1, 0)), 0.035, 0.035, 0.2, 8, Color.WHITE)
		m.cylinder("wall", xf * _at(Vector3(s, 0.08, 0)), 0.03, 0.03, 0.15, 8, c(Color(0.95, 0.95, 0.9), HarborTown.K_ENAMEL))
		m.cylinder("wall", xf * _at(Vector3(s, 0.205, 0)), 0.036, 0.036, 0.01, 8, c(Color(0.8, 0.75, 0.6), HarborTown.K_PAINT))
	m.box("wall", xf * _at(Vector3(0.25, 0.02, 0.05), 0.4), Vector3(0.3, 0.04, 0.2), c(Color(0.85, 0.83, 0.76), HarborTown.K_CLOTH))


## A mailbox on its post by the gate, the flag up if the mail is in.
static func mailbox(m: TownMesh, xf: Transform3D, paint: Color, flag_up: bool) -> void:
	m.box("wall", xf * _at(Vector3(0, 0.55, 0)), Vector3(0.09, 1.1, 0.09), c(Color(0.92, 0.91, 0.87), HarborTown.K_PAINT), true)
	m.box("iron", xf * _at(Vector3(0, 1.18, 0)), Vector3(0.2, 0.2, 0.45), paint)
	m.cylinder("iron", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 1.28, 0)), 0.1, 0.1, 0.45, 10, paint)
	var flag := Transform3D(Basis(Vector3(1, 0, 0), 0.0 if flag_up else PI / 2.0), Vector3(0.11, 1.2, -0.08))
	m.box("iron", xf * flag * _at(Vector3(0, 0.12, 0)), Vector3(0.02, 0.24, 0.04), Color(0.62, 0.1, 0.08))
	m.box("iron", xf * flag * _at(Vector3(0, 0.22, 0.04)), Vector3(0.02, 0.06, 0.1), Color(0.62, 0.1, 0.08))


## The flag on a bracket by the door, pole angled out from the wall.
static func flag(m: TownMesh, xf: Transform3D) -> void:
	var pole := xf * Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3.ZERO)
	m.cylinder("iron", pole * _at(Vector3(0, 0.75, 0)), 0.015, 0.015, 1.5, 6, Color(0.85, 0.85, 0.8))
	var cloth := pole * _at(Vector3(0.0, 1.05, 0.0))
	for k in 7:
		var red := k % 2 == 0
		m.box("wall", cloth * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.45, -0.05 - 0.07 * k, 0.0)), Vector3(0.85, 0.07, 0.008),
			c(Color(0.65, 0.1, 0.1) if red else Color(0.92, 0.9, 0.86), HarborTown.K_CLOTH), true)
	m.box("wall", cloth * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0.2, -0.12, 0.006)), Vector3(0.36, 0.26, 0.008), c(Color(0.12, 0.16, 0.36), HarborTown.K_CLOTH), true)


## A picket fence from x0 to x1 at z, open for a gate at gap.
static func picket_fence(m: TownMesh, xf: Transform3D, x0: float, x1: float, gap: float) -> void:
	var white := c(Color(0.92, 0.91, 0.87), HarborTown.K_PAINT)
	var x := x0
	while x <= x1:
		if absf(x - gap) > 0.62:
			m.box("wall", xf * _at(Vector3(x, 0.5, 0)), Vector3(0.07, 1.0, 0.025), white)
			m.prism("wall", xf * _at(Vector3(x, 1.0, 0)), 0.07, 0.06, 0.025, white)
		x += 0.14
	for seg: Array in [[x0, gap - 0.62], [gap + 0.62, x1]]:
		var a: float = seg[0]
		var b: float = seg[1]
		if b <= a:
			continue
		for y: float in [0.28, 0.78]:
			m.box("wall", xf * _at(Vector3((a + b) / 2.0, y, -0.03)), Vector3(b - a, 0.07, 0.035), white)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * _at(Vector3(gap + s * 0.6, 0.6, 0)), Vector3(0.12, 1.2, 0.12), white)
		m.sphere("wall", xf * _at(Vector3(gap + s * 0.6, 1.25, 0)), 0.07, 8, white)


## A coir welcome mat at a door, lettered or plain.
static func welcome_mat(m: TownMesh, xf: Transform3D, lettered: bool) -> void:
	m.box("wall", xf * _at(Vector3(0, 0.008, 0)), Vector3(0.75, 0.016, 0.45), c(Color(0.55, 0.4, 0.22), HarborTown.K_CLOTH), true)
	m.box("wall", xf * _at(Vector3(0, 0.012, 0)), Vector3(0.65, 0.016, 0.35), c(Color(0.62, 0.46, 0.26), HarborTown.K_CLOTH), true)
	if lettered:
		for k in 7:
			m.box("wall", xf * _at(Vector3(-0.24 + 0.08 * k, 0.018, 0.0)), Vector3(0.05, 0.004, 0.09), c(Color(0.25, 0.15, 0.08), HarborTown.K_CLOTH), true)


## The milkman's box by the door: an insulated tin chest.
static func milk_box(m: TownMesh, xf: Transform3D) -> void:
	m.box("iron", xf * _at(Vector3(0, 0.17, 0)), Vector3(0.4, 0.34, 0.3), Color(0.85, 0.85, 0.82))
	m.box("iron", xf * _at(Vector3(0, 0.35, 0)), Vector3(0.42, 0.03, 0.32), Color(0.2, 0.3, 0.55))
	m.box("iron", xf * _at(Vector3(0, 0.2, 0.152)), Vector3(0.24, 0.08, 0.005), Color(0.2, 0.3, 0.55))


## A garden hose coiled on the grass, its nozzle out.
static func hose(m: TownMesh, xf: Transform3D) -> void:
	var green := Color(0.15, 0.35, 0.15)
	for ring in 4:
		var r := 0.22 + 0.04 * ring
		var prev := Vector3(r, 0.03 + 0.02 * ring, 0)
		for k in range(1, 17):
			var a := TAU * k / 16.0
			var p := Vector3(cos(a) * r, 0.03 + 0.02 * ring, sin(a) * r)
			m.bar("iron", xf * prev, xf * p, 0.014, 4, green)
			prev = p
	m.bar("iron", xf * Vector3(0.34, 0.1, 0), xf * Vector3(0.9, 0.02, 0.3), 0.014, 4, green)
	m.cylinder("iron", xf * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0.95, 0.03, 0.32)), 0.02, 0.012, 0.12, 6, Color(0.7, 0.55, 0.25))


## A wooden swing frame: two A-frames, a beam, a board seat on ropes.
static func swing_frame(m: TownMesh, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var wood := c(Color(0.5, 0.42, 0.32), HarborTown.K_TIMBER)
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			m.bar("wall", xf * Vector3(s * 1.1, 0, f * 0.7), xf * Vector3(s * 1.1, 2.3, 0), 0.05, 5, wood)
	m.bar("wall", xf * Vector3(-1.2, 2.3, 0), xf * Vector3(1.2, 2.3, 0), 0.07, 6, wood)
	var sway := rng.randf_range(-0.15, 0.15)
	for x: float in [-0.3, 0.3]:
		m.bar("iron", xf * Vector3(x, 2.25, 0), xf * Vector3(x, 0.5, sway), 0.008, 3, Color(0.6, 0.55, 0.45))
	m.box("wall", xf * _at(Vector3(0, 0.48, sway)), Vector3(0.7, 0.04, 0.22), c(Color(0.62, 0.15, 0.1), HarborTown.K_PAINT), true)


## A small bird perched, its tail down, facing along the transform.
static func bird(m: TownMesh, xf: Transform3D, feathers: Color) -> void:
	var f := c(feathers, HarborTown.K_CLOTH)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(0.7, 0.8, 1.2)), Vector3(0, 0.05, 0)), 0.045, 6, f)
	m.sphere("wall", xf * _at(Vector3(0, 0.1, 0.04)), 0.028, 6, f)
	m.tri("wall", xf * Vector3(-0.012, 0.1, 0.066), xf * Vector3(0.012, 0.1, 0.066), xf * Vector3(0, 0.095, 0.085), (xf.basis * Vector3(0, 1, 0)).normalized(), c(Color(0.7, 0.55, 0.2), HarborTown.K_ENAMEL))
	m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 0.02, -0.07)), Vector3(0.03, 0.01, 0.07), f)

