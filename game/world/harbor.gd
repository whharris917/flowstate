class_name Harbor
extends Node3D
## The harbour's boats and the bell buoy: art, no records, moved by
## the sea. Lobster boats lie at their moorings downwind of the ball,
## bow to the wind, swinging slowly; a dragger lies alongside the
## T-head; two dories are tied to a float that rises and falls with the
## tide at the foot of a gangway. Each rides the swell: its heave, pitch
## and roll are read off the wave trains the sea shader draws, sampled
## at bow and stern, port and starboard, so a long boat pitches less
## than a short one and every boat moves with the water it sits on.
##
## Out past the cove's mouth a bell buoy rolls. Its tilt follows the
## water's slope through its own roll period; a clapper hangs inside
## the bell as a free pendulum from the top of the tower, and the bell
## sounds when the clapper strikes it, as hard as it struck. In a calm
## it seldom rings; in a sea it rings irregularly, as a real one does.
## A red light on top flashes every four seconds after dark.

const WAVES: Array = [
	# direction the train travels, wavelength m, amplitude m, scaled by the swell
	[Vector2(-0.7071, -0.7071), 24.0, 0.32, true],
	[Vector2(-0.9701, -0.2425), 9.5, 0.14, true],
	[Vector2(-0.2873, -0.9578), 4.6, 0.07, false],
]
const SHELTER := 0.55       # how much of the open sea's swell reaches the moorings
const GANGWAY := 7.0        # the gangway's length, m

var coast: TownCoast
var town: HarborTown
var swell := 1.0            # the weather's
var wind_dir := Vector2(-0.7071, -0.7071)   # where the wind blows toward
var night := 0.0
var bell_strikes := 0
var _t := 0.0
var _boats: Array[Dictionary] = []
var _float: Node3D
var _gangway: Node3D
var _buoy: Node3D
var _buoy_tilt := Vector2.ZERO
var _buoy_rate := Vector2.ZERO
var _clapper := Vector2.ZERO
var _clapper_rate := Vector2.ZERO
var _buoy_lamp: StandardMaterial3D
var _buoy_light: OmniLight3D
var _bell_audio: AudioStreamPlayer3D
var _last_ring := 0.0
var _hull_mat: StandardMaterial3D


## The water's height and slope at p, t seconds on: (h, dh/dx, dh/dz).
static func wave(p: Vector2, t: float, swell_: float) -> Vector3:
	var out := Vector3.ZERO
	for w: Array in WAVES:
		var dir: Vector2 = w[0]
		var k := TAU / float(w[1])
		var amp := float(w[2]) * (swell_ if bool(w[3]) else 1.0)
		var ph := dir.dot(p) * k - t * sqrt(9.81 * k)
		out.x += amp * sin(ph)
		out.y += amp * k * cos(ph) * dir.x
		out.z += amp * k * cos(ph) * dir.y
	return out


func build(c: TownCoast, t: HarborTown) -> void:
	coast = c
	town = t
	name = "Harbor"
	_hull_mat = StandardMaterial3D.new()
	_hull_mat.vertex_color_use_as_albedo = true
	_hull_mat.vertex_color_is_srgb = true
	_hull_mat.roughness = 0.4
	_hull_mat.clearcoat_enabled = true
	_hull_mat.clearcoat = 0.4
	_hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 1941
	# Lobster boats on their moorings in the cove.
	var hulls: Array[Color] = [Color(0.92, 0.91, 0.87), Color(0.92, 0.91, 0.87), Color(0.22, 0.42, 0.44), Color(0.30, 0.40, 0.28)]
	var cabins: Array[Color] = [Color(0.92, 0.91, 0.87), Color(0.62, 0.72, 0.78), Color(0.90, 0.86, 0.72), Color(0.92, 0.91, 0.87)]
	var moorings: Array[Vector2] = [Vector2(-6.0, 130.0), Vector2(-50.0, 134.0), Vector2(-26.0, 146.0), Vector2(-62.0, 118.0)]
	for k in moorings.size():
		var node := _lobster_boat(hulls[k], cabins[k], rng)
		_boats.append({"node": node, "mooring": moorings[k], "rode": 9.0 + rng.randf_range(-1.5, 1.5),
			"length": 10.5, "beam": 3.4, "phase": rng.randf() * TAU, "roll_gain": 1.4})
		_mooring_ball(moorings[k], k)
	# The dragger alongside the T-head's south face, bow east.
	var dragger := _dragger()
	_boats.append({"node": dragger, "tied": Vector2(-30.0, TownCoast.HEAD_Z.y + 3.2), "yaw": 0.0,
		"length": 16.0, "beam": 5.0, "phase": 1.0, "roll_gain": 0.8})
	# The float and its gangway; two dories tied to the float.
	_build_float()
	for k in 2:
		var dory := _dory([Color(0.80, 0.72, 0.52), Color(0.36, 0.48, 0.40)][k])
		_boats.append({"node": dory, "tied": Vector2(-6.9, 112.5 + 7.0 * k), "yaw": -PI / 2.0,
			"length": 5.0, "beam": 1.6, "phase": 2.0 + k, "roll_gain": 2.0})
	_build_buoy()


## ---- the hulls -------------------------------------------------------------

## A hull lofted from sections: stern at -x, bow at +x, the waterline at
## y = 0. Bottom paint below it, a dark boot top, then the topsides in
## hull colour to the sheer; a transom aft. Returns the mesh.
func _hull(length: float, beam: float, draft: float, free_aft: float, free_fwd: float, topside: Color,
		sole: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var bands: Array = [[-1.0, 0.0, Color(0.50, 0.14, 0.10)], [0.0, 0.16, Color(0.10, 0.10, 0.10)], [0.16, 99.0, topside]]
	var station := func(t: float, y: float) -> Vector3:
		var b := beam / 2.0 * (0.80 + 0.20 * sin(minf(t / 0.45, 1.0) * PI / 2.0))
		if t > 0.5:
			b *= sqrt(maxf(0.0, 1.0 - pow((t - 0.5) / 0.5, 2.0)))
		var d := draft * (1.0 if t < 0.65 else 1.0 - 0.75 * pow((t - 0.65) / 0.35, 1.4))
		var frac := clampf((y + d) / (d * 1.1 + 0.25), 0.0, 1.0)
		var w := b * (1.0 - pow(1.0 - frac, 2.2)) * (1.0 + 0.05 * maxf(y, 0.0))
		return Vector3(-length / 2.0 + length * t, y, w)
	var keel := func(t: float) -> float:
		return -draft * (1.0 if t < 0.65 else 1.0 - 0.75 * pow((t - 0.65) / 0.35, 1.4))
	var sheer := func(t: float) -> float:
		return free_aft + (free_fwd - free_aft) * t * t
	for band: Array in bands:
		var col: Color = band[2]
		var levels := 3
		for i in n:
			var t0 := float(i) / n
			var t1 := float(i + 1) / n
			var y00 := clampf(float(band[0]), keel.call(t0), sheer.call(t0))
			var y01 := clampf(float(band[1]), keel.call(t0), sheer.call(t0))
			var y10 := clampf(float(band[0]), keel.call(t1), sheer.call(t1))
			var y11 := clampf(float(band[1]), keel.call(t1), sheer.call(t1))
			if float(band[0]) < -0.5:
				y00 = keel.call(t0)
				y10 = keel.call(t1)
			for k in levels:
				var ya0 := lerpf(y00, y01, float(k) / levels)
				var yb0 := lerpf(y00, y01, float(k + 1) / levels)
				var ya1 := lerpf(y10, y11, float(k) / levels)
				var yb1 := lerpf(y10, y11, float(k + 1) / levels)
				for side: float in [-1.0, 1.0]:
					var p00: Vector3 = station.call(t0, ya0)
					var p01: Vector3 = station.call(t0, yb0)
					var p10: Vector3 = station.call(t1, ya1)
					var p11: Vector3 = station.call(t1, yb1)
					p00.z *= side
					p01.z *= side
					p10.z *= side
					p11.z *= side
					var out := Vector3(0, -0.3, side)
					_tri(st, p00, p10, p11, out, col)
					_tri(st, p00, p11, p01, out, col)
			# The transom closes the stern.
			if i == 0:
				for k in levels:
					var ya := lerpf(y00, y01, float(k) / levels)
					var yb := lerpf(y00, y01, float(k + 1) / levels)
					var a: Vector3 = station.call(0.0, ya)
					var b: Vector3 = station.call(0.0, yb)
					_tri(st, Vector3(a.x, a.y, -a.z), Vector3(a.x, a.y, a.z), Vector3(b.x, b.y, b.z), Vector3(-1, 0, 0), col)
					_tri(st, Vector3(a.x, a.y, -a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, -b.z), Vector3(-1, 0, 0), col)
	# The sole: a deck across the hull at its height, so no sea shows
	# inside it.
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a: Vector3 = station.call(t0, sole)
		var b: Vector3 = station.call(t1, sole)
		if a.z <= 0.01 and b.z <= 0.01:
			continue
		var deck := Color(0.55, 0.52, 0.46)
		_tri(st, Vector3(a.x, sole, -a.z), Vector3(a.x, sole, a.z), Vector3(b.x, sole, b.z), Vector3.UP, deck)
		_tri(st, Vector3(a.x, sole, -a.z), Vector3(b.x, sole, b.z), Vector3(b.x, sole, -b.z), Vector3.UP, deck)
	st.index()
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		var swap := b
		b = c
		c = swap
	for p: Vector3 in [a, b, c]:
		st.set_color(col)
		st.add_vertex(p)


func _hull_node(mesh: ArrayMesh) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _hull_mat
	node.add_child(inst)
	return node


func _commit(mesh: TownMesh, node: Node3D) -> void:
	mesh.commit(node, {"wall": town.wall_mat, "glass": town.glass_mat, "lamp": town.lamp_mat,
		"iron": town.iron_mat, "steel": town.steel_mat}, ["wall", "iron"])


## A Maine lobster boat: a long low cockpit aft, the wheelhouse forward
## with its windows, a mast and the hauler's davit, the exhaust stack.
func _lobster_boat(hull: Color, cabin: Color, rng: RandomNumberGenerator) -> Node3D:
	var node := _hull_node(_hull(10.5, 3.4, 0.9, 1.05, 1.75, hull, 0.4))
	var m := TownMesh.new()
	var c := HarborTown.kc(cabin, HarborTown.K_PAINT)
	var cab := HarborTown.at(Vector3(1.9, 1.35, 0))
	m.box("wall", cab, Vector3(2.8, 1.9, 2.3), c)
	m.box("wall", HarborTown.at(Vector3(1.6, 2.35, 0)), Vector3(3.6, 0.08, 2.6), HarborTown.kc(Color(0.9, 0.9, 0.86), HarborTown.K_PAINT), true)
	for z: float in [-0.75, 0.0, 0.75]:
		var face := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(3.31, 1.75, z))
		m.quad("glass", face * Vector3(-0.32, -0.3, 0), face * Vector3(-0.32, 0.3, 0), face * Vector3(0.32, 0.3, 0),
			face * Vector3(0.32, -0.3, 0), Vector3(1, 0, 0), Color(1.0, rng.randf(), 0.5, 0.5))
	for s: float in [-1.0, 1.0]:
		var side := Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(1.9, 1.75, s * 1.16))
		m.quad("glass", side * Vector3(-0.9, -0.3, 0), side * Vector3(-0.9, 0.3, 0), side * Vector3(0.6, 0.3, 0),
			side * Vector3(0.6, -0.3, 0), Vector3(0, 0, s), Color(1.0, rng.randf(), 0.5, 0.5))
	m.cylinder("iron", HarborTown.at(Vector3(1.2, 3.6, 0.0)), 0.05, 0.04, 2.6, 6, Color(0.85, 0.85, 0.82))
	m.cylinder("iron", HarborTown.at(Vector3(0.6, 2.9, 0.9)), 0.08, 0.08, 1.2, 8, Color(0.1, 0.1, 0.1))
	m.bar("iron", Vector3(0.4, 1.0, -1.4), Vector3(0.1, 2.0, -1.8), 0.05, 6, Color(0.6, 0.6, 0.6))
	m.box("wall", HarborTown.at(Vector3(-3.0, 0.75, 0)), Vector3(1.0, 0.6, 0.6), HarborTown.kc(Color(0.72, 0.62, 0.20), HarborTown.K_PAINT), true)
	_commit(m, node)
	return node


## An eastern-rig dragger: bigger, higher forward, a wheelhouse aft of
## the mast, a boom, the gallows frames; her wheelhouse lit at night.
func _dragger() -> Node3D:
	var node := _hull_node(_hull(16.0, 5.0, 1.6, 1.4, 2.6, Color(0.20, 0.26, 0.32), 0.6))
	var m := TownMesh.new()
	var white := HarborTown.kc(Color(0.9, 0.9, 0.86), HarborTown.K_PAINT)
	m.box("wall", HarborTown.at(Vector3(-3.5, 2.1, 0)), Vector3(3.2, 2.6, 3.2), white)
	m.box("wall", HarborTown.at(Vector3(-3.5, 3.45, 0)), Vector3(3.5, 0.1, 3.5), white, true)
	for s: float in [-1.0, 1.0]:
		var side := Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(-3.5, 2.6, s * 1.61))
		m.quad("glass", side * Vector3(-1.2, -0.35, 0), side * Vector3(-1.2, 0.35, 0), side * Vector3(1.2, 0.35, 0),
			side * Vector3(1.2, -0.35, 0), Vector3(0, 0, s), Color(0.3, 0.4, 0.0, 0.8))
	var front := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-1.89, 2.6, 0))
	m.quad("glass", front * Vector3(-1.3, -0.35, 0), front * Vector3(-1.3, 0.35, 0), front * Vector3(1.3, 0.35, 0),
		front * Vector3(1.3, -0.35, 0), Vector3(1, 0, 0), Color(0.3, 0.6, 0.0, 0.8))
	m.cylinder("wall", HarborTown.at(Vector3(1.5, 5.5, 0)), 0.14, 0.09, 9.0, 8, HarborTown.kc(Color(0.55, 0.45, 0.30), HarborTown.K_TIMBER))
	m.bar("wall", Vector3(1.5, 2.2, 0), Vector3(-4.5, 4.0, 0.0), 0.08, 6, HarborTown.kc(Color(0.55, 0.45, 0.30), HarborTown.K_TIMBER))
	for s: float in [-1.0, 1.0]:
		m.bar("iron", Vector3(-6.2, 1.4, s * 2.2), Vector3(-6.2, 3.2, s * 2.2), 0.07, 6, Color(0.1, 0.1, 0.1))
		m.bar("iron", Vector3(-6.2, 3.2, s * 2.2), Vector3(-5.4, 3.2, s * 2.2), 0.07, 6, Color(0.1, 0.1, 0.1))
		m.bar("iron", Vector3(1.5, 9.6, 0), Vector3(-7.4, 1.4, s * 2.1), 0.012, 4, Color(0.2, 0.2, 0.2))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-3.5, 2.5, 0)
	lamp.omni_range = 6.0
	lamp.light_color = Color(1.0, 0.75, 0.45)
	node.add_child(lamp)
	town.lamps.append({"light": lamp, "thr": 0.3, "energy": 0.8})
	_commit(m, node)
	return node


## A dory: flared, narrow on the bottom, open, with thwarts.
func _dory(color: Color) -> Node3D:
	var node := _hull_node(_hull(5.0, 1.6, 0.22, 0.55, 0.75, color, 0.06))
	var m := TownMesh.new()
	var wood := HarborTown.kc(Color(0.55, 0.45, 0.32), HarborTown.K_PLANK)
	for x: float in [-1.0, 0.4]:
		m.box("wall", HarborTown.at(Vector3(x, 0.35, 0)), Vector3(0.22, 0.04, 1.3), wood, true)
	m.bar("wall", Vector3(-0.4, 0.4, 0.4), Vector3(1.8, 0.45, 0.55), 0.03, 5, wood)
	_commit(m, node)
	return node


func _mooring_ball(at: Vector2, k: int) -> void:
	var ball := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.25
	s.height = 0.45
	ball.mesh = s
	ball.material_override = ViewUtil.painted(Color(0.92, 0.92, 0.88))
	add_child(ball)
	_boats.append({"node": ball, "ball": at, "length": 0.5, "beam": 0.5, "phase": float(k), "roll_gain": 0.5})


## ---- the float and the gangway --------------------------------------------

func _build_float() -> void:
	_float = Node3D.new()
	add_child(_float)
	var m := TownMesh.new()
	m.box("wall", HarborTown.at(Vector3(0, 0.1, 0)), Vector3(4.0, 0.2, 12.0), HarborTown.kc(Color(0.52, 0.48, 0.42), HarborTown.K_PLANK), true)
	m.box("wall", HarborTown.at(Vector3(0, -0.25, 0)), Vector3(3.8, 0.5, 11.8), HarborTown.kc(Color(0.25, 0.25, 0.26), HarborTown.K_TIMBER), true)
	for z: float in [-5.0, -1.5, 2.0, 5.0]:
		m.cylinder("iron", HarborTown.at(Vector3(1.9, 0.35, z)), 0.1, 0.08, 0.3, 8, Color(0.1, 0.1, 0.1))
	_commit(m, _float)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.4, 12.0)
	shape.shape = box
	body.add_child(shape)
	_float.add_child(body)
	_gangway = Node3D.new()
	add_child(_gangway)
	# The gangway: hinged at the T-head, its foot rolling on the float.
	var g := TownMesh.new()
	var l := GANGWAY
	g.box("wall", HarborTown.at(Vector3(l / 2.0, 0, 0)), Vector3(l, 0.1, 1.2), HarborTown.kc(Color(0.50, 0.46, 0.40), HarborTown.K_PLANK), true)
	for s: float in [-1.0, 1.0]:
		g.box("iron", HarborTown.at(Vector3(l / 2.0, 0.9, s * 0.6)), Vector3(l, 0.05, 0.05), Color(0.2, 0.2, 0.2), true)
		for k in 5:
			g.box("iron", HarborTown.at(Vector3(l * (k + 0.5) / 5.0, 0.45, s * 0.6)), Vector3(0.05, 0.9, 0.05), Color(0.2, 0.2, 0.2), true)
	_commit(g, _gangway)
	var gbody := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(l, 0.12, 1.2)
	gshape.shape = gbox
	gshape.position = Vector3(l / 2.0, 0, 0)
	gbody.add_child(gshape)
	_gangway.add_child(gbody)


## ---- the bell buoy -----------------------------------------------------------

func _build_buoy() -> void:
	_buoy = Node3D.new()
	_buoy.name = "BellBuoy"
	add_child(_buoy)
	var m := TownMesh.new()
	var red := HarborTown.kc(Color(0.66, 0.12, 0.09), HarborTown.K_PAINT)
	m.cylinder("wall", HarborTown.at(Vector3(0, 0.1, 0)), 1.05, 1.05, 1.3, 20, red)
	m.cylinder("wall", HarborTown.at(Vector3(0, -2.0, 0)), 0.28, 0.28, 3.0, 10, red)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		m.bar("wall", Vector3(cos(a) * 0.85, 0.7, sin(a) * 0.85), Vector3(cos(a) * 0.35, 3.7, sin(a) * 0.35), 0.06, 6, red)
	for y: float in [2.0, 3.7]:
		var r := 0.85 - (y - 0.7) / 3.0 * 0.5
		for k in 12:
			var a0 := TAU * k / 12.0
			var a1 := TAU * (k + 1) / 12.0
			m.bar("wall", Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), 0.04, 5, red)
	m.box("wall", HarborTown.at(Vector3(0, 1.4, 0.62)), Vector3(0.5, 0.6, 0.04), red, true)
	m.cylinder("iron", HarborTown.at(Vector3(0, 3.95, 0)), 0.12, 0.12, 0.3, 10, Color(0.1, 0.1, 0.1))
	_commit(m, _buoy)
	var plate := Label3D.new()
	plate.text = "2"
	plate.font_size = 120
	plate.pixel_size = 0.004
	plate.modulate = Color(0.95, 0.95, 0.9)
	plate.shaded = true
	plate.double_sided = false
	plate.position = Vector3(0, 1.4, 0.65)
	_buoy.add_child(plate)
	# The bell, bronze, hung under the top of the tower.
	var bell := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.34
	cone.height = 0.45
	bell.mesh = cone
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.62, 0.44, 0.22)
	bronze.metallic = 0.85
	bronze.roughness = 0.38
	bell.material_override = bronze
	bell.position = Vector3(0, 3.35, 0)
	_buoy.add_child(bell)
	_buoy_lamp = ViewUtil.glow(Color(1.0, 0.12, 0.08), 0.0)
	var lens := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.13
	ball.height = 0.26
	lens.mesh = ball
	lens.material_override = _buoy_lamp
	lens.position = Vector3(0, 4.2, 0)
	_buoy.add_child(lens)
	_buoy_light = OmniLight3D.new()
	_buoy_light.position = Vector3(0, 4.3, 0)
	_buoy_light.omni_range = 14.0
	_buoy_light.light_color = Color(1.0, 0.15, 0.1)
	_buoy_light.light_energy = 0.0
	_buoy.add_child(_buoy_light)
	if DisplayServer.get_name() != "headless":
		_bell_audio = AudioStreamPlayer3D.new()
		# Carried as far as a real one: loud alongside, faint from the town,
		# the high clang lost first with distance.
		_bell_audio.unit_size = 12.0
		_bell_audio.max_distance = 1500.0
		_bell_audio.attenuation_filter_cutoff_hz = 6000.0
		_bell_audio.attenuation_filter_db = -18.0
		_bell_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_bell_audio.bus = "Bell"
		_bell_audio.max_polyphony = 3
		_buoy.add_child(_bell_audio)


## ---- the sea moving them ----------------------------------------------------

func _process(delta: float) -> void:
	step(minf(delta, 0.1))


## One step of the harbour: every boat set on the water, the float and
## its gangway on the tide, the buoy rolled and its bell rung.
func step(delta: float) -> void:
	_t += delta
	var tide := coast.tide_y
	var wind_yaw := _yaw_of(-wind_dir)
	for b: Dictionary in _boats:
		var node: Node3D = b["node"]
		var phase: float = b["phase"]
		var centre: Vector2
		var yaw: float
		if b.has("mooring"):
			# Downwind of the ball, bow to the wind, swinging on the rode.
			var swing := 0.35 * sin(_t * 0.045 + phase) + 0.12 * sin(_t * 0.13 + phase * 2.0)
			var lie := wind_dir.rotated(swing)
			centre = (b["mooring"] as Vector2) + lie * float(b["rode"])
			yaw = _yaw_of(-lie)
		elif b.has("ball"):
			centre = b["ball"]
			yaw = 0.0
		else:
			centre = b["tied"]
			yaw = float(b["yaw"])
		_ride(node, centre, yaw, float(b["length"]), float(b["beam"]), float(b["roll_gain"]), phase, tide)
	# The float rides the tide at the gangway's foot; the gangway spans
	# from the T-head to it.
	var fc := Vector2(-10.0, 116.0)
	var fw := wave(fc, _t, swell * SHELTER * 0.7)
	_float.transform = Transform3D(Basis(Vector3(0, 0, 1), atan(fw.y) * 1.2), Vector3(fc.x, tide + 0.18 + fw.x, fc.y))
	var top := Vector3(TownCoast.HEAD_X.y, TownCoast.DECK_Y + 0.05, 116.0)
	var drop := top.y - (_float.position.y + 0.25)
	_gangway.transform = Transform3D(Basis(Vector3(0, 0, 1), -asin(clampf(drop / GANGWAY, -0.9, 0.9))), top)
	_step_buoy(delta, tide)


## A boat set on the water: its heave the mean of the water under bow,
## stern, port and starboard, its pitch and roll the differences.
func _ride(node: Node3D, centre: Vector2, yaw: float, length: float, beam: float, roll_gain: float,
		phase: float, tide: float) -> void:
	var fwd := Vector2(cos(yaw), -sin(yaw))
	var port := Vector2(-fwd.y, fwd.x) * -1.0
	var s := swell * SHELTER
	var bow := wave(centre + fwd * length * 0.45, _t, s).x
	var stern := wave(centre - fwd * length * 0.45, _t, s).x
	var p := wave(centre + port * beam * 0.5, _t, s).x
	var sb := wave(centre - port * beam * 0.5, _t, s).x
	var heave := (bow + stern + p + sb) / 4.0
	var pitch := atan2(bow - stern, length * 0.9)
	var roll := atan2(p - sb, beam) * roll_gain + 0.02 * sin(_t * 1.3 + phase) * s
	node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), pitch) * Basis(Vector3.RIGHT, roll),
		Vector3(centre.x, tide + heave, centre.y))


## The yaw that points a boat's bow (+x) along dir.
static func _yaw_of(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


## The buoy: a tilt that follows the water's slope through its own roll
## period, a clapper swinging free under the tower's top, the bell
## rung where they meet.
func _step_buoy(delta: float, tide: float) -> void:
	var at := TownCoast.BUOY
	var steps := maxi(int(ceil(delta / 0.008)), 1)
	var dt := delta / steps
	var omega := TAU / 2.6
	var zeta := 0.12
	var arm := 3.35         # waterline to the clapper's pivot, m
	var hang := 0.45        # the clapper's pendulum, m
	var gap := 0.16         # how far the clapper swings before it meets the bell, rad
	var w := wave(at, _t, swell)
	var slope := Vector2(w.y, w.z) * 1.4
	for _i in steps:
		var accel := (slope - _buoy_tilt) * omega * omega - _buoy_rate * 2.0 * zeta * omega
		_buoy_rate += accel * dt
		_buoy_tilt += _buoy_rate * dt
		# The clapper hangs from a pivot that swings with the tower's top:
		# gravity pulls it to the vertical, the pivot's acceleration throws
		# it the other way.
		var c_acc := -_clapper * (9.81 / hang) - accel * (arm / hang) - _clapper_rate * 0.6
		_clapper_rate += c_acc * dt
		_clapper += _clapper_rate * dt
		var rel := _clapper - _buoy_tilt
		if rel.length() > gap:
			var n := rel.normalized()
			var closing := (_clapper_rate - _buoy_rate).dot(n)
			_clapper = _buoy_tilt + n * gap
			if closing > 0.0:
				_clapper_rate -= n * closing * 1.35
				_ring(closing)
	var tilt := Basis(Vector3(1, 0, 0), _buoy_tilt.y) * Basis(Vector3(0, 0, 1), -_buoy_tilt.x)
	_buoy.transform = Transform3D(tilt, Vector3(at.x, tide + w.x - 0.1, at.y))
	# Its light: a red flash every four seconds, after dark.
	var flash := 1.0 if fmod(_t, 4.0) < 0.6 else 0.0
	var dark := smoothstep(0.45, 0.65, night)
	_buoy_lamp.emission_energy_multiplier = 6.0 * flash * dark
	_buoy_light.light_energy = 2.5 * flash * dark
	_buoy_light.visible = dark > 0.0


func _ring(speed: float) -> void:
	if speed < 0.12 or _t - _last_ring < 0.2:
		return
	_last_ring = _t
	bell_strikes += 1
	if _bell_audio == null:
		return
	var hard := speed > 0.9
	_bell_audio.stream = load("res://audio/bell_1.wav" if hard else "res://audio/bell_2.wav")
	_bell_audio.volume_db = linear_to_db(clampf(speed / 1.0, 0.3, 1.0)) + 4.0
	_bell_audio.pitch_scale = 1.0 + randf_range(-0.004, 0.004)
	_bell_audio.play()
