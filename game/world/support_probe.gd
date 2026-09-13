extends Node
## Debug harness: boots the sandbox, places structure and two routed
## runs — one supported near the floor, one strung mid-air so the
## support rule flags it — then screenshots the scene for review.
## Run windowed: godot --path game res://world/support_probe.tscn


func _ready() -> void:
	MouseMode.probe = true
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(1.2).timeout
	var plant: Plant = (world as WorldBase).plant
	var player: Player = (world as WorldBase).player

	plant.place_structure("s_column", "probe_col_1", Vector3(5.0, 0.08, -0.5), 0.0)
	plant.place_structure("s_column", "probe_col_2", Vector3(9.0, 0.08, -0.5), 0.0)
	plant.place_structure("s_beam", "probe_beam", Vector3(7.0, 6.08, -0.5), 0.0, 4.35)
	plant.place_structure("s_wall", "probe_wall", Vector3(-6.0, 0.08, 3.0), 0.0)

	var low := plant.place_new("gauge_level", Vector3(12.0, 0.08, -2.0), 0.0)
	plant.connect_equipment("supply_tank", "level", low.comp_name, "process",
		[plant.to_local(Vector3(7.0, 0.42, -2.0))])
	var high := plant.place_new("gauge_level", Vector3(12.0, 0.08, 2.5), 0.0)
	plant.connect_equipment("supply_tank", "level", high.comp_name, "process",
		[plant.to_local(Vector3(7.0, 3.2, 2.5))])

	# Standalone infrastructure: a cable tray on the pad and a conduit
	# run strung above it, carried by the tray.
	plant.place_run("run_tray", "probe_tray",
		[plant.to_local(Vector3(1.0, 0.5, 4.0)), plant.to_local(Vector3(10.0, 0.5, 4.0))])
	plant.place_run("run_conduit", "probe_conduit",
		[plant.to_local(Vector3(1.2, 1.0, 4.0)), plant.to_local(Vector3(9.8, 1.0, 4.0))])

	# Service color + line label on the low run.
	for visual: Dictionary in plant._wire_visuals:
		if visual["b"] == low.comp_name:
			plant.set_run_service(visual["node"] as PipeView, Color(0.93, 0.79, 0.10), "PW-101")

	# The architectural set: door, window, stairs, catwalk, railing, sign.
	plant.place_structure("s_door", "probe_door", Vector3(-4.5, 0.08, 1.0), 0.0)
	plant.place_structure("s_window", "probe_window", Vector3(-6.0, 0.08, -3.5), PI / 2.0)
	plant.place_structure("s_stairs", "probe_stairs", Vector3(-2.0, 0.08, 2.4), 0.0)
	plant.place_structure("s_catwalk", "probe_catwalk", Vector3(-2.0, 0.08, -3.5), 0.0)
	plant.place_structure("s_railing", "probe_rail", Vector3(2.5, 0.08, 4.6), 0.0, 5.0)
	plant.place_structure("s_sign", "probe_sign", Vector3(3.4, 0.08, 3.4), 0.0)
	plant.set_sign_text("probe_sign", "STILL AREA\nPPE REQUIRED")

	player.global_position = Vector3(7.0, 0.15, 9.0)
	player.zoom_t = 0.75
	player._zoom_now = 0.75
	player.camera.rotation.x = -0.35

	await get_tree().create_timer(1.0).timeout
	for visual: Dictionary in plant._wire_visuals:
		if visual["b"] == high.comp_name:
			var sparse: Array = [plant._marker_pos(str(visual["a"]), str(visual["a_port"]))]
			sparse.append_array(visual["waypoints"])
			sparse.append(plant._marker_pos(str(visual["b"]), str(visual["b_port"])))
			var path := PipeRoute.lay(sparse)
			var global_path: Array[Vector3] = []
			for point in path:
				global_path.append(plant.to_global(point))
			var check := SupportCheck.evaluate(global_path,
				plant.get_world_3d().direct_space_state,
				(visual["node"] as PipeView).collider_rids())
			var pv := visual["node"] as PipeView
			print("[probe] high run ok=%s span=%.2f view_unsupported=%s meshes=%d is_bad=%s was_hot=%s getter=%.2f" % [
				check["ok"], check["max_span"], pv._unsupported, pv._meshes.size(),
				pv._meshes[0].material_override == pv._bad, pv._was_hot, pv._getter.call()])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://probe_support.png")
	print("[probe] screenshot written to user://probe_support.png")
	get_tree().quit()
