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
	_unit_400(plant)
	_signage(plant)


## ---- pipe rack PR-1: steel bents carrying services east ------------------

## Where a trunk feed leaves the PR-1 tray: beside its load, but never
## down the face of a rack column.
static func _drop_x(x: float) -> float:
	for col: float in [-3.0, 3.0, 9.0, 15.0, 21.0, 27.0, 33.0, 39.0]:
		if absf(x - col) < 0.7:
			return col + (0.7 if x >= col else -0.7)
	return x


static func _pipe_rack(plant: Plant) -> void:
	# Bents from the plant feeder east: the power trunk to Unit 300
	# rides the tray, so the rack starts where the feeder stands.
	for x: float in [-3.0, 3.0, 9.0, 15.0, 21.0]:
		plant.place_structure("s_column", "pr1_col_%d" % int(absf(x) + (100 if x < 0 else 0)),
			Vector3(x, 0.0, 1.5), 0.0)
	for tier: float in [3.0, 4.0]:
		for mid_x: float in [0.0, 6.0, 12.0, 18.0]:
			plant.place_structure("s_beam", "pr1_beam_%d_%d" % [int(tier), int(mid_x)],
				Vector3(mid_x, tier, 1.5), 0.0, 6.0)
	# Trays hang off the south face of the beams: on the beam line they
	# would run straight through the columns, and on the north face
	# they would take the head off anyone climbing the Unit 100 stairs.
	plant.place_run("run_tray", "pr1_tray",
		[plant.to_local(Vector3(-2.8, 3.35, 2.25)), plant.to_local(Vector3(20.8, 3.35, 2.25))])
	# A stub bent back to the feeder: the trunk risers climb beside its
	# column and the branch tray carries them onto the rack.
	plant.place_structure("s_column", "pr1_col_feed", Vector3(-3.0, 0.0, -0.8), 0.0)
	plant.place_structure("s_beam", "pr1_beam_3_feed", Vector3(-3.0, 3.0, 0.65), PI / 2.0, 2.9)
	plant.place_run("run_tray", "pr1_tray_feed",
		[plant.to_local(Vector3(-2.6, 3.35, -0.6)), plant.to_local(Vector3(-2.6, 3.35, 2.4))])
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
	# A flight of stairs rises 3.0 m to the top of its hull, so the deck
	# it serves sits on beams at 2.7: beam top 2.875, deck top 3.025,
	# and the player walks straight off the stairs onto it.
	plant.place_structure("s_beam", "u100_beam_s", Vector3(16, 2.7, -6.0), 0.0, 6.0)
	plant.place_structure("s_beam", "u100_beam_n", Vector3(16, 2.7, -1.8), 0.0, 6.0)
	plant.place_structure("s_beam", "u100_beam_w", Vector3(13, 2.7, -3.9), PI / 2.0, 4.2)
	plant.place_structure("s_beam", "u100_beam_e", Vector3(19, 2.7, -3.9), PI / 2.0, 4.2)
	plant.place_structure("s_deck", "u100_deck", Vector3(16, 2.875, -3.9), 0.0)
	plant.place_structure("s_catwalk", "u100_catwalk", Vector3(16, 2.875, -6.2), 0.0)
	# The stairs land on the north edge, the one side where no frame
	# beam crosses the flight: the east beam at x 19 would run straight
	# across a flight from the east. The landing sits over the north
	# edge beam, with the railing split around it.
	plant.place_structure("s_railing", "u100_rail_n1", Vector3(14.85, 3.025, -1.95), 0.0, 1.7)
	plant.place_structure("s_railing", "u100_rail_n2", Vector3(17.6, 3.025, -1.95), 0.0, 0.8)
	plant.place_structure("s_railing", "u100_rail_w", Vector3(14.05, 3.025, -3.9), PI / 2.0, 3.8)
	plant.place_structure("s_stairs", "u100_stairs", Vector3(16.5, 0.0, 0.2), 0.0)

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
	# LT-101 is on the tank's shell, ranged to its geometry by being there.
	plant.mount_instrument("gauge_level", "lt_101", {}, "ft_100", 0.3, 0.4, false)
	plant.place("controller", "lic_101", {"kp": 8.0, "ki": 1.5, "sp": 15.0},
		Vector3(13.2, 0.0, -5.8), 0.0, false)
	plant.connect_equipment("supply_101", "outlet", "lv_101", "inlet",
		[plant.to_local(Vector3(12.0, 0.3, -4.4))])
	plant.connect_equipment("lv_101", "outlet", "ft_100", "inlet",
		[plant.to_local(Vector3(15.4, 0.3, -3.5))])
	plant.connect_equipment("ft_100", "outlet", "du_101", "inlet")
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
	plant.mount_instrument("float_switch", "ls_201", {"low_l": 500.0, "high_l": 1100.0},
		"bt_200", 0.5, PI, false)
	plant.place("pump", "feed_pump", {"rated_lps": 3.0}, Vector3(15.4, 0.0, 8.4), 0.0, false)
	# FI-201 sits in the discharge line: the pump's whole flow runs
	# through its element.
	plant.place("gauge_flow", "fi_201", {}, Vector3(16.6, 0.0, 8.4), 0.0, false)
	plant.connect_equipment("supply_201", "outlet", "feed_pump", "inlet",
		[plant.to_local(Vector3(14.2, 0.3, 9.2))])
	plant.connect_equipment("bt_200", "outlet", "du_201", "inlet")
	plant.connect_equipment("ls_201", "contact", t + "1", "in",
		[plant.to_local(Vector3(17.3, 0.3, 7.2)), plant.to_local(Vector3(15.2, 0.3, 6.8))])
	plant.connect_equipment(t + "2", "out", "feed_pump", "run",
		[plant.to_local(Vector3(15.3, 0.3, 7.4))])
	plant.connect_equipment("feed_pump", "outlet", "fi_201", "inlet")
	plant.connect_equipment("fi_201", "outlet", "bt_200", "inlet",
		[plant.to_local(Vector3(17.2, 0.3, 8.6))])
	_service_wire(plant, "fi_201", "bt_200", Color(0.15, 0.35, 0.75), "PW-201")

	# Power: 480 V from the plant feeder, through the doorway, to the
	# cabinet PSU and the pump starter.
	plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), psu_name, "ac_in",
		[plant.to_local(Vector3(-3.6, 0.3, 0.2)), plant.to_local(Vector3(12.6, 0.3, 4.4)),
		plant.to_local(Vector3(12.6, 0.3, 6.2)), plant.to_local(Vector3(13.8, 0.3, 6.6))])
	plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), "feed_pump", "power",
		[plant.to_local(Vector3(-3.6, 0.3, 0.4)), plant.to_local(Vector3(12.5, 0.3, 4.5)),
		plant.to_local(Vector3(12.5, 0.3, 7.0)), plant.to_local(Vector3(15.0, 0.3, 8.0))])


## ---- Unit 300: synthesis train --------------------------------------------
## Two reagent headers and a recycled solvent header feed a jacketed
## reactor; a steam generator fires a heat exchanger that preheats the
## A-feed and delivers the reaction duty. The batch is cooled in a
## crystallizer under a real temperature loop until product drops out of
## solution, a centrifuge splits crystals from mother liquor, the cake
## is dried and lands in the product silo, and the liquor goes to a
## recovery still whose overheads return to the solvent tank and go
## round again. Every stream is metered, every motor is powered and
## audible, and the ring closes on real material.

static func _unit_300(plant: Plant) -> void:
	# Rack extension carrying the area cable tray east to the unit.
	for x: float in [27.0, 33.0, 39.0]:
		plant.place_structure("s_column", "pr1x_col_%d" % int(x), Vector3(x, 0.0, 1.5), 0.0)
	for tier: float in [3.0, 4.0]:
		for mid_x: float in [24.0, 30.0, 36.0]:
			plant.place_structure("s_beam", "pr1x_beam_%d_%d" % [int(tier), int(mid_x)],
				Vector3(mid_x, tier, 1.5), 0.0, 6.0)
	plant.place_run("run_tray", "pr1x_tray",
		[plant.to_local(Vector3(21.2, 3.35, 2.25)), plant.to_local(Vector3(38.8, 3.35, 2.25))])

	# ---- feed end -------------------------------------------------
	# A header is what it carries: this is where each species enters
	# the plant, and everything downstream finds out by being piped.
	plant.place("source", "supply_301a", {"species": "reagent_a"},
		Vector3(24.0, 0.0, -7.5), 0.0, false)
	plant.place("source", "supply_301b", {"species": "reagent_b"},
		Vector3(24.0, 0.0, -3.5), 0.0, false)
	plant.place("source", "supply_bfw", {"species": "water"},
		Vector3(24.0, 0.0, 2.5), 0.0, false)
	plant.place("source", "supply_solv", {"species": "solvent"},
		Vector3(24.0, 0.0, 6.5), 0.0, false)
	plant.place("pump", "p_301a", {"rated_lps": 0.6}, Vector3(26.6, 0.0, -7.5), 0.0, false)
	plant.place("pump", "p_301b", {"rated_lps": 0.6}, Vector3(26.6, 0.0, -3.5), 0.0, false)
	plant.place("pump", "p_solv", {"rated_lps": 0.3}, Vector3(26.6, 0.0, 6.5), 0.0, false)
	plant.place("steamgen", "sg_301", {"rated_kgps": 0.5}, Vector3(27.6, 0.0, 3.2), 0.0, false)
	plant.place("hx", "e_301", {"max_duty_kw": 1200.0}, Vector3(30.8, 0.0, -0.5), 0.0, false)

	# ---- reaction and crystallization ------------------------------
	plant.place("reactor", "r_301", {"capacity_l": 6000.0, "rate_lps": 1.2},
		Vector3(34.2, 0.0, -4.5), 0.0, false)
	plant.place("pump", "p_302", {"rated_lps": 1.8}, Vector3(36.4, 0.0, -4.5), 0.0, false)
	plant.place("crystallizer", "cx_303", {"capacity_l": 4000.0},
		Vector3(38.8, 0.0, -4.5), 0.0, false)
	# TIC-303 is direct acting: cooling has to rise when the batch is
	# ABOVE setpoint, so its gains are negative. Its output is
	# kilowatts removed, not valve percent.
	plant.place("controller", "tic_303",
		{"kp": -8.0, "ki": -0.25, "sp": 16.0, "out_max": 400.0},
		Vector3(38.8, 0.0, -7.2), 0.0, false)
	plant.place("centrifuge", "cf_301", {"rate_lps": 1.2}, Vector3(41.4, 0.0, -4.5), 0.0, false)
	# A hand valve on a wash line from the solvent header to the
	# centrifuge (2026-09-11): shut as commissioned, so nothing changes
	# until someone opens it at the handwheel — then clean solvent
	# displaces the mother liquor in the cake, the purity on the fill
	# line climbs, and the solvent inventory climbs with it.
	plant.place("block_valve", "hv_311", {"cv_lps": 2.0, "stroke_s": 3.0},
		Vector3(39.6, 0.0, -6.4), 0.0, false)
	# A nozzle takes one line (director, 2026-09-12): the header feeds a
	# splitter tee, P-SOLV off its near side leg, the wash off the far.
	plant.place("tee_split", "tee_solv", {}, Vector3(25.6, 0.0, 7.6), 0.0, false)
	plant.connect_equipment("supply_solv", "outlet", "tee_solv", "in")
	plant.connect_equipment("tee_solv", "c", "hv_311", "inlet",
		[plant.to_local(Vector3(25.6, 0.35, 8.4)), plant.to_local(Vector3(38.6, 0.35, 8.4)),
			plant.to_local(Vector3(38.6, 0.35, -6.4))])
	plant.connect_equipment("hv_311", "outlet", "cf_301", "wash",
		[plant.to_local(Vector3(41.24, 0.35, -6.4))])

	# ---- cake side: hopper, dryer, product silo --------------------
	plant.place("tank", "ht_304", {"height_m": 1.8, "diameter_m": 1.0},
		Vector3(43.8, 0.0, -4.5), 0.0, false)
	plant.place("dryer", "dr_305", {"rate_lps": 1.0}, Vector3(46.2, 0.0, -4.5), 0.0, false)
	# HIC-305 is a hand controller: an operator dialling in a duty.
	plant.place("controller", "hic_305", {"kp": 0.0, "ki": 0.0, "out_max": 800.0},
		Vector3(46.2, 0.0, -7.0), 0.0, false)
	plant.place("tank", "pt_300", {"height_m": 7.0, "diameter_m": 3.2},
		Vector3(49.2, 0.0, -1.0), 0.0, false)
	plant.mount_instrument("gauge_level", "lt_300", {}, "pt_300", 0.22, 0.53, false)
	plant.place("vialfill", "vf_310", {}, Vector3(52.6, 0.0, -2.6), 0.0, false)
	# A trend screen by the filler (2026-09-11): the purity on the fill
	# line beside the reactor's own purity and temperature, and the
	# wash that HV-311 lets through — the composition story of the
	# train on one page, replayed from the historian.
	plant.place("hmi_trend", "hmi_301", {"tags": ["aq_310.reading", "r_301.purity", "r_301.temp",
		"cf_301.wash_lps"], "window_s": 600.0}, Vector3(49.8, 0.0, 0.8), 0.0, false)
	# An analyser on the fill line: until this is wired, nobody can say
	# anything true about quality.
	plant.place("gauge_conc", "aq_310", {"species": "product"},
		Vector3(51.0, 0.0, -4.4), 0.0, false)

	# ---- liquor side: the recycle ----------------------------------
	plant.place("tank", "lt_306", {"height_m": 2.4, "diameter_m": 1.4},
		Vector3(41.4, 0.0, 4.2), 0.0, false)
	plant.place("still", "st_307", {"rate_lps": 1.5, "cut_c": 150.0},
		Vector3(44.6, 0.0, 4.2), 0.0, false)
	plant.place("controller", "hic_307", {"kp": 0.0, "ki": 0.0, "out_max": 3000.0},
		Vector3(46.8, 0.0, 6.6), 0.0, false)
	plant.place("tank", "sv_308", {"height_m": 2.6, "diameter_m": 1.6},
		Vector3(38.0, 0.0, 6.6), 0.0, false)
	# Temperature probes on the shells where temperature means something:
	# the solvent tank takes hot distillate off the still, the liquor
	# tank takes mother liquor off the centrifuge. Mounted after both
	# tanks exist: a mount on a vessel not yet placed is silently nothing.
	plant.mount_instrument("gauge_temp", "ti_308", {}, "sv_308", 0.45, 0.9, false)
	plant.mount_instrument("gauge_temp", "ti_306", {}, "lt_306", 0.45, 0.9, false)
	plant.place("pump", "p_309", {"rated_lps": 0.8}, Vector3(35.2, 0.0, 6.6), 0.0, false)
	plant.place("drain", "du_301", {"rate_lps": 2.0}, Vector3(35.2, 0.0, -7.8), 0.0, false)

	# The transfer lock: cycles vacuum-vent-drain on its own, its
	# pressure on a local gauge and its condensate to an open drain.
	plant.place("vaclock", "vl_302", {}, Vector3(30.6, 0.0, -8.0), 0.0, false)
	plant.place("gauge_press", "pi_302", {}, Vector3(28.8, 0.0, -8.6), 0.0, false)
	plant.place("drain", "du_302", {"rate_lps": 1.5}, Vector3(32.8, 0.0, -8.3), 0.0, false)

	# Nozzles where a real tank has them: fill low on the south face
	# (a 6 m riser to the top head would be an unsupported span).
	var pt_view := plant.views["pt_300"] as TankView
	pt_view.set_nozzle("inlet", 0.10, -1.9)
	# The outlet as low as a weld goes (2026-09-22): at the default tenth
	# of its seven metres it stood above the whole commissioned heel, and
	# the filler drew from nothing.
	pt_view.set_nozzle("outlet", 0.04, -0.7)

	# ---- process path ----------------------------------------------
	plant.connect_equipment("supply_301a", "outlet", "p_301a", "inlet")
	plant.connect_equipment("supply_301b", "outlet", "p_301b", "inlet")
	plant.connect_equipment("supply_bfw", "outlet", "sg_301", "inlet")
	plant.connect_equipment("tee_solv", "b", "p_solv", "inlet")
	plant.connect_equipment("p_301a", "outlet", "e_301", "cold_in",
		[plant.to_local(Vector3(28.4, 0.35, -5.9)), plant.to_local(Vector3(28.4, 0.35, -0.5))])
	plant.connect_equipment("sg_301", "steam", "e_301", "steam_in",
		[plant.to_local(Vector3(28.5, 0.35, 1.6)), plant.to_local(Vector3(30.1, 0.35, 0.3))])
	plant.place("tee_mix", "tee_301a", {}, Vector3(33.0, 0.0, -2.2), 0.0, false)
	plant.connect_equipment("e_301", "cold_out", "tee_301a", "a",
		[plant.to_local(Vector3(32.0, 0.9, -1.6)), plant.to_local(Vector3(32.0, 0.35, -2.2))])
	plant.connect_equipment("tee_301a", "out", "r_301", "inlet_a",
		[plant.to_local(Vector3(33.78, 0.35, -2.2)), plant.to_local(Vector3(33.78, 0.35, -3.15)),
			plant.to_local(Vector3(33.78, 2.9, -3.15))])
	plant.connect_equipment("p_301b", "outlet", "r_301", "inlet_b",
		[plant.to_local(Vector3(31.6, 0.35, -3.5))])
	plant.connect_equipment("e_301", "duty", "r_301", "heat_duty",
		[plant.to_local(Vector3(31.9, 0.3, 0.4)), plant.to_local(Vector3(33.0, 0.3, -3.2))])
	# Reactor -> crystallizer. Both vessels stand at grade, so the
	# reactor's outlet cannot climb to the crystallizer's top nozzle on
	# its own head: a transfer pump goes between them.
	plant.connect_equipment("r_301", "outlet", "p_302", "inlet",
		[plant.to_local(Vector3(35.4, 0.35, -4.5))])
	plant.connect_equipment("p_302", "outlet", "cx_303", "inlet",
		[plant.to_local(Vector3(37.6, 0.35, -4.5)), plant.to_local(Vector3(38.4, 0.9, -4.5))])
	# The crystallizer temperature loop: analyser in, cooling duty out.
	plant.connect_equipment("cx_303", "temp", "tic_303", "pv",
		[plant.to_local(Vector3(37.9, 0.3, -6.2))])
	plant.connect_equipment("tic_303", "out", "cx_303", "cool_duty",
		[plant.to_local(Vector3(39.9, 0.3, -6.4))])
	plant.connect_equipment("cx_303", "outlet", "cf_301", "inlet",
		[plant.to_local(Vector3(40.4, 0.35, -4.5))])
	# Cake side.
	plant.connect_equipment("cf_301", "product", "ht_304", "inlet",
		[plant.to_local(Vector3(42.6, 0.35, -4.5))])
	plant.connect_equipment("ht_304", "outlet", "dr_305", "inlet",
		[plant.to_local(Vector3(45.0, 0.35, -4.5))])
	plant.connect_equipment("hic_305", "out", "dr_305", "heat_duty",
		[plant.to_local(Vector3(46.5, 0.3, -6.0))])
	plant.connect_equipment("dr_305", "product", "pt_300", "inlet",
		[plant.to_local(Vector3(47.6, 0.35, -4.2)), plant.to_local(Vector3(47.6, 0.35, -2.9))])
	plant.connect_equipment("pt_300", "outlet", "vf_310", "inlet",
		[plant.to_local(Vector3(50.9, 0.35, -1.0)), plant.to_local(Vector3(50.9, 0.35, -2.6))])
	plant.connect_equipment("dr_305", "product", "aq_310", "process",
		[plant.to_local(Vector3(48.2, 0.3, -4.6))])
	# Liquor side and the recycle.
	plant.connect_equipment("cf_301", "waste", "lt_306", "inlet",
		[plant.to_local(Vector3(41.4, 0.35, -2.6)), plant.to_local(Vector3(41.4, 0.35, 2.9))])
	plant.connect_equipment("lt_306", "outlet", "st_307", "inlet",
		[plant.to_local(Vector3(43.0, 0.35, 4.2))])
	plant.connect_equipment("hic_307", "out", "st_307", "heat_duty",
		[plant.to_local(Vector3(46.0, 0.3, 5.6))])
	plant.place("tee_mix", "tee_308", {}, Vector3(38.0, 0.0, 4.6), -PI / 2.0, false)
	plant.connect_equipment("st_307", "distillate", "tee_308", "b",
		[plant.to_local(Vector3(45.6, 0.35, 6.9)), plant.to_local(Vector3(41.0, 0.35, 6.9)),
			plant.to_local(Vector3(41.0, 0.35, 4.6))])
	plant.connect_equipment("tee_308", "out", "sv_308", "inlet")
	plant.connect_equipment("st_307", "bottoms", "du_301", "inlet",
		[plant.to_local(Vector3(44.6, 0.35, 2.2)), plant.to_local(Vector3(35.2, 0.35, 2.2)),
			plant.to_local(Vector3(35.2, 0.35, -6.9))])
	plant.connect_equipment("p_solv", "outlet", "tee_308", "c",
		[plant.to_local(Vector3(29.0, 0.35, 6.5)), plant.to_local(Vector3(34.6, 0.35, 6.5)),
			plant.to_local(Vector3(34.6, 0.35, 4.6))])
	# The loop closes here: recovered solvent goes back to the reactor.
	plant.connect_equipment("sv_308", "outlet", "p_309", "inlet",
		[plant.to_local(Vector3(36.7, 0.35, 6.6))])
	plant.connect_equipment("p_309", "outlet", "tee_301a", "c",
		[plant.to_local(Vector3(34.2, 0.35, 6.0)), plant.to_local(Vector3(34.2, 0.35, -1.4)),
			plant.to_local(Vector3(33.0, 0.35, -1.4))])
	# The lock keeps to itself.
	plant.connect_equipment("vl_302", "press", "pi_302", "process",
		[plant.to_local(Vector3(29.9, 0.35, -8.5))])
	# Two lines land on one drain nozzle: a tee, which the network
	# solves without a component.
	plant.place("tee_mix", "tee_302d", {}, Vector3(34.6, 0.0, -8.3), PI, false)
	plant.connect_equipment("vl_302", "drain_flow", "tee_302d", "b",
		[plant.to_local(Vector3(31.7, 0.35, -7.2)), plant.to_local(Vector3(34.6, 0.35, -7.2))])
	plant.connect_equipment("e_301", "condensate", "tee_302d", "a",
		[plant.to_local(Vector3(30.8, 0.35, -3.0)), plant.to_local(Vector3(35.6, 0.35, -3.0)),
			plant.to_local(Vector3(35.6, 0.35, -8.3))])
	plant.connect_equipment("tee_302d", "out", "du_302", "inlet")

	# ---- power: 480 V from the plant feeder, up onto the PR-1 tray,
	# east along it, and down beside each load. Sixteen conduits in
	# one tray, the way a plant carries them; at grade they could not
	# pass between the drain and the tank (2026-09-12).
	var riser_top := Vector3(-2.6, 3.6, -0.8)
	# The tray hangs 0.75 m off the column line: at 2.1 the lanes toward
	# the columns were inside them and sixteen conduits did not fit the
	# lanes that were left; at 2.4 it was past the beams' reach and hung
	# in the air (2026-09-18).
	var tray_in := Vector3(-2.6, 3.6, 2.25)
	const TRAY_END := 38.6
	var loads: Array = [
			["p_301a", Vector3(25.6, 0.3, -6.6)],
			["p_301b", Vector3(25.6, 0.3, -3.0)],
			["p_solv", Vector3(25.6, 0.3, 5.8)],
			["sg_301", Vector3(26.4, 0.3, 2.2)],
			["r_301", Vector3(33.2, 0.3, -2.6)],
			["p_302", Vector3(35.8, 0.3, -3.6)],
			["cx_303", Vector3(37.9, 0.3, -3.0)],
			["cf_301", Vector3(40.6, 0.3, -3.4)],
			["dr_305", Vector3(45.4, 0.3, -3.6)],
			["st_307", Vector3(43.8, 0.3, 3.2)],
			["p_309", Vector3(34.4, 0.3, 5.8)],
			["vl_302", Vector3(29.6, 0.3, -7.2)],
			["vf_310", Vector3(53.9, 0.3, -3.6)]]
	for i in loads.size():
		var load: Array = loads[i]
		var at: Vector3 = load[1]
		# Sixteen risers side by side along the feeder's flank, two rows
		# of eight, laid deliberately: one shared riser spot left the
		# lanes to part sixteen conduits on one line (2026-09-18).
		@warning_ignore("integer_division")
		var riser := riser_top + Vector3(0.15 * (i / 8), 0.0, 0.12 * (i % 8))   # the second row away from the column
		# Off the tray sideways before dropping: straight down from the
		# tray centreline is straight through the beam under it.
		var drop_x := _drop_x(minf(at.x, TRAY_END))
		# Down beside the column, then to the load: the router routes round
		# whatever stands between (2026-09-18: a corner at the load's own z
		# was tried and put two drops through the crystallizer).
		var path: Array[Vector3] = [plant.to_local(riser), plant.to_local(tray_in),
			plant.to_local(Vector3(drop_x, 3.6, 2.25)), plant.to_local(Vector3(drop_x, 3.6, 2.65)),
			plant.to_local(at)]
		plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), str(load[0]), "power", path)

	# ---- commissioned state ----------------------------------------
	# Seeded deliberately so the loop is doing something within a
	# minute rather than an hour. Everything here is a real inventory
	# with a real composition; nothing is a display value.
	(plant.sim.get_component("sg_301") as SimSteamGen).is_on = true
	(plant.sim.get_component("cf_301") as SimCentrifuge).is_on = true
	(plant.sim.get_component("vl_302") as SimVacuumLock).is_on = true
	(plant.sim.get_component("vf_310") as SimVialFiller).is_on = true
	(plant.sim.get_component("dr_305") as SimDryer).is_on = true
	(plant.sim.get_component("st_307") as SimStill).is_on = true
	for pump_name: String in ["p_301a", "p_301b", "p_solv", "p_302", "p_309"]:
		(plant.sim.get_component(pump_name) as SimPump).mode = "hand"
	# The two hand controllers hold their duties.
	var hic5 := plant.sim.get_component("hic_305") as SimPID
	hic5.set_mode("manual")
	hic5.manual_out = 420.0
	var hic7 := plant.sim.get_component("hic_307") as SimPID
	hic7.set_mode("manual")
	hic7.manual_out = 2000.0

	# A warm working charge in the reactor: solvent with both reagents
	# in it, held over from the last shift and crossing 60 C shortly.
	var charge := SimStream.zero_amounts()
	charge[SimSpecies.SOLVENT] = 0.70
	charge[SimSpecies.REAGENT_A] = 0.15
	charge[SimSpecies.REAGENT_B] = 0.15
	(plant.sim.get_component("r_301") as SimReactor).charge(2600.0, charge, 55.0)
	# A hot, product-rich heel in the crystallizer, so it has residence
	# time to actually drop crystals from the first minute.
	var liquor := SimStream.zero_amounts()
	liquor[SimSpecies.SOLVENT] = 0.74
	liquor[SimSpecies.PRODUCT] = 0.21
	liquor[SimSpecies.IMPURITY] = 0.05
	(plant.sim.get_component("cx_303") as SimCrystallizer).charge(1100.0, liquor, 62.0)
	# Recovered solvent from the last campaign, so the recycle pump has
	# something to send while the still comes up.
	var solvent := SimStream.zero_amounts()
	solvent[SimSpecies.SOLVENT] = 0.97
	solvent[SimSpecies.IMPURITY] = 0.03
	(plant.sim.get_component("sv_308") as SimTank).charge(900.0, solvent, 30.0)
	# A heel of dried product in the silo so filling can run at once:
	# 3000 L stands 0.37 m, above the outlet at 0.28 m.
	var dry := SimStream.zero_amounts()
	dry[SimSpecies.PRODUCT] = 0.94
	dry[SimSpecies.IMPURITY] = 0.06
	(plant.sim.get_component("pt_300") as SimTank).charge(3000.0, dry, 24.0)

	_service_wire(plant, "sg_301", "e_301", Color(0.78, 0.79, 0.82), "ST-301")
	# Product-side lines are sanitary: tri-clamp fittings wherever a line
	# has to come apart to be cleaned (director, 2026-09-04).
	_service_wire(plant, "cf_301", "ht_304", Color(0.13, 0.55, 0.28), "CK-301", "clamp")
	_service_wire(plant, "cf_301", "lt_306", Color(0.45, 0.36, 0.25), "ML-301", "clamp")
	_service_wire(plant, "st_307", "tee_308", Color(0.20, 0.45, 0.75), "SR-307", "clamp")
	_service_wire(plant, "tee_308", "sv_308", Color(0.20, 0.45, 0.75), "SR-307", "clamp")
	_service_wire(plant, "p_309", "tee_301a", Color(0.20, 0.45, 0.75), "SR-309", "clamp")
	_service_wire(plant, "tee_301a", "r_301", Color(0.20, 0.45, 0.75), "SR-309", "clamp")
	_service_wire(plant, "st_307", "du_301", Color(0.45, 0.36, 0.25), "WS-307")
	_service_wire(plant, "cx_303", "cf_301", Color(0.60, 0.25, 0.60), "PR-303", "clamp")
	_service_wire(plant, "tee_solv", "hv_311", Color(0.20, 0.45, 0.75), "WL-311", "clamp")
	_service_wire(plant, "hv_311", "cf_301", Color(0.20, 0.45, 0.75), "WL-311", "clamp")
	_service_wire(plant, "ht_304", "dr_305", Color(0.60, 0.25, 0.60), "PR-304", "clamp")
	_service_wire(plant, "dr_305", "pt_300", Color(0.60, 0.25, 0.60), "PR-305", "clamp")
	_service_wire(plant, "pt_300", "vf_310", Color(0.60, 0.25, 0.60), "PR-310", "clamp")


## ---- Unit 400: the gravity rig ---------------------------------------------
## A detached two-storey tower south of the home pad that shows what
## pressure-driven flow does with elevation. A sump at grade, a tank on
## the mid deck, a tank on the top deck. P-401 lifts sump water seven
## metres to the top tank under a level switch; from there it runs back
## down by gravity alone, splitting at a tee between the mid tank and
## the sump, and the mid tank drains to the sump the same way. P-402,
## with five metres of head, is piped to the same top nozzle and
## dead-heads: motor turning, nothing moving. Nothing enters or leaves
## the rig; the same 1700 L go round.

static func _unit_400(plant: Plant) -> void:
	# ---- the tower: a 4 x 12 m platform with a 4 x 4 m top deck --------
	# A flight of stairs tops out 3.03 m above its base, so the decks
	# sit on beams at 2.7 and 5.7 (deck tops 3.025 and 6.025) and the
	# player walks straight off each flight onto the next level. The
	# platform runs three bays south so the second flight, 4.4 m plus
	# room to stand behind it, fits on it.
	for z: float in [9.0, 13.0, 17.0, 21.0]:
		for x: float in [-4.0, 0.0]:
			plant.place_structure("s_column", "u400_col_%d_%d" % [int(-x), int(z)],
				Vector3(x, 0.0, z), 0.0)
		plant.place_structure("s_beam", "u400_beam_27_x%d" % int(z), Vector3(-2, 2.7, z), 0.0, 4.0)
	for z: float in [11.0, 15.0, 19.0]:
		plant.place_structure("s_beam", "u400_beam_27_w%d" % int(z), Vector3(-4, 2.7, z), PI / 2.0, 4.0)
		plant.place_structure("s_beam", "u400_beam_27_e%d" % int(z), Vector3(0, 2.7, z), PI / 2.0, 4.0)
		plant.place_structure("s_deck", "u400_deck_mid_%d" % int(z), Vector3(-2, 2.875, z), 0.0)
	plant.place_structure("s_beam", "u400_beam_57_n", Vector3(-2, 5.7, 9), 0.0, 4.0)
	plant.place_structure("s_beam", "u400_beam_57_s", Vector3(-2, 5.7, 13), 0.0, 4.0)
	plant.place_structure("s_beam", "u400_beam_57_w", Vector3(-4, 5.7, 11), PI / 2.0, 4.0)
	plant.place_structure("s_beam", "u400_beam_57_e", Vector3(0, 5.7, 11), PI / 2.0, 4.0)
	plant.place_structure("s_deck", "u400_deck_top", Vector3(-2, 5.875, 11), 0.0)
	# Stairs: grade to the mid deck from the east, landing at z 11-12.5;
	# mid to top along the platform's west strip, climbing north onto
	# the top deck's south edge. Each top edge sits 0.1 m inside its
	# deck so the landing spans the edge beam.
	plant.place_structure("s_stairs", "u400_stairs_lo", Vector3(2.1, 0.0, 11.75), PI / 2.0)
	plant.place_structure("s_stairs", "u400_stairs_hi", Vector3(-3.2, 3.025, 15.1), 0.0)
	# Railings leave the two landings and the foot of the flight open.
	plant.place_structure("s_railing", "u400_rail_m_n", Vector3(-2, 3.025, 9.05), 0.0, 4.0)
	plant.place_structure("s_railing", "u400_rail_m_e1", Vector3(-0.05, 3.025, 10.0), PI / 2.0, 2.0)
	plant.place_structure("s_railing", "u400_rail_m_e2", Vector3(-0.05, 3.025, 16.75), PI / 2.0, 8.5)
	plant.place_structure("s_railing", "u400_rail_m_s", Vector3(-2, 3.025, 20.95), 0.0, 4.0)
	plant.place_structure("s_railing", "u400_rail_m_w1", Vector3(-3.95, 3.025, 10.95), PI / 2.0, 3.9)
	plant.place_structure("s_railing", "u400_rail_m_w2", Vector3(-3.95, 3.025, 19.15), PI / 2.0, 3.7)
	plant.place_structure("s_railing", "u400_rail_t_n", Vector3(-2, 6.025, 9.05), 0.0, 4.0)
	plant.place_structure("s_railing", "u400_rail_t_w", Vector3(-3.95, 6.025, 11.0), PI / 2.0, 4.0)
	plant.place_structure("s_railing", "u400_rail_t_e", Vector3(-0.05, 6.025, 11.0), PI / 2.0, 4.0)
	plant.place_structure("s_railing", "u400_rail_t_s", Vector3(-1.2, 6.025, 12.95), 0.0, 2.4)

	# ---- equipment ---------------------------------------------------
	# Three vessels at three heights. Placement height is elevation, so
	# the top tank's floor really is six metres above the sump's. The
	# mid tank keeps to the north-east corner, clear of both landings.
	# The batch is 300 L, moved at about 20 L/s so a whole cycle runs in
	# a minute and a half (director, 2026-09-04: ten times faster than
	# the first version). The sump works between 300 and 600 L, the two
	# tanks above between a 150 L heel and 450 L, so the lift ends when
	# the top tank is full at the same moment the sump reaches its heel,
	# and no pump ever draws on an uncovered nozzle.
	# Their nozzles are sized for the 20 L/s lines: the default vessel
	# nozzle would throttle a gravity drain to a fifth of that and
	# starve the lift pump's suction.
	plant.place("tank", "t_403", {"height_m": 1.6, "diameter_m": 1.0, "nozzle_cv_lps": 200.0},
		Vector3(-2.0, 0.0, 11.0), 0.0, false)
	plant.place("tank", "t_402", {"height_m": 1.6, "diameter_m": 0.9, "nozzle_cv_lps": 200.0},
		Vector3(-0.9, 3.025, 9.9), 0.0, false)
	plant.place("tank", "t_401", {"height_m": 1.6, "diameter_m": 0.9, "nozzle_cv_lps": 200.0},
		Vector3(-1.4, 6.025, 11.4), 0.0, false)
	# Two pumps that look alike and are not: P-401 is rated to lift
	# 35 m, P-402 only 5 m, and the top tank's inlet is 7.5 m up.
	# The pump skid, laid for the real line sizes (2026-09-22): the sump's
	# suction tee sends one leg each way -- north to P-401, west to
	# P-402, south to the sewer -- so no suction line meets another, and
	# the two discharges join north of the tower, P-401's straight up its
	# own line through FI-401, P-402's round the skid's west edge, before
	# one riser beside the north-west column climbs to the top tank. At
	# DN50 the old skid's lines passed between each other; at DN150 and
	# DN80 they ran into each other and the starter's cables.
	plant.place("pump", "p_401", {"rated_lps": 20.0, "head_m": 35.0}, Vector3(-3.4, 0.0, 9.9), PI / 2.0, false)
	plant.place("pump", "p_402", {"rated_lps": 20.0, "head_m": 5.0}, Vector3(-5.0, 0.0, 11.0), PI, false)
	plant.place("relay", "k_401", {}, Vector3(-2.2, 0.0, 9.5), 0.0, false)
	# FI-401 sits in P-401's discharge line: an inline element the whole
	# flow runs through, not a tapping, sized to its line (40 kPa at
	# 20 L/s; the default element would cost more head than the lift).
	plant.place("gauge_flow", "fi_401", {"meter_k": 100.0}, Vector3(-3.4, 0.0, 8.8), PI / 2.0, false)
	# A block valve on every transfer: XV-401 on the top deck at the top
	# tank's outlet, XV-402 at grade where the mid tank's drain comes
	# down the north-east column, XV-403 and the sewer connection under
	# the platform west of the sump, XV-404 on the makeup line. The
	# sewer line has only the sump's own depth to drive it, so its
	# valve and connection are twice the size of the others.
	plant.place("block_valve", "xv_401", {"cv_lps": 150.0, "stroke_s": 2.0, "dn": 100},
		Vector3(-1.4, 6.025, 9.7), PI / 2.0, false)
	plant.place("block_valve", "xv_402", {"cv_lps": 150.0, "stroke_s": 2.0, "dn": 100},
		Vector3(1.3, 0.0, 8.55), 0.0, false)
	plant.place("block_valve", "xv_403", {"cv_lps": 200.0, "stroke_s": 2.0, "dn": 100},
		Vector3(-3.4, 0.0, 12.5), -PI / 2.0, false)
	plant.place("drain", "du_401", {"rate_lps": 200.0}, Vector3(-3.4, 0.0, 14.3), PI / 2.0, false)
	# Makeup water: a header through XV-404 into the sump. This is where
	# the rig's water comes from; it starts empty and fills from here.
	plant.place("source", "supply_401", {"species": "water"}, Vector3(3.6, 0.0, 15.0), PI, false)
	plant.place("block_valve", "xv_404", {"cv_lps": 20.0, "stroke_s": 2.0},
		Vector3(1.6, 0.0, 15.0), PI, false)
	# Level switches are single-point, one per trip level, each mounted
	# at the height it trips at: the sequence asks "is it above this
	# line" and nothing else, so no step can start with its exit switch
	# already in the state it is waiting for. (A two-point switch reads
	# "below low" until the level has been to high, which is the wrong
	# answer for a tank that only ever got half way.) An indicator on
	# every tank for the visitor.
	plant.mount_instrument("float_switch", "lsl_401", {"low_l": 150.0, "high_l": 150.0},
		"t_401", 0.15, 0.45, false)
	plant.mount_instrument("float_switch", "lsh_401", {"low_l": 450.0, "high_l": 450.0},
		"t_401", 0.44, 0.0, false)
	plant.mount_instrument("float_switch", "lsl_402", {"low_l": 150.0, "high_l": 150.0},
		"t_402", 0.15, 0.0, false)
	plant.mount_instrument("float_switch", "lsl_403", {"low_l": 300.0, "high_l": 300.0},
		"t_403", 0.24, 0.45, false)
	plant.mount_instrument("float_switch", "lsh_403", {"low_l": 600.0, "high_l": 600.0},
		"t_403", 0.48, 0.0, false)
	plant.mount_instrument("gauge_level", "li_401", {}, "t_401", 0.4, PI / 2.0, false)
	plant.mount_instrument("gauge_level", "li_402", {}, "t_402", 0.35, PI / 2.0, false)
	plant.mount_instrument("gauge_level", "li_403", {}, "t_403", 0.5, -PI / 2.0, false)

	# Nozzles face their runs, and every outlet sits low: a nozzle is
	# where the kernel's nozzle stands (2026-09-22), so a tank drains
	# only to its outlet, and an outlet at 16 % of the height left
	# 163 L in a 1,018 L tank whose step exits at the 150 L heel
	# switch — the sequence stood at DRAIN T-401 for the rest of the
	# soak. At 6 % the heel is 61 L, under every switch.
	var sump := plant.views["t_403"] as TankView
	sump.set_nozzle("outlet", 0.06, PI)
	sump.set_nozzle("inlet", 0.92, PI / 2.0)
	var mid := plant.views["t_402"] as TankView
	mid.set_nozzle("inlet", 0.92, 0.0)
	mid.set_nozzle("outlet", 0.06, -PI / 2.0)
	var top := plant.views["t_401"] as TankView
	top.set_nozzle("inlet", 0.92, PI)
	top.set_nozzle("outlet", 0.06, -PI / 2.0)

	# ---- process path ------------------------------------------------
	# Both pumps and the sewer line draw off the sump: a tee at its outlet
	# nozzle, a leg each way. Each line is laid at its size from the first
	# (Plant.next_line_size), so the route it takes is the route a line
	# that size needs.
	plant.place("tee_split", "tee_403a", {"dn": 150}, Vector3(-3.4, 0.0, 11.0), PI, false)
	_sized(plant, 150, "t_403", "outlet", "tee_403a", "in")
	_sized(plant, 80, "tee_403a", "c", "p_401", "inlet")
	_sized(plant, 80, "tee_403a", "a", "p_402", "inlet")
	_sized(plant, 100, "tee_403a", "b", "xv_403", "inlet")
	_sized(plant, 100, "xv_403", "outlet", "du_401", "inlet")
	# P-401 straight north through the meter to the discharge tee; P-402
	# west, then north along the skid's edge into the tee's side; one
	# riser beside the north-west column to the top tank's inlet, over
	# the top deck.
	plant.place("tee_mix", "tee_401m", {"dn": 80}, Vector3(-3.4, 0.0, 7.7), PI / 2.0, false)
	_sized(plant, 80, "p_401", "outlet", "fi_401", "inlet")
	_sized(plant, 80, "fi_401", "outlet", "tee_401m", "a")
	_sized(plant, 80, "p_402", "outlet", "tee_401m", "b",
		_local(plant, [Vector3(-5.8, 0.42, 11.0), Vector3(-5.8, 0.42, 7.7)]))
	# The riser stands off the north-west column's corner, within a
	# bracket's reach of it; the low leg to it climbs first, so it passes
	# over P-402's discharge rather than through it.
	_sized(plant, 80, "tee_401m", "out", "t_401", "inlet",
		_local(plant, [Vector3(-3.4, 0.35, 7.1), Vector3(-3.4, 1.6, 7.1), Vector3(-4.4, 1.6, 7.1),
			Vector3(-4.4, 1.6, 8.6), Vector3(-4.4, 7.35, 8.6), Vector3(-3.4, 7.35, 8.6),
			Vector3(-3.4, 7.35, 11.4)]))
	# Gravity, one transfer at a time. The top tank drains north through
	# XV-401, over the deck edge and down the north-east column to the
	# mid tank's inlet.
	plant.connect_equipment("t_401", "outlet", "xv_401", "inlet")
	plant.connect_equipment("xv_401", "outlet", "t_402", "inlet",
		_local(plant, [Vector3(-1.4, 6.2, 8.9), Vector3(0.45, 6.2, 8.9), Vector3(0.45, 5.4, 8.9),
			Vector3(0.45, 5.4, 9.9)]))
	# The mid tank drains north under the railing, down the same column
	# to XV-402 at grade, then in under the platform to the sump's inlet.
	plant.connect_equipment("t_402", "outlet", "xv_402", "inlet",
		_local(plant, [Vector3(-0.9, 3.28, 8.55), Vector3(0.4, 3.28, 8.55), Vector3(0.4, 0.35, 8.55)]))
	plant.place("tee_mix", "tee_403m", {"dn": 150}, Vector3(-2.0, 0.0, 13.0), PI / 2.0, false)
	plant.connect_equipment("xv_402", "outlet", "tee_403m", "a",
		_local(plant, [Vector3(2.3, 0.35, 8.55), Vector3(2.3, 0.35, 14.2), Vector3(-2.0, 0.35, 14.2)]))
	plant.connect_equipment("tee_403m", "out", "t_403", "inlet")
	# Makeup: header, valve, and a line in under the platform to the
	# sump's inlet, which is a tee with the mid tank's drain.
	plant.connect_equipment("supply_401", "outlet", "xv_404", "inlet")
	plant.connect_equipment("xv_404", "outlet", "tee_403m", "c",
		_local(plant, [Vector3(-0.2, 0.35, 15.0), Vector3(-0.2, 0.35, 13.0)]))
	# Line sizing, for about 20 L/s everywhere so each stage moves its
	# 300 L in fifteen seconds or so. A line's resistance is its length
	# at its size (director, 2026-09-22), so sizing is choosing the bore:
	# the sump's outlet and inlet the fattest, DN150, since the sewer and
	# the gravity drains have only a metre or two of head behind them;
	# the gravity drains and the sewer line DN100; the pump lines DN80,
	# so the lift lands near P-401's rating; the makeup DN50, which
	# throttles the fill to take about as long as the lift. (These were
	# hand-set resistances until the rule, each a line size in disguise.)
	for line: Array in [
			["tee_403m", "out", "t_403", "inlet", 150],
			["t_401", "outlet", "xv_401", "inlet", 100],
			["xv_401", "outlet", "t_402", "inlet", 100],
			["t_402", "outlet", "xv_402", "inlet", 100],
			["xv_402", "outlet", "tee_403m", "a", 100]]:
		var view := plant.line_between(str(line[0]), str(line[1]), str(line[2]), str(line[3]))
		if view == null:
			push_error("unit 400: no line %s.%s -> %s.%s" % [line[0], line[1], line[2], line[3]])
		else:
			plant.set_run_size(view, int(line[4]))

	# ---- the sequence: a PLC in its own cabinet ----------------------
	# The cabinet stands north of the platform with its door to the
	# rig. Five level switches in on one strip, five outputs out on
	# another: the lift pump's starter and the four block valves. Five
	# steps, each sealed in until the next takes over, each advanced by
	# a switch:
	#   1 FILL        XV-404 open until LSH-403 (sump 600 L)
	#   2 LIFT        P-401 until LSH-401 (top tank 450 L), or LSL-403
	#                 (sump at its 300 L heel) first, which protects the pump
	#   3 DRAIN T-401 XV-401 open until LSL-401 (top tank at its heel)
	#   4 DRAIN T-402 XV-402 open until LSL-402 (mid tank at its heel)
	#   5 SEWER       XV-403 open until LSL-403 (sump at its heel); repeat
	# The first cycle primes the rig: the tanks above start empty, so the
	# lift ends on the sump's heel with the top tank short of full and
	# the drains move less than a batch. From the second cycle the heels
	# are in place and every step moves its 300 L.
	var cab := "u400_cab"
	plant.place_cabinet(cab, Vector3(4.6, 0.0, 8.2), PI)
	plant.cabinet_add_module(cab, "psu", 0, 0)
	plant.cabinet_add_module(cab, "plc", 0, 4)
	plant.cabinet_add_module(cab, "card_di", 0, 8)
	plant.cabinet_add_module(cab, "card_do", 0, 10)
	plant.cabinet_add_module(cab, "tb8d", 1, 0)
	plant.cabinet_add_module(cab, "tb8d", 2, 0)
	var plc_name := plant.cabinet_plc(cab)
	var plc := plant.sim.get_component(plc_name) as SimPLC
	var psu_name := ""
	for record_name in plant.cabinet_all_records(cab):
		if plant.equip_types.get(record_name) == "psu":
			psu_name = record_name
	var di := "%s_m5_t" % cab   # inputs strip
	var do := "%s_m6_t" % cab   # outputs strip
	plant.connect_equipment(psu_name, "dc_out", plc_name, "power", [], false)
	for i in 7:
		plant.connect_equipment(di + str(i + 1), "out", plc_name, "di_%d" % i, [], false)
		plant.connect_equipment(plc_name, "do_%d" % i, do + str(i + 1), "in", [], false)
	# di_0 LSL-401, di_1 LSH-401, di_2 LSL-402, di_3 LSL-403, di_4
	# LSH-403; a contact is closed while the level is at or below its
	# line. di_5 START, di_6 STOP (normally closed) from the local
	# control station. do_0 K-401, do_1..do_4 XV-401..XV-404, do_5 the
	# RUNNING lamp, do_6 the STOPPED lamp.
	#
	# m_5 is the run latch: START sets it, STOP drops it, and it holds
	# itself through STOP's made contact in between. The step bits keep
	# their place while stopped; only the outputs are gated, so a
	# stopped sequence closes its valves, stops its pump, and resumes
	# where it was on START.
	plc.set_program([
		{"coil": "m_5", "logic": [
			[{"ref": "di_5"}, {"ref": "di_6"}],
			[{"ref": "m_5"}, {"ref": "di_6"}]]},
		{"coil": "m_0", "logic": [
			[{"ref": "m_4"}, {"ref": "di_3"}],
			[{"ref": "m_0"}, {"ref": "m_1", "nc": true}],
			[{"ref": "m_0", "nc": true}, {"ref": "m_1", "nc": true}, {"ref": "m_2", "nc": true},
				{"ref": "m_3", "nc": true}, {"ref": "m_4", "nc": true}]]},
		{"coil": "m_1", "logic": [
			[{"ref": "m_0"}, {"ref": "di_4", "nc": true}],
			[{"ref": "m_1"}, {"ref": "m_2", "nc": true}]]},
		{"coil": "m_2", "logic": [
			[{"ref": "m_1"}, {"ref": "di_1", "nc": true}],
			[{"ref": "m_1"}, {"ref": "di_3"}],
			[{"ref": "m_2"}, {"ref": "m_3", "nc": true}]]},
		{"coil": "m_3", "logic": [
			[{"ref": "m_2"}, {"ref": "di_0"}],
			[{"ref": "m_3"}, {"ref": "m_4", "nc": true}]]},
		{"coil": "m_4", "logic": [
			[{"ref": "m_3"}, {"ref": "di_2"}],
			[{"ref": "m_4"}, {"ref": "m_0", "nc": true}]]},
		{"coil": "do_0", "logic": [[{"ref": "m_1"}, {"ref": "m_5"}]]},
		{"coil": "do_1", "logic": [[{"ref": "m_2"}, {"ref": "m_5"}]]},
		{"coil": "do_2", "logic": [[{"ref": "m_3"}, {"ref": "m_5"}]]},
		{"coil": "do_3", "logic": [[{"ref": "m_4"}, {"ref": "m_5"}]]},
		{"coil": "do_4", "logic": [[{"ref": "m_0"}, {"ref": "m_5"}]]},
		{"coil": "do_5", "logic": [[{"ref": "m_5"}]]},
		{"coil": "do_6", "logic": [[{"ref": "m_5", "nc": true}]]},
	])
	# The local control station beside the HMI-400 screen, facing the
	# walkway like the screen does (the first version stood behind the
	# sequence signs facing a sign's back, and the director could not
	# find it). START and STOP to the input strip, RUNNING and STOPPED
	# from the output strip, all along the ground to the cabinet.
	plant.place_control_station("lcs_401", Vector3(1.9, 0.0, 9.0), 0.0, Plant.default_station_devices())
	plant.connect_equipment("lcs_401_start", "contact", di + "6", "in",
		_local(plant, [Vector3(2.4, 0.18, 9.05), Vector3(5.9, 0.18, 9.05), Vector3(5.9, 0.18, 8.5)]))
	plant.connect_equipment("lcs_401_stop", "contact", di + "7", "in",
		_local(plant, [Vector3(2.4, 0.18, 9.15), Vector3(6.0, 0.18, 9.15), Vector3(6.0, 0.18, 8.55)]))
	plant.connect_equipment(do + "6", "out", "lcs_401_running", "lamp",
		_local(plant, [Vector3(3.7, 0.2, 8.75), Vector3(2.5, 0.2, 8.75), Vector3(2.5, 0.2, 8.95)]))
	plant.connect_equipment(do + "7", "out", "lcs_401_stopped", "lamp",
		_local(plant, [Vector3(3.7, 0.12, 8.6), Vector3(2.6, 0.12, 8.6), Vector3(2.6, 0.12, 9.0)]))
	# Commissioned running: START pressed once at handover, so the rig
	# is cycling when the director arrives. STOP on the station holds
	# it wherever it is; START resumes.
	(plant.sim.get_component("lcs_401_start") as SimPushbutton).press()

	# ---- field wiring: two junction boxes, two multicores --------------
	# The way a real field is wired (director, 2026-09-04): the switches
	# and the east-side valves land on JB-401 beside the north-east
	# column, the starter and the sewer valve on JB-402 beside the
	# north-west column, and each box sends one multicore to the
	# cabinet instead of ten conduits home. Every circuit is still its
	# own kernel wire, one scan late at each terminal.
	plant.place_junction_box("jb_401", Vector3(0.6, 0.0, 9.3), PI / 2.0, 8)
	plant.place_junction_box("jb_402", Vector3(-1.6, 0.0, 8.3), -PI / 2.0, 4)
	# Switch conduits leave each tank's east face, drop through the deck
	# beside its edge beam, and come down beside the north-east column
	# to the box, north of the landing.
	plant.connect_equipment("lsl_401", "contact", "jb_401_t1", "in",
		_local(plant, [Vector3(-0.6, 6.4, 11.6), Vector3(-0.6, 5.3, 11.6), Vector3(-0.6, 5.3, 10.5),
			Vector3(0.45, 5.3, 10.5), Vector3(0.45, 1.7, 10.5)]))
	plant.connect_equipment("lsh_401", "contact", "jb_401_t2", "in",
		_local(plant, [Vector3(-0.6, 7.1, 11.4), Vector3(-0.6, 5.3, 11.4), Vector3(-0.6, 5.3, 10.8),
			Vector3(0.45, 5.3, 10.8), Vector3(0.45, 1.8, 10.8)]))
	plant.connect_equipment("lsl_402", "contact", "jb_401_t3", "in",
		_local(plant, [Vector3(-0.2, 3.35, 9.9), Vector3(-0.2, 2.3, 9.9), Vector3(0.45, 2.3, 9.9),
			Vector3(0.45, 1.6, 9.9)]))
	plant.connect_equipment("lsl_403", "contact", "jb_401_t4", "in",
		_local(plant, [Vector3(-0.8, 0.12, 11.3), Vector3(0.6, 0.12, 11.3), Vector3(0.6, 0.12, 9.95)]))
	plant.connect_equipment("lsh_403", "contact", "jb_401_t5", "in",
		_local(plant, [Vector3(-0.8, 0.12, 11.0), Vector3(0.75, 0.12, 11.0), Vector3(0.75, 0.12, 9.95)]))
	# Outputs leave the boxes to the valves and the starter.
	plant.connect_equipment("jb_401_t6", "out", "xv_401", "open",
		_local(plant, [Vector3(0.45, 1.9, 9.5), Vector3(0.45, 5.3, 9.5), Vector3(-0.6, 5.3, 9.5),
			Vector3(-0.6, 5.3, 9.7), Vector3(-0.6, 6.75, 9.7)]))
	plant.connect_equipment("jb_401_t7", "out", "xv_402", "open",
		_local(plant, [Vector3(1.3, 0.2, 9.3)]))
	plant.connect_equipment("jb_401_t8", "out", "xv_404", "open",
		_local(plant, [Vector3(1.0, 0.2, 9.0), Vector3(1.0, 0.2, 14.2), Vector3(1.6, 0.2, 14.2)]))
	plant.connect_equipment("jb_402_t1", "out", "k_401", "coil")
	plant.connect_equipment("k_401", "contact", "p_401", "run")
	# The sewer valve's command runs down the tower's interior above the
	# sump's suction line and comes round the valve's west side.
	plant.connect_equipment("jb_402_t2", "out", "xv_403", "open",
		_local(plant, [Vector3(-2.9, 1.1, 8.6), Vector3(-2.9, 1.1, 12.0), Vector3(-4.45, 1.1, 12.0),
			Vector3(-4.45, 0.72, 12.5)]))
	# The multicores: MC-401 carries five switches to the input strip
	# and three valve commands back; MC-402 carries the starter and the
	# sewer valve. One cable each, along the ground to the cabinet.
	var mc401: Array = []
	for i in 5:
		mc401.append(["jb_401_t%d" % (i + 1), "out", di + str(i + 1), "in"])
	mc401.append([do + "2", "out", "jb_401_t6", "in"])
	mc401.append([do + "3", "out", "jb_401_t7", "in"])
	mc401.append([do + "5", "out", "jb_401_t8", "in"])
	plant.connect_multicore("MC-401", mc401,
		_local(plant, [Vector3(0.9, 0.3, 8.9), Vector3(5.8, 0.3, 8.9), Vector3(5.8, 0.3, 8.2)]))
	plant.connect_multicore("MC-402",
		[[do + "1", "out", "jb_402_t1", "in"], [do + "4", "out", "jb_402_t2", "in"]],
		_local(plant, [Vector3(3.5, 0.3, 8.75), Vector3(-1.2, 0.3, 8.75)]))

	# ---- power: 480 V from the plant feeder, low along the ground ----
	# Straight down off the way first, under the Unit 300 stub legs.
	var way_drop := Vector3(-3.3, 0.3, -1.12)
	plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), "p_401", "power",
		_local(plant, [way_drop, Vector3(-3.4, 0.3, 0.6), Vector3(-3.4, 0.3, 5.6),
			Vector3(-4.4, 0.14, 6.0), Vector3(-4.4, 0.14, 10.05)]))
	plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), "p_402", "power",
		_local(plant, [way_drop, Vector3(-3.2, 0.3, 0.6), Vector3(-3.2, 0.3, 5.4),
			Vector3(-3.2, 0.1, 5.8), Vector3(-6.6, 0.1, 5.8), Vector3(-6.6, 0.1, 11.8),
			Vector3(-4.85, 0.1, 11.8)]))
	plant.connect_equipment("plant_mains", plant.free_way("plant_mains"), psu_name, "ac_in",
		_local(plant, [way_drop, Vector3(-3.0, 0.3, 0.6), Vector3(-3.0, 0.3, 5.3), Vector3(5.6, 0.3, 5.3),
			Vector3(5.6, 0.3, 7.6)]))

	# ---- commissioned state ------------------------------------------
	# P-401 is in Auto and belongs to the sequence; P-402 is left in
	# Manual On so the lesson is always running. Nothing is charged:
	# the sump fills from the header when the plant starts.
	(plant.sim.get_component("p_402") as SimPump).mode = "hand"

	_service_wire(plant, "fi_401", "tee_401m", Color(0.13, 0.55, 0.28), "PW-401")
	_service_wire(plant, "tee_401m", "t_401", Color(0.13, 0.55, 0.28), "PW-401")
	_service_wire(plant, "p_402", "tee_401m", Color(0.13, 0.55, 0.28), "PW-402")
	_service_wire(plant, "t_401", "xv_401", Color(0.20, 0.45, 0.75), "GR-401")
	_service_wire(plant, "xv_401", "t_402", Color(0.20, 0.45, 0.75), "GR-401")
	_service_wire(plant, "t_402", "xv_402", Color(0.20, 0.45, 0.75), "GR-402")
	_service_wire(plant, "xv_402", "tee_403m", Color(0.20, 0.45, 0.75), "GR-402")
	_service_wire(plant, "tee_403m", "t_403", Color(0.20, 0.45, 0.75), "GR-402")
	_service_wire(plant, "t_403", "tee_403a", Color(0.45, 0.30, 0.15), "SW-403")
	_service_wire(plant, "tee_403a", "xv_403", Color(0.45, 0.30, 0.15), "SW-403")
	_service_wire(plant, "xv_403", "du_401", Color(0.45, 0.30, 0.15), "SW-403")
	_service_wire(plant, "xv_404", "tee_403m", Color(0.13, 0.55, 0.28), "MU-404")

	# The operator screen: a simplified P&ID of the unit with every
	# reading live from the records, facing the rig beside the cabinet.
	var hmi := HmiScreenView.new()
	hmi.name = "hmi_400"
	plant.add_child(hmi)
	hmi.position = plant.to_local(Vector3(2.9, 1.68, 8.4))
	var overview := UnitHmiPanel.new()
	overview.setup(plant, cab)
	hmi.setup(overview, "HMI-400", Vector2i(1024, 640), 1.2,
		"HMI-400 — Unit 400 overview\nLevels, switches, valves and pumps read live from the records; the step from the PLC; the trend from the historian.")

	plant.place_structure("s_sign", "sign_u400", Vector3(1.5, 0.0, 7.6), 0.0)
	plant.set_sign_text("sign_u400", "UNIT 400\nSTAGED TRANSFER")
	# A sign board takes four lines of about eight characters, so the
	# sequence reads across three boards.
	plant.place_structure("s_sign", "sign_u400_seq1", Vector3(6.2, 0.0, 8.2), 0.0)
	plant.set_sign_text("sign_u400_seq1", "SEQUENCE\n1 FILL\n2 LIFT")
	plant.place_structure("s_sign", "sign_u400_seq2", Vector3(7.2, 0.0, 8.2), 0.0)
	plant.set_sign_text("sign_u400_seq2", "3 DRAIN\nTOP-MID\n4 DRAIN\nMID-SUMP")
	plant.place_structure("s_sign", "sign_u400_seq3", Vector3(8.2, 0.0, 8.2), 0.0)
	plant.set_sign_text("sign_u400_seq3", "5 SUMP\nTO SEWER\nREPEAT")
	plant.place_structure("s_sign", "sign_p402", Vector3(-6.2, 0.0, 12.3), 0.0)
	plant.set_sign_text("sign_p402", "P-402: 5 m HEAD\nLIFT TO T-401 IS 7.5 m\nDEAD-HEADED")

## A line laid at its size from the first, so its route is chosen for
## the bore it has.
static func _sized(plant: Plant, dn: int, a: String, a_port: String, b: String, b_port: String,
		waypoints: Array = []) -> void:
	plant.next_line_size(dn)
	var why := plant.connect_equipment(a, a_port, b, b_port, waypoints)
	if why != "":
		push_error("%s.%s -> %s.%s: %s" % [a, a_port, b, b_port, why])


## World-space waypoints to plant-local, for the routed runs.
static func _local(plant: Plant, points: Array) -> Array:
	var out: Array = []
	for point: Vector3 in points:
		out.append(plant.to_local(point))
	return out


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

static func _service_wire(plant: Plant, a: String, b: String, color: Color, label: String,
		fitting: String = "") -> void:
	for visual: Dictionary in plant._wire_visuals:
		if str(visual["a"]) == a and str(visual["b"]) == b and visual["node"] != null:
			plant.set_run_service(visual["node"] as PipeView, color, label, fitting)
			return


static func _service_run(plant: Plant, run_name: String, color: Color, label: String) -> void:
	if plant.runs.has(run_name):
		plant.set_run_service((plant.runs[run_name] as Dictionary)["node"] as PipeView,
			color, label)
