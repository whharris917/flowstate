extends Node
## Debug harness for the Maine coast: boots the site and photographs
## it from the pad, across the cove, from the shore ledge and from the
## air, then at dawn, dusk and night, printing the frame rate with
## each shot. Run windowed:
##   godot --path game res://world/maine_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	# FLOWSTATE_PROBE_SCENE names another world (the blank map, say) for
	# a frame-rate comparison from the same two vantages.
	var scene := OS.get_environment("FLOWSTATE_PROBE_SCENE")
	if scene.is_empty():
		scene = "res://world/maine.tscn"
	var world: Node = (load(scene) as PackedScene).instantiate()
	add_child(world)
	if not world is MaineMap:
		_prefix = "probe_%s_" % world.name.to_lower()
	_run(world as WorldBase)


var _prefix := "probe_maine_"


func _run(world: WorldBase) -> void:
	await get_tree().create_timer(2.5).timeout
	var player := world.player
	world.set_time_of_day(10.0)
	# From the pad's south-east corner, out over the ledges to the sea.
	await _view(player, Vector3(70.0, 0.35, 55.0), -2.35, -0.12, 0.0, "pad_sea")
	if not world is MaineMap:
		await _view(player, Vector3(16.0, 0.35, 10.0), -2.35, -0.8, 2.3, "aerial")
		print("[probe] comparison run on %s done" % world.name)
		get_tree().quit()
		return
	var coast := (world as MaineMap).coast
	# Across the cove to the lighthouse, then the same view under each
	# graphics preset with its frame rate, once the pipelines have compiled.
	await _view(player, Vector3(-20.0, 0.35, 70.0), 2.64, -0.05, 0.0, "lighthouse")
	for preset: String in GraphicsSettings.PRESET_NAMES:
		world.graphics.set_preset(preset)
		world.graphics.apply(world)
		# Pipelines compile first; then three seconds of samples, and the
		# best second is reported, as the least disturbed by the laptop's clock.
		await get_tree().create_timer(2.5).timeout
		var best := 0.0
		var loop_ms := 0.0
		for _k in 6:
			await get_tree().create_timer(0.5).timeout
			best = maxf(best, Engine.get_frames_per_second())
			loop_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 / 6.0
		await _shot("user://%sgraphics_%s.png" % [_prefix, preset.to_lower()])
		print("[probe] graphics %s: %.0f fps (loop %.0f ms) — %s" % [preset, best, loop_ms,
			world.graphics.summary()])
	world.graphics.set_preset("High")
	world.graphics.apply(world)
	# From the east shore ledge, back up at the site.
	var y := coast.height_at(104.0, 30.0)
	await _view(player, Vector3(104.0, y + 0.4, 30.0), PI / 2.0, 0.08, 0.0, "shore")
	# Down on the beach at the cove's head, looking out.
	y = coast.height_at(-30.0, 92.0)
	await _view(player, Vector3(-30.0, y + 0.4, 92.0), PI, 0.02, 0.0, "beach")
	# The aerial.
	await _view(player, Vector3(16.0, 0.35, 10.0), -2.35, -0.8, 2.3, "aerial")
	# The clock: dawn fog, dusk, night with the light.
	for shot: Array in [[6.3, "dawn"], [17.8, "dusk"], [21.5, "night"]]:
		world.set_time_of_day(float(shot[0]))
		await _view(player, Vector3(-20.0, 0.35, 70.0), 2.64, -0.02, 0.0, str(shot[1]))
	print("[probe] screenshots written to user://")
	get_tree().quit()


func _view(player: Player, at: Vector3, yaw: float, pitch: float, zoom: float, name_: String) -> void:
	player.global_position = at
	player.rotation.y = yaw
	player.camera.rotation.x = pitch
	player.zoom_t = zoom
	player._zoom_now = zoom
	await get_tree().create_timer(0.8).timeout
	await _shot("user://%s%s.png" % [_prefix, name_])
	print("[probe] %s: %.0f fps, player at (%.0f, %.1f, %.0f)" % [name_, Engine.get_frames_per_second(),
		player.global_position.x, player.global_position.y, player.global_position.z])


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
