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


func _run(world: TownMap) -> void:
	await get_tree().create_timer(2.5).timeout
	var player := world.player
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	world.set_weather(0.9)
	world.set_time_of_day(18.1)
	world.weather.wet = 1.0
	world.weather._next_strike = 1000.0
	# The showpiece: Main Street in the storm, east to the church.
	await _view(player, Vector3(-6.0, 0.4, 17.5), -PI / 2.0, 0.02, "storm_main")
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


func _view(player: Player, at: Vector3, yaw: float, pitch: float, name_: String) -> void:
	await _view_zoom(player, at, yaw, pitch, 0.0, name_)


func _view_zoom(player: Player, at: Vector3, yaw: float, pitch: float, zoom: float, name_: String) -> void:
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
