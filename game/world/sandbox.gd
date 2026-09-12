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


func _init() -> void:
	plant_height = 0.08
	plant_save_path = "user://save_sandbox.json"
	with_suite = false     # the aseptic annex lives in the hall
	with_hum = false       # outdoors: no machine-room hum
	reverb_room_size = 0.3
	reverb_wet = 0.05


func _build_world() -> void:
	_build_environment()

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

	# The clearing: two rings of trees round the developed area, the
	# near ring dense and shadowed, the far ring taller and sparser so
	# no gap shows the horizon from ground level.
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

	# Home pad under the starter loop: a tiled plant floor with a safety
	# stripe at its edge.
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
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.5   # the sun's half-degree: soft penumbrae, a real disc in the sky
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
	# Unit 500: the geometry gallery, art only, nothing simulated.
	Gallery.build(plant, self)


func _process(delta: float) -> void:
	super._process(delta)
	_ground.position = Vector3(snappedf(player.global_position.x, 2.0), 0.0,
		snappedf(player.global_position.z, 2.0))
