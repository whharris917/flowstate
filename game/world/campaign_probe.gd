extends Node
## Debug harness: boots the campaign, screenshots the gated build page
## and the journal, then quits. Run windowed (not headless):
##   godot --path game res://world/campaign_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/campaign.tscn") as PackedScene).instantiate()
	add_child(world)
	_run()


func _run() -> void:
	await get_tree().create_timer(1.6).timeout
	var world := get_child(0) as WorldBase
	world.player.camera.rotation.x = -0.5
	_press(KEY_B)
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_campaign_build.png")
	_press(KEY_B)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_J)
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_campaign_journal.png")
	print("[probe] campaign screenshots written to user://")
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
