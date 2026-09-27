extends Node
## Debug harness for the Mark Twain house: boots the world and
## photographs the house from round the lawn and the rooms inside,
## printing the frame rate with each; `walk` climbs in from the drive and
## up every flight with real input.
## Run windowed:
##   godot --path game res://world/twain_probe.tscn
## FLOWSTATE_TW_SHOTS=outside, inside, walk or night limits it.

const EYE := 1.6

var _world: TwainMap


func _ready() -> void:
	MouseMode.probe = true
	var world: TwainMap = (load("res://world/twain.tscn") as PackedScene).instantiate()
	add_child(world)
	_world = world
	_run(world)


## A survey point (feet) in the world, at eye height over the floor y.
static func s(sx: float, sz: float, y: float) -> Vector3:
	return TwainHouse.w(sx, sz, y)


func _run(world: TwainMap) -> void:
	await get_tree().create_timer(6.0).timeout
	var player := world.player
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	world.set_time_of_day(10.0)
	var which := OS.get_environment("FLOWSTATE_TW_SHOTS")
	player._fov_target = 70.0
	var views := OS.get_environment("FLOWSTATE_TW_VIEWS")
	if views != "":
		# name:fov:x,y,z:tx,ty,tz;... for looking at one thing closely.
		for v: String in views.split(";"):
			var parts := v.split(":")
			var p := parts[2].split_floats(",")
			var t := parts[3].split_floats(",")
			player._fov_target = float(parts[1])
			await _look(player, Vector3(p[0], p[1], p[2]), Vector3(t[0], t[1], t[2]), parts[0])
		get_tree().quit()
		return
	if which == "" or which == "outside":
		await _look(player, Vector3(30.0, EYE, 26.0), Vector3(0.0, 5.0, 0.0), "southeast")
		await _look(player, Vector3(34.0, EYE, -2.0), Vector3(0.0, 5.0, -2.0), "east")
		await _look(player, Vector3(22.0, EYE, -26.0), Vector3(2.0, 5.0, -4.0), "northeast")
		await _look(player, Vector3(-4.0, EYE, -42.0), Vector3(-2.0, 6.0, -6.0), "north")
		await _look(player, Vector3(-40.0, EYE, -4.0), Vector3(0.0, 6.0, -4.0), "west")
		await _look(player, Vector3(2.0, EYE, 42.0), Vector3(0.0, 6.0, 0.0), "south")
		await _look(player, Vector3(-38.0, 34.0, 36.0), Vector3(0.0, 4.0, 0.0), "aerial")
		await _look(player, Vector3(40.0, 30.0, -36.0), Vector3(0.0, 4.0, 0.0), "aerial_ne")
		player._fov_target = 40.0
		await _look(player, Vector3(26.0, EYE, 18.0), Vector3(3.0, 9.0, 4.0), "gables")
		player._fov_target = 70.0
	if which == "" or which == "inside":
		player._fov_target = 75.0
		await _look(player, s(94.0, 64.0, 0.0) + Vector3(0, EYE, 0), s(76.0, 60.0, 5.0), "hall_stair")
		await _look(player, s(76.5, 70.0, 0.0) + Vector3(0, EYE, 0), s(94.0, 76.0, 4.0), "hall_north")
		await _look(player, s(86.0, 47.0, 0.0) + Vector3(0, EYE, 0), s(56.0, 47.0, 4.0), "library_south")
		await _look(player, s(72.0, 41.0, 0.0) + Vector3(0, EYE, 0), s(72.0, 56.0, 5.0), "library_mantel")
		await _look(player, s(89.5, 41.0, 0.0) + Vector3(0, EYE, 0), s(113.0, 50.0, 4.0), "dining")
		await _look(player, s(98.5, 80.0, 0.0) + Vector3(0, EYE, 0), s(117.0, 66.0, 4.0), "drawing")
		await _look(player, s(70.0, 67.0, 0.0) + Vector3(0, EYE, 0), s(50.0, 60.0, 4.0), "guest")
		await _look(player, s(62.0, 47.0, 0.0) + Vector3(0, EYE, 0), s(44.0, 47.0, 4.0), "conservatory")
		await _look(player, s(95.0, 68.0, TwainHouse.F2) + Vector3(0, EYE, 0), s(76.0, 62.0, TwainHouse.F2 + 5.0), "hall2")
		await _look(player, s(99.0, 79.0, TwainHouse.F2) + Vector3(0, EYE, 0), s(112.0, 64.0, TwainHouse.F2 + 3.0), "bedroom")
		await _look(player, s(77.0, 50.0, TwainHouse.F2) + Vector3(0, EYE, 0), s(60.0, 44.0, TwainHouse.F2 + 4.0), "school")
		await _look(player, s(88.0, 48.0, TwainHouse.F3) + Vector3(0, EYE, 0), s(57.0, 47.0, TwainHouse.F3 + 6.0), "billiard")
		await _look(player, s(90.0, 68.0, TwainHouse.F3) + Vector3(0, EYE, 0), s(76.0, 60.0, TwainHouse.F3 + 1.0), "hall3")
	if which == "" or which == "night":
		world.set_time_of_day(21.0)
		await get_tree().create_timer(1.0).timeout
		player._fov_target = 70.0
		await _look(player, Vector3(30.0, EYE, 26.0), Vector3(0.0, 5.0, 0.0), "southeast_night")
		player._fov_target = 75.0
		await _look(player, s(94.0, 64.0, 0.0) + Vector3(0, EYE, 0), s(76.0, 60.0, 5.0), "hall_night")
		await _look(player, s(86.0, 47.0, 0.0) + Vector3(0, EYE, 0), s(56.0, 47.0, 4.0), "library_night")
		world.set_time_of_day(10.0)
	if which == "walk":
		# In from the drive up the veranda's steps and the front door, up
		# each flight to the billiard room.
		var steps := s(90.5, 99.0, TwainHouse.GRADE)
		await _walk(player, Vector3(steps.x, 0.3, steps.z), s(90.5, 70.0, 0.0), 7.0)
		await _walk(player, s(89.0, 63.2, 0.0) + Vector3(0, 0.3, 0), s(70.0, 63.2, 0.0), 3.5)
		await _walk(player, s(74.0, 63.2, 6.6) + Vector3(0, 0.3, 0), s(74.0, 58.2, 6.6), 0.8)
		await _walk(player, s(74.5, 58.2, 6.6) + Vector3(0, 0.3, 0), s(95.0, 58.2, 6.6), 3.0)
		await _walk(player, s(88.0, 58.2, 13.1) + Vector3(0, 0.3, 0), s(88.0, 63.2, 13.1), 1.0)
		await _walk(player, s(88.0, 63.2, 13.1) + Vector3(0, 0.3, 0), s(70.0, 63.2, 13.1), 3.5)
		await _walk(player, s(74.5, 58.2, 18.6) + Vector3(0, 0.3, 0), s(95.0, 58.2, 18.6), 3.0)
		await _walk(player, s(86.8, 57.5, 24.1) + Vector3(0, 0.3, 0), s(86.8, 45.0, 24.1), 2.0)
		# Onto the ombra and down its steps to the lawn.
		await _walk(player, s(40.0, 79.0, 0.0) + Vector3(0, 0.3, 0), s(10.0, 79.0, 0.0), 4.0)
	print("[probe] screenshots written to user://")
	get_tree().quit()


## Stand the camera at `from` and aim it at `to`, then photograph.
func _look(player: Player, from: Vector3, to: Vector3, name_: String) -> void:
	var d := to - from
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var at := from - Vector3(0, EYE, 0)
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	player.camera.fov = player._fov_target
	await get_tree().create_timer(1.2).timeout
	player.global_position = at
	player.velocity = Vector3.ZERO
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://probe_tw_%s.png" % name_)
	await get_tree().create_timer(0.8).timeout
	print("[probe] %s: %.0f fps · %.2f M tris · %d draws" % [name_, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


## Stand the player at `from`, face them toward `toward` and hold
## forward: the same input the director gives.
func _walk(player: Player, from: Vector3, toward: Vector3, seconds: float) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	var d := toward - from
	player.rotation.y = atan2(-d.x, -d.z)
	player.camera.rotation.x = 0.0
	await get_tree().physics_frame
	Input.action_press("move_forward")
	var trail: Array[String] = []
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		var p := player.global_position
		trail.append("(%.1f, %.2f, %.1f)" % [p.x, p.y, p.z])
	Input.action_release("move_forward")
	await get_tree().create_timer(0.3).timeout
	print("[probe] walk from (%.1f, %.1f, %.1f): %s" % [from.x, from.y, from.z, " ".join(trail)])
