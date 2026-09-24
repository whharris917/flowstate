class_name MaineCoast
extends Landscape
## A site on the coast of Maine. A graded pad on
## a granite headland seven metres over the Gulf of Maine, with the
## sea to the east and south; a cove with a cobble beach at its head
## to the south-west and a lighthouse on the next point across it;
## spruce-fir woods rising to hills in the north-west; islands and a
## ledge offshore.
##
## The coast is a signed distance field: a wavy mainland edge east and
## south, a cove cut out of it, discs added for the point and the
## islands. The ground is a profile of that distance — seabed sloping
## away, ledge rising to a shelf, then rolling hills — with the ledges
## stepped where the sea works them, and the site and the light
## station graded flat. The lighthouse is art, like the trees: its
## beam turns, and the lens flashes as it sweeps past the viewer.
##
## The river comes down out of the north-west hills and meets the sea west of
## the light, beyond the point: a tidal reach at sea level for its
## first two hundred metres — the sea plane fills it, ledge and gravel
## bars along it — then a rapid stream climbing between wooded banks,
## with its own water ribbon, boulders in the current, and the sound
## of it. It is a centreline with a meander, a width, a depth and a
## water level, all functions of the distance upstream of the mouth;
## the ground is cut to a valley round it and a channel under it.

const SEA := -7.0
const SITE := Vector2(15.0, 10.0)
const SITE_HALF := Vector2(60.0, 50.0)       # x -45..75, z -40..60
const GRADE_BLEND := 30.0
const COVE := Vector2(-30.0, 150.0)
const COVE_R := 62.0
const BEACH := Vector2(-30.0, 104.0)         # the cove's head
const HEAD := Vector2(-95.0, 185.0)          # the lighthouse point
const HEAD_R := 48.0
const LIGHTHOUSE := Vector2(-78.0, 178.0)
const LIGHT_Y := 4.5
const BEAM_PERIOD := 10.0                    # one turn; the flash is every ten seconds
# The river: its mouth on the shore west of the light, the way it runs
# inland (unit), the across direction, the tidal reach, the grade of
# the stream above it, and where it fades out under the far wood.
const RIVER_MOUTH := Vector2(-190.0, 112.0)
const RIVER_DIR := Vector2(-0.6222, -0.7829)
const RIVER_PERP := Vector2(-0.7829, 0.6222)
const RIVER_TIDAL := 220.0
const RIVER_GRADE := 0.03
const RIVER_END := 560.0
# The heighliner: a hollow cylinder a mile long
# hanging out over the sea to the south-east, its bore open at both
# ends, angled so the site sees one mouth. Art, silent, still.
const SHIP_CENTRE := Vector3(1250.0, 560.0, 950.0)
const SHIP_LENGTH := 1600.0
const SHIP_RADIUS := 190.0
const SHIP_BORE := 148.0
const SHIP_YAW := 0.22
const SHIP_PITCH := 0.04
# Islands: centre, radius, stretch along x and z, rotation.
const ISLANDS: Array = [
	[Vector2(340.0, 30.0), 60.0, 1.8, 0.8, 0.5],
	[Vector2(255.0, 195.0), 9.0, 1.0, 1.0, 0.0],       # a ledge, awash at high water
	[Vector2(520.0, -190.0), 75.0, 1.3, 1.0, -0.4],
	[Vector2(160.0, 330.0), 34.0, 1.0, 1.4, 0.2],
	[Vector2(430.0, 250.0), 12.0, 1.0, 1.0, 0.0],
]

var _n: FastNoiseLite
var _hills: FastNoiseLite
var _flats: Array[Dictionary] = []
var _beam: SpotLight3D
var _lamp_mat: StandardMaterial3D
var _lens: MeshInstance3D
var _beam_angle := 0.0
var _night := 0.0
var _ship_mats: Array[ShaderMaterial] = []


func _init() -> void:
	centre = Vector3(SITE.x, 0.0, SITE.y)
	sea_level = SEA
	_n = FastNoiseLite.new()
	_n.seed = 207
	_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n.fractal_type = FastNoiseLite.FRACTAL_NONE
	_n.frequency = 1.0
	_hills = FastNoiseLite.new()
	_hills.seed = 1820
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_hills.fractal_octaves = 4
	_hills.fractal_gain = 0.5
	_hills.fractal_lacunarity = 2.1
	_hills.frequency = 1.0
	_flats = [
		{"c": SITE, "half": SITE_HALF, "blend": GRADE_BLEND, "y": 0.0},
		{"c": LIGHTHOUSE + Vector2(3.0, 2.0), "half": Vector2(14.0, 10.0), "blend": 12.0, "y": LIGHT_Y},
	]


## ---- the ground ----------------------------------------------------------

func coast_distance(x: float, z: float) -> float:
	var d_e := (112.0 + 14.0 * _n.get_noise_2d(0.0, z * 0.011) + 5.0 * _n.get_noise_2d(50.0, z * 0.045)) - x
	var d_s := (108.0 + 14.0 * _n.get_noise_2d(x * 0.011, 70.0) + 5.0 * _n.get_noise_2d(x * 0.045, 120.0)) - z
	var d := minf(d_e, d_s)
	var p := Vector2(x, z)
	d = minf(d, p.distance_to(COVE) - COVE_R)
	d = maxf(d, HEAD_R - p.distance_to(HEAD))
	for island: Array in ISLANDS:
		var c: Vector2 = island[0]
		var q := (p - c).rotated(-float(island[4]))
		var e := Vector2(q.x / float(island[2]), q.y / float(island[3])).length()
		d = maxf(d, float(island[1]) - e)
	# The river's tidal reach is sea: the channel is cut into the field
	# up to the head of tide, closing over thirty metres there, and a
	# short way out past the mouth, closing there too — the centreline's
	# extension out to sea runs under the lighthouse point.
	var rv := river_at(x, z)
	if rv.y > -40.0 and rv.y < RIVER_TIDAL + 30.0:
		d = minf(d, rv.x - river_half(rv.y) + maxf(rv.y - RIVER_TIDAL, 0.0) + maxf(-rv.y - 15.0, 0.0))
	return d


## ---- the river -----------------------------------------------------------

## The meander: how far the channel lies across from its straight
## line, s metres upstream of the mouth.
func _meander(s: float) -> float:
	return 26.0 * sin(s * 0.018 + 0.6) + 14.0 * sin(s * 0.041 + 2.0)


func _meander_slope(s: float) -> float:
	return 26.0 * 0.018 * cos(s * 0.018 + 0.6) + 14.0 * 0.041 * cos(s * 0.041 + 2.0)


## Where (x, z) stands to the river: x is the distance from the
## centreline, y the metres upstream of the mouth (negative out to sea).
func river_at(x: float, z: float) -> Vector2:
	var q := Vector2(x, z) - RIVER_MOUTH
	var s := q.dot(RIVER_DIR)
	var l := q.dot(RIVER_PERP)
	var perp := absf(l - _meander(s)) / sqrt(1.0 + pow(_meander_slope(s), 2.0))
	return Vector2(perp, s)


func river_centre(s: float) -> Vector2:
	return RIVER_MOUTH + RIVER_DIR * s + RIVER_PERP * _meander(s)


## The true distance from p to the river's centreline between the
## mouth and its end (river_at is a local estimate, good near the
## channel and conservative far from it).
func river_distance(p: Vector2) -> float:
	var best := INF
	var s := 0.0
	while s <= RIVER_END:
		best = minf(best, p.distance_to(river_centre(s)))
		s += 5.0
	return best


## Half the channel's width: an estuary forty metres across at the
## mouth, a stream of fifteen up in the hills.
func river_half(s: float) -> float:
	return 7.0 + 15.0 * exp(-maxf(s, 0.0) / 120.0)


## The water's height: the sea's up the tidal reach, then a steady
## climb.
func river_level(s: float) -> float:
	return SEA + RIVER_GRADE * maxf(s - RIVER_TIDAL, 0.0)


func river_depth(s: float) -> float:
	return 2.0 + 1.0 * exp(-maxf(s, 0.0) / 150.0)


## 1 in the stream above the head of tide, where boulders stand in
## the current.
func stream_at(x: float, z: float) -> float:
	var rv := river_at(x, z)
	if rv.y > RIVER_TIDAL and rv.y < RIVER_END and rv.x < river_half(rv.y) + 2.0:
		return 1.0
	return 0.0


func height_at(x: float, z: float) -> float:
	var d := coast_distance(x, z)
	var h: float
	if d < 0.0:
		h = SEA + maxf(d * 0.22, -22.0)
	else:
		h = SEA + 9.5 * pow(minf(d, 30.0) / 30.0, 0.75) + 0.07 * maxf(d - 30.0, 0.0)
	var inland := smoothstep(12.0, 80.0, d)
	var rise := 0.05 * maxf((-(x - SITE.x) - (z - SITE.y)) * 0.7071, 0.0)
	var hills := 9.0 * _hills.get_noise_2d(x * 0.0035, z * 0.0035) + 5.0 + rise
	var rolls := 2.4 * _n.get_noise_2d(x * 0.03 + 3.0, z * 0.03) + 1.2 * _n.get_noise_2d(x * 0.09, z * 0.09 + 9.0) \
		+ 0.35 * _n.get_noise_2d(x * 0.25 + 17.0, z * 0.25)
	h += inland * hills + rolls * (0.35 + 0.65 * inland)
	h += 0.9 * _outcrop(x, z, d)
	# The river: a valley lowered toward the water, never raised, and
	# the channel cut under it; both fade out where the river leaves
	# under the far wood.
	var rv := river_at(x, z)
	if rv.y > -60.0 and rv.y < RIVER_END + 80.0:
		var w := river_level(rv.y)
		var half := river_half(rv.y)
		var tail := 1.0 - smoothstep(RIVER_END, RIVER_END + 80.0, rv.y)
		var valley := (1.0 - smoothstep(half + 4.0, half + 55.0, rv.x)) * tail * smoothstep(-30.0, 10.0, rv.y)
		if valley > 0.0:
			h = lerpf(h, minf(h, w + 2.6 + 0.06 * rv.x), valley)
		var channel := (1.0 - smoothstep(half + 1.0, half + 6.0, rv.x)) * tail
		if channel > 0.0:
			h = lerpf(h, minf(h, w - river_depth(rv.y)), channel)
	# Ledges: stepped shelves in the band the sea works, except where
	# the cove's head is a beach.
	var band := smoothstep(-4.0, -1.5, h - SEA) * (1.0 - smoothstep(4.0, 7.0, h - SEA)) * (1.0 - beach_at(x, z))
	if band > 0.0:
		h = lerpf(h, _terrace(h, 1.3), 0.55 * band)
	# The world's edge goes under the sea.
	var r := Vector2(x - SITE.x, z - SITE.y).length()
	if r > 650.0:
		h = lerpf(h, SEA - 25.0, smoothstep(650.0, 780.0, r))
	for flat in _flats:
		var w := _flat_weight(x, z, flat)
		if w > 0.0:
			h = lerpf(h, float(flat["y"]), w)
	return h


func _terrace(h: float, step: float) -> float:
	var k := floorf(h / step)
	var f := h / step - k
	return (k + smoothstep(0.3, 0.7, f)) * step


## 1 inside a graded rectangle, falling to 0 over its blend.
func _flat_weight(x: float, z: float, flat: Dictionary) -> float:
	var c: Vector2 = flat["c"]
	var half: Vector2 = flat["half"]
	var q := Vector2(absf(x - c.x), absf(z - c.y)) - half
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	return 1.0 - smoothstep(0.0, float(flat["blend"]), outside)


func is_graded(x: float, z: float) -> bool:
	for flat in _flats:
		if _flat_weight(x, z, flat) > 0.0:
			return true
	return false


func graded_at(x: float, z: float) -> float:
	var w := 0.0
	for flat in _flats:
		w = maxf(w, _flat_weight(x, z, flat))
	return w


## Ledge outcrops: bedrock breaking through the turf in patches on
## the low ground behind the shore, never on a graded flat. The
## height function raises them a little with a sharp edge, and the
## shader paints them rock.
func _outcrop(x: float, z: float, d: float) -> float:
	if d < 8.0 or d > 110.0 or graded_at(x, z) > 0.5:
		return 0.0
	var n := _n.get_noise_2d(x * 0.045 + 91.0, z * 0.045)
	return smoothstep(0.30, 0.40, n) * (1.0 - smoothstep(80.0, 110.0, d))


func outcrop_at(x: float, z: float) -> float:
	return _outcrop(x, z, coast_distance(x, z))


## The cove's head, and gravel bars along the river's tidal reach.
func beach_at(x: float, z: float) -> float:
	var cove := 1.0 - smoothstep(30.0, 55.0, Vector2(x, z).distance_to(BEACH))
	var rv := river_at(x, z)
	var bars := (1.0 - smoothstep(river_half(rv.y) + 1.0, river_half(rv.y) + 12.0, rv.x)) \
		* smoothstep(-10.0, 30.0, rv.y) * (1.0 - smoothstep(RIVER_TIDAL - 20.0, RIVER_TIDAL + 20.0, rv.y))
	return maxf(cove, bars)


## Spruce and fir stand to within a few metres of the ledge; the
## graded ground and the barrens (open heath on the headland) take none.
func tree_ground(x: float, z: float) -> float:
	var d := coast_distance(x, z)
	if d < 10.0:
		return -INF
	var h := height_at(x, z)
	if h < SEA + 2.0 or is_graded(x, z):
		return -INF
	if _n.get_noise_2d(x * 0.02 + 33.0, z * 0.02) > 0.42:
		return -INF
	# The river's channel and its immediate bank take no tree; the
	# woods come down to the water's edge beyond that.
	var rv := river_at(x, z)
	if rv.y > -20.0 and rv.y < RIVER_END and rv.x < river_half(rv.y) + 3.0:
		return -INF
	return h


## ---- the light station ---------------------------------------------------

func _build_landmarks() -> void:
	var at := Vector3(LIGHTHOUSE.x, LIGHT_Y, LIGHTHOUSE.y)
	var white := ViewUtil.painted(Color(0.93, 0.92, 0.88))
	var black := ViewUtil.painted(Color(0.10, 0.10, 0.11))
	var red := ViewUtil.painted(Color(0.55, 0.12, 0.10))
	var brick := ViewUtil.matte(Color(0.48, 0.28, 0.22))
	var plinth := ViewUtil.matte(Color(0.55, 0.50, 0.46))
	# The tower: a tapered white cylinder on a granite plinth, a
	# gallery with a railing, the lantern glazed under a red cap.
	_solid_cylinder(3.2, 3.2, 0.6, at + Vector3(0, 0.3, 0), plinth)
	_solid_cylinder(2.5, 1.9, 11.0, at + Vector3(0, 6.1, 0), white)
	_solid_cylinder(2.6, 2.6, 0.35, at + Vector3(0, 11.75, 0), black)
	var rail := TorusMesh.new()
	rail.inner_radius = 2.45
	rail.outer_radius = 2.55
	var rail_inst := MeshInstance3D.new()
	rail_inst.mesh = rail
	rail_inst.position = at + Vector3(0, 12.9, 0)
	rail_inst.material_override = black
	add_child(rail_inst)
	for k in 12:
		var a := TAU * k / 12.0
		ViewUtil.cylinder(self, 0.03, 1.0, at + Vector3(cos(a) * 2.5, 12.4, sin(a) * 2.5), black)
	_solid_cylinder(1.6, 1.6, 0.25, at + Vector3(0, 12.05, 0), black)
	_solid_cylinder(1.55, 1.55, 2.6, at + Vector3(0, 13.45, 0), ViewUtil.flat(Color(0.75, 0.85, 0.95, 0.30)))
	for k in 8:
		var a := TAU * k / 8.0
		ViewUtil.cylinder(self, 0.05, 2.6, at + Vector3(cos(a) * 1.55, 13.45, sin(a) * 1.55), black)
	_solid_cylinder(1.7, 1.7, 0.2, at + Vector3(0, 14.85, 0), black)
	var cap := ViewUtil.cylinder(self, 1.75, 1.6, at + Vector3(0, 15.75, 0), red)
	(cap.mesh as CylinderMesh).top_radius = 0.25
	ViewUtil.cylinder(self, 0.28, 0.5, at + Vector3(0, 16.7, 0), black)
	# The lamp: a lens that flashes as the beam sweeps past the viewer,
	# and the beam itself, which turns day and night and only shows at
	# night. Art: it is no record.
	_lamp_mat = ViewUtil.glow(Color(1.0, 0.95, 0.80), 1.0)
	var lens := SphereMesh.new()
	lens.radius = 0.5
	lens.height = 1.0
	_lens = MeshInstance3D.new()
	_lens.mesh = lens
	_lens.position = at + Vector3(0, 13.45, 0)
	_lens.material_override = _lamp_mat
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lens)
	_beam = SpotLight3D.new()
	_beam.position = at + Vector3(0, 13.45, 0)
	_beam.spot_range = 350.0
	_beam.spot_angle = 6.0
	_beam.spot_attenuation = 0.6
	_beam.light_color = Color(1.0, 0.95, 0.82)
	_beam.light_energy = 0.0
	_beam.shadow_enabled = false
	add_child(_beam)
	# The keeper's house: white clapboard, a red gable roof, a chimney;
	# an oil house in brick beside it.
	var house := at + Vector3(9.0, 0.0, 3.0)
	_solid_box(Vector3(8.0, 3.4, 6.5), house + Vector3(0, 1.7, 0), white)
	var roof := PrismMesh.new()
	roof.size = Vector3(7.4, 2.2, 8.8)
	var roof_inst := MeshInstance3D.new()
	roof_inst.mesh = roof
	roof_inst.position = house + Vector3(0, 4.5, 0)
	roof_inst.rotation.y = PI / 2.0
	roof_inst.material_override = red
	add_child(roof_inst)
	_solid_box(Vector3(0.7, 2.4, 0.7), house + Vector3(2.4, 5.0, 1.2), brick)
	for k in 3:
		ViewUtil.box(self, Vector3(0.9, 1.2, 0.05), house + Vector3(-2.4 + 2.4 * k, 1.9, 3.26),
			ViewUtil.flat(Color(0.55, 0.65, 0.75, 0.5)))
	ViewUtil.box(self, Vector3(0.9, 2.0, 0.05), house + Vector3(0, 1.0, -3.26), red)
	var shed := at + Vector3(-7.0, 0.0, 5.0)
	_solid_box(Vector3(2.6, 2.3, 2.6), shed + Vector3(0, 1.15, 0), brick)
	var shed_roof := PrismMesh.new()
	shed_roof.size = Vector3(3.0, 0.9, 3.0)
	var shed_roof_inst := MeshInstance3D.new()
	shed_roof_inst.mesh = shed_roof
	shed_roof_inst.position = shed + Vector3(0, 2.75, 0)
	shed_roof_inst.material_override = red
	add_child(shed_roof_inst)
	# A flagpole on the lawn.
	ViewUtil.cylinder(self, 0.05, 9.0, at + Vector3(4.0, 4.5, -5.0), white)
	_build_river()
	_build_heighliner()


## A hollow hull a mile long: outer skin, the bore through it, annular
## ends, longitudinal spines and rib rings breaking the silhouette,
## and a ring of dim lamps deep in each mouth, the only light on it.
## Dark and matte in its own shader, outside the fog that would
## bleach it at that distance; no shadow (the sun's shadow reaches
## 200 m), no collision (nothing walks there), no sound.
func _build_heighliner() -> void:
	var ship := Node3D.new()
	ship.name = "Heighliner"
	ship.position = SHIP_CENTRE
	ship.rotation = Vector3(SHIP_PITCH, SHIP_YAW, 0.0)
	add_child(ship)
	var hull := _ship_material(Color(0.085, 0.088, 0.095))
	var trim := _ship_material(Color(0.115, 0.115, 0.125))
	var half := SHIP_LENGTH / 2.0
	var tube := _tube_mesh(SHIP_RADIUS, SHIP_BORE, SHIP_LENGTH, 56)
	var body := MeshInstance3D.new()
	body.mesh = tube
	body.material_override = hull
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(body)
	# Spines: eight ridges the length of the hull.
	for k in 8:
		var a := TAU * k / 8.0 + 0.2
		var spine := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(14.0, 9.0, SHIP_LENGTH * 0.92)
		spine.mesh = box
		spine.material_override = trim
		spine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spine.position = Vector3(cos(a), sin(a), 0.0) * (SHIP_RADIUS + 3.0)
		spine.rotation.z = a + PI / 2.0
		ship.add_child(spine)
	# Ribs: rings standing a little proud, closer together toward the ends.
	for zf: float in [-0.44, -0.36, -0.18, 0.0, 0.18, 0.36, 0.44]:
		var rib := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = SHIP_RADIUS + 7.0
		ring.bottom_radius = SHIP_RADIUS + 7.0
		ring.height = 22.0
		ring.radial_segments = 56
		rib.mesh = ring
		rib.material_override = trim
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rib.position = Vector3(0.0, 0.0, zf * SHIP_LENGTH)
		rib.rotation.x = PI / 2.0
		ship.add_child(rib)
	# Lamps: twenty round each mouth, well inside the bore, dim amber.
	var lamp_mat := ViewUtil.glow(Color(1.0, 0.72, 0.38), 3.0)
	var lamp := SphereMesh.new()
	lamp.radius = 5.0
	lamp.height = 10.0
	for end: float in [-1.0, 1.0]:
		for k in 20:
			var a := TAU * k / 20.0
			var light := MeshInstance3D.new()
			light.mesh = lamp
			light.material_override = lamp_mat
			light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			light.position = Vector3(cos(a), sin(a), 0.0) * (SHIP_BORE - 4.0) + Vector3(0.0, 0.0, end * (half - 90.0))
			ship.add_child(light)
	stats["heighliner"] = 1


func _ship_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/heighliner.gdshader")
	mat.set_shader_parameter("hull", color)
	_ship_mats.append(mat)
	return mat


## A tube along local Z: an outer skin, an inner bore facing inward,
## and the flat annulus at each end.
func _tube_mesh(r_out: float, r_in: float, length: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := length / 2.0
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var n_out := Vector3((c0 + c1).x, (c0 + c1).y, 0.0).normalized()
		var o0 := Vector3(c0.x, c0.y, 0.0) * r_out
		var o1 := Vector3(c1.x, c1.y, 0.0) * r_out
		var i0 := Vector3(c0.x, c0.y, 0.0) * r_in
		var i1 := Vector3(c1.x, c1.y, 0.0) * r_in
		var zb := Vector3(0.0, 0.0, -half)
		var zf := Vector3(0.0, 0.0, half)
		# Outer skin, facing out.
		quad.call(o0 + zb, o0 + zf, o1 + zf, o1 + zb, n_out)
		# The bore, facing in.
		quad.call(i1 + zb, i1 + zf, i0 + zf, i0 + zb, -n_out)
		# The ends.
		quad.call(i0 + zf, o0 + zf, o1 + zf, i1 + zf, Vector3(0.0, 0.0, 1.0))
		quad.call(i1 + zb, o1 + zb, o0 + zb, i0 + zb, Vector3(0.0, 0.0, -1.0))
	st.index()
	return st.commit()


## The stream above the head of tide: a water ribbon along the
## centreline at the water's height, wide enough to bury its edges in
## the banks, its own shader flowing down it, and the sound of it
## every thirty-five metres. The tidal reach below needs nothing: the
## sea plane fills it.
func _build_river() -> void:
	var samples: Array[Dictionary] = []
	var s := RIVER_TIDAL + 25.0
	var s_end := RIVER_END - 20.0
	while s <= s_end + 0.01:
		var c := river_centre(s)
		var tangent := (RIVER_DIR + RIVER_PERP * _meander_slope(s)).normalized()
		var across := Vector2(-tangent.y, tangent.x)
		samples.append({"c": Vector3(c.x, river_level(s), c.y), "n": across, "w": river_half(s) + 4.0, "s": s})
		s += 6.0
	river_mat = ShaderMaterial.new()
	river_mat.shader = load("res://world/river.gdshader")
	var ribbon := _water_ribbon(samples, river_mat)
	ribbon.name = "River"
	stats["river_m"] = int(s_end)
	var spots := 0
	var stream: AudioStreamWAV = null
	if DisplayServer.get_name() != "headless":
		stream = _loop_stream("res://audio/river_loop.wav")
	s = RIVER_TIDAL + 15.0
	while s < s_end:
		spots += 1
		if stream != null:
			var c := river_centre(s)
			var p := AudioStreamPlayer3D.new()
			p.stream = stream
			p.position = Vector3(c.x, river_level(s) + 0.5, c.y)
			p.volume_db = -7.0
			p.unit_size = 9.0
			p.max_distance = 90.0
			p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p.bus = "Master"
			add_child(p)
			p.play(_rng.randf() * stream.get_length())
		s += 35.0
	stats["river_emitters"] = spots


func _on_time_of_day(_horizon: float, twilight: float) -> void:
	_night = 1.0 - twilight
	if _beam != null:
		_beam.light_energy = 40.0 * _night
	# The ship's own haze follows the horizon: pale by day, near black
	# at night, so it hangs unseen but for its lamps.
	var haze := Color(0.07, 0.09, 0.15).lerp(Color(0.62, 0.72, 0.84), twilight)
	for mat in _ship_mats:
		mat.set_shader_parameter("haze_color", haze)


func _process(delta: float) -> void:
	super._process(delta)
	if _beam == null:
		return
	_beam_angle = fmod(_beam_angle + delta * TAU / BEAM_PERIOD, TAU)
	_beam.rotation.y = _beam_angle
	# The lens is bright for the moment the beam points at the viewer.
	var cam := get_viewport().get_camera_3d()
	var flash := 0.0
	if cam != null:
		var to_cam := cam.global_position - _lens.global_position
		to_cam.y = 0.0
		if to_cam.length() > 1.0:
			var beam_dir := Vector3(-sin(_beam_angle), 0.0, -cos(_beam_angle))
			flash = smoothstep(0.975, 0.999, beam_dir.dot(to_cam.normalized()))
	# A sweep, not a strobe: the flash rises and falls over a wider arc
	# and peaks lower: at eighty times white it blooms across the whole
	# sky every ten seconds.
	_lamp_mat.emission_energy_multiplier = 1.0 + (6.0 + 24.0 * flash) * _night
