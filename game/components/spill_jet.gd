class_name SpillJet
extends Node3D
## What leaves an open pipe end, drawn and heard off the real flow
## (2026-09-22; it replaced DripStream, which drew a straight column
## down from the lip whatever the flow). The liquid leaves the end along
## the pipe's axis at its real exit speed -- the flow the kernel solved
## over the bore's area -- and falls on a true parabola to what it lands
## on, the liquid in an open vessel or the floor:
##
##   v0 = Q / A along the nozzle,  p(t) = p0 + v0 t + g t^2 / 2
##
## Below STREAM_LPS it is drops, each an event off the rate with a drip
## where it lands (a drop is a twentieth of a millilitre, so a millilitre
## a second is twenty a second). Above it, a coherent stream whose width
## follows continuity (the same flow at a higher speed needs less area,
## so it narrows as it falls), thinning into spray that disperses the
## further it falls; a splash where it lands, sized by the flow and the
## impact speed; and on the floor a puddle (SpillPuddle). Streaks in the
## stream move at the stream's own speed.
##
## World space throughout (top_level): the owner hands it the end's
## position and axis each frame.

const DROP_ML := 0.05        # one drop
const STREAM_LPS := 0.003    # sixty drops a second: a stream, not drips
const POOL := 6              # drip players in flight at once
const G := 9.81
const SAMPLES := 24          # points along the stream's centreline
const SIDES := 10            # around it
const BREAKUP_D := 60.0      # bore diameters before the core is mostly spray

var _drops: GPUParticles3D
var _drops_proc: ParticleProcessMaterial
var _spray: GPUParticles3D
var _spray_proc: ParticleProcessMaterial
var _splash: GPUParticles3D
var _splash_proc: ParticleProcessMaterial
var _core: MeshInstance3D
var _core_mat: ShaderMaterial
var _puddle: SpillPuddle
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next := 0
var _debt := 0.0
var _pour: EquipmentAudio = null
var _drop_index := 0
# What the core was last built for: rebuilt when any moves by a few percent.
var _built_key := PackedFloat64Array([-1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _landing := Vector3.ZERO


static func make(parent: Node3D) -> SpillJet:
	var jet := SpillJet.new()
	jet.top_level = true
	parent.add_child(jet)
	jet._build()
	return jet


func _water() -> StandardMaterial3D:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.66, 0.82, 0.93, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	water.metallic_specular = 0.8
	return water


func _particles(radius: float, material: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.local_coords = false
	p.amount = 4
	p.lifetime = 0.5
	p.randomness = 0.1
	p.process_material = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drop := SphereMesh.new()
	drop.radius = radius
	drop.height = radius * 2.2
	drop.radial_segments = 8
	drop.rings = 4
	drop.material = _water()
	p.draw_pass_1 = drop
	add_child(p)
	return p


func _build() -> void:
	# Drops: small spheres leaving the lip under gravity.
	_drops_proc = ParticleProcessMaterial.new()
	_drops_proc.spread = 3.0
	_drops_proc.gravity = Vector3(0, -G, 0)
	_drops = _particles(0.007, _drops_proc)
	# Spray: the stream breaking up, the same trajectory, dispersing.
	_spray_proc = ParticleProcessMaterial.new()
	_spray_proc.gravity = Vector3(0, -G, 0)
	_spray_proc.scale_min = 0.5
	_spray_proc.scale_max = 1.3
	_spray_proc.turbulence_enabled = true
	_spray_proc.turbulence_noise_strength = 1.0
	_spray_proc.turbulence_noise_scale = 1.5
	_spray = _particles(0.005, _spray_proc)
	# Splash: thrown up and out where it lands.
	_splash_proc = ParticleProcessMaterial.new()
	_splash_proc.direction = Vector3.UP
	_splash_proc.spread = 70.0
	_splash_proc.gravity = Vector3(0, -G, 0)
	_splash_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_splash_proc.scale_min = 0.4
	_splash_proc.scale_max = 1.1
	_splash = _particles(0.006, _splash_proc)
	# The coherent stream: a tube along the parabola, built as it changes.
	_core = MeshInstance3D.new()
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = load("res://components/falling_water.gdshader") as Shader
	_core.material_override = _core_mat
	_core.visible = false
	add_child(_core)
	_puddle = SpillPuddle.make(self)
	if DisplayServer.get_name() != "headless":
		for i in POOL:
			var player := AudioStreamPlayer3D.new()
			player.stream = load("res://audio/drip_%d.wav" % (i % 3 + 1)) as AudioStreamWAV
			player.bus = "Room"
			player.unit_size = 3.0
			player.max_distance = 22.0
			player.volume_db = -10.0
			player.top_level = true
			add_child(player)
			_pool.append(player)
		_pour = EquipmentAudio.make(self, "res://audio/pour_loop.wav", Vector3.ZERO, -14.0)


## The exit speed of `lps` through a bore of this diameter, m/s.
static func exit_speed(lps: float, bore_d_m: float) -> float:
	var area := PI * bore_d_m * bore_d_m / 4.0
	return maxf(lps, 0.0) * 0.001 / maxf(area, 1e-8)


## The time a jet leaving `origin` with velocity `v0` takes to fall to
## height `y`, or -1 if it never gets there.
static func time_to(origin: Vector3, v0: Vector3, y: float) -> float:
	var drop := origin.y - y
	var disc := v0.y * v0.y + 2.0 * G * drop
	if disc < 0.0:
		return -1.0
	return (v0.y + sqrt(disc)) / G


static func point_at(origin: Vector3, v0: Vector3, t: float) -> Vector3:
	return origin + v0 * t + Vector3(0, -0.5 * G * t * t, 0)


## The state this frame: the flow leaving the end (L/s), the end's
## position and outward axis (world), the bore's diameter, the height it
## lands at and whether that is liquid in a vessel (no puddle) or the
## floor.
func set_state(lps: float, origin: Vector3, axis: Vector3, bore_d_m: float, landing_y: float,
		into_liquid: bool, delta: float) -> void:
	lps = maxf(lps, 0.0)
	var dir := axis.normalized() if axis.length() > 1e-6 else Vector3.DOWN
	var v0 := dir * exit_speed(lps, bore_d_m)
	var t_land := time_to(origin, v0, landing_y)
	if t_land <= 0.0:
		t_land = 0.05
	_landing = point_at(origin, v0, t_land)
	_puddle.feed(0.0 if into_liquid else lps, Vector3(_landing.x, landing_y, _landing.z), delta)
	if lps <= 1e-7:
		_stop()
		return
	if lps < STREAM_LPS:
		_draw_drops(lps, origin, v0, t_land, delta)
	else:
		_draw_stream(lps, origin, v0, bore_d_m, t_land)


func _stop() -> void:
	_drops.emitting = false
	_spray.emitting = false
	_splash.emitting = false
	_core.visible = false
	if _pour != null:
		_pour.set_running(false)
	_debt = 0.0


func _draw_drops(lps: float, origin: Vector3, v0: Vector3, t_land: float, delta: float) -> void:
	_core.visible = false
	_spray.emitting = false
	_splash.emitting = false
	if _pour != null:
		_pour.set_running(false)
	_drops.global_position = origin
	var speed := v0.length()
	_drops_proc.direction = v0.normalized() if speed > 1e-4 else Vector3.DOWN
	_drops_proc.initial_velocity_min = speed * 0.9
	_drops_proc.initial_velocity_max = speed * 1.1 + 0.05
	var drops_per_s := lps * 1000.0 / DROP_ML
	var flight := t_land + 0.05
	var amount := maxi(int(ceil(drops_per_s * flight)) + 1, 2)
	if _drops.amount != amount or absf(_drops.lifetime - flight) > 0.01:
		_drops.amount = amount
		_drops.lifetime = flight
	_drops.emitting = true
	# A drip for each drop, where it lands.
	_debt += drops_per_s * delta
	var played := 0
	while _debt >= 1.0 and played < 3:
		_debt -= 1.0
		played += 1
		_drop_index += 1
		if _pool.is_empty():
			continue
		var player := _pool[_pool_next]
		_pool_next = (_pool_next + 1) % _pool.size()
		player.global_position = _landing
		# The pitch wanders a little from drop to drop, as drops do.
		player.pitch_scale = 0.9 + 0.25 * float((_drop_index * 7) % 5) / 4.0
		player.play()
	if _debt > 3.0:
		_debt = 3.0   # a hitch is not repaid with a burst


func _draw_stream(lps: float, origin: Vector3, v0: Vector3, bore_d_m: float, t_land: float) -> void:
	_drops.emitting = false
	_debt = 0.0
	var speed := v0.length()
	var key := PackedFloat64Array([lps, origin.x, origin.y, origin.z, v0.x, v0.y, v0.z, t_land])
	if _needs_rebuild(key):
		_build_core(lps, origin, v0, bore_d_m, t_land)
		_built_key = key
	_core.visible = true
	# Spray: the same trajectory with a spread, more of it the more flows.
	_spray.global_position = origin
	_spray_proc.direction = v0.normalized() if speed > 1e-4 else Vector3.DOWN
	_spray_proc.spread = clampf(2.0 + 25.0 * lps, 2.0, 12.0)
	_spray_proc.initial_velocity_min = speed * 0.92
	_spray_proc.initial_velocity_max = speed * 1.05 + 0.02
	_spray_proc.turbulence_influence_min = 0.01
	_spray_proc.turbulence_influence_max = clampf(0.02 + 0.03 * speed, 0.02, 0.12)
	var spray_amount := clampi(int(lps * 400.0), 12, 256)
	if _spray.amount != spray_amount or absf(_spray.lifetime - t_land) > 0.02:
		_spray.amount = spray_amount
		_spray.lifetime = maxf(t_land, 0.05)
	_spray.emitting = true
	# Splash: thrown up by the speed it lands at.
	var impact := (v0 + Vector3(0, -G * t_land, 0)).length()
	var up := clampf(0.22 * impact, 0.2, 2.2)
	_splash.global_position = _landing
	_splash_proc.emission_sphere_radius = clampf(sqrt(lps * 0.001 / (PI * maxf(impact, 0.1))) * 2.0, 0.01, 0.15)
	_splash_proc.initial_velocity_min = up * 0.4
	_splash_proc.initial_velocity_max = up
	var splash_amount := clampi(int(lps * 200.0), 8, 160)
	var splash_life := clampf(2.0 * up / G + 0.1, 0.15, 0.6)
	if _splash.amount != splash_amount or absf(_splash.lifetime - splash_life) > 0.02:
		_splash.amount = splash_amount
		_splash.lifetime = splash_life
	_splash.emitting = true
	if _pour != null:
		_pour.global_position = _landing
		# -22 dB at the threshold, up to -4 dB at a litre a second.
		_pour.volume_db = clampf(-22.0 + 7.0 * log(lps / STREAM_LPS) / log(2.0), -22.0, -4.0)
		_pour.set_running(true)


func _needs_rebuild(key: PackedFloat64Array) -> bool:
	if _built_key[0] < 0.0:
		return true
	if absf(key[0] - _built_key[0]) > 0.03 * maxf(key[0], 1e-6):
		return true
	for i in range(1, key.size()):
		if absf(key[i] - _built_key[i]) > 0.01:
			return true
	return false


## The coherent stream as a tube along the parabola. Its radius is the
## jet's own by continuity -- the flow over the speed it has reached --
## drawn no thinner than can be seen; its opacity fades as it breaks up
## into spray over BREAKUP_D bore diameters.
func _build_core(lps: float, origin: Vector3, v0: Vector3, bore_d_m: float, t_land: float) -> void:
	var q := lps * 0.001
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.0
	var points: Array[Vector3] = []
	for i in SAMPLES + 1:
		var t := t_land * float(i) / float(SAMPLES)
		points.append(point_at(origin, v0, t) - origin)
		if i > 0:
			length += points[i].distance_to(points[i - 1])
	var breakup := BREAKUP_D * maxf(bore_d_m, 0.004)
	var walked := 0.0
	for i in SAMPLES + 1:
		var t := t_land * float(i) / float(SAMPLES)
		var vel := v0 + Vector3(0, -G * t, 0)
		var tangent := vel.normalized() if vel.length() > 1e-5 else Vector3.DOWN
		var side := tangent.cross(Vector3.UP)
		if side.length() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		var normal := side.cross(tangent).normalized()
		var r := sqrt(q / (PI * maxf(vel.length(), 0.05)))
		r = clampf(r, 0.003, 0.2)
		if i > 0:
			walked += points[i].distance_to(points[i - 1])
		var fade := clampf(1.0 - 0.7 * walked / maxf(breakup, 0.01), 0.3, 1.0)
		for k in SIDES + 1:
			var ang := TAU * float(k) / float(SIDES)
			var offset := (side * cos(ang) + normal * sin(ang)) * r
			st.set_color(Color(1, 1, 1, fade))
			st.set_uv(Vector2(float(k) / float(SIDES), walked / maxf(length, 1e-4)))
			st.set_normal((side * cos(ang) + normal * sin(ang)).normalized())
			st.add_vertex(points[i] + offset)
	for i in SAMPLES:
		for k in SIDES:
			var a := i * (SIDES + 1) + k
			var b := a + SIDES + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.commit(mesh)
	_core.mesh = mesh
	_core.global_position = origin
	_core.global_basis = Basis.IDENTITY
	_core_mat.set_shader_parameter("length_m", maxf(length, 0.01))
	var mean_speed := length / maxf(t_land, 0.01)
	_core_mat.set_shader_parameter("speed", mean_speed)
	_core_mat.set_shader_parameter("alpha", clampf(0.55 + 0.25 * lps, 0.55, 0.8))
