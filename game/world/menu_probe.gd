extends Node
## Debug harness: shows the title screen, screenshots it, quits.
##   godot --path game res://world/menu_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	add_child((load("res://world/menu.tscn") as PackedScene).instantiate())
	_run()


func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://probe_menu.png")
	print("[probe] menu screenshot written to user://")
	get_tree().quit()
