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
const VARIANTS := 3

static var _meshes: Dictionary = {}          # "maple0" etc -> ArrayMesh
static var _leaf_mat: ShaderMaterial = null
static var _needle_mat: ShaderMaterial = null
static var _bark_mat: ShaderMaterial = null


## A tree of kind ("maple", "elm", "spruce") and variant, built on
## first asking.
static func mesh(kind: String, variant: int) -> ArrayMesh:
	var key := "%s%d" % [kind, variant]
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key) + 1947
		_meshes[key] = _spruce(rng) if kind == "spruce" else _broadleaf(rng, kind == "elm")
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
	_leaf_mat.set_shader_parameter("tex_size", 256.0)
	_needle_mat = ShaderMaterial.new()
	_needle_mat.shader = shader
	_needle_mat.set_shader_parameter("leaves", _needle_texture())
	_needle_mat.set_shader_parameter("tex_size", 256.0)


## ---- the pictures -------------------------------------------------------------

## A cluster of leaves on their twigs, seen face on: forty-odd leaves
## with lobed edges and a darker midrib, radiating from the twig, pale
## grey so the tree's own colour tints them.
static func _leaf_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.35, 0.3, 0.25, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := Vector2(n / 2.0, n / 2.0)
	for k in 46:
		var a := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf()) * n * 0.36
		var base := c + Vector2(cos(a), sin(a)) * r
		var dir := Vector2(cos(a + rng.randf_range(-0.6, 0.6)), sin(a + rng.randf_range(-0.6, 0.6)))
		var length := rng.randf_range(24.0, 34.0)
		var width := length * rng.randf_range(0.36, 0.48)
		var shade := rng.randf_range(0.62, 1.0)
		_line(img, c + (base - c) * 0.35, base, 1.2, Color(0.30, 0.24, 0.18, 1.0))
		_leaf(img, base, dir, length, width, shade)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _leaf(img: Image, base: Vector2, dir: Vector2, length: float, width: float, shade: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var lo := (base - Vector2(length, length)).floor()
	var hi := (base + Vector2(length, length) * 1.1).ceil()
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y), img.get_height())):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x), img.get_width())):
			var q := Vector2(x, y) - base
			var u := q.dot(dir) / length
			if u < 0.0 or u > 1.0:
				continue
			var v := absf(q.dot(side))
			var edge := width * 0.5 * pow(sin(PI * u), 0.75) * (0.72 + 0.28 * absf(sin(3.0 * PI * u)))
			if v > edge:
				continue
			var vein := 1.0 - 0.25 * (1.0 - smoothstep(0.0, 1.5, v))
			var g := shade * vein * (0.9 + 0.1 * u)
			img.set_pixel(x, y, Color(g, g, g, 1.0))


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
		uv_flip := false) -> void:
	var pts := [c - u - v, c - u + v, c + u + v, c + u - v]
	var uvs := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	if uv_flip:
		uvs = [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])


static func _broadleaf(rng: RandomNumberGenerator, elm: bool) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark_col := Color(0.30, 0.27, 0.24) if elm else Color(0.36, 0.33, 0.30)
	var crown := Vector3(0, REF_H * (0.68 if elm else 0.6), 0)
	var trunk_top := Vector3(rng.randf_range(-0.3, 0.3), REF_H * (0.42 if elm else 0.3), rng.randf_range(-0.3, 0.3))
	_limb(bark, Vector3.ZERO, trunk_top, 0.34, 0.24, 8, bark_col)
	var limbs := 4 if elm else 3 + rng.randi() % 2
	for k in limbs:
		var az := TAU * k / limbs + rng.randf_range(-0.4, 0.4)
		var tilt := deg_to_rad(rng.randf_range(22.0, 32.0) if elm else rng.randf_range(30.0, 48.0))
		var dir := Vector3(sin(tilt) * cos(az), cos(tilt), sin(tilt) * sin(az))
		_branch(bark, leaves, rng, trunk_top, dir, REF_H * (0.36 if elm else 0.3), 0.2, 0, crown, bark_col, elm)
	# A few clusters inside the crown, so it is not hollow.
	for k in 10:
		var p := crown + Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.5, 1.5), rng.randf_range(-1.8, 1.8))
		_cluster(leaves, rng, p, crown, 1.8)
	var mesh := bark.commit()
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat)
	mesh.surface_set_material(1, _leaf_mat)
	return mesh


static func _branch(bark: SurfaceTool, leaves: SurfaceTool, rng: RandomNumberGenerator, from: Vector3, dir: Vector3,
		length: float, radius: float, depth: int, crown: Vector3, col: Color, elm: bool) -> void:
	# Two segments with a bend, the second turning a little upward
	# (or, on an elm's outer limbs, arching over).
	var bend := Vector3(rng.randf_range(-0.2, 0.2), (-0.15 if elm and depth >= 1 else 0.12), rng.randf_range(-0.2, 0.2))
	var mid := from + dir * length * 0.5
	var dir2 := (dir + bend).normalized()
	var end := mid + dir2 * length * 0.5
	var sides := 5 if depth == 0 else 3
	_limb(bark, from, mid, radius, radius * 0.8, sides, col)
	_limb(bark, mid, end, radius * 0.8, radius * 0.6, sides, col)
	if depth >= 2:
		for k in 2:
			var p := end + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.5, 0.8), rng.randf_range(-0.9, 0.9))
			_cluster(leaves, rng, p, crown, rng.randf_range(1.5, 2.1))
		return
	var children := 3 if depth == 0 else 2 + rng.randi() % 2
	for k in children:
		var az := rng.randf_range(0.0, TAU)
		var off := Vector3(cos(az), rng.randf_range(0.1, 0.6), sin(az)).normalized()
		var child := (dir2 + off * rng.randf_range(0.55, 0.9)).normalized()
		var start := mid.lerp(end, rng.randf_range(0.4, 1.0))
		_branch(bark, leaves, rng, start, child, length * rng.randf_range(0.6, 0.75), radius * 0.55, depth + 1, crown, col, elm)


## A leaf cluster at p: three crossed cards at random turns, normals
## bent out from the crown's centre.
static func _cluster(leaves: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, crown: Vector3, size: float) -> void:
	var out := (p - crown).normalized()
	if out.length() < 0.5:
		out = Vector3.UP
	var n := (out * 0.7 + Vector3.UP * 0.3).normalized()
	var shade := Color.WHITE * rng.randf_range(0.82, 1.08)
	shade.a = 1.0
	var basis := Basis.from_euler(Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)))
	for k in 3:
		var axis_u: Vector3 = [basis.x, basis.y, basis.z][k]
		var axis_v: Vector3 = [basis.y, basis.z, basis.x][k]
		_card(leaves, p, axis_u * size * 0.5, axis_v * size * 0.5, n, shade)


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
			var shade := Color.WHITE * rng.randf_range(0.8, 1.05)
			shade.a = 1.0
			var n := (out * 0.6 + Vector3.UP * 0.4).normalized()
			# The bough: a flat card along it, and a second tipped up across it.
			_card(needles, mid, side * reach * 0.42, dir * reach * 0.5, n, shade)
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
