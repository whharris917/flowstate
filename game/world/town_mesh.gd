class_name TownMesh
extends RefCounted
## A town's worth of geometry gathered into one mesh per material, so a
## few hundred buildings draw in a handful of calls. Boxes, gable
## prisms, cylinders and single quads are added in a transform with a
## vertex colour (what the material reads: a paint colour, a kind, a
## lamp's delay); commit() makes the meshes. Art only: no collision
## here, no records.
##
## Faces are wound clockwise seen from the front, as Godot draws them.

var _surfaces: Dictionary = {}   # key -> Surface
var triangles := 0


## One material's arrays. Appends go through its own methods: a packed
## array handed out of an object or a dictionary is a copy.
class Surface:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()

	func vertex(p: Vector3, normal: Vector3, col: Color, tex: Vector2) -> void:
		v.append(p)
		n.append(normal)
		c.append(col)
		uv.append(tex)

	func index(k: int) -> void:
		i.append(k)


func _s(key: String) -> Surface:
	if not _surfaces.has(key):
		_surfaces[key] = Surface.new()
	return _surfaces[key]


## A flat quad through a, b, c, d (in order round it) facing n: the
## winding is chosen from n. UVs are given per corner.
func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color,
		uv_a := Vector2(0, 0), uv_b := Vector2(0, 1), uv_c := Vector2(1, 1), uv_d := Vector2(1, 0)) -> void:
	var s := _s(key)
	var base := s.v.size()
	if (b - a).cross(c - a).dot(n) > 0.0:
		s.vertex(a, n, col, uv_a)
		s.vertex(d, n, col, uv_d)
		s.vertex(c, n, col, uv_c)
		s.vertex(b, n, col, uv_b)
	else:
		s.vertex(a, n, col, uv_a)
		s.vertex(b, n, col, uv_b)
		s.vertex(c, n, col, uv_c)
		s.vertex(d, n, col, uv_d)
	for k: int in [0, 1, 2, 0, 2, 3]:
		s.index(base + k)
	triangles += 2


func tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	var s := _s(key)
	var base := s.v.size()
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	s.vertex(a, n, col, Vector2.ZERO)
	s.vertex(c if flip else b, n, col, Vector2.ZERO)
	s.vertex(b if flip else c, n, col, Vector2.ZERO)
	for k in 3:
		s.index(base + k)
	triangles += 1


const _FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
]


## A box of size centred at xf's origin. bottom = false leaves the
## underside out (anything standing on the ground).
func box(key: String, xf: Transform3D, size: Vector3, col: Color, bottom := false) -> void:
	var h := size / 2.0
	for f in 6:
		if f == 5 and not bottom:
			continue
		var face: Array = _FACES[f]
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var c := n * h
		var hu := u * h
		var hv := v * h
		var su := absf(u.dot(size))
		var sv := absf(v.dot(size))
		quad(key, xf * (c - hu - hv), xf * (c - hu + hv), xf * (c + hu + hv), xf * (c + hu - hv),
			(xf.basis * n).normalized(), col, Vector2(0, 0), Vector2(0, sv), Vector2(su, sv), Vector2(su, 0))


## A gable: a triangle w wide and h high in the local x-y plane, its
## base on y = 0, drawn out d along z (centred).
func prism(key: String, xf: Transform3D, w: float, h: float, d: float, col: Color) -> void:
	var l := Vector3(-w / 2.0, 0, 0)
	var r := Vector3(w / 2.0, 0, 0)
	var t := Vector3(0, h, 0)
	var f := Vector3(0, 0, d / 2.0)
	var nz := (xf.basis * Vector3(0, 0, 1)).normalized()
	tri(key, xf * (l + f), xf * (t + f), xf * (r + f), nz, col)
	tri(key, xf * (l - f), xf * (t - f), xf * (r - f), -nz, col)
	var nl := (xf.basis * Vector3(-h, w / 2.0, 0).normalized()).normalized()
	var nr := (xf.basis * Vector3(h, w / 2.0, 0).normalized()).normalized()
	quad(key, xf * (l - f), xf * (l + f), xf * (t + f), xf * (t - f), nl, col)
	quad(key, xf * (r - f), xf * (r + f), xf * (t + f), xf * (t - f), nr, col)


## A cylinder or cone along local y, centred, smooth-sided.
func cylinder(key: String, xf: Transform3D, r_bottom: float, r_top: float, h: float, sides: int,
		col: Color, caps := true) -> void:
	var s := _s(key)
	var base := s.v.size()
	var slope := (r_bottom - r_top) / h
	for k in sides + 1:
		var a := TAU * k / sides
		var dir := Vector3(cos(a), 0, sin(a))
		var n := (xf.basis * Vector3(dir.x, slope, dir.z).normalized()).normalized()
		s.vertex(xf * (dir * r_bottom + Vector3(0, -h / 2.0, 0)), n, col, Vector2(float(k) / sides, 0))
		s.vertex(xf * (dir * r_top + Vector3(0, h / 2.0, 0)), n, col, Vector2(float(k) / sides, 1))
	for k in sides:
		var a0 := base + k * 2
		# Seen from outside, bottom k+1 is left of bottom k: this order
		# runs clockwise.
		for j: int in [a0, a0 + 3, a0 + 1, a0, a0 + 2, a0 + 3]:
			s.index(j)
		triangles += 2
	if caps:
		for end: float in [-1.0, 1.0]:
			var r := r_top if end > 0.0 else r_bottom
			if r <= 0.0:
				continue
			var n := (xf.basis * Vector3(0, end, 0)).normalized()
			var centre := xf * Vector3(0, end * h / 2.0, 0)
			for k in sides:
				var a0 := TAU * k / sides
				var a1 := TAU * (k + 1) / sides
				tri(key, centre, xf * Vector3(cos(a0) * r, end * h / 2.0, sin(a0) * r),
					xf * Vector3(cos(a1) * r, end * h / 2.0, sin(a1) * r), n, col)


## A sphere (or, scaled by xf, an ellipsoid): lamp globes, buoys.
func sphere(key: String, xf: Transform3D, radius: float, sides: int, col: Color) -> void:
	var rings := maxi(sides / 2, 3)
	for j in rings:
		var a0 := PI * j / rings - PI / 2.0
		var a1 := PI * (j + 1) / rings - PI / 2.0
		for k in sides:
			var b0 := TAU * k / sides
			var b1 := TAU * (k + 1) / sides
			var p00 := Vector3(cos(a0) * cos(b0), sin(a0), cos(a0) * sin(b0))
			var p01 := Vector3(cos(a0) * cos(b1), sin(a0), cos(a0) * sin(b1))
			var p10 := Vector3(cos(a1) * cos(b0), sin(a1), cos(a1) * sin(b0))
			var p11 := Vector3(cos(a1) * cos(b1), sin(a1), cos(a1) * sin(b1))
			var n := (xf.basis * (p00 + p01 + p10 + p11).normalized()).normalized()
			quad(key, xf * (p00 * radius), xf * (p10 * radius), xf * (p11 * radius), xf * (p01 * radius), n, col)


## A round bar from a to b (a pipe, a wire's span, a rail).
func bar(key: String, a: Vector3, b: Vector3, radius: float, sides: int, col: Color) -> void:
	var along := b - a
	var length := along.length()
	if length < 1e-4:
		return
	var y := along / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	cylinder(key, Transform3D(Basis(x, y, z), (a + b) / 2.0), radius, radius, length, sides, col, false)


## One mesh instance per material key under parent. shadows: the keys
## that cast.
func commit(parent: Node3D, materials: Dictionary, shadows: Array = []) -> Dictionary:
	var out: Dictionary = {}
	for key: String in _surfaces:
		var s: Surface = _surfaces[key]
		if s.v.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.v
		arrays[Mesh.ARRAY_NORMAL] = s.n
		arrays[Mesh.ARRAY_COLOR] = s.c
		arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_INDEX] = s.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var inst := MeshInstance3D.new()
		inst.name = "Town_" + key
		inst.mesh = mesh
		inst.material_override = materials.get(key)
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows.has(key) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inst)
		out[key] = inst
	return out
