extends Node
## Debug harness for the Monroe courthouse: boots the world and
## photographs the courthouse from where the street imagery stands (the
## west front from North Main Street, the east front from North Hayne,
## the south end from West Franklin), the cupola close to, an aerial,
## and the rooms inside, printing the frame rate with each.
## Run windowed:
##   godot --path game res://world/courthouse_probe.tscn
## FLOWSTATE_CH_SHOTS=outside or inside limits it to those views.

var _world: CourthouseMap


func _ready() -> void:
	MouseMode.probe = true
	var world: CourthouseMap = (load("res://world/courthouse.tscn") as PackedScene).instantiate()
	add_child(world)
	_world = world
	_run(world)


func _run(world: CourthouseMap) -> void:
	await get_tree().create_timer(6.0).timeout
	var player := world.player
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	world.set_time_of_day(15.5)
	var which := OS.get_environment("FLOWSTATE_CH_SHOTS")
	if which == "walk":
		# With real input: in from North Main up the west porch and
		# through the hall; up each stair in its two flights; into the
		# courtroom from the south hall; in at the south door.
		await _walk(player, Vector3(-36.0, 0.3, 3.5), -PI / 2.0, 3.0)
		await _walk(player, Vector3(-18.5, 0.3, 0.3), -PI / 2.0, 7.0)
		await _walk(player, Vector3(0.5, UnionCourthouse.F1 + 0.1, -9.5), -PI / 2.0, 2.5)
		await _walk(player, Vector3(7.0, CourthouseInterior.LANDING + 0.1, -11.4), PI / 2.0, 2.5)
		await _walk(player, Vector3(-0.5, UnionCourthouse.F1 + 0.1, 9.5), PI / 2.0, 2.5)
		await _walk(player, Vector3(-7.0, CourthouseInterior.LANDING + 0.1, 11.4), -PI / 2.0, 2.5)
		await _walk(player, Vector3(0.0, UnionCourthouse.F2 + 0.1, 12.0), 0.0, 4.0)
		await _walk(player, Vector3(0.0, 0.3, 34.0), 0.0, 4.0)
		get_tree().quit()
		return
	if which == "match":
		# The street imagery's own cameras, turned into the building's
		# frame (it stands 2.8 degrees west of north): [x, z, heading,
		# pitch, focal length in pixels of a 726-high frame].
		for cam: Array in [["south30", -6.9, 42.6, 7.8, 14.0, 1069.0], ["west25_up", -39.34, -1.70, 92.8, 22.0, 1391.0],
				["west25_low", -39.34, -1.70, 92.8, 6.0, 1391.0], ["west15", -39.34, -1.70, 93.8, 34.0, 2342.0],
				["west90", -39.34, -1.70, 92.8, 20.0, 308.0], ["east90", 42.86, -0.435, 272.8, 15.0, 308.0]]:
			var f := float(cam[5]) * 720.0 / 726.0
			player._fov_target = rad_to_deg(2.0 * atan(360.0 / f))
			player.camera.fov = player._fov_target
			await _view(player, Vector3(float(cam[1]), 2.5 - 1.6, float(cam[2])), -deg_to_rad(float(cam[3])),
				deg_to_rad(float(cam[4])), "match_" + str(cam[0]))
		get_tree().quit()
		return
	if which == "" or which == "outside":
		player._fov_target = 90.0
		await _view(player, Vector3(-39.0, 0.9, 0.35), -PI / 2.0, 0.0, "west_front")
		await _view(player, Vector3(-39.0, 0.9, 0.35), -PI / 2.0, 0.35, "west_up")
		await _view(player, Vector3(43.2, 0.9, -2.4), PI / 2.0, 0.1, "east_front")
		await _view(player, Vector3(-4.4, 0.9, 43.0), 0.0, 0.1, "south_end")
		await _view(player, Vector3(-30.0, 0.9, -32.0), -PI * 0.75, 0.15, "northwest")
		player._fov_target = 30.0
		await _view(player, Vector3(-39.0, 0.9, 0.35), -PI / 2.0, 0.42, "cupola")
		await _view(player, Vector3(-39.0, 0.9, 0.35), -PI / 2.0, 0.08, "porch")
		player._fov_target = 75.0
		await _view_zoom(player, Vector3(-60.0, 40.0, 40.0), -PI * 0.25 - 0.3, -0.5, 0.0, "aerial")
	if which == "" or which == "inside":
		player._fov_target = 75.0
		await _view(player, Vector3(-7.0, UnionCourthouse.F1 + 0.05, 0.0), -PI / 2.0, -0.05, "cross_hall")
		await _view(player, Vector3(0.0, UnionCourthouse.F1 + 0.05, 6.0), 0.0, 0.0, "axial_hall_north")
		await _view(player, Vector3(0.0, UnionCourthouse.F1 + 0.05, -18.0), PI, 0.0, "axial_hall_south")
		await _view(player, Vector3(0.5, UnionCourthouse.F1 + 0.05, -8.8), -PI / 2.0 + 0.4, 0.2, "stair_north")
		await _view(player, Vector3(0.0, UnionCourthouse.F2 + 0.05, 7.0), 0.0, 0.05, "courtroom_bench")
		await _view(player, Vector3(6.5, UnionCourthouse.F2 + 0.05, -4.0), PI * 0.8, 0.05, "courtroom_back")
		await _view(player, Vector3(-6.0, UnionCourthouse.F1 + 0.05, -4.0), PI * 0.25, 0.0, "heritage_room")
		world.set_time_of_day(20.5)
		await _view(player, Vector3(0.0, UnionCourthouse.F2 + 0.05, 7.0), 0.0, 0.05, "courtroom_night")
		await _view(player, Vector3(-39.0, 0.9, 0.35), -PI / 2.0, 0.05, "west_night")
	print("[probe] screenshots written to user://")
	get_tree().quit()


func _view(player: Player, at: Vector3, yaw: float, pitch: float, name_: String) -> void:
	await _view_zoom(player, at, yaw, pitch, 0.0, name_)


func _view_zoom(player: Player, at: Vector3, yaw: float, pitch: float, zoom: float, name_: String) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	player.zoom_t = zoom
	player._zoom_now = zoom
	await get_tree().create_timer(1.2).timeout
	player.global_position = at
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://probe_ch_%s.png" % name_)
	await get_tree().create_timer(1.0).timeout
	print("[probe] %s: %.0f fps · %.2f M tris · %d draws" % [name_, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


## Stand the player somewhere, face them a way and hold forward: the
## same input the director gives, so a stair is proven walkable.
func _walk(player: Player, from: Vector3, facing: float, seconds: float) -> void:
	player.global_position = from
	player.velocity = Vector3.ZERO
	player.rotation.y = facing
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
