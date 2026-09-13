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
	# What each part of the showcase costs on Low (director, 2026-09-13:
	# "the showcase needs to reach 60 fps on Low"): the rate with each
	# part hidden in turn, and with cheaper settings.
	world.graphics.set_preset("Low")
	world.graphics.apply(world)
	var plant := world.plant
	var forests: Array = []
	var runs: Array = []
	for child in world.get_children():
		if child is Forest:
			forests.append(child)
	for child in plant.get_children():
		if child is PipeView:
			runs.append(child)
	var views: Array = plant.views.values()
	var hall := world.find_child("Hall", false, false)
	var gallery := world.find_child("Gallery", false, false)
	var show := func(nodes: Array, on: bool) -> void:
		for node in nodes:
			if node != null:
				(node as Node3D).visible = on
	var parts: Array = [
		["everything", func(on: bool) -> void: pass],
		["without the forest", func(on: bool) -> void: show.call(forests, on)],
		["without the hall", func(on: bool) -> void: show.call([hall], on)],
		["without the gallery", func(on: bool) -> void: show.call([gallery], on)],
		["without the runs", func(on: bool) -> void: show.call(runs, on)],
		["without the equipment", func(on: bool) -> void: show.call(views, on)],
		["without shadows", func(on: bool) -> void: world.sun.shadow_enabled = on],
		["without the hall lights", func(on: bool) -> void:
			for light in (world as Object).get("_hall_lights"):
				(light as Light3D).visible = on],
		["at 25% scale (the CPU floor)", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 0.25
			world.graphics.apply(world)],
		["at 100% scale, no upscaler", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 1.0
			world.graphics.values["upscaler"] = "fsr1" if on else "bilinear"
			world.graphics.apply(world)],
		["without the HMI screens", func(on: bool) -> void:
			for node in _screens(world):
				(node as Node3D).visible = on],
		# Script cost, at quarter scale so the GPU is out of it: each
		# group's processing switched off, its geometry still drawn.
		["at 25%, views not processing", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 0.25
			world.graphics.apply(world)
			for node in views:
				(node as Node).propagate_call("set_process", [on])],
		["at 25%, runs not processing", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 0.25
			world.graphics.apply(world)
			for node in runs:
				(node as Node).propagate_call("set_process", [on])],
		["at 25%, HUD and screens not processing", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 0.25
			world.graphics.apply(world)
			world.hud.set_process(on)
			for node in _screens(world):
				(node as Node).propagate_call("set_process", [on])],
		["at 25%, world not processing", func(on: bool) -> void:
			world.graphics.values["scale"] = 0.5 if on else 0.25
			world.graphics.apply(world)
			world.set_process(on)],
	]
	for part: Array in parts:
		(part[1] as Callable).call(false)
		await get_tree().create_timer(1.5).timeout
		var best := 0.0
		for _k in 4:
			await get_tree().create_timer(0.5).timeout
			best = maxf(best, Engine.get_frames_per_second())
		print("[probe] Low %-30s %.0f fps · %.2f M tris · %d draws" % [str(part[0]), best,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		(part[1] as Callable).call(true)
	# How much of the scan the frame still waits for on Low: the join
	# at the end of the draw, sampled per frame for two seconds.
	world.graphics.set_preset("Low")
	world.graphics.apply(world)
	await get_tree().create_timer(1.5).timeout
	var waits: Array[float] = []
	var t_wait_end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < t_wait_end:
		await get_tree().process_frame
		waits.append(plant.last_join_ms)
		plant.last_join_ms = 0.0
	var wait_sum := 0.0
	var wait_max := 0.0
	var waited := 0
	for w in waits:
		wait_sum += w
		wait_max = maxf(wait_max, w)
		if w > 0.5:
			waited += 1
	print("[probe] scan join on Low: %d frames, %d waited, mean %.1f ms, worst %.1f ms, scan %.1f ms"
		% [waits.size(), waited, wait_sum / maxi(waits.size(), 1), wait_max, plant.last_tick_ms])
	# Frame pacing on Medium (director, 2026-09-13: "looking around is a
	# bit jumpy"): a jumpy look is frames of uneven length, not a low
	# average, so every frame's length is sampled for three seconds and
	# the spread is printed with the mean.
	world.graphics.set_preset("Medium")
	world.graphics.apply(world)
	await get_tree().create_timer(2.0).timeout
	var frames: Array[float] = []
	var t_end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		frames.append(get_process_delta_time() * 1000.0)
	var mean := 0.0
	for f in frames:
		mean += f
	mean /= maxi(frames.size(), 1)
	var worst := 0.0
	var spread := 0.0
	var long_frames := 0
	for f in frames:
		worst = maxf(worst, f)
		spread += (f - mean) * (f - mean)
		if f > 1.5 * mean:
			long_frames += 1
	spread = sqrt(spread / maxi(frames.size(), 1))
	print("[probe] pacing on Medium: %d frames, mean %.1f ms, spread %.1f ms, worst %.1f ms, %d frames over 1.5x the mean"
		% [frames.size(), mean, spread, worst, long_frames])
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


## The in-world screens, each a SubViewport rendered every frame.
static func _screens(node: Node) -> Array:
	var out: Array = []
	if node is HmiScreenView or node is HmiView:
		out.append(node)
		return out
	for child in node.get_children():
		out.append_array(_screens(child))
	return out


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
