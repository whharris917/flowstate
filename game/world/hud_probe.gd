extends Node
## Debug harness: boots the sandbox, screenshots the HUD before and
## after injecting a build-mode keypress, then quits. Lets Claude see
## rendered output. Run windowed (not headless):
##   godot --path game res://world/hud_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run()


func _run() -> void:
	await get_tree().create_timer(1.6).timeout  # icon renders land in this window
	var world := get_child(0) as WorldBase
	await _shot("user://probe_normal.png")
	world.player.camera.rotation.x = -0.5  # aim at the floor so the ghost lands
	_press(KEY_B)
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_build.png")
	_press(KEY_TAB)
	await get_tree().create_timer(0.4).timeout
	await _shot("user://probe_structure.png")
	# The options panel, with the graphics section and the live frame rate.
	_press(KEY_B)
	world.player.camera.rotation.x = 0.0
	_press(KEY_O)
	await get_tree().create_timer(0.5).timeout
	await _shot("user://probe_options.png")
	_press(KEY_O)
	# Each graphics preset from the same spot, with its frame rate.
	for preset: String in GraphicsSettings.PRESET_NAMES:
		world.graphics.set_preset(preset)
		world.graphics.apply(world)
		# Pipelines compile on the first frames after a switch; the rate
		# is read once they have, sampled for three seconds, and the best
		# second is reported: the laptop's clock wanders, and the best
		# second is the one least disturbed by it.
		await get_tree().create_timer(2.5).timeout
		var best := 0.0
		var loop_ms := 0.0
		for _k in 6:
			await get_tree().create_timer(0.5).timeout
			best = maxf(best, Engine.get_frames_per_second())
			loop_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 / 6.0
		await _shot("user://probe_graphics_%s.png" % preset.to_lower())
		print("[probe] graphics %s: %.0f fps (loop %.0f ms) — %s" % [preset, best, loop_ms, world.graphics.summary()])
	world.graphics.set_preset("High")
	world.graphics.apply(world)
	# The same view at noon and at dusk: the lighting pass reads here.
	for shot: Array in [[12.0, "noon"], [17.7, "dusk"], [21.0, "night"]]:
		world.set_time_of_day(float(shot[0]))
		await get_tree().create_timer(0.5).timeout
		await _shot("user://probe_%s.png" % str(shot[1]))
	# The night sky from outside the hall, looking up past the roof line.
	world.player.global_position = Vector3(-30.0, 0.35, 0.0)
	world.player.rotation.y = PI / 2.0
	world.player.camera.rotation.x = 0.55
	await get_tree().create_timer(0.5).timeout
	await _shot("user://probe_night_sky.png")
	print("[probe] screenshots written to user://")
	get_tree().quit()


func _press(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
