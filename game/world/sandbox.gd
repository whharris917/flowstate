extends WorldBase
## Development sandbox: an infinite outdoor plane under an open sky.
## Collision is a true infinite plane (WorldBoundaryShape3D); the
## visible ground is one big quad that quietly follows the player, with
## a world-space grid shader so movement and placement scale read even
## with no walls anywhere. The starter loop sits on a pad at the origin.

const GROUND_SIZE := 4000.0   # wide enough that the edge stays past the horizon
							  # even from the top of the camera's zoom handle
const PAD_SIZE := Vector3(16.0, 0.16, 12.0)

const COL_PAD := Color(0.47, 0.47, 0.45)
const COL_SAFETY := Color(0.95, 0.78, 0.05)

var _ground: MeshInstance3D
var _stars: MeshInstance3D
var _stars_mat: ShaderMaterial
var _hall_lights: Array[OmniLight3D] = []
var _hall_lamp_mat: StandardMaterial3D = null

# The hall over the showcase (director, 2026-09-12): walls and a roof
# round the developed slab, glass bands for daylight, skylight strips,
# high-bay lights that come up with dusk. Sandbox only.
const HALL_MIN := Vector3(-14.0, 0.0, -12.0)
const HALL_MAX := Vector3(58.0, 18.0, 46.0)
const WALL_T := 0.3
const COL_HALL_WALL := Color(0.82, 0.82, 0.79)
const COL_HALL_ROOF := Color(0.30, 0.31, 0.33)
const COL_HALL_STEEL := Color(0.16, 0.17, 0.19)
const COL_HALL_GLASS := Color(0.72, 0.84, 0.95, 0.22)


func _init() -> void:
	plant_height = 0.08
	plant_save_path = "user://save_sandbox.json"
	with_suite = false     # the aseptic annex lives in the hall
	with_hum = false       # outdoors: no machine-room hum
	reverb_room_size = 0.3
	reverb_wet = 0.05


func _build_world() -> void:
	_build_environment()
	_build_ground()
	_build_forest()
	_build_pad()


## The ground under everything. A site with a landscape (the Maine
## coast) overrides this and _build_forest to put a terrain here.
func _build_ground() -> void:
	# Infinite walkable plane.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)

	# The visible ground: follows the player in _process, grid drawn in
	# world space by the shader so nothing swims when it moves.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	_ground = MeshInstance3D.new()
	_ground.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/ground_grid.gdshader")
	_ground.material_override = mat
	add_child(_ground)


## The clearing: two rings of trees round the developed area, the
## near ring dense and shadowed, the far ring taller and sparser so
## no gap shows the horizon from ground level.
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var clearing := Vector3(16.0, 0.0, 10.0)
	var near := Forest.new()
	near.plant_bushes(clearing, 84.0, 96.0, 3.2, rng)
	near.plant_ring(clearing, 88.0, 130.0, 4.4, 11.0, rng)
	near.finish(true)
	add_child(near)
	var far := Forest.new()
	far.plant_ring(clearing, 130.0, 210.0, 6.5, 16.0, rng)
	far.finish(false)
	add_child(far)


## Home pad under the starter loop: a tiled plant floor with a safety
## stripe at its edge.
func _build_pad() -> void:
	_static_box(PAD_SIZE, Vector3(0, 0, -1.0), COL_PAD, WorldBase.tile_floor())
	var stripe := ViewUtil.box(self, Vector3(PAD_SIZE.x, 0.012, 0.12),
		Vector3(0, 0.09, -1.0 + PAD_SIZE.z / 2.0 - 0.2), ViewUtil.flat(COL_SAFETY))
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_environment() -> void:
	# A physical sky (2026-09-11): scattering, a real sun disc and the
	# haze at the horizon all follow the sun, so dawn and dusk come from
	# the sun's angle rather than from hand-picked colours.
	var physical := PhysicalSkyMaterial.new()
	# A crisp autumn day (director, 2026-09-12): clean air, deep blue,
	# little haze around the sun.
	physical.rayleigh_coefficient = 3.0
	physical.rayleigh_color = Color(0.20, 0.38, 0.90)   # a saturated scatter: the blue survives tone mapping
	physical.mie_coefficient = 0.0025
	physical.mie_eccentricity = 0.75
	physical.turbidity = 2.5
	physical.sun_disk_scale = 1.0
	physical.ground_color = Color(0.36, 0.38, 0.36)
	# set_time_of_day sets the energy: a physical sky is dim at a low
	# sun and needs lifting toward dawn and dusk.
	physical.energy_multiplier = 2.0
	sky_mat = physical
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	sky_env = env
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_bloom = 0.05
	# Contact shadow in the corners and under the skirts: the cheapest
	# thing that makes steel look like it stands on the ground.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.ssao_power = 1.8
	# A whisper of distance fog gives the infinite plane a horizon, and
	# aerial perspective lets the far plant take the sky's colour.
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.84)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.25
	env.fog_sky_affect = 0.0
	# Screen-space reflections: the stainless picks up the ground and
	# the pipes beside it, not only the sky.
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	# Volumetric fog waits on the high-lighting option (with SDFGI).
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.90, 0.93, 0.97)
	env.volumetric_fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 1.8
	sun.light_color = Color(1.0, 0.97, 0.90)
	_sun_base_energy = sun.light_energy
	_sun_base_color = sun.light_color
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0  # the hall roof must shade its whole floor
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.5   # the sun's half-degree: soft penumbrae, a real disc in the sky

	# Stars on a dome that follows the player; visibility follows the clock.
	_stars_mat = ShaderMaterial.new()
	_stars_mat.shader = load("res://world/stars.gdshader")
	var dome := SphereMesh.new()
	dome.radius = 1500.0
	dome.height = 3000.0
	dome.radial_segments = 32
	dome.rings = 16
	_stars = MeshInstance3D.new()
	_stars.mesh = dome
	_stars.material_override = _stars_mat
	_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stars)
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	add_child(sun)


## A commissioned still gives the sandbox something tall with real
## detail on top: overhead pressure gauge on the platform, wired to the
## vapor-line tap. E at the base (or the platform) cycles the reboiler.
func _after_plant() -> void:
	# The developed area stands on one tiled slab, its top flush with
	# the home pad, so the showcase units are on a plant floor and not
	# on the grass; the blank map keeps just the pad.
	_static_box(Vector3(72.0, 0.5, 58.0), Vector3(22.0, plant_height - 0.25, 17.0), COL_PAD,
		WorldBase.tile_floor())
	_build_enclosure()
	plant.place("column", "still_column", {}, Vector3(7.0, 0.08, -4.0), 0.0, true)
	plant.place("gauge_press", "pi_still_top", {}, Vector3(7.5, 9.72, -3.4), PI, true)
	plant.connect_equipment("still_column", "p_top", "pi_still_top", "process",
		[Vector3(7.5, 10.9, -3.3)])
	# The reboiler is a 480 V load like any other: cable from the feeder.
	plant.connect_equipment("plant_mains", "power", "still_column", "power",
		[Vector3(-3.8, 0.3, -0.4), Vector3(7.7, 0.3, -3.5)])
	# The full unit-area showcase: pipe rack, Unit 100 PID loop, MCC
	# room with a PLC-run batch tank, signage.
	Showcase.build(plant)
	# Unit 500: the geometry gallery, art only, nothing simulated — and
	# static, so its thousand primitives become a mesh per look.
	Gallery.build(plant, self)
	var gallery := find_child("Gallery", false, false)
	if gallery != null:
		MeshMerge.merge_view(gallery as Node3D)


func _process(delta: float) -> void:
	super._process(delta)
	if _ground != null:
		_ground.position = Vector3(snappedf(player.global_position.x, 2.0), 0.0,
			snappedf(player.global_position.z, 2.0))
	if _stars != null:
		_stars.position = player.global_position


## Stars come out as twilight goes; the hall lights come up with it.
func _on_time_of_day(_horizon: float, twilight: float) -> void:
	if _stars_mat != null:
		_stars_mat.set_shader_parameter("visibility", 1.0 - twilight)
		# The dome covers the whole sky; by day it drew nothing and still
		# cost the fill (4 fps on the laptop, 2026-09-13).
		_stars.visible = twilight < 0.999
	# Night level set with the director (2026-09-12): 3 was too dim, 9
	# too bright; 5.5 is a lit night shift.
	for light in _hall_lights:
		light.light_energy = lerpf(5.5, 1.2, twilight)
	if _hall_lamp_mat != null:
		_hall_lamp_mat.emission_energy_multiplier = lerpf(4.5, 1.5, twilight)


## ---- the hall -------------------------------------------------------------

func _build_enclosure() -> void:
	# Everything the hall is made of goes under one node and is merged
	# into a mesh per look at the end (2026-09-13): the lamp lenses
	# share their material, so the night glow still reaches them.
	var hall := Node3D.new()
	hall.name = "Hall"
	add_child(hall)
	_box_parent = hall
	var y0 := plant_height
	var top := HALL_MAX.y
	var cx := (HALL_MIN.x + HALL_MAX.x) / 2.0
	var cz := (HALL_MIN.z + HALL_MAX.z) / 2.0
	var lx := HALL_MAX.x - HALL_MIN.x
	var lz := HALL_MAX.z - HALL_MIN.z
	# Up each wall: sill, window band, then wall to the roof (the
	# clerestory came out, director 2026-09-12; daylight from above is
	# the skylights' job).
	var bands: Array = [[0.0, 2.6, false], [2.6, 5.6, true], [5.6, top, false]]
	# Roller-door openings in the sill band: west by the pad, east by
	# Unit 300. Their lintel is the window band.
	_wall(Vector3(HALL_MIN.x, y0, cz), lz, true, bands, [-6.0, 2.0])
	_wall(Vector3(HALL_MAX.x, y0, cz), lz, true, bands, [8.0, 16.0])
	_wall(Vector3(cx, y0, HALL_MIN.z), lx, false, bands, [])
	_wall(Vector3(cx, y0, HALL_MAX.z), lx, false, bands, [])
	# Roof: 4 m panels with 2 m skylight strips between, running the
	# hall's depth, so the sun comes in in stripes.
	var x := HALL_MIN.x
	while x < HALL_MAX.x - 0.01:
		var w := minf(4.0, HALL_MAX.x - x)
		_static_box(Vector3(w, 0.3, lz), Vector3(x + w / 2.0, y0 + top + 0.15, cz), COL_HALL_ROOF)
		x += w
		if x < HALL_MAX.x - 0.01:
			var g := minf(2.0, HALL_MAX.x - x)
			_glass_box(Vector3(g, 0.12, lz), Vector3(x + g / 2.0, y0 + top + 0.06, cz))
			x += g
	# Steel: a column at each wall every 12 m and a roof beam across.
	var bx := HALL_MIN.x + 6.0
	while bx < HALL_MAX.x:
		for wall_z: float in [HALL_MIN.z + 0.45, HALL_MAX.z - 0.45]:
			_static_box(Vector3(0.45, top, 0.45), Vector3(bx, y0 + top / 2.0, wall_z), COL_HALL_STEEL)
		_static_box(Vector3(0.5, 0.8, lz - 0.6), Vector3(bx, y0 + top - 0.4, cz), COL_HALL_STEEL)
		bx += 12.0
	# High-bay lights on a 12 m grid under the beams.
	_hall_lamp_mat = ViewUtil.glow(Color(1.0, 0.97, 0.90), 2.0)
	var fx := HALL_MIN.x + 6.0
	while fx < HALL_MAX.x:
		var fz := HALL_MIN.z + 6.0
		while fz < HALL_MAX.z:
			_high_bay(Vector3(fx, y0 + top - 1.3, fz))
			fz += 12.0
		fx += 12.0
	_box_parent = null
	MeshMerge.merge_view(hall)


## One wall as its bands; a door interval (in the wall's long axis,
## world coordinates) is cut from the sill band only.
func _wall(center: Vector3, length: float, along_z: bool, bands: Array, door: Array) -> void:
	for band: Array in bands:
		var b0 := float(band[0])
		var b1 := float(band[1])
		var glass := bool(band[2])
		var h := b1 - b0
		var y := center.y + b0 + h / 2.0
		var segments: Array = [[-length / 2.0, length / 2.0]]
		if not door.is_empty() and b0 == 0.0:
			var along := center.z if along_z else center.x
			segments = [[-length / 2.0, float(door[0]) - along], [float(door[1]) - along, length / 2.0]]
		for seg: Array in segments:
			var s0 := float(seg[0])
			var s1 := float(seg[1])
			if s1 - s0 <= 0.01:
				continue
			var mid := (s0 + s1) / 2.0
			var size := Vector3(WALL_T, h, s1 - s0) if along_z else Vector3(s1 - s0, h, WALL_T)
			var pos := Vector3(center.x, y, center.z + mid) if along_z else Vector3(center.x + mid, y, center.z)
			if glass:
				_glass_box(size, pos)
			else:
				_static_box(size, pos, COL_HALL_WALL)


## Glass: walkable-into, see-through, and no shadow, so the sun comes
## through it.
func _glass_box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = ViewUtil.flat(COL_HALL_GLASS)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	(_box_parent if _box_parent != null else self).add_child(body)


## A high-bay fixture: a lit housing and the light it throws.
func _high_bay(pos: Vector3) -> void:
	var holder: Node3D = _box_parent if _box_parent != null else self
	ViewUtil.box(holder, Vector3(1.2, 0.18, 0.5), pos + Vector3(0, 0.12, 0), ViewUtil.flat(COL_HALL_STEEL))
	var lens := ViewUtil.box(holder, Vector3(1.1, 0.04, 0.42), pos, _hall_lamp_mat)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, -0.3, 0)
	light.light_color = Color(1.0, 0.96, 0.88)
	light.light_energy = 1.0
	light.omni_range = 40.0
	light.omni_attenuation = 1.1
	light.shadow_enabled = false
	add_child(light)
	_hall_lights.append(light)
