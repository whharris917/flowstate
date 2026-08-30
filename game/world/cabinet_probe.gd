extends Node
## Debug harness: places a control cabinet, lands a field wire on its
## terminal strip, hooks terminal -> PLC -> terminal internally, loads
## a mirror rung, then screenshots the open cabinet and its schematic
## panel. Run windowed: godot --path game res://world/cabinet_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(1.2).timeout
	var plant: Plant = (world as WorldBase).plant
	var player: Player = (world as WorldBase).player

	var plc := plant.place_new("cabinet", Vector3(5.5, 0.08, 2.0), 0.0) as SimPLC
	var cab := plc.comp_name.trim_suffix("_plc")
	plant.connect_equipment("level_switch", "contact", cab + "_td1", "in",
		[plant.to_local(Vector3(3.0, 0.3, 0.5))])
	plant.connect_equipment(cab + "_td1", "out", plc.comp_name, "di_0", [], false)
	plant.connect_equipment(plc.comp_name, "do_0", cab + "_td2", "in", [], false)
	plc.set_program([
		{"coil": "m_0", "logic": [
			[{"ref": "di_0"}, {"ref": "di_1", "nc": true}],
			[{"ref": "m_0"}, {"ref": "di_1", "nc": true}]]},
		{"coil": "t_0", "logic": [[{"ref": "m_0"}]]},
		{"coil": "do_0", "logic": [[{"ref": "t_0"}]]},
	])
	plc.set_timer_preset(0, 5.0)
	# Force the field contact closed so power flow lights up.
	(plant.sim.get_component("level_switch") as SimFloatSwitch).set_band(150.0, 150.0)

	# Swing the door open and stand where the interior is visible.
	var cab_view := (plant.cabinets[cab] as Dictionary)["node"] as CabinetView
	cab_view._door_open = true
	player.global_position = Vector3(5.5, 0.15, 6.5)
	player.zoom_t = 0.25
	player._zoom_now = 0.25
	player.camera.rotation.x = -0.15

	await get_tree().create_timer(1.2).timeout
	await _shot("user://probe_cabinet.png")
	plant.cabinet_panel.open(plant, cab)
	await get_tree().create_timer(0.4).timeout
	await _shot("user://probe_cabinet_panel.png")
	plant.cabinet_panel.visible = false
	plant.ladder_panel.open(plant, cab)
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_ladder.png")
	plant.ladder_panel.visible = false
	(world as WorldBase).builder.port_menu.open(plant, "fill_pump — I/O",
		["fill_pump"], Callable())
	await get_tree().create_timer(0.3).timeout
	await _shot("user://probe_portmenu.png")
	print("[probe] cabinet screenshots written to user://")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
