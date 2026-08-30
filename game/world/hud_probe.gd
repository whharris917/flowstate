extends Node
## Debug harness: boots the sandbox, screenshots the HUD before and
## after injecting a build-mode keypress, then quits. Lets Claude see
## rendered output. Run windowed (not headless):
##   godot --path game res://world/hud_probe.tscn


func _ready() -> void:
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
