extends Node
## Debug harness: boots the sandbox, places structure and two routed
## runs — one supported near the floor, one strung mid-air so the
## support rule flags it — then screenshots the scene for review.
## Run windowed: godot --path game res://world/support_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(1.2).timeout
	var plant: Plant = (world as WorldBase).plant
	var player: Player = (world as WorldBase).player

	plant.place_structure("s_column", "probe_col_1", Vector3(5.0, 0.08, -0.5), 0.0)
	plant.place_structure("s_column", "probe_col_2", Vector3(9.0, 0.08, -0.5), 0.0)
	plant.place_structure("s_beam", "probe_beam", Vector3(7.0, 6.08, -0.5), 0.0)
	plant.place_structure("s_wall", "probe_wall", Vector3(-6.0, 0.08, 3.0), 0.0)

	var low := plant.place_new("gauge_level", Vector3(12.0, 0.08, -2.0), 0.0)
	plant.connect_equipment("supply_tank", "level", low.comp_name, "process",
		[plant.to_local(Vector3(7.0, 0.42, -2.0))])
	var high := plant.place_new("gauge_level", Vector3(12.0, 0.08, 2.5), 0.0)
	plant.connect_equipment("supply_tank", "level", high.comp_name, "process",
		[plant.to_local(Vector3(7.0, 3.2, 2.5))])

	player.global_position = Vector3(7.0, 0.15, 9.0)
	player.zoom_t = 0.75
	player._zoom_now = 0.75
	player.camera.rotation.x = -0.35

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://probe_support.png")
	print("[probe] screenshot written to user://probe_support.png")
	get_tree().quit()
