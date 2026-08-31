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
	_unit_300(plant)
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

	# The loop: LV-101 fills FT-100 from the supply header
	# against a real drain; LT-101 reads the head, LIC-101 drives the
	# valve. Settles at SP 15 kPa, with every liter metered.
	plant.place("source", "supply_101", {}, Vector3(11.0, 0.0, -5.6), 0.0, false)
	plant.place("valve", "lv_101", {"cv_lps": 6.0}, Vector3(13.8, 0.0, -3.5), 0.0, false)
	# A real vessel: 2.4 m x 1.1 m dia -> 2281 L; the transmitter is
	# ranged to its geometry (950 L per meter of head).
	plant.place("tank", "ft_100", {"height_m": 2.4, "diameter_m": 1.1, "level_l": 1100.0},
		Vector3(17.0, 0.0, -3.5), 0.0, false)
	plant.place("drain", "du_101", {"rate_lps": 2.5}, Vector3(17.0, 0.0, -6.1), 0.0, false)
	plant.place("gauge_level", "lt_101", {"liters_per_meter": 950.4},
		Vector3(18.9, 0.0, -2.6), 0.0, false)
	plant.place("controller", "lic_101", {"kp": 8.0, "ki": 1.5, "sp": 15.0},
		Vector3(13.2, 0.0, -5.8), 0.0, false)
	plant.connect_equipment("supply_101", "outlet", "lv_101", "inlet",
		[plant.to_local(Vector3(12.0, 0.3, -4.4))])
	plant.connect_equipment("lv_101", "outlet", "ft_100", "inlet",
		[plant.to_local(Vector3(15.4, 0.3, -3.5))])
	plant.connect_equipment("ft_100", "outlet", "du_101", "inlet")
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

	# The batch tank and its feed pump, run from the cabinet, drawing
	# from a dedicated supply header and draining for real.
	plant.place("source", "supply_201", {}, Vector3(13.4, 0.0, 9.8), 0.0, false)
	# 2.0 m x 1.0 m dia -> 1571 L, trips at 500/1100 L.
	plant.place("tank", "bt_200", {"height_m": 2.0, "diameter_m": 1.0, "level_l": 480.0},
		Vector3(19.0, 0.0, 8.2), 0.0, false)
	plant.place("drain", "du_201", {"rate_lps": 1.2}, Vector3(20.8, 0.0, 9.4), 0.0, false)
	plant.place("float_switch", "ls_201", {"low_l": 500.0, "high_l": 1100.0},
		Vector3(17.6, 1.1, 8.2), 0.0, false)
	plant.place("pump", "feed_pump", {"rated_lps": 3.0}, Vector3(15.4, 0.0, 8.4), 0.0, false)
	plant.place("gauge_flow", "fi_201", {}, Vector3(16.6, 0.0, 9.6), 0.0, false)
	plant.connect_equipment("supply_201", "outlet", "feed_pump", "inlet",
		[plant.to_local(Vector3(14.2, 0.3, 9.2))])
	plant.connect_equipment("bt_200", "outlet", "du_201", "inlet")
	plant.connect_equipment("bt_200", "level", "ls_201", "level")
	plant.connect_equipment("ls_201", "contact", t + "1", "in",
		[plant.to_local(Vector3(17.3, 0.3, 7.2)), plant.to_local(Vector3(15.2, 0.3, 6.8))])
	plant.connect_equipment(t + "2", "out", "feed_pump", "run",
		[plant.to_local(Vector3(15.3, 0.3, 7.4))])
	plant.connect_equipment("feed_pump", "outlet", "bt_200", "inlet",
		[plant.to_local(Vector3(17.2, 0.3, 8.6))])
	plant.connect_equipment("feed_pump", "outlet", "fi_201", "process")
	_service_wire(plant, "feed_pump", "bt_200", Color(0.15, 0.35, 0.75), "PW-201")

	# Power: 480 V from the plant feeder, through the doorway, to the
	# cabinet PSU and the pump starter.
	plant.connect_equipment("plant_mains", "power", psu_name, "ac_in",
		[plant.to_local(Vector3(-3.6, 0.3, 0.2)), plant.to_local(Vector3(12.6, 0.3, 4.4)),
		plant.to_local(Vector3(12.6, 0.3, 6.2)), plant.to_local(Vector3(13.8, 0.3, 6.6))])
	plant.connect_equipment("plant_mains", "power", "feed_pump", "power",
		[plant.to_local(Vector3(-3.6, 0.3, 0.4)), plant.to_local(Vector3(12.5, 0.3, 4.5)),
		plant.to_local(Vector3(12.5, 0.3, 7.0)), plant.to_local(Vector3(15.0, 0.3, 8.0))])


## ---- Unit 300: synthesis train --------------------------------------------
## Two reactant headers feed a jacketed reactor; a steam generator
## fires a heat exchanger that preheats the A-feed and delivers the
## reaction duty; the centrifuge splits the reactor discharge on its
## live purity signal — product to a 56 kL storage tank, waste to the
## sewer. Every stream is metered, every motor is powered and audible.

static func _unit_300(plant: Plant) -> void:
	# Rack extension carrying the area's cable tray east to the unit.
	for x: float in [27.0, 33.0, 39.0]:
		plant.place_structure("s_column", "pr1x_col_%d" % int(x), Vector3(x, 0.0, 1.5), 0.0)
	for tier: float in [3.0, 4.0]:
		for mid_x: float in [24.0, 30.0, 36.0]:
			plant.place_structure("s_beam", "pr1x_beam_%d_%d" % [int(tier), int(mid_x)],
				Vector3(mid_x, tier, 1.5), 0.0, 6.0)
	plant.place_run("run_tray", "pr1x_tray",
		[plant.to_local(Vector3(21.2, 3.35, 1.5)), plant.to_local(Vector3(38.8, 3.35, 1.5))])

	# Equipment: headers, feed pumps, boiler, exchanger, reactor,
	# centrifuge, product tank, waste drain, level transmitter.
	plant.place("source", "supply_301a", {}, Vector3(24.0, 0.0, -7.5), 0.0, false)
	plant.place("source", "supply_301b", {}, Vector3(24.0, 0.0, -3.5), 0.0, false)
	plant.place("source", "supply_bfw", {}, Vector3(24.0, 0.0, 2.5), 0.0, false)
	plant.place("pump", "p_301a", {"rated_lps": 2.0}, Vector3(26.6, 0.0, -7.5), 0.0, false)
	plant.place("pump", "p_301b", {"rated_lps": 2.0}, Vector3(26.6, 0.0, -3.5), 0.0, false)
	plant.place("steamgen", "sg_301", {"rated_kgps": 0.5}, Vector3(27.6, 0.0, 3.2), 0.0, false)
	plant.place("hx", "e_301", {"max_duty_kw": 1200.0}, Vector3(30.8, 0.0, -0.5), 0.0, false)
	plant.place("reactor", "r_301", {"capacity_l": 4000.0, "rate_lps": 6.0},
		Vector3(34.2, 0.0, -4.5), 0.0, false)
	plant.place("centrifuge", "cf_301", {"rate_lps": 4.0}, Vector3(37.6, 0.0, -4.5), 0.0, false)
	plant.place("drain", "du_301", {"rate_lps": 2.0}, Vector3(35.2, 0.0, -7.8), 0.0, false)
	# The transfer lock: cycles vacuum-vent-drain on its own, its
	# pressure on a local gauge and its condensate to an open drain.
	plant.place("vaclock", "vl_302", {}, Vector3(30.6, 0.0, -8.0), 0.0, false)
	plant.place("gauge_press", "pi_302", {}, Vector3(28.8, 0.0, -8.6), 0.0, false)
	plant.place("drain", "du_302", {"rate_lps": 1.5}, Vector3(32.8, 0.0, -8.3), 0.0, false)
	# The prize: 7.0 m x 3.2 m dia -> ~56.3 kL of finished product.
	# A 1500 L heel from the last campaign, so downstream filling has
	# something to run on while today's batch converts.
	plant.place("tank", "pt_300", {"height_m": 7.0, "diameter_m": 3.2, "level_l": 1500.0},
		Vector3(37.8, 0.0, 1.8), 0.0, false)
	# Fill-finish: the isolator draws real product from the tank.
	plant.place("vialfill", "vf_310", {}, Vector3(41.5, 0.0, -1.2), 0.0, false)
	plant.place("gauge_level", "lt_300", {"liters_per_meter": 8042.5},
		Vector3(40.2, 0.0, 3.2), 0.0, false)
	# Nozzles where a real tank has them: fill low on the south face
	# (a 6 m riser to the top head would be an unsupported span), level
	# tap low on the east face, toward its transmitter.
	var pt_view := plant.views["pt_300"] as TankView
	pt_view.set_nozzle("inlet", 0.10, -1.9)
	pt_view.set_nozzle("level", 0.22, 0.53)

	# Process path. Facade pairs meter the header and reactor draws.
	plant.connect_equipment("supply_301a", "outlet", "p_301a", "inlet")
	plant.connect_equipment("supply_301b", "outlet", "p_301b", "inlet")
	plant.connect_equipment("supply_bfw", "outlet", "sg_301", "inlet")
	plant.connect_equipment("p_301a", "outlet", "e_301", "cold_in",
		[plant.to_local(Vector3(28.4, 0.35, -5.9)), plant.to_local(Vector3(28.4, 0.35, -0.5))])
	plant.connect_equipment("sg_301", "steam", "e_301", "steam_in",
		[plant.to_local(Vector3(28.5, 0.35, 1.6)), plant.to_local(Vector3(30.1, 0.35, 0.3))])
	plant.connect_equipment("e_301", "cold_out", "r_301", "inlet_a",
		[plant.to_local(Vector3(33.0, 0.9, -1.6))])
	plant.connect_equipment("p_301b", "outlet", "r_301", "inlet_b",
		[plant.to_local(Vector3(31.6, 0.35, -3.5))])
	plant.connect_equipment("e_301", "duty", "r_301", "heat_duty",
		[plant.to_local(Vector3(31.9, 0.3, 0.4)), plant.to_local(Vector3(33.0, 0.3, -3.2))])
	plant.connect_equipment("r_301", "outlet", "cf_301", "inlet",
		[plant.to_local(Vector3(36.2, 0.35, -4.5))])
	plant.connect_equipment("r_301", "purity", "cf_301", "purity_in",
		[plant.to_local(Vector3(33.2, 0.3, -6.2)), plant.to_local(Vector3(36.6, 0.3, -6.2))])
	plant.connect_equipment("cf_301", "product", "pt_300", "inlet",
		[plant.to_local(Vector3(38.6, 0.35, -2.6))])
	plant.connect_equipment("cf_301", "waste", "du_301", "flow_in",
		[plant.to_local(Vector3(36.4, 0.35, -6.6))])
	plant.connect_equipment("pt_300", "level", "lt_300", "process")
	plant.connect_equipment("vl_302", "press", "pi_302", "process",
		[plant.to_local(Vector3(29.9, 0.35, -8.5))])
	plant.connect_equipment("vl_302", "drain_flow", "du_302", "flow_in",
		[plant.to_local(Vector3(31.7, 0.35, -8.15))])
	plant.connect_equipment("pt_300", "outlet", "vf_310", "inlet",
		[plant.to_local(Vector3(39.8, 0.35, -0.3))])

	# Power: 480 V drops from the plant feeder along the rack line.
	var trunk := [Vector3(-3.6, 0.3, -0.8), Vector3(22.6, 0.3, -0.8)]
	for load: Array in [
			["p_301a", Vector3(25.6, 0.3, -6.6)],
			["p_301b", Vector3(25.6, 0.3, -3.0)],
			["sg_301", Vector3(26.4, 0.3, 2.2)],
			["r_301", Vector3(33.2, 0.3, -2.6)],
			["cf_301", Vector3(36.8, 0.3, -3.4)],
			["vl_302", Vector3(29.6, 0.3, -7.2)],
			["vf_310", Vector3(42.9, 0.3, -2.2)]]:
		var path: Array[Vector3] = []
		for point: Vector3 in trunk:
			path.append(plant.to_local(point))
		path.append(plant.to_local(load[1] as Vector3))
		plant.connect_equipment("plant_mains", "power", str(load[0]), "power", path)

	# Commission the unit: burner and bowl on, both feed pumps in hand,
	# and a working charge in the reactor so the continuous train has
	# residence time — feeds run 4 L/s in, the bowl 4 L/s out, and the
	# charge heats toward reaction temperature while purity climbs.
	(plant.sim.get_component("sg_301") as SimSteamGen).is_on = true
	(plant.sim.get_component("cf_301") as SimCentrifuge).is_on = true
	(plant.sim.get_component("vl_302") as SimVacuumLock).is_on = true
	(plant.sim.get_component("vf_310") as SimVialFiller).is_on = true
	for pump_name: String in ["p_301a", "p_301b"]:
		(plant.sim.get_component(pump_name) as SimPump).mode = "hand"
	var reac := plant.sim.get_component("r_301") as SimReactor
	reac.volume_l = 2600.0
	reac.level.value = 2600.0
	reac.temp_c = 55.0  # held warm from the last shift; crosses 60 C in ~1 min

	_service_wire(plant, "sg_301", "e_301", Color(0.78, 0.79, 0.82), "ST-301")
	_service_wire(plant, "cf_301", "pt_300", Color(0.13, 0.55, 0.28), "P-301")
	_service_wire(plant, "cf_301", "du_301", Color(0.45, 0.36, 0.25), "WS-301")


static func _signage(plant: Plant) -> void:
	var signs := [
		["sign_u100", Vector3(11.6, 0.0, -2.4), 0.0, "UNIT 100\nLEVEL CONTROL"],
		["sign_mcc", Vector3(12.9, 0.0, 7.8), PI, "MCC-1\nAUTHORIZED ONLY"],
		["sign_rack", Vector3(9.0, 0.0, 2.8), 0.0, "PIPE RACK PR-1\nNO CLIMBING"],
		["sign_still", Vector3(4.9, 0.08, -4.8), 0.0, "STILL AREA\nPPE REQUIRED"],
		["sign_u300", Vector3(23.0, 0.0, -1.2), 0.0, "UNIT 300\nSYNTHESIS"],
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
