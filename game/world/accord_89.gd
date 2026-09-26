class_name Accord89
extends Node3D
## A 1989 Honda Accord sedan in silver: the third generation's low
## wedge, a long flat hood running to slim flush headlamps with amber
## corners, a thin-pillared glasshouse, a short square trunk and a band
## of tail lamps across the back; black rubbing strips down the sides,
## grey bumpers, thirteen-inch wheels under flat silver covers pierced
## with a ring of holes. Inside, grey cloth seats and a dark dash.
##
## Art only: scenery with no record. Frame: origin on the ground under
## the middle of the car, -z forward, x to the right. lights_on lights
## the lamps (and throws the headlamps' beams); braking brightens the
## tail lamps.

const LENGTH := 4.54
const WIDTH := 1.69
const WHEEL_R := 0.29
const AXLE_F := -1.32
const AXLE_R := 1.28
const TRACK := 0.735          # half the track

const SILVER := Color(0.72, 0.73, 0.74)
const TRIM := Color(0.06, 0.06, 0.065)
const BUMPER := Color(0.46, 0.47, 0.48)
const CLOTH := Color(0.33, 0.34, 0.36)

var m := TownMesh.new()
var _lamp_front: StandardMaterial3D
var _lamp_rear: StandardMaterial3D
var _beams: Array[SpotLight3D] = []


func build(lights_on := true, braking := false) -> void:
	name = "Accord89"
	_body()
	_glasshouse()
	_front()
	_rear()
	_sides()
	for z: float in [AXLE_F, AXLE_R]:
		for s: float in [-1.0, 1.0]:
			_wheel(Vector3(s * TRACK, WHEEL_R, z), s)
	_interior()
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.metallic = 0.55
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	var matte := StandardMaterial3D.new()
	matte.vertex_color_use_as_albedo = true
	matte.vertex_color_is_srgb = true
	matte.roughness = 0.75
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.16, 0.19, 0.22, 0.86)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.7
	glass.roughness = 0.04
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lamp_front = StandardMaterial3D.new()
	_lamp_front.vertex_color_use_as_albedo = true
	_lamp_front.vertex_color_is_srgb = true
	_lamp_front.emission_enabled = true
	_lamp_front.emission = Color(1.0, 0.93, 0.78)
	_lamp_rear = StandardMaterial3D.new()
	_lamp_rear.vertex_color_use_as_albedo = true
	_lamp_rear.vertex_color_is_srgb = true
	_lamp_rear.emission_enabled = true
	_lamp_rear.emission = Color(1.0, 0.08, 0.04)
	m.commit(self, {"paint": paint, "matte": matte, "glass": glass, "front": _lamp_front, "rear": _lamp_rear},
		["paint", "matte"])
	for s: float in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.position = Vector3(s * 0.55, 0.6, -2.3)
		beam.rotation = Vector3(-0.08, 0.0, 0.0)
		beam.spot_range = 30.0
		beam.spot_angle = 28.0
		beam.light_color = Color(1.0, 0.92, 0.75)
		beam.light_energy = 6.0
		beam.shadow_enabled = false
		add_child(beam)
		_beams.append(beam)
	set_lights(lights_on, braking)


func set_lights(on: bool, braking := false) -> void:
	_lamp_front.emission_energy_multiplier = 4.0 if on else 0.0
	_lamp_rear.emission_energy_multiplier = (6.0 if braking else 2.2) if on else (4.0 if braking else 0.0)
	for beam in _beams:
		beam.visible = on


## ---- the shell ------------------------------------------------------------

## A shape drawn as a side profile (z, y) and extruded across the car,
## its half width at each vertex given by half(y): the side faces
## triangulated, the band round the edge in quads.
func _extrude(key: String, profile: PackedVector2Array, half: Callable, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(profile)
	for s: float in [-1.0, 1.0]:
		for k in range(0, tris.size(), 3):
			var p: Array[Vector3] = []
			for j in 3:
				var q := profile[tris[k + j]]
				p.append(Vector3(s * float(half.call(q.y)), q.y, q.x))
			m.tri(key, p[0], p[1], p[2], Vector3(s, 0, 0), col)
	var n := profile.size()
	for k in n:
		var a := profile[k]
		var b := profile[(k + 1) % n]
		var ha := float(half.call(a.y))
		var hb := float(half.call(b.y))
		var edge := Vector3(0, b.y - a.y, b.x - a.x)
		var out := Vector3(0, edge.z, -edge.y).normalized()
		# The band faces outward from the profile's middle.
		var mid := Vector2(0, 0)
		for q in profile:
			mid += q
		mid /= n
		var c := Vector3(0, (a.y + b.y) / 2.0 - mid.y, (a.x + b.x) / 2.0 - mid.x)
		if out.dot(c) < 0.0:
			out = -out
		m.quad(key, Vector3(-ha, a.y, a.x), Vector3(ha, a.y, a.x), Vector3(hb, b.y, b.x), Vector3(-hb, b.y, b.x), out, col)


func _body() -> void:
	# From the front bumper's foot, round over the hood, the cowl, the
	# belt, the trunk and down the tail.
	var pr := PackedVector2Array([
		Vector2(-2.20, 0.30), Vector2(-2.27, 0.44), Vector2(-2.25, 0.58), Vector2(-2.17, 0.66),
		Vector2(-1.60, 0.72), Vector2(-0.85, 0.82), Vector2(-0.70, 0.84),
		Vector2(1.30, 0.90), Vector2(1.45, 0.93), Vector2(2.16, 0.94), Vector2(2.24, 0.90),
		Vector2(2.27, 0.62), Vector2(2.25, 0.34), Vector2(2.15, 0.28),
		Vector2(1.70, 0.24), Vector2(0.85, 0.22), Vector2(-0.85, 0.22), Vector2(-1.85, 0.24)])
	var half := func(y: float) -> float:
		return WIDTH / 2.0 - (0.06 if y > 0.8 else 0.0) - (0.03 if y < 0.3 else 0.0)
	_extrude("paint", pr, half, SILVER)
	# The wheel arches, black within.
	for z: float in [AXLE_F, AXLE_R]:
		for s: float in [-1.0, 1.0]:
			m.cylinder("matte", Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(s * (WIDTH / 2.0 - 0.02), WHEEL_R + 0.02, z)),
				0.36, 0.36, 0.05, 20, TRIM)


func _glasshouse() -> void:
	# The windshield, the roof, the backlight: glass all round, the roof
	# and the pillars laid over it.
	var pr := PackedVector2Array([Vector2(-0.72, 0.84), Vector2(-0.05, 1.33), Vector2(0.85, 1.35), Vector2(1.40, 0.91)])
	var half := func(y: float) -> float:
		return lerpf(0.80, 0.66, clampf((y - 0.84) / 0.5, 0.0, 1.0))
	_extrude("glass", pr, half, Color(1, 1, 1))
	# The roof panel.
	m.box("paint", Transform3D(Basis(), Vector3(0, 1.345, 0.40)), Vector3(1.30, 0.02, 0.86), SILVER)
	m.box("paint", Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.33, -0.04)), Vector3(1.28, 0.02, 0.14), SILVER)
	# The pillars: A raked with the windshield, B upright, C raked with the
	# backlight; black sash round the side glass.
	for s: float in [-1.0, 1.0]:
		_bar("paint", Vector3(s * 0.80, 0.85, -0.70), Vector3(s * 0.665, 1.33, -0.06), 0.035, SILVER)
		_bar("matte", Vector3(s * 0.78, 0.9, 0.18), Vector3(s * 0.675, 1.33, 0.18), 0.04, TRIM)
		_bar("paint", Vector3(s * 0.77, 0.92, 1.28), Vector3(s * 0.665, 1.34, 0.84), 0.045, SILVER)
		_bar("matte", Vector3(s * 0.675, 1.335, -0.05), Vector3(s * 0.665, 1.345, 0.84), 0.015, TRIM)
		_bar("matte", Vector3(s * 0.81, 0.905, -0.68), Vector3(s * 0.79, 0.915, 1.28), 0.015, TRIM)
		# The small quarter glass behind the rear door, set in the C pillar.
		m.quad("matte", Vector3(s * 0.765, 0.95, 1.05), Vector3(s * 0.765, 1.06, 0.98), Vector3(s * 0.768, 0.95, 0.95),
			Vector3(s * 0.768, 0.95, 1.05), Vector3(s, 0, 0), TRIM)
		# The mirror.
		m.box("matte", Transform3D(Basis(Vector3.UP, s * 0.2), Vector3(s * 0.93, 0.98, -0.55)), Vector3(0.18, 0.12, 0.08), TRIM)
	# The wipers resting at the windshield's foot.
	for x: float in [-0.35, 0.25]:
		_bar("matte", Vector3(x - 0.2, 0.87, -0.66), Vector3(x + 0.3, 0.88, -0.63), 0.012, TRIM)


func _front() -> void:
	var z := -2.26
	# The grey bumper with its black strip.
	m.box("paint", Transform3D(Basis(), Vector3(0, 0.40, z + 0.04)), Vector3(WIDTH - 0.04, 0.22, 0.14), BUMPER)
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.43, z - 0.02)), Vector3(WIDTH - 0.1, 0.05, 0.04), TRIM)
	# The slim grille between the headlamps, the flush lamps, amber
	# corners wrapping round.
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.585, z + 0.08)), Vector3(0.46, 0.08, 0.04), TRIM)
	for i in 5:
		m.box("paint", Transform3D(Basis(), Vector3(0, 0.555 + i * 0.015, z + 0.06)), Vector3(0.44, 0.004, 0.01), BUMPER)
	for s: float in [-1.0, 1.0]:
		m.box("front", Transform3D(Basis(), Vector3(s * 0.46, 0.595, z + 0.09)), Vector3(0.40, 0.10, 0.03), Color(0.95, 0.95, 0.92))
		m.box("matte", Transform3D(Basis(), Vector3(s * 0.46, 0.595, z + 0.08)), Vector3(0.42, 0.12, 0.02), TRIM)
		m.box("front", Transform3D(Basis(Vector3.UP, s * 0.5), Vector3(s * 0.76, 0.595, z + 0.18)), Vector3(0.16, 0.09, 0.03),
			Color(1.0, 0.55, 0.12))
	# The badge.
	m.box("paint", Transform3D(Basis(), Vector3(0, 0.59, z + 0.055)), Vector3(0.08, 0.05, 0.01), Color(0.85, 0.86, 0.88))
	# The plate.
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.40, z - 0.04)), Vector3(0.31, 0.155, 0.01), Color(0.9, 0.9, 0.88))


func _rear() -> void:
	var z := 2.27
	m.box("paint", Transform3D(Basis(), Vector3(0, 0.40, z - 0.03)), Vector3(WIDTH - 0.04, 0.22, 0.14), BUMPER)
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.43, z + 0.03)), Vector3(WIDTH - 0.1, 0.05, 0.04), TRIM)
	# The band of tail lamps across the back, the plate between.
	for s: float in [-1.0, 1.0]:
		m.box("rear", Transform3D(Basis(), Vector3(s * 0.54, 0.72, z - 0.005)), Vector3(0.52, 0.16, 0.03), Color(0.75, 0.05, 0.04))
		m.box("matte", Transform3D(Basis(), Vector3(s * 0.54, 0.665, z)), Vector3(0.5, 0.03, 0.03), Color(0.9, 0.9, 0.9))
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.72, z - 0.01)), Vector3(0.52, 0.16, 0.02), TRIM)
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.70, z + 0.012)), Vector3(0.31, 0.155, 0.01), Color(0.9, 0.9, 0.88))
	# The exhaust.
	m.cylinder("matte", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(-0.5, 0.25, z - 0.05)), 0.03, 0.03, 0.2, 8, Color(0.25, 0.25, 0.25))


func _sides() -> void:
	for s: float in [-1.0, 1.0]:
		var x := s * (WIDTH / 2.0 + 0.005)
		# The rubbing strip.
		m.box("matte", Transform3D(Basis(), Vector3(x, 0.52, 0.0)), Vector3(0.03, 0.05, 3.9), TRIM)
		# The door cuts and the handles.
		for z: float in [-0.72, 0.18, 1.18]:
			m.box("matte", Transform3D(Basis(), Vector3(x, 0.57, z)), Vector3(0.006, 0.62, 0.006), Color(0.3, 0.3, 0.3))
		for z: float in [-0.15, 0.85]:
			m.box("matte", Transform3D(Basis(), Vector3(x, 0.8, z)), Vector3(0.02, 0.03, 0.14), TRIM)
		# The fuel door.
		if s > 0.0:
			m.box("matte", Transform3D(Basis(), Vector3(x, 0.78, 1.75)), Vector3(0.004, 0.11, 0.12), SILVER.darkened(0.15))
	# The antenna.
	_bar("matte", Vector3(0.55, 0.93, 1.6), Vector3(0.62, 1.8, 1.9), 0.004, TRIM)


## A wheel: the tyre, the flat silver cover with its ring of holes.
func _wheel(c: Vector3, s: float) -> void:
	var xf := Transform3D(Basis(Vector3.BACK, PI / 2.0), c)
	m.cylinder("matte", xf, WHEEL_R, WHEEL_R, 0.19, 24, Color(0.05, 0.05, 0.05))
	var face := c + Vector3(s * 0.1, 0, 0)
	m.cylinder("paint", Transform3D(Basis(Vector3.BACK, PI / 2.0), face), 0.19, 0.19, 0.012, 24, Color(0.8, 0.81, 0.82))
	m.cylinder("paint", Transform3D(Basis(Vector3.BACK, PI / 2.0), face + Vector3(s * 0.01, 0, 0)), 0.05, 0.05, 0.01, 12, Color(0.6, 0.6, 0.62))
	for k in 8:
		var a := TAU * k / 8.0
		m.cylinder("matte", Transform3D(Basis(Vector3.BACK, PI / 2.0), face + Vector3(s * 0.004, sin(a) * 0.12, cos(a) * 0.12)),
			0.028, 0.028, 0.012, 8, Color(0.1, 0.1, 0.1))


func _interior() -> void:
	var cloth := CLOTH
	for s: float in [-1.0, 1.0]:
		# The front seats and their headrests.
		m.box("matte", Transform3D(Basis(), Vector3(s * 0.38, 0.42, -0.05)), Vector3(0.5, 0.14, 0.5), cloth)
		m.box("matte", Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(s * 0.38, 0.75, 0.22)), Vector3(0.5, 0.62, 0.12), cloth)
		m.box("matte", Transform3D(Basis(), Vector3(s * 0.38, 1.13, 0.30)), Vector3(0.26, 0.17, 0.1), cloth)
		# The door panels.
		m.box("matte", Transform3D(Basis(), Vector3(s * 0.76, 0.62, 0.3)), Vector3(0.03, 0.5, 2.0), cloth.darkened(0.3))
	# The back bench.
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.40, 0.95)), Vector3(1.36, 0.14, 0.5), cloth)
	m.box("matte", Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.72, 1.22)), Vector3(1.36, 0.6, 0.12), cloth)
	# The dash, the wheel.
	m.box("matte", Transform3D(Basis(), Vector3(0, 0.78, -0.62)), Vector3(1.4, 0.18, 0.3), Color(0.12, 0.12, 0.13))
	m.cylinder("matte", Transform3D(Basis(Vector3.RIGHT, PI / 2.0 - 0.45), Vector3(-0.38, 0.86, -0.42)), 0.19, 0.19, 0.03, 18,
		Color(0.08, 0.08, 0.08))


func _bar(key: String, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	m.bar(key, a, b, r, 6, col)
