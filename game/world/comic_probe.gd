extends Node
## Renders the backgrounds of "The Clock Tower Ghost", a comic set at the
## Monroe courthouse: the world at dusk and at night from a camera of the
## probe's own, a silver 1989 Accord on North Main Street, a traffic
## signal at West Jefferson, a green lantern glow in the cupola, and
## scaffolding round the cupola for the 1886 flashback. Writes
## user://comic_<shot>.png at 1920 by 1080.
## Run windowed:
##   godot --path game res://world/comic_probe.tscn

var _world: CourthouseMap
var _cam: Camera3D
var _car: Accord89
var _ghost_lights: Array[OmniLight3D] = []
var _scaffold: Node3D
var _signal_red: OmniLight3D
var _moon: DirectionalLight3D
## The time the courthouse clock shows in a shot; below 0, the world's.
var _story_clock := -1.0


func _ready() -> void:
	MouseMode.probe = true
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_viewport().size = Vector2i(1920, 1080)
	var world: CourthouseMap = (load("res://world/courthouse.tscn") as PackedScene).instantiate()
	add_child(world)
	_world = world
	_run()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	for layer in _world.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_world.graphics.set_preset("High")
	_world.graphics.apply(_world)
	_world.player.global_position = Vector3(0, UnionCourthouse.F1 + 0.1, -16.0)
	_world.player.set_physics_process(false)
	_cam = Camera3D.new()
	_cam.near = 0.03
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	_car = Accord89.new()
	add_child(_car)
	_car.build(true)
	_props()
	await get_tree().create_timer(4.0).timeout
	if OS.get_environment("COMIC_SWEEP") != "":
		for h: float in [18.4, 18.55, 18.7, 18.85]:
			await _shot("sweep_%d" % int(h * 100), h, Vector3(-49, 1.7, 30), Vector3(-2, 11, -2), 58.0, Vector3(-38.6, 0, 8), true)
		get_tree().quit()
		return

	# The story happens at blue hour, a little before seven.
	var dusk := 18.45
	_story_clock = 18.0 + 56.0 / 60.0
	# The title: the cupola at dusk, the lantern glowing.
	await _shot("title", dusk, Vector3(-16, 14, 22), Vector3(0, 29, 0), 45.0, Vector3(-38.8, 0, 400), true)
	# The Accord comes up North Main past the courthouse, and toward us.
	await _shot("dusk_wide", dusk, Vector3(-49, 1.7, 34), Vector3(-6, 10, -2), 56.0, Vector3(-38.6, 0, 20), false)
	await _shot("car_approach", dusk, Vector3(-41.5, 1.1, -8), Vector3(-37.5, 2.2, 14), 50.0, Vector3(-38.6, 0, 9), false)
	# From the back seat, out of the right-hand window, up at the cupola.
	_car_at(Vector3(-38.6, 0, 400))
	await _shot("window", dusk, Vector3(-37.9, 1.05, -1.2), Vector3(-34.9, 4.25, -1.4), 72.0, Vector3.INF, true)
	# Through the windshield from the back seat: North Main ahead, the
	# courthouse on the right.
	await _shot("windshield", dusk, Vector3(-38.9, 1.15, -2.0), Vector3(-37.2, 2.4, -40.0), 68.0, Vector3.INF, true)
	# 1886: the cupola in scaffolding.
	_scaffold.visible = true
	await _shot("flashback", 11.0, Vector3(-15, 21, 13), Vector3(0, 25.5, 0), 42.0, Vector3(-38.8, 0, 400), false)
	await _shot("flashback_fall", 11.0, Vector3(-6, 14.5, 7), Vector3(0, 29, 0), 55.0, Vector3(-38.8, 0, 400), false)
	_scaffold.visible = false
	# The cupola, the glow in the vents.
	await _shot("cupola_glow", dusk, Vector3(-11, 21, 9), Vector3(0, 27, 0), 38.0, Vector3(-38.8, 0, 400), true)
	# The west clock at four minutes to seven.
	await _still("clock_656", Vector3(-8.2, 30.4, 0.0), Vector3(0, 30.4, 0), 21.0)
	# At the red light on West Jefferson, from behind.
	_car_at(Vector3(-38.6, 0, -24.5))
	_signal_red.visible = true
	await _shot("red_light", dusk, Vector3(-37.4, 1.55, -14.5), Vector3(-39.2, 2.6, -48), 55.0, Vector3.INF, true)
	# Wider, the ghost's view: the cupola and the town below it.
	await _shot("ghost_cupola", dusk, Vector3(-22, 16, 17), Vector3(0, 27.5, 0), 48.0, Vector3.INF, true)
	# The car's right side from the lawn: the ghost at the back window.
	await _shot("car_side", dusk, Vector3(-33.6, 1.2, -22.6), Vector3(-38.6, 1.0, -25.0), 50.0, Vector3.INF, true)
	# Seven o'clock: the ghost sets the clock; the town from Main Street.
	_story_clock = 19.0
	await _still("ghost_clock", Vector3(-7.5, 28.0, 5.0), Vector3(0, 30.0, 0), 34.0)
	await _shot("seven_wide", dusk, Vector3(-47, 1.7, 24), Vector3(-4, 14, -4), 56.0, Vector3.INF, false)
	_signal_red.visible = false
	# The epilogue by day.
	_story_clock = -1.0
	await _shot("epilogue_day", 16.2, Vector3(-41, 1.7, 9), Vector3(0, 13, -1), 58.0, Vector3(-38.8, 0, 400), false)
	print("[comic] backgrounds written to user://")
	get_tree().quit()


## Everything the story needs that the world lacks.
func _props() -> void:
	# The lantern's glow in the cupola: green light at each louvred vent.
	for dir: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var l := OmniLight3D.new()
		l.position = dir * 2.9 + Vector3(0, 24.4, 0)
		l.light_color = Color(0.55, 1.0, 0.72)
		l.light_energy = 3.0
		l.omni_range = 3.6
		l.visible = false
		add_child(l)
		_ghost_lights.append(l)
	# The traffic signal over North Main at West Jefferson: a span wire, a
	# yellow head of three lamps.
	var sig := Node3D.new()
	add_child(sig)
	var sm := TownMesh.new()
	var iron := Color(0.1, 0.1, 0.1)
	for x: float in [-51.5, -30.0]:
		sm.cylinder("m", Transform3D(Basis(), Vector3(x, 3.8, -33.5)), 0.12, 0.1, 7.6, 10, iron)
	sm.bar("m", Vector3(-51.5, 7.3, -33.5), Vector3(-30.0, 7.3, -33.5), 0.012, 4, iron)
	var head := Vector3(-39.5, 6.3, -33.5)
	sm.box("m", Transform3D(Basis(), head), Vector3(0.36, 1.05, 0.3), Color(0.85, 0.68, 0.10))
	sm.bar("m", head + Vector3(0, 0.52, 0), Vector3(-39.5, 7.3, -33.5), 0.02, 4, iron)
	for k in 3:
		var y := head.y + 0.32 - k * 0.32
		sm.cylinder("m", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(head.x, y, head.z + 0.16)), 0.12, 0.12, 0.02, 14,
			Color(0.25, 0.04, 0.03) if k == 0 else (Color(0.2, 0.15, 0.02) if k == 1 else Color(0.03, 0.15, 0.06)))
		sm.box("m", Transform3D(Basis(), Vector3(head.x, y + 0.1, head.z + 0.24)), Vector3(0.28, 0.02, 0.16), iron)
	var red := TownMesh.new()
	red.cylinder("r", Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(head.x, head.y + 0.32, head.z + 0.175)), 0.11, 0.11, 0.01, 14,
		Color(1, 1, 1))
	var sig_mat := StandardMaterial3D.new()
	sig_mat.vertex_color_use_as_albedo = true
	sig_mat.roughness = 0.6
	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(1.0, 0.1, 0.05)
	red_mat.emission_enabled = true
	red_mat.emission = Color(1.0, 0.08, 0.03)
	red_mat.emission_energy_multiplier = 6.0
	sm.commit(sig, {"m": sig_mat}, ["m"])
	red.commit(sig, {"r": red_mat}, [])
	_signal_red = OmniLight3D.new()
	_signal_red.position = head + Vector3(0, 0.32, 0.5)
	_signal_red.light_color = Color(1.0, 0.12, 0.06)
	_signal_red.light_energy = 1.5
	_signal_red.omni_range = 9.0
	_signal_red.visible = false
	add_child(_signal_red)
	# Scaffolding of sawn poles round the cupola, ledgers and planks.
	_scaffold = Node3D.new()
	_scaffold.visible = false
	add_child(_scaffold)
	var sc := TownMesh.new()
	var wood := Color(0.55, 0.42, 0.28)
	var r := 3.9
	var posts: Array[Vector2] = []
	for i in 4:
		for j in 3:
			var t := -r + j * r
			posts.append([Vector2(t, -r), Vector2(r, t), Vector2(-t, r), Vector2(-r, -t)][i])
	for p: Vector2 in posts:
		sc.bar("m", Vector3(p.x, 16.6, p.y), Vector3(p.x, 31.5, p.y), 0.07, 6, wood)
	var y := 18.5
	while y < 31.0:
		for i in 4:
			var a: Vector2 = [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)][i]
			var bb: Vector2 = [Vector2(r, -r), Vector2(r, r), Vector2(-r, r), Vector2(-r, -r)][i]
			sc.bar("m", Vector3(a.x, y, a.y), Vector3(bb.x, y, bb.y), 0.05, 5, wood)
			var mid := (a + bb) / 2.0
			var inward := -mid.normalized()
			sc.box("m", Transform3D(Basis(Vector3.UP, 0.0 if absf(a.y - bb.y) < 0.1 else PI / 2.0),
				Vector3(mid.x + inward.x * 0.45, y + 0.06, mid.y + inward.y * 0.45)), Vector3(2.0 * r, 0.05, 0.9), wood.lightened(0.1))
		# A brace across each face.
		y += 2.4
	for i in 4:
		var a: Vector2 = [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)][i]
		var bb: Vector2 = [Vector2(r, -r), Vector2(r, r), Vector2(-r, r), Vector2(-r, -r)][i]
		sc.bar("m", Vector3(a.x, 18.5, a.y), Vector3(bb.x, 30.5, bb.y), 0.04, 5, wood)
	# A ladder up the west face, a bucket and a coil of rope on a plank.
	for s: float in [-0.25, 0.25]:
		sc.bar("m", Vector3(-r - 0.1, 16.6, s), Vector3(-r - 0.1, 29.0, s), 0.03, 5, wood)
	var ry := 16.8
	while ry < 29.0:
		sc.bar("m", Vector3(-r - 0.1, ry, -0.25), Vector3(-r - 0.1, ry, 0.25), 0.02, 4, wood)
		ry += 0.3
	sc.cylinder("m", Transform3D(Basis(), Vector3(-r + 0.4, 23.5 + 0.2, 1.4)), 0.14, 0.17, 0.3, 10, Color(0.4, 0.4, 0.42))
	sc.cylinder("m", Transform3D(Basis(), Vector3(-r + 0.4, 23.5 + 0.12, -1.6)), 0.25, 0.25, 0.1, 12, Color(0.6, 0.5, 0.3))
	var wood_mat := StandardMaterial3D.new()
	wood_mat.vertex_color_use_as_albedo = true
	wood_mat.vertex_color_is_srgb = true
	wood_mat.roughness = 0.9
	sc.commit(_scaffold, {"m": wood_mat}, ["m"])
	# A blue fill from the east sky, so the town reads at dusk as it does
	# to the eye; off by day.
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.66, 1.0)
	_moon.light_energy = 0.55
	_moon.shadow_enabled = true
	_moon.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	_moon.visible = false
	add_child(_moon)


func _car_at(p: Vector3) -> void:
	_car.global_position = p
	_car.rotation = Vector3.ZERO


func _set_hour(hour: float) -> void:
	_world.set_time_of_day(hour)
	var night := hour > 18.2 or hour < 6.0
	_moon.visible = night
	_world.sky_env.tonemap_exposure = 1.25 if night else 0.9
	if _story_clock >= 0.0:
		_world.courthouse.set_clock(_story_clock)


## A shot from cam toward target at the hour, the car placed at car_at
## (Vector3.INF leaves it), the cupola's glow on or off.
func _shot(name_: String, hour: float, cam: Vector3, target: Vector3, fov: float, car_at: Vector3, glow: bool) -> void:
	_set_hour(hour)
	if car_at != Vector3.INF:
		_car_at(car_at)
	_car.set_lights(hour > 18.2 or hour < 6.5, _signal_red.visible)
	for l in _ghost_lights:
		l.visible = glow
	_cam.global_position = cam
	_cam.look_at(target, Vector3.UP)
	_cam.fov = fov
	await _save(name_)


## A shot from inside the car: camera and target in the car's frame.
func _shot_local(name_: String, hour: float, cam: Vector3, target: Vector3, fov: float, glow: bool) -> void:
	_set_hour(hour)
	for l in _ghost_lights:
		l.visible = glow
	var xf := _car.global_transform
	_cam.global_position = xf * cam
	_cam.look_at(xf * target, Vector3.UP)
	_cam.fov = fov
	await _save(name_)


## A close still at the current hour (the clock's hands set by hand).
func _still(name_: String, cam: Vector3, target: Vector3, fov: float) -> void:
	if _story_clock >= 0.0:
		_world.courthouse.set_clock(_story_clock)
	for l in _ghost_lights:
		l.visible = true
	_cam.global_position = cam
	_cam.look_at(target, Vector3.UP)
	_cam.fov = fov
	await _save(name_)


func _save(name_: String) -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://comic_%s.png" % name_)
	print("[comic] %s %dx%d" % [name_, img.get_width(), img.get_height()])
