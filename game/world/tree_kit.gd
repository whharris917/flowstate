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
		var crown := foot.lerp(top, 0.72)
		for c in 9:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.8), rng.randf_range(-1, 1)).normalized()
			var from := foot.lerp(top, rng.randf_range(0.5, 0.9))
			var tip := from + dir * rng.randf_range(0.8, 1.8)
			_limb(bark, from, tip, 0.03, 0.01, 3, white)
			_cluster(leaves, rng, tip, crown, rng.randf_range(1.0, 1.4))
			_cluster(leaves, rng, tip + Vector3(0, -0.5, 0), crown, 1.0)
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


## A white pine: a straight trunk, bare below, then whorls of level
## branches ending in soft tufts, irregular.
static func _pine(rng: RandomNumberGenerator) -> ArrayMesh:
	_ensure_materials()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.30, 0.25, 0.20)
	_limb(bark, Vector3.ZERO, Vector3(0, REF_H, 0), 0.3, 0.04, 7, col)
	var y := REF_H * 0.35
	while y < REF_H * 0.98:
		var up := y / REF_H
		var count := 3 + rng.randi() % 3
		for k in count:
			if rng.randf() < 0.2:
				continue
			var az := rng.randf_range(0.0, TAU)
			var reach := (1.1 - up) * REF_H * 0.32 + 0.4
			var out := Vector3(cos(az), rng.randf_range(0.0, 0.2), sin(az)).normalized()
			var tip := Vector3(0, y, 0) + out * reach
			_limb(bark, Vector3(0, y, 0), tip, 0.06, 0.02, 4, col)
			for t in 3:
				var p := Vector3(0, y, 0).lerp(tip, 0.45 + 0.27 * t)
				var side := Vector3(-out.z, 0, out.x)
				var n := (out * 0.3 + Vector3.UP).normalized()
				var shade := Color.WHITE * rng.randf_range(0.85, 1.05)
				shade.a = 1.0
				_card(needles, p + Vector3(0, 0.1, 0), side * 0.55, out * 0.5, n, shade)
				_card(needles, p + Vector3(0, 0.15, 0), (side * 0.6 + Vector3.UP * 0.8).normalized() * 0.45, out * 0.5, n, shade * 0.9)
		y += REF_H * rng.randf_range(0.07, 0.1)
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
	var crown := Vector3(0, REF_H * 0.55, 0)
	for k in 9:
		var az := rng.randf_range(0.0, TAU)
		var tip := Vector3(cos(az) * REF_H * 0.3, REF_H * rng.randf_range(0.6, 0.95), sin(az) * REF_H * 0.3)
		_limb(bark, Vector3(cos(az) * 0.3, 0, sin(az) * 0.3), tip, 0.12, 0.05, 4, col)
		for k2 in 3:
			var p := tip.lerp(crown, 0.25 * k2) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 0.6), rng.randf_range(-1, 1))
			_cluster(leaves, rng, p, crown, REF_H * 0.3)
		if flowering:
			for f in 3:
				var head := tip + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.6, 0.4), rng.randf_range(-1.2, 1.2))
				var bloom := Color(0.82, 0.62, 0.66).lerp(Color(0.62, 0.66, 0.82), rng.randf()).lerp(Color(0.78, 0.72, 0.6), 0.35)
				_ball(bark, head, REF_H * 0.09, bloom)
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
		_card(leaves, p, basis.x * s * 0.22, basis.y * s * 0.22, n, shade)
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

