class_name Showcase
## Builds the sandbox showcase: a realistic unit segment exercising
## every system in the game — structural steel, a pipe rack with
## labeled services, a PID level loop (Unit 100), an MCC room whose
## cabinet was built module-by-module and runs a batch tank on ladder
## logic with a TON anti-chatter delay, plus signage. Everything is
## sim-backed and live; nothing is decoration. Coordinates are world
## space on the sandbox ground plane.


static func build(plant: Plant) -> void:
	_pipe_rack(plant)
	_unit_100(plant)
	_mcc_and_batch(plant)
	_signage(plant)


## ---- pipe rack PR-1: steel bents carrying services east ------------------

static func _pipe_rack(plant: Plant) -> void:
	for x: float in [9.0, 15.0, 21.0]:
		plant.place_structure("s_column", "pr1_col_%d" % int(x), Vector3(x, 0.0, 1.5), 0.0)
	for tier: float in [3.0, 4.0]:
		for mid_x: float in [12.0, 18.0]:
			plant.place_structure("s_beam", "pr1_beam_%d_%d" % [int(tier), int(mid_x)],
				Vector3(mid_x, tier, 1.5), 0.0, 6.0)
	plant.place_run("run_tray", "pr1_tray",
		[plant.to_local(Vector3(9.2, 3.35, 1.5)), plant.to_local(Vector3(20.8, 3.35, 1.5))])
	plant.place_run("run_conduit", "pr1_conduit",
		[plant.to_local(Vector3(9.2, 3.55, 1.5)), plant.to_local(Vector3(20.8, 3.55, 1.5))])
	plant.place_run("run_pipe", "pr1_pw",
		[plant.to_local(Vector3(9.2, 4.35, 1.15)), plant.to_local(Vector3(20.8, 4.35, 1.15))])
	plant.place_run("run_pipe", "pr1_st",
		[plant.to_local(Vector3(9.2, 4.35, 1.85)), plant.to_local(Vector3(20.8, 4.35, 1.85))])
	_service_run(plant, "pr1_pw", Color(0.13, 0.55, 0.28), "PW-101")
	_service_run(plant, "pr1_st", Color(0.78, 0.79, 0.82), "ST-201")


## ---- Unit 100: steel frame + deck over a working PID level loop ----------

static func _unit_100(plant: Plant) -> void:
	# Frame: four columns, top beams, one deck with catwalk, railings,
	# and stairs landing on the east edge.
	for corner: Vector2 in [Vector2(13, -6), Vector2(19, -6), Vector2(13, -1.8), Vector2(19, -1.8)]:
		plant.place_structure("s_column", "u100_col_%d_%d" % [int(corner.x), int(-corner.y * 10)],
			Vector3(corner.x, 0.0, corner.y), 0.0)
	plant.place_structure("s_beam", "u100_beam_s", Vector3(16, 3.0, -6.0), 0.0, 6.0)
	plant.place_structure("s_beam", "u100_beam_n", Vector3(16, 3.0, -1.8), 0.0, 6.0)
	plant.place_structure("s_beam", "u100_beam_w", Vector3(13, 3.0, -3.9), PI / 2.0, 4.2)
	plant.place_structure("s_beam", "u100_beam_e", Vector3(19, 3.0, -3.9), PI / 2.0, 4.2)
	plant.place_structure("s_deck", "u100_deck", Vector3(16, 3.18, -3.9), 0.0)
	plant.place_structure("s_catwalk", "u100_catwalk", Vector3(16, 3.18, -6.2), 0.0)
	plant.place_structure("s_railing", "u100_rail_n", Vector3(16, 3.33, -1.95), 0.0, 4.0)
	plant.place_structure("s_railing", "u100_rail_w", Vector3(14.05, 3.33, -3.9), PI / 2.0, 3.8)
	plant.place_structure("s_stairs", "u100_stairs", Vector3(20.1, 0.0, -3.9), PI / 2.0)

	# The loop: LV-101 fills FT-100 against a constant drain; LT-101
	# reads the head, LIC-101 drives the valve. Settles at SP 15 kPa.
	plant.place("valve", "lv_101", {"cv_lps": 6.0}, Vector3(13.8, 0.0, -3.5), 0.0, false)
	plant.place("tank", "ft_100", {"capacity_l": 200.0, "level_l": 40.0, "drain_lps": 2.5},
		Vector3(17.0, 0.0, -3.5), 0.0, false)
	plant.place("gauge_level", "lt_101", {}, Vector3(18.9, 0.0, -2.6), 0.0, false)
	plant.place("controller", "lic_101", {"kp": 8.0, "ki": 1.5, "sp": 15.0},
		Vector3(13.2, 0.0, -5.8), 0.0, false)
	plant.connect_equipment("lv_101", "flow", "ft_100", "in_flow",
		[plant.to_local(Vector3(15.4, 0.3, -3.5))])
	plant.connect_equipment("ft_100", "level", "lt_101", "process")
	plant.connect_equipment("lt_101", "signal", "lic_101", "pv",
		[plant.to_local(Vector3(18.9, 0.3, -5.4)), plant.to_local(Vector3(14.6, 0.3, -5.8))])
	plant.connect_equipment("lic_101", "out", "lv_101", "cmd",
		[plant.to_local(Vector3(13.5, 0.3, -4.6))])
	_service_wire(plant, "lv_101", "ft_100", Color(0.13, 0.55, 0.28), "BW-102")


## ---- MCC room + PLC-run batch tank ---------------------------------------

static func _mcc_and_batch(plant: Plant) -> void:
	# The room: wall run with a doorway and a window wall.
	plant.place_structure("s_door", "mcc_door", Vector3(12.6, 0.0, 5.2), 0.0)
	plant.place_structure("s_wall", "mcc_wall", Vector3(15.4, 0.0, 5.2), 0.0)
	plant.place_structure("s_window", "mcc_window", Vector3(19.4, 0.0, 5.2), 0.0)

	# The cabinet, built the way a player would: modules on rails, then
	# internal wiring, then the program.
	var cab := "mcc_cab"
	plant.place_cabinet(cab, Vector3(14.4, 0.0, 6.6), 0.0)
	plant.cabinet_add_module(cab, "psu", 0, 0)
	plant.cabinet_add_module(cab, "plc", 0, 4)
	plant.cabinet_add_module(cab, "card_di", 0, 8)
	plant.cabinet_add_module(cab, "card_do", 0, 10)
	plant.cabinet_add_module(cab, "relay", 1, 0)
	plant.cabinet_add_module(cab, "tb8d", 2, 0)
	var plc_name := plant.cabinet_plc(cab)
	var plc := plant.sim.get_component(plc_name) as SimPLC
	var psu_name := ""
	var relay_name := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "psu":
			psu_name = record_name
		elif plant.equip_types.get(record_name) == "relay":
			relay_name = record_name
	var t := "%s_m6_t" % cab
	plant.connect_equipment(psu_name, "dc_out", plc_name, "power", [], false)
	plant.connect_equipment(t + "1", "out", plc_name, "di_0", [], false)
	plant.connect_equipment(plc_name, "do_0", relay_name, "coil", [], false)
	plant.connect_equipment(relay_name, "contact", t + "2", "in", [], false)
	# Low level calls for fill; the TON holds off 2 s so a sloshing
	# switch can't chatter the starter.
	plc.set_program([
		{"coil": "t_0", "logic": [[{"ref": "di_0"}]]},
		{"coil": "do_0", "logic": [[{"ref": "t_0"}]]},
	])
	plc.set_timer_preset(0, 2.0)

	# The batch tank and its feed pump, run from the cabinet.
	plant.place("tank", "bt_200", {"capacity_l": 150.0, "level_l": 30.0, "drain_lps": 1.2},
		Vector3(19.0, 0.0, 8.2), 0.0, false)
	plant.place("float_switch", "ls_201", {"low_l": 40.0, "high_l": 110.0},
		Vector3(17.6, 1.32, 8.2), 0.0, false)
	plant.place("pump", "feed_pump", {"rated_lps": 3.0}, Vector3(15.4, 0.0, 8.4), 0.0, false)
	plant.place("gauge_flow", "fi_201", {}, Vector3(16.6, 0.0, 9.6), 0.0, false)
	plant.connect_equipment("bt_200", "level", "ls_201", "level")
	plant.connect_equipment("ls_201", "contact", t + "1", "in",
		[plant.to_local(Vector3(17.3, 0.3, 7.2)), plant.to_local(Vector3(15.2, 0.3, 6.8))])
	plant.connect_equipment(t + "2", "out", "feed_pump", "run",
		[plant.to_local(Vector3(15.3, 0.3, 7.4))])
	plant.connect_equipment("feed_pump", "flow", "bt_200", "in_flow",
		[plant.to_local(Vector3(17.2, 0.3, 8.6))])
	plant.connect_equipment("feed_pump", "flow", "fi_201", "process")
	_service_wire(plant, "feed_pump", "bt_200", Color(0.15, 0.35, 0.75), "PW-201")

	# Power: 480 V from the plant feeder, through the doorway, to the
	# cabinet PSU and the pump starter.
	plant.connect_equipment("plant_mains", "power", psu_name, "ac_in",
		[plant.to_local(Vector3(-3.6, 0.3, 0.2)), plant.to_local(Vector3(12.6, 0.3, 4.4)),
		plant.to_local(Vector3(12.6, 0.3, 6.2)), plant.to_local(Vector3(13.8, 0.3, 6.6))])
	plant.connect_equipment("plant_mains", "power", "feed_pump", "power",
		[plant.to_local(Vector3(-3.6, 0.3, 0.4)), plant.to_local(Vector3(12.5, 0.3, 4.5)),
		plant.to_local(Vector3(12.5, 0.3, 7.0)), plant.to_local(Vector3(15.0, 0.3, 8.0))])


static func _signage(plant: Plant) -> void:
	var signs := [
		["sign_u100", Vector3(11.6, 0.0, -2.4), 0.0, "UNIT 100\nLEVEL CONTROL"],
		["sign_mcc", Vector3(12.9, 0.0, 7.8), PI, "MCC-1\nAUTHORIZED ONLY"],
		["sign_rack", Vector3(9.0, 0.0, 2.8), 0.0, "PIPE RACK PR-1\nNO CLIMBING"],
		["sign_still", Vector3(4.9, 0.08, -4.8), 0.0, "STILL AREA\nPPE REQUIRED"],
	]
	for entry: Array in signs:
		plant.place_structure("s_sign", entry[0], entry[1], entry[2])
		plant.set_sign_text(entry[0], entry[3])


## ---- helpers --------------------------------------------------------------

static func _service_wire(plant: Plant, a: String, b: String, color: Color, label: String) -> void:
	for visual: Dictionary in plant._wire_visuals:
		if str(visual["a"]) == a and str(visual["b"]) == b and visual["node"] != null:
			plant.set_run_service(visual["node"] as PipeView, color, label)
			return


static func _service_run(plant: Plant, run_name: String, color: Color, label: String) -> void:
	if plant.runs.has(run_name):
		plant.set_run_service((plant.runs[run_name] as Dictionary)["node"] as PipeView,
			color, label)
