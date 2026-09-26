extends Node
## Debug harness for the harbour town: boots it and photographs the
## showpiece (Main Street and the harbour in an early evening storm),
## a lightning stroke over the sea, the waterfront, the bell buoy, a
## fair noon, a clear night sky, and the aerial, printing the frame
## rate with each and the showpiece's rate on each graphics preset.
## Run windowed:
##   godot --path game res://world/town_probe.tscn
## FLOWSTATE_TOWN_SHOTS=storm limits it to the storm views.


func _ready() -> void:
	MouseMode.probe = true
	var world: TownMap = (load("res://world/town.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


var _world: TownMap


func _run(world: TownMap) -> void:
	_world = world
	await get_tree().create_timer(2.5).timeout
	var player := world.player
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	world.set_weather(0.9)
	world.set_time_of_day(18.1)
	world.weather.wet = 1.0
	world.weather._next_strike = 1000.0
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "main":
		await _main_street(world, player)
		get_tree().quit()
		return
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "trees":
		await _trees(world, player)
		get_tree().quit()
		return
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "row":
		await _row(world, player)
		get_tree().quit()
		return
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "street":
		await _water_street(world, player)
		get_tree().quit()
		return
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "house":
		await _house(world, player)
		get_tree().quit()
		return
	# The showpiece: Main Street in the storm, east to the church.
	await _view(player, Vector3(-6.0, 0.4, 17.5), -PI / 2.0, 0.02, "storm_main")
	await _view_zoom(player, Vector3(-20.0, 0.4, -35.0), -2.5, -0.35, 1.6, "hill_over_town")
	await _view(player, Vector3(30.0, 0.4, 47.5), -PI / 2.0 + 0.2, 0.0, "water_street_curve")
	await _view(player, Vector3(-14.0, 0.4, -30.0), PI, -0.05, "harbor_street_down")
	# Down the harbour road over the waterfront to the boats and the light.
	await _view(player, Vector3(-12.0, 0.4, 58.0), 2.75, -0.12, "storm_harbor_road")
	# On the T-head looking out past the boats to the buoy.
	await _view(player, Vector3(-26.0, TownCoast.DECK_Y + 0.1, 119.0), PI + 0.24, 0.02, "storm_wharf")
	# From the waterfront back up at the town glowing over the harbour.
	await _view(player, Vector3(-24.0, TownCoast.DECK_Y + 0.1, 114.0), -0.43, 0.1, "storm_town_from_wharf")
	# A stroke out over the sea, caught mid-flash.
	player.global_position = Vector3(-28.0, TownCoast.DECK_Y + 0.1, 118.0)
	player.rotation.y = -2.35
	player.camera.rotation.x = 0.12
	await get_tree().create_timer(0.8).timeout
	world.weather._strike(player.global_position)
	await get_tree().create_timer(0.03).timeout
	await _shot("user://probe_town_storm_lightning.png")
	print("[probe] storm_lightning: %.0f fps" % Engine.get_frames_per_second())
	# The frame rate of the showpiece on each preset.
	player.global_position = Vector3(-6.0, 0.4, 17.5)
	player.rotation.y = -PI / 2.0
	player.camera.rotation.x = 0.02
	for preset: String in ["Low", "Medium", "High"]:
		world.graphics.set_preset(preset)
		world.graphics.apply(world)
		await get_tree().create_timer(2.5).timeout
		var best := 0.0
		for _k in 6:
			await get_tree().create_timer(0.5).timeout
			best = maxf(best, Engine.get_frames_per_second())
		print("[probe] storm on %s: %.0f fps · %.2f M tris · %d draws" % [preset, best,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		await _shot("user://probe_town_storm_%s.png" % preset.to_lower())
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	if OS.get_environment("FLOWSTATE_TOWN_SHOTS") == "storm":
		get_tree().quit()
		return
	# The bell buoy close to, in the storm.
	await _view(player, Vector3(TownCoast.BUOY.x - 8.0, world.coast.tide_y + 2.0, TownCoast.BUOY.y - 10.0), PI - 0.6, -0.08, "storm_buoy")
	# A fair noon with clouds.
	world.set_weather(0.0)
	world.weather.wet = 0.0
	world.set_time_of_day(12.5)
	await _view(player, Vector3(-6.0, 0.4, 17.5), -PI / 2.0, 0.15, "fair_main")
	await _view(player, Vector3(-12.0, 0.4, 58.0), 2.75, -0.08, "fair_harbor_road")
	world.set_weather(0.35)
	world.set_time_of_day(16.0)
	await _view(player, Vector3(-12.0, 0.4, 58.0), 2.75, 0.2, "cloudy_harbor_road")
	# A clear night: the sky, the Milky Way, the town's lights.
	world.set_weather(0.0)
	world.set_time_of_day(21.5)
	await _view(player, Vector3(-28.0, TownCoast.DECK_Y + 0.1, 118.0), PI, 0.75, "night_sky")
	await _view(player, Vector3(-24.0, TownCoast.DECK_Y + 0.1, 114.0), -0.43, 0.1, "night_town")
	# The aerial, at dusk in the storm.
	world.set_weather(0.9)
	world.set_time_of_day(18.1)
	await _view_zoom(player, Vector3(15.0, 0.4, 10.0), -2.35, -0.8, 2.3, "storm_aerial")
	print("[probe] screenshots written to user://")
	get_tree().quit()


## The trees by day: one close to, looking up into its crown; the
## street trees down Main Street; along Water Street; the edge of the
## woods up the north road.
func _trees(world: TownMap, player: Player) -> void:
	world.set_weather(0.1)
	world.set_time_of_day(13.0)
	var plants: Array = world.town._trees._plants
	for k in 3:
		var plant: Array = plants[(k * 7) % plants.size()]
		var at: Vector3 = plant[0]
		await _view(player, at + Vector3(6.0, 0.0, 6.0), PI / 4.0, 0.35, "trees_close_%d" % k)
	await _view(player, Vector3(-6.0, 0.4, 17.5), -PI / 2.0, 0.2, "trees_main")
	await _view(player, Vector3(30.0, 0.4, 47.5), -PI / 2.0 + 0.2, 0.12, "trees_water")
	await _view(player, Vector3(-14.0, 0.4, -38.0), 0.0, 0.08, "trees_woods")
	await _view_zoom(player, Vector3(-20.0, 0.4, -35.0), -2.5, -0.35, 1.6, "trees_aerial")


## Main Street by day and at dusk in the storm: down the street from the
## corner of Harbor Street, the north row close to, the city hall, the
## domed hall from the street's end, and from above.
func _main_street(world: TownMap, player: Player) -> void:
	world.set_weather(0.1)
	world.weather.wet = 0.0
	world.set_time_of_day(14.0)
	await _view(player, Vector3(-9.0, 0.4, 12.5), -PI / 2.0, 0.1, "main_down")
	await _view(player, Vector3(8.0, 0.4, 15.5), -PI / 2.0 - 0.9, 0.3, "main_north_row")
	await _view(player, Vector3(30.0, 0.4, 9.0), PI / 2.0 + 0.9, 0.3, "main_south_row")
	await _view(player, Vector3(2.0, 0.4, 9.0), PI - 0.2, 0.45, "main_city_hall")
	await _view(player, Vector3(64.0, 0.4, 12.0), -PI / 2.0, 0.12, "main_dome")
	await _view_zoom(player, Vector3(10.0, 30.0, -25.0), -PI * 0.75, -0.55, 0.0, "main_aerial")
	world.set_weather(0.9)
	world.weather.wet = 1.0
	world.set_time_of_day(18.4)
	await _view(player, Vector3(-9.0, 0.4, 12.5), -PI / 2.0, 0.1, "main_storm")


## Every house on the harbour side of Water Street, outside and in, at
## dusk with the rooms lit: from the street, then its rooms by plan.
func _row(world: TownMap, player: Player) -> void:
	world.set_weather(0.3)
	world.set_time_of_day(17.6)
	for h: Dictionary in world.town.houses_built:
		if not h.get("detailed", false):
			continue
		var base: Transform3D = h["base"]
		var tag := "row_%d_s%d" % [int(base.origin.x), int(h["style"])]
		await _local_view(player, base, Vector3(1.5, 0.0, 6.5), Vector3(-0.2, 0, -1), 0.1, tag + "_front")
		match int(h["style"]):
			1:
				await _local_view(player, base, Vector3(1.6, 0.6, -1.2), Vector3(1, 0, -0.5), -0.05, tag + "_living")
				await _local_view(player, base, Vector3(-1.6, 0.6, -5.0), Vector3(-1, 0, -0.3), -0.1, tag + "_kitchen")
				await _local_view(player, base, Vector3(-1.5, 0.6, -1.0), Vector3(-1, 0, -0.6), -0.05, tag + "_dining")
				await _local_view(player, base, Vector3(0.5, 3.5, -6.0), Vector3(-1, 0, 0.6), -0.1, tag + "_upstairs")
				await _local_view(player, base, Vector3(1.6, 3.5, -1.4), Vector3(1, 0, -0.4), -0.1, tag + "_bedroom")
			2:
				await _local_view(player, base, Vector3(-1.9, 0.6, -0.8), Vector3(1, 0, -0.6), -0.05, tag + "_parlor")
				await _local_view(player, base, Vector3(0.5, 0.6, -5.2), Vector3(0.2, 0, -1), -0.1, tag + "_dining")
				await _local_view(player, base, Vector3(-2.0, 0.6, -7.8), Vector3(1, 0, -0.4), -0.1, tag + "_kitchen")
				await _local_view(player, base, Vector3(-2.0, 3.5, -5.9), Vector3(1, 0, -0.5), -0.1, tag + "_upstairs")
			_:
				await _local_view(player, base, Vector3(-1.8, 0.6, -2.0), Vector3(-1, 0, 0), -0.05, tag + "_living")


## A view from a point in a house's own frame, looking along dir in it.
func _local_view(player: Player, base: Transform3D, at: Vector3, dir: Vector3, pitch: float, name_: String) -> void:
	var p := base * at
	var wd := base.basis * dir
	await _view(player, p + Vector3(0, 0.05, 0), atan2(-wd.x, -wd.z), pitch, name_)


## Water Street, the harbour edge, dressed: along it by day, front
## yards close, the back yards from the slope below, the north side,
## then the same street at dusk in the storm.
func _water_street(world: TownMap, player: Player) -> void:
	world.set_weather(0.2)
	world.weather.wet = 0.0
	world.set_time_of_day(15.0)
	await _view(player, Vector3(0.0, 0.4, 44.0), -1.92, 0.02, "street_along")
	await _view(player, Vector3(45.0, 0.4, 45.0), PI, 0.0, "street_yard_45")
	await _view(player, Vector3(57.0, 0.4, 45.0), PI, 0.0, "street_yard_57")
	await _view(player, Vector3(7.5, 0.4, 45.0), PI, 0.0, "street_yard_8")
	await _view(player, Vector3(30.0, 0.4, 42.8), 0.0, 0.0, "street_north_side")
	var y := world.coast.height_at(40.0, 72.0)
	await _view(player, Vector3(40.0, y + 0.4, 72.0), 0.25, 0.08, "street_backs")
	y = world.coast.height_at(9.0, 66.5)
	await _view(player, Vector3(9.0, y + 0.4, 66.5), 0.0, 0.0, "street_back_8")
	y = world.coast.height_at(45.0, 66.5)
	await _view(player, Vector3(45.0, y + 0.4, 66.5), 0.0, 0.0, "street_back_45")
	world.set_weather(0.9)
	world.weather.wet = 1.0
	world.set_time_of_day(18.1)
	await _view(player, Vector3(0.0, 0.4, 44.0), -1.92, 0.05, "street_dusk")
	await _view(player, Vector3(45.0, 0.4, 45.0), PI, 0.05, "street_yard_45_dusk")


## The Cape at number 14, whose front is at (21, 51.5) facing north:
## outside in the storm, the rooms, the back from the harbour side, and
## the front on a fair afternoon.
func _house(world: TownMap, player: Player) -> void:
	await _view(player, Vector3(18.0, 0.4, 45.0), PI + 0.1, 0.08, "cape_front")
	await _view(player, Vector3(22.8, 1.0, 53.4), -PI / 2.0, -0.05, "cape_living")
	await _view(player, Vector3(21.5, 1.0, 55.6), PI / 2.0 + 0.3, -0.1, "cape_living_back")
	await _view(player, Vector3(19.2, 1.0, 56.1), PI / 2.0, -0.1, "cape_kitchen")
	await _view(player, Vector3(20.6, 1.0, 52.0), PI, 0.35, "cape_stair")
	await _view(player, Vector3(22.5, 3.7, 57.0), -0.95, -0.2, "cape_bedroom")
	await _view(player, Vector3(19.0, 3.7, 55.5), PI / 2.0 - 0.2, -0.1, "cape_boys_room")
	var y := world.coast.height_at(21.0, 66.0)
	await _view(player, Vector3(21.0, y + 0.4, 66.0), 0.0, 0.12, "cape_back")
	world.set_weather(0.0)
	world.set_time_of_day(14.0)
	await _view(player, Vector3(16.0, 0.4, 45.5), PI + 0.35, 0.1, "cape_front_day")
	await _view(player, Vector3(22.8, 1.0, 53.4), -PI / 2.0, -0.05, "cape_living_day")


func _view(player: Player, at: Vector3, yaw: float, pitch: float, name_: String) -> void:
	await _view_zoom(player, at, yaw, pitch, 0.0, name_)


func _view_zoom(player: Player, at: Vector3, yaw: float, pitch: float, zoom: float, name_: String) -> void:
	# The town stands on a hillside: a view is never below the ground.
	at.y = maxf(at.y, _world.coast.height_at(at.x, at.z) + 0.3)
	player.global_position = at
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	player.zoom_t = zoom
	player._zoom_now = zoom
	await get_tree().create_timer(1.2).timeout
	await _shot("user://probe_town_%s.png" % name_)
	print("[probe] %s: %.0f fps" % [name_, Engine.get_frames_per_second()])


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
