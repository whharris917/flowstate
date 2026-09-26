class_name Weather
extends Node3D
## The weather over the harbour town, from one level: 0 a fair day, a
## few clouds; then cloud building to an overcast; a drizzle; at 1 a
## storm out over the sea, a low scud racing in under the deck, the
## lightning flickering in the cloud on the horizon and its thunder
## rolling in soft from miles off, a wind, whitecaps outside and a sea
## running in the harbour. Art and sound only: no records.
##
## The level sets what the weather is; the world's clock and the level
## together set the light (apply_light, called whenever either moves):
## the sun dimmed by the cloud, the sky greyed, the fog drawn in, and a
## darkness from 0 to 1 that the town's lamps and windows answer. Every
## frame it carries the clouds on the wind, keeps the rain round the
## player, wets the streets as it rains and dries them after, and
## throws the lightning: strokes at random through a storm, three to
## eleven kilometres out, most seen only as the cloud lighting, the odd
## channel showing low on the horizon, each one's thunder arriving at
## the speed of sound from where it struck.

const CLOUD_DOME := 3500.0
const SOUND := 343.0            # m/s
const TOWN_CENTRE := Vector2(15.0, 10.0)

var level := 0.0
var cover := 0.0                # the high deck, 0 clear to 1 overcast
var scud := 0.0                 # the low deck
var storm := 0.0                # how dark and wild
var rain := 0.0
var lightning := 0.0            # how often it strikes
var wind := 0.0                 # 0 calm to 1 a gale
var fog := 0.0
var wet := 0.0                  # how wet the surfaces are: follows the rain, dries slowly
var night := 0.0                # 0 daylight to 1 dark, cloud included
var wind_dir := Vector2(-0.7071, -0.7071)   # where it blows toward: in off the sea
var strikes := 0
var lamps_on := false
var indoors := false            # a roof over the player: the weather and the sea heard through it
var bell_blocked := false       # no clear line from the player to the bell buoy

var world: WorldBase
var coast: TownCoast
var town: HarborTown
var harbor: Harbor
var clouds_mat: ShaderMaterial
var _clouds: MeshInstance3D
var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _flash_light: DirectionalLight3D
var _bolt: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _drift_high := Vector2.ZERO
var _drift_low := Vector2.ZERO
var _t := 0.0
var _next_strike := 6.0
var _pulses: Array[Vector2] = []            # (start time, strength)
var _flash := 0.0
var _flash_dir := Vector3(0.7, 0.2, 0.7)
var _flash_reach := 0.0                     # how much of the stroke's light reaches the town
var _sky_lit := false
var _thunder: Array[Dictionary] = []        # {at, file, volume, dir}
var _rain_audio: AudioStreamPlayer
var _gale_audio: AudioStreamPlayer
var _lamps_since := 1000.0
var _sun_color := Color.WHITE
var _sun_energy := 1.0
var _ambient_energy := 0.6
var _rng := RandomNumberGenerator.new()
var _headless := false
var _listen_left := 0.0
var _outdoor_cut := 20000.0
var _bell_cut := 20000.0


func setup(w: WorldBase, c: TownCoast, t: HarborTown, h: Harbor) -> void:
	world = w
	coast = c
	town = t
	harbor = h
	name = "Weather"
	_rng.seed = 1938
	_headless = DisplayServer.get_name() == "headless"
	_build_clouds()
	_build_rain()
	_build_lightning()
	_build_sound()


## ---- the level ---------------------------------------------------------------

## The weather from its one number; the light follows when the world
## next applies it.
func set_level(l: float) -> void:
	level = clampf(l, 0.0, 1.0)
	cover = clampf(0.22 + 0.78 * smoothstep(0.08, 0.55, level), 0.0, 1.0)
	scud = smoothstep(0.55, 0.9, level)
	storm = smoothstep(0.45, 1.0, level)
	rain = smoothstep(0.55, 0.85, level)
	lightning = smoothstep(0.78, 1.0, level)
	wind = 0.15 + 0.85 * smoothstep(0.25, 1.0, level)
	fog = smoothstep(0.6, 1.0, level)
	if clouds_mat != null:
		clouds_mat.set_shader_parameter("cover", cover)
		clouds_mat.set_shader_parameter("scud", scud)
		clouds_mat.set_shader_parameter("storm", storm)
		clouds_mat.set_shader_parameter("wind_dir", wind_dir)
	var sea := coast.sea_mat
	if sea != null:
		sea.set_shader_parameter("swell", 1.0 + 1.4 * storm)
		sea.set_shader_parameter("chop", 1.0 + 2.2 * wind * wind)
		sea.set_shader_parameter("whitecaps", smoothstep(0.55, 1.0, level))
		sea.set_shader_parameter("rain", rain)
	harbor.swell = 1.0 + 1.4 * storm
	for mat in TreeKit.materials():
		mat.set_shader_parameter("wind", wind)
		mat.set_shader_parameter("wind_dir", wind_dir)
	harbor.wind_dir = wind_dir
	if _rain != null:
		_rain.emitting = rain > 0.01
		_rain.amount_ratio = clampf(rain, 0.05, 1.0)
		_rain_process.direction = Vector3(wind_dir.x * 0.6 * wind, -1.0, wind_dir.y * 0.6 * wind).normalized()
	if _headless or not is_inside_tree():
		wet = rain


## How much cloud stands between the sun and the ground, past the few
## fair-weather clouds that dim nothing.
func overcast() -> float:
	return clampf((cover - 0.3) / 0.7, 0.0, 1.0)


## ---- the light ---------------------------------------------------------------

## The world has set the sun, the sky and the ambient for the clock;
## the cloud takes its share of them, draws the fog in, and says how
## dark it is.
func apply_light(horizon: float, twilight: float) -> void:
	var sun := world.sun
	var env := world.sky_env
	var o := overcast()
	_sun_color = sun.light_color
	_sun_energy = sun.light_energy
	sun.light_energy *= 1.0 - 0.93 * o
	var amb := env.ambient_light_color
	var grey := Color(amb.get_luminance(), amb.get_luminance(), amb.get_luminance() * 1.08)
	env.ambient_light_color = amb.lerp(grey, 0.7 * o)
	env.ambient_light_energy *= 1.0 - 0.2 * storm
	_ambient_energy = env.ambient_light_energy
	var horizon_col := env.fog_light_color
	var fog_col := horizon_col.lerp(Color(horizon_col.get_luminance(), horizon_col.get_luminance(), horizon_col.get_luminance() * 1.1), o)
	env.fog_light_color = fog_col * (1.0 - 0.55 * storm)
	env.fog_density = 0.0009 + 0.0055 * fog + 0.0012 * rain
	env.fog_sky_affect = 0.55 * fog
	var painted := world.sky_mat as ShaderMaterial
	if painted != null:
		painted.set_shader_parameter("overcast", 0.95 * o)
		painted.set_shader_parameter("energy", 1.0 - 0.45 * storm)
	# The darkness the lamps and windows answer to.
	var daylight := twilight * (0.3 + 0.7 * horizon) * (1.0 - 0.65 * o)
	night = 1.0 - daylight
	town.glass_mat.set_shader_parameter("night", night)
	harbor.night = night
	if clouds_mat != null:
		var sun_lin := Color(_sun_color.r, _sun_color.g, _sun_color.b).srgb_to_linear()
		var sky_lin := env.ambient_light_color.srgb_to_linear() * Color(0.82, 0.9, 1.08)
		var sun_dir := world.sun.global_transform.basis.z
		var painted_sun: Variant = painted.get_shader_parameter("sun_dir") if painted != null else null
		if painted_sun is Vector3:
			sun_dir = painted_sun
		clouds_mat.set_shader_parameter("sun_dir", sun_dir)
		# Under a deck the eye sees its underside, which the sun does not reach.
		clouds_mat.set_shader_parameter("sun_light", Vector3(sun_lin.r, sun_lin.g, sun_lin.b) * _sun_energy * 0.55 * twilight * (1.0 - 0.85 * o))
		clouds_mat.set_shader_parameter("sky_light", Vector3(sky_lin.r, sky_lin.g, sky_lin.b) * _ambient_energy * 1.4)
		var fog_lin := env.fog_light_color.srgb_to_linear()
		clouds_mat.set_shader_parameter("horizon_color", Vector3(fog_lin.r, fog_lin.g, fog_lin.b) * (0.5 + 0.5 * twilight) * (1.0 - 0.4 * storm))
	coast.beam_mat.set_shader_parameter("density", smoothstep(0.5, 0.85, night) * (0.25 + 0.75 * maxf(fog, rain)))
	_switch_lamps()


## The photocells: the lamps come on as it gets dark and go off as it
## gets light, each on its own few seconds' delay.
func _switch_lamps() -> void:
	var want := night > (0.52 if lamps_on else 0.58)
	if want != lamps_on:
		lamps_on = want
		_lamps_since = 0.0 if is_inside_tree() and not _headless else 1000.0
	town.lamp_mat.set_shader_parameter("switched_on", lamps_on)
	_update_lamps()


func _update_lamps() -> void:
	town.lamp_mat.set_shader_parameter("since", _lamps_since)
	for lamp: Dictionary in town.lamps:
		var k: float
		if lamp.has("thr"):
			var thr: float = lamp["thr"]
			k = smoothstep(thr, thr + 0.03, night)
		else:
			var ramp := clampf((_lamps_since - float(lamp["delay"]) * 8.0) / 0.5, 0.0, 1.0)
			k = ramp if lamps_on else 1.0 - ramp
		if lamp.has("light"):
			var light: Light3D = lamp["light"]
			light.light_energy = float(lamp["energy"]) * k
			light.visible = k > 0.002
		if lamp.has("mat"):
			(lamp["mat"] as StandardMaterial3D).emission_energy_multiplier = float(lamp["glow"]) * k
	if clouds_mat != null:
		var glow := Color(1.0, 0.62, 0.32).srgb_to_linear()
		var g := 0.04 * smoothstep(0.5, 0.9, night) * (1.0 if lamps_on else 0.0) * (0.5 + 0.5 * scud)
		clouds_mat.set_shader_parameter("town_glow", Vector3(glow.r, glow.g, glow.b) * g)


## ---- building ---------------------------------------------------------------

func _build_clouds() -> void:
	clouds_mat = ShaderMaterial.new()
	clouds_mat.shader = load("res://world/clouds.gdshader")
	clouds_mat.render_priority = -1
	clouds_mat.set_shader_parameter("town_xz", TOWN_CENTRE)
	var dome := SphereMesh.new()
	dome.radius = CLOUD_DOME
	dome.height = CLOUD_DOME * 2.0
	dome.radial_segments = 32
	dome.rings = 16
	dome.is_hemisphere = true
	_clouds = MeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.mesh = dome
	_clouds.material_override = clouds_mat
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.extra_cull_margin = 16384.0
	add_child(_clouds)


## Drizzle: fine streaks round the player, falling at their terminal speed and
## slanting with the wind, each a pair of crossed ribbons aligned to its
## fall so it reads from any side, lit by whatever lamp is near.
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 3500
	_rain.lifetime = 4.0
	_rain.preprocess = 4.0
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_rain.emitting = false
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_process.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	_rain_process.direction = Vector3(0, -1, 0)
	_rain_process.spread = 2.0
	_rain_process.initial_velocity_min = 4.0
	_rain_process.initial_velocity_max = 5.0
	_rain_process.gravity = Vector3(0, -0.5, 0)
	_rain_process.particle_flag_align_y = true
	# Drops stop at a roof that has a shelter box (the Cape's).
	_rain_process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = _rain_process
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var across := Vector3(0.004, 0, 0) if k == 0 else Vector3(0, 0, 0.004)
		var up := Vector3(0, 0.12, 0)
		var n := Vector3(0, 0, 1) if k == 0 else Vector3(1, 0, 0)
		for p: Vector3 in [-across - up, -across + up, across + up, -across - up, across + up, across - up]:
			st.set_normal(n)
			st.add_vertex(p)
	var streak := st.commit()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.76, 0.82, 0.18)
	mat.roughness = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	streak.surface_set_material(0, mat)
	_rain.draw_pass_1 = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _build_lightning() -> void:
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.light_color = Color(0.82, 0.86, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	add_child(_flash_light)
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.albedo_color = Color(0.85, 0.88, 1.0)
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	_bolt_mat.render_priority = 2
	_bolt = MeshInstance3D.new()
	_bolt.name = "Bolt"
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


func _build_sound() -> void:
	if _headless:
		return
	_rain_audio = _loop("res://audio/rain_loop.wav")
	_gale_audio = _loop("res://audio/gale_loop.wav")


func _loop(path: String) -> AudioStreamPlayer:
	var stream := load(path) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	p.bus = "Outdoor"
	add_child(p)
	p.play()
	return p


## ---- every frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3(TOWN_CENTRE.x, 2.0, TOWN_CENTRE.y)
	# The clouds ride the wind: the scud low and fast, the deck slow.
	var speed := 4.0 + 22.0 * wind
	_drift_high -= wind_dir * speed * 0.35 * delta
	_drift_low -= wind_dir * speed * delta
	_clouds.position = eye
	clouds_mat.set_shader_parameter("drift_high", _drift_high)
	clouds_mat.set_shader_parameter("drift_low", _drift_low)
	# The rain falls round the player, from upwind so the slant still
	# covers the view.
	_rain.global_position = eye + Vector3(0, 14.0, 0) - Vector3(wind_dir.x, 0, wind_dir.y) * 8.0 * wind
	# The surfaces wet up in a minute of rain and dry over a few after.
	var target := rain
	var rate := 1.0 / 25.0 if target > wet else 1.0 / 240.0
	wet = move_toward(wet, target, rate * delta)
	coast.terrain_mat.set_shader_parameter("wet", wet)
	town.wall_mat.set_shader_parameter("wet", wet)
	town.glass_mat.set_shader_parameter("wet", wet)
	town.street_mat.set_shader_parameter("wet", wet)
	town.street_mat.set_shader_parameter("rain", rain)
	for mat in TreeKit.materials():
		mat.set_shader_parameter("wet", wet)
	if _lamps_since < 20.0:
		_lamps_since += delta
		_update_lamps()
	_step_lightning(delta, eye)
	_step_sound(delta, eye)
	_listen(delta, eye)


func _step_lightning(delta: float, eye: Vector3) -> void:
	if lightning > 0.0:
		_next_strike -= delta
		if _next_strike <= 0.0:
			_strike(eye)
			_next_strike = -log(maxf(_rng.randf(), 1e-4)) * lerpf(45.0, 18.0, lightning)
	# The return strokes: each a sharp rise and a fast fade.
	_flash = 0.0
	for p in _pulses:
		var age := _t - p.x
		if age >= 0.0:
			_flash += p.y * exp(-age / 0.05)
	if not _pulses.is_empty() and _t - _pulses[_pulses.size() - 1].x > 0.6:
		_pulses.clear()
	var lit := _flash > 0.01
	_flash_light.visible = lit
	_flash_light.light_energy = _flash * 2.2 * _flash_reach
	_bolt.visible = lit and _bolt.mesh != null
	_bolt_mat.albedo_color = Color(0.85, 0.88, 1.0) * clampf(_flash * 3.0, 0.0, 6.0)
	if lit or _sky_lit:
		_sky_lit = lit
		var f := _flash if lit else 0.0
		clouds_mat.set_shader_parameter("flash", f)
		clouds_mat.set_shader_parameter("flash_dir", _flash_dir)
		var painted := world.sky_mat as ShaderMaterial
		if painted != null:
			painted.set_shader_parameter("flash", f * 0.6)
			painted.set_shader_parameter("flash_dir", _flash_dir)
		world.sky_env.ambient_light_energy = _ambient_energy + f * 0.8 * _flash_reach
	# Thunder, when its sound has come the distance.
	var k := 0
	while k < _thunder.size():
		var th: Dictionary = _thunder[k]
		if _t >= float(th["at"]):
			_play_thunder(th, eye)
			_thunder.remove_at(k)
		else:
			k += 1


## A stroke: where, how many return strokes, the bolt if it is near
## enough to see below the cloud, the thunder on its way.
func _strike(eye: Vector3) -> void:
	strikes += 1
	var toward_sea := atan2(0.7071, 0.7071)
	var az := toward_sea + _rng.randf_range(-1.3, 1.3)
	var dist := exp(_rng.randf_range(log(3000.0), log(11000.0)))
	var ground := Vector2(eye.x, eye.z) + Vector2(cos(az), sin(az)) * dist
	var at := Vector3(ground.x, coast.sea_level, ground.y)
	_flash_dir = (at + Vector3(0, 350.0, 0) - eye).normalized()
	_flash_reach = clampf(1400.0 / dist, 0.1, 0.45)
	_flash_light.basis = Basis.looking_at(-_flash_dir)
	var count := 1 + _rng.randi() % 4
	var start := _t
	for i in count:
		_pulses.append(Vector2(start, _rng.randf_range(0.6, 1.0) * (1.0 if i == 0 else 0.7)))
		start += _rng.randf_range(0.05, 0.14)
	if dist < 3400.0:
		_bolt.mesh = _bolt_mesh(at, eye)
	else:
		_bolt.mesh = null   # in the cloud, or past the horizon: the sky lights, no channel shows
	var file := "res://audio/thunder_1.wav" if dist < 4500.0 else ("res://audio/thunder_2.wav" if dist < 7500.0 else "res://audio/thunder_3.wav")
	_thunder.append({"at": _t + dist / SOUND, "file": file,
		"volume": -3.0 - 12.0 * log(dist / 3000.0) / log(10.0), "dir": _flash_dir})


## The channel: from the cloud's base down to the sea in jagged steps,
## a branch or two, each segment a pair of crossed ribbons.
func _bolt_mesh(at: Vector3, eye: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := at + Vector3(_rng.randf_range(-120.0, 120.0), 430.0 - at.y, _rng.randf_range(-120.0, 120.0))
	var width := clampf(eye.distance_to(at) / 450.0, 1.0, 7.0)
	var pts := _jag(top, at, 7, 60.0)
	_ribbons(st, pts, width)
	for b in 2:
		var from: Vector3 = pts[2 + _rng.randi() % 4]
		var end := from + Vector3(_rng.randf_range(-160.0, 160.0), -_rng.randf_range(80.0, 200.0), _rng.randf_range(-160.0, 160.0))
		_ribbons(st, _jag(from, end, 4, 30.0), width * 0.6)
	return st.commit()


func _jag(a: Vector3, b: Vector3, depth: int, spread: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [a, b]
	var s := spread
	for _d in depth:
		var next: Array[Vector3] = [pts[0]]
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) / 2.0 + Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s) * 0.3, _rng.randf_range(-s, s))
			next.append(mid)
			next.append(pts[i + 1])
		pts = next
		s *= 0.55
	return pts


func _ribbons(st: SurfaceTool, pts: Array[Vector3], width: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		for across: Vector3 in [Vector3(width, 0, 0), Vector3(0, 0, width)]:
			for p: Vector3 in [a - across, a + across, b + across, a - across, b + across, b - across]:
				st.add_vertex(p)


func _play_thunder(th: Dictionary, eye: Vector3) -> void:
	if _headless:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(str(th["file"]))
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.volume_db = float(th["volume"])
	p.pitch_scale = _rng.randf_range(0.9, 1.05)
	p.bus = "Outdoor"
	var dir: Vector3 = th["dir"]
	p.position = eye + Vector3(dir.x, 0.0, dir.z).normalized() * 40.0
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _step_sound(delta: float, eye: Vector3) -> void:
	if _headless:
		return
	_rain_audio.volume_db = linear_to_db(maxf(rain, 0.0001)) - 10.0
	_gale_audio.volume_db = linear_to_db(maxf(smoothstep(0.35, 1.0, wind), 0.0001)) - 15.0


## What the player hears through: a roof overhead muffles the rain,
## the wind and the sea (the Outdoor bus's low-pass closes and it drops
## a little); anything solid between the player and the bell buoy (a
## house, the brow of the hill) muffles the bell. Two rays a few times a
## second; the filters ease over a fraction of a second.
func _listen(delta: float, eye: Vector3) -> void:
	_listen_left -= delta
	if _listen_left <= 0.0:
		_listen_left = 0.15
		var space := get_world_3d().direct_space_state
		var skip: Array[RID] = [world.player.get_rid()]
		var up := PhysicsRayQueryParameters3D.create(eye, eye + Vector3(0, 12.0, 0), 1)
		up.exclude = skip
		indoors = not space.intersect_ray(up).is_empty()
		var buoy := Vector3(TownCoast.BUOY.x, coast.tide_y + 3.0, TownCoast.BUOY.y)
		var line := PhysicsRayQueryParameters3D.create(eye, buoy, 1)
		line.exclude = skip
		bell_blocked = not space.intersect_ray(line).is_empty()
	var k := 1.0 - exp(-delta * 5.0)
	_outdoor_cut = exp(lerpf(log(_outdoor_cut), log(600.0 if indoors else 20000.0), k))
	_bell_cut = exp(lerpf(log(_bell_cut), log(700.0 if bell_blocked else 20000.0), k))
	var outdoor := AudioServer.get_bus_index("Outdoor")
	var bell := AudioServer.get_bus_index("Bell")
	(AudioServer.get_bus_effect(outdoor, 0) as AudioEffectLowPassFilter).cutoff_hz = _outdoor_cut
	(AudioServer.get_bus_effect(bell, 0) as AudioEffectLowPassFilter).cutoff_hz = _bell_cut
	AudioServer.set_bus_volume_db(outdoor, lerpf(-8.0, 0.0, inverse_lerp(log(600.0), log(20000.0), log(_outdoor_cut))))
	AudioServer.set_bus_volume_db(bell, lerpf(-9.0, 0.0, inverse_lerp(log(700.0), log(20000.0), log(_bell_cut))))

