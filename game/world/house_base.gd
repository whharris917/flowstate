class_name HouseBase
extends Node3D
## What every house modelled whole is built from: walls as slabs round
## their openings, double-hung windows with their sashes (one left open
## now and then) and curtains on a rod, lamps and ceiling fixtures that
## light at the room's own darkness, fires that flicker from dusk, and a
## library of furniture and the small things of a room.
##
## Three meshes per house. The shell (the outer walls, the roof, the
## trim, the glass) draws at any distance. The detail (the rooms' faces,
## floors and stair, the sashes, the curtains, the furniture and the
## small things) draws only within DETAIL_RANGE, so a house can carry as
## much as a room holds and the town pays for it only up close. The far
## mesh stands in for the rooms past that range: a pane in each window
## showing a room lit at its own time, as the town's plainer houses do.
## Room lights fade out past LIGHT_RANGE for the same reason. `m` is
## whichever mesh is being built: shell(), detail() and far() switch it.
##
## A house's frame: its front face on z = 0 facing +z, x across the
## front, the back face at z = -depth; floors at their own heights.
## Art only: no records. Solid to the player.

const T_OUT := 0.1           # clapboard and sheathing
const T_IN := 0.05           # plaster
const DETAIL_RANGE := 55.0
const LIGHT_RANGE := 60.0
const TRIM := Color(0.93, 0.92, 0.88)
const PLASTER := Color(0.90, 0.88, 0.82)
const OAK := Color(0.62, 0.42, 0.24)

var town: HarborTown
var shell_mesh := TownMesh.new()
var detail_mesh := TownMesh.new()
var far_mesh := TownMesh.new()
var m: TownMesh = shell_mesh
var glass_mat: StandardMaterial3D
var stats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _lights := 0
var _fires: Array[Dictionary] = []   # {light, mat, lit}
var _t := 0.0


func _setup(t: HarborTown, front: Vector3, yaw: float, seed_: int) -> void:
	town = t
	transform = HarborTown.at(front, yaw)
	_rng.seed = seed_
	glass_mat = StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.80, 0.86, 0.90, 0.10)
	glass_mat.roughness = 0.04
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func shell() -> void:
	m = shell_mesh


func detail() -> void:
	m = detail_mesh


func far() -> void:
	m = far_mesh


## Both meshes under the house; the detail one draws only near.
func _commit() -> void:
	var mats := {"wall": town.wall_mat, "iron": town.iron_mat, "steel": town.steel_mat, "lamp": town.lamp_mat,
		"clear": glass_mat, "shade": town.shade_mat}
	shell_mesh.commit(self, mats, ["wall", "iron"])
	var near := detail_mesh.commit(self, mats, [])
	for key: String in near:
		var inst: MeshInstance3D = near[key]
		inst.name = "Detail_" + key
		inst.visibility_range_end = DETAIL_RANGE
		inst.visibility_range_end_margin = 5.0
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var distant := far_mesh.commit(self, {"glass": town.glass_mat}, [])
	for key: String in distant:
		var inst: MeshInstance3D = distant[key]
		inst.name = "Far_" + key
		inst.visibility_range_begin = DETAIL_RANGE - 5.0
		inst.visibility_range_begin_margin = 5.0
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	stats = {"triangles": shell_mesh.triangles + detail_mesh.triangles, "detail_triangles": detail_mesh.triangles,
		"lights": _lights}


static func c(color: Color, kind: int) -> Color:
	return HarborTown.kc(color, kind)


## ---- building blocks -----------------------------------------------------------

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
		# Every opening in this column, bottom up: wall below the lowest,
		# between each and the next, and above the highest.
		var holes: Array = []
		for o: Array in openings:
			if (u0 + u1) / 2.0 > float(o[0]) and (u0 + u1) / 2.0 < float(o[1]):
				holes.append(o)
		holes.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))
		var bottom := y0
		for hole: Array in holes:
			_slab(key, q0, q1, bottom, float(hole[2]), float(hole[2]), t, col, solid)
			bottom = maxf(bottom, float(hole[3]))
		_slab(key, q0, q1, bottom, maxf(t0, bottom), maxf(t1, bottom), t, col, solid)


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
	_solid((a + b) / 2.0 - basis.y * 0.05, Vector3(w, 0.1, length), basis)


## A straight stair from (x0..x1, z_bottom) at y0 up to z_top at y1,
## rising toward z_top: treads, risers, a closed side on side_x (the
## open side), a ramp underfoot, a newel, a handrail, balusters.
func _stair(x0: float, x1: float, z_bottom: float, z_top: float, y0: float, y1: float, rail_x: float,
		wood: Color, white: Color) -> void:
	var n := int(round((y1 - y0) / 0.19))
	var rise := (y1 - y0) / n
	var dz := (z_top - z_bottom) / n
	var cx := (x0 + x1) / 2.0
	var width := absf(x1 - x0)
	for k in n - 1:
		var y := y0 + rise * (k + 1)
		var z := z_bottom + dz * (k + 0.5)
		_box("wall", Vector3(cx, y - 0.02, z + signf(dz) * 0.015), Vector3(width, 0.04, absf(dz) + 0.03), wood)
		_box("wall", Vector3(cx, y - rise / 2.0, z_bottom + dz * k), Vector3(width, rise, 0.02), white)
	_slab("wall", Vector2(rail_x, z_bottom), Vector2(rail_x, z_top), y0, y0 + rise, y1 - 0.05, 0.04, white)
	_ramp(Vector3(cx, y0, z_bottom + signf(-dz) * 0.05), Vector3(cx, y1, z_top), width)
	_box("wall", Vector3(rail_x, y0 + 0.55, z_bottom), Vector3(0.1, 1.1, 0.1), white, true)
	_box("wall", Vector3(rail_x, y0 + 1.12, z_bottom), Vector3(0.13, 0.05, 0.13), wood)
	m.bar("wall", Vector3(rail_x, y0 + 1.0, z_bottom), Vector3(rail_x, y1 + 0.9, z_top), 0.03, 6, wood)
	for k in n - 1:
		var y := y0 + rise * (k + 1)
		var z := z_bottom + dz * (k + 0.5)
		_box("wall", Vector3(rail_x, y + 0.5, z), Vector3(0.03, 1.0, 0.03), white)


## A railing along the open side of a stairwell upstairs, from za to zb at x.
func _well_rail(x: float, za: float, zb: float, y: float, wood: Color, white: Color) -> void:
	_box("wall", Vector3(x, y + 0.9, (za + zb) / 2.0), Vector3(0.07, 0.05, absf(za - zb)), wood, true)
	var n := int(absf(za - zb) / 0.12)
	for k in n + 1:
		_box("wall", Vector3(x, y + 0.45, lerpf(za, zb, float(k) / n)), Vector3(0.025, 0.9, 0.025), white)
	_solid(Vector3(x, y + 0.5, (za + zb) / 2.0), Vector3(0.1, 1.0, absf(za - zb)))


## A double-hung window in a wall whose outer face passes through
## centre, facing out along yaw (0: +z). Casing and sill outside,
## shutters if asked, the two sashes with six lights each (the lower one
## raised when open), a stool and casing inside, curtains on a rod when
## a colour is given, a radiator under it on the ground floor.
func _window_unit(centre: Vector3, w: float, h: float, yaw: float, shutters: bool, depth: float,
		curtain: Variant = null, open := false, radiator := false, shutter_color := Color(0.10, 0.16, 0.12)) -> void:
	var keep := m
	shell()
	var xf := HarborTown.at(centre, yaw)
	var trim := c(TRIM, HarborTown.K_PAINT)
	var inner := c(TRIM, HarborTown.K_ENAMEL)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.07, 0.03)), Vector3(w + 0.3, 0.14, 0.06), trim, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.16, 0.05)), Vector3(w + 0.36, 0.04, 0.1), trim, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.04, 0.05)), Vector3(w + 0.34, 0.06, 0.12), trim, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 + 0.07), 0, 0.03)), Vector3(0.14, h, 0.06), trim, true)
	if shutters:
		for s: float in [-1.0, 1.0]:
			var sx := s * (w / 2.0 + 0.14 + w * 0.25)
			m.box("wall", xf * HarborTown.at(Vector3(sx, 0, 0.04)), Vector3(w * 0.5, h + 0.1, 0.03), c(shutter_color, HarborTown.K_PAINT), true)
			for k in 8:
				m.box("wall", xf * HarborTown.at(Vector3(sx, -h / 2.0 + 0.12 + k * (h - 0.2) / 8.0, 0.058)), Vector3(w * 0.42, 0.02, 0.01), c(shutter_color * 0.8, HarborTown.K_PAINT), true)
	# From afar, a pane of the town's lit-room glass just inside.
	far()
	var face := (xf.basis * Vector3(0, 0, 1)).normalized()
	m.quad("glass", xf * Vector3(-w / 2.0, -h / 2.0, -0.04), xf * Vector3(-w / 2.0, h / 2.0, -0.04), xf * Vector3(w / 2.0, h / 2.0, -0.04),
		xf * Vector3(w / 2.0, -h / 2.0, -0.04), face, Color(_rng.randf_range(0.2, 0.6), _rng.randf(), 0.0, _rng.randf()),
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	detail()
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 - 0.01), 0, -depth / 2.0)), Vector3(0.02, h, depth), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 - 0.01, -depth / 2.0)), Vector3(w, 0.02, depth), inner, true)
	# The sashes: the upper outside, the lower inside; open, the lower
	# one stands raised in front of the upper. The glass draws from any
	# distance, the frames only near.
	var zs: Array[float] = [-0.05, -0.08]
	for k in 2:
		var sh := h / 2.0
		var cy := h / 4.0 if k == 0 else -h / 4.0
		if k == 1 and open:
			cy += sh * 0.8
		var sz := zs[k]
		var frame := c(TRIM, HarborTown.K_ENAMEL)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy + sh / 2.0 - 0.025, sz)), Vector3(w, 0.05, 0.04), frame, true)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy - sh / 2.0 + 0.03, sz)), Vector3(w, 0.06, 0.04), frame, true)
		for s: float in [-1.0, 1.0]:
			m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 - 0.025), cy, sz)), Vector3(0.05, sh, 0.04), frame, true)
		for f: float in [-1.0 / 6.0, 1.0 / 6.0]:
			m.box("wall", xf * HarborTown.at(Vector3(f * w, cy, sz)), Vector3(0.018, sh - 0.08, 0.025), frame, true)
		m.box("wall", xf * HarborTown.at(Vector3(0, cy, sz)), Vector3(w - 0.08, 0.018, 0.025), frame, true)
		var n := (xf.basis * Vector3(0, 0, 1)).normalized()
		shell_mesh.quad("clear", xf * Vector3(-w / 2.0 + 0.05, cy - sh / 2.0 + 0.05, sz), xf * Vector3(-w / 2.0 + 0.05, cy + sh / 2.0 - 0.04, sz),
			xf * Vector3(w / 2.0 - 0.05, cy + sh / 2.0 - 0.04, sz), xf * Vector3(w / 2.0 - 0.05, cy - sh / 2.0 + 0.05, sz), n, Color.WHITE)
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.02, -depth - 0.06)), Vector3(w + 0.2, 0.035, 0.14), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.1, -depth - 0.015)), Vector3(w + 0.12, 0.1, 0.03), inner, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, h / 2.0 + 0.06, -depth - 0.015)), Vector3(w + 0.24, 0.12, 0.03), inner, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (w / 2.0 + 0.05), 0, -depth - 0.015)), Vector3(0.1, h, 0.03), inner, true)
	if radiator:
		var rad := xf * HarborTown.at(Vector3(0, -h / 2.0 - 0.45, -depth - 0.14))
		for k in 9:
			m.box("iron", rad * HarborTown.at(Vector3(-0.32 + 0.08 * k, 0, 0)), Vector3(0.05, 0.55, 0.14), Color(0.72, 0.72, 0.7))
		m.cylinder("iron", rad * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0, -0.2, 0)), 0.02, 0.02, 0.72, 6, Color(0.72, 0.72, 0.7))
	if curtain is Color:
		# The rod on its brackets, two panels drawn to the sides in folds;
		# a window left open has its curtains blowing a little inward.
		var cz := -depth - 0.1
		var cloth := c(curtain as Color, HarborTown.K_CLOTH)
		m.bar("iron", xf * Vector3(-w / 2.0 - 0.3, h / 2.0 + 0.15, cz), xf * Vector3(w / 2.0 + 0.3, h / 2.0 + 0.15, cz), 0.012, 6, Color(0.6, 0.5, 0.3))
		for s: float in [-1.0, 1.0]:
			var drift := 0.12 if open else 0.0
			for f in 4:
				var fx := s * (w / 2.0 + 0.2 - 0.07 * f)
				var fold := 0.02 * (f % 2)
				m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -drift * 0.3), Vector3(fx, 0.05, cz - fold - drift * 0.3)), Vector3(0.08, h + 0.2, 0.012), cloth, true)
	m = keep


## A lamp: its shade or globe glowing, a light, lighting at the darkness
## thr. kind names its fixture: "porch", "ceiling", "pendant", "shade".
## The glowing parts go into the house's shade mesh, one draw for all.
func _lamp_fixture(pos: Vector3, kind: String, thr: float, energy: float, range_m := 5.0) -> void:
	var keep := m
	var glow := Color(thr, 0.8, 0.0, 1.0)
	match kind:
		"porch":
			shell()
			m.cylinder("shade", HarborTown.at(pos), 0.09, 0.07, 0.26, 10, glow)
			m.box("iron", HarborTown.at(pos + Vector3(0, 0.15, 0)), Vector3(0.2, 0.04, 0.2), Color(0.08, 0.08, 0.08))
			m.box("iron", HarborTown.at(pos + Vector3(0, 0.0, -0.08)), Vector3(0.04, 0.3, 0.04), Color(0.08, 0.08, 0.08))
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4.0
				m.bar("iron", pos + Vector3(cos(a) * 0.09, -0.13, sin(a) * 0.09), pos + Vector3(cos(a) * 0.07, 0.13, sin(a) * 0.07), 0.008, 4, Color(0.08, 0.08, 0.08))
		"ceiling":
			m.sphere("shade", Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), pos), 0.18, 12, glow)
			m.cylinder("iron", HarborTown.at(pos + Vector3(0, 0.1, 0)), 0.04, 0.04, 0.12, 8, Color(0.7, 0.6, 0.35))
		"pendant":
			m.sphere("shade", Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.0)), pos), 0.22, 12, glow)
			m.bar("iron", pos + Vector3(0, 0.1, 0), pos + Vector3(0, 0.9, 0), 0.008, 4, Color(0.7, 0.6, 0.35))
		_:
			m.cylinder("shade", HarborTown.at(pos), 0.22, 0.13, 0.26, 14, glow, false)
	m = keep
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, -0.12, 0)
	light.omni_range = range_m
	light.omni_attenuation = 1.3
	light.light_color = Color(1.0, 0.74, 0.45)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_RANGE
	light.distance_fade_length = 15.0
	add_child(light)
	_lights += 1
	town.lamps.append({"light": light, "thr": thr, "energy": energy})


## A fire burning in a firebox whose mouth faces along yaw: logs, the
## embers glowing, a flickering light; lit from dusk.
func _fire_at(pos: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(pos, yaw)
	for k in 3:
		m.cylinder("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0).rotated(Vector3.UP, 0.25 * k - 0.25), Vector3(0, 0.12 + 0.07 * (k % 2), -0.1 + 0.1 * k)),
			0.05, 0.05, 0.45, 6, c(Color(0.3, 0.2, 0.12), HarborTown.K_TIMBER))
	var ember := ViewUtil.glow(Color(1.0, 0.42, 0.12), 0.0)
	var embers := MeshInstance3D.new()
	var bed := BoxMesh.new()
	bed.size = Vector3(0.5, 0.05, 0.3)
	embers.mesh = bed
	embers.material_override = ember
	embers.transform = xf * HarborTown.at(Vector3(0, 0.06, 0))
	embers.visibility_range_end = DETAIL_RANGE
	add_child(embers)
	var light := OmniLight3D.new()
	light.transform = xf * HarborTown.at(Vector3(0, 0.45, 0.5))
	light.omni_range = 5.0
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 0.0
	light.shadow_enabled = false   # a shadowed point light redraws the whole merged town six times
	light.distance_fade_enabled = true
	light.distance_fade_begin = LIGHT_RANGE
	light.distance_fade_length = 15.0
	add_child(light)
	_fires.append({"light": light, "mat": ember, "lit": 0.0, "phase": _rng.randf() * 10.0})


## The fires: lit once it is dusk, flickering on two quick cycles and a
## slow one, the embers breathing with them.
func _process(delta: float) -> void:
	if _fires.is_empty():
		return
	_t += delta
	var night: float = town.glass_mat.get_shader_parameter("night")
	for fire: Dictionary in _fires:
		var t := _t + float(fire["phase"])
		fire["lit"] = move_toward(float(fire["lit"]), 1.0 if night > 0.3 else 0.0, delta * 0.2)
		var lit: float = fire["lit"]
		var flicker := 0.75 + 0.12 * sin(t * 11.0) + 0.08 * sin(t * 17.3 + 1.0) + 0.1 * sin(t * 2.1)
		var light: OmniLight3D = fire["light"]
		light.light_energy = 1.6 * flicker * lit
		light.visible = lit > 0.01
		(fire["mat"] as StandardMaterial3D).emission_energy_multiplier = (2.5 + 1.5 * flicker) * lit


## ---- furniture ---------------------------------------------------------------------

func _armchair(at_: Vector3, yaw: float, cloth: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.22, 0)), Vector3(0.75, 0.3, 0.75), cloth, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.62, -0.3)), Vector3(0.75, 0.6, 0.18), cloth, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * 0.32, 0.45, 0.02)), Vector3(0.14, 0.3, 0.7), cloth, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.42, 0.06)), Vector3(0.5, 0.12, 0.55), c(cloth * 1.1, HarborTown.K_CLOTH), true)
	_solid(xf * Vector3(0, 0.4, -0.05), Vector3(0.7, 0.8, 0.7), xf.basis)


func _table(at_: Vector3, top: Vector2, height: float, wood: Color, yaw := 0.0) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, height - 0.02, 0)), Vector3(top.x, 0.04, top.y), wood, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.box("wall", xf * HarborTown.at(Vector3(sx * (top.x / 2.0 - 0.05), (height - 0.04) / 2.0, sz * (top.y / 2.0 - 0.05))), Vector3(0.04, height - 0.04, 0.04), wood, true)
	_solid(xf * Vector3(0, height / 2.0, 0), Vector3(top.x, height, top.y), xf.basis)


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


func _bed(at_: Vector3, yaw: float, size: Vector2, quilt: Color, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.3, 0)), Vector3(size.x, 0.25, size.y), c(Color(0.9, 0.9, 0.86), HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.44, 0.1)), Vector3(size.x + 0.04, 0.06, size.y - 0.2), quilt, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.46, -size.y / 2.0 + 0.22)), Vector3(size.x - 0.2, 0.12, 0.32), c(Color(0.94, 0.93, 0.9), HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.55, -size.y / 2.0 - 0.03)), Vector3(size.x + 0.08, 1.1, 0.06), wood, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.35, size.y / 2.0 + 0.03)), Vector3(size.x + 0.08, 0.7, 0.06), wood, true)
	# A folded blanket at the foot, slippers on the floor beside.
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.49, size.y / 2.0 - 0.3)), Vector3(size.x - 0.1, 0.05, 0.3), c(quilt.lightened(0.25), HarborTown.K_CLOTH), true)
	for s: float in [-0.06, 0.06]:
		m.box("wall", xf * HarborTown.at(Vector3(size.x / 2.0 + 0.2 + s * 2.0, 0.02, -size.y / 2.0 + 0.5)), Vector3(0.09, 0.04, 0.26), c(Color(0.5, 0.2, 0.2), HarborTown.K_CLOTH), true)
	_solid(xf * Vector3(0, 0.3, 0), Vector3(size.x, 0.6, size.y), xf.basis)


## A sofa, length long, facing along yaw.
func _sofa(at_: Vector3, yaw: float, length: float, cloth: Color, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.22, 0)), Vector3(length, 0.3, 0.85), cloth, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.6, -0.32)), Vector3(length, 0.55, 0.22), cloth, true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * (length / 2.0 - 0.09), 0.42, 0)), Vector3(0.18, 0.34, 0.85), cloth, true)
	var cushions := int((length - 0.36) / 0.6)
	for k in cushions:
		var x := -(length - 0.36) / 2.0 + (k + 0.5) * (length - 0.36) / cushions
		m.box("wall", xf * HarborTown.at(Vector3(x, 0.44, 0.07)), Vector3((length - 0.36) / cushions - 0.02, 0.14, 0.7), c(cloth * 1.08, HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(-length / 2.0 + 0.4, 0.62, -0.12), 0.3), Vector3(0.35, 0.3, 0.12), c(Color(0.75, 0.62, 0.35), HarborTown.K_CLOTH), true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.box("wall", xf * HarborTown.at(Vector3(sx * (length / 2.0 - 0.1), 0.04, sz * 0.35)), Vector3(0.06, 0.08, 0.06), wood, true)
	_solid(xf * Vector3(0, 0.4, 0), Vector3(length, 0.8, 0.85), xf.basis)


## A braided or hooked rug, oval, two colours.
func _rug(at_: Vector3, size: Vector2, outer: Color, inner: Color, yaw := 0.0) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.cylinder("wall", xf * Transform3D(Basis.from_scale(Vector3(size.x / 2.0, 1.0, size.y / 2.0)), Vector3(0, 0.006, 0)), 1.0, 1.0, 0.012, 24, c(outer, HarborTown.K_CLOTH))
	m.cylinder("wall", xf * Transform3D(Basis.from_scale(Vector3(size.x / 2.0 * 0.72, 1.0, size.y / 2.0 * 0.72)), Vector3(0, 0.009, 0)), 1.0, 1.0, 0.012, 24, c(inner, HarborTown.K_CLOTH))


## A fireplace against a wall, its mouth along yaw: brick breast, the
## firebox, hearth, mantel shelf, a mirror or picture over, a clock and
## candlesticks on the shelf; the fire.
func _fireplace(at_: Vector3, yaw: float, brick: Color, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	var b := c(brick, HarborTown.K_BRICK)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.65, 0.2)), Vector3(1.7, 1.3, 0.4), b, true)
	_solid(xf * Vector3(0, 0.65, 0.2), Vector3(1.7, 1.3, 0.4), xf.basis)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.4, 0.41)), Vector3(0.8, 0.62, 0.02), c(Color(0.05, 0.04, 0.04), HarborTown.K_ENAMEL), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.02, 0.65)), Vector3(1.8, 0.04, 0.5), c(Color(0.3, 0.3, 0.32), HarborTown.K_GRANITE), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.32, 0.47)), Vector3(1.95, 0.07, 0.22), c(wood, HarborTown.K_WOOD), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.22, 0.39)), Vector3(1.9, 0.14, 0.06), c(wood, HarborTown.K_WOOD), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.9, 0.02)), Vector3(1.2, 0.8, 0.04), c(Color(0.55, 0.42, 0.2), HarborTown.K_WOOD), true)
	m.box("steel", xf * HarborTown.at(Vector3(0, 1.9, 0.045)), Vector3(1.08, 0.68, 0.01), Color.WHITE, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.46, 0.5)), Vector3(0.28, 0.22, 0.12), c(wood, HarborTown.K_WOOD), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.48, 0.56)), Vector3(0.12, 0.12, 0.01), c(Color(0.9, 0.88, 0.8), HarborTown.K_ENAMEL), true)
	for s: float in [-1.0, 1.0]:
		m.cylinder("iron", xf * HarborTown.at(Vector3(s * 0.6, 1.45, 0.5)), 0.03, 0.02, 0.2, 8, Color(0.75, 0.6, 0.3))
		m.cylinder("wall", xf * HarborTown.at(Vector3(s * 0.6, 1.62, 0.5)), 0.012, 0.012, 0.14, 6, c(Color(0.95, 0.93, 0.85), HarborTown.K_ENAMEL))
	# The fire irons in their stand.
	m.cylinder("iron", xf * HarborTown.at(Vector3(0.75, 0.35, 0.7)), 0.01, 0.01, 0.7, 4, Color(0.15, 0.15, 0.15))
	m.box("iron", xf * HarborTown.at(Vector3(0.75, 0.02, 0.7)), Vector3(0.14, 0.02, 0.14), Color(0.15, 0.15, 0.15))
	_fire_at(xf * Vector3(0, 0.02, 0.28), yaw)


## A bookcase, full, against a wall, its front along yaw.
func _bookcase(at_: Vector3, yaw: float, width: float, height: float, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, height / 2.0, 0)), Vector3(width, height, 0.34), c(wood, HarborTown.K_WOOD), true)
	_solid(xf * Vector3(0, height / 2.0, 0), Vector3(width, height, 0.34), xf.basis)
	var colors: Array[Color] = [Color(0.45, 0.12, 0.1), Color(0.12, 0.22, 0.4), Color(0.2, 0.32, 0.18), Color(0.55, 0.45, 0.25), Color(0.3, 0.2, 0.15), Color(0.6, 0.55, 0.45)]
	var shelves := int(height / 0.42)
	for shelf in shelves:
		var y := 0.12 + shelf * 0.42
		var x := -width / 2.0 + 0.05
		while x < width / 2.0 - 0.07:
			var bw := _rng.randf_range(0.025, 0.05)
			var bh := _rng.randf_range(0.2, 0.3)
			var lean := 0.0 if _rng.randf() < 0.95 else 0.2
			m.box("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), lean), Vector3(x + bw / 2.0, y + bh / 2.0, 0.18)), Vector3(bw, bh, 0.2), c(colors[_rng.randi() % colors.size()], HarborTown.K_CLOTH), true)
			x += bw + 0.003
		m.box("wall", xf * HarborTown.at(Vector3(0, y - 0.02, 0.18)), Vector3(width - 0.06, 0.03, 0.02), c(wood, HarborTown.K_WOOD), true)


## A console radio, its dial lighting when the evening comes.
func _radio(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.52, 0)), Vector3(0.78, 1.04, 0.4), c(Color(0.36, 0.2, 0.1), HarborTown.K_WOOD), true)
	_solid(xf * Vector3(0, 0.52, 0), Vector3(0.78, 1.04, 0.4), xf.basis)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.42, 0.205)), Vector3(0.56, 0.5, 0.01), c(Color(0.55, 0.45, 0.3), HarborTown.K_CLOTH), true)
	for k in 5:
		m.box("wall", xf * HarborTown.at(Vector3(0, 0.22 + 0.1 * k, 0.212)), Vector3(0.58, 0.012, 0.012), c(Color(0.3, 0.16, 0.08), HarborTown.K_WOOD), true)
	m.cylinder("shade", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.85, 0.205)), 0.09, 0.09, 0.01, 16, Color(_rng.randf_range(0.4, 0.6), 0.5, 0.0, 1.0))
	for s: float in [-1.0, 1.0]:
		m.cylinder("wall", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(s * 0.25, 0.85, 0.215)), 0.025, 0.025, 0.03, 8, c(Color(0.2, 0.12, 0.06), HarborTown.K_WOOD))


## An upright piano against a wall, the lid down, music on the rest.
func _piano(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	var wood := c(Color(0.18, 0.1, 0.06), HarborTown.K_WOOD)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.65, 0)), Vector3(1.5, 1.3, 0.6), wood, true)
	_solid(xf * Vector3(0, 0.65, 0.1), Vector3(1.5, 1.3, 0.8), xf.basis)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.72, 0.38)), Vector3(1.4, 0.06, 0.28), wood, true)
	for k in 36:
		m.box("wall", xf * HarborTown.at(Vector3(-0.66 + 0.037 * k, 0.765, 0.42)), Vector3(0.033, 0.02, 0.2), c(Color(0.93, 0.91, 0.84), HarborTown.K_ENAMEL), true)
	for k in 25:
		if k % 7 == 2 or k % 7 == 6:
			continue
		m.box("wall", xf * HarborTown.at(Vector3(-0.64 + 0.052 * k, 0.785, 0.37)), Vector3(0.02, 0.02, 0.11), c(Color(0.05, 0.05, 0.05), HarborTown.K_ENAMEL), true)
	m.box("wall", xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.98, 0.33)), Vector3(0.45, 0.3, 0.01), c(Color(0.92, 0.9, 0.82), HarborTown.K_CLOTH), true)
	for s: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s * 0.62, 0.3, 0.4)), Vector3(0.06, 0.6, 0.06), wood, true)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.25, 1.0)), Vector3(0.8, 0.5, 0.35), wood, true)
	m.cylinder("wall", xf * HarborTown.at(Vector3(0.45, 1.36, -0.05)), 0.06, 0.08, 0.14, 10, c(Color(0.3, 0.45, 0.6), HarborTown.K_ENAMEL))
	_picture(xf * Vector3(0, 1.75, -0.28), yaw, Vector2(0.4, 0.5), Color(0.5, 0.45, 0.35))


## A dresser with a mirror, a brush and a jewel box on its top.
func _dresser(at_: Vector3, yaw: float, wood: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	var w := c(wood, HarborTown.K_WOOD)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.45, 0)), Vector3(1.1, 0.9, 0.5), w, true)
	_solid(xf * Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 0.5), xf.basis)
	for k in 3:
		m.box("wall", xf * HarborTown.at(Vector3(0, 0.18 + 0.26 * k, 0.255)), Vector3(1.0, 0.22, 0.01), c(wood * 0.85, HarborTown.K_WOOD), true)
		for s: float in [-1.0, 1.0]:
			m.sphere("iron", xf * HarborTown.at(Vector3(s * 0.3, 0.18 + 0.26 * k, 0.27)), 0.018, 6, Color(0.7, 0.58, 0.3))
	m.box("wall", xf * HarborTown.at(Vector3(0, 1.35, -0.2)), Vector3(0.8, 0.9, 0.04), w, true)
	m.box("steel", xf * HarborTown.at(Vector3(0, 1.35, -0.175)), Vector3(0.68, 0.78, 0.01), Color.WHITE, true)
	m.box("wall", xf * HarborTown.at(Vector3(-0.3, 0.93, 0.05)), Vector3(0.18, 0.06, 0.12), c(Color(0.55, 0.2, 0.25), HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0.25, 0.91, 0.08), 0.4), Vector3(0.22, 0.02, 0.06), c(Color(0.3, 0.2, 0.12), HarborTown.K_WOOD), true)
	m.cylinder("wall", xf * HarborTown.at(Vector3(0.4, 0.97, -0.05)), 0.03, 0.04, 0.14, 8, c(Color(0.85, 0.85, 0.9), HarborTown.K_ENAMEL))


## A nightstand with its lamp, a book and a glass of water.
func _nightstand(at_: Vector3, yaw: float, wood: Color, thr: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	_table(at_, Vector2(0.42, 0.4), 0.62, c(wood, HarborTown.K_WOOD), yaw)
	m.cylinder("wall", xf * HarborTown.at(Vector3(0, 0.74, -0.05)), 0.06, 0.08, 0.24, 10, c(Color(0.8, 0.78, 0.7), HarborTown.K_ENAMEL))
	_lamp_fixture(xf * Vector3(0, 0.98, -0.05), "shade", thr, 0.4, 3.5)
	m.box("wall", xf * HarborTown.at(Vector3(0.08, 0.635, 0.1), 0.3), Vector3(0.14, 0.03, 0.2), c(Color(0.4, 0.15, 0.12), HarborTown.K_CLOTH), true)
	m.cylinder("clear", xf * HarborTown.at(Vector3(-0.12, 0.68, 0.1)), 0.03, 0.03, 0.1, 8, Color.WHITE)


## A kitchen range in white enamel on legs, facing along yaw.
func _range(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	var white := Color(0.92, 0.91, 0.87)
	m.box("iron", xf * HarborTown.at(Vector3(0, 0.55, 0)), Vector3(1.0, 0.6, 0.66), white)
	_solid(xf * Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 0.66), xf.basis)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.cylinder("iron", xf * HarborTown.at(Vector3(sx * 0.44, 0.12, sz * 0.27)), 0.03, 0.03, 0.24, 6, Color(0.1, 0.1, 0.1))
	for k in 4:
		m.cylinder("iron", xf * HarborTown.at(Vector3(-0.2 + 0.4 * (k % 2), 0.86, -0.12 + 0.24 * (k / 2))), 0.09, 0.09, 0.02, 12, Color(0.12, 0.12, 0.12))
	m.box("iron", xf * HarborTown.at(Vector3(0.25, 0.52, 0.335)), Vector3(0.42, 0.4, 0.02), Color(0.85, 0.84, 0.8))
	m.box("iron", xf * HarborTown.at(Vector3(0.25, 0.7, 0.35)), Vector3(0.3, 0.03, 0.03), Color(0.7, 0.7, 0.7))
	m.box("iron", xf * HarborTown.at(Vector3(0, 1.1, -0.3)), Vector3(1.0, 0.45, 0.06), white)
	m.cylinder("iron", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 1.15, -0.26)), 0.07, 0.07, 0.02, 14, Color(0.15, 0.15, 0.15))
	# A kettle on a burner, a pot on another.
	m.cylinder("iron", xf * HarborTown.at(Vector3(-0.2, 0.95, -0.12)), 0.09, 0.11, 0.16, 12, Color(0.75, 0.2, 0.15))
	m.bar("iron", xf * Vector3(-0.28, 1.05, -0.12), xf * Vector3(-0.12, 1.05, -0.12), 0.01, 4, Color(0.1, 0.1, 0.1))
	m.cylinder("steel", xf * HarborTown.at(Vector3(0.2, 0.95, 0.12)), 0.12, 0.12, 0.16, 12, Color.WHITE)


## A monitor-top refrigerator, its compressor in a drum on top.
func _fridge(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	var white := Color(0.92, 0.91, 0.87)
	m.box("iron", xf * HarborTown.at(Vector3(0, 0.76, 0)), Vector3(0.66, 1.44, 0.66), white)
	_solid(xf * Vector3(0, 0.9, 0), Vector3(0.66, 1.8, 0.66), xf.basis)
	m.cylinder("iron", xf * HarborTown.at(Vector3(0, 1.64, 0)), 0.26, 0.26, 0.3, 16, white)
	for k in 12:
		var a := TAU * k / 12.0
		m.box("iron", xf * HarborTown.at(Vector3(cos(a) * 0.265, 1.64, sin(a) * 0.265)), Vector3(0.01, 0.26, 0.01), Color(0.7, 0.7, 0.68))
	m.box("iron", xf * HarborTown.at(Vector3(0.2, 1.04, 0.34)), Vector3(0.06, 0.2, 0.04), Color(0.72, 0.72, 0.7))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.cylinder("iron", xf * HarborTown.at(Vector3(sx * 0.28, 0.02, sz * 0.28)), 0.03, 0.03, 0.04, 6, Color(0.1, 0.1, 0.1))


## A sink counter length long against a wall: cabinets under, the enamel
## sink with its drainboards, the faucet, a dish rack with plates, soap.
func _sink_counter(at_: Vector3, yaw: float, length: float, cabinet: Color, top: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.43, 0)), Vector3(length, 0.86, 0.6), c(cabinet, HarborTown.K_ENAMEL), true)
	_solid(xf * Vector3(0, 0.45, 0), Vector3(length, 0.9, 0.6), xf.basis)
	var doors := int(length / 0.5)
	for k in doors:
		var x := -length / 2.0 + (k + 0.5) * length / doors
		m.box("wall", xf * HarborTown.at(Vector3(x, 0.42, 0.302)), Vector3(length / doors - 0.04, 0.7, 0.01), c(cabinet * 0.95, HarborTown.K_ENAMEL), true)
		m.box("iron", xf * HarborTown.at(Vector3(x + 0.15, 0.62, 0.31)), Vector3(0.02, 0.08, 0.02), Color(0.2, 0.2, 0.2))
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.88, 0)), Vector3(length + 0.04, 0.04, 0.64), c(top, HarborTown.K_LINO), true)
	m.box("iron", xf * HarborTown.at(Vector3(0, 0.84, 0.02)), Vector3(0.6, 0.12, 0.45), Color(0.92, 0.91, 0.87))
	m.box("iron", xf * HarborTown.at(Vector3(0, 0.86, 0.02)), Vector3(0.5, 0.1, 0.36), Color(0.75, 0.75, 0.72))
	m.bar("steel", xf * Vector3(0, 0.9, -0.24), xf * Vector3(0, 1.12, -0.22), 0.015, 6, Color.WHITE)
	m.bar("steel", xf * Vector3(0, 1.12, -0.22), xf * Vector3(0, 1.08, -0.06), 0.015, 6, Color.WHITE)
	for s: float in [-1.0, 1.0]:
		m.cylinder("steel", xf * HarborTown.at(Vector3(s * 0.12, 0.95, -0.25)), 0.025, 0.025, 0.05, 8, Color.WHITE)
	var rack := xf * HarborTown.at(Vector3(0.6, 0.9, 0.0))
	for k in 4:
		m.cylinder("wall", rack * Transform3D(Basis(Vector3.RIGHT, PI / 2.0 - 0.2), Vector3(-0.15 + 0.1 * k, 0.12, 0)), 0.11, 0.11, 0.012, 14, c(Color(0.93, 0.92, 0.88), HarborTown.K_ENAMEL))
	m.box("wall", xf * HarborTown.at(Vector3(-0.45, 0.93, -0.2)), Vector3(0.08, 0.05, 0.05), c(Color(0.9, 0.8, 0.5), HarborTown.K_ENAMEL), true)


## Wall cabinets over a counter, length long, at height y.
func _wall_cabinets(at_: Vector3, yaw: float, length: float, cabinet: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf, Vector3(length, 0.75, 0.34), c(cabinet, HarborTown.K_ENAMEL), true)
	var doors := int(length / 0.45)
	for k in doors:
		var x := -length / 2.0 + (k + 0.5) * length / doors
		m.box("wall", xf * HarborTown.at(Vector3(x, 0, 0.172)), Vector3(length / doors - 0.04, 0.68, 0.01), c(cabinet * 0.95, HarborTown.K_ENAMEL), true)
		m.box("iron", xf * HarborTown.at(Vector3(x + 0.13, -0.25, 0.18)), Vector3(0.02, 0.08, 0.02), Color(0.2, 0.2, 0.2))


## A kitchen table with an oilcloth and its chairs, a bowl on it.
func _kitchen_table(at_: Vector3, cloth: Color, wood: Color) -> void:
	_table(at_, Vector2(1.0, 0.75), 0.76, c(wood, HarborTown.K_ENAMEL))
	_box("wall", at_ + Vector3(0, 0.765, 0), Vector3(1.04, 0.01, 0.79), c(cloth, HarborTown.K_LINO))
	for s: float in [-1.0, 1.0]:
		_chair(at_ + Vector3(s * 0.62, 0, 0), -s * PI / 2.0, c(wood, HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0.15, 0.82, -0.1)), 0.07, 0.06, 0.1, 10, c(Color(0.25, 0.45, 0.35), HarborTown.K_ENAMEL))
	for k in 3:
		m.sphere("wall", HarborTown.at(at_ + Vector3(0.12 + 0.05 * (k % 2), 0.88, -0.1 + 0.04 * k)), 0.035, 8, c(Color(0.85, 0.65, 0.15), HarborTown.K_ENAMEL))


## A dining table set: the table, four chairs, places laid, a centrepiece.
func _dining_set(at_: Vector3, wood: Color, cloth: Variant) -> void:
	_table(at_, Vector2(1.5, 0.9), 0.76, c(wood, HarborTown.K_WOOD))
	if cloth is Color:
		_box("wall", at_ + Vector3(0, 0.765, 0), Vector3(1.6, 0.01, 1.0), c(cloth as Color, HarborTown.K_CLOTH))
	for s: float in [-1.0, 1.0]:
		for x: float in [-0.4, 0.4]:
			_chair(at_ + Vector3(x, 0, s * 0.62), 0.0 if s < 0.0 else PI, c(wood, HarborTown.K_WOOD))
			m.cylinder("wall", HarborTown.at(at_ + Vector3(x, 0.775, s * 0.28)), 0.12, 0.1, 0.012, 14, c(Color(0.93, 0.92, 0.88), HarborTown.K_ENAMEL))
			m.box("steel", HarborTown.at(at_ + Vector3(x + 0.16, 0.775, s * 0.28)), Vector3(0.015, 0.005, 0.18), Color.WHITE)
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.83, 0)), 0.13, 0.08, 0.1, 14, c(Color(0.6, 0.62, 0.7), HarborTown.K_ENAMEL))
	for k in 5:
		m.sphere("wall", HarborTown.at(at_ + Vector3(-0.05 + 0.05 * (k % 3), 0.9 + 0.03 * (k / 3), -0.03 + 0.04 * (k % 2))), 0.04, 8, c(Color(0.62, 0.1, 0.08), HarborTown.K_ENAMEL))


## A clawfoot tub, a pedestal sink with the medicine cabinet over it, a
## toilet, a towel on its bar; the tub along x from at_.
func _bath_fixtures(tub: Vector3, tub_yaw: float, sink: Vector3, sink_yaw: float, wc: Vector3, wc_yaw: float) -> void:
	var white := Color(0.94, 0.93, 0.9)
	var t := HarborTown.at(tub, tub_yaw)
	m.box("iron", t * HarborTown.at(Vector3(0, 0.42, 0)), Vector3(1.5, 0.45, 0.72), white)
	m.box("iron", t * HarborTown.at(Vector3(0, 0.55, 0)), Vector3(1.36, 0.22, 0.58), Color(0.8, 0.8, 0.78))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.sphere("iron", t * HarborTown.at(Vector3(sx * 0.6, 0.1, sz * 0.26)), 0.07, 8, Color(0.75, 0.6, 0.3))
	m.bar("steel", t * Vector3(-0.72, 0.68, 0), t * Vector3(-0.62, 0.78, 0), 0.015, 6, Color.WHITE)
	_solid(t * Vector3(0, 0.35, 0), Vector3(1.5, 0.7, 0.72), t.basis)
	var s := HarborTown.at(sink, sink_yaw)
	m.cylinder("iron", s * HarborTown.at(Vector3(0, 0.38, 0)), 0.1, 0.14, 0.76, 12, white)
	m.box("iron", s * HarborTown.at(Vector3(0, 0.82, 0)), Vector3(0.55, 0.14, 0.42), white)
	m.box("steel", s * HarborTown.at(Vector3(0, 1.55, -0.18)), Vector3(0.45, 0.6, 0.04), Color.WHITE)
	m.box("wall", s * HarborTown.at(Vector3(0.5, 1.1, -0.18)), Vector3(0.5, 0.02, 0.03), c(Color(0.7, 0.7, 0.7), HarborTown.K_ENAMEL), true)
	m.box("wall", s * HarborTown.at(Vector3(0.5, 0.85, -0.16)), Vector3(0.4, 0.5, 0.02), c(Color(0.55, 0.7, 0.8), HarborTown.K_CLOTH), true)
	var w := HarborTown.at(wc, wc_yaw)
	m.cylinder("iron", w * HarborTown.at(Vector3(0, 0.2, 0.05)), 0.17, 0.13, 0.4, 14, white)
	m.box("iron", w * HarborTown.at(Vector3(0, 0.65, -0.25)), Vector3(0.45, 0.42, 0.2), white)
	m.box("wall", w * HarborTown.at(Vector3(0, 0.42, 0.05)), Vector3(0.38, 0.03, 0.42), c(Color(0.3, 0.2, 0.12), HarborTown.K_WOOD), true)


## A wall clock, a calendar, a coat rack: the small things of a room.
func _wall_clock(centre: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(centre, yaw)
	m.cylinder("wall", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 0.02)), 0.14, 0.14, 0.04, 16, c(Color(0.4, 0.25, 0.12), HarborTown.K_WOOD))
	m.cylinder("wall", xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 0.042)), 0.12, 0.12, 0.005, 16, c(Color(0.94, 0.92, 0.85), HarborTown.K_ENAMEL))
	m.box("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), 0.9), Vector3(0.03, 0.02, 0.047)), Vector3(0.012, 0.08, 0.004), c(Color(0.05, 0.05, 0.05), HarborTown.K_ENAMEL))
	m.box("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), -0.3), Vector3(-0.01, 0.04, 0.048)), Vector3(0.01, 0.1, 0.004), c(Color(0.05, 0.05, 0.05), HarborTown.K_ENAMEL))


## A vase of flowers.
func _vase(at_: Vector3, bloom: Color) -> void:
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.1, 0)), 0.05, 0.07, 0.2, 10, c(Color(0.35, 0.5, 0.65), HarborTown.K_ENAMEL))
	for k in 6:
		var a := TAU * k / 6.0
		var tip := at_ + Vector3(cos(a) * 0.1, 0.35 + 0.04 * (k % 2), sin(a) * 0.1)
		m.bar("wall", at_ + Vector3(0, 0.18, 0), tip, 0.004, 3, c(Color(0.2, 0.35, 0.15), HarborTown.K_CLOTH))
		m.sphere("wall", HarborTown.at(tip), 0.035, 6, c(bloom, HarborTown.K_CLOTH))


## ---- signs of life -----------------------------------------------------------------

## The evening paper, folded, left where it was read.
func _newspaper(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.008, 0)), Vector3(0.3, 0.016, 0.42), c(Color(0.86, 0.84, 0.78), HarborTown.K_CLOTH), true)
	for k in 5:
		m.box("wall", xf * HarborTown.at(Vector3(-0.06 + 0.04 * (k % 2), 0.017, -0.15 + 0.07 * k)), Vector3(0.16, 0.002, 0.03), c(Color(0.35, 0.35, 0.35), HarborTown.K_CLOTH), true)


## A cup on its saucer.
func _cup(at_: Vector3) -> void:
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.005, 0)), 0.07, 0.06, 0.01, 12, c(Color(0.93, 0.92, 0.88), HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.045, 0)), 0.04, 0.03, 0.07, 12, c(Color(0.93, 0.92, 0.88), HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.078, 0)), 0.036, 0.036, 0.004, 12, c(Color(0.25, 0.15, 0.08), HarborTown.K_ENAMEL))


## A book, shut or lying open face down.
func _book(at_: Vector3, yaw: float, open: bool, cover: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	if open:
		for s2: float in [-1.0, 1.0]:
			m.box("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), s2 * 0.25), Vector3(s2 * 0.075, 0.02, 0)), Vector3(0.15, 0.02, 0.22), c(cover, HarborTown.K_CLOTH), true)
	else:
		m.box("wall", xf * HarborTown.at(Vector3(0, 0.02, 0)), Vector3(0.16, 0.04, 0.23), c(cover, HarborTown.K_CLOTH), true)
		m.box("wall", xf * HarborTown.at(Vector3(0.005, 0.02, 0)), Vector3(0.15, 0.03, 0.22), c(Color(0.92, 0.9, 0.82), HarborTown.K_CLOTH), true)


## A knitting basket, yarn and needles.
func _knitting(at_: Vector3) -> void:
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.13, 0)), 0.2, 0.16, 0.26, 12, c(Color(0.6, 0.48, 0.3), HarborTown.K_TIMBER))
	var yarns: Array[Color] = [Color(0.7, 0.2, 0.2), Color(0.25, 0.35, 0.6), Color(0.85, 0.8, 0.6)]
	for k in 3:
		m.sphere("wall", HarborTown.at(at_ + Vector3(-0.07 + 0.07 * k, 0.28, 0.03 * (k - 1))), 0.06, 8, c(yarns[k], HarborTown.K_CLOTH))
	for s2: float in [-1.0, 1.0]:
		m.bar("iron", at_ + Vector3(0.0, 0.26, 0.05 * s2), at_ + Vector3(0.12, 0.5, 0.08 * s2), 0.004, 3, Color(0.6, 0.6, 0.6))


## A pair of shoes by the door.
func _shoes(at_: Vector3, yaw: float, leather: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	for s2: float in [-1.0, 1.0]:
		m.box("wall", xf * HarborTown.at(Vector3(s2 * 0.07, 0.035, 0)), Vector3(0.1, 0.07, 0.28), c(leather, HarborTown.K_WOOD), true)
		m.box("wall", xf * HarborTown.at(Vector3(s2 * 0.07, 0.075, -0.06)), Vector3(0.09, 0.03, 0.13), c(leather * 1.1, HarborTown.K_WOOD), true)


## A man's hat.
func _hat(at_: Vector3, felt := Color(0.3, 0.26, 0.22)) -> void:
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.01, 0)), 0.17, 0.17, 0.012, 16, c(felt, HarborTown.K_CLOTH))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.07, 0)), 0.1, 0.11, 0.11, 12, c(felt, HarborTown.K_CLOTH))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.035, 0)), 0.112, 0.112, 0.025, 12, c(Color(0.12, 0.1, 0.08), HarborTown.K_CLOTH))


## A dog asleep, curled, its nose on its paws.
func _dog(at_: Vector3, yaw: float, fur: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	var f := c(fur, HarborTown.K_CLOTH)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.5)), Vector3(0, 0.14, 0)), 0.24, 10, f)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(0.9, 0.8, 1.2)), Vector3(0.18, 0.1, 0.28)), 0.1, 8, f)
	m.sphere("wall", xf * HarborTown.at(Vector3(0.2, 0.08, 0.4)), 0.05, 6, c(fur.darkened(0.3), HarborTown.K_CLOTH))
	for s2: float in [-1.0, 1.0]:
		m.box("wall", xf * Transform3D(Basis(Vector3(0, 0, 1), s2 * 0.5), Vector3(0.18 + s2 * 0.08, 0.17, 0.24)), Vector3(0.03, 0.12, 0.08), c(fur.darkened(0.2), HarborTown.K_CLOTH), true)
	m.bar("wall", xf * Vector3(-0.1, 0.06, -0.3), xf * Vector3(0.25, 0.05, -0.25), 0.03, 5, f)
	m.cylinder("wall", xf * HarborTown.at(Vector3(0, 0.01, 0)), 0.45, 0.45, 0.02, 16, c(Color(0.45, 0.2, 0.2), HarborTown.K_CLOTH))


## A pie cooling on a counter.
func _pie(at_: Vector3) -> void:
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.02, 0)), 0.14, 0.11, 0.04, 16, c(Color(0.85, 0.6, 0.3), HarborTown.K_ENAMEL))
	m.cylinder("wall", HarborTown.at(at_ + Vector3(0, 0.045, 0)), 0.12, 0.13, 0.015, 16, c(Color(0.8, 0.55, 0.28), HarborTown.K_CLOTH))
	for k in 4:
		m.box("wall", HarborTown.at(at_ + Vector3(-0.09 + 0.06 * k, 0.055, 0)), Vector3(0.015, 0.008, 0.22), c(Color(0.88, 0.66, 0.36), HarborTown.K_CLOTH))
		m.box("wall", HarborTown.at(at_ + Vector3(0, 0.058, -0.09 + 0.06 * k)), Vector3(0.22, 0.008, 0.015), c(Color(0.88, 0.66, 0.36), HarborTown.K_CLOTH))


## A loaf of bread on its board.
func _bread(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.01, 0)), Vector3(0.36, 0.02, 0.22), c(Color(0.6, 0.45, 0.28), HarborTown.K_WOOD), true)
	m.sphere("wall", xf * Transform3D(Basis.from_scale(Vector3(1.6, 0.7, 0.85)), Vector3(0, 0.06, 0)), 0.09, 8, c(Color(0.75, 0.5, 0.25), HarborTown.K_CLOTH))


## An apron hung on a hook on a wall facing along yaw.
func _apron(at_: Vector3, yaw: float, cloth: Color) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("iron", xf * HarborTown.at(Vector3(0, 0.02, 0.02)), Vector3(0.02, 0.02, 0.04), Color(0.3, 0.3, 0.3))
	m.box("wall", xf * HarborTown.at(Vector3(0, -0.3, 0.035)), Vector3(0.36, 0.55, 0.01), c(cloth, HarborTown.K_CLOTH), true)
	m.box("wall", xf * HarborTown.at(Vector3(0, -0.4, 0.042)), Vector3(0.2, 0.14, 0.005), c(cloth.lightened(0.2), HarborTown.K_CLOTH), true)


## A child's things on the floor: blocks, a toy truck.
func _toys(at_: Vector3) -> void:
	var colours: Array[Color] = [Color(0.8, 0.2, 0.15), Color(0.2, 0.4, 0.7), Color(0.85, 0.7, 0.2), Color(0.25, 0.55, 0.3)]
	for k in 7:
		var p := at_ + Vector3(_rng.randf_range(-0.3, 0.3), 0.03 + (0.06 if k > 4 else 0.0), _rng.randf_range(-0.3, 0.3))
		m.box("wall", HarborTown.at(p, _rng.randf_range(0.0, 1.0)), Vector3(0.06, 0.06, 0.06), c(colours[k % 4], HarborTown.K_PAINT), true)
	var truck := HarborTown.at(at_ + Vector3(0.45, 0, 0.1), 0.6)
	m.box("iron", truck * HarborTown.at(Vector3(0, 0.07, 0)), Vector3(0.12, 0.06, 0.3), Color(0.7, 0.15, 0.1))
	m.box("iron", truck * HarborTown.at(Vector3(0, 0.12, 0.08)), Vector3(0.11, 0.06, 0.1), Color(0.7, 0.15, 0.1))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.cylinder("iron", truck * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(sx * 0.065, 0.03, sz * 0.1)), 0.03, 0.03, 0.02, 8, Color(0.1, 0.1, 0.1))


## A treadle sewing machine, black and gold on its iron stand.
func _sewing_machine(at_: Vector3, yaw: float) -> void:
	var xf := HarborTown.at(at_, yaw)
	m.box("wall", xf * HarborTown.at(Vector3(0, 0.74, 0)), Vector3(0.9, 0.04, 0.45), c(Color(0.42, 0.26, 0.14), HarborTown.K_WOOD), true)
	for s2: float in [-1.0, 1.0]:
		m.box("iron", xf * HarborTown.at(Vector3(s2 * 0.38, 0.36, 0)), Vector3(0.04, 0.72, 0.38), Color(0.1, 0.1, 0.1))
	m.box("iron", xf * Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.08, 0.05)), Vector3(0.55, 0.02, 0.28), Color(0.1, 0.1, 0.1))
	m.box("iron", xf * HarborTown.at(Vector3(0.05, 0.82, 0)), Vector3(0.36, 0.1, 0.14), Color(0.05, 0.05, 0.05))
	m.box("iron", xf * HarborTown.at(Vector3(0.2, 0.95, 0)), Vector3(0.08, 0.24, 0.12), Color(0.05, 0.05, 0.05))
	m.box("iron", xf * HarborTown.at(Vector3(0.0, 1.05, 0)), Vector3(0.44, 0.08, 0.1), Color(0.05, 0.05, 0.05))
	m.box("iron", xf * HarborTown.at(Vector3(0.0, 1.05, 0.051)), Vector3(0.3, 0.02, 0.002), Color(0.75, 0.6, 0.25))
	m.cylinder("iron", xf * Transform3D(Basis(Vector3(0, 0, 1), PI / 2.0), Vector3(0.27, 0.98, 0)), 0.06, 0.06, 0.03, 12, Color(0.4, 0.4, 0.4))
	m.cylinder("wall", xf * HarborTown.at(Vector3(-0.25, 0.8, 0.1)), 0.03, 0.03, 0.06, 8, c(Color(0.7, 0.2, 0.2), HarborTown.K_CLOTH))
	_solid(xf * Vector3(0, 0.5, 0), Vector3(0.9, 1.0, 0.45), xf.basis)


## A tumbler with two toothbrushes on a basin.
func _toothbrushes(at_: Vector3) -> void:
	m.cylinder("clear", HarborTown.at(at_ + Vector3(0, 0.05, 0)), 0.03, 0.028, 0.1, 10, Color.WHITE)
	for k in 2:
		m.bar("wall", at_ + Vector3(0.0, 0.02, 0.0), at_ + Vector3(-0.02 + 0.04 * k, 0.17, 0.01), 0.006, 4, c([Color(0.8, 0.2, 0.2), Color(0.2, 0.5, 0.3)][k], HarborTown.K_ENAMEL))

