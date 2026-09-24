class_name OverflowSheet
extends Node3D
## A vessel running over: liquid spilling from its top and
## running down the shell to the floor, where it splashes and pools.
## Driven by the record's own meter, `overflowed_l`: the rate is what
## that counter gained, smoothed over half a second, since the scan
## gains it in 50 ms steps and the frames between gain nothing. Nothing
## shows while the vessel holds; the sheet's opacity, the splash and the
## pour's loudness follow the rate, and the puddle is the volume spilled
## lately, spread thin (SpillPuddle).

const SMOOTH_S := 0.5
const SIDES := 40
const G := 9.81

var lps := 0.0                 # the smoothed overflow rate
var _last_l := -1.0
var _sheet: MeshInstance3D
var _mat: ShaderMaterial
var _splash: GPUParticles3D
var _splash_proc: ParticleProcessMaterial
var _puddle: SpillPuddle
var _pour: EquipmentAudio = null
var _built_h := -1.0
var _built_r := -1.0


static func make(parent: Node3D) -> OverflowSheet:
	var sheet := OverflowSheet.new()
	parent.add_child(sheet)
	sheet._build()
	return sheet


func _build() -> void:
	_sheet = MeshInstance3D.new()
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://components/falling_water.gdshader") as Shader
	_mat.set_shader_parameter("around", 60.0)
	_mat.set_shader_parameter("streak_m", 0.25)
	_mat.set_shader_parameter("rivulets", 18.0)
	_sheet.material_override = _mat
	_sheet.visible = false
	add_child(_sheet)
	_splash_proc = ParticleProcessMaterial.new()
	_splash_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_splash_proc.emission_ring_axis = Vector3.UP
	_splash_proc.emission_ring_height = 0.0
	_splash_proc.direction = Vector3.UP
	_splash_proc.spread = 60.0
	_splash_proc.gravity = Vector3(0, -G, 0)
	_splash_proc.initial_velocity_min = 0.4
	_splash_proc.initial_velocity_max = 1.2
	_splash_proc.scale_min = 0.4
	_splash_proc.scale_max = 1.1
	_splash = GPUParticles3D.new()
	_splash.emitting = false
	_splash.amount = 16
	_splash.lifetime = 0.35
	_splash.process_material = _splash_proc
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drop := SphereMesh.new()
	drop.radius = 0.006
	drop.height = 0.013
	drop.radial_segments = 8
	drop.rings = 4
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.66, 0.82, 0.93, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	drop.material = water
	_splash.draw_pass_1 = drop
	add_child(_splash)
	_puddle = SpillPuddle.make(self)
	if DisplayServer.get_name() != "headless":
		_pour = EquipmentAudio.make(self, "res://audio/pour_loop.wav", Vector3.ZERO, -16.0)


## The vessel's counter this frame, and its size.
func update(overflowed_l: float, height_m: float, radius_m: float, delta: float) -> void:
	var rate := 0.0
	if _last_l >= 0.0 and overflowed_l >= _last_l and delta > 0.0:
		rate = (overflowed_l - _last_l) / delta
	_last_l = overflowed_l   # a load or an undo that lowers it starts afresh
	lps += (rate - lps) * clampf(delta / SMOOTH_S, 0.0, 1.0)
	if lps < 1e-5:
		lps = 0.0
	# The sheet stands just outside the shell and its base ring.
	var r := radius_m + 0.055
	_puddle.min_radius = r
	_puddle.feed(lps, global_position, delta)
	if lps <= 0.0:
		_sheet.visible = false
		_splash.emitting = false
		if _pour != null:
			_pour.set_running(false)
		return
	if absf(height_m - _built_h) > 0.005 or absf(r - _built_r) > 0.005:
		_build_sheet(height_m, r)
	_sheet.visible = true
	# A film running down a wall is slowed by it; half the free-fall speed
	# over the height, no faster than a few metres a second.
	var speed := clampf(0.5 * sqrt(2.0 * G * height_m), 0.3, 3.0)
	_mat.set_shader_parameter("speed", speed)
	# A trickle runs down in a few rivulets; a litre a second wets about
	# a third of the shell; thirty, all of it.
	_mat.set_shader_parameter("alpha", clampf(0.35 + 0.1 * sqrt(lps), 0.35, 0.6))
	_mat.set_shader_parameter("coverage", clampf(0.15 + 0.15 * sqrt(lps), 0.15, 1.0))
	_splash_proc.emission_ring_radius = r
	_splash_proc.emission_ring_inner_radius = r - 0.01
	var amount := clampi(int(lps * 150.0), 8, 200)
	if _splash.amount != amount:
		_splash.amount = amount
	_splash.position = Vector3(0, 0.01, 0)
	_splash.emitting = true
	if _pour != null:
		_pour.volume_db = clampf(-20.0 + 6.0 * log(maxf(lps, 0.01) / 0.01) / log(2.0), -20.0, -4.0)
		_pour.set_running(true)


## An open tube from the top edge to the floor, UV.y 0 at the top.
func _build_sheet(height_m: float, r: float) -> void:
	_built_h = height_m
	_built_r = r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 2:
		var y := height_m if ring == 0 else 0.0
		for k in SIDES + 1:
			var ang := TAU * float(k) / float(SIDES)
			var n := Vector3(cos(ang), 0, sin(ang))
			st.set_color(Color(1, 1, 1, 1))
			st.set_uv(Vector2(float(k) / float(SIDES), float(ring)))
			st.set_normal(n)
			st.add_vertex(n * r + Vector3(0, y, 0))
	for k in SIDES:
		var a := k
		var b := k + SIDES + 1
		st.add_index(a)
		st.add_index(b)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(b)
		st.add_index(b + 1)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	_sheet.mesh = mesh
	_mat.set_shader_parameter("length_m", height_m)
