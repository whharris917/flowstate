extends Node
## Debug harness for the empty-cabinet workflow: place a cabinet,
## build its panel through the module API (PSU, PLC CPU, I/O cards,
## relay, terminal strip), wire it internally, feed it, then
## screenshot the open 3D interior, the cabinet editor, and the
## ladder editor. Run windowed:
##   godot --path game res://world/cabinet_probe.tscn


func _ready() -> void:
	var world: Node = (load("res://world/sandbox.tscn") as PackedScene).instantiate()
	add_child(world)
	_run(world)


func _run(world: Node) -> void:
	await get_tree().create_timer(1.2).timeout
	var plant: Plant = (world as WorldBase).plant
	var player: Player = (world as WorldBase).player

	var cab := "cabinet_1"
	plant.place_cabinet(cab, Vector3(5.5, 0.08, 2.0), 0.0)
	plant.cabinet_add_module(cab, "psu", 0, 0)
	plant.cabinet_add_module(cab, "plc", 0, 4)
	plant.cabinet_add_module(cab, "card_di", 0, 8)
	plant.cabinet_add_module(cab, "card_do", 0, 10)
	plant.cabinet_add_module(cab, "relay", 1, 0)
	plant.cabinet_add_module(cab, "relay", 1, 2)
	plant.cabinet_add_module(cab, "tb8d", 2, 0)
	var plc_name := plant.cabinet_plc(cab)
	var plc := plant.sim.get_component(plc_name) as SimPLC
	var psu_name := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "psu":
			psu_name = record_name
	var t := "%s_m7_t" % cab  # the strip's terminals

	plant.connect_equipment("level_switch", "contact", t + "1", "in",
		[plant.to_local(Vector3(3.0, 0.3, 0.5))])
	plant.connect_equipment(t + "1", "out", plc_name, "di_0", [], false)
	plant.connect_equipment(psu_name, "dc_out", plc_name, "power", [], false)
	plant.connect_equipment(plc_name, "do_0", t + "2", "in", [], false)
	plant.connect_equipment("plant_mains", "power", psu_name, "ac_in",
		[plant.to_local(Vector3(0.0, 0.3, 2.5))])
	plc.set_program([
		{"coil": "m_0", "logic": [
			[{"ref": "di_0"}, {"ref": "di_1", "nc": true}],
			[{"ref": "m_0"}, {"ref": "di_1", "nc": true}]]},
		{"coil": "t_0", "logic": [[{"ref": "m_0"}]]},
		{"coil": "do_0", "logic": [[{"ref": "t_0"}]]},
	])
	plc.set_timer_preset(0, 5.0)
	(plant.sim.get_component("level_switch") as SimFloatSwitch).set_band(150.0, 150.0)

	var cab_view := (plant.cabinets[cab] as Dictionary)["node"] as CabinetView
	cab_view._door_open = true
	player.global_position = Vector3(5.5, 0.15, 6.5)
	player.zoom_t = 0.25
	player._zoom_now = 0.25
	player.camera.rotation.x = -0.15

	await get_tree().create_timer(1.2).timeout
	await _shot("user://probe_cabinet.png")
	plant.cabinet_editor.open(plant, cab)
	await get_tree().create_timer(0.4).timeout
	await _shot("user://probe_cabinet_editor.png")
	plant.cabinet_editor.visible = false
	plant.ladder_panel.open(plant, cab)
	await get_tree().create_timer(0.6).timeout
	await _shot("user://probe_ladder.png")
	print("[probe] cabinet screenshots written to user://")
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
