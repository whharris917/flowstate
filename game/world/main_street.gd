class_name MainStreet
extends RefCounted
## Main Street as the commercial core of a small New England capital
## after Montpelier's: brick blocks of three and four storeys built
## shoulder to shoulder in the 1880s and 90s, each its own height and
## its own red, cast-iron shopfronts with plate glass and a recessed
## door under a sign band, the storeys above in tall two-over-two sashes
## under segmental or round-arched hoods with granite sills and
## keystones, and a bracketed cornice along every top; a corner oriel
## with a slate cap at the street corner; a granite bank; the picture
## house with its marquee; a hotel with a two-storey porch and a
## mansard roof; the post office in granite. Across the street a brick
## city hall with a clock tower, more blocks, and a granite library.
## At the head of the street, on a lawn above its end, a granite hall
## with a Doric portico and a gilded dome, the woods on the hill behind.
##
## Art only. Every building stands on its terrace (TownCoast.BUILDINGS)
## with its front on the walk; the clock's hands follow the world's
## time (HarborTown.set_clock).

const G := 4.6          # the ground storey
const U := 3.7          # each storey above
const NORTH_Z := TownCoast.MAIN_Z - 7.0
const SOUTH_Z := TownCoast.MAIN_Z + 7.0
const STONE := Color(0.66, 0.65, 0.62)      # Barre granite, dressed
const IRON_FRONT: Array[Color] = [Color(0.12, 0.16, 0.13), Color(0.22, 0.14, 0.10), Color(0.10, 0.10, 0.11),
	Color(0.30, 0.26, 0.20)]
const BRICKS: Array[Color] = [Color(0.50, 0.25, 0.18), Color(0.56, 0.28, 0.19), Color(0.45, 0.22, 0.17),
	Color(0.60, 0.34, 0.24), Color(0.52, 0.30, 0.22)]
const CORNICES: Array[Color] = [Color(0.30, 0.28, 0.25), Color(0.42, 0.36, 0.28), Color(0.22, 0.26, 0.22),
	Color(0.80, 0.76, 0.66)]
const SLATE := Color(0.24, 0.24, 0.27)
const COPPER := Color(0.36, 0.56, 0.48)
const GOLD := Color(1.0, 0.77, 0.34)


static func build(t: HarborTown) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1889
	# The north side, west to east. Local x runs along the front; side 1
	# faces south across the street, -1 north.
	_block(t, rng, -8.0, 3.0, 1, 14.5, {"floors": 4, "shops": 2, "signs": ["HARDWARE", "BOOKS"], "win": "segment",
		"awnings": [Color(0.20, 0.36, 0.22), null], "oriel": -1, "belt": true, "crest": true})
	_block(t, rng, 3.0, 12.0, 1, 14.5, {"floors": 3, "signs": ["DRUGS"], "win": "round_top",
		"awnings": [Color(0.55, 0.12, 0.10)]})
	_block(t, rng, 12.0, 25.0, 1, 14.5, {"floors": 3, "front": "theatre", "win": "flat", "face": Color(0.60, 0.44, 0.30)})
	_block(t, rng, 25.0, 34.0, 1, 14.5, {"floors": 3, "front": "bank", "win": "round", "kind": HarborTown.K_GRANITE,
		"face": STONE, "cornice": Color(0.62, 0.61, 0.58)})
	_block(t, rng, 34.0, 46.0, 1, 14.5, {"floors": 3, "front": "hotel", "win": "segment", "top": "mansard",
		"face": Color(0.47, 0.24, 0.18), "setback": 2.4, "signs": ["HOTEL"]})
	_block(t, rng, 46.0, 56.0, 1, 14.5, {"floors": 3, "front": "post", "win": "flat", "kind": HarborTown.K_GRANITE,
		"face": Color(0.62, 0.61, 0.58), "cornice": Color(0.60, 0.59, 0.56)})
	# The south side, east to west as seen from the street (local x runs
	# west on this side).
	_city_hall(t, rng, -6.5, 10.5)
	_block(t, rng, 11.5, 19.5, -1, 9.0, {"floors": 4, "signs": ["GROCERIES"], "win": "segment", "belt": true,
		"awnings": [Color(0.60, 0.50, 0.30)]})
	_block(t, rng, 19.5, 28.5, -1, 9.5, {"floors": 3, "shops": 2, "signs": ["CLOTHING", "JEWELER"], "win": "round_top",
		"awnings": [null, Color(0.18, 0.22, 0.40)], "crest": true})
	_library(t, rng, 30.5, 43.0)
	_block(t, rng, 43.5, 53.0, -1, 9.0, {"floors": 3, "signs": ["LUNCH"], "win": "segment",
		"awnings": [Color(0.62, 0.14, 0.12)], "oriel": -1})
	_domed_hall(t, rng)


## The frame of a building on the street: origin at the middle of its
## front on the ground, +z out to the street.
static func _frame(t: HarborTown, x0: float, x1: float, side: int, setback := 0.0) -> Transform3D:
	var cx := (x0 + x1) / 2.0
	var fz := NORTH_Z - setback if side > 0 else SOUTH_Z + setback
	var gy := t.coast.height_at(cx, fz - side * 1.0)
	return HarborTown.at(Vector3(cx, gy, fz), 0.0 if side > 0 else PI)


static func _top(floors: int) -> float:
	return G + U * (floors - 1) + 1.3


## ---- a commercial block ----------------------------------------------------

static func _block(t: HarborTown, rng: RandomNumberGenerator, x0: float, x1: float, side: int, depth: float,
		s: Dictionary) -> void:
	var setback: float = s.get("setback", 0.0)
	var base := _frame(t, x0, x1, side, setback)
	var w := x1 - x0
	var floors: int = s.get("floors", 3)
	var h := _top(floors)
	var kind: int = s.get("kind", HarborTown.K_BRICK)
	var face: Color = s.get("face", BRICKS[rng.randi() % BRICKS.size()])
	var wall := HarborTown.kc(face, kind)
	var front: String = s.get("front", "shop")
	var cornice: Color = s.get("cornice", CORNICES[rng.randi() % CORNICES.size()])
	var iron: Color = IRON_FRONT[rng.randi() % IRON_FRONT.size()]
	depth -= setback
	# The body. A shop's ground storey stands back where its doors are
	# recessed, the storeys above carried over them to the street line.
	var recess := 1.2 if front == "shop" else 0.0
	t.m.box("wall", base * HarborTown.at(Vector3(0, (h - 1.2) / 2.0, -(depth + recess) / 2.0)),
		Vector3(w, h + 1.2, depth - recess), wall)
	t._solid(base * HarborTown.at(Vector3(0, h / 2.0, -(depth + recess) / 2.0)), Vector3(w, h, depth - recess))
	if recess > 0.0:
		t.m.box("wall", base * HarborTown.at(Vector3(0, (G + h) / 2.0, -recess / 2.0)), Vector3(w, h - G, recess), wall, true)
	# The flat roof behind its parapet, a chimney on each party wall.
	t.m.box("wall", base * HarborTown.at(Vector3(0, h + 0.02, -depth / 2.0)), Vector3(w - 0.6, 0.04, depth - 0.6),
		HarborTown.kc(Color(0.14, 0.14, 0.14), HarborTown.K_TAR))
	for e: float in [-1.0, 1.0]:
		if rng.randf() < 0.7:
			var cz := -rng.randf_range(3.0, depth - 2.0)
			t.m.box("wall", base * HarborTown.at(Vector3(e * (w / 2.0 - 0.45), h + 0.8, cz)), Vector3(0.9, 1.6, 0.6),
				HarborTown.kc(face * 0.9, HarborTown.K_BRICK))
	# The ground storey.
	match front:
		"theatre":
			t._theatre_front(base, w, h)
		"bank":
			_bank_front(t, rng, base, w)
		"post":
			t._post_front(base, w, h, "U.S. POST OFFICE")
		"hotel":
			_hotel_front(t, rng, base, w, setback, iron, s)
		_:
			_shops(t, rng, base, w, int(s.get("shops", 1)), iron, s.get("signs", []), s.get("awnings", []))
	# Belt courses of granite between the storeys.
	if bool(s.get("belt", false)):
		for k in range(1, floors - 1):
			t.m.box("wall", base * HarborTown.at(Vector3(0, G + U * k - 0.1, 0.04)), Vector3(w, 0.2, 0.08),
				HarborTown.kc(STONE, HarborTown.K_GRANITE))
	# The storeys above: tall sashes in bays.
	var bays: int = s.get("bays", maxi(2, int(w / 2.5)))
	var win: String = s.get("win", "segment")
	var oriel: int = s.get("oriel", 0)
	for f in range(1, floors):
		var wh := 2.2 - 0.15 * (f - 1)
		var y := G + U * (f - 1) + 0.55 + wh / 2.0 + (0.4 if f == 1 else 0.0)
		var style := win
		if win == "round_top":
			style = "round" if f == floors - 1 else "segment"
		for b in bays:
			var x := -w / 2.0 + w * (b + 0.5) / bays
			if front == "theatre" and absf(x) < 1.6:
				continue
			if oriel != 0 and absf(x - oriel * (w / 2.0 - 1.4)) < 1.4:
				continue
			_opening(t, rng, base, Vector3(x, y, 0.0), 1.0, wh, style, face, kind)
	if oriel != 0:
		_oriel(t, rng, base, Vector3(oriel * (w / 2.0 - 1.4), 0, 0.0), floors, h, face, kind)
	# The top: a bracketed cornice over a frieze, and on some a crest
	# over the middle; the hotel a mansard storey with dormers.
	_cornice(t, base, w, h, cornice, face, kind)
	if bool(s.get("crest", false)):
		var c := HarborTown.kc(cornice, HarborTown.K_PAINT)
		t.m.prism("wall", base * HarborTown.at(Vector3(0, h + 0.1, 0.25)), 3.4, 0.9, 0.3, c)
		t.m.box("wall", base * HarborTown.at(Vector3(0, h + 0.05, 0.25)), Vector3(3.6, 0.1, 0.4), c)
	if s.get("top", "") == "mansard":
		_mansard(t, rng, base, w, depth, h + 0.1, bays)


## The shops across a ground storey: cast-iron piers, plate glass over
## panelled kickplates, a door recessed between the windows with a
## transom over it, the sign band and the iron cornice over all; an
## awning let down over some; a light burning in each after dark.
static func _shops(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, w: float, n: int, iron: Color,
		signs: Array, awnings: Array) -> void:
	var ic := HarborTown.kc(iron, HarborTown.K_PAINT)
	var paint := HarborTown.kc(iron.lerp(Color(0.45, 0.38, 0.30), 0.35), HarborTown.K_PAINT)
	for k in n + 1:
		var x := -w / 2.0 + 0.25 + (w - 0.5) * k / n
		t.m.box("wall", base * HarborTown.at(Vector3(x, G / 2.0, 0.08)), Vector3(0.5, G, 0.26), ic)
		t.m.box("wall", base * HarborTown.at(Vector3(x, 0.2, 0.12)), Vector3(0.62, 0.4, 0.34), HarborTown.kc(STONE, HarborTown.K_GRANITE))
		t.m.box("wall", base * HarborTown.at(Vector3(x, G - 1.12, 0.12)), Vector3(0.62, 0.2, 0.32), ic)
	# The sign band and the storefront's cornice.
	t.m.box("wall", base * HarborTown.at(Vector3(0, G - 0.62, 0.05)), Vector3(w, 0.8, 0.14), ic)
	t.m.box("wall", base * HarborTown.at(Vector3(0, G - 0.12, 0.16)), Vector3(w + 0.2, 0.26, 0.4), ic)
	for k in n:
		var sx0 := -w / 2.0 + 0.5 + (w - 0.5) * k / n
		var sx1 := -w / 2.0 + (w - 0.5) * (k + 1) / n
		var mid := (sx0 + sx1) / 2.0
		var shop := rng.randf_range(0.12, 0.2)
		# The display windows either side of the door, each a box standing
		# out to the street line with its glass and kickplate.
		for e: float in [-1.0, 1.0]:
			var a := mid + e * 0.75
			var b := sx1 if e > 0.0 else sx0
			var lo := minf(a, b)
			var hi := maxf(a, b)
			t.m.box("wall", base * HarborTown.at(Vector3((lo + hi) / 2.0, (G - 1.0) / 2.0, -0.6)), Vector3(hi - lo, G - 1.0, 1.2), paint)
			t._solid(base * HarborTown.at(Vector3((lo + hi) / 2.0, G / 2.0, -0.6)), Vector3(hi - lo, G, 1.2))
			t.m.box("wall", base * HarborTown.at(Vector3((lo + hi) / 2.0, 0.3, 0.03)), Vector3(hi - lo, 0.6, 0.06), ic)
			t._pane(base, Vector3(lo + 0.05, 0.62, 0.005), Vector3(hi - 0.05, G - 1.1, 0.005),
				Color(shop, rng.randf(), 0.5, 0.6))
		# The recess: a tiled floor, the door and its transom at the back.
		t.m.box("wall", base * HarborTown.at(Vector3(mid, 0.02, -0.6)), Vector3(1.5, 0.04, 1.2),
			HarborTown.kc(Color(0.78, 0.76, 0.70), HarborTown.K_TILE))
		t.m.box("wall", base * HarborTown.at(Vector3(mid, 1.25, -1.17)), Vector3(1.2, 2.5, 0.06), paint)
		t._pane(base, Vector3(mid - 0.42, 1.0, -1.135), Vector3(mid + 0.42, 2.3, -1.135), Color(shop, rng.randf(), 0.5, 0.6))
		t._pane(base, Vector3(mid - 0.6, 2.6, -1.19), Vector3(mid + 0.6, G - 1.15, -1.19), Color(shop, rng.randf(), 0.5, 0.6))
		if k < signs.size() and str(signs[k]) != "":
			t._sign(base * HarborTown.at(Vector3(mid, G - 0.62, 0.13)), str(signs[k]), 88, Color(0.88, 0.74, 0.40))
		if k < awnings.size() and awnings[k] is Color:
			var canvas := HarborTown.kc(awnings[k] as Color, HarborTown.K_CLOTH)
			var tilt := Basis(Vector3.RIGHT, deg_to_rad(20.0))
			t.m.box("wall", base * Transform3D(tilt, Vector3(mid, G - 1.35, 0.85)), Vector3(sx1 - sx0 - 0.1, 0.04, 1.8), canvas, true)
			t.m.box("wall", base * HarborTown.at(Vector3(mid, G - 1.88, 1.68)), Vector3(sx1 - sx0 - 0.1, 0.3, 0.03), canvas, true)
		elif k < awnings.size():
			# Rolled up under the sign band.
			t.m.cylinder("wall", base * Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(mid, G - 1.12, 0.3)), 0.11, 0.11,
				sx1 - sx0 - 0.2, 8, HarborTown.kc(Color(0.45, 0.40, 0.34), HarborTown.K_CLOTH))
		var light := OmniLight3D.new()
		light.transform = base * HarborTown.at(Vector3(mid, 2.4, 1.3))
		light.omni_range = 7.0
		light.omni_attenuation = 1.2
		light.light_color = Color(1.0, 0.74, 0.46)
		light.shadow_enabled = false
		t.add_child(light)
		t.lamps.append({"light": light, "thr": shop, "energy": 0.9})


## A window in a masonry front at c: the sash (two over two) in its
## reveal, a granite sill, and over it a segmental hood of brick with a
## granite keystone, a round arch, or a flat granite lintel.
static func _opening(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, c: Vector3, ww: float, wh: float,
		style: String, face: Color, kind: int) -> void:
	var wall := HarborTown.kc(face, kind)
	var stone := HarborTown.kc(STONE, HarborTown.K_GRANITE)
	var thr := t._upstairs_threshold()
	var tone := rng.randf()
	var col := Color(thr, rng.randf(), 0.15, tone)
	t._pane(base, c + Vector3(-ww / 2.0, -wh / 2.0, 0.01), c + Vector3(ww / 2.0, wh / 2.0, 0.01), col)
	# The reveal: the jambs stand out round the glass so it sits deep.
	for e: float in [-1.0, 1.0]:
		t.m.box("wall", base * HarborTown.at(c + Vector3(e * (ww / 2.0 + 0.06), 0, 0.07)), Vector3(0.12, wh, 0.14), wall)
	t.m.box("wall", base * HarborTown.at(c + Vector3(0, -wh / 2.0 - 0.06, 0.1)), Vector3(ww + 0.34, 0.12, 0.2), stone)
	var top := c + Vector3(0, wh / 2.0, 0)
	match style:
		"flat":
			t.m.box("wall", base * HarborTown.at(top + Vector3(0, 0.15, 0.07)), Vector3(ww + 0.4, 0.3, 0.14), stone)
			t.m.box("wall", base * HarborTown.at(top + Vector3(0, 0.17, 0.12)), Vector3(0.22, 0.36, 0.12), stone)
		"round":
			# The arched head glazed as a fan over the sash.
			var r := ww / 2.0
			var n := 8
			for k in n:
				var a0 := PI * k / n
				var a1 := PI * (k + 1) / n
				var p0 := top + Vector3(cos(a0) * r, sin(a0) * r, 0.01)
				var p1 := top + Vector3(cos(a1) * r, sin(a1) * r, 0.01)
				var nrm := (base.basis * Vector3(0, 0, 1)).normalized()
				var uv := func(p: Vector3) -> Vector2:
					return Vector2((p.x - top.x + r) / (2.0 * r), 0.8 + 0.2 * (p.y - top.y) / r)
				t.m.quad("glass", base * (top + Vector3(0, 0, 0.01)), base * p1, base * p0, base * (top + Vector3(0, 0, 0.01)),
					nrm, Color(thr, col.g, 0.5, tone), uv.call(top), uv.call(p1), uv.call(p0), uv.call(top))
			_arc(t, base, top, r + 0.12, 0.0, PI, 9, 0.24, 0.12, wall.darkened(0.12))
			t.m.box("wall", base * HarborTown.at(top + Vector3(0, r + 0.14, 0.13)), Vector3(0.22, 0.34, 0.12), stone)
		_:
			var chord := ww + 0.36
			var rise := 0.26
			var r := (chord * chord / 4.0 + rise * rise) / (2.0 * rise)
			var half := asin(chord / 2.0 / r)
			var centre := top + Vector3(0, 0.06 + rise - r, 0)
			_arc(t, base, centre, r, PI / 2.0 - half, PI / 2.0 + half, 5, 0.22, 0.1, wall.darkened(0.12))
			t.m.box("wall", base * HarborTown.at(top + Vector3(0, rise + 0.08, 0.12)), Vector3(0.2, 0.32, 0.12), stone)
			# The brick filling the arch's head over the sash.
			t.m.box("wall", base * HarborTown.at(top + Vector3(0, rise / 2.0, 0.02)), Vector3(ww, rise, 0.04), wall)


## Voussoirs round an arc of radius r about centre, from angle a0 to a1,
## each thick across and standing proud of the face.
static func _arc(t: HarborTown, base: Transform3D, centre: Vector3, r: float, a0: float, a1: float, n: int, thick: float,
		proud: float, col: Color) -> void:
	var step := (a1 - a0) / n
	var seg := 2.0 * r * sin(step / 2.0) + 0.02
	for k in n:
		var a := a0 + step * (k + 0.5)
		var p := centre + Vector3(cos(a) * r, sin(a) * r, proud / 2.0)
		t.m.box("wall", base * Transform3D(Basis(Vector3.BACK, a - PI / 2.0), p), Vector3(seg, thick, proud), col)


## The cornice along a block's top: a frieze of corbelled brick, then a
## deep projecting cornice of pressed metal on paired brackets.
static func _cornice(t: HarborTown, base: Transform3D, w: float, h: float, col: Color, face: Color, kind: int) -> void:
	var c := HarborTown.kc(col, HarborTown.K_PAINT)
	t.m.box("wall", base * HarborTown.at(Vector3(0, h - 0.95, 0.04)), Vector3(w, 0.55, 0.08), HarborTown.kc(face.darkened(0.1), kind))
	t.m.box("wall", base * HarborTown.at(Vector3(0, h - 1.28, 0.08)), Vector3(w, 0.1, 0.16), HarborTown.kc(face.darkened(0.15), kind))
	t.m.box("wall", base * HarborTown.at(Vector3(0, h - 0.18, 0.38)), Vector3(w + 0.3, 0.36, 0.76), c, true)
	t.m.box("wall", base * HarborTown.at(Vector3(0, h - 0.42, 0.12)), Vector3(w, 0.12, 0.24), c)
	var n := maxi(int(w / 1.1), 2)
	for k in n + 1:
		var x := -w / 2.0 + 0.15 + (w - 0.3) * k / n
		for e: float in [-0.12, 0.12]:
			t.m.box("wall", base * HarborTown.at(Vector3(x + e, h - 0.68, 0.3)), Vector3(0.1, 0.52, 0.6), c)


## A mansard storey on a block's top: slate slopes steep on every side,
## a dormer to each bay, a flat deck over.
static func _mansard(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, w: float, depth: float, y: float,
		bays: int) -> void:
	var slate := HarborTown.kc(SLATE, HarborTown.K_ROOF)
	var rise := 3.1
	var inset := 0.9
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := 0.1
	var z1 := -depth
	var lo: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	var hi: Array[Vector3] = [Vector3(x0 + inset, y + rise, z0 - inset), Vector3(x1 - inset, y + rise, z0 - inset),
		Vector3(x1 - inset, y + rise, z1 + inset), Vector3(x0 + inset, y + rise, z1 + inset)]
	for k in 4:
		var j := (k + 1) % 4
		var n := ((lo[j] - lo[k]).cross(hi[k] - lo[k])).normalized()
		t.m.quad("wall", base * lo[k], base * hi[k], base * hi[j], base * lo[j], (base.basis * n).normalized(), slate)
	t.m.box("wall", base * HarborTown.at(Vector3(0, y + rise - 0.02, (z0 + z1) / 2.0)), Vector3(w - 2.0 * inset, 0.04, depth + 0.1 - 2.0 * inset),
		HarborTown.kc(Color(0.14, 0.14, 0.14), HarborTown.K_TAR))
	var trim := HarborTown.kc(HarborTown.TRIM, HarborTown.K_PAINT)
	for b in bays:
		var x := -w / 2.0 + w * (b + 0.5) / bays
		var d := base * HarborTown.at(Vector3(x, y + 1.35, 0.05))
		t.m.box("wall", d * HarborTown.at(Vector3(0, 0, -0.6)), Vector3(1.3, 2.1, 1.2), trim)
		t.m.prism("wall", d * HarborTown.at(Vector3(0, 1.05, -0.6)), 1.6, 0.55, 1.3, trim)
		t._pane(d, Vector3(-0.42, -0.75, 0.005), Vector3(0.42, 0.75, 0.005), Color(t._upstairs_threshold(), rng.randf(), 0.15, rng.randf()))


## A corner oriel: an eight-sided bay carried out from the first floor
## up past the cornice, windowed on its outer faces, under a slate cone.
static func _oriel(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, at: Vector3, floors: int, h: float,
		face: Color, kind: int) -> void:
	var r := 1.15
	var wall := HarborTown.kc(face, kind)
	var c := base * HarborTown.at(at + Vector3(0, 0, 0.35))
	var y0 := G + 0.2
	var y1 := h + 0.9
	t.m.cylinder("wall", c * HarborTown.at(Vector3(0, y0 - 0.5, 0)), 0.3, r, 1.0, 8, wall)
	t.m.cylinder("wall", c * HarborTown.at(Vector3(0, (y0 + y1) / 2.0, 0)), r, r, y1 - y0, 8, wall)
	t.m.cylinder("wall", c * HarborTown.at(Vector3(0, y1 + 0.1, 0)), r + 0.2, r + 0.2, 0.2, 8, HarborTown.kc(CORNICES[0], HarborTown.K_PAINT))
	t.m.cylinder("wall", c * HarborTown.at(Vector3(0, y1 + 1.4, 0)), r + 0.15, 0.0, 2.4, 8, HarborTown.kc(SLATE, HarborTown.K_ROOF))
	t.m.sphere("iron", c * HarborTown.at(Vector3(0, y1 + 2.7, 0)), 0.1, 8, HarborTown.IRON)
	# Windows on the five faces toward the street and the corner.
	for f in range(1, floors):
		var y := G + U * (f - 1) + 0.55 + 1.0 + (0.4 if f == 1 else 0.0)
		for j in 8:
			var a := TAU * (j + 0.5) / 8.0
			var out := Vector3(cos(a), 0, sin(a))
			if out.z < -0.3:
				continue
			var yaw := atan2(out.x, out.z)
			var fx := c * Transform3D(Basis(Vector3.UP, yaw), out * (r * cos(PI / 8.0) + 0.01) + Vector3(0, y, 0))
			t._pane(fx, Vector3(-0.3, -0.9, 0), Vector3(0.3, 0.9, 0), Color(t._upstairs_threshold(), rng.randf(), 0.15, rng.randf()))
	t._solid(c * HarborTown.at(Vector3(0, (y0 + y1) / 2.0, 0)), Vector3(r * 1.8, y1 - y0, r * 1.8))


## A savings bank's front in granite: a round-arched doorway up two
## steps between tall arched windows, its name cut in the frieze.
static func _bank_front(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, w: float) -> void:
	var stone := HarborTown.kc(STONE, HarborTown.K_GRANITE)
	for k in 2:
		t.m.box("wall", base * HarborTown.at(Vector3(0, 0.1 + 0.2 * k, 0.55 - 0.3 * k)), Vector3(3.2 - 0.4 * k, 0.2, 0.9), stone)
	t.m.box("wall", base * HarborTown.at(Vector3(0, 1.8, 0.03)), Vector3(1.6, 3.2, 0.06), HarborTown.kc(Color(0.22, 0.15, 0.09), HarborTown.K_WOOD))
	_arc(t, base, Vector3(0, 3.4, 0), 1.05, 0.0, PI, 11, 0.36, 0.14, stone)
	t._pane(base, Vector3(-0.8, 3.4, 0.01), Vector3(0.8, 4.1, 0.01), Color(0.3, 0.2, 0.5, 0.7))
	for e: float in [-1.0, 1.0]:
		_opening(t, rng, base, Vector3(e * (w / 2.0 - 1.9), 2.3, 0.0), 1.2, 2.6, "round", STONE, HarborTown.K_GRANITE)
	t._sign(base * HarborTown.at(Vector3(0, G - 0.3, 0.1)), "SAVINGS BANK", 80, Color(0.2, 0.2, 0.2))


## A hotel's front: a lobby of plate glass and a double door, and a porch
## of two storeys across it, turned columns and a railed gallery above.
static func _hotel_front(t: HarborTown, rng: RandomNumberGenerator, base: Transform3D, w: float, porch: float, iron: Color,
		s: Dictionary) -> void:
	var trim := HarborTown.kc(HarborTown.TRIM, HarborTown.K_PAINT)
	var deck := HarborTown.kc(Color(0.42, 0.40, 0.36), HarborTown.K_PLANK)
	var lobby := rng.randf_range(0.1, 0.16)
	for e: float in [-1.0, 1.0]:
		t._pane(base, Vector3(e * 1.2, 0.7, 0.01), Vector3(e * (w / 2.0 - 0.6), G - 1.0, 0.01), Color(lobby, rng.randf(), 0.5, 0.8))
	t.m.box("wall", base * HarborTown.at(Vector3(0, 1.4, 0.03)), Vector3(2.0, 2.8, 0.06), HarborTown.kc(Color(0.25, 0.12, 0.08), HarborTown.K_WOOD))
	t._pane(base, Vector3(-0.8, 1.0, 0.07), Vector3(0.8, 2.6, 0.07), Color(lobby, rng.randf(), 0.5, 0.8))
	var signs: Array = s.get("signs", [])
	# The porch floor, a step up from the walk; the gallery floor and the
	# porch roof; the columns every bay, a rail between them above.
	t.m.box("wall", base * HarborTown.at(Vector3(0, 0.1, porch / 2.0)), Vector3(w, 0.2, porch), deck)
	t.m.box("wall", base * HarborTown.at(Vector3(0, G, porch / 2.0)), Vector3(w, 0.25, porch), trim, true)
	t.m.box("wall", base * HarborTown.at(Vector3(0, G + U - 0.2, porch / 2.0 + 0.1)), Vector3(w + 0.2, 0.25, porch + 0.2), trim, true)
	var n := int(w / 2.4)
	for k in n + 1:
		var x := -w / 2.0 + 0.2 + (w - 0.4) * k / n
		var p := Vector3(x, 0, porch - 0.2)
		t.m.cylinder("wall", base * HarborTown.at(p + Vector3(0, G / 2.0 + 0.1, 0)), 0.14, 0.12, G - 0.2, 10, trim)
		t.m.cylinder("wall", base * HarborTown.at(p + Vector3(0, G + U / 2.0, 0)), 0.12, 0.1, U - 0.4, 10, trim)
		t._solid(base * HarborTown.at(p + Vector3(0, G / 2.0, 0)), Vector3(0.28, G, 0.28))
	t.m.box("wall", base * HarborTown.at(Vector3(0, G + 0.95, porch - 0.2)), Vector3(w, 0.08, 0.1), trim)
	var spindles := int(w / 0.14)
	for k in spindles:
		var x := -w / 2.0 + (k + 0.5) * w / spindles
		t.m.box("wall", base * HarborTown.at(Vector3(x, G + 0.55, porch - 0.2)), Vector3(0.035, 0.75, 0.035), trim)
	if signs.size() > 0:
		t._sign(base * HarborTown.at(Vector3(0, G + 0.55, porch - 0.13)), str(signs[0]), 110, Color(0.25, 0.1, 0.06))
	var light := OmniLight3D.new()
	light.transform = base * HarborTown.at(Vector3(0, G - 0.4, porch / 2.0))
	light.omni_range = 8.0
	light.light_color = HarborTown.LAMP_COLOR
	light.shadow_enabled = false
	t.add_child(light)
	t.lamps.append({"light": light, "thr": lobby, "energy": 1.2})


## ---- the city hall ----------------------------------------------------------

## A city hall of brick with granite trim, three storeys, a tower rising
## from the middle of its front: an arched doorway at its foot, a clock
## on each face, a belfry open on every side, a copper roof.
static func _city_hall(t: HarborTown, rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var base := _frame(t, x0, x1, -1)
	var w := x1 - x0
	var depth := 8.0
	var face := Color(0.55, 0.27, 0.19)
	var wall := HarborTown.kc(face, HarborTown.K_BRICK)
	var stone := HarborTown.kc(STONE, HarborTown.K_GRANITE)
	var g := 4.2
	var u := 3.8
	var h := g + u * 2.0 + 1.3
	t.m.box("wall", base * HarborTown.at(Vector3(0, (h - 1.2) / 2.0, -depth / 2.0)), Vector3(w, h + 1.2, depth), wall)
	t._solid(base * HarborTown.at(Vector3(0, h / 2.0, -depth / 2.0)), Vector3(w, h, depth))
	t.m.box("wall", base * HarborTown.at(Vector3(0, 0.6, 0.06)), Vector3(w, 1.2, 0.12), stone)
	for k in 2:
		t.m.box("wall", base * HarborTown.at(Vector3(0, g + u * k - 0.1, 0.05)), Vector3(w, 0.22, 0.1), stone)
	t.m.box("wall", base * HarborTown.at(Vector3(0, h + 0.02, -depth / 2.0)), Vector3(w - 0.6, 0.04, depth - 0.6),
		HarborTown.kc(Color(0.14, 0.14, 0.14), HarborTown.K_TAR))
	_cornice(t, base, w, h, Color(0.30, 0.28, 0.25), face, HarborTown.K_BRICK)
	for f in 3:
		var y := (g * 0.5 + 0.3) if f == 0 else (g + u * (f - 1) + 0.5 + 1.1)
		for x: float in [-6.8, -4.6, 4.6, 6.8]:
			_opening(t, rng, base, Vector3(x, y, 0.0), 1.05, 2.2 if f < 2 else 2.0, "flat" if f == 0 else "segment", face,
				HarborTown.K_BRICK)
	# The tower: out a little from the front, 4.4 m square, to the belfry.
	var tw := 4.4
	var tz := -1.6
	var top := 21.5
	t.m.box("wall", base * HarborTown.at(Vector3(0, (top - 1.2) / 2.0, tz)), Vector3(tw, top + 1.2, tw), wall)
	t._solid(base * HarborTown.at(Vector3(0, top / 2.0, tz)), Vector3(tw, top, tw))
	for y: float in [h - 0.3, 17.0, top - 0.2]:
		t.m.box("wall", base * HarborTown.at(Vector3(0, y, tz)), Vector3(tw + 0.3, 0.3, tw + 0.3), stone)
	# The doorway: granite steps, an arch of voussoirs, oak doors, a
	# fanlight lit when the hall is.
	for k in 3:
		t.m.box("wall", base * HarborTown.at(Vector3(0, 0.1 + 0.2 * k, 1.1 - 0.3 * k)), Vector3(3.4 - 0.3 * k, 0.2, 0.8), stone)
	var fz := tz + tw / 2.0
	t.m.box("wall", base * HarborTown.at(Vector3(0, 1.85, fz + 0.03)), Vector3(1.8, 3.1, 0.06), HarborTown.kc(Color(0.30, 0.18, 0.10), HarborTown.K_WOOD))
	_arc(t, base, Vector3(0, 3.4, fz), 1.15, 0.0, PI, 11, 0.4, 0.16, stone)
	t._pane(base, Vector3(-0.9, 3.4, fz + 0.02), Vector3(0.9, 4.2, fz + 0.02), Color(0.35, 0.3, 0.5, 0.7))
	var tbase := base * HarborTown.at(Vector3(0, 0, fz))
	for y: float in [g + 1.6, g + u + 1.5]:
		_opening(t, rng, tbase, Vector3(0, y, 0), 1.1, 2.2, "round", face, HarborTown.K_BRICK)
	# The clock stage: a dial on each face, lit from within at dusk.
	for j in 4:
		var yaw := PI / 2.0 * j
		var fx := base * HarborTown.at(Vector3(0, 0, tz)) * HarborTown.at(Vector3.ZERO, yaw) * HarborTown.at(Vector3(0, 0, tw / 2.0))
		t.m.cylinder("wall", fx * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 15.4, 0.06)), 1.25, 1.25, 0.12, 24,
			HarborTown.kc(STONE, HarborTown.K_GRANITE))
		t.m.cylinder("lamp", fx * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 15.4, 0.13)), 1.05, 1.05, 0.04, 24,
			Color(0.3, 0, 0, 1))
		t.add_clock(fx * HarborTown.at(Vector3(0, 15.4, 0.17)))
	# The belfry: an arched opening on each face, dark within.
	for j in 4:
		var yaw := PI / 2.0 * j
		var fx := base * HarborTown.at(Vector3(0, 0, tz)) * HarborTown.at(Vector3.ZERO, yaw) * HarborTown.at(Vector3(0, 0, tw / 2.0))
		t.m.box("wall", fx * HarborTown.at(Vector3(0, 19.0, 0.01)), Vector3(1.6, 2.6, 0.02), HarborTown.kc(Color(0.05, 0.05, 0.05), HarborTown.K_PAINT))
		_arc(t, fx, Vector3(0, 20.3, 0), 0.85, 0.0, PI, 9, 0.24, 0.1, stone)
	# The roof: a copper pyramid, a lantern, a vane.
	var roof := base * HarborTown.at(Vector3(0, top + 2.2, tz)) * HarborTown.at(Vector3.ZERO, PI / 4.0)
	t.m.cylinder("wall", roof, (tw + 0.6) * 0.7071, 0.0, 4.4, 4, HarborTown.kc(COPPER, HarborTown.K_PAINT))
	t.m.bar("iron", base * Vector3(0, top + 4.2, tz), base * Vector3(0, top + 6.0, tz), 0.04, 6, HarborTown.IRON)
	t.m.box("iron", base * HarborTown.at(Vector3(0.25, top + 5.7, tz)), Vector3(0.9, 0.3, 0.03), HarborTown.IRON)
	t._sign(base * HarborTown.at(Vector3(0, h - 0.95, 0.1)), "CITY HALL", 80, Color(0.86, 0.80, 0.62))
	var light := OmniLight3D.new()
	light.transform = base * HarborTown.at(Vector3(0, 3.0, fz + 1.2))
	light.omni_range = 8.0
	light.light_color = HarborTown.LAMP_COLOR
	light.shadow_enabled = false
	t.add_child(light)
	t.lamps.append({"light": light, "delay": 0.3, "energy": 1.4})


## ---- the library -----------------------------------------------------------

## A library in granite: two tall storeys, a pavilion out from the middle
## round an arched door up three steps, round-arched windows below and
## paired ones above, a bracketed cornice, a low hipped roof.
static func _library(t: HarborTown, rng: RandomNumberGenerator, x0: float, x1: float) -> void:
	var base := _frame(t, x0, x1, -1, 1.5)
	var w := x1 - x0
	var depth := 9.0
	var face := Color(0.64, 0.63, 0.60)
	var wall := HarborTown.kc(face, HarborTown.K_GRANITE)
	var g := 4.8
	var h := g + 4.2 + 1.2
	t.m.box("wall", base * HarborTown.at(Vector3(0, (h - 1.2) / 2.0, -depth / 2.0)), Vector3(w, h + 1.2, depth), wall)
	t._solid(base * HarborTown.at(Vector3(0, h / 2.0, -depth / 2.0)), Vector3(w, h, depth))
	t.m.box("wall", base * HarborTown.at(Vector3(0, (h + 0.2) / 2.0 - 0.6, 0.3)), Vector3(4.0, h + 1.4, 0.6), wall)
	_cornice(t, base, w, h, Color(0.60, 0.59, 0.56), face, HarborTown.K_GRANITE)
	t.m.box("wall", base * HarborTown.at(Vector3(0, g, 0.08)), Vector3(w, 0.25, 0.16), wall)
	var roof := base * HarborTown.at(Vector3(0, h + 1.0, -depth / 2.0)) * Transform3D(Basis.from_scale(Vector3(w / depth, 1, 1))
		* Basis(Vector3.UP, PI / 4.0), Vector3.ZERO)
	t.m.cylinder("wall", roof, depth * 0.7071, 0.0, 2.0, 4, HarborTown.kc(SLATE, HarborTown.K_ROOF))
	for k in 3:
		t.m.box("wall", base * HarborTown.at(Vector3(0, 0.1 + 0.2 * k, 1.6 - 0.35 * k)), Vector3(3.6 - 0.3 * k, 0.2, 0.8),
			HarborTown.kc(STONE, HarborTown.K_GRANITE))
	t.m.box("wall", base * HarborTown.at(Vector3(0, 1.75, 0.63)), Vector3(1.6, 2.9, 0.06), HarborTown.kc(Color(0.26, 0.16, 0.09), HarborTown.K_WOOD))
	_arc(t, base, Vector3(0, 3.2, 0.6), 1.0, 0.0, PI, 11, 0.34, 0.12, wall.darkened(0.08))
	t._pane(base, Vector3(-0.8, 3.2, 0.62), Vector3(0.8, 4.0, 0.62), Color(0.3, 0.3, 0.5, 0.7))
	var pav := base * HarborTown.at(Vector3(0, 0, 0.6))
	_opening(t, rng, pav, Vector3(0, g + 1.9, 0), 1.2, 2.2, "round", face, HarborTown.K_GRANITE)
	for x: float in [-4.6, -3.0, 3.0, 4.6]:
		_opening(t, rng, base, Vector3(x, 2.4, 0.0), 1.1, 2.6, "round", face, HarborTown.K_GRANITE)
		_opening(t, rng, base, Vector3(x, g + 1.9, 0.0), 0.9, 2.1, "flat", face, HarborTown.K_GRANITE)
	t._sign(base * HarborTown.at(Vector3(0, h - 0.95, 0.68)), "PUBLIC LIBRARY", 64, Color(0.22, 0.22, 0.22))


## ---- the domed hall -------------------------------------------------------

## A granite hall on its lawn at the head of Main Street, facing down the
## street: a rusticated base, a portico of six Doric columns under a
## pediment, a wing either side, and over the middle a drum ringed with
## pilasters and windows carrying a gilded dome, a lantern and a figure
## on its crown. A granite walk comes up the lawn to the steps between
## two lamps.
static func _domed_hall(t: HarborTown, rng: RandomNumberGenerator) -> void:
	var y := t.coast.civic_y
	var front_x := TownCoast.CIVIC.x - TownCoast.CIVIC_HALF.x + 2.6
	var base := HarborTown.at(Vector3(front_x, y, TownCoast.MAIN_Z), -PI / 2.0)
	var face := Color(0.70, 0.69, 0.66)
	var stone := HarborTown.kc(face, HarborTown.K_GRANITE)
	var light_stone := HarborTown.kc(Color(0.78, 0.77, 0.74), HarborTown.K_GRANITE)
	var paint := HarborTown.kc(Color(0.84, 0.83, 0.79), HarborTown.K_PAINT)
	var pod := 1.8
	# Steps from the lawn to the portico's floor.
	for k in 6:
		t.m.box("wall", base * HarborTown.at(Vector3(0, pod * (k + 0.5) / 6.0 - 0.1, 2.4 - 0.4 * k - 0.2)),
			Vector3(14.0, pod / 6.0 + 0.2, 0.4), light_stone)
	var ramp := base * Transform3D(Basis(Vector3.RIGHT, atan2(pod, 2.4)), Vector3(0, pod / 2.0 - 0.15, 1.2))
	t._solid(ramp, Vector3(14.0, 0.3, sqrt(pod * pod + 2.4 * 2.4)))
	# The portico: its floor, the columns, the entablature, the pediment.
	t.m.box("wall", base * HarborTown.at(Vector3(0, pod / 2.0 - 0.6, -2.0)), Vector3(14.0, pod + 1.2, 4.0), stone)
	t._solid(base * HarborTown.at(Vector3(0, pod / 2.0, -2.0)), Vector3(14.0, pod, 4.0))
	var col_h := 8.0
	for k in 6:
		var x := -5.5 + 2.2 * k
		t.m.cylinder("wall", base * HarborTown.at(Vector3(x, pod + col_h / 2.0, -0.8)), 0.52, 0.44, col_h, 16, light_stone)
		t.m.box("wall", base * HarborTown.at(Vector3(x, pod + col_h - 0.15, -0.8)), Vector3(1.2, 0.3, 1.2), light_stone)
		t.m.box("wall", base * HarborTown.at(Vector3(x, pod + 0.12, -0.8)), Vector3(1.2, 0.24, 1.2), light_stone)
		t._solid(base * HarborTown.at(Vector3(x, pod + col_h / 2.0, -0.8)), Vector3(0.9, col_h, 0.9))
	var ent := pod + col_h
	t.m.box("wall", base * HarborTown.at(Vector3(0, ent + 0.7, -2.2)), Vector3(13.4, 1.4, 4.6), light_stone, true)
	t.m.box("wall", base * HarborTown.at(Vector3(0, ent + 1.5, -2.2)), Vector3(13.8, 0.2, 5.0), light_stone)
	t.m.prism("wall", base * HarborTown.at(Vector3(0, ent + 1.6, -2.2)), 13.8, 2.5, 5.0, light_stone)
	# The middle block behind the portico and a wing either side.
	var body_h := ent + 1.6
	t.m.box("wall", base * HarborTown.at(Vector3(0, body_h / 2.0 - 0.6, -12.0)), Vector3(22.0, body_h + 1.2, 16.0), stone)
	t._solid(base * HarborTown.at(Vector3(0, body_h / 2.0, -12.0)), Vector3(22.0, body_h, 16.0))
	t.m.box("wall", base * HarborTown.at(Vector3(0, body_h - 0.2, -12.0)), Vector3(22.6, 0.5, 16.6), light_stone)
	var wing_h := body_h - 1.8
	for e: float in [-1.0, 1.0]:
		var wc := Vector3(e * 17.5, 0, -12.0)
		t.m.box("wall", base * HarborTown.at(wc + Vector3(0, wing_h / 2.0 - 0.6, 0)), Vector3(13.0, wing_h + 1.2, 13.0), stone)
		t._solid(base * HarborTown.at(wc + Vector3(0, wing_h / 2.0, 0)), Vector3(13.0, wing_h, 13.0))
		t.m.box("wall", base * HarborTown.at(wc + Vector3(0, wing_h - 0.2, 0)), Vector3(13.6, 0.5, 13.6), light_stone)
		t.m.box("wall", base * HarborTown.at(wc + Vector3(0, pod - 0.1, 0)), Vector3(13.2, 0.25, 13.2), light_stone)
		# The wing's front: tall windows over the base, shorter above.
		var wf := base * HarborTown.at(Vector3(e * 17.5, 0, -5.5))
		for k in 4:
			var x := -4.8 + 3.2 * k
			_opening(t, rng, wf, Vector3(x, 0.9, 0), 0.8, 0.9, "flat", face, HarborTown.K_GRANITE)
			_opening(t, rng, wf, Vector3(x, pod + 2.6, 0), 1.3, 3.2, "round", face, HarborTown.K_GRANITE)
			_opening(t, rng, wf, Vector3(x, pod + 6.6, 0), 1.2, 2.2, "flat", face, HarborTown.K_GRANITE)
	# The middle block's front behind the columns: doors and windows.
	var mf := base * HarborTown.at(Vector3(0, 0, -4.0))
	t.m.box("wall", mf * HarborTown.at(Vector3(0, pod + 1.9, 0.03)), Vector3(2.2, 3.8, 0.06), HarborTown.kc(Color(0.24, 0.15, 0.08), HarborTown.K_WOOD))
	t._pane(mf, Vector3(-1.0, pod + 4.0, 0.02), Vector3(1.0, pod + 4.9, 0.02), Color(0.2, 0.3, 0.5, 0.7))
	for x: float in [-3.3, 3.3]:
		_opening(t, rng, mf, Vector3(x, pod + 2.6, 0), 1.3, 3.2, "round", face, HarborTown.K_GRANITE)
		_opening(t, rng, mf, Vector3(x, pod + 6.6, 0), 1.2, 2.2, "flat", face, HarborTown.K_GRANITE)
	# The drum on a square base, standing clear of the pediment, ringed
	# with pilasters and windows; the dome, gilded, over it; the lantern
	# and the figure on its crown.
	var dc := base * HarborTown.at(Vector3(0, body_h, -12.0))
	var db := 3.4
	var dh := 5.6
	t.m.box("wall", dc * HarborTown.at(Vector3(0, db / 2.0, 0)), Vector3(11.0, db, 11.0), stone)
	t.m.box("wall", dc * HarborTown.at(Vector3(0, db + 0.1, 0)), Vector3(11.4, 0.25, 11.4), light_stone)
	t.m.cylinder("wall", dc * HarborTown.at(Vector3(0, db + dh / 2.0, 0)), 4.3, 4.3, dh, 32, paint)
	t.m.cylinder("wall", dc * HarborTown.at(Vector3(0, db + dh + 0.2, 0)), 4.75, 4.75, 0.4, 32, paint)
	for k in 16:
		var a := TAU * k / 16.0
		var out := Vector3(cos(a), 0, sin(a))
		t.m.cylinder("wall", dc * HarborTown.at(out * 4.45 + Vector3(0, db + dh / 2.0, 0)), 0.2, 0.18, dh, 8, paint)
		var wa := a + TAU / 32.0
		var wo := Vector3(cos(wa), 0, sin(wa))
		var fx := dc * Transform3D(Basis(Vector3.UP, atan2(wo.x, wo.z)), wo * 4.32 + Vector3(0, db + dh / 2.0, 0))
		t._pane(fx, Vector3(-0.35, -1.4, 0), Vector3(0.35, 1.4, 0), Color(rng.randf_range(0.4, 1.0), rng.randf(), 0.15, rng.randf()))
	var dy := db + dh + 0.4
	t.m.sphere("gold", dc * Transform3D(Basis.from_scale(Vector3(1.0, 1.2, 1.0)), Vector3(0, dy, 0)), 4.4, 28, GOLD)
	var ly := dy + 5.8
	t.m.cylinder("wall", dc * HarborTown.at(Vector3(0, ly, 0)), 0.85, 0.85, 1.6, 12, paint)
	for k in 8:
		var a := TAU * k / 8.0
		t.m.box("wall", dc * HarborTown.at(Vector3(cos(a) * 0.86, ly, sin(a) * 0.86)), Vector3(0.2, 1.0, 0.2),
			HarborTown.kc(Color(0.08, 0.08, 0.08), HarborTown.K_PAINT))
	t.m.sphere("gold", dc * Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), Vector3(0, ly + 0.8, 0)), 0.95, 16, GOLD)
	var figure := HarborTown.kc(Color(0.62, 0.56, 0.46), HarborTown.K_PAINT)
	t.m.cylinder("wall", dc * HarborTown.at(Vector3(0, ly + 2.4, 0)), 0.34, 0.2, 1.9, 10, figure)
	t.m.sphere("wall", dc * HarborTown.at(Vector3(0, ly + 3.55, 0)), 0.2, 10, figure)
	t.m.bar("wall", dc * Vector3(0.15, ly + 3.0, 0), dc * Vector3(0.35, ly + 4.0, 0.25), 0.07, 6, figure)
	# The walk up the lawn from the street's end, and a lamp either side
	# of its foot.
	var from := Vector2(TownCoast.CIVIC.x - TownCoast.CIVIC_HALF.x - 9.5, TownCoast.MAIN_Z)
	var to := Vector2(front_x - 2.4, TownCoast.MAIN_Z)
	var n := int(from.distance_to(to))
	for k in n:
		var a := from.lerp(to, float(k) / n)
		var b := from.lerp(to, float(k + 1) / n)
		var ya := t.coast.height_at(a.x, a.y)
		var yb := t.coast.height_at(b.x, b.y)
		var slope := Basis(Vector3.BACK, atan2(yb - ya, b.x - a.x))
		t.m.box("wall", Transform3D(slope, Vector3((a.x + b.x) / 2.0, (ya + yb) / 2.0, a.y)), Vector3(b.x - a.x + 0.05, 0.1, 3.2),
			HarborTown.kc(STONE, HarborTown.K_GRANITE))
	for e: float in [-1.0, 1.0]:
		var p := Vector2(to.x - 1.5, TownCoast.MAIN_Z + e * 2.4)
		t._iron_post(Vector3(p.x, t.coast.height_at(p.x, p.y), p.y))
