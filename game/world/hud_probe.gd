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
	await get_tree().create_timer(1.2).timeout
	var hud: Hud = (get_child(0) as WorldBase).hud
	print("[probe] viewport ", get_viewport().get_visible_rect())
	print("[probe] hud rect ", hud.get_global_rect())
	print("[probe] readout ", hud._readout_label.get_global_rect())
	print("[probe] toast ", hud._toast_label.get_global_rect())
	print("[probe] mode ", hud._mode_label.get_global_rect())
	await _shot("user://probe_normal.png")
	_press(KEY_B)
	await get_tree().create_timer(0.5).timeout
	await _shot("user://probe_build.png")
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
