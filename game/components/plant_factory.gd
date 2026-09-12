class_name PlantFactory
## One place that knows how to make each equipment type: sim record,
## view, placement footprint, and where its port markers sit. Both the
## commissioned starting plant and player placement go through here, so
## save/load can rebuild anything.

const CATALOG: Array[Dictionary] = [
	{"type": "tank", "label": "Tank 100 L"},
	{"type": "pump", "label": "Pump 4 L/s"},
	{"type": "reactor", "label": "Stirred reactor"},
	{"type": "hx", "label": "Heat exchanger"},
	{"type": "steamgen", "label": "Steam generator"},
	{"type": "vialfill", "label": "Vial filler (isolator)"},
]

const CATALOG_SEPARATION: Array[Dictionary] = [
	{"type": "crystallizer", "label": "Crystallizer"},
	{"type": "centrifuge", "label": "Centrifuge"},
	{"type": "dryer", "label": "Cake dryer"},
	{"type": "still", "label": "Recovery still"},
	{"type": "column", "label": "Batch column"},
]

const CATALOG_UTILITIES: Array[Dictionary] = [
	{"type": "source", "label": "Supply header"},
	{"type": "drain", "label": "Drain / sewer"},
	{"type": "vaclock", "label": "Vacuum lock"},
]

const CATALOG_INSTRUMENTS: Array[Dictionary] = [
	{"type": "float_switch", "label": "Level switch"},
	{"type": "gauge_level", "label": "Level gauge"},
	{"type": "gauge_flow", "label": "Flow gauge"},
	{"type": "gauge_dp", "label": "DP gauge"},
	{"type": "gauge_press", "label": "Pressure gauge"},
	{"type": "gauge_temp", "label": "Temperature gauge"},
	{"type": "gauge_conc", "label": "Purity analyser"},
	{"type": "controller", "label": "PID controller"},
]

const CATALOG_CONTROL: Array[Dictionary] = [
	{"type": "valve", "label": "Control valve"},
	{"type": "block_valve", "label": "Block valve (on/off)"},
	{"type": "relay", "label": "Relay cabinet"},
	{"type": "cabinet", "label": "Control cabinet"},
	{"type": "junction_box", "label": "Junction box"},
	{"type": "control_station", "label": "Control station"},
	{"type": "mains", "label": "Mains feeder 480VAC"},
	{"type": "psu", "label": "Power supply 24VDC"},
]

# Ghost/collision footprint (x, y, z) and the view's y-offset when the
# placement point is on the floor.
const FOOTPRINTS := {
	"tank": Vector3(1.8, 2.3, 1.8),
	"pump": Vector3(0.85, 0.95, 0.7),
	"relay": Vector3(1.0, 2.2, 0.55),
	"gauge_level": Vector3(0.5, 1.8, 0.5),
	"gauge_flow": Vector3(0.5, 1.8, 0.5),
	"gauge_dp": Vector3(0.5, 1.8, 0.5),
	"gauge_press": Vector3(0.5, 1.8, 0.5),
	"column": Vector3(1.7, 11.2, 1.7),
	"float_switch": Vector3(0.25, 0.6, 0.25),
	"valve": Vector3(0.7, 1.3, 0.55),
	"block_valve": Vector3(0.7, 1.1, 0.55),
	"controller": Vector3(0.5, 1.9, 0.5),
	"cabinet": Vector3(1.4, 2.1, 0.75),
	"junction_box": Vector3(0.5, 1.7, 0.3),
	"control_station": Vector3(0.6, 1.6, 0.3),
	"mains": Vector3(0.85, 1.85, 0.65),
	"psu": Vector3(0.65, 1.6, 0.45),
	"source": Vector3(0.75, 1.9, 0.75),
	"drain": Vector3(0.95, 0.5, 0.95),
	"reactor": Vector3(1.8, 3.1, 1.8),
	"centrifuge": Vector3(1.2, 1.8, 1.2),
	"hx": Vector3(2.0, 1.0, 0.8),
	"steamgen": Vector3(2.1, 2.8, 1.3),
	"vaclock": Vector3(1.5, 2.9, 1.4),
	"vialfill": Vector3(2.5, 2.5, 1.2),
	"gauge_temp": Vector3(0.5, 1.8, 0.5),
	"gauge_conc": Vector3(0.5, 1.8, 0.5),
	"crystallizer": Vector3(1.7, 2.7, 1.7),
	"dryer": Vector3(1.7, 1.7, 1.3),
	"still": Vector3(1.5, 7.0, 1.5),
}
const Y_OFFSETS := {
	"tank": 0.0, "pump": 0.0, "relay": 1.5,
	"gauge_level": 0.0, "gauge_flow": 0.0, "gauge_dp": 0.0,
	"gauge_press": 0.0, "column": 0.0,
	"float_switch": 0.0, "air_cascade": 0.0,
	"valve": 0.0, "block_valve": 0.0, "controller": 0.0, "cabinet": 0.0, "junction_box": 0.0,
	"control_station": 0.0,
	"mains": 0.0, "psu": 0.0, "source": 0.0, "drain": 0.0,
	"reactor": 0.0, "centrifuge": 0.0, "hx": 0.0, "steamgen": 0.0,
	"vaclock": 0.0, "vialfill": 0.0,
	"gauge_temp": 0.0, "gauge_conc": 0.0,
	"crystallizer": 0.0, "dryer": 0.0, "still": 0.0,
}

# Where each port's fitting sits in the view's local space, flush with
# the equipment body. Entries are either a bare Vector3 (outward
# direction derived radially) or {"pos": ..., "dir": ...} when the
# mounting face isn't radial.
const PORT_ANCHORS := {
	# Tank anchors are unused — TankView builds its own movable nozzles.
	"pump": {
		"inlet": {"pos": Vector3(-0.25, 0.42, 0), "dir": Vector3.LEFT},
		"outlet": {"pos": Vector3(0.25, 0.42, 0), "dir": Vector3.RIGHT},
		"run": {"pos": Vector3(0.02, 0.44, 0.16), "dir": Vector3.BACK},
		"power": {"pos": Vector3(-0.15, 0.18, -0.25), "dir": Vector3.FORWARD}},
	"relay": {
		"coil": {"pos": Vector3(-0.13, -0.2, 0.09), "dir": Vector3.BACK},
		"contact": {"pos": Vector3(0.13, -0.2, 0.09), "dir": Vector3.BACK}},
	"float_switch": {
		"level": {"pos": Vector3(0, -0.26, 0), "dir": Vector3.DOWN},
		"contact": {"pos": Vector3(0.06, 0.05, 0), "dir": Vector3.RIGHT}},
	"gauge_level": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	# An inline meter: the line runs through the spool at its base.
	"gauge_flow": {
		"inlet": {"pos": Vector3(-0.25, 0.32, 0), "dir": Vector3.LEFT},
		"outlet": {"pos": Vector3(0.25, 0.32, 0), "dir": Vector3.RIGHT},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_dp": {
		"process_a": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"process_b": {"pos": Vector3(0, 0.45, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_press": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_temp": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_conc": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"valve": {
		"inlet": {"pos": Vector3(-0.31, 0.32, 0), "dir": Vector3.LEFT},
		"outlet": {"pos": Vector3(0.31, 0.32, 0), "dir": Vector3.RIGHT},
		"cmd": {"pos": Vector3(0, 0.98, 0.22), "dir": Vector3.BACK}},
	"block_valve": {
		"inlet": {"pos": Vector3(-0.31, 0.32, 0), "dir": Vector3.LEFT},
		"outlet": {"pos": Vector3(0.31, 0.32, 0), "dir": Vector3.RIGHT},
		"open": {"pos": Vector3(0, 0.72, 0.2), "dir": Vector3.BACK}},
	"source": {"outlet": {"pos": Vector3(0.5, 1.55, 0), "dir": Vector3.RIGHT}},
	"drain": {
		"inlet": {"pos": Vector3(0.46, 0.52, 0), "dir": Vector3.RIGHT}},
	"controller": {
		"pv": {"pos": Vector3(-0.14, 1.12, 0.07), "dir": Vector3.BACK},
		"out": {"pos": Vector3(0.14, 1.12, 0.07), "dir": Vector3.BACK}},
	"mains": {"power": {"pos": Vector3(0.35, 1.05, 0), "dir": Vector3.RIGHT}},
	"reactor": {
		"inlet_a": {"pos": Vector3(-0.42, 2.42, 0), "dir": Vector3.UP},
		"inlet_b": {"pos": Vector3(0.42, 2.42, 0), "dir": Vector3.UP},
		"heat_duty": {"pos": Vector3(0.83, 1.1, 0), "dir": Vector3.RIGHT},
		"power": {"pos": Vector3(0.2, 2.85, 0.18), "dir": Vector3.BACK},
		"purity": {"pos": Vector3(-0.77, 1.7, 0), "dir": Vector3.LEFT},
		"level": {"pos": Vector3(0, 1.0, -0.79), "dir": Vector3.FORWARD},
		"outlet": {"pos": Vector3(0.77, 0.5, 0), "dir": Vector3.RIGHT}},
	"centrifuge": {
		"inlet": {"pos": Vector3(0.16, 1.4, 0), "dir": Vector3.UP},
		"power": {"pos": Vector3(0.16, 1.62, 0.14), "dir": Vector3.BACK},
		"product": {"pos": Vector3(0.49, 0.65, 0), "dir": Vector3.RIGHT},
		"waste": {"pos": Vector3(-0.49, 0.55, 0), "dir": Vector3.LEFT}},
	"crystallizer": {
		"inlet": {"pos": Vector3(-0.38, 2.1, 0), "dir": Vector3.UP},
		"cool_duty": {"pos": Vector3(0.78, 1.35, 0), "dir": Vector3.RIGHT},
		"power": {"pos": Vector3(0.2, 2.5, 0.18), "dir": Vector3.BACK},
		"solids": {"pos": Vector3(-0.72, 1.6, 0), "dir": Vector3.LEFT},
		"temp": {"pos": Vector3(-0.72, 1.1, 0), "dir": Vector3.LEFT},
		"level": {"pos": Vector3(0, 1.0, -0.74), "dir": Vector3.FORWARD},
		"outlet": {"pos": Vector3(0.72, 0.45, 0), "dir": Vector3.RIGHT}},
	"dryer": {
		"inlet": {"pos": Vector3(-0.76, 1.05, 0), "dir": Vector3.LEFT},
		"heat_duty": {"pos": Vector3(0.3, 0.35, 0.6), "dir": Vector3.BACK},
		"power": {"pos": Vector3(-0.3, 0.35, 0.6), "dir": Vector3.BACK},
		"product": {"pos": Vector3(0.76, 0.5, 0), "dir": Vector3.RIGHT}},
	"still": {
		"inlet": {"pos": Vector3(-0.68, 2.6, 0), "dir": Vector3.LEFT},
		"heat_duty": {"pos": Vector3(0.6, 0.7, 0.2), "dir": Vector3.RIGHT},
		"power": {"pos": Vector3(-0.55, 0.6, 0.3), "dir": Vector3.BACK},
		"distillate": {"pos": Vector3(0.66, 6.1, 0), "dir": Vector3.RIGHT},
		"bottoms": {"pos": Vector3(0.62, 0.4, 0), "dir": Vector3.RIGHT}},
	"hx": {
		"steam_in": {"pos": Vector3(-0.35, 0.74, 0), "dir": Vector3.UP},
		"cold_in": {"pos": Vector3(-0.97, 0.45, 0), "dir": Vector3.LEFT},
		"cold_out": {"pos": Vector3(0.97, 0.45, 0), "dir": Vector3.RIGHT},
		"duty": {"pos": Vector3(0.35, 0.45, 0.31), "dir": Vector3.BACK}},
	"steamgen": {
		"inlet": {"pos": Vector3(-1.05, 0.8, 0), "dir": Vector3.LEFT},
		"power": {"pos": Vector3(0.5, 0.35, 0.7), "dir": Vector3.BACK},
		"steam": {"pos": Vector3(0.35, 1.35, 0), "dir": Vector3.UP},
		"press": {"pos": Vector3(-0.2, 1.35, 0), "dir": Vector3.UP}},
	"vaclock": {
		"power": {"pos": Vector3(-0.75, 0.9, 0.26), "dir": Vector3.BACK},
		"press": {"pos": Vector3(0.42, 2.28, 0), "dir": Vector3.RIGHT},
		"drain_flow": {"pos": Vector3(0.36, 0.6, 0), "dir": Vector3.RIGHT}},
	"vialfill": {
		"inlet": {"pos": Vector3(-1.17, 0.6, 0), "dir": Vector3.LEFT},
		"power": {"pos": Vector3(1.17, 0.45, 0), "dir": Vector3.RIGHT}},
	"psu": {
		"ac_in": {"pos": Vector3(-0.25, 1.2, 0), "dir": Vector3.LEFT},
		"dc_out": {"pos": Vector3(0.25, 1.2, 0), "dir": Vector3.RIGHT}},
	# Overhead tap at the end of the vapor line; power lands on the
	# reboiler band.
	"column": {
		"p_top": {"pos": Vector3(0, 11.3, 1.08), "dir": Vector3.BACK},
		"power": {"pos": Vector3(0.63, 1.15, 0), "dir": Vector3.RIGHT}},
	# Pressure taps sit on the suite's walls, near the ceiling.
	"air_cascade": {
		"p_al1": Vector3(-23.5, 2.5, -4.35),
		"p_gown": Vector3(-26.8, 2.5, -3.35),
		"p_al2": Vector3(-29.9, 2.5, -4.35),
		"p_core": Vector3(-33.0, 2.5, -1.35),
		"p_iso": Vector3(-35.3, 2.3, -5.6),
	},
}

# Instruments that mount on a vessel's shell rather than stand on the
# floor. Their process input is the vessel's internal level tap, wired
# by the plant when they are mounted, so only the signal side gets a
# fitting. Anchors are in the mount frame: +x is outward from the shell.
const MOUNTABLE: Array[String] = ["float_switch", "gauge_level", "gauge_temp"]
const MOUNTED_ANCHORS := {
	"float_switch": {"contact": {"pos": Vector3(0.12, 0.05, 0), "dir": Vector3.RIGHT}},
	"gauge_level": {"signal": {"pos": Vector3(0.1, -0.2, 0), "dir": Vector3.DOWN}},
	"gauge_temp": {"signal": {"pos": Vector3(0.1, -0.2, 0), "dir": Vector3.DOWN}},
}
# The instrument's input the plant lands the hidden wire on, and the
# vessel's hidden tap it lands it from: level instruments read the
# level tap, a temperature probe reads the contents tap.
const MOUNTED_INPUT := {"float_switch": "level", "gauge_level": "process", "gauge_temp": "process"}
const MOUNTED_HOST_PORT := {"float_switch": "level", "gauge_level": "level", "gauge_temp": "contents"}

# One player pipe is one kernel wire: a material nozzle to a material
# nozzle, and the network decides what moves through it and which way.
# There is no facade pairing and no hidden draw wire any more.
const KIND_COLORS := {
	SimTypes.PortKind.SIGNAL_DISCRETE: Color(0.11, 0.69, 0.48),
	SimTypes.PortKind.SIGNAL_ANALOG: Color(0.92, 0.60, 0.10),
	SimTypes.PortKind.PROCESS_MATERIAL: Color(0.16, 0.47, 0.84),
	SimTypes.PortKind.PROCESS_LEVEL: Color(0.15, 0.65, 0.80),
	SimTypes.PortKind.PROCESS_PRESSURE: Color(0.58, 0.40, 0.85),
	SimTypes.PortKind.POWER: Color(0.55, 0.15, 0.12),
}


static func type_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in CATALOG:
		ids.append(entry["type"])
	return ids


static func make_record(sim: Simulation, type_id: String, name_: String,
		params: Dictionary) -> SimComponent:
	match type_id:
		"tank":
			return sim.add(SimTank.new(name_,
				params.get("capacity_l", 100.0),
				params.get("level_l", 0.0), params.get("drain_lps", 0.0),
				params.get("height_m", 0.0), params.get("diameter_m", 0.0),
				params.get("headspace_kpa", 0.0), params.get("elevation_m", 0.0),
				params.get("nozzle_cv_lps", SimTank.OUTLET_CV_LPS)))
		"pump":
			return sim.add(SimPump.new(name_, params.get("rated_lps", 4.0),
				params.get("mode", "auto"), params.get("head_m", 30.0)))
		"relay":
			return sim.add(SimRelay.new(name_))
		"float_switch":
			return sim.add(SimFloatSwitch.new(name_,
				params.get("low_l", 40.0), params.get("high_l", 80.0)))
		"gauge_level":
			return sim.add(SimGauge.new(name_, "level_kpa",
				params.get("liters_per_meter", 45.45)))
		"gauge_flow":
			return sim.add(SimGauge.new(name_, "flow", 45.45, "product",
				params.get("meter_k", SimGauge.METER_K)))
		"gauge_dp":
			return sim.add(SimGauge.new(name_, "dp_pa"))
		"gauge_press":
			return sim.add(SimGauge.new(name_, "press_kpa"))
		"gauge_temp":
			return sim.add(SimGauge.new(name_, "temp_c"))
		"gauge_conc":
			return sim.add(SimGauge.new(name_, "conc_pct", 45.45,
				params.get("species", "product")))
		"column":
			return sim.add(SimColumn.new(name_,
				params.get("charge_l", 60.0), params.get("max_duty_kw", 100.0)))
		"air_cascade":
			return sim.add(SimAirCascade.new(name_, AsepticSuite.ROOMS, AsepticSuite.DOORS))
		"valve":
			return sim.add(SimControlValve.new(name_,
				params.get("cv_lps", 6.0), params.get("tau_s", 1.0)))
		"block_valve":
			return sim.add(SimBlockValve.new(name_,
				params.get("cv_lps", 20.0), params.get("stroke_s", 4.0)))
		"controller":
			return sim.add(SimPID.new(name_,
				params.get("kp", 8.0), params.get("ki", 1.5), params.get("kd", 0.0),
				params.get("sp", 15.0),
				params.get("out_min", 0.0), params.get("out_max", 100.0)))
		"plc":
			return sim.add(SimPLC.new(name_,
				params.get("di", 8), params.get("do", 8),
				params.get("ai", 4), params.get("ao", 4)))
		"terminal":
			return sim.add(SimTerminal.new(name_, params.get("kind", "discrete")))
		"pushbutton":
			return sim.add(SimPushbutton.new(name_, params.get("momentary", true),
				params.get("normally_closed", false)))
		"pilot_light":
			return sim.add(SimPilotLight.new(name_, params.get("color", "green")))
		"mains":
			return sim.add(SimMainsFeed.new(name_, params.get("spec", "480VAC")))
		"psu":
			return sim.add(SimPowerSupply.new(name_))
		"source":
			return sim.add(SimSource.new(name_,
				params.get("species", "water"), params.get("temp_c", 20.0),
				params.get("pressure_kpa", 400.0), params.get("elevation_m", 0.0)))
		"drain":
			return sim.add(SimDrain.new(name_, params.get("rate_lps", 1.0),
				params.get("elevation_m", 0.0)))
		"reactor":
			return sim.add(SimReactor.new(name_,
				params.get("capacity_l", 4000.0), params.get("rate_lps", 6.0),
				params.get("height_m", 2.4), params.get("elevation_m", 0.0)))
		"centrifuge":
			return sim.add(SimCentrifuge.new(name_, params.get("rate_lps", 4.0)))
		"hx":
			return sim.add(SimHeatExchanger.new(name_, params.get("max_duty_kw", 1200.0)))
		"steamgen":
			return sim.add(SimSteamGen.new(name_, params.get("rated_kgps", 0.5)))
		"vaclock":
			return sim.add(SimVacuumLock.new(name_))
		"vialfill":
			return sim.add(SimVialFiller.new(name_))
		"crystallizer":
			return sim.add(SimCrystallizer.new(name_, params.get("capacity_l", 3000.0),
				params.get("height_m", 2.2), params.get("elevation_m", 0.0)))
		"dryer":
			return sim.add(SimDryer.new(name_, params.get("rate_lps", 2.0)))
		"still":
			return sim.add(SimStill.new(name_, params.get("rate_lps", 3.0),
				params.get("cut_c", 150.0), params.get("sharpness", 0.95)))
	push_error("unknown equipment type '%s'" % type_id)
	return null


static func make_view(type_id: String, record: SimComponent,
		extra: SimComponent = null) -> Node3D:
	var view: Node3D = null
	match type_id:
		"tank":
			view = TankView.new()
		"pump":
			view = PumpView.new()
		"relay":
			view = RelayView.new()
		"float_switch":
			view = FloatSwitchView.new()
		"gauge_level", "gauge_flow", "gauge_dp", "gauge_press", \
		"gauge_temp", "gauge_conc":
			view = GaugeView.new()
		"column":
			view = ColumnView.new()
		"valve":
			view = ControlValveView.new()
		"block_valve":
			view = BlockValveView.new()
		"controller":
			view = PIDView.new()
		"mains":
			view = MainsView.new()
		"psu":
			view = PsuView.new()
		"source":
			view = SourceView.new()
		"drain":
			view = DrainView.new()
		"reactor":
			view = ReactorView.new()
		"centrifuge":
			view = CentrifugeView.new()
		"hx":
			view = HeatExchangerView.new()
		"steamgen":
			view = SteamGenView.new()
		"vaclock":
			view = VacLockView.new()
		"vialfill":
			view = VialFillerView.new()
		"crystallizer":
			view = CrystallizerView.new()
		"dryer":
			view = DryerView.new()
		"still":
			view = StillView.new()
		"air_cascade":
			view = AsepticSuite.new()
	if view == null:
		push_error("unknown equipment type '%s'" % type_id)
		return null
	view.set_meta("type_id", type_id)
	view.set_meta("record_name", record.comp_name)
	return view


## The build-menu label of a type, for the journal and toasts.
static func label_for(type_id: String) -> String:
	for catalog: Array in [CATALOG, CATALOG_SEPARATION, CATALOG_INSTRUMENTS,
			CATALOG_CONTROL, CATALOG_UTILITIES]:
		for entry: Dictionary in catalog:
			if str(entry["type"]) == type_id:
				return str(entry["label"])
	return type_id


## Call after the view is in the tree and set up: builds the typed port
## markers connect mode clicks on (collision layer 2). Markers are
## keyed "record:port" and MERGED into the view's existing set, so one
## view (a cabinet) can carry markers for several records (its
## terminals). anchors_override positions ports the type table can't.
static func attach_port_markers(view: Node3D, record: SimComponent, type_id: String,
		anchors_override: Dictionary = {}, skip: Array[String] = []) -> void:
	# Every port the player can pipe gets a fitting. A record's hidden
	# ports (a vessel's internal level tap) and a mounted instrument's
	# process side (wired by the plant when it was mounted) get none.
	var anchors: Dictionary = PORT_ANCHORS.get(type_id, {})
	var markers: Dictionary = view.get_meta("port_markers", {})
	var hidden := record.hidden_ports()
	for port_name: String in record.inputs:
		if hidden.has(port_name) or skip.has(port_name):
			continue
		var kind: SimTypes.PortKind = (record.inputs[port_name] as SimInputPort).kind
		var raw: Variant = anchors_override.get(port_name,
			anchors.get(port_name, Vector3(0, 0.5, 0)))
		markers["%s:%s" % [record.comp_name, port_name]] = \
			make_marker(view, record.comp_name, port_name, kind,
				_anchor_pos(raw), true, _anchor_dir(raw))
	for port_name: String in record.outputs:
		if hidden.has(port_name) or skip.has(port_name):
			continue
		var raw: Variant = anchors_override.get(port_name,
			anchors.get(port_name, Vector3(0, 0.8, 0)))
		markers["%s:%s" % [record.comp_name, port_name]] = \
			make_marker(view, record.comp_name, port_name,
				(record.outputs[port_name] as SimOutputPort).kind,
				_anchor_pos(raw), false, _anchor_dir(raw))
	view.set_meta("port_markers", markers)


static func _anchor_pos(raw: Variant) -> Vector3:
	return (raw as Dictionary)["pos"] if raw is Dictionary else raw


static func _anchor_dir(raw: Variant) -> Vector3:
	return (raw as Dictionary).get("dir", Vector3.ZERO) if raw is Dictionary else Vector3.ZERO


## An attached fitting, not a floating primitive: process ports are
## flanged stub nozzles, signal and power ports are surface-mounted
## junction boxes with cable glands. A mounting plate seats against
## the equipment body; the fitting's local +X points outward along
## dir (derived radially when not given).
static func make_marker(view: Node3D, record_name: String, port_name: String,
		kind: SimTypes.PortKind, local_pos: Vector3, is_input: bool,
		dir: Vector3 = Vector3.ZERO) -> StaticBody3D:
	if dir == Vector3.ZERO:
		dir = Vector3(local_pos.x, 0.0, local_pos.z)
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.UP
	var color: Color = KIND_COLORS[kind]
	var body := StaticBody3D.new()
	body.position = local_pos
	body.collision_layer = 2
	body.collision_mask = 0
	var up_ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	var z_axis := dir.cross(up_ref).normalized()
	body.basis = Basis(dir, z_axis.cross(dir), z_axis)
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.11
	shape.shape = sphere_shape
	shape.position = Vector3(0.06, 0, 0)
	body.add_child(shape)

	var steel := ViewUtil.flat(Color(0.45, 0.47, 0.50))
	var is_pipe := SimTypes.is_material(kind) \
		or kind == SimTypes.PortKind.PROCESS_LEVEL \
		or kind == SimTypes.PortKind.PROCESS_PRESSURE
	if is_pipe:
		ViewUtil.box(body, Vector3(0.06, 0.15, 0.15), Vector3(-0.02, 0, 0), steel)
		var neck_r := 0.032
		if SimTypes.is_material(kind):
			neck_r = 0.05
		var neck := ViewUtil.cylinder(body, neck_r, 0.15, Vector3(0.07, 0, 0), steel)
		neck.rotation_degrees = Vector3(0, 0, 90)
		var flange := ViewUtil.cylinder(body, neck_r * 1.8, 0.03, Vector3(0.145, 0, 0), steel)
		flange.rotation_degrees = Vector3(0, 0, 90)
		# Colored gasket face: a ring on inlets, a solid cap on outlets.
		var face := ViewUtil.cylinder(body, neck_r * (1.35 if is_input else 1.1), 0.02,
			Vector3(0.165, 0, 0), ViewUtil.glow(color, 0.8))
		face.rotation_degrees = Vector3(0, 0, 90)
	else:
		ViewUtil.box(body, Vector3(0.05, 0.13, 0.13), Vector3(-0.015, 0, 0), steel)
		ViewUtil.box(body, Vector3(0.09, 0.10, 0.10), Vector3(0.05, 0, 0),
			ViewUtil.flat(Color(0.28, 0.29, 0.32)))
		var gland := ViewUtil.cylinder(body, 0.022, 0.06, Vector3(0.115, 0, 0), steel)
		gland.rotation_degrees = Vector3(0, 0, 90)
		var collar := ViewUtil.cylinder(body, 0.036 if is_input else 0.03, 0.02,
			Vector3(0.10, 0, 0), ViewUtil.glow(color, 0.9))
		collar.rotation_degrees = Vector3(0, 0, 90)

	var tag := Label3D.new()
	tag.text = port_name
	tag.position = Vector3(0.08, 0.16, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 24
	tag.pixel_size = 0.0028
	body.add_child(tag)
	body.set_meta("record_name", record_name)
	body.set_meta("port_name", port_name)
	body.set_meta("is_input", is_input)
	body.set_meta("kind", kind)
	body.set_meta("owner_view", view)
	view.add_child(body)
	return body


## What a device's right-click CONFIGURE tab lets you size: the
## constructor parameters it was placed with, under the same keys the
## save file carries (Plant._params_for), so an edit survives a reload.
## min/max are the game's sane range, not physics. A type with
## constructor params and no row here cannot be resized in play.
const CONFIG := {
	"tank": [
		{"key": "height_m", "label": "Height", "unit": "m", "min": 0.5, "max": 12.0, "step": 0.1},
		{"key": "diameter_m", "label": "Diameter", "unit": "m", "min": 0.4, "max": 6.0, "step": 0.1},
		{"key": "nozzle_cv_lps", "label": "Nozzle Cv", "unit": "L/s at 1 bar", "min": 1.0, "max": 500.0, "step": 1.0},
	],
	"pump": [
		{"key": "rated_lps", "label": "Rated flow", "unit": "L/s", "min": 0.1, "max": 200.0, "step": 0.1},
		{"key": "head_m", "label": "Shutoff head", "unit": "m", "min": 1.0, "max": 150.0, "step": 1.0},
	],
	"float_switch": [
		{"key": "low_l", "label": "Trips low at", "unit": "L", "min": 0.0, "max": 100000.0, "step": 1.0},
		{"key": "high_l", "label": "Trips high at", "unit": "L", "min": 0.0, "max": 100000.0, "step": 1.0},
	],
	"gauge_level": [
		{"key": "liters_per_meter", "label": "Range", "unit": "L per m", "min": 1.0, "max": 100000.0, "step": 1.0},
	],
	"gauge_flow": [
		{"key": "meter_k", "label": "Element loss", "unit": "Pa per (L/s)²", "min": 1.0, "max": 100000.0, "step": 10.0},
	],
	"gauge_conc": [
		{"key": "species", "label": "Species", "options": "species"},
	],
	"column": [
		{"key": "charge_l", "label": "Charge", "unit": "L", "min": 10.0, "max": 20000.0, "step": 10.0},
		{"key": "max_duty_kw", "label": "Reboiler duty", "unit": "kW", "min": 1.0, "max": 1000.0, "step": 1.0},
	],
	"valve": [
		{"key": "cv_lps", "label": "Cv", "unit": "L/s at 1 bar", "min": 0.1, "max": 500.0, "step": 0.1},
		{"key": "tau_s", "label": "Actuator time constant", "unit": "s", "min": 0.1, "max": 60.0, "step": 0.1},
	],
	"block_valve": [
		{"key": "cv_lps", "label": "Cv", "unit": "L/s at 1 bar", "min": 0.1, "max": 500.0, "step": 0.1},
		{"key": "stroke_s", "label": "Stroke time", "unit": "s", "min": 0.5, "max": 60.0, "step": 0.5},
	],
	"controller": [
		{"key": "sp", "label": "Setpoint", "unit": "", "min": -1000000.0, "max": 1000000.0, "step": 0.1},
		{"key": "kp", "label": "Gain Kp", "unit": "", "min": -1000.0, "max": 1000.0, "step": 0.01},
		{"key": "ki", "label": "Integral Ki", "unit": "1/s", "min": -1000.0, "max": 1000.0, "step": 0.001},
		{"key": "kd", "label": "Derivative Kd", "unit": "s", "min": -1000.0, "max": 1000.0, "step": 0.01},
		{"key": "out_min", "label": "Output low", "unit": "", "min": -1000000.0, "max": 1000000.0, "step": 0.1},
		{"key": "out_max", "label": "Output high", "unit": "", "min": -1000000.0, "max": 1000000.0, "step": 0.1},
	],
	"drain": [
		{"key": "rate_lps", "label": "Cv to sewer", "unit": "L/s at 1 bar", "min": 0.1, "max": 500.0, "step": 0.1},
	],
	"reactor": [
		{"key": "capacity_l", "label": "Capacity", "unit": "L", "min": 100.0, "max": 50000.0, "step": 10.0},
		{"key": "height_m", "label": "Height", "unit": "m", "min": 0.5, "max": 8.0, "step": 0.1},
		{"key": "rate_lps", "label": "Rated throughput", "unit": "L/s", "min": 0.1, "max": 100.0, "step": 0.1},
	],
	"centrifuge": [
		{"key": "rate_lps", "label": "Rated feed", "unit": "L/s", "min": 0.1, "max": 100.0, "step": 0.1},
	],
	"hx": [
		{"key": "max_duty_kw", "label": "Maximum duty", "unit": "kW", "min": 1.0, "max": 5000.0, "step": 1.0},
	],
	"steamgen": [
		{"key": "rated_kgps", "label": "Rated steam", "unit": "kg/s", "min": 0.01, "max": 20.0, "step": 0.01},
	],
	"source": [
		{"key": "species", "label": "Species", "options": "species"},
		{"key": "pressure_kpa", "label": "Header pressure", "unit": "kPa", "min": 0.0, "max": 2000.0, "step": 10.0},
		{"key": "temp_c", "label": "Temperature", "unit": "°C", "min": -20.0, "max": 200.0, "step": 1.0},
	],
	"crystallizer": [
		{"key": "capacity_l", "label": "Capacity", "unit": "L", "min": 100.0, "max": 50000.0, "step": 10.0},
		{"key": "height_m", "label": "Height", "unit": "m", "min": 0.5, "max": 8.0, "step": 0.1},
	],
	"dryer": [
		{"key": "rate_lps", "label": "Rated feed", "unit": "L/s", "min": 0.1, "max": 100.0, "step": 0.1},
	],
	"still": [
		{"key": "rate_lps", "label": "Boilup", "unit": "L/s", "min": 0.1, "max": 100.0, "step": 0.1},
		{"key": "cut_c", "label": "Cut temperature", "unit": "°C", "min": 20.0, "max": 250.0, "step": 1.0},
		{"key": "sharpness", "label": "Cut sharpness", "unit": "", "min": 0.1, "max": 50.0, "step": 0.1},
	],
}
