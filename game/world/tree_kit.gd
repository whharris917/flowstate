class_name TreeKit
extends RefCounted
## Trees with leaves: meshes of a few kinds and variants, built once a
## run and shared by every forest that asks for detail. A broadleaf
## (maple, or an elm's tall vase) is a trunk dividing into limbs and
## those into branches, each a tapered cylinder, with clusters of
## leaves as crossed cards at the twigs' ends. A spruce is a tapering
## trunk ringed with whorls of boughs, each a pair of needle cards
## drooping from it, longer toward the ground, and a leader at the top.
## The leaf and needle pictures are drawn here, once, into textures.
##
## Every mesh stands REF_H tall from its foot at the origin: an
## instance scales it to its own height. Two surfaces: bark, then
## foliage, both in foliage.gdshader so the whole tree sways as one.

const REF_H := 12.0
const VARIANTS := 2

static var _meshes: Dictionary = {}          # "maple0" etc -> ArrayMesh
static var _leaf_mat: ShaderMaterial = null
static var _needle_mat: ShaderMaterial = null
static var _bark_mat: ShaderMaterial = null


## A tree or a plant of kind and variant, built on first asking:
## "maple", "elm", "oak", "birch" (a clump of white stems), "spruce",
## "pine" (a white pine, tiers of tufted boughs), "shrub" (a lilac or
## a burning bush), "hydrangea" (a shrub in flower gone papery),
## "hedge" (a metre of clipped yew, instanced in a row, stretched).
static func mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "%s%d" % [kind, variant]
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key) + 1947
		match kind:
			"spruce":
				_meshes[key] = _spruce(rng)
			"pine":
				_meshes[key] = _pine(rng)
			"birch":
				_meshes[key] = _birch(rng)
			"oak":
				_meshes[key] = _oak(rng)
			"shrub":
				_meshes[key] = _shrub(rng, false)
			"hydrangea":
				_meshes[key] = _shrub(rng, true)
			"hedge":
				_meshes[key] = _hedge(rng)
			_:
				_meshes[key] = _broadleaf(rng, kind == "elm")
	return _meshes[key]


## The materials every detailed tree shares; the weather sets their wind.
static func materials() -> Array[ShaderMaterial]:
	_ensure_materials()
	return [_bark_mat, _leaf_mat, _needle_mat]


static func _ensure_materials() -> void:
	if _bark_mat != null:
		return
	var shader := load("res://world/foliage.gdshader") as Shader
	_bark_mat = ShaderMaterial.new()
	_bark_mat.shader = shader
	_bark_mat.set_shader_parameter("bark", true)
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = shader
	_leaf_mat.set_shader_parameter("leaves", _leaf_texture())
	_leaf_mat.set_shader_parameter("tex_size", 512.0)
	_needle_mat = ShaderMaterial.new()
	_needle_mat.shader = shader
	_needle_mat.set_shader_parameter("leaves", _needle_texture())
	_needle_mat.set_shader_parameter("tex_size", 256.0)


## ---- the pictures -------------------------------------------------------------

## Four clumps of leaves in the four quarters of the picture, as a
## spray of a real tree shows against the sky: a ragged outline, no two
## alike, a few twigs running out through it, the leaves (lobed like a
## maple's or plain) scattered at their own turns and sizes, the inner
## ones darker and overlapped by the outer, gaps of sky between. Pale,
## so the tree's own colour tints them. A card shows one quarter.
static func _leaf_texture() -> ImageTexture:
	var n := 512
	var cell := n / 2
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.35, 0.3, 0.22, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for q in 4:
		var c := Vector2((q % 2) * cell + cell / 2.0, (q / 2) * cell + cell / 2.0)
		var ph: Array[float] = [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
		var reach := func(a: float) -> float:
			return cell * 0.44 * (0.74 + 0.13 * sin(3.0 * a + ph[0]) + 0.09 * sin(5.0 * a + ph[1]) + 0.05 * sin(9.0 * a + ph[2]))
		# Twigs from the heart outward, thin, mostly hidden.
		for t in 6:
			var a := TAU * t / 6.0 + rng.randf_range(-0.4, 0.4)
			var from := c + Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 12.0)
			var to := c + Vector2(cos(a), sin(a)) * float(reach.call(a)) * 0.85
			_line(img, from, to, 0.9, Color(0.26, 0.2, 0.15, 1.0))
		# Leaves, heart first, so the outer ones lie over the inner.
		var spots: Array = []
		for k in 170:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * float(reach.call(a))
			spots.append([r / cell, a, r])
		spots.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		for spot: Array in spots:
			var a: float = spot[1]
			var r: float = spot[2]
			var at := c + Vector2(cos(a), sin(a)) * r
			var la := a + rng.randf_range(-1.3, 1.3)
			var size := rng.randf_range(11.0, 18.0)
			var depth := clampf(r / (cell * 0.4), 0.0, 1.0)
			var tone := Color(rng.randf_range(0.8, 1.0), rng.randf_range(0.9, 1.0), rng.randf_range(0.6, 0.85)) \
				* rng.randf_range(0.7, 0.95) * lerpf(0.72, 1.05, depth)
			_leaf_shape(img, at - Vector2(cos(la), sin(la)) * size * 0.4, Vector2(cos(la), sin(la)), size, rng.randf() < 0.6, tone, 0.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## One leaf from its stalk's end at base along dir: lobed (a maple's
## five points) or plain (an oval with a point), size long, tone its
## colour, darker along the midrib, paler toward the tip.
static func _leaf_shape(img: Image, base: Vector2, dir: Vector2, size: float, lobed: bool, tone: Color, _spin: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var centre := base + dir * size * 0.5
	var r := size * 0.62
	for y in range(maxi(int(centre.y - r), 0), mini(int(centre.y + r) + 1, img.get_height())):
		for x in range(maxi(int(centre.x - r), 0), mini(int(centre.x + r) + 1, img.get_width())):
			var q := Vector2(x, y) - centre
			var u := q.dot(dir) / (size * 0.5)
			var v := q.dot(side) / (size * 0.5)
			var inside: bool
			if lobed:
				var ang := atan2(v, u)
				var rad := sqrt(u * u + v * v)
				var edge := 0.62 + 0.38 * pow(absf(cos(ang * 2.5)), 0.6)
				inside = rad < edge and not (u < -0.55 and absf(v) < 0.15)
			else:
				inside = (u * u) / 1.0 + (v * v) / 0.32 < 1.0 - 0.25 * maxf(u, 0.0)
			if not inside:
				continue
			var rib := 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.08, absf(v)))
			var light := rib * (0.88 + 0.14 * (u + 1.0) * 0.5)
			img.set_pixel(x, y, Color(tone.r * light, tone.g * light, tone.b * light, 1.0))


## A spruce twig with its needles, base at the bottom of the picture,
## tip at the top: a brown twig, side shoots, needles all round them
## drawn as short strokes, the silhouette tapering to the tip.
static func _needle_texture() -> ImageTexture:
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.25, 0.18, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var shoots: Array = [[Vector2(w / 2.0, h - 2.0), Vector2(w / 2.0, 6.0), 1.0]]
	for k in 7:
		var t := 0.15 + 0.11 * k
		var from := Vector2(w / 2.0, h - 2.0 - t * (h - 8.0))
		var s := -1.0 if k % 2 == 0 else 1.0
		var reach := (1.0 - t) * w * 0.42 + 14.0
		shoots.append([from, from + Vector2(s * reach, -reach * 0.55), 0.6])
	for shoot: Array in shoots:
		var a: Vector2 = shoot[0]
		var b: Vector2 = shoot[1]
		_line(img, a, b, 1.6 * float(shoot[2]), Color(0.32, 0.24, 0.16, 1.0))
		var along := (b - a).normalized()
		var side := Vector2(-along.y, along.x)
		var count := int(a.distance_to(b) / 2.2)
		for j in count:
			var t := float(j) / count
			var p := a.lerp(b, t)
			for s: float in [-1.0, 1.0]:
				var nl := lerpf(15.0, 7.0, t) * float(shoot[2]) * rng.randf_range(0.8, 1.2) + 3.0
				var d := (along * 0.75 + side * s * rng.randf_range(0.6, 1.1)).normalized()
				var g := rng.randf_range(0.55, 0.95)
				_line(img, p, p + d * nl, 1.0, Color(g, g, g, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _line(img: Image, a: Vector2, b: Vector2, r: float, col: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for dy in range(-int(ceil(r)), int(ceil(r)) + 1):
			for dx in range(-int(ceil(r)), int(ceil(r)) + 1):
				if dx * dx + dy * dy > r * r + 0.5:
					continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)


## ---- the trees -------------------------------------------------------------------

## A tapered limb from a to b, radius ra to rb, into the bark surface.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color) -> void:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := x * cos(a0) + z * sin(a0)
		var d1 := x * cos(a1) + z * sin(a1)
		var p00 := a + d0 * ra
		var p01 := a + d1 * ra
		var p10 := b + d0 * rb
		var p11 := b + d1 * rb
		for v: Array in [[p00, d0], [p10, d0], [p11, d1], [p00, d0], [p11, d1], [p01, d1]]:
			st.set_color(col)
			st.set_normal(v[1])
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[0])


## A card: a quad centred at c spanning u and v (half extents), UV over
## it, its normal n (bent outward from the crown for soft light).
static func _card(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, n: Vector3, col: Color,
		uv_flip := false, quarter := -1) -> void:
	var pts := [c - u - v, c - u + v, c + u + v, c + u - v]
	var uvs := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	if uv_flip:
		uvs = [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
	var at := Vector2.ZERO
	var span := 1.0
	if quarter >= 0:
		at = Vector2(quarter % 2, quarter / 2) * 0.5
		span = 0.5
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(at + (uvs[k] as Vector2) * span)
		st.add_vertex(pts[k])


static func _broadleaf(rng: RandomNumberGenerator, elm: bool) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark_col := Color(0.30, 0.27, 0.24) if elm else Color(0.36, 0.33, 0.30)
	var crown := Vector3(0, REF_H * (0.68 if elm else 0.6), 0)
	var crown_r := REF_H * (0.3 if elm else 0.34)
	# The trunk flares into the ground and leans a little.
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
	var trunk_top := Vector3(0, REF_H * (0.42 if elm else 0.3), 0) + lean
	_limb(bark, Vector3(0, -0.2, 0), Vector3(0, 0.5, 0) + lean * 0.1, 0.5, 0.34, 8, bark_col)
	_bent_limb(bark, rng, Vector3(0, 0.5, 0) + lean * 0.1, trunk_top, 0.34, 0.24, 8, bark_col, 0.15)
	var limbs := 4 if elm else 3 + rng.randi() % 2
	for k in limbs:
		var az := TAU * k / limbs + rng.randf_range(-0.4, 0.4)
		var tilt := deg_to_rad(rng.randf_range(20.0, 30.0) if elm else rng.randf_range(28.0, 50.0))
		var dir := Vector3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az))
		_branch(bark, leaves, rng, trunk_top + Vector3(0, rng.randf_range(-0.3, 0.3), 0), dir, REF_H * (0.34 if elm else 0.28),
			0.2, 0, crown, bark_col, elm, crown_r)
	# The crown filled in toward its heart, shaded.
	for k in 40:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.3, 0.95)
		_cluster(leaves, rng, crown + d * crown_r, crown, rng.randf_range(1.6, 2.2), crown_r)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## A limb from a to b in three bending pieces, tapering.
static func _bent_limb(st: SurfaceTool, rng: RandomNumberGenerator, a: Vector3, b: Vector3, ra: float, rb: float, sides: int,
		col: Color, wander: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [a]
	var len_ := a.distance_to(b)
	for k in range(1, 3):
		var t := k / 3.0
		pts.append(a.lerp(b, t) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * len_ * wander * 0.3)
	pts.append(b)
	for k in 3:
		_limb(st, pts[k], pts[k + 1], lerpf(ra, rb, k / 3.0), lerpf(ra, rb, (k + 1) / 3.0), sides, col)
	return pts


static func _branch(bark: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, from: Vector3, dir: Vector3,
		length: float, radius: float, depth: int, crown: Vector3, col: Color, elm: bool, crown_r := 4.0) -> void:
	# Bending as it goes: up at first, then out, an elm's outer limbs
	# arching over.
	var droop := -0.35 if elm and depth >= 1 else rng.randf_range(-0.1, 0.25)
	var end := from + (dir + Vector3(0, droop, 0) * 0.5).normalized() * length
	var sides := 5 if depth == 0 else (4 if depth == 1 else 3)
	var pts := _bent_limb(bark, rng, from, end, radius, radius * 0.55, sides, col, 0.25)
	if depth >= 2:
		# The twigs: leaf clumps along the last pieces and at the end.
		for k in range(1, 4):
			for j in 2:
				var p: Vector3 = pts[k] + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.4, 0.6), rng.randf_range(-0.8, 0.8))
				_cluster(leaves, rng, p, crown, rng.randf_range(1.3, 1.9), crown_r)
		return
	var children := 3 if depth == 0 else 2 + rng.randi() % 2
	for k in children:
		var az := rng.randf_range(0.0, TAU)
		var off := Vector3(cos(az), rng.randf_range(0.0, 0.5), sin(az)).normalized()
		var child := (dir + off * rng.randf_range(0.6, 1.0)).normalized()
		var start: Vector3 = pts[1 + rng.randi() % 3]
		_branch(bark, leaves, rng, start, child, length * rng.randf_range(0.55, 0.72), radius * 0.5, depth + 1, crown, col, elm, crown_r)


## A clump of leaves at p: two cards turned mostly outward from the
## crown's heart, each at its own tilt and spin, so no two clumps show
## the same face. Shaded by how deep in the crown it hangs (the heart
## and the underside darker), its colour a little warmer or cooler than
## the tree's.
static func _cluster(leaves: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, crown: Vector3, size: float, crown_r := 4.0) -> void:
	var out := p - crown
	var depth := clampf(out.length() / crown_r, 0.0, 1.2)
	out = out.normalized() if out.length() > 0.1 else Vector3.UP
	var n := (out * 0.8 + Vector3.UP * 0.2).normalized()
	var shade := lerpf(0.5, 1.05, smoothstep(0.2, 1.0, depth)) * (0.82 if out.y < -0.3 else 1.0) * rng.randf_range(0.9, 1.1)
	var warm := rng.randf_range(-0.1, 0.1)
	var col := Color(shade * (1.0 + warm), shade, shade * (1.0 - warm * 0.7), 1.0)
	for k in 3:
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.3, 1.1))
		var facing := (tilt * out).normalized()
		var u := facing.cross(Vector3.UP if absf(facing.y) < 0.95 else Vector3.RIGHT).normalized()
		u = u.rotated(facing, rng.randf_range(0.0, TAU))
		var v := facing.cross(u).normalized()
		var sz := size * rng.randf_range(0.75, 1.1)
		var at := p + facing * 0.06 * k + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * size * 0.15
		_card(leaves, at, u * sz * 0.5, v * sz * 0.5, n, col, rng.randf() < 0.5, rng.randi() % 4)


static func _spruce(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark_col := Color(0.30, 0.23, 0.17)
	_limb(bark, Vector3.ZERO, Vector3(0, REF_H * 0.98, 0), 0.26, 0.03, 7, bark_col)
	var y := REF_H * rng.randf_range(0.10, 0.16)
	var whorl := 0
	while y < REF_H * 0.93:
		var up := y / REF_H
		var reach := (1.0 - up) * REF_H * 0.30 + 0.35
		var count := 6 if up < 0.7 else 5
		var droop := deg_to_rad(lerpf(32.0, 8.0, up))
		var turn := rng.randf_range(0.0, TAU)
		for k in count:
			var az := turn + TAU * k / count + rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(az), 0, sin(az))
			var dir := (out * cos(droop) - Vector3.UP * sin(droop)).normalized()
			var side := Vector3(-out.z, 0, out.x)
			var root := Vector3(0, y, 0)
			var mid := root + dir * reach * 0.5
			# Deeper in and lower down, the boughs are darker; each droops
			# at its tip, its outer half a second card bent down.
			var shade := Color.WHITE * rng.randf_range(0.85, 1.05) * lerpf(0.55, 1.0, up)
			shade.a = 1.0
			var n := (out * 0.6 + Vector3.UP * 0.4).normalized()
			var inner := root + dir * reach * 0.3
			_card(needles, inner, side * reach * 0.3, dir * reach * 0.3, n, shade * 0.8)
			var tip_dir := (dir - Vector3.UP * 0.25).normalized()
			_card(needles, root + dir * reach * 0.6 + tip_dir * reach * 0.2, side * reach * 0.4, tip_dir * reach * 0.35, n, shade)
			if up > 0.6:
				continue
			var tipped := (side * 0.5 + Vector3.UP * 0.866).normalized()
			_card(needles, mid + Vector3(0, 0.05, 0), tipped * reach * 0.3, dir * reach * 0.5, n, shade * 0.9)
		y += REF_H * rng.randf_range(0.055, 0.075)
		whorl += 1
	# The leader: two crossed cards up the top.
	var top := Vector3(0, REF_H * 0.93, 0)
	for k in 2:
		var s := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		_card(needles, top + Vector3(0, REF_H * 0.05, 0), s * 0.35, Vector3(0, REF_H * 0.055, 0), Vector3.UP, Color.WHITE)
	var mesh := bark.commit()
	needles.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _needle_mat)
	return mesh


## A clump of paper birches: two or three slender white stems leaning
## apart, their bark marked with dark bands, a light crown of small
## leaf clusters.
static func _birch(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(0.86, 0.85, 0.80)
	var mark := Color(0.12, 0.11, 0.10)
	var stems := 2 + rng.randi() % 2
	for k in stems:
		var az := TAU * k / stems + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(az) * 0.12, 1.0, sin(az) * 0.12).normalized()
		var foot := Vector3(cos(az) * 0.1, 0, sin(az) * 0.1)
		var top := foot + lean * REF_H * rng.randf_range(0.85, 1.0)
		_limb(bark, foot, top, 0.12, 0.03, 6, white)
		for b in 7:
			var t := rng.randf_range(0.08, 0.7)
			var p := foot.lerp(top, t)
			_limb(bark, p, p + lean * 0.05, 0.125 - 0.09 * t, 0.123 - 0.09 * t, 6, mark)
		# An open oval crown over the upper half: fine branches rising
		# from the stem and arching over, leaves hanging all along them.
		var crown := foot.lerp(top, 0.7)
		for c in 16:
			var t := rng.randf_range(0.42, 0.95)
			var from := foot.lerp(top, t)
			var az2 := rng.randf_range(0.0, TAU)
			var reach := lerpf(2.2, 0.7, (t - 0.42) / 0.53) * rng.randf_range(0.8, 1.2)
			var out := Vector3(cos(az2), 0, sin(az2))
			var mid := from + out * reach * 0.55 + Vector3.UP * reach * 0.45
			var tip := from + out * reach + Vector3.UP * reach * rng.randf_range(-0.1, 0.25)
			_limb(bark, from, mid, 0.035, 0.018, 3, mark.lerp(white, 0.3))
			_limb(bark, mid, tip, 0.018, 0.008, 3, mark.lerp(white, 0.2))
			for j in 3:
				var at := mid.lerp(tip, j / 2.0) + Vector3(0, -0.25 * j, 0)
				_cluster(leaves, rng, at, crown, rng.randf_range(0.9, 1.3), 2.2)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## A white oak grown in the open: a short thick trunk, great limbs
## reaching out more than up, a broad low crown.
static func _oak(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.34, 0.31, 0.27)
	var fork := Vector3(rng.randf_range(-0.3, 0.3), REF_H * 0.28, rng.randf_range(-0.3, 0.3))
	_limb(bark, Vector3.ZERO, fork, 0.5, 0.36, 8, col)
	var crown := Vector3(0, REF_H * 0.55, 0)
	for k in 5:
		var az := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var tilt := deg_to_rad(rng.randf_range(48.0, 66.0))
		var dir := Vector3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az))
		_branch(bark, leaves, rng, fork, dir, REF_H * 0.36, 0.24, 0, crown, col, false)
	for k in 14:
		var p := crown + Vector3(rng.randf_range(-3.5, 3.5), rng.randf_range(-1.2, 1.6), rng.randf_range(-3.5, 3.5))
		_cluster(leaves, rng, p, crown, 2.0)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## A white pine: a straight trunk bare below, then whorls of level
## boughs far apart and irregular, some missing, each a flat spray of
## needles, the crown open and ragged, flattening at the top.
static func _pine(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.30, 0.25, 0.20)
	_limb(bark, Vector3.ZERO, Vector3(0, REF_H * 0.97, 0), 0.3, 0.05, 7, col)
	var y := REF_H * rng.randf_range(0.3, 0.38)
	while y < REF_H * 0.95:
		var up := y / REF_H
		var count := 4 + rng.randi() % 2
		var turn := rng.randf_range(0.0, TAU)
		for k in count:
			if rng.randf() < 0.25:
				continue
			var az := turn + TAU * k / count + rng.randf_range(-0.35, 0.35)
			var out := Vector3(cos(az), 0, sin(az))
			var reach := ((1.05 - up) * REF_H * 0.3 + 0.6) * rng.randf_range(0.7, 1.2)
			var lift := deg_to_rad(rng.randf_range(-6.0, 10.0))
			var dir := (out * cos(lift) + Vector3.UP * sin(lift)).normalized()
			var root := Vector3(0, y, 0)
			_limb(bark, root, root + dir * reach * 0.8, 0.07, 0.02, 4, col)
			var side := Vector3(-out.z, 0, out.x)
			var shade := Color.WHITE * rng.randf_range(0.8, 1.05)
			shade.a = 1.0
			var n := (out * 0.3 + Vector3.UP * 0.7).normalized()
			var mid := root + dir * reach * 0.55
			_card(needles, mid, side * reach * 0.38, dir * reach * 0.48, n, shade)
			_card(needles, mid + Vector3(0, 0.12, 0), (side * 0.7 + Vector3.UP * 0.7).normalized() * reach * 0.26, dir * reach * 0.45, n, shade * 0.9)
		y += REF_H * rng.randf_range(0.08, 0.12)
	var top := Vector3(0, REF_H * 0.95, 0)
	for k in 3:
		var a := TAU * k / 3.0
		_card(needles, top, Vector3(cos(a), 0, sin(a)) * 0.9, Vector3(-sin(a), 0.2, cos(a)) * 0.9, Vector3.UP, Color.WHITE)
	var mesh := bark.commit()
	needles.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _needle_mat)
	return mesh


## A shrub: many stems from the ground, leaf clusters round their ends;
## in flower (a hydrangea at the end of the season), heads of papery
## bloom among the leaves. Stands REF_H tall like the trees: instance it
## small.
static func _shrub(rng: RandomNumberGenerator, flowering: bool) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.35, 0.3, 0.25)
	# A rounded mass: leaf clusters through an ellipsoid over a few short
	# stems, thickest at its skin.
	var crown := Vector3(0, REF_H * 0.5, 0)
	var rx := REF_H * 0.42
	var ry := REF_H * 0.42
	for k in 7:
		var az := rng.randf_range(0.0, TAU)
		var tip := crown + Vector3(cos(az) * rx * 0.5, rng.randf_range(0.0, ry * 0.5), sin(az) * rx * 0.5)
		_limb(bark, Vector3(cos(az) * 0.2, 0, sin(az) * 0.2), tip, 0.1, 0.04, 4, col)
	for k in 30:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1), rng.randf_range(-1, 1)).normalized() * sqrt(rng.randf_range(0.35, 1.0))
		var p := crown + Vector3(d.x * rx, d.y * ry, d.z * rx)
		_cluster(leaves, rng, p, crown, REF_H * 0.28)
		if flowering and k % 3 == 0 and d.y > -0.3:
			var bloom := Color(0.82, 0.62, 0.66).lerp(Color(0.62, 0.66, 0.82), rng.randf()).lerp(Color(0.78, 0.72, 0.6), 0.35)
			_ball(bark, crown + Vector3(d.x * rx, d.y * ry, d.z * rx) * 1.02, REF_H * 0.1, bloom)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## A metre of clipped hedge: a box of leaf cards, dense and level on
## top, REF_H on a side (instance it scaled to size).
static func _hedge(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := REF_H
	_limb(bark, Vector3(0, 0, 0), Vector3(0, s * 0.5, 0), s * 0.06, s * 0.04, 4, Color(0.3, 0.25, 0.2))
	for k in 40:
		var p := Vector3(rng.randf_range(-0.45, 0.45) * s, rng.randf_range(0.1, 0.92) * s, rng.randf_range(-0.42, 0.42) * s)
		var n := Vector3(p.x, p.y - 0.5 * s, p.z).normalized()
		var shade := Color.WHITE * rng.randf_range(0.8, 1.0)
		shade.a = 1.0
		var basis := Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)))
		_card(leaves, p, basis.x * s * 0.22, basis.y * s * 0.22, n, shade, false, k % 4)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


## A rough ball in the bark surface (a flower head), its own colour.
static func _ball(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var rings := 4
	var sides := 7
	for j in rings:
		var a0 := PI * j / rings - PI / 2.0
		var a1 := PI * (j + 1) / rings - PI / 2.0
		for k in sides:
			var b0 := TAU * k / sides
			var b1 := TAU * (k + 1) / sides
			var q: Array[Vector3] = [_sph(a0, b0), _sph(a1, b0), _sph(a1, b1), _sph(a0, b0), _sph(a1, b1), _sph(a0, b1)]
			for v in q:
				st.set_color(col)
				st.set_normal(v)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(c + v * r)


static func _sph(a: float, b: float) -> Vector3:
	return Vector3(cos(a) * cos(b), sin(a), cos(a) * sin(b))

