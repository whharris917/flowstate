class_name Plant
extends Node3D
## Owns the sim graph and the fixed-rate tick; child views only render.
## All equipment — the commissioned starting loop and everything the
## player places — goes through PlantFactory, so save/load can rebuild
## the entire graph from a file.

const SIM_DT := 0.05  # 20 Hz, decoupled from frame rate
const SAVE_VERSION := 5  # v5: pressure kernel, no draw wires; v3/v4 saves still load

var save_path: String = "user://save.json"
var build_suite: bool = true   # the hall builds the aseptic annex; the sandbox doesn't
var config_panel: RunConfigPanel = null   # injected by the world after _ready
var cabinet_editor: CabinetEditor = null  # injected by the world after _ready
var ladder_panel: LadderPanel = null      # injected by the world after _ready
var tank_panel: TankConfigPanel = null    # injected by the world after _ready

var sim: Simulation
var historian: SimHistorian
var hmi_view: HmiView
var balance_panel: PlantBalancePanel

# Convenience refs to the commissioned loop (refreshed after load).
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump

var views: Dictionary = {}         # record name -> Node3D view
var equip_types: Dictionary = {}   # record name -> type_id
var protected: Dictionary = {}     # record name -> true (not deletable)
var cabinets: Dictionary = {}      # name -> {node, plc, terminals}
var member_of: Dictionary = {}     # record name -> cabinet name
var mounted: Dictionary = {}       # instrument name -> {host, frac, angle}
var structures: Dictionary = {}    # name -> {type, node}
var runs: Dictionary = {}          # name -> {kind, node, points (plant-local)}
var _wire_visuals: Array[Dictionary] = []   # {node, a, b}

var _accumulator: float = 0.0
# One-off kernel cost report, taken over the first few hundred scans.
var _cost_ticks: int = 0
var _cost_total_us: int = 0
var _cost_solve_ms: float = 0.0
var _cost_newton_ms: float = 0.0
var _cost_iterations: int = 0
# Support re-validation runs a few physics frames after geometry
# changes, once new/freed colliders have actually reached the space.
var _revalidate_in: int = 0
var _support_exercise_phase: int = 0
var _support_exercise_wait: int = 0


func _ready() -> void:
	_new_graph()
	_self_check()
	_build_initial_plant()
	_build_hmi()
	if DisplayServer.get_name() == "headless":
		_exercise_build_api()
		_support_exercise_phase = 1
		_support_exercise_wait = 4


## Headless smoke runs can't press B/C/X, so exercise the build API
## directly: place, connect, mis-wire, remove, save/load round-trip.
func _exercise_build_api() -> void:
	var problems: Array[String] = []
	# A level transmitter mounts on the tank's shell and is ranged to it.
	var gauge := mount_new("gauge_level", "supply_tank", 0.3, -0.7)
	if gauge == null:
		problems.append("mount gauge failed")
	if connect_equipment(gauge.comp_name, "signal", "fill_pump", "run") == "":
		problems.append("kind mismatch was NOT refused")
	for _i in 40:
		sim.tick()
	var reading := (gauge as SimGauge).reading
	var expected := tank.level_l / (tank.cross_section_m2 * 1000.0) * SimGauge.WATER_KPA_PER_M
	if absf(reading - expected) > 0.3:
		problems.append("gauge reading %.2f kPa, tank head is %.2f" % [reading, expected])
	var pump2 := place_new("pump", _world(Vector3(6.0, 0.0, -1.0)), 0.0)
	if pump2 == null or not remove_equipment(pump2.comp_name):
		problems.append("place/remove pump failed")
	var src_t := place_new("source", _world(Vector3(7.5, 0.0, 0.5)), 0.0)
	var drn_t := place_new("drain", _world(Vector3(8.6, 0.0, 0.5)), 0.0)
	if src_t == null or drn_t == null:
		problems.append("place source/drain failed")
	elif not remove_equipment(drn_t.comp_name) or not remove_equipment(src_t.comp_name):
		problems.append("source/drain removal failed")
	# Column: full duty from hot standby should settle the overhead near
	# 40 kPa within a couple of minutes, read honestly by a press gauge.
	var col := place_new("column", _world(Vector3(10.0, 0.0, 2.0)), 0.0) as SimColumn
	var pi_top := place_new("gauge_press", _world(Vector3(11.5, 0.0, 2.0)), 0.0)
	if col == null or pi_top == null:
		problems.append("place column/gauge failed")
	else:
		if connect_equipment(col.comp_name, "p_top", pi_top.comp_name, "process") != "":
			problems.append("pressure gauge connect refused")
		if connect_equipment("plant_mains", "power", col.comp_name, "power") != "":
			problems.append("column power feed refused")
		col.set_duty(1.0)
		for _i in 2400:
			sim.tick()
		var kpa := (pi_top as SimGauge).reading
		if kpa < 30.0 or kpa > 50.0:
			problems.append("column overhead %.1f kPa outside expected range" % kpa)
		if not remove_equipment(pi_top.comp_name) or not remove_equipment(col.comp_name):
			problems.append("column cleanup failed")
	# Air-cascade checks only where the aseptic suite exists (the hall).
	var cascade := sim.get_component("suite_hvac") as SimAirCascade
	if cascade != null:
		# Let the cascade settle, then verify ordering and the DP gauge.
		for _i in 2400:
			sim.tick()
		var p: Dictionary = cascade.pressures
		if not (0.0 < float(p["al1"]) and float(p["al1"]) < float(p["gown"])
				and float(p["gown"]) < float(p["al2"]) and float(p["al2"]) < float(p["core"])
				and float(p["core"]) < float(p["iso"])):
			problems.append("cascade ordering wrong: %s" % str(p))
		var pdi := sim.get_component("pdi_iso") as SimGauge
		if absf(pdi.reading - (float(p["iso"]) - float(p["core"]))) > 0.5:
			problems.append("dp gauge disagrees with cascade")
		cascade.set_door("gown_al2", true)
		cascade.set_door("al2_core", true)
		for _i in 600:
			sim.tick()
		if float(cascade.pressures["core"]) - float(cascade.pressures["gown"]) > 5.0:
			problems.append("open airlock failed to collapse the step")
		cascade.set_door("gown_al2", false)
		cascade.set_door("al2_core", false)
	if remove_equipment("supply_tank"):
		problems.append("protected equipment was removable")
	# Disconnect: pull the gauge's mount wire, then land it again — the
	# single-source slot must free up.
	if not sim.disconnect_ports(sim.get_component("supply_tank"), "level",
			sim.get_component(gauge.comp_name), "process"):
		problems.append("disconnect refused")
	else:
		for visual in _wire_visuals.duplicate():
			if visual["b"] == gauge.comp_name:
				_wire_visuals.erase(visual)
		if connect_equipment("supply_tank", "level", gauge.comp_name, "process", [], false) != "":
			problems.append("rewire after disconnect refused")
	# Cabinet: starts empty, gets a panel built module by module, then a
	# field signal traverses terminal -> PLC rung -> terminal, and
	# through an interposing relay — field to panel to field. The rack
	# is dead until its PSU gets a 480 V feed.
	var cab := "chk_cab"
	if not place_cabinet(cab, _world(Vector3(3.0, 0.0, 6.5)), 0.0):
		problems.append("place cabinet failed")
		cab = ""
	else:
		if cabinet_plc(cab) != "" or not cabinet_all_records(cab).is_empty():
			problems.append("new cabinet was not empty")
		if cabinet_add_module(cab, "card_di", 0, 8) == "":
			problems.append("I/O card accepted without a CPU")
		if cabinet_add_module(cab, "psu", 0, 0) != "" \
				or cabinet_add_module(cab, "plc", 0, 4) != "" \
				or cabinet_add_module(cab, "card_di", 0, 8) != "" \
				or cabinet_add_module(cab, "card_do", 0, 10) != "" \
				or cabinet_add_module(cab, "relay", 1, 0) != "" \
				or cabinet_add_module(cab, "tb8d", 2, 0) != "":
			problems.append("module placement refused")
		if cabinet_add_module(cab, "plc", 1, 4) == "":
			problems.append("second CPU accepted")
		if cabinet_add_module(cab, "relay", 1, 0) == "":
			problems.append("overlapping module accepted")
		var backed: Dictionary = cabinet_backed_channels(cab)
		if (backed["di"] as Array).size() != 8 or (backed["ai"] as Array).size() != 0:
			problems.append("card-backed channels wrong: %s" % str(backed))
		var plc_name := cabinet_plc(cab)
		var cab_plc := sim.get_component(plc_name) as SimPLC
		var psu_name := ""
		var relay_name := ""
		var t := "%s_m6_t" % cab  # the tb8d strip's terminals
		for record_name in cabinet_all_records(cab):
			if equip_types.get(record_name) == "psu":
				psu_name = record_name
			elif equip_types.get(record_name) == "relay":
				relay_name = record_name
		if connect_equipment("level_switch", "contact", t + "1", "in") != "":
			problems.append("field wire to cabinet terminal refused")
		if connect_equipment(t + "1", "out", plc_name, "di_0", [], false) != "":
			problems.append("internal terminal->PLC wire refused")
		if connect_equipment(psu_name, "dc_out", plc_name, "power", [], false) != "":
			problems.append("PSU->PLC power wire refused")
		if cab_plc.set_program([{"coil": "do_0", "logic": [[{"ref": "di_0"}]]}]) != "":
			problems.append("PLC refused a mirror rung")
		if connect_equipment(plc_name, "do_0", t + "2", "in", [], false) != "":
			problems.append("internal PLC->terminal wire refused")
		switch.set_band(150.0, 150.0)  # level < 150: contact closed for sure
		for _i in 10:
			sim.tick()
		# The PSU has no 480 V feed yet: the whole rack must be dead.
		if (sim.get_component(t + "2") as SimTerminal).t_out.value > 0.5:
			problems.append("unpowered PLC drove an output")
		if connect_equipment("plant_mains", "power", psu_name, "ac_in") != "":
			problems.append("mains to cabinet PSU refused")
		for _i in 10:
			sim.tick()
		if (sim.get_component(t + "2") as SimTerminal).t_out.value < 0.5:
			problems.append("signal failed to traverse terminal -> PLC -> terminal")
		# And through the interposing relay.
		if connect_equipment(t + "1", "out", relay_name, "coil", [], false) != "":
			problems.append("terminal -> relay coil wire refused")
		if connect_equipment(relay_name, "contact", t + "3", "in", [], false) != "":
			problems.append("relay contact -> terminal wire refused")
		for _i in 10:
			sim.tick()
		if (sim.get_component(t + "3") as SimTerminal).t_out.value < 0.5:
			problems.append("signal failed to traverse the interposing relay")
		switch.set_band(40.0, 80.0)
	var real_path := save_path
	save_path = "user://selfcheck_save.json"
	var roundtrip := save_game() and load_game()
	save_path = real_path
	if not roundtrip:
		problems.append("save/load round-trip failed")
	elif sim.get_component(gauge.comp_name) == null:
		problems.append("placed gauge missing after load")
	elif tank == null or pump == null:
		problems.append("commissioned refs missing after load")
	else:
		var routed := false
		for visual in _wire_visuals:
			if (visual["waypoints"] as Array).size() > 0:
				routed = true
		if not routed:
			problems.append("routed waypoints lost in save/load round-trip")
	if cab != "" and roundtrip:
		var plc_after := sim.get_component(cabinet_plc(cab)) as SimPLC
		if plc_after == null or plc_after.program.size() != 1:
			problems.append("cabinet PLC program lost in save/load")
		else:
			(sim.get_component("level_switch") as SimFloatSwitch).set_band(150.0, 150.0)
			for _i in 10:
				sim.tick()
			if (sim.get_component("%s_m6_t2" % cab) as SimTerminal).t_out.value < 0.5:
				problems.append("cabinet loop dead after save/load")
			(sim.get_component("level_switch") as SimFloatSwitch).set_band(40.0, 80.0)
		if not remove_cabinet(cab):
			problems.append("cabinet removal failed")
	if problems.is_empty():
		print("[flowstate] build-api exercise OK — gauge %.1f kPa, %d components, %d wires"
			% [reading, sim.components.size(), sim.wires.size()])
	else:
		push_warning("[flowstate] build-api exercise FAILED: " + "; ".join(problems))


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SIM_DT:
		var started := Time.get_ticks_usec()
		sim.tick()
		_note_cost(Time.get_ticks_usec() - started)
		_accumulator -= SIM_DT
	if _revalidate_in > 0:
		_revalidate_in -= 1
		if _revalidate_in == 0:
			_revalidate_supports()
	if _support_exercise_phase > 0:
		_support_exercise_wait -= 1
		if _support_exercise_wait <= 0:
			_exercise_supports()


## The kernel budget is 50 ms per scan at 20 Hz, and the hydraulic
## solve is the part that grows with the plant, so say once what a
## scan actually costs on this plant.
func _note_cost(elapsed_us: int) -> void:
	if _cost_ticks < 0:
		return
	_cost_ticks += 1
	_cost_total_us += elapsed_us
	_cost_solve_ms += sim.solve_ms
	_cost_newton_ms += sim.newton_ms
	var net := sim.network()
	_cost_iterations += net.iterations if net != null else 0
	if _cost_ticks >= 150:
		print("[flowstate] kernel cost: %.2f ms/scan; hydraulic pass %.2f ms, of which the Newton solve %.2f ms (%d nodes, %d branches, band %d, %.1f iterations a scan, residual %.6f L/s)" % [
			_cost_total_us / 1000.0 / _cost_ticks, _cost_solve_ms / _cost_ticks,
			_cost_newton_ms / _cost_ticks,
			net.node_count() if net != null else 0,
			net.branches.size() if net != null else 0,
			net.bandwidth() if net != null else 0,
			float(_cost_iterations) / _cost_ticks,
			net.residual_lps if net != null else 0.0])
		_cost_ticks = -1


func _new_graph() -> void:
	sim = Simulation.new(SIM_DT)
	historian = sim.attach_historian(SimHistorian.new())


## ---- equipment lifecycle ------------------------------------------------

func place(type_id: String, name_: String, params: Dictionary,
		world_pos: Vector3, rot_y: float, is_protected: bool) -> SimComponent:
	# Nozzle pressures are piezometric, so a vessel on a deck really
	# does stand above one at grade: the placement height is its
	# elevation, and it is re-derived from the saved position on load.
	if type_id in ["tank", "reactor", "crystallizer", "source", "drain"] \
			and not params.has("elevation_m"):
		params = params.duplicate()
		params["elevation_m"] = snappedf(to_local(world_pos).y, 0.01)
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var view := PlantFactory.make_view(type_id, record)
	view.position = to_local(world_pos) + Vector3(0, PlantFactory.Y_OFFSETS.get(type_id, 0.0), 0)
	view.rotation.y = rot_y
	add_child(view)
	match type_id:
		"tank":
			(view as TankView).setup(record as SimTank)
		"pump":
			(view as PumpView).setup(record as SimPump)
		"relay":
			(view as RelayView).setup(record as SimRelay)
		"float_switch":
			(view as FloatSwitchView).setup(record as SimFloatSwitch)
		"gauge_level", "gauge_flow", "gauge_dp", "gauge_press", \
		"gauge_temp", "gauge_conc":
			(view as GaugeView).setup(record as SimGauge)
		"column":
			(view as ColumnView).setup(record as SimColumn)
		"valve":
			(view as ControlValveView).setup(record as SimControlValve)
		"block_valve":
			(view as BlockValveView).setup(record as SimBlockValve)
		"controller":
			(view as PIDView).setup(record as SimPID)
		"mains":
			(view as MainsView).setup(record as SimMainsFeed)
		"psu":
			(view as PsuView).setup(record as SimPowerSupply)
		"source":
			(view as SourceView).setup(record as SimSource)
		"drain":
			(view as DrainView).setup(record as SimDrain)
		"reactor":
			(view as ReactorView).setup(record as SimReactor)
		"centrifuge":
			(view as CentrifugeView).setup(record as SimCentrifuge)
		"hx":
			(view as HeatExchangerView).setup(record as SimHeatExchanger)
		"steamgen":
			(view as SteamGenView).setup(record as SimSteamGen)
		"vaclock":
			(view as VacLockView).setup(record as SimVacuumLock)
		"vialfill":
			(view as VialFillerView).setup(record as SimVialFiller)
		"crystallizer":
			(view as CrystallizerView).setup(record as SimCrystallizer)
		"dryer":
			(view as DryerView).setup(record as SimDryer)
		"still":
			(view as StillView).setup(record as SimStill)
		"air_cascade":
			(view as AsepticSuite).setup(record as SimAirCascade)
	if type_id == "tank":
		(view as TankView).config_cb = _configure_tank  # nozzles are its own
	else:
		PlantFactory.attach_port_markers(view, record, type_id)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	if is_protected:
		protected[record.comp_name] = true
	return record


func place_new(type_id: String, world_pos: Vector3, rot_y: float) -> SimComponent:
	return place(type_id, sim.unique_name(type_id), {}, world_pos, rot_y, false)


## ---- instruments on vessels ------------------------------------------------
## A level switch or level transmitter is not placed on the floor and
## piped to a "level" nozzle (director's call, 2026-09-02): it is
## mounted on a vessel's shell, and the plant lands the kernel wire
## from the vessel's internal tap for it. frac is the height up the
## shell, angle the bearing round it.

func mount_instrument(type_id: String, name_: String, params: Dictionary,
		host_name: String, frac: float, angle: float, is_protected: bool) -> SimComponent:
	var host_view := views.get(host_name) as TankView
	var host := sim.get_component(host_name) as SimTank
	if host_view == null or host == null or not PlantFactory.MOUNTABLE.has(type_id):
		return null
	params = params.duplicate()
	if type_id == "gauge_level" and not params.has("liters_per_meter"):
		# A transmitter is ranged to the vessel it is on.
		params["liters_per_meter"] = host.cross_section_m2 * 1000.0
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var view := PlantFactory.make_view(type_id, record)
	if type_id == "float_switch":
		(view as FloatSwitchView).setup(record as SimFloatSwitch, true)
	else:
		(view as GaugeView).setup(record as SimGauge, true)
	host_view.mount(view, frac, angle)
	var skip: Array[String] = [str(PlantFactory.MOUNTED_INPUT[type_id])]
	PlantFactory.attach_port_markers(view, record, type_id,
		PlantFactory.MOUNTED_ANCHORS.get(type_id, {}), skip)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	mounted[record.comp_name] = {"host": host_name, "frac": frac, "angle": angle}
	if is_protected:
		protected[record.comp_name] = true
	connect_equipment(host_name, "level", record.comp_name,
		str(PlantFactory.MOUNTED_INPUT[type_id]), [], false)
	return record


## Mount with default sizing: a switch trips around the height it is
## mounted at, a transmitter is ranged to the vessel.
func mount_new(type_id: String, host_name: String, frac: float, angle: float) -> SimComponent:
	var params := {}
	var host := sim.get_component(host_name) as SimTank
	if type_id == "float_switch" and host != null:
		var trip := host.capacity_l * clampf(frac, 0.04, 0.97)
		params = {"low_l": maxf(trip - 0.15 * host.capacity_l, 0.0),
			"high_l": minf(trip + 0.15 * host.capacity_l, host.capacity_l)}
	return mount_instrument(type_id, sim.unique_name(type_id), params,
		host_name, frac, angle, false)


## ---- control cabinets -----------------------------------------------------
## A cabinet starts as an EMPTY enclosure with bare DIN rails. The
## cabinet editor places modules — PSU, one PLC CPU, I/O cards (which
## gate usable PLC channels), relays, terminal strips — each backed by
## real kernel records, and lands internal wires as hidden kernel
## wires. The 3D interior renders the layout; field wiring uses the
## flank markers terminal strips and PSUs provide.

func unique_cabinet_name() -> String:
	var index := 1
	while cabinets.has("cabinet_%d" % index):
		index += 1
	return "cabinet_%d" % index


func place_cabinet(name_: String, world_pos: Vector3, rot_y: float) -> bool:
	if cabinets.has(name_):
		return false
	var view := CabinetView.new()
	view.position = to_local(world_pos)
	view.rotation.y = rot_y
	add_child(view)
	view.setup(name_)
	view.config_cb = _configure_cabinet
	cabinets[name_] = {"node": view, "modules": [], "next_id": 1}
	return true


## Add one module to a rail. Returns "" or the refusal reason.
## forced_id / forced_bank replay a saved layout exactly.
func cabinet_add_module(cab: String, type_id: String, rail: int, slot: int,
		forced_id: String = "", forced_bank: int = -1) -> String:
	if not cabinets.has(cab):
		return "no such cabinet"
	if not CabinetSpec.MODULES.has(type_id):
		return "unknown module type"
	var entry: Dictionary = cabinets[cab]
	var modules: Array = entry["modules"]
	if not CabinetSpec.span_free(modules, rail, slot, CabinetSpec.units_of(type_id)):
		return "doesn't fit there"
	if type_id == "plc" and cabinet_plc(cab) != "":
		return "one CPU per cabinet"
	var bank := -1
	if CabinetSpec.CARD_FAMILY.has(type_id):
		if cabinet_plc(cab) == "":
			return "place a PLC CPU first"
		bank = forced_bank if forced_bank >= 0 else _free_bank(cab, type_id)
		if bank < 0:
			return "no channel capacity left for that card"
	var id := forced_id
	if id == "":
		id = "m%d" % int(entry["next_id"])
	entry["next_id"] = maxi(int(entry["next_id"]), int(id.trim_prefix("m")) + 1)
	var base := "%s_%s" % [cab, id]
	var records: Array[String] = []
	match type_id:
		"psu":
			records.append(_add_cab_record(cab, "psu", base, {}))
		"plc":
			records.append(_add_cab_record(cab, "plc", base,
				{"di": 16, "do": 16, "ai": 8, "ao": 8}))
		"relay":
			records.append(_add_cab_record(cab, "relay", base, {}))
		"tb8d":
			for i in range(8):
				records.append(_add_cab_record(cab, "terminal", "%s_t%d" % [base, i + 1],
					{"kind": "discrete"}))
		"tb4a":
			for i in range(4):
				records.append(_add_cab_record(cab, "terminal", "%s_t%d" % [base, i + 1],
					{"kind": "analog"}))
	modules.append({"id": id, "type": type_id, "rail": rail, "slot": slot,
		"bank": bank, "records": records})
	_sync_cabinet(cab)
	return ""


func _add_cab_record(cab: String, type_id: String, name_: String, params: Dictionary) -> String:
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	sim.register_with_historian(record)
	views[name_] = (cabinets[cab] as Dictionary)["node"]
	equip_types[name_] = type_id
	protected[name_] = true
	member_of[name_] = cab
	return name_


## Lowest bank of the card's family not already claimed in this cabinet.
func _free_bank(cab: String, type_id: String) -> int:
	var family := str(CabinetSpec.CARD_FAMILY[type_id])
	var width := int(CabinetSpec.CARD_CHANNELS[type_id])
	var capacity := {"di": 16, "do": 16, "ai": 8, "ao": 8}[family] as int
	var taken := {}
	for module_v: Variant in (cabinets[cab] as Dictionary)["modules"]:
		var module := module_v as Dictionary
		if CabinetSpec.CARD_FAMILY.get(str(module["type"])) == family:
			taken[int(module["bank"])] = true
	for bank in range(capacity / width):
		if not taken.has(bank):
			return bank
	return -1


func cabinet_remove_module(cab: String, module_id: String) -> bool:
	if not cabinets.has(cab):
		return false
	var entry: Dictionary = cabinets[cab]
	var modules: Array = entry["modules"]
	for i in range(modules.size()):
		var module := modules[i] as Dictionary
		if str(module["id"]) != module_id:
			continue
		if CabinetSpec.CARD_FAMILY.has(str(module["type"])):
			_drop_card_wires(cab, module)
		for record_name: String in module["records"]:
			sim.remove_component(record_name)
			_prune_wires_of(record_name)
			views.erase(record_name)
			equip_types.erase(record_name)
			protected.erase(record_name)
			member_of.erase(record_name)
		modules.remove_at(i)
		_sync_cabinet(cab)
		return true
	return false


## Removing an I/O card takes its channels' wires with it.
func _drop_card_wires(cab: String, module: Dictionary) -> void:
	var plc_name := cabinet_plc(cab)
	if plc_name == "":
		return
	var family := str(CabinetSpec.CARD_FAMILY[str(module["type"])])
	var width := int(CabinetSpec.CARD_CHANNELS[str(module["type"])])
	var channels := {}
	for i in range(width):
		channels["%s_%d" % [family, int(module["bank"]) * width + i]] = true
	for visual in _wire_visuals.duplicate():
		var hits: bool = (str(visual["a"]) == plc_name and channels.has(str(visual["a_port"]))) \
			or (str(visual["b"]) == plc_name and channels.has(str(visual["b_port"])))
		if hits:
			remove_internal_wire(visual)


func _prune_wires_of(member: String) -> void:
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == member or visual["b"] == member:
			if visual["node"] != null:
				(visual["node"] as Node).queue_free()
		else:
			keep.append(visual)
	_wire_visuals = keep


func remove_cabinet(name_: String) -> bool:
	if not cabinets.has(name_):
		return false
	var entry: Dictionary = cabinets[name_]
	for module_v: Variant in (entry["modules"] as Array).duplicate():
		var module := module_v as Dictionary
		for record_name: String in module["records"]:
			sim.remove_component(record_name)
			_prune_wires_of(record_name)
			views.erase(record_name)
			equip_types.erase(record_name)
			protected.erase(record_name)
			member_of.erase(record_name)
	(entry["node"] as Node).queue_free()
	cabinets.erase(name_)
	_revalidate_in = 3
	return true


## ---- cabinet queries (editor, ladder, port menu) --------------------------

func cabinet_plc(cab: String) -> String:
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		if str(module["type"]) == "plc":
			return str((module["records"] as Array)[0])
	return ""


## Channels the placed I/O cards back, per family: {"di": [0,1,...]}.
func cabinet_backed_channels(cab: String) -> Dictionary:
	var out := {"di": [], "do": [], "ai": [], "ao": []}
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		if not CabinetSpec.CARD_FAMILY.has(type_id):
			continue
		var family := str(CabinetSpec.CARD_FAMILY[type_id])
		var width := int(CabinetSpec.CARD_CHANNELS[type_id])
		for i in range(width):
			(out[family] as Array).append(int(module["bank"]) * width + i)
	for family: String in out:
		(out[family] as Array).sort()
	return out


## Field-wirable member records: terminals and PSUs.
func cabinet_field_records(cab: String) -> Array[String]:
	var out: Array[String] = []
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		var module := module_v as Dictionary
		if str(module["type"]) in ["tb8d", "tb4a", "psu"]:
			for record_name: String in module["records"]:
				out.append(record_name)
	return out


## All member records, for the editor's wiring panel.
func cabinet_all_records(cab: String) -> Array[String]:
	var out: Array[String] = []
	for module_v: Variant in (cabinets.get(cab, {}) as Dictionary).get("modules", []):
		for record_name: String in (module_v as Dictionary)["records"]:
			out.append(record_name)
	return out


## ---- cabinet sync: flank markers + 3D interior ----------------------------

func _sync_cabinet(cab: String) -> void:
	var entry: Dictionary = cabinets[cab]
	var view := entry["node"] as CabinetView
	var markers: Dictionary = view.get_meta("port_markers", {})
	for key: String in markers:
		var marker := markers[key] as Node
		if is_instance_valid(marker):
			marker.queue_free()
	view.set_meta("port_markers", {})
	var y := 1.72
	for module_v: Variant in entry["modules"]:
		var module := module_v as Dictionary
		var type_id := str(module["type"])
		for record_name: String in module["records"]:
			var record := sim.get_component(record_name)
			if record is SimTerminal:
				PlantFactory.attach_port_markers(view, record, "terminal",
					{"in": Vector3(-0.72, y, 0.12), "out": Vector3(0.72, y, 0.12)})
				y -= 0.115
			elif record is SimPowerSupply:
				PlantFactory.attach_port_markers(view, record, "psu",
					{"ac_in": Vector3(-0.72, y, 0.12), "dc_out": Vector3(0.72, y, 0.12)})
				y -= 0.115
	view.set_layout(entry["modules"], _cabinet_wire_specs(cab))
	var relays: Array[SimRelay] = []
	for module_v: Variant in entry["modules"]:
		for record_name: String in (module_v as Dictionary)["records"]:
			var record := sim.get_component(record_name)
			if record is SimRelay:
				relays.append(record as SimRelay)
	view.set_relays(relays)
	_revalidate_in = 3


func _cabinet_wire_specs(cab: String) -> Array:
	var specs: Array = []
	var members := {}
	for record_name in cabinet_all_records(cab):
		members[record_name] = true
	for visual in _wire_visuals:
		if not (members.has(str(visual["a"])) and members.has(str(visual["b"]))):
			continue
		var a := _cabinet_port_pos(cab, str(visual["a"]))
		var b := _cabinet_port_pos(cab, str(visual["b"]))
		var src := sim.get_component(str(visual["a"]))
		var port: SimOutputPort = src.outputs.get(str(visual["a_port"])) if src != null else null
		var color: Color = PlantFactory.KIND_COLORS.get(port.kind, Color.GRAY) if port != null \
			else Color.GRAY
		specs.append({"a": a, "b": b, "color": color})
	return specs


func _cabinet_port_pos(cab: String, record_name: String) -> Vector3:
	for module_v: Variant in (cabinets[cab] as Dictionary)["modules"]:
		var module := module_v as Dictionary
		var records: Array = module["records"]
		var index := records.find(record_name)
		if index < 0:
			continue
		var units := CabinetSpec.units_of(str(module["type"]))
		var center := CabinetSpec.module_center(int(module["rail"]), int(module["slot"]), units)
		var width := units * CabinetSpec.UNIT_W - 0.012
		if records.size() > 1:  # terminal within a strip
			center.x += -width / 2.0 + (index + 0.5) * width / records.size()
		return center + Vector3(0, -CabinetSpec.MODULE_H / 2.0, 0)
	return Vector3.ZERO


func _configure_cabinet(view: CabinetView) -> void:
	if cabinet_editor != null:
		cabinet_editor.open(self, view.cabinet_name)


## Drop one internal (hidden) wire — the schematic panel's remove.
func remove_internal_wire(visual: Dictionary) -> void:
	_disconnect_visual(visual)
	_wire_visuals.erase(visual)


## ---- tank configuration ---------------------------------------------------

func _configure_tank(view: TankView) -> void:
	if tank_panel != null:
		tank_panel.open(self, view.tank.comp_name)


func resize_tank(name_: String, height_m: float, diameter_m: float) -> void:
	var record := sim.get_component(name_) as SimTank
	var view := views.get(name_) as TankView
	if record == null or view == null:
		return
	record.set_size(height_m, diameter_m)
	view.rebuild()
	refresh_wires_of(name_)
	# Instruments on the shell moved with it; their cables follow.
	for inst_name: String in mounted:
		if str((mounted[inst_name] as Dictionary)["host"]) == name_:
			refresh_wires_of(inst_name)
	_revalidate_in = 3


## Rebuild the pipe visuals touching one record — after its nozzles
## moved or its vessel was resized.
func refresh_wires_of(name_: String) -> void:
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue
		if str(visual["a"]) != name_ and str(visual["b"]) != name_:
			continue
		(visual["node"] as Node).queue_free()
		var pipe := _build_pipe(str(visual["a"]), str(visual["a_port"]),
			str(visual["b"]), str(visual["b_port"]), visual["waypoints"])
		visual["node"] = pipe
		if str(visual.get("color", "")) != "":
			pipe.apply_service(Color.html(str(visual["color"])), str(visual.get("label", "")))
	_revalidate_in = 3


func remove_equipment(name_: String) -> bool:
	if protected.has(name_) or not views.has(name_):
		return false
	# Instruments mounted on a vessel go with it.
	for inst_name: String in mounted.keys():
		if inst_name != name_ and str((mounted[inst_name] as Dictionary)["host"]) == name_:
			remove_equipment(inst_name)
	if mounted.has(name_):
		var host_view := views.get(str((mounted[name_] as Dictionary)["host"])) as TankView
		if host_view != null:
			host_view.unmount(views[name_] as Node3D)
		mounted.erase(name_)
	sim.remove_component(name_)
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == name_ or visual["b"] == name_:
			if visual["node"] != null:
				(visual["node"] as Node).queue_free()
		else:
			keep.append(visual)
	_wire_visuals = keep
	(views[name_] as Node).queue_free()
	views.erase(name_)
	equip_types.erase(name_)
	return true


## Connect two ports (by record/port name), optionally routed through
## player-laid waypoints (plant-local). Returns "" on success or a
## human-readable refusal — the kernel's wiring rules, surfaced.
## visible=false makes an internal wire (cabinet hookup): a real
## kernel wire with no 3D run behind it.
func connect_equipment(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array = [],
		visible: bool = true) -> String:
	var src := sim.get_component(src_name)
	var dst := sim.get_component(dst_name)
	if src == null or dst == null:
		return "component missing"
	# One player pipe is one kernel wire. A material nozzle may take
	# several: that is a tee, and the network solves the split.
	var out_port: SimOutputPort = src.outputs.get(src_port)
	var in_port: SimInputPort = dst.inputs.get(dst_port)
	if out_port == null or in_port == null:
		return "connect an output to an input"
	if out_port.kind != in_port.kind:
		return "cannot wire %s (%s) to %s (%s)" % [
			out_port.path(), SimTypes.kind_name(out_port.kind),
			in_port.path(), SimTypes.kind_name(in_port.kind)]
	if in_port.wire_count > 0 and not SimTypes.allows_multiple_sources(in_port.kind):
		return "%s already has a wire" % in_port.path()
	if not sim.connect_ports(src, src_port, dst, dst_port):
		return "connection refused"
	if visible:
		_wire_visual(src_name, src_port, dst_name, dst_port, waypoints)
	else:
		_wire_visuals.append({
			"node": null, "a": src_name, "a_port": src_port,
			"b": dst_name, "b_port": dst_port, "waypoints": [],
			"color": "", "label": "", "hidden": true,
		})
	return ""


## Size a routed pipe run, in Pa per (L/s)^2: a short generous line is
## 5000, a long thin one tens of thousands. Saved with the wire.
func set_pipe_resistance(src_name: String, src_port: String, dst_name: String,
		dst_port: String, k_pa_per_lps2: float) -> bool:
	var wire := sim.find_wire(sim.get_component(src_name), src_port,
		sim.get_component(dst_name), dst_port)
	if wire == null or not wire.is_material():
		return false
	sim.set_wire_resistance(wire, k_pa_per_lps2)
	return true


## ---- structure ----------------------------------------------------------

func unique_struct_name(prefix: String) -> String:
	var index := 1
	while structures.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


## base_pos is the bottom-center placement point in world space.
## Bearing rules are the caller's job (StructureFactory.placement_ok);
## the loader and headless exercises place directly.
func place_structure(type_id: String, name_: String, base_pos: Vector3, rot_y: float,
		length: float = -1.0) -> bool:
	if structures.has(name_):
		return false
	var node := StructureFactory.make_view(type_id, name_, length)
	if node == null:
		return false
	add_child(node)
	node.global_position = base_pos + Vector3(0, (StructureFactory.SIZES[type_id] as Vector3).y / 2.0, 0)
	node.rotation.y = rot_y
	if type_id == "s_sign":
		node.config_cb = _configure_sign
	structures[name_] = {"type": type_id, "node": node, "length": length, "text": ""}
	_revalidate_in = 3
	return true


## Removing structure re-checks every run: whatever it was carrying
## turns alarm-red rather than quietly staying up.
func remove_structure(name_: String) -> bool:
	if not structures.has(name_):
		return false
	((structures[name_] as Dictionary)["node"] as Node).queue_free()
	structures.erase(name_)
	_revalidate_in = 3
	return true


## ---- standalone infrastructure runs --------------------------------------

func unique_run_name(prefix: String) -> String:
	var index := 1
	while runs.has("%s_%d" % [prefix, index]):
		index += 1
	return "%s_%d" % [prefix, index]


## A routed run with no kernel wire behind it: pipe, conduit, or cable
## tray laid ahead of the equipment it will one day serve. sparse
## points are plant-local; colliders go on layer 1, so the run is real
## support for whatever gets routed along it later.
func place_run(kind: String, name_: String, sparse_local: Array) -> bool:
	if runs.has(name_) or not StructureFactory.RUNS.has(kind):
		return false
	var spec: Dictionary = StructureFactory.RUNS[kind]
	var view := PipeView.new()
	add_child(view)
	view.setup(PipeRoute.orthogonalize(sparse_local), func() -> float: return 0.0,
		spec["color"], spec["radius"], name_, spec["style"], 1)
	view.config_cb = _configure_run
	runs[name_] = {"kind": kind, "node": view, "points": sparse_local,
		"color": "", "label": ""}
	_revalidate_in = 3
	return true


## E on a run: open the color/label editor and store what it applies.
func _configure_run(view: PipeView) -> void:
	if config_panel == null:
		return
	config_panel.open_for_run(view.service_color(), view.service_label,
		func(color: Color, label_: String) -> void: set_run_service(view, color, label_))


func set_run_service(view: PipeView, color: Color, label_: String) -> void:
	for visual in _wire_visuals:
		if visual["node"] == view:
			visual["color"] = color.to_html(false)
			visual["label"] = label_
			view.apply_service(color, label_)
			return
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		if entry["node"] == view:
			entry["color"] = color.to_html(false)
			entry["label"] = label_
			view.apply_service(color, label_)
			return


## E on a sign: open the text editor and persist the result.
func _configure_sign(view: StructureView) -> void:
	if config_panel == null:
		return
	var entry: Dictionary = structures.get(view.struct_name, {})
	config_panel.open_for_sign(str(entry.get("text", "")),
		func(text: String) -> void: set_sign_text(view.struct_name, text))


func set_sign_text(name_: String, text: String) -> void:
	if not structures.has(name_):
		return
	var entry: Dictionary = structures[name_]
	entry["text"] = text
	(entry["node"] as StructureView).set_text(text if text != "" else "SIGN")


func remove_placed_run(view: PipeView) -> bool:
	for name_: String in runs:
		if (runs[name_] as Dictionary)["node"] == view:
			view.queue_free()
			runs.erase(name_)
			_revalidate_in = 3  # whatever it carried re-checks
			return true
	return false


## Remove one routed run by its view (X while aiming at it): the wire
## leaves the kernel, the input reverts next scan, the visual goes.
func remove_run(view: PipeView) -> bool:
	for visual in _wire_visuals:
		if visual["node"] == view:
			_disconnect_visual(visual)
			(visual["node"] as Node).queue_free()
			_wire_visuals.erase(visual)
			return true
	return false


## Drop the kernel wire behind a visual entry.
func _disconnect_visual(visual: Dictionary) -> void:
	var src := sim.get_component(str(visual["a"]))
	var dst := sim.get_component(str(visual["b"]))
	if src == null or dst == null:
		return
	sim.disconnect_ports(src, str(visual["a_port"]), dst, str(visual["b_port"]))


## Re-run the support rule over every routed run — wires and standalone
## infrastructure — updating brackets and alarm state. Called a few
## frames after geometry changes. A run excludes its own colliders so
## it can't count as its own support.
func _revalidate_supports() -> void:
	var space := get_world_3d().direct_space_state
	for visual in _wire_visuals:
		if visual["node"] == null:
			continue  # internal cabinet wire, nothing physical to carry
		var path := PipeRoute.routed(
			_marker_pos(str(visual["a"]), str(visual["a_port"])),
			_marker_dir(str(visual["a"]), str(visual["a_port"])),
			_marker_pos(str(visual["b"]), str(visual["b_port"])),
			_marker_dir(str(visual["b"]), str(visual["b_port"])),
			visual["waypoints"])
		_apply_support_path(visual["node"] as PipeView, path, space)
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		_apply_support(entry["node"] as PipeView, entry["points"], space)


func _apply_support(view: PipeView, sparse_local: Array, space: PhysicsDirectSpaceState3D) -> void:
	_apply_support_path(view, PipeRoute.orthogonalize(sparse_local), space)


func _apply_support_path(view: PipeView, path: Array[Vector3],
		space: PhysicsDirectSpaceState3D) -> void:
	var global_path: Array[Vector3] = []
	for point in path:
		global_path.append(to_global(point))
	var result := SupportCheck.evaluate(global_path, space, view.collider_rids())
	var local_brackets: Array[Dictionary] = []
	for bracket: Dictionary in result["brackets"]:
		local_brackets.append({"from": to_local(bracket["from"]), "to": to_local(bracket["to"])})
	view.set_supports(local_brackets, not bool(result["ok"]))


func _wire_visual(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array) -> void:
	var pipe := _build_pipe(src_name, src_port, dst_name, dst_port, waypoints)
	_wire_visuals.append({
		"node": pipe, "a": src_name, "a_port": src_port,
		"b": dst_name, "b_port": dst_port, "waypoints": waypoints,
		"color": "", "label": "",
	})
	_revalidate_in = 3


func _build_pipe(src_name: String, src_port: String, dst_name: String, dst_port: String,
		waypoints: Array) -> PipeView:
	var from := _marker_pos(src_name, src_port)
	var to := _marker_pos(dst_name, dst_port)
	var src := sim.get_component(src_name)
	var port: SimOutputPort = src.outputs[src_port]
	var kind := port.kind
	var getter: Callable
	var wire: SimWire = null
	if SimTypes.is_material(kind):
		# The honest live value of a pipe is the flow the network solved
		# through it. An instrument tap has no branch of its own and
		# reads the line it is tapped into.
		wire = sim.find_wire(src, src_port, sim.get_component(dst_name), dst_port)
		getter = func() -> float:
			if wire == null:
				return 0.0
			if wire.branch != null:
				return absf(wire.branch.flow_lps)
			return wire.dst.stream.flow_lps
	else:
		getter = func() -> float: return port.value
	var is_process := SimTypes.is_material(kind) \
		or kind == SimTypes.PortKind.PROCESS_LEVEL
	var pipe := PipeView.new()
	add_child(pipe)
	pipe.setup(PipeRoute.routed(from, _marker_dir(src_name, src_port),
			to, _marker_dir(dst_name, dst_port), waypoints), getter,
		PlantFactory.KIND_COLORS[kind], 0.07 if is_process else 0.025,
		"%s.%s -> %s.%s" % [src_name, src_port, dst_name, dst_port])
	pipe.config_cb = _configure_run
	if wire != null:
		# A line can be pressurised without moving: a dead-headed
		# discharge, a full riser under a stopped pump. Show that too.
		var live := wire
		var kernel := sim
		pipe.set_pressure_getter(func() -> float:
			return maxf(kernel.pressure_at(live.src), kernel.pressure_at(live.dst)))
	return pipe


func _marker_pos(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get("%s:%s" % [record_name, port_name])
	return to_local(marker.global_position) if marker != null else view.position


## The fitting's outward axis (plant-local): runs must leave along it.
func _marker_dir(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get("%s:%s" % [record_name, port_name])
	return marker.global_basis.x.normalized() if marker != null else Vector3.ZERO


## ---- the commissioned starting loop -------------------------------------

func _build_initial_plant() -> void:
	tank = place("tank", "supply_tank",
		{"capacity_l": 100.0, "level_l": 70.0},
		_world(Vector3(2.5, 0, -2.0)), 0.0, true) as SimTank
	# The level switch is on the tank's shell, not beside it.
	switch = mount_instrument("float_switch", "level_switch", {"low_l": 40.0, "high_l": 80.0},
		"supply_tank", 0.6, 0.9, true) as SimFloatSwitch
	relay = place("relay", "pump_relay", {},
		_world(Vector3(-2.5, 1.5, -4.74)) - Vector3(0, PlantFactory.Y_OFFSETS["relay"], 0),
		0.0, true) as SimRelay
	pump = place("pump", "fill_pump", {"rated_lps": 4.0},
		_world(Vector3(-0.5, 0, -2.6)), 0.0, true) as SimPump
	place("mains", "plant_mains", {}, _world(Vector3(-4.4, 0, -1.2)), 0.0, true)
	place("source", "raw_water", {}, _world(Vector3(-6.4, 0, -2.9)), 0.0, true)
	place("drain", "du_100", {"rate_lps": 1.5}, _world(Vector3(4.7, 0, -1.4)), 0.0, true)
	# Power first — nothing runs without a cable back to the feeder.
	connect_equipment("plant_mains", "power", "fill_pump", "power",
		[Vector3(-3.6, 0.3, -1.6), Vector3(-1.0, 0.3, -2.9)])
	# The flow path is honest end to end: the pump pulls from the
	# supply header, and the tank's consumption is a real drain. One
	# pipe per connection — the facade meters the draw underneath.
	connect_equipment("raw_water", "outlet", "fill_pump", "inlet",
		[Vector3(-5.6, 0.3, -3.1), Vector3(-1.2, 0.3, -3.1)])
	connect_equipment("supply_tank", "outlet", "du_100", "inlet")
	# Signal runs drop to the floor and run along it — the support rule
	# applies to the commissioned loop too.
	connect_equipment("level_switch", "contact", "pump_relay", "coil",
		[Vector3(1.7, 0.3, -3.4), Vector3(-2.7, 0.3, -4.3)])
	connect_equipment("pump_relay", "contact", "fill_pump", "run",
		[Vector3(-2.3, 0.3, -3.6), Vector3(-0.8, 0.3, -2.7)])
	connect_equipment("fill_pump", "outlet", "supply_tank", "inlet")
	if build_suite:
		_build_aseptic_suite()


func _build_aseptic_suite() -> void:
	# The suite view builds its own world-space geometry; keep its node
	# at global y=0 (plant sits 0.08 up on the plinth).
	place("air_cascade", "suite_hvac", {}, _world(Vector3(0, -0.08, 0)), 0.0, true)
	var gauge_specs: Array = [
		["pdi_gown", Vector3(-27.9, -0.08, -8.2), "p_gown", "p_al1"],
		["pdi_core", Vector3(-32.2, -0.08, -7.3), "p_core", "p_al2"],
		["pdi_iso", Vector3(-34.2, -0.08, -6.9), "p_iso", "p_core"],
	]
	for spec: Array in gauge_specs:
		place("gauge_dp", spec[0], {}, _world(spec[1]), 0.0, true)
		connect_equipment("suite_hvac", spec[2], spec[0], "process_a")
		connect_equipment("suite_hvac", spec[3], spec[0], "process_b")


func _world(local: Vector3) -> Vector3:
	return to_global(local)


func _build_hmi() -> void:
	hmi_view = HmiView.new()
	hmi_view.position = Vector3(-4.6, 1.6, -4.75)
	add_child(hmi_view)
	hmi_view.setup(historian, tank, switch, relay, pump)
	# The material balance by unit, beside it: the standing proof that
	# what the headers fed is still somewhere, from the records' meters.
	var balance_screen := HmiScreenView.new()
	balance_screen.name = "hmi_balance"
	balance_screen.position = Vector3(-6.9, 1.6, -4.75)
	add_child(balance_screen)
	balance_panel = PlantBalancePanel.new()
	balance_panel.setup(self)
	balance_screen.setup(balance_panel, "MATERIAL BALANCE", Vector2i(1024, 640), 1.2,
		"Material balance by unit: fed, out, held against held at build, and the residual, all from the records' own meters; the plant residual trended from the historian.")


func _self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var c_tank := check.add(SimTank.new("t", 100.0, 70.0)) as SimTank
	var c_switch := check.add(SimFloatSwitch.new("s", 40.0, 80.0)) as SimFloatSwitch
	var c_relay := check.add(SimRelay.new("r")) as SimRelay
	var c_pump := check.add(SimPump.new("p", 4.0)) as SimPump
	var c_mains := check.add(SimMainsFeed.new("m")) as SimMainsFeed
	var c_src := check.add(SimSource.new("bl")) as SimSource
	var c_drn := check.add(SimDrain.new("d", 1.5)) as SimDrain
	check.connect_ports(c_mains, "power", c_pump, "power")
	check.connect_ports(c_src, "outlet", c_pump, "inlet")
	check.connect_ports(c_pump, "outlet", c_tank, "inlet")
	check.connect_ports(c_tank, "outlet", c_drn, "inlet")
	check.connect_ports(c_tank, "level", c_switch, "level")
	check.connect_ports(c_switch, "contact", c_relay, "coil")
	check.connect_ports(c_relay, "contact", c_pump, "run")
	check.run_for(600.0)
	# Mass closes across the loop: what the header delivered is either
	# still in the tank or went down the drain.
	var closure := absf(c_src.total_l - ((c_tank.level_l - 70.0) + c_drn.total_l))
	var ok := c_tank.level_l >= 38.0 and c_tank.level_l <= 82.0 \
		and c_tank.overflowed_l == 0.0 and c_relay.cycles >= 1 and c_relay.cycles < 15 \
		and closure < 0.5
	if ok:
		print("[flowstate] kernel self-check OK — 600 s: level %.1f L, %d relay cycles, balance within %.3f L"
			% [c_tank.level_l, c_relay.cycles, closure])
	else:
		push_warning("[flowstate] kernel self-check FAILED — level %.1f L, overflow %.1f L, %d cycles, balance off by %.2f L"
			% [c_tank.level_l, c_tank.overflowed_l, c_relay.cycles, closure])
	_hydraulics_self_check()
	_control_self_check()
	_stream_self_check()


## Mirrors the Python hydraulics tests: the behaviours that separate a
## solved network from asserted flow. If a pump does not dead-head, if
## two in parallel double the flow, if a tee does not split by
## resistance, or if a tank does not drain downhill on its own, then
## pressure is decorative and we are back to bookkeeping.
func _hydraulics_self_check() -> void:
	var problems: Array[String] = []

	# A tee is a node: the split falls out of the resistances, and the
	# flow in equals the flows out. Warm-started, the next solve is
	# nearly free.
	var net := SimNetwork.new()
	var supply := net.add_node(200000.0, true)
	var tee := net.add_node()
	var easy_end := net.add_node(0.0, true)
	var hard_end := net.add_node(0.0, true)
	var feed := net.add_branch(SimResistance.new(supply, tee, 500.0))
	var easy := net.add_branch(SimResistance.new(tee, easy_end, 1000.0))
	var hard := net.add_branch(SimResistance.new(tee, hard_end, 9000.0))
	net.solve()
	if absf(feed.flow_lps - (easy.flow_lps + hard.flow_lps)) > SimNetwork.TOLERANCE_LPS:
		problems.append("tee does not conserve")
	if absf(easy.flow_lps - 3.0 * hard.flow_lps) > 0.02 * easy.flow_lps:
		problems.append("tee split is not by resistance")
	net.solve()
	if net.iterations > 3:
		problems.append("warm start took %d iterations" % net.iterations)

	# A pump makes its rating against a free discharge, dead-heads
	# against too much head, and two in parallel do not double the flow.
	if _pump_rig(300000.0, 4.0, 0.0) < 3.99:
		problems.append("free discharge did not give the rated flow")
	if _pump_rig(300000.0, 4.0, 320000.0) != 0.0:
		problems.append("pump did not dead-head")
	var one := _parallel_pumps(1)
	var two := _parallel_pumps(2)
	if not (two > one and two < 2.0 * one):
		problems.append("parallel pumps: one %.2f, two %.2f" % [one, two])

	# Two vessels and a pipe: the raised one empties into the low one
	# with no pump anywhere, and nothing is lost on the way.
	var sim := Simulation.new(SIM_DT)
	var full := sim.add(SimTank.new("full", 2000.0, 1800.0, 0.0, 3.0, 0.0, 0.0, 5.0)) as SimTank
	var low := sim.add(SimTank.new("low", 2000.0, 0.0, 0.0, 3.0)) as SimTank
	sim.connect_ports(full, "outlet", low, "inlet")
	sim.run_for(200.0)
	if low.level_l < 50.0 or full.level_l >= 1800.0:
		problems.append("raised tank did not drain into the low one")
	if absf(full.level_l + low.level_l - 1800.0) > 0.5:
		problems.append("gravity transfer lost material")

	# Both at grade, the receiving nozzle above the source's level:
	# nothing moves, and nothing should.
	sim = Simulation.new(SIM_DT)
	var src_t := sim.add(SimTank.new("a", 500.0, 400.0, 0.0, 2.0)) as SimTank
	var dst_t := sim.add(SimTank.new("b", 500.0, 0.0, 0.0, 2.0)) as SimTank
	sim.connect_ports(src_t, "outlet", dst_t, "inlet")
	sim.run_for(200.0)
	if dst_t.level_l > 0.1 or absf(src_t.level_l - 400.0) > 0.1:
		problems.append("gravity ran uphill")

	# Header -> pump -> tank -> drain: the header meters what was
	# pulled, the drain runs faster under more head, and mass closes.
	sim = Simulation.new(SIM_DT)
	var header := sim.add(SimSource.new("hdr")) as SimSource
	var pump := sim.add(SimPump.new("p", 3.0, "hand")) as SimPump
	var tank_ := sim.add(SimTank.new("t", 4000.0, 0.0, 0.0, 3.0)) as SimTank
	var drain := sim.add(SimDrain.new("d", 2.0)) as SimDrain
	var mains := sim.add(SimMainsFeed.new("m")) as SimMainsFeed
	sim.connect_ports(mains, "power", pump, "power")
	sim.connect_ports(header, "outlet", pump, "inlet")
	sim.connect_ports(pump, "outlet", tank_, "inlet")
	sim.connect_ports(tank_, "outlet", drain, "inlet")
	sim.run_for(20.0)
	var shallow := drain.flow_lps
	sim.run_for(400.0)
	var deep := drain.flow_lps
	if not (tank_.depth_m > 0.5 and deep > shallow * 1.5):
		problems.append("drain did not run faster under more head (%.2f -> %.2f)" % [shallow, deep])
	if header.total_l < 100.0 or absf(header.total_l - (tank_.level_l + drain.total_l)) > 0.5:
		problems.append("header -> tank -> drain does not close (%.1f fed, %.1f accounted)"
			% [header.total_l, tank_.level_l + drain.total_l])
	if sim.network().residual_lps > SimNetwork.TOLERANCE_LPS:
		problems.append("plant solve left a residual of %.5f L/s" % sim.network().residual_lps)

	# A pump cannot fill a tank taller than its head: the motor turns
	# and nothing moves.
	sim = Simulation.new(SIM_DT)
	var low_hdr := sim.add(SimSource.new("hdr", "water", 20.0, 0.0)) as SimSource
	var weak := sim.add(SimPump.new("p", 3.0, "hand", 4.0)) as SimPump
	var tower := sim.add(SimTank.new("tower", 8000.0, 0.0, 0.0, 20.0)) as SimTank
	var mains2 := sim.add(SimMainsFeed.new("m")) as SimMainsFeed
	sim.connect_ports(mains2, "power", weak, "power")
	sim.connect_ports(low_hdr, "outlet", weak, "inlet")
	sim.connect_ports(weak, "outlet", tower, "inlet")
	sim.run_for(60.0)
	if not (weak.running and weak.flow_lps < 0.01):
		problems.append("pump lifted past its head (%.2f L/s)" % weak.flow_lps)

	# The valve equation: half open is more than half the flow, because
	# flow follows the square root of the drop, not the position.
	var wide := _valve_flow(100.0)
	var half := _valve_flow(50.0)
	if not (wide > 0.5 and half > wide * 0.5 and half < wide):
		problems.append("valve: wide open %.2f, half %.2f" % [wide, half])

	# Composition follows flow: two headers into one vessel blend.
	sim = Simulation.new(SIM_DT)
	var hot := sim.add(SimSource.new("hot", "solvent", 80.0, 300.0)) as SimSource
	var cold := sim.add(SimSource.new("cold", "water", 20.0, 300.0)) as SimSource
	var blend := sim.add(SimTank.new("t", 8000.0, 0.0, 0.0, 4.0)) as SimTank
	sim.connect_ports(hot, "outlet", blend, "inlet")
	sim.connect_ports(cold, "outlet", blend, "inlet")
	sim.run_for(120.0)
	var x_solv := blend.contents.frac(SimSpecies.SOLVENT)
	if not (x_solv > 0.2 and x_solv < 0.8 and blend.temp_c > 20.0 and blend.temp_c < 80.0):
		problems.append("two headers did not blend (%.2f solvent, %.1f C)" % [x_solv, blend.temp_c])

	if problems.is_empty():
		print("[flowstate] hydraulics self-check OK — tees split, pumps dead-head, gravity drains, valves follow the square root, mass closes")
	else:
		push_warning("[flowstate] hydraulics self-check FAILED — %s" % "; ".join(problems))


func _pump_rig(head_pa: float, max_lps: float, lift_pa: float) -> float:
	var net := SimNetwork.new()
	var suction := net.add_node(0.0, true)
	var discharge := net.add_node(lift_pa, true)
	var pump := net.add_branch(SimPumpCurve.new(suction, discharge, head_pa, max_lps)) as SimPumpCurve
	pump.running = true
	net.solve()
	return pump.flow_lps


## Both pumps ride up their curves against the extra line loss, so the
## second one buys far less than the first.
func _parallel_pumps(count: int) -> float:
	var net := SimNetwork.new()
	var suction := net.add_node(0.0, true)
	var header := net.add_node()
	var outlet := net.add_node(0.0, true)
	for _i in count:
		var pump := net.add_branch(SimPumpCurve.new(suction, header, 300000.0, 4.0)) as SimPumpCurve
		pump.running = true
	var line := net.add_branch(SimResistance.new(header, outlet, 20000.0))
	net.solve()
	return line.flow_lps


## Header -> control valve -> tank, with the command wired from a hand
## controller in manual, because an input port resets every scan.
func _valve_flow(command: float) -> float:
	var sim := Simulation.new(SIM_DT)
	var header := sim.add(SimSource.new("hdr", "water", 20.0, 300.0)) as SimSource
	var valve := sim.add(SimControlValve.new("v", 6.0, 0.2)) as SimControlValve
	var tank_ := sim.add(SimTank.new("t", 9000.0, 0.0, 0.0, 4.0)) as SimTank
	var hand := sim.add(SimPID.new("hic", 0.0, 0.0, 0.0, 0.0, 0.0, 100.0)) as SimPID
	hand.set_mode("manual")
	hand.manual_out = command
	sim.connect_ports(hand, "out", valve, "cmd")
	sim.connect_ports(header, "outlet", valve, "inlet")
	sim.connect_ports(valve, "outlet", tank_, "inlet")
	sim.run_for(20.0)
	return valve.flow_lps


## Mirrors the Python stream tests: material has to be conserved when
## streams merge, a vessel has to blend what arrives into what it holds,
## and — the part save/load can quietly break — composition and
## temperature have to survive a state round-trip. A tank that forgets
## what is in it after a reload is the worst kind of bug, because
## everything still runs and only the numbers are wrong.
func _stream_self_check() -> void:
	var problems: Array[String] = []

	# Mixing conserves each species, and blends temperature by flow.
	var hot := SimStream.pure(SimSpecies.SOLVENT, 2.0, 80.0)
	var cold := SimStream.pure(SimSpecies.WATER, 6.0, 20.0)
	var mixed := SimStream.mix(hot, cold)
	if absf(mixed.flow_lps - 8.0) > 1e-4:
		problems.append("mixing lost flow")
	if absf(mixed.temp_c - 35.0) > 1e-3:
		problems.append("mixing got the temperature wrong")
	if absf(mixed.species_lps(SimSpecies.SOLVENT) - 2.0) > 1e-4 \
			or absf(mixed.species_lps(SimSpecies.WATER) - 6.0) > 1e-4:
		problems.append("mixing lost a species")

	# A vessel blends what arrives into what it holds.
	var check := Simulation.new(SIM_DT)
	var vessel := check.add(SimTank.new("v", 4000.0)) as SimTank
	var charge := SimStream.zero_amounts()
	charge[SimSpecies.WATER] = 1.0
	vessel.charge(1000.0, charge, 20.0)
	for _i in 200:  # 10 s of hot solvent at 10 L/s, stood at the nozzle
		# the way the hydraulic pass leaves it: the node stream plus a
		# signed rate into the vessel.
		vessel.inlet.stream = SimStream.pure(SimSpecies.SOLVENT, 10.0, 80.0)
		vessel.inlet.flow_lps = 10.0
		vessel.tick(SIM_DT)
	if absf(vessel.level_l - 1100.0) > 1.0:
		problems.append("vessel inventory drifted while filling")
	if absf(vessel.contents.frac(SimSpecies.SOLVENT) - 100.0 / 1100.0) > 0.01:
		problems.append("vessel did not blend the incoming composition")
	if vessel.temp_c <= 20.5 or vessel.temp_c >= 80.0:
		problems.append("hot feed did not warm the vessel")

	# Composition survives a save/load round-trip.
	var before := vessel.contents
	var restored := SimTank.new("v2", 4000.0)
	restored.apply_state(vessel.state_dict())
	if absf(restored.level_l - vessel.level_l) > 1e-4:
		problems.append("level lost in round-trip")
	if absf(restored.temp_c - before.temp_c) > 1e-3:
		problems.append("temperature lost in round-trip")
	for i in SimSpecies.COUNT:
		if absf(restored.contents.frac(i) - before.frac(i)) > 1e-3:
			problems.append("composition lost in round-trip")
			break

	if problems.is_empty():
		print("[flowstate] stream self-check OK — mixing conserves, vessels blend, composition survives save/load")
	else:
		push_warning("[flowstate] stream self-check FAILED — %s" % ", ".join(problems))


## Mirrors the Python control tests: a PID level loop must settle on
## setpoint, and a ladder seal-in must latch and drop.
func _control_self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var tank_ := check.add(SimTank.new("t", 200.0, 50.0, 2.0)) as SimTank
	var lt := check.add(SimGauge.new("lt", "level_kpa")) as SimGauge
	var lic := check.add(SimPID.new("lic", 8.0, 1.5, 0.0, 15.0)) as SimPID
	var lv := check.add(SimControlValve.new("lv", 6.0)) as SimControlValve
	var header := check.add(SimSource.new("uh")) as SimSource
	check.connect_ports(header, "outlet", lv, "inlet")
	check.connect_ports(tank_, "level", lt, "process")
	check.connect_ports(lt, "signal", lic, "pv")
	check.connect_ports(lic, "out", lv, "cmd")
	check.connect_ports(lv, "outlet", tank_, "inlet")
	check.run_for(600.0)
	var level_kpa := tank_.level_l / 45.45 * SimGauge.WATER_KPA_PER_M

	var plc := SimPLC.new("plc")
	plc.power.value = 1.0  # direct-tick check: energize the rack
	var err := plc.set_program([
		{"coil": "m_0", "logic": [
			[{"ref": "di_0"}, {"ref": "di_1", "nc": true}],
			[{"ref": "m_0"}, {"ref": "di_1", "nc": true}]]},
		{"coil": "do_0", "logic": [[{"ref": "m_0"}]]},
	])
	plc.di_ports[0].value = 1.0
	plc.tick(SIM_DT)
	plc.di_ports[0].value = 0.0
	plc.tick(SIM_DT)
	var sealed := plc.do_ports[0].value > 0.5
	plc.di_ports[1].value = 1.0
	plc.tick(SIM_DT)
	var dropped := plc.do_ports[0].value < 0.5

	if absf(level_kpa - 15.0) < 0.3 and absf(lv.flow_lps - 2.0) < 0.15 \
			and err == "" and sealed and dropped:
		print("[flowstate] control self-check OK — PID holds %.1f kPa, ladder seals and drops"
			% level_kpa)
	else:
		push_warning("[flowstate] control self-check FAILED — level %.2f kPa, flow %.2f, err '%s', sealed %s, dropped %s"
			% [level_kpa, lv.flow_lps, err, sealed, dropped])


## Headless support-rule exercise. Physics space queries see nothing
## during _ready (colliders land in the space a frame later), so this
## runs in two phases from _physics_process: phase 1 checks an open
## span and places test structure; phase 2 checks the braced span and
## the structure bearing rules, then cleans up.
func _exercise_supports() -> void:
	var space := get_world_3d().direct_space_state
	# A lane clear of incidental support in both worlds: sandbox pad is
	# bare there, and the hall's column grid (x/z multiples of 8) and
	# mezzanine posts all miss the z=4 line within x in [-4, 4].
	var origin := to_global(Vector3(0.0, -0.08, 4.0))
	var run: Array[Vector3] = [origin + Vector3(-4, 2, 0), origin + Vector3(4, 2, 0)]
	if _support_exercise_phase == 1:
		var open_check := SupportCheck.evaluate(run, space)
		if bool(open_check["ok"]):
			push_warning("[flowstate] support exercise FAILED: 8 m air span passed (max span %.2f)"
				% float(open_check["max_span"]))
			_support_exercise_phase = 0
			return
		place_structure("s_column", "chk_col_1", origin + Vector3(-1.4, 0, 0), 0.0)
		place_structure("s_column", "chk_col_2", origin + Vector3(1.4, 0, 0), 0.0)
		place_structure("s_column", "chk_col_3", origin + Vector3(-2.8, 0, 4), 0.0)
		place_structure("s_column", "chk_col_4", origin + Vector3(2.8, 0, 4), 0.0)
		_support_exercise_phase = 2
		_support_exercise_wait = 4
		return
	var problems: Array[String] = []
	var braced_check := SupportCheck.evaluate(run, space)
	if not bool(braced_check["ok"]):
		problems.append("braced span still failed (max span %.2f)" % float(braced_check["max_span"]))
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space) != "":
		problems.append("beam across two columns was refused")
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space, 5.8) != "":
		problems.append("stretched 5.8 m beam across columns was refused")
	# The interactive flow seats beams center-to-center: length equals
	# the column spacing exactly. Must bear (regression: the 0.2 m end
	# inset used to miss the 0.35 m column with a hairline ray).
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 4), 0.0, space, 5.6) != "":
		problems.append("center-to-center beam across columns was refused")
	if StructureFactory.placement_ok("s_beam", origin + Vector3(0, 6.0, 8), 0.0, space) == "":
		problems.append("floating beam was accepted")
	if _support_exercise_phase == 2:
		if not problems.is_empty():
			push_warning("[flowstate] support exercise FAILED: " + "; ".join(problems))
			_support_exercise_phase = 0
			return
		# Lay a floor-hugging cable tray; next phase, conduit strung
		# above it must count the tray as its support.
		place_run("run_tray", "chk_tray",
			[to_local(origin + Vector3(-3.6, 0.42, 2)), to_local(origin + Vector3(3.6, 0.42, 2))])
		_support_exercise_phase = 3
		_support_exercise_wait = 4
		return
	var tray_view := (runs["chk_tray"] as Dictionary)["node"] as PipeView
	var conduit: Array[Vector3] = [origin + Vector3(-3.5, 0.95, 2), origin + Vector3(3.5, 0.95, 2)]
	var over_tray := SupportCheck.evaluate(conduit, space)
	if not bool(over_tray["ok"]):
		problems.append("conduit over the tray was not supported by it")
	var without_tray := SupportCheck.evaluate(conduit, space, tray_view.collider_rids())
	if bool(without_tray["ok"]):
		problems.append("conduit counted something other than the tray as support")
	if not remove_placed_run(tray_view):
		problems.append("tray cleanup failed")
	for chk in ["chk_col_1", "chk_col_2", "chk_col_3", "chk_col_4"]:
		if not remove_structure(chk):
			problems.append("structure cleanup failed")
	_support_exercise_phase = 0
	if problems.is_empty():
		print("[flowstate] support exercise OK — spans, bearings, and tray-as-support all behave")
	else:
		push_warning("[flowstate] support exercise FAILED: " + "; ".join(problems))


## ---- save / load ---------------------------------------------------------

func save_game() -> bool:
	var comps: Array[Dictionary] = []
	for name_: String in views:
		if member_of.has(name_):
			continue  # cabinet members are saved with their cabinet
		var record := sim.get_component(name_)
		var view: Node3D = views[name_]
		var comp_entry := {
			"type": equip_types[name_],
			"name": name_,
			"state": record.state_dict(),
			"params": _params_for(record),
			"pos": [view.global_position.x, view.global_position.y
				- PlantFactory.Y_OFFSETS.get(equip_types[name_], 0.0), view.global_position.z],
			"rot_y": view.rotation.y,
			"protected": protected.has(name_),
		}
		if view is TankView:
			comp_entry["nozzles"] = (view as TankView).get_nozzles()
		if mounted.has(name_):
			comp_entry["mount"] = (mounted[name_] as Dictionary).duplicate()
		comps.append(comp_entry)
	var wire_list: Array = []
	for visual in _wire_visuals:
		var path_out: Array = []
		for point: Vector3 in visual["waypoints"]:
			path_out.append([point.x, point.y, point.z])
		var wire_entry := {
			"src": visual["a"], "src_port": visual["a_port"],
			"dst": visual["b"], "dst_port": visual["b_port"],
			"waypoints": path_out,
			"color": visual.get("color", ""), "label": visual.get("label", ""),
			"hidden": visual.get("hidden", false),
		}
		var wire := sim.find_wire(sim.get_component(str(visual["a"])), str(visual["a_port"]),
			sim.get_component(str(visual["b"])), str(visual["b_port"]))
		if wire != null and wire.is_material() and wire.k_pa_per_lps2 != SimWire.DEFAULT_K:
			wire_entry["k"] = wire.k_pa_per_lps2
		wire_list.append(wire_entry)
	var struct_list: Array = []
	for name_: String in structures:
		var entry: Dictionary = structures[name_]
		var node := entry["node"] as Node3D
		var size: Vector3 = StructureFactory.SIZES[entry["type"]]
		var base := node.global_position - Vector3(0, size.y / 2.0, 0)
		struct_list.append({
			"type": entry["type"], "name": name_,
			"pos": [base.x, base.y, base.z], "rot_y": node.rotation.y,
			"length": entry.get("length", -1.0), "text": entry.get("text", ""),
		})
	var run_list: Array = []
	for name_: String in runs:
		var entry: Dictionary = runs[name_]
		var pts: Array = []
		for point: Vector3 in entry["points"]:
			pts.append([point.x, point.y, point.z])
		run_list.append({"kind": entry["kind"], "name": name_, "points": pts,
			"color": entry.get("color", ""), "label": entry.get("label", "")})
	var cab_list: Array = []
	for name_: String in cabinets:
		var entry: Dictionary = cabinets[name_]
		var node := entry["node"] as Node3D
		var module_list: Array = []
		var states := {}
		for module_v: Variant in entry["modules"]:
			var module := module_v as Dictionary
			module_list.append({"id": module["id"], "type": module["type"],
				"rail": module["rail"], "slot": module["slot"], "bank": module["bank"]})
			for record_name: String in module["records"]:
				var record := sim.get_component(record_name)
				if record != null:
					var state := record.state_dict()
					if not state.is_empty():
						states[record_name] = state
		cab_list.append({
			"name": name_,
			"pos": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rot_y": node.rotation.y,
			"modules": module_list, "states": states,
		})
	var payload := {
		"version": SAVE_VERSION, "time": sim.time,
		"components": comps, "wires": wire_list, "structures": struct_list,
		"runs": run_list, "cabinets": cab_list,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	return true


func _params_for(record: SimComponent) -> Dictionary:
	if record is SimTank:
		var tank_rec := record as SimTank
		return {"height_m": tank_rec.height_m, "diameter_m": tank_rec.diameter_m,
			"nozzle_cv_lps": tank_rec.nozzle_cv_lps}
	if record is SimPump:
		var pump_rec := record as SimPump
		return {"rated_lps": pump_rec.rated_lps, "head_m": pump_rec.head_m}
	if record is SimFloatSwitch:
		var fs := record as SimFloatSwitch
		return {"low_l": fs.low_l, "high_l": fs.high_l}
	if record is SimGauge:
		var g := record as SimGauge
		return {"liters_per_meter": g.liters_per_meter, "species": g.species_key(), "meter_k": g.meter_k}
	if record is SimColumn:
		var col := record as SimColumn
		return {"charge_l": col.charge_l, "max_duty_kw": col.max_duty_kw}
	if record is SimControlValve:
		var cvalve := record as SimControlValve
		return {"cv_lps": cvalve.cv_lps, "tau_s": cvalve.tau_s}
	if record is SimBlockValve:
		var xv := record as SimBlockValve
		return {"cv_lps": xv.cv_lps, "stroke_s": xv.stroke_s}
	if record is SimPID:
		var pid := record as SimPID
		return {"kp": pid.kp, "ki": pid.ki, "kd": pid.kd, "sp": pid.sp,
			"out_min": pid.out_min, "out_max": pid.out_max}
	if record is SimTerminal:
		return {"kind": (record as SimTerminal).kind}
	if record is SimDrain:
		return {"rate_lps": (record as SimDrain).rate_lps}
	if record is SimReactor:
		var reac := record as SimReactor
		return {"capacity_l": reac.capacity_l, "rate_lps": reac.rate_lps,
			"height_m": reac.height_m}
	if record is SimCentrifuge:
		return {"rate_lps": (record as SimCentrifuge).rate_lps}
	if record is SimHeatExchanger:
		return {"max_duty_kw": (record as SimHeatExchanger).max_duty_kw}
	if record is SimSteamGen:
		return {"rated_kgps": (record as SimSteamGen).rated_kgps}
	if record is SimSource:
		var src := record as SimSource
		return {"species": src.species_key(), "temp_c": src.temp_c,
			"pressure_kpa": src.pressure_kpa}
	if record is SimCrystallizer:
		var cx := record as SimCrystallizer
		return {"capacity_l": cx.capacity_l, "height_m": cx.height_m}
	if record is SimDryer:
		return {"rate_lps": (record as SimDryer).rate_lps}
	if record is SimStill:
		var st := record as SimStill
		return {"rate_lps": st.rate_lps, "cut_c": st.cut_c, "sharpness": st.sharpness}
	return {}


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) < 3:
		return false
	var payload := parsed as Dictionary

	for name_: String in views:
		if not member_of.has(name_):  # members share the cabinet node
			(views[name_] as Node).queue_free()
	for visual in _wire_visuals:
		if visual["node"] != null:
			(visual["node"] as Node).queue_free()
	for name_: String in structures:
		((structures[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in runs:
		((runs[name_] as Dictionary)["node"] as Node).queue_free()
	for name_: String in cabinets:
		((cabinets[name_] as Dictionary)["node"] as Node).queue_free()
	views.clear()
	equip_types.clear()
	protected.clear()
	structures.clear()
	runs.clear()
	cabinets.clear()
	member_of.clear()
	mounted.clear()
	_wire_visuals.clear()
	_new_graph()

	for entry: Dictionary in payload.get("cabinets", []):
		var pos_arr: Array = entry["pos"]
		place_cabinet(entry["name"],
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]), float(entry.get("rot_y", 0.0)))
		for module_v: Variant in entry.get("modules", []):
			var module := module_v as Dictionary
			cabinet_add_module(entry["name"], str(module["type"]),
				int(module["rail"]), int(module["slot"]),
				str(module["id"]), int(module.get("bank", -1)))
		var states: Dictionary = entry.get("states", {})
		for record_name: String in states:
			var record := sim.get_component(record_name)
			if record != null:
				record.apply_state(states[record_name])

	for entry: Dictionary in payload.get("runs", []):
		var pts: Array = []
		for point: Array in entry["points"]:
			pts.append(Vector3(point[0], point[1], point[2]))
		place_run(entry["kind"], entry["name"], pts)
		if str(entry.get("color", "")) != "":
			set_run_service((runs[entry["name"]] as Dictionary)["node"] as PipeView,
				Color.html(str(entry["color"])), str(entry.get("label", "")))

	for entry: Dictionary in payload.get("structures", []):
		var pos_arr: Array = entry["pos"]
		place_structure(entry["type"], entry["name"],
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]), float(entry.get("rot_y", 0.0)),
			float(entry.get("length", -1.0)))
		if str(entry.get("text", "")) != "":
			set_sign_text(entry["name"], str(entry["text"]))

	for entry: Dictionary in payload["components"]:
		if entry.has("mount"):
			continue  # after its host
		var pos_arr: Array = entry["pos"]
		var record := place(entry["type"], entry["name"], entry.get("params", {}),
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
			var loaded_view: Node3D = views.get(entry["name"])
			if loaded_view is TankView:
				(loaded_view as TankView).rebuild()  # sized by restored state
				if entry.has("nozzles"):
					(loaded_view as TankView).apply_nozzles(entry["nozzles"])
	for entry: Dictionary in payload["components"]:
		if not entry.has("mount"):
			continue
		var spot: Dictionary = entry["mount"]
		var record := mount_instrument(entry["type"], entry["name"], entry.get("params", {}),
			str(spot["host"]), float(spot["frac"]), float(spot["angle"]),
			bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
	for wire_entry: Dictionary in payload["wires"]:
		var waypoints: Array = []
		for point: Array in wire_entry.get("waypoints", []):
			waypoints.append(Vector3(point[0], point[1], point[2]))
		var error := connect_equipment(wire_entry["src"], wire_entry["src_port"],
			wire_entry["dst"], wire_entry["dst_port"], waypoints,
			not bool(wire_entry.get("hidden", false)))
		if error == "" and str(wire_entry.get("color", "")) != "":
			set_run_service((_wire_visuals[_wire_visuals.size() - 1] as Dictionary)["node"] as PipeView,
				Color.html(str(wire_entry["color"])), str(wire_entry.get("label", "")))
		if error == "" and wire_entry.has("k"):
			set_pipe_resistance(wire_entry["src"], wire_entry["src_port"],
				wire_entry["dst"], wire_entry["dst_port"], float(wire_entry["k"]))
	sim.time = float(payload.get("time", 0.0))

	tank = sim.get_component("supply_tank") as SimTank
	switch = sim.get_component("level_switch") as SimFloatSwitch
	relay = sim.get_component("pump_relay") as SimRelay
	pump = sim.get_component("fill_pump") as SimPump
	if hmi_view != null and tank != null:
		hmi_view.panel.setup(historian, tank, switch, relay, pump)
	return true
