class_name HarborTown
extends Node3D
## A small Maine harbour town of the 1940s on the coast's graded site:
## Main Street's brick storefronts (hardware, drug store, theatre,
## bank, five-and-ten, post office) facing a stainless diner, a gas
## station, a grocery and a white church; clapboard capes, colonials
## and gable-fronted houses on Elm and Water Streets and along Harbor
## Street, which runs down to the waterfront, the fish houses and the
## wharf. Cast-iron lamp posts on Main Street, gooseneck lamps on
## wooden poles strung with wire everywhere else, maples turning in
## the yards.
##
## Art only, like the lighthouse: no records, nothing simulated. The
## fabric is gathered into one mesh per material (TownMesh); the
## windows light house by house as it gets dark, the street lamps come
## on photocell by photocell, and the rain wets it all, through a few
## shader values the world sets. Buildings, posts and the wharf are
## solid to the player.

const K_PAINT := 0
const K_CLAP := 1
const K_BRICK := 2
const K_SHAKE := 3
const K_GRANITE := 4
const K_ROOF := 5
const K_PLANK := 6
const K_TIMBER := 7
const K_TAR := 8
const K_PAPER := 9
const K_OAK := 10
const K_LINO := 11
const K_PLASTER := 12
const K_TILE := 13
const K_ENAMEL := 14
const K_CLOTH := 15
const K_WOOD := 16

const TRIM := Color(0.91, 0.90, 0.86)
const GRANITE := Color(0.58, 0.56, 0.53)
const BRICK := Color(0.50, 0.25, 0.18)
const CREOSOTE := Color(0.22, 0.18, 0.14)
const IRON := Color(0.07, 0.075, 0.08)
const POLE := Color(0.30, 0.24, 0.18)
const LAMP_COLOR := Color(1.0, 0.76, 0.48)

const CLAPBOARDS: Array[Color] = [
	Color(0.90, 0.89, 0.84), Color(0.90, 0.89, 0.84), Color(0.90, 0.89, 0.84),
	Color(0.88, 0.82, 0.62), Color(0.92, 0.84, 0.52), Color(0.56, 0.64, 0.70),
	Color(0.60, 0.66, 0.54), Color(0.52, 0.17, 0.13), Color(0.55, 0.52, 0.48),
]
const ROOFS: Array[Color] = [
	Color(0.20, 0.20, 0.21), Color(0.18, 0.22, 0.20), Color(0.33, 0.21, 0.17), Color(0.25, 0.27, 0.31),
]
const SHUTTERS: Array[Color] = [Color(0.10, 0.16, 0.12), Color(0.08, 0.08, 0.08), Color(0.35, 0.08, 0.07)]
const DOORS: Array[Color] = [Color(0.45, 0.08, 0.07), Color(0.08, 0.08, 0.08), Color(0.12, 0.25, 0.16), Color(0.36, 0.24, 0.14)]
const LEAVES: Array[Color] = [
	Color(0.78, 0.36, 0.07), Color(0.66, 0.14, 0.06), Color(0.80, 0.62, 0.12),
	Color(0.52, 0.48, 0.12), Color(0.16, 0.24, 0.08), Color(0.74, 0.28, 0.06),
]

var coast: TownCoast
var m := TownMesh.new()
var wall_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var street_mat: ShaderMaterial
var lamp_mat: ShaderMaterial
var iron_mat: StandardMaterial3D
var steel_mat: StandardMaterial3D
## The lights the lamps throw. A street lamp's is {light, energy,
## delay}: its photocell's delay, as a share of eight seconds, the same
## as its glass's. A lit room's is {light, energy, thr}: the darkness at
## which it comes on, as its window's. The world switches them.
var lamps: Array[Dictionary] = []
var stats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _solids: Node3D
var _trees: Forest
var _signs := 0
var _houses := 0
var _marquee_bulb := 0
var stats_trees := 0
var cape: CapeHouse
## Chimney smoke's particle settings: the weather leans them with the wind.
var smoke: Array[ParticleProcessMaterial] = []
var clear_mat: StandardMaterial3D
var shade_mat: ShaderMaterial   # every lamp shade in the modelled houses: glows at its own darkness
## Every house as built, for whatever dresses its yard: {base, w, d,
## style, door_x, found, front_xs, f1, chimney, water, thr, harbour_side}.
var houses_built: Array[Dictionary] = []
var _keep_clear: Array[Rect2] = []


func build(c: TownCoast) -> void:
	coast = c
	_rng.seed = 1947
	name = "HarborTown"
	_solids = Node3D.new()
	_solids.name = "Solids"
	add_child(_solids)
	_trees = Forest.new()
	_trees.name = "StreetTrees"
	_make_materials()
	var t0 := Time.get_ticks_msec()
	_streets()
	_main_street_north()
	_diner(Vector2(2.0, 21.0))
	_gas_station(Vector2(22.0, 19.5))
	_grocery(Vector2(37.0, 19.0))
	_church(Vector2(60.0, 19.5))
	_houses_all()
	_main_lamps()
	_pole_lines()
	_waterfront()
	WaterStreet.dress(self)
	_street_trees()
	m.commit(self, {"wall": wall_mat, "glass": glass_mat, "street": street_mat, "lamp": lamp_mat, "clear": clear_mat,
		"iron": iron_mat, "steel": steel_mat}, ["wall", "iron", "steel"])
	_trees.finish(true, false, true)
	add_child(_trees)
	stats = {"trees": stats_trees, "houses": _houses, "lamps": lamps.size(), "signs": _signs, "triangles": m.triangles,
		"solids": _solids.get_child_count(), "ms": Time.get_ticks_msec() - t0}


## ---- materials ------------------------------------------------------------

func _make_materials() -> void:
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = load("res://world/town_wall.gdshader")
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = load("res://world/town_glass.gdshader")
	street_mat = ShaderMaterial.new()
	street_mat.shader = load("res://world/street.gdshader")
	lamp_mat = ShaderMaterial.new()
	lamp_mat.shader = load("res://world/town_lamp.gdshader")
	iron_mat = StandardMaterial3D.new()
	iron_mat.vertex_color_use_as_albedo = true
	iron_mat.vertex_color_is_srgb = true
	iron_mat.metallic = 0.35
	iron_mat.roughness = 0.45
	iron_mat.clearcoat_enabled = true
	iron_mat.clearcoat = 0.3
	steel_mat = ViewUtil.steel(Color(0.74, 0.76, 0.78))
	shade_mat = ShaderMaterial.new()
	shade_mat.shader = load("res://world/town_shade.gdshader")
	clear_mat = StandardMaterial3D.new()
	clear_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear_mat.albedo_color = Color(0.85, 0.9, 0.92, 0.25)
	clear_mat.roughness = 0.05
	clear_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## A colour and what the surface is made of, for the wall shader.
static func kc(color: Color, kind: int) -> Color:
	return Color(color.r, color.g, color.b, kind / 20.0)


static func at(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## A solid box for the player, in xf.
func _solid(xf: Transform3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = xf
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_solids.add_child(body)


## Painted lettering on a sign board, facing out along xf's +z.
func _sign(xf: Transform3D, text: String, size: int, color: Color, lit := false) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.pixel_size = 0.004
	lbl.modulate = color
	lbl.outline_size = 0
	lbl.shaded = not lit
	lbl.double_sided = false
	lbl.transform = xf
	lbl.visibility_range_end = 120.0
	add_child(lbl)
	_signs += 1
	return lbl


## ---- streets -------------------------------------------------------------

func _streets() -> void:
	var lifts: Array[float] = [0.035, 0.03, 0.02, 0.02, 0.05, 0.05]
	for k in TownCoast.STREETS.size():
		var street: Array = TownCoast.STREETS[k]
		_ribbon(street[0], float(street[1]), 0.0, bool(street[2]), lifts[k])
	# The harbour road, down its ramp to the waterfront.
	_ribbon([Vector2(TownCoast.RAMP_TOP.x, TownCoast.RAMP_TOP.z), Vector2(TownCoast.RAMP_FOOT.x, TownCoast.RAMP_FOOT.z)],
		7.0, 0.0, false, 0.05)
	# Concrete walks on Main Street and Harbor Street, a granite curb
	# at the road's edge; broken where the streets cross.
	var mz := TownCoast.MAIN_Z
	var hx := TownCoast.HARBOR_X
	for side: float in [-1.0, 1.0]:
		var z := mz + side * 5.7
		for run: Vector2 in [Vector2(-45.0, hx - 4.5), Vector2(hx + 4.5, 75.0)]:
			_walk(Vector2(run.x, z), Vector2(run.y, z), Vector2(0, -side))
		# Harbor Street's walks stop at the outer edge of Main Street's;
		# the east walk breaks for Elm and Water Streets too.
		var x := hx + side * 5.7
		var runs: Array[Vector2] = [Vector2(-40.0, mz - 6.9), Vector2(mz + 6.9, 60.0)]
		if side > 0.0:
			runs = [Vector2(-40.0, TownCoast.ELM_Z - 3.5), Vector2(TownCoast.ELM_Z + 3.5, mz - 6.9),
				Vector2(mz + 6.9, TownCoast.WATER_Z - 3.5), Vector2(TownCoast.WATER_Z + 3.5, 60.0)]
		for run in runs:
			_walk(Vector2(x, run.x), Vector2(x, run.y), Vector2(-side, 0))
	# The waterfront apron: packed gravel down at the harbour.
	var y := TownCoast.APRON_Y + 0.03
	var lo := TownCoast.APRON - TownCoast.APRON_HALF
	var hi := TownCoast.APRON + TownCoast.APRON_HALF
	m.quad("street", Vector3(lo.x, y, lo.y), Vector3(lo.x, y, hi.y), Vector3(hi.x, y, hi.y), Vector3(hi.x, y, lo.y),
		Vector3.UP, Color(0, 0, 0, 1.0), Vector2(lo.x, lo.y), Vector2(lo.x, hi.y), Vector2(hi.x, hi.y), Vector2(hi.x, lo.y))


## A strip of road laid on the ground along points, three vertices
## across so a crowned or tilted ground is followed. kind 0 asphalt,
## 0.5 concrete, 1 gravel.
func _ribbon(points: Array, width: float, kind: float, centre_line: bool, lift: float) -> void:
	var samples: Array[Vector2] = []
	var dirs: Array[Vector2] = []
	for k in points.size() - 1:
		var a: Vector2 = points[k]
		var b: Vector2 = points[k + 1]
		var n := maxi(int(a.distance_to(b) / 2.0), 1)
		for j in n:
			samples.append(a.lerp(b, float(j) / n))
			dirs.append((b - a).normalized())
	samples.append(points[points.size() - 1])
	dirs.append(dirs[dirs.size() - 1])
	var col := Color(1.0 if centre_line else 0.0, 0, 0, kind)
	var along := 0.0
	var prev: Array[Vector3] = []
	var prev_v := 0.0
	for i in samples.size():
		var d := dirs[i]
		if i > 0 and i < samples.size() - 1:
			d = (dirs[i - 1] + dirs[i]).normalized()
		var side := Vector2(-d.y, d.x)
		var row: Array[Vector3] = []
		for f: float in [-0.5, 0.0, 0.5]:
			var p := samples[i] + side * width * f
			row.append(Vector3(p.x, coast.height_at(p.x, p.y) + lift, p.y))
		if i > 0:
			along += samples[i].distance_to(samples[i - 1])
			for k in 2:
				var u0 := width * (-0.5 + 0.5 * k)
				var u1 := u0 + width * 0.5
				m.quad("street", prev[k], row[k], row[k + 1], prev[k + 1], Vector3.UP, col,
					Vector2(u0, prev_v), Vector2(u0, along), Vector2(u1, along), Vector2(u1, prev_v))
		prev = row
		prev_v = along


## A concrete walk 2.4 m wide from a to b (its centre line), raised on
## a granite curb on the side toward the road (road, a unit vector).
func _walk(a: Vector2, b: Vector2, road: Vector2) -> void:
	var w := 2.4
	var side := road * (w / 2.0)
	var y := 0.17
	var col := Color(0, 0, 0, 0.5)
	var len_ := a.distance_to(b)
	var p0 := a - side
	var p1 := a + side
	var p2 := b + side
	var p3 := b - side
	m.quad("street", Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y),
		Vector3.UP, col, Vector2(-1.2, 0), Vector2(1.2, 0), Vector2(1.2, len_), Vector2(-1.2, len_))
	# The curb, and the walk's body under its surface.
	var mid := (a + b) / 2.0
	var yaw := atan2((b - a).x, (b - a).y)
	var body := at(Vector3(mid.x, y / 2.0 - 0.005, mid.y), yaw)
	m.box("wall", body, Vector3(w, y - 0.01, len_), kc(Color(0.52, 0.51, 0.48), K_PAINT))
	var curb := mid + side
	m.box("wall", at(Vector3(curb.x, y / 2.0, curb.y), yaw), Vector3(0.16, y + 0.01, len_), kc(GRANITE, K_GRANITE))


## ---- Main Street ----------------------------------------------------------

## The north side's row of storefronts, shoulder to shoulder, facing
## the street.
func _main_street_north() -> void:
	var z := TownCoast.MAIN_Z - 4.5 - 2.4 - 0.1
	# [centre x, width, height, facade, kind, sign, awning or null, kind of front]
	var row: Array = [
		[-2.0, 10.0, 7.6, Color(0.50, 0.25, 0.18), K_BRICK, "HARDWARE", Color(0.20, 0.36, 0.22), "shop"],
		[7.5, 9.0, 7.6, Color(0.56, 0.30, 0.20), K_BRICK, "DRUGS", Color(0.55, 0.12, 0.10), "shop"],
		[18.5, 13.0, 9.6, Color(0.60, 0.44, 0.30), K_BRICK, "", null, "theatre"],
		[29.5, 9.0, 7.0, Color(0.64, 0.62, 0.58), K_GRANITE, "SAVINGS BANK", null, "bank"],
		[39.5, 11.0, 7.6, Color(0.66, 0.50, 0.32), K_BRICK, "5 AND 10", Color(0.62, 0.14, 0.12), "shop"],
		[50.5, 11.0, 5.4, Color(0.48, 0.24, 0.17), K_BRICK, "U.S. POST OFFICE", null, "post"],
	]
	for spec: Array in row:
		_store(Vector3(float(spec[0]), 0.0, z), 0.0, float(spec[1]), 14.0, float(spec[2]),
			spec[3], int(spec[4]), str(spec[5]), spec[6], str(spec[7]))


## A two-storey commercial block: brick or stone, a pressed-metal
## cornice, a flat roof behind a parapet, the storefront (plate glass
## over a kickplate, a door, the sign band, an awning), flats above.
func _store(front: Vector3, yaw: float, w: float, d: float, h: float, facade: Color, kind: int,
		sign: String, awning: Variant, front_kind: String) -> void:
	var base := at(front, yaw)
	var fc := kc(facade, kind)
	m.box("wall", base * at(Vector3(0, h / 2.0, -d / 2.0)), Vector3(w, h, d), fc)
	_solid(base * at(Vector3(0, h / 2.0, -d / 2.0)), Vector3(w, h, d))
	m.box("wall", base * at(Vector3(0, h + 0.02, -d / 2.0)), Vector3(w - 0.5, 0.04, d - 0.5), kc(Color(0.14, 0.14, 0.14), K_TAR))
	var cornice := kc(Color(0.30, 0.28, 0.25) if kind == K_BRICK else TRIM, K_PAINT)
	m.box("wall", base * at(Vector3(0, h - 0.35, 0.18)), Vector3(w + 0.1, 0.45, 0.36), cornice)
	m.box("wall", base * at(Vector3(0, h - 0.62, 0.08)), Vector3(w, 0.1, 0.16), cornice)
	var ground := 3.9
	if front_kind == "theatre":
		_theatre_front(base, w, h)
	elif front_kind == "bank":
		_bank_front(base, w, h, sign)
	elif front_kind == "post":
		_post_front(base, w, h, sign)
	else:
		_shopfront(base, w, ground, sign, awning)
	# The flats upstairs: sash windows with stone sills and lintels.
	if h > 6.5 and front_kind != "bank":
		var n := int(w / 2.3)
		for k in n:
			var x := -w / 2.0 + w * (k + 0.5) / n
			var y := ground + 1.9 + (1.0 if front_kind == "theatre" else 0.0)
			_window(base, Vector3(x, y, 0.0), 0.95, 1.6, _upstairs_threshold(), null, 0.0, true)


## Whether and when someone upstairs puts a light on.
func _upstairs_threshold() -> float:
	return 1.0 if _rng.randf() < 0.3 else _rng.randf_range(0.25, 0.8)


func _shopfront(base: Transform3D, w: float, ground: float, sign: String, awning: Variant) -> void:
	var dark := kc(Color(0.12, 0.14, 0.13), K_PAINT)
	# Pilasters either side, the kickplate, the plate glass either side
	# of the door, the sign band over it all.
	for s: float in [-1.0, 1.0]:
		m.box("wall", base * at(Vector3(s * (w / 2.0 - 0.2), ground / 2.0, 0.06)), Vector3(0.4, ground, 0.12), kc(TRIM, K_PAINT))
	m.box("wall", base * at(Vector3(0, 0.3, 0.05)), Vector3(w - 0.8, 0.6, 0.1), dark)
	var shop := _rng.randf_range(0.12, 0.2)
	for s: float in [-1.0, 1.0]:
		var x0 := s * 0.75
		var x1 := s * (w / 2.0 - 0.45)
		_pane(base, Vector3(minf(x0, x1), 0.6, 0.02), Vector3(maxf(x0, x1), 3.0, 0.02), Color(shop, _rng.randf(), 0.5, 0.6))
	m.box("wall", base * at(Vector3(0, 1.2, 0.03)), Vector3(1.3, 2.4, 0.06), dark)
	_pane(base, Vector3(-0.45, 1.3, 0.065), Vector3(0.45, 2.25, 0.065), Color(shop, _rng.randf(), 0.5, 0.6))
	m.box("wall", base * at(Vector3(0, 3.35, 0.07)), Vector3(w - 0.8, 0.7, 0.14), dark)
	if sign != "":
		_sign(base * at(Vector3(0, 3.35, 0.15)), sign, 96, Color(0.85, 0.72, 0.38))
	if awning is Color:
		var canvas := kc(awning as Color, K_TAR)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(22.0))
		m.box("wall", base * Transform3D(tilt, Vector3(0, 2.95, 0.8)), Vector3(w - 1.0, 0.04, 1.7), canvas)
		m.box("wall", base * at(Vector3(0, 2.52, 1.58)), Vector3(w - 1.0, 0.28, 0.03), canvas)
	# A lamp in the window: the shop's light spills on the walk.
	var light := OmniLight3D.new()
	light.transform = base * at(Vector3(0, 2.4, 1.2))
	light.omni_range = 7.0
	light.omni_attenuation = 1.2
	light.light_color = Color(1.0, 0.74, 0.46)
	light.shadow_enabled = false
	add_child(light)
	lamps.append({"light": light, "thr": shop, "energy": 0.9})


## One pane of glass from lo to hi (facade frame corners, z the face).
func _pane(base: Transform3D, lo: Vector3, hi: Vector3, col: Color) -> void:
	var n := (base.basis * Vector3(0, 0, 1)).normalized()
	m.quad("glass", base * lo, base * Vector3(lo.x, hi.y, lo.z), base * hi, base * Vector3(hi.x, lo.y, hi.z), n, col,
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))


## A sash window centred at c on a facade (base's +z the outward face):
## white trim, a sill, shutters when given, the glass lighting at the
## darkness thr. stone: granite sill and lintel for a brick front.
func _window(base: Transform3D, c: Vector3, w: float, h: float, thr: float, shutter: Variant,
		style: float = 0.0, stone: bool = false) -> void:
	var trim := kc(GRANITE if stone else TRIM, K_GRANITE if stone else K_PAINT)
	m.box("wall", base * at(c + Vector3(0, h / 2.0 + 0.08, 0.04)), Vector3(w + (0.3 if stone else 0.24), 0.16, 0.08), trim)
	m.box("wall", base * at(c + Vector3(0, -h / 2.0 - 0.05, 0.06)), Vector3(w + 0.3, 0.08, 0.12), trim)
	if not stone:
		for s: float in [-1.0, 1.0]:
			m.box("wall", base * at(c + Vector3(s * (w / 2.0 + 0.05), 0, 0.03)), Vector3(0.1, h, 0.06), trim)
	if shutter is Color:
		for s: float in [-1.0, 1.0]:
			m.box("wall", base * at(c + Vector3(s * (w * 0.75 + 0.14), 0, 0.03)), Vector3(w * 0.48, h, 0.04),
				kc(shutter as Color, K_PAINT))
	_pane(base, c + Vector3(-w / 2.0, -h / 2.0, 0.015), c + Vector3(w / 2.0, h / 2.0, 0.015),
		Color(thr, _rng.randf(), style, _rng.randf()))


func _theatre_front(base: Transform3D, w: float, h: float) -> void:
	var dark := kc(Color(0.30, 0.10, 0.10), K_PAINT)
	for s: float in [-1.0, 1.0]:
		m.box("wall", base * at(Vector3(s * (w / 2.0 - 0.3), 1.9, 0.08)), Vector3(0.6, 3.8, 0.16), kc(TRIM, K_PAINT))
	# The box office and the doors under the marquee.
	m.box("wall", base * at(Vector3(0, 1.3, 0.3)), Vector3(1.8, 2.6, 0.6), dark)
	_pane(base, Vector3(-0.7, 1.2, 0.61), Vector3(0.7, 2.2, 0.61), Color(0.05, 0.3, 0.5, 0.8))
	for s: float in [-1.0, 1.0]:
		m.box("wall", base * at(Vector3(s * 3.4, 1.2, 0.04)), Vector3(2.6, 2.4, 0.08), dark)
		_pane(base, Vector3(s * 3.4 - 1.1, 0.3, 0.085), Vector3(s * 3.4 + 1.1, 2.2, 0.085), Color(0.08, 0.6, 0.5, 0.7))
	# The marquee over the walk: a letter board on three sides, lit
	# from under, a border of bulbs that chase.
	var mq := base * at(Vector3(0, 4.3, 1.4))
	m.box("wall", mq, Vector3(w - 1.0, 1.3, 2.8), kc(Color(0.72, 0.62, 0.30), K_PAINT), true)
	m.box("wall", mq * at(Vector3(0, 0, 1.41)), Vector3(w - 1.6, 0.9, 0.02), kc(Color(0.92, 0.90, 0.82), K_PAINT))
	_sign(mq * at(Vector3(0, 0.18, 1.44)), "NOW SHOWING", 64, Color(0.08, 0.08, 0.08))
	_sign(mq * at(Vector3(0, -0.2, 1.44)), "DOUBLE FEATURE", 56, Color(0.35, 0.05, 0.05))
	var n := int((w - 1.0) / 0.3)
	for k in n:
		for row: float in [-0.6, 0.6]:
			var x := -(w - 1.0) / 2.0 + (k + 0.5) * (w - 1.0) / n
			_bulb(mq * Vector3(x, row, 1.42), 0.05, true)
	for k in 7:
		for s: float in [-1.0, 1.0]:
			_bulb(mq * Vector3(-(w - 1.6) / 2.0 + (w - 1.6) * (k + 0.5) / 7.0, -0.66, s * 1.2), 0.06, false, 0.05)
	# The blade sign, up the front above the marquee.
	var blade := base * at(Vector3(0, 7.2, 0.9))
	m.box("wall", blade, Vector3(0.35, 4.4, 1.3), kc(Color(0.62, 0.12, 0.10), K_PAINT), true)
	for s: float in [-1.0, 1.0]:
		var face := blade * Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(s * 0.19, 0, 0))
		_sign(face, "S\nT\nR\nA\nN\nD", 72, Color(1.0, 0.86, 0.55), true)
		for k in 12:
			_bulb(blade * Vector3(s * 0.19, -2.1 + 4.2 * k / 11.0, 0.62), 0.045, true)
	var under := OmniLight3D.new()
	under.transform = base * at(Vector3(0, 3.4, 1.6))
	under.omni_range = 9.0
	under.light_color = Color(1.0, 0.82, 0.55)
	add_child(under)
	lamps.append({"light": under, "delay": 0.05, "energy": 2.2})


## A bulb in the lamp mesh: marquee bulbs chase.
func _bulb(pos: Vector3, r: float, chase: bool, delay: float = 0.0) -> void:
	var col := Color(delay, 1.0 if chase else 0.0, float(_marquee_bulb % 64) / 64.0, 1.0)
	_marquee_bulb += 1
	m.box("lamp", at(pos), Vector3(r, r, r) * 2.0, col, true)


func _bank_front(base: Transform3D, w: float, h: float, sign: String) -> void:
	var stone := kc(Color(0.70, 0.68, 0.64), K_GRANITE)
	for s: float in [-1.0, 1.0]:
		m.cylinder("wall", base * at(Vector3(s * 1.6, 2.6, 0.55)), 0.28, 0.24, 4.6, 12, kc(Color(0.78, 0.76, 0.72), K_PAINT))
	m.box("wall", base * at(Vector3(0, 5.1, 0.55)), Vector3(4.4, 0.5, 1.1), stone, true)
	m.box("wall", base * at(Vector3(0, 0.15, 0.6)), Vector3(4.6, 0.3, 1.2), stone)
	m.box("wall", base * at(Vector3(0, 1.4, 0.03)), Vector3(1.6, 2.8, 0.06), kc(Color(0.20, 0.15, 0.10), K_PAINT))
	for s: float in [-1.0, 1.0]:
		_window(base, Vector3(s * 3.3, 2.6, 0.0), 1.1, 2.8, 1.0, null, 0.5, true)
	_sign(base * at(Vector3(0, 5.95, 0.12)), sign, 80, Color(0.18, 0.18, 0.18))


func _post_front(base: Transform3D, w: float, h: float, sign: String) -> void:
	m.box("wall", base * at(Vector3(0, 0.15, 0.9)), Vector3(4.0, 0.3, 1.8), kc(GRANITE, K_GRANITE))
	m.box("wall", base * at(Vector3(0, 1.45, 0.03)), Vector3(1.8, 2.6, 0.06), kc(Color(0.14, 0.2, 0.15), K_PAINT))
	_pane(base, Vector3(-0.7, 1.6, 0.065), Vector3(0.7, 2.6, 0.065), Color(0.2, 0.2, 0.5, 0.7))
	for s: float in [-1.0, 1.0]:
		for k in 2:
			_window(base, Vector3(s * (2.2 + 1.8 * k), 2.1, 0.0), 1.1, 2.2, 0.3 if k == 0 else 1.0, null, 0.0, true)
	_sign(base * at(Vector3(0, 3.9, 0.08)), sign, 64, Color(0.86, 0.80, 0.60))
	# The flag on its pole at the corner.
	m.cylinder("iron", at(base * Vector3(w / 2.0 - 0.6, 5.4, 1.2)), 0.05, 0.035, 10.8, 8, TRIM)
	var flag := at(base * Vector3(w / 2.0 - 0.6 - 0.8, 10.0, 1.2), base.basis.get_euler().y)
	m.box("wall", flag, Vector3(1.5, 0.9, 0.02), kc(Color(0.62, 0.12, 0.12), K_TAR), true)


## ---- the south side -------------------------------------------------------

## A stainless diner, the kind built in a factory and trucked to its
## lot: a long car on a brick base, a barrel roof, a band of windows,
## red enamel stripes, a neon sign on the roof.
func _diner(front: Vector2) -> void:
	var base := at(Vector3(front.x, 0.0, front.y), PI)
	var w := 16.0
	var d := 5.6
	m.box("wall", base * at(Vector3(0, 0.35, -d / 2.0)), Vector3(w - 0.3, 0.7, d - 0.3), kc(BRICK, K_BRICK))
	m.box("steel", base * at(Vector3(0, 2.0, -d / 2.0)), Vector3(w, 2.6, d), Color.WHITE)
	m.cylinder("steel", base * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0) * Basis.from_scale(Vector3(0.22, 1.0, 1.0)),
		Vector3(0, 3.3, -d / 2.0)), d / 2.0 + 0.05, d / 2.0 + 0.05, w + 0.1, 20, Color.WHITE)
	_solid(base * at(Vector3(0, 1.8, -d / 2.0)), Vector3(w, 3.6, d))
	var red := kc(Color(0.62, 0.10, 0.09), K_PAINT)
	for y: float in [1.05, 2.95]:
		m.box("wall", base * at(Vector3(0, y, 0.01)), Vector3(w + 0.02, 0.16, 0.04), red)
	var n := 9
	for k in n:
		var x := -w / 2.0 + 0.6 + (w - 1.2) * (k + 0.5) / n
		if absf(x) < 1.0:
			continue
		_pane(base, Vector3(x - 0.72, 1.3, 0.03), Vector3(x + 0.72, 2.7, 0.03), Color(0.08, _rng.randf(), 0.5, 0.9))
	# The vestibule and its door.
	m.box("steel", base * at(Vector3(0, 1.4, 0.8)), Vector3(2.0, 2.8, 1.6), Color.WHITE)
	_pane(base, Vector3(-0.5, 0.3, 1.61), Vector3(0.5, 2.3, 1.61), Color(0.08, 0.2, 0.5, 0.9))
	m.box("wall", base * at(Vector3(0, 0.1, 1.9)), Vector3(2.4, 0.2, 0.8), kc(GRANITE, K_GRANITE))
	# The sign: DINER in red neon on a frame over the roof.
	var frame := base * at(Vector3(0, 4.6, -d / 2.0 + 0.4))
	m.box("iron", frame, Vector3(5.2, 1.1, 0.12), Color(0.12, 0.12, 0.12))
	for s: float in [-1.0, 1.0]:
		m.bar("iron", frame * Vector3(s * 2.2, -0.5, 0), frame * Vector3(s * 2.2, -1.4, -0.6), 0.04, 6, Color(0.12, 0.12, 0.12))
	_sign(frame * at(Vector3(0, 0, 0.08)), "DINER", 150, Color(4.0, 0.35, 0.25), true)
	var neon := OmniLight3D.new()
	neon.transform = frame * at(Vector3(0, 0, 1.0))
	neon.omni_range = 9.0
	neon.light_color = Color(1.0, 0.25, 0.2)
	add_child(neon)
	lamps.append({"light": neon, "delay": 0.02, "energy": 1.2})
	var inside := OmniLight3D.new()
	inside.transform = base * at(Vector3(0, 2.2, 1.6))
	inside.omni_range = 8.0
	inside.light_color = Color(1.0, 0.8, 0.55)
	add_child(inside)
	lamps.append({"light": inside, "thr": 0.08, "energy": 1.4})


## A gas station: a white office and one service bay under a parapet,
## two pumps with lit globes on an island in the forecourt, a round
## sign on a post.
func _gas_station(front: Vector2) -> void:
	var base := at(Vector3(front.x, 0.0, front.y + 4.5), PI)
	var white := kc(Color(0.88, 0.88, 0.85), K_PAINT)
	var green := kc(Color(0.14, 0.34, 0.20), K_PAINT)
	m.box("wall", base * at(Vector3(0, 1.9, -2.5)), Vector3(9.0, 3.8, 5.0), white)
	_solid(base * at(Vector3(0, 1.9, -2.5)), Vector3(9.0, 3.8, 5.0))
	m.box("wall", base * at(Vector3(0, 3.95, 0.02)), Vector3(9.2, 0.4, 0.2), green)
	m.box("wall", base * at(Vector3(2.0, 1.5, 0.03)), Vector3(3.6, 3.0, 0.06), kc(Color(0.75, 0.75, 0.72), K_PAINT))
	_pane(base, Vector3(0.4, 1.6, 0.065), Vector3(3.6, 2.8, 0.065), Color(0.15, 0.2, 0.5, 0.6))
	_pane(base, Vector3(-3.9, 1.0, 0.02), Vector3(-1.6, 2.6, 0.02), Color(0.1, 0.5, 0.5, 0.6))
	m.box("wall", base * at(Vector3(-0.9, 1.1, 0.03)), Vector3(0.95, 2.2, 0.06), green)
	_sign(base * at(Vector3(-1.2, 3.95, 0.14)), "GARAGE", 64, Color(0.92, 0.9, 0.84))
	# The pump island and its two pumps.
	var island := base * at(Vector3(0, 0.1, 3.2))
	m.box("wall", island, Vector3(4.2, 0.2, 1.1), kc(Color(0.6, 0.59, 0.56), K_PAINT))
	for s: float in [-1.0, 1.0]:
		var pump := island * at(Vector3(s * 1.2, 0.95, 0))
		m.box("iron", pump, Vector3(0.55, 1.7, 0.42), Color(0.62, 0.10, 0.08))
		m.box("iron", pump * at(Vector3(0, 0.35, 0.215)), Vector3(0.36, 0.36, 0.01), Color(0.9, 0.88, 0.8))
		m.cylinder("iron", pump * at(Vector3(0, 0.95, 0)), 0.08, 0.08, 0.2, 8, Color(0.62, 0.10, 0.08))
		m.sphere("lamp", pump * Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.45)), Vector3(0, 1.25, 0)), 0.26, 12, Color(0.03, 0, 0, 1))
		_solid(pump, Vector3(0.55, 1.7, 0.42))
	# The sign on its post.
	var post := base * at(Vector3(-4.8, 0, 4.4))
	m.cylinder("iron", post * at(Vector3(0, 2.8, 0)), 0.09, 0.09, 5.6, 8, Color(0.85, 0.85, 0.82))
	m.cylinder("iron", post * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 6.0, 0)), 0.95, 0.95, 0.14, 24, Color(0.85, 0.85, 0.82))
	for s: float in [-1.0, 1.0]:
		var face := post * Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(0, 6.0, s * 0.08))
		_sign(face, "GASOLINE", 64, Color(0.62, 0.10, 0.08))
	var light := OmniLight3D.new()
	light.transform = base * at(Vector3(0, 3.3, 2.2))
	light.omni_range = 10.0
	light.light_color = Color(1.0, 0.86, 0.66)
	add_child(light)
	lamps.append({"light": light, "delay": 0.04, "energy": 1.6})


## A grocery: two storeys of clapboard behind a square false front, a
## porch across it with a bench.
func _grocery(front: Vector2) -> void:
	var base := at(Vector3(front.x, 0.0, front.y + 1.9), PI)
	var w := 10.0
	var d := 10.0
	var clap := kc(Color(0.86, 0.80, 0.60), K_CLAP)
	m.box("wall", base * at(Vector3(0, 0.3, -d / 2.0)), Vector3(w + 0.1, 0.6, d + 0.1), kc(GRANITE, K_GRANITE))
	m.box("wall", base * at(Vector3(0, 3.6, -d / 2.0)), Vector3(w, 6.0, d), clap)
	_solid(base * at(Vector3(0, 3.6, -d / 2.0)), Vector3(w, 7.2, d))
	_roof(base, Vector3(0, 6.6, -d / 2.0), w, d, deg_to_rad(28.0), false, clap, kc(ROOFS[0], K_ROOF), 0.3)
	m.box("wall", base * at(Vector3(0, 7.6, 0.05)), Vector3(w, 2.0, 0.1), clap)
	m.box("wall", base * at(Vector3(0, 8.65, 0.1)), Vector3(w + 0.2, 0.12, 0.3), kc(TRIM, K_PAINT))
	_sign(base * at(Vector3(0, 7.5, 0.12)), "GROCERIES", 96, Color(0.25, 0.12, 0.08))
	_shopfront(base, w, 3.4, "", null)
	for k in 3:
		_window(base, Vector3(-3.0 + 3.0 * k, 5.0, 0.0), 0.9, 1.5, _upstairs_threshold(), null)
	# The porch: floor, posts, a roof.
	var wood := kc(Color(0.55, 0.50, 0.44), K_PLANK)
	m.box("wall", base * at(Vector3(0, 0.45, 1.3)), Vector3(w, 0.2, 2.6), wood)
	_solid(base * at(Vector3(0, 0.25, 1.3)), Vector3(w, 0.5, 2.6))
	for k in 4:
		m.box("wall", base * at(Vector3(-w / 2.0 + 0.2 + (w - 0.4) * k / 3.0, 1.95, 2.45)), Vector3(0.14, 2.8, 0.14), kc(TRIM, K_PAINT))
	m.box("wall", base * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(0, 3.45, 1.3)), Vector3(w + 0.3, 0.1, 3.0), kc(ROOFS[1], K_ROOF), true)
	m.box("wall", base * at(Vector3(2.5, 0.8, 0.5)), Vector3(1.6, 0.08, 0.4), wood)


## A white church: a clapboard nave under a steep roof, tall windows, a
## square tower at the front rising to a belfry and a spire.
func _church(front: Vector2) -> void:
	var base := at(Vector3(front.x, 0.0, front.y + 2.4), PI)
	var white := kc(Color(0.93, 0.92, 0.88), K_CLAP)
	var w := 11.0
	var d := 20.0
	m.box("wall", base * at(Vector3(0, 0.35, -d / 2.0)), Vector3(w + 0.1, 0.7, d + 0.1), kc(GRANITE, K_GRANITE))
	m.box("wall", base * at(Vector3(0, 4.3, -d / 2.0)), Vector3(w, 7.2, d), white)
	_solid(base * at(Vector3(0, 4.0, -d / 2.0)), Vector3(w, 8.0, d))
	_roof(base, Vector3(0, 7.9, -d / 2.0), w, d, deg_to_rad(45.0), false, white, kc(Color(0.22, 0.23, 0.25), K_ROOF), 0.4)
	# Tall windows down each side.
	for s: float in [-1.0, 1.0]:
		var side := base * Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(s * w / 2.0, 0, -d / 2.0))
		for k in 4:
			_window(side, Vector3(-7.0 + 4.6 * k, 4.2, 0), 1.3, 4.0, 0.33, null, 1.0)
	# The tower, the belfry and the spire.
	var t := base * at(Vector3(0, 0, 0.9))
	m.box("wall", t * at(Vector3(0, 6.5, 0)), Vector3(4.4, 13.0, 4.4), white)
	_solid(t * at(Vector3(0, 6.5, 0)), Vector3(4.4, 13.0, 4.4))
	m.box("wall", t * at(Vector3(0, 13.1, 0)), Vector3(4.8, 0.3, 4.8), kc(TRIM, K_PAINT))
	m.box("wall", t * at(Vector3(0, 14.9, 0)), Vector3(3.6, 3.4, 3.6), white)
	for f in 4:
		var face := t * Transform3D(Basis(Vector3.UP, f * PI / 2.0), Vector3.ZERO)
		m.box("wall", face * at(Vector3(0, 14.9, 1.81)), Vector3(1.6, 2.2, 0.04), kc(Color(0.12, 0.12, 0.12), K_PAINT))
		for k in 7:
			m.box("wall", face * Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, 14.0 + 0.3 * k, 1.84)),
				Vector3(1.6, 0.04, 0.25), kc(TRIM, K_PAINT))
		for s: float in [-1.0, 1.0]:
			m.box("wall", face * at(Vector3(s * 1.7, 14.9, 1.75)), Vector3(0.3, 3.4, 0.2), kc(TRIM, K_PAINT))
	m.box("wall", t * at(Vector3(0, 16.75, 0)), Vector3(4.0, 0.3, 4.0), kc(TRIM, K_PAINT))
	m.cylinder("wall", t * at(Vector3(0, 22.4, 0)), 2.05, 0.02, 11.0, 8, kc(Color(0.92, 0.91, 0.87), K_PAINT))
	m.sphere("iron", t * at(Vector3(0, 28.1, 0)), 0.14, 10, Color(0.72, 0.58, 0.25))
	m.bar("iron", t * Vector3(0, 27.8, 0), t * Vector3(0, 29.2, 0), 0.025, 6, Color(0.72, 0.58, 0.25))
	# The doors and the steps.
	m.box("wall", t * at(Vector3(0, 1.5, 2.22)), Vector3(1.8, 3.0, 0.06), kc(Color(0.50, 0.09, 0.08), K_PAINT))
	m.box("wall", t * at(Vector3(0, 3.4, 2.24)), Vector3(2.2, 0.4, 0.08), kc(TRIM, K_PAINT))
	_window(t, Vector3(0, 8.0, 2.2), 1.2, 2.4, 0.33, null, 1.0)
	for k in 3:
		m.box("wall", t * at(Vector3(0, 0.12 + 0.2 * k, 3.3 - 0.35 * k)), Vector3(3.2, 0.24, 0.8), kc(GRANITE, K_GRANITE))
	var light := OmniLight3D.new()
	light.transform = t * at(Vector3(0, 3.8, 2.8))
	light.omni_range = 7.0
	light.light_color = LAMP_COLOR
	add_child(light)
	lamps.append({"light": light, "delay": 0.3, "energy": 1.0})


## A gable roof over a body: two shingled slabs meeting at the ridge,
## the gables filled in the wall's finish. centre is the middle of the
## eaves line in base's frame; span across the slope, length along the
## ridge. ridge_x: the ridge runs along base's x (a side-gabled house);
## otherwise along z (a gable front).
func _roof(base: Transform3D, centre: Vector3, span: float, length: float, pitch: float, ridge_x: bool,
		wall: Color, roof: Color, overhang: float) -> void:
	var r := Basis(Vector3.UP, PI / 2.0) if ridge_x else Basis()
	var frame := base * Transform3D(r, centre)
	var rise := span / 2.0 * tan(pitch)
	m.prism("wall", frame, span, rise, length, wall)
	var slope := (span / 2.0) / cos(pitch)
	var t := 0.12
	for side: float in [-1.0, 1.0]:
		var down := Vector3(side * cos(pitch), -sin(pitch), 0)
		var up_n := Vector3(side * sin(pitch), cos(pitch), 0)
		var mid := Vector3(side * span / 4.0, rise / 2.0, 0) + up_n * (t / 2.0) + down * (overhang / 2.0)
		var slab := Transform3D(Basis(Vector3(0, 0, 1), -side * pitch), mid)
		m.box("wall", frame * slab, Vector3(slope + overhang, t, length + 2.0 * overhang * 0.8), roof, true)
	m.box("wall", frame * at(Vector3(0, rise + t * 0.9, 0)), Vector3(0.22, 0.08, length + 1.6 * overhang), roof, true)


## ---- houses ---------------------------------------------------------------

func _houses_all() -> void:
	var yaw_s := 0.0      # faces +z (south)
	var yaw_n := PI       # faces -z
	var yaw_e := PI / 2.0
	var mz := TownCoast.MAIN_Z
	var lots: Array = [
		# Main Street, west of Harbor Street.
		[Vector2(-38.0, mz - 8.0), yaw_s], [Vector2(-26.0, mz - 8.0), yaw_s],
		[Vector2(-38.0, mz + 8.0), yaw_n], [Vector2(-26.0, mz + 8.0), yaw_n],
		# Harbor Street, the west side.
		[Vector2(-22.5, -34.0), yaw_e], [Vector2(-22.5, -14.0), yaw_e], [Vector2(-22.5, 50.0), yaw_e],
		# Elm Street.
		[Vector2(4.0, -31.5), yaw_s], [Vector2(17.0, -31.5), yaw_s], [Vector2(30.0, -31.5), yaw_s],
		[Vector2(43.0, -31.5), yaw_s], [Vector2(56.0, -31.5), yaw_s], [Vector2(68.0, -31.5), yaw_s],
		[Vector2(8.0, -17.5), yaw_n], [Vector2(21.0, -17.5), yaw_n], [Vector2(34.0, -17.5), yaw_n],
		[Vector2(47.0, -17.5), yaw_n], [Vector2(60.0, -17.5), yaw_n],
		# Water Street: the north side behind the diner and the grocery,
		# the south side over the harbour.
		[Vector2(-2.0, 37.5), yaw_s], [Vector2(22.0, 37.5), yaw_s], [Vector2(38.0, 37.5), yaw_s],
		[Vector2(7.5, 51.5), yaw_n], [Vector2(33.5, 51.5), yaw_n],
		[Vector2(45.5, 51.5), yaw_n], [Vector2(57.5, 51.5), yaw_n], [Vector2(69.5, 51.5), yaw_n],
	]
	# One house modelled whole, inside and out: the Cape at number 14,
	# its back to the harbour.
	cape = CapeHouse.new()
	add_child(cape)
	cape.build(self, Vector3(21.0, 0.0, 51.5), yaw_n)
	_keep_clear.append(Rect2(Vector2(14.0, 47.5), Vector2(14.0, 14.0)))
	for lot: Array in lots:
		var p: Vector2 = lot[0]
		var shallow := p.y > 30.0 and p.y < 40.0 or (p.y < -15.0 and p.y > -20.0)
		var style := _rng.randi() % 3
		if shallow and style == 2:
			style = 0
		if absf(p.y - 51.5) < 0.1:
			var row_styles := {7.5: 1, 33.5: 2, 45.5: 0, 57.5: 1, 69.5: 2}
			_detailed_house(Vector3(p.x, 0.0, p.y), float(lot[1]), int(row_styles.get(p.x, style)))
		else:
			_house(Vector3(p.x, 0.0, p.y), float(lot[1]), style, shallow)


## A house on the harbour side of Water Street, modelled whole inside and
## out: a Cape like number 14 in its own colours, or a colonial, or a
## gable-front house with a porch.
func _detailed_house(front: Vector3, yaw: float, style: int) -> void:
	_houses += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(front.x * 131.0) + 7
	var clap: Color = CLAPBOARDS[rng.randi() % CLAPBOARDS.size()]
	var kind := K_SHAKE if clap.is_equal_approx(CLAPBOARDS[8]) else K_CLAP
	var papers: Array[Color] = []
	var paper_pool: Array[Color] = [Color(0.72, 0.66, 0.52), Color(0.58, 0.66, 0.72), Color(0.78, 0.62, 0.58),
		Color(0.62, 0.70, 0.58), Color(0.86, 0.80, 0.84), Color(0.84, 0.82, 0.66), Color(0.70, 0.72, 0.78), Color(0.82, 0.74, 0.62)]
	for k in 6:
		papers.append(paper_pool[rng.randi() % paper_pool.size()])
	var cloths: Array[Color] = [Color(0.32, 0.40, 0.30), Color(0.55, 0.22, 0.2), Color(0.3, 0.35, 0.5), Color(0.55, 0.45, 0.3), Color(0.45, 0.3, 0.45)]
	var woods: Array[Color] = [Color(0.42, 0.26, 0.14), Color(0.55, 0.38, 0.22), Color(0.3, 0.18, 0.1)]
	var curtain_pool: Array[Color] = [Color(0.85, 0.82, 0.72), Color(0.9, 0.9, 0.88), Color(0.8, 0.6, 0.55), Color(0.62, 0.7, 0.62), Color(0.88, 0.8, 0.55)]
	var opens: Array[int] = []
	for k in 2:
		opens.append(1 + rng.randi() % 14)
	var house: HouseBase
	if style == 0:
		var cape_house := CapeHouse.new()
		add_child(cape_house)
		cape_house.build(self, front, yaw, {"seed": rng.randi(), "CLAP": clap, "SHUTTER": SHUTTERS[rng.randi() % SHUTTERS.size()],
			"DOOR": DOORS[rng.randi() % DOORS.size()], "ROOF": ROOFS[rng.randi() % ROOFS.size()],
			"paper_living": papers[0], "paper_dining": papers[1], "paper_bed": papers[4], "paper_bed2": papers[5],
			"kitchen_paint": Color(0.9, 0.92, 0.84), "curtains": curtain_pool[rng.randi() % curtain_pool.size()],
			"number": str(int(front.x)), "with_yard": false, "open_windows": opens})
		house = cape_house
	else:
		var full := FullHouse.new()
		add_child(full)
		full.build(self, front, yaw, {"seed": rng.randi(), "style": style, "clap": clap, "clap_kind": kind,
			"shutter": SHUTTERS[rng.randi() % SHUTTERS.size()], "door_color": DOORS[rng.randi() % DOORS.size()],
			"roof": ROOFS[rng.randi() % ROOFS.size()], "papers": papers, "cloth": cloths[rng.randi() % cloths.size()],
			"wood": woods[rng.randi() % woods.size()], "curtains": curtain_pool[rng.randi() % curtain_pool.size()],
			"open_windows": opens})
		house = full
	houses_built.append(house.call("record"))
	var r: Dictionary = houses_built[houses_built.size() - 1]
	var hw: float = r["w"]
	var hd: float = r["d"]
	# No tree whose crown would reach through a wall into the rooms.
	_keep_clear.append(Rect2(Vector2(front.x - hw / 2.0 - 3.5, front.z - 3.5), Vector2(hw + 7.0, hd + 7.0)))


## A house whose front stands at front, facing along yaw. style 0 a
## cape (a storey and a half under a steep roof), 1 a centre-chimney
## colonial (two storeys, five bays, shutters), 2 a gable-front house
## with a porch. shallow: a lot too short for the full depth.
func _house(front: Vector3, yaw: float, style: int, shallow: bool) -> void:
	_houses += 1
	var base := at(front, yaw)
	var color: Color = CLAPBOARDS[_rng.randi() % CLAPBOARDS.size()]
	var kind := K_SHAKE if color.is_equal_approx(CLAPBOARDS[8]) else K_CLAP
	var wall := kc(color, kind)
	var roof := kc(ROOFS[_rng.randi() % ROOFS.size()], K_ROOF)
	var shutter: Variant = SHUTTERS[_rng.randi() % SHUTTERS.size()] if style == 1 or _rng.randf() < 0.3 else null
	var door := kc(DOORS[_rng.randi() % DOORS.size()], K_PAINT)
	var found := 0.6
	var w: float
	var d: float
	var walls: float
	var pitch: float
	match style:
		0:
			w = 10.0
			d = 7.0 if shallow else 8.0
			walls = 2.9
			pitch = deg_to_rad(45.0)
		1:
			w = 11.0
			d = 6.5 if shallow else 8.5
			walls = 5.6
			pitch = deg_to_rad(33.0)
		_:
			w = 7.5
			d = 10.5
			walls = 5.4
			pitch = deg_to_rad(40.0)
	# Some are shifted along the lot: the street is not a row of stamps.
	base = base * at(Vector3(_rng.randf_range(-0.8, 0.8), 0, 0))
	var body := base * at(Vector3(0, found + walls / 2.0, -d / 2.0))
	m.box("wall", base * at(Vector3(0, found / 2.0, -d / 2.0)), Vector3(w + 0.12, found, d + 0.12), kc(GRANITE, K_GRANITE))
	m.box("wall", body, Vector3(w, walls, d), wall)
	_solid(base * at(Vector3(0, (found + walls) / 2.0, -d / 2.0)), Vector3(w, found + walls, d))
	for s: float in [-1.0, 1.0]:
		for e: float in [0.0, -d]:
			m.box("wall", base * at(Vector3(s * (w / 2.0 - 0.02), found + walls / 2.0, e + (0.02 if e == 0.0 else -0.02))),
				Vector3(0.18, walls, 0.06), kc(TRIM, K_PAINT))
	m.box("wall", base * at(Vector3(0, found + walls - 0.12, 0.04)), Vector3(w + 0.1, 0.24, 0.08), kc(TRIM, K_PAINT))
	var eave := found + walls
	var ridge_x := style != 2
	var span := d if ridge_x else w
	var length := w if ridge_x else d
	_roof(base, Vector3(0, eave, -d / 2.0), span, length, pitch, ridge_x, wall, roof, 0.35)
	var rise := span / 2.0 * tan(pitch)
	# Chimneys: one at the ridge for a cape or colonial, at the back of a
	# gable front.
	var chim := kc(BRICK, K_BRICK)
	var chimney_top: Vector3
	if style == 0 or style == 1:
		var cx := 0.0 if style == 0 else w / 2.0 - 1.2
		m.box("wall", base * at(Vector3(cx, eave + rise / 2.0 + 0.6, -d / 2.0)), Vector3(0.8, rise + 1.6, 1.0), chim)
		chimney_top = base * Vector3(cx, eave + rise + 1.4, -d / 2.0)
	else:
		m.box("wall", base * at(Vector3(1.2, eave + rise * 0.4 + 0.8, -d + 1.2)), Vector3(0.7, rise + 1.2, 0.7), chim)
		chimney_top = base * Vector3(1.2, eave + rise * 0.9 + 1.4, -d + 1.2)
	# The front: a door and windows on each floor.
	var f1 := found + 1.55
	var f2 := found + 2.8 + 1.4
	var thr_house := _rng.randf_range(0.18, 0.6)
	var door_x := 0.0 if style != 2 else -w / 2.0 + 1.6
	m.box("wall", base * at(Vector3(door_x, found + 1.05, 0.03)), Vector3(0.95, 2.1, 0.06), door)
	m.box("wall", base * at(Vector3(door_x, found + 2.2, 0.05)), Vector3(1.4, 0.22, 0.1), kc(TRIM, K_PAINT))
	for k in 2:
		m.box("wall", base * at(Vector3(door_x, found - 0.15 - 0.2 * k, 0.4 + 0.3 * k)), Vector3(1.6, 0.2, 0.6 + 0.2 * k), kc(GRANITE, K_GRANITE))
	var xs: Array[float] = []
	if style == 0:
		xs = [-3.4, -1.8, 1.8, 3.4]
	elif style == 1:
		xs = [-4.1, -2.1, 2.1, 4.1]
	else:
		xs = [0.2, 2.2]
	for x in xs:
		_window(base, Vector3(x, f1, 0.0), 0.85, 1.45, _room(thr_house), shutter)
	if style == 1:
		for x: float in [-4.1, -2.1, 0.0, 2.1, 4.1]:
			_window(base, Vector3(x, f2, 0.0), 0.85, 1.3, _room(thr_house), shutter)
	elif style == 2:
		for x: float in [-w / 2.0 + 1.6, 0.2, 2.2]:
			_window(base, Vector3(x, f2, 0.0), 0.85, 1.3, _room(thr_house), shutter)
		_window(base, Vector3(0, eave + rise * 0.35, 0.0), 0.7, 1.0, _room(thr_house), null)
	# The gable ends of a cape and a colonial: windows in the attic and,
	# on a colonial, both floors of the sides.
	for s: float in [-1.0, 1.0]:
		var side := base * Transform3D(Basis(Vector3.UP, s * PI / 2.0), Vector3(s * w / 2.0, 0, -d / 2.0))
		if style == 0:
			for x: float in [-1.2, 1.2]:
				_window(side, Vector3(x, eave + 0.9, 0.0), 0.75, 1.2, _room(thr_house), null)
			_window(side, Vector3(-1.5, f1, 0.0), 0.85, 1.45, _room(thr_house), null)
		elif style == 1:
			for x: float in [-1.8, 1.8]:
				_window(side, Vector3(x, f1, 0.0), 0.85, 1.45, _room(thr_house), null)
				_window(side, Vector3(x, f2, 0.0), 0.85, 1.3, _room(thr_house), null)
		else:
			for x: float in [-3.2, 0.0, 3.2]:
				_window(side, Vector3(x, f1, 0.0), 0.85, 1.45, _room(thr_house), null)
				_window(side, Vector3(x, f2, 0.0), 0.85, 1.3, _room(thr_house), null)
	var back := base * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -d))
	for x: float in [-2.0, 2.0]:
		_window(back, Vector3(x, f1, 0.0), 0.85, 1.3, _room(thr_house), null)
	# Dormers on some capes: a window under its own little gable.
	if style == 0 and _rng.randf() < 0.6:
		# Each dormer's face stands 0.4 m back from the eaves line, where
		# the 45-degree roof is 0.4 m over the eaves, so its window sill
		# clears the shingles.
		for x: float in [-2.4, 2.4]:
			var dorm := base * at(Vector3(x, eave + 1.1, -1.2))
			m.box("wall", dorm, Vector3(1.3, 1.7, 1.6), wall)
			_roof(dorm, Vector3(0, 0.85, 0), 1.3, 1.8, deg_to_rad(45.0), false, wall, roof, 0.12)
			_window(dorm, Vector3(0, 0.0, 0.8), 0.7, 1.0, _room(thr_house), null)
	# A porch across a gable front: floor, posts, a shed roof, a rail.
	if style == 2:
		var deck := kc(Color(0.50, 0.46, 0.40), K_PLANK)
		m.box("wall", base * at(Vector3(0, found - 0.05, 1.2)), Vector3(w, 0.2, 2.4), deck)
		_solid(base * at(Vector3(0, (found - 0.05) / 2.0, 1.2)), Vector3(w, found, 2.4))
		for k in 4:
			var px := -w / 2.0 + 0.15 + (w - 0.3) * k / 3.0
			m.box("wall", base * at(Vector3(px, found + 1.4, 2.3)), Vector3(0.14, 2.8, 0.14), kc(TRIM, K_PAINT))
		m.box("wall", base * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12.0)), Vector3(0, found + 2.95, 1.2)),
			Vector3(w + 0.3, 0.1, 2.9), roof, true)
		m.box("wall", base * at(Vector3(0.9, found + 0.9, 2.3)), Vector3(w - 3.2, 0.07, 0.07), kc(TRIM, K_PAINT))
		# A porch light by the door.
		_porch_light(base * Vector3(door_x + 0.8, found + 2.2, 0.15), thr_house)
	elif _rng.randf() < 0.5:
		_porch_light(base * Vector3(door_x + 0.75, found + 2.0, 0.1), thr_house)
	# A picket fence along the front of the lot, a gap for the walk. Water
	# Street's houses get theirs with the rest of their yards (WaterStreet).
	var water := absf(front.z - 51.5) < 1.0 or absf(front.z - 37.5) < 1.0
	if _rng.randf() < 0.45 and not water:
		_fence(base, -5.5, 5.5, 4.0, door_x)
	houses_built.append({"base": base, "w": w, "d": d, "style": style, "door_x": door_x, "found": found,
		"front_xs": xs, "f1": f1, "chimney": chimney_top, "water": water, "thr": thr_house,
		"harbour_side": absf(front.z - 51.5) < 1.0})


## A room's light: the house's own time plus a little, or never.
func _room(thr: float) -> float:
	return 1.0 if _rng.randf() < 0.25 else clampf(thr + _rng.randf_range(-0.05, 0.25), 0.1, 0.95)


func _porch_light(pos: Vector3, thr: float) -> void:
	var delay := _rng.randf()
	m.sphere("lamp", at(pos), 0.08, 8, Color(delay, 0, 0, 1))
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, -0.1, 0)
	light.omni_range = 5.0
	light.light_color = Color(1.0, 0.72, 0.42)
	add_child(light)
	lamps.append({"light": light, "delay": delay, "energy": 0.6})


func _fence(base: Transform3D, x0: float, x1: float, z: float, gap: float) -> void:
	var white := kc(TRIM, K_PAINT)
	var x := x0
	while x <= x1:
		if absf(x - gap) > 0.7:
			m.box("wall", base * at(Vector3(x, 0.5, z)), Vector3(0.07, 1.0, 0.025), white)
		x += 0.14
	for s: Array in [[x0, gap - 0.7], [gap + 0.7, x1]]:
		var a: float = s[0]
		var b: float = s[1]
		for y: float in [0.3, 0.8]:
			m.box("wall", base * at(Vector3((a + b) / 2.0, y, z - 0.03)), Vector3(b - a, 0.07, 0.03), white)


## ---- lamps ----------------------------------------------------------------

## Cast-iron posts down both walks of Main Street, a milk-glass globe on
## each.
func _main_lamps() -> void:
	var mz := TownCoast.MAIN_Z
	var x := -40.0
	var side := 1.0
	while x <= 72.0:
		if absf(x - TownCoast.HARBOR_X) > 7.0:
			_iron_post(Vector3(x, 0.17, mz + side * 5.0))
		x += 11.0
		side = -side


func _iron_post(foot: Vector3) -> void:
	var xf := at(foot)
	m.box("iron", xf * at(Vector3(0, 0.3, 0)), Vector3(0.36, 0.6, 0.36), IRON)
	m.cylinder("iron", xf * at(Vector3(0, 0.75, 0)), 0.14, 0.1, 0.3, 10, IRON)
	m.cylinder("iron", xf * at(Vector3(0, 2.35, 0)), 0.075, 0.06, 3.0, 10, IRON)
	m.cylinder("iron", xf * at(Vector3(0, 3.9, 0)), 0.11, 0.16, 0.18, 10, IRON)
	var delay := _rng.randf()
	m.sphere("lamp", xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.25, 1.0)), Vector3(0, 4.25, 0)), 0.25, 14, Color(delay, 0, 0, 1))
	m.cylinder("iron", xf * at(Vector3(0, 4.6, 0)), 0.1, 0.02, 0.14, 10, IRON)
	_solid(xf * at(Vector3(0, 2.3, 0)), Vector3(0.3, 4.6, 0.3))
	var light := OmniLight3D.new()
	light.position = foot + Vector3(0, 4.25, 0)
	light.omni_range = 15.0
	light.omni_attenuation = 1.1
	light.light_color = LAMP_COLOR
	light.shadow_enabled = false
	add_child(light)
	lamps.append({"light": light, "delay": delay, "energy": 2.2})


## Wooden utility poles down Harbor Street, Elm, Water and the harbour
## road, strung with three wires on crossarms, a gooseneck lamp under an
## enamel shade on each.
func _pole_lines() -> void:
	var hx := TownCoast.HARBOR_X
	var lines: Array = [
		[Vector3(hx - 5.2, 0, -36.0), Vector3(hx - 5.2, 0, -6.0), Vector3(hx - 5.2, 0, 26.0), Vector3(hx - 5.2, 0, 52.0)],
		[Vector3(2.0, 0, TownCoast.ELM_Z - 4.2), Vector3(24.0, 0, TownCoast.ELM_Z - 4.2), Vector3(46.0, 0, TownCoast.ELM_Z - 4.2),
			Vector3(68.0, 0, TownCoast.ELM_Z - 4.2)],
		[Vector3(2.0, 0, TownCoast.WATER_Z + 4.2), Vector3(24.0, 0, TownCoast.WATER_Z + 4.2), Vector3(46.0, 0, TownCoast.WATER_Z + 4.2),
			Vector3(68.0, 0, TownCoast.WATER_Z + 4.2)],
		[Vector3(-17.1, 0, 67.6), Vector3(-26.9, 0, 73.8), Vector3(-36.7, 0, 80.2)],
	]
	for line: Array in lines:
		var tops: Array[Transform3D] = []
		for k in line.size():
			var p: Vector3 = line[k]
			p.y = coast.height_at(p.x, p.z)
			var next: Vector3 = line[mini(k + 1, line.size() - 1)]
			var prev: Vector3 = line[maxi(k - 1, 0)]
			var along := (next - prev)
			along.y = 0.0
			var yaw := atan2(along.x, along.z)
			tops.append(_pole(p, yaw))
		for k in tops.size() - 1:
			for s: float in [-0.9, 0.0, 0.9]:
				_wire(tops[k] * Vector3(s, 0.1, 0), tops[k + 1] * Vector3(s, 0.1, 0))


## A pole at foot, its crossarm across yaw (the line's direction), the
## lamp's arm reaching toward the street. Returns the crossarm's frame.
func _pole(foot: Vector3, yaw: float) -> Transform3D:
	var xf := at(foot, yaw)
	m.cylinder("wall", xf * at(Vector3(0, 4.6, 0)), 0.15, 0.12, 9.2, 8, kc(POLE, K_TIMBER))
	_solid(xf * at(Vector3(0, 4.6, 0)), Vector3(0.3, 9.2, 0.3))
	var arm := xf * at(Vector3(0, 8.5, 0))
	m.box("wall", arm, Vector3(2.2, 0.1, 0.1), kc(POLE, K_TIMBER))
	for s: float in [-0.9, 0.0, 0.9]:
		m.cylinder("wall", arm * at(Vector3(s, 0.12, 0)), 0.04, 0.03, 0.14, 6, kc(Color(0.30, 0.52, 0.40), K_PAINT))
	# The gooseneck: out from the pole toward the street and down to the
	# shade; a bulb under it.
	var toward := 1.0
	var px := xf * Vector3(1.7, 0, 0)
	var nx := xf * Vector3(-1.7, 0, 0)
	if coast.street_distance(nx.x, nx.z) < coast.street_distance(px.x, px.z):
		toward = -1.0
	var lamp_side := xf * at(Vector3.ZERO, toward * PI / 2.0)
	var a := lamp_side * Vector3(0, 6.8, 0.1)
	var b := lamp_side * Vector3(0, 7.1, 1.1)
	var c := lamp_side * Vector3(0, 6.9, 1.7)
	m.bar("iron", a, b, 0.03, 6, IRON)
	m.bar("iron", b, c, 0.03, 6, IRON)
	var shade := at(c + Vector3(0, -0.12, 0))
	m.cylinder("iron", shade, 0.42, 0.1, 0.22, 16, Color(0.10, 0.22, 0.14))
	var delay := _rng.randf()
	m.sphere("lamp", at(c + Vector3(0, -0.2, 0)), 0.08, 8, Color(delay, 0, 0, 1))
	var spot := SpotLight3D.new()
	spot.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), c + Vector3(0, -0.2, 0))
	spot.spot_angle = 62.0
	spot.spot_range = 16.0
	spot.spot_attenuation = 1.0
	spot.light_color = LAMP_COLOR
	spot.shadow_enabled = false
	add_child(spot)
	lamps.append({"light": spot, "delay": delay, "energy": 5.0})
	return arm


## A wire from a to b hanging in a shallow curve.
func _wire(a: Vector3, b: Vector3) -> void:
	var sag := a.distance_to(b) * 0.018
	var prev := a
	for k in range(1, 7):
		var t := k / 6.0
		var p := a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		m.bar("iron", prev, p, 0.012, 4, Color(0.05, 0.05, 0.05))
		prev = p


## ---- the waterfront -------------------------------------------------------

## The granite bulkhead along the apron, the wharf on its piles out to
## the T-head, the fish houses, traps stacked to dry, bollards and a
## gin pole, and two lamps on the wharf.
func _waterfront() -> void:
	var ay := TownCoast.APRON_Y
	var lo := TownCoast.APRON - TownCoast.APRON_HALF
	var hi := TownCoast.APRON + TownCoast.APRON_HALF
	var bulk := at(Vector3(TownCoast.APRON.x, ay - 2.6, hi.y + 0.6))
	m.box("wall", bulk, Vector3(hi.x - lo.x, 5.2, 1.2), kc(GRANITE, K_GRANITE), true)
	_solid(bulk, Vector3(hi.x - lo.x, 5.2, 1.2))
	# The wharf: deck, stringers, piles down to the bottom.
	var dy := TownCoast.DECK_Y
	var wx := TownCoast.WHARF_X
	var z0 := TownCoast.WHARF_FROM
	var z1 := TownCoast.HEAD_Z.x
	var plank := kc(Color(0.52, 0.48, 0.42), K_PLANK)
	var timber := kc(CREOSOTE, K_TIMBER)
	var deck := at(Vector3(wx, dy - 0.15, (z0 + z1) / 2.0))
	m.box("wall", deck, Vector3(4.6, 0.3, z1 - z0), plank, true)
	_solid(deck, Vector3(4.6, 0.3, z1 - z0))
	var hx := TownCoast.HEAD_X
	var hz := TownCoast.HEAD_Z
	var head := at(Vector3((hx.x + hx.y) / 2.0, dy - 0.15, (hz.x + hz.y) / 2.0))
	m.box("wall", head, Vector3(hx.y - hx.x, 0.3, hz.y - hz.x), plank, true)
	_solid(head, Vector3(hx.y - hx.x, 0.3, hz.y - hz.x))
	var piles: Array[Vector2] = []
	var z := z0 + 1.5
	while z < z1:
		piles.append(Vector2(wx - 2.1, z))
		piles.append(Vector2(wx + 2.1, z))
		z += 3.0
	var x := hx.x + 0.3
	while x <= hx.y:
		piles.append(Vector2(x, hz.x + 0.3))
		piles.append(Vector2(x, hz.y - 0.3))
		x += 3.0
	for p in piles:
		var bottom := coast.height_at(p.x, p.y) - 0.5
		var top := dy + 0.35
		m.cylinder("wall", at(Vector3(p.x, (top + bottom) / 2.0, p.y)), 0.17, 0.15, top - bottom, 8, timber)
	for s: float in [-1.0, 1.0]:
		m.box("wall", at(Vector3(wx + s * 2.1, dy - 0.45, (z0 + z1) / 2.0)), Vector3(0.25, 0.3, z1 - z0), timber, true)
	m.box("wall", at(Vector3((hx.x + hx.y) / 2.0, dy - 0.45, hz.y - 0.3)), Vector3(hx.y - hx.x, 0.3, 0.25), timber, true)
	m.box("wall", at(Vector3((hx.x + hx.y) / 2.0, dy - 0.45, hz.x + 0.3)), Vector3(hx.y - hx.x, 0.3, 0.25), timber, true)
	# Bollards along the T-head's edge, a cap log along the wharf's.
	for k in 5:
		var bx := hx.x + 1.0 + (hx.y - hx.x - 2.0) * k / 4.0
		m.cylinder("iron", at(Vector3(bx, dy + 0.25, hz.y - 0.5)), 0.16, 0.13, 0.5, 10, Color(0.1, 0.1, 0.1))
	for s: float in [-1.0, 1.0]:
		m.box("wall", at(Vector3(wx + s * 2.2, dy + 0.1, (z0 + z1) / 2.0)), Vector3(0.22, 0.2, z1 - z0), timber)
	# The fish houses on the apron: weathered shingle and barn red, a
	# bait shed out on the T-head.
	_shed(Vector3(-42.0, ay, 77.5), 0.0, 7.0, 5.0, 3.2, kc(Color(0.56, 0.53, 0.49), K_SHAKE), true)
	_shed(Vector3(-19.5, ay, 77.0), 0.0, 5.5, 4.2, 2.8, kc(Color(0.52, 0.17, 0.13), K_CLAP), false)
	_shed(Vector3(-37.0, dy, 116.0), PI / 2.0, 3.4, 3.0, 2.4, kc(Color(0.56, 0.53, 0.49), K_SHAKE), false)
	# Traps stacked to dry, some wooden lath, some wire painted yellow
	# and green; barrels; buoys hung on a shed wall.
	var trap_colors: Array[Color] = [Color(0.45, 0.38, 0.28), Color(0.72, 0.62, 0.20), Color(0.22, 0.42, 0.26)]
	for stack: Vector3 in [Vector3(-33.0, ay, 76.0), Vector3(-33.0, ay, 77.2), Vector3(-26.5, ay, 80.5),
			Vector3(-24.0, dy, 118.5), Vector3(-22.8, dy, 118.5), Vector3(-26.0, ay, 76.0)]:
		var tc := trap_colors[_rng.randi() % trap_colors.size()]
		var high := 2 + _rng.randi() % 4
		for k in high:
			var tx := at(stack + Vector3(0, 0.28 + 0.56 * k, 0), _rng.randf_range(-0.08, 0.08))
			m.box("wall", tx, Vector3(1.1, 0.55, 0.62), kc(tc, K_PLANK if tc.r < 0.5 and tc.g < 0.4 else K_PAINT))
		_solid(at(stack + Vector3(0, 0.28 * high, 0)), Vector3(1.1, 0.56 * high, 0.62))
	for k in 3:
		m.cylinder("wall", at(Vector3(-46.0 + 0.7 * k, ay + 0.45, 80.2)), 0.3, 0.3, 0.9, 12, kc(Color(0.30, 0.34, 0.40), K_PAINT))
	var buoy_colors: Array[Color] = [Color(0.85, 0.75, 0.2), Color(0.8, 0.2, 0.15), Color(0.2, 0.5, 0.3), Color(0.9, 0.9, 0.85)]
	for k in 8:
		var bc := buoy_colors[k % buoy_colors.size()]
		m.cylinder("wall", at(Vector3(-44.9 + 0.55 * k, ay + 1.5 + 0.4 * (k % 2), 80.05)), 0.11, 0.11, 0.55, 8, kc(bc, K_PAINT))
	# The gin pole on the T-head, for landing the catch.
	var gin := Vector3(-20.0, dy, 113.5)
	m.cylinder("wall", at(gin + Vector3(0, 3.0, 0)), 0.14, 0.11, 6.0, 8, timber)
	m.bar("wall", gin + Vector3(0, 1.2, 0), gin + Vector3(1.2, 4.6, 2.2), 0.08, 6, timber)
	m.bar("iron", gin + Vector3(1.2, 4.6, 2.2), gin + Vector3(1.2, 2.2, 2.2), 0.01, 4, Color(0.3, 0.28, 0.24))
	_solid(at(gin + Vector3(0, 3.0, 0)), Vector3(0.3, 6.0, 0.3))
	# Two lamps on posts on the T-head and one at the wharf's foot.
	for p: Vector3 in [Vector3(-40.5, dy, 119.4), Vector3(-19.5, dy, 112.6), Vector3(-27.6, dy, 86.0)]:
		_wharf_lamp(p)


func _shed(front: Vector3, yaw: float, w: float, d: float, h: float, wall: Color, window: bool) -> void:
	var base := at(front, yaw)
	m.box("wall", base * at(Vector3(0, h / 2.0, -d / 2.0)), Vector3(w, h, d), wall)
	_solid(base * at(Vector3(0, h / 2.0, -d / 2.0)), Vector3(w, h, d))
	_roof(base, Vector3(0, h, -d / 2.0), d, w, deg_to_rad(38.0), true, wall, kc(Color(0.22, 0.22, 0.22), K_ROOF), 0.25)
	m.box("wall", base * at(Vector3(-w * 0.2, 1.0, 0.03)), Vector3(1.1, 2.0, 0.06), kc(Color(0.45, 0.10, 0.08), K_PAINT))
	if window:
		_window(base, Vector3(w * 0.25, 1.5, 0.0), 0.8, 0.9, 0.3, null)


func _wharf_lamp(foot: Vector3) -> void:
	var xf := at(foot)
	m.cylinder("wall", xf * at(Vector3(0, 2.2, 0)), 0.1, 0.09, 4.4, 8, kc(CREOSOTE, K_TIMBER))
	_solid(xf * at(Vector3(0, 2.2, 0)), Vector3(0.2, 4.4, 0.2))
	var c := foot + Vector3(0.7, 4.3, 0)
	m.bar("iron", foot + Vector3(0, 4.2, 0), c, 0.025, 6, IRON)
	m.cylinder("iron", at(c + Vector3(0, -0.1, 0)), 0.36, 0.09, 0.2, 14, Color(0.10, 0.22, 0.14))
	var delay := _rng.randf()
	m.sphere("lamp", at(c + Vector3(0, -0.18, 0)), 0.07, 8, Color(delay, 0, 0, 1))
	var spot := SpotLight3D.new()
	spot.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), c + Vector3(0, -0.2, 0))
	spot.spot_angle = 65.0
	spot.spot_range = 13.0
	spot.light_color = LAMP_COLOR
	add_child(spot)
	lamps.append({"light": spot, "delay": delay, "energy": 4.0})


## ---- trees ----------------------------------------------------------------

## Street trees down both sides of every street in town, maples and
## elms turning; more in the yards and round the church, and a few
## spruces standing among the houses.
func _street_trees() -> void:
	var trees: Array[Vector2] = []
	for k in 4:
		var street: Array = TownCoast.STREETS[k]
		var pts: Array = street[0]
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var off := float(street[1]) / 2.0 + (3.9 if k < 2 else 2.2)
		var t := 3.0
		while t < a.distance_to(b):
			for s: float in [-1.0, 1.0]:
				trees.append(a + dir * (t + _rng.randf_range(-1.5, 1.5) + (4.5 if s > 0.0 else 0.0)) + side * s * off)
			t += 10.0
	for k in 500:
		trees.append(Vector2(_rng.randf_range(-44.0, 74.0), _rng.randf_range(-40.0, 58.0)))
	var planted: Array[Vector2] = []
	for p in trees:
		if not _clear_for_tree(p):
			continue
		var crowded := false
		for q in planted:
			if p.distance_to(q) < 5.0:
				crowded = true
				break
		if crowded:
			continue
		planted.append(p)
		var foot := Vector3(p.x, coast.height_at(p.x, p.y), p.y)
		if _rng.randf() < 0.12 and coast.street_distance(p.x, p.y) > 4.0:
			_trees.plant_conifer(foot, _rng.randf_range(11.0, 17.0), _rng)
		else:
			_trees.plant_broadleaf(foot, _rng.randf_range(10.0, 16.0), LEAVES[_rng.randi() % LEAVES.size()], _rng)
	stats_trees = planted.size()


## A tree stands clear of the streets and of every building.
func _clear_for_tree(p: Vector2) -> bool:
	if coast.street_distance(p.x, p.y) < 1.5:
		return false
	for r in _keep_clear:
		if r.has_point(p):
			return false
	for body in _solids.get_children():
		var b := body as StaticBody3D
		var shape := (b.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var local := b.transform.affine_inverse() * Vector3(p.x, b.transform.origin.y, p.y)
		var half := shape.size / 2.0 + Vector3(0.8, 0, 0.8)
		if absf(local.x) < half.x and absf(local.z) < half.z:
			return false
	return true
