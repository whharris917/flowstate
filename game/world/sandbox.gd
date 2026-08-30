extends WorldBase
## Development sandbox: an infinite outdoor plane under an open sky.
## Collision is a true infinite plane (WorldBoundaryShape3D); the
## visible ground is one big quad that quietly follows the player, with
## a world-space grid shader so movement and placement scale read even
## with no walls anywhere. The starter loop sits on a pad at the origin.

const GROUND_SIZE := 600.0
const PAD_SIZE := Vector3(16.0, 0.16, 12.0)

const COL_PAD := Color(0.55, 0.55, 0.53)
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

	# Home pad under the starter loop, with a safety stripe at its edge.
	_static_box(PAD_SIZE, Vector3(0, 0, -1.0), COL_PAD)
	var stripe := ViewUtil.box(self, Vector3(PAD_SIZE.x, 0.012, 0.12),
		Vector3(0, 0.09, -1.0 + PAD_SIZE.z / 2.0 - 0.2), ViewUtil.flat(COL_SAFETY))
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.48, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.84)
	sky_mat.ground_bottom_color = Color(0.24, 0.27, 0.25)
	sky_mat.ground_horizon_color = Color(0.62, 0.67, 0.68)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	# A whisper of distance fog gives the infinite plane a horizon.
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.84)
	env.fog_density = 0.0012
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


## A commissioned still gives the sandbox something tall with real
## detail on top: overhead pressure gauge on the platform, wired to the
## vapor-line tap. E at the base (or the platform) cycles the reboiler.
func _after_plant() -> void:
	plant.place("column", "still_column", {}, Vector3(7.0, 0.08, -4.0), 0.0, true)
	plant.place("gauge_press", "pi_still_top", {}, Vector3(7.5, 9.72, -3.4), PI, true)
	plant.connect_equipment("still_column", "p_top", "pi_still_top", "process",
		[Vector3(7.5, 10.9, -3.3)])


func _process(delta: float) -> void:
	super._process(delta)
	_ground.position = Vector3(snappedf(player.global_position.x, 2.0), 0.0,
		snappedf(player.global_position.z, 2.0))
