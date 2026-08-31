extends Node
## Debug harness: boots the sandbox (which builds the showcase) and
## screenshots the unit area — aerial overview, Unit 100, and the MCC
## zone — after letting the processes run a few seconds.
## Run windowed: godot --path game res://world/showcase_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(4.0).timeout  # let loops move
	var player: Player = (world as WorldBase).player

	player.global_position = Vector3(8.0, 0.15, 14.0)
	player.zoom_t = 1.35
	player._zoom_now = 1.35
	player.camera.rotation.x = -0.72
	await get_tree().create_timer(0.8).timeout
	await _shot("user://probe_showcase_aerial.png")

	player.global_position = Vector3(16.0, 0.15, 1.5)
	player.rotation.y = 0.0  # facing -z, toward Unit 100
	player.zoom_t = 0.55
	player._zoom_now = 0.55
	player.camera.rotation.x = -0.25
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u100.png")

	player.global_position = Vector3(16.5, 0.15, 12.5)
	player.rotation.y = 0.0
	player.zoom_t = 0.5
	player._zoom_now = 0.5
	player.camera.rotation.x = -0.2
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_mcc.png")

	player.global_position = Vector3(31.5, 0.15, -11.5)
	player.rotation.y = PI  # facing +z, into the synthesis train
	player.zoom_t = 0.85
	player._zoom_now = 0.85
	player.camera.rotation.x = -0.32
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_showcase_u300.png")

	# Honest numbers, not just pictures: after ~6 s of sim the boiler
	# should be firing, both feeds moving, and the reactor warming.
	var plant := (world as WorldBase).plant
	var sg := plant.sim.get_component("sg_301") as SimSteamGen
	var reac := plant.sim.get_component("r_301") as SimReactor
	var fuge := plant.sim.get_component("cf_301") as SimCentrifuge
	var product_tank := plant.sim.get_component("pt_300") as SimTank
	print("[probe] u300: steam %.2f kg/s · duty->%.0f kW · reactor %.0f L %.1f C · fuge %s · pt_300 %.1f L" % [
		sg.steam.value, reac.heat_duty.value, reac.volume_l, reac.temp_c,
		"SPIN" if fuge.spinning else "idle", product_tank.level_l])
	var bad: Array[String] = []
	for visual: Dictionary in plant._wire_visuals:
		var node: Node = visual["node"]
		if node is PipeView and (node as PipeView)._unsupported:
			bad.append("%s->%s" % [visual["a"], visual["b"]])
	print("[probe] unsupported runs: %s" % ("none" if bad.is_empty() else ", ".join(bad)))
	print("[probe] showcase screenshots written to user://")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
