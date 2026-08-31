class_name PlantFactory
## One place that knows how to make each equipment type: sim record,
## view, placement footprint, and where its port markers sit. Both the
## commissioned starting plant and player placement go through here, so
## save/load can rebuild anything.

const CATALOG: Array[Dictionary] = [
	{"type": "tank", "label": "Tank 100 L"},
	{"type": "pump", "label": "Pump 4 L/s"},
	{"type": "reactor", "label": "Stirred reactor"},
	{"type": "centrifuge", "label": "Centrifuge"},
	{"type": "hx", "label": "Heat exchanger"},
	{"type": "steamgen", "label": "Steam generator"},
	{"type": "column", "label": "Distillation column"},
	{"type": "vialfill", "label": "Vial filler (isolator)"},
]

const CATALOG_UTILITIES: Array[Dictionary] = [
	{"type": "source", "label": "Supply header"},
	{"type": "drain", "label": "Drain / sewer"},
	{"type": "vaclock", "label": "Vacuum lock"},
]

const CATALOG_INSTRUMENTS: Array[Dictionary] = [
	{"type": "gauge_level", "label": "Level gauge"},
	{"type": "gauge_flow", "label": "Flow gauge"},
	{"type": "gauge_dp", "label": "DP gauge"},
	{"type": "gauge_press", "label": "Pressure gauge"},
	{"type": "controller", "label": "PID controller"},
]

const CATALOG_CONTROL: Array[Dictionary] = [
	{"type": "valve", "label": "Control valve"},
	{"type": "relay", "label": "Relay cabinet"},
	{"type": "cabinet", "label": "Control cabinet"},
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
	"controller": Vector3(0.5, 1.9, 0.5),
	"cabinet": Vector3(1.4, 2.1, 0.75),
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
}
const Y_OFFSETS := {
	"tank": 0.0, "pump": 0.0, "relay": 1.5,
	"gauge_level": 0.0, "gauge_flow": 0.0, "gauge_dp": 0.0,
	"gauge_press": 0.0, "column": 0.0,
	"float_switch": 0.0, "air_cascade": 0.0,
	"valve": 0.0, "controller": 0.0, "cabinet": 0.0,
	"mains": 0.0, "psu": 0.0, "source": 0.0, "drain": 0.0,
	"reactor": 0.0, "centrifuge": 0.0, "hx": 0.0, "steamgen": 0.0,
	"vaclock": 0.0, "vialfill": 0.0,
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
	"gauge_flow": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_dp": {
		"process_a": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"process_b": {"pos": Vector3(0, 0.45, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"gauge_press": {
		"process": {"pos": Vector3(0, 0.25, 0.04), "dir": Vector3.BACK},
		"signal": {"pos": Vector3(0, 1.32, -0.04), "dir": Vector3.FORWARD}},
	"valve": {
		"inlet": {"pos": Vector3(-0.31, 0.32, 0), "dir": Vector3.LEFT},
		"outlet": {"pos": Vector3(0.31, 0.32, 0), "dir": Vector3.RIGHT},
		"cmd": {"pos": Vector3(0, 0.98, 0.22), "dir": Vector3.BACK}},
	"source": {"outlet": {"pos": Vector3(0.5, 1.55, 0), "dir": Vector3.RIGHT}},
	"drain": {
		"inlet": {"pos": Vector3(0.46, 0.52, 0), "dir": Vector3.RIGHT},
		"flow_in": {"pos": Vector3(-0.46, 0.52, 0), "dir": Vector3.LEFT}},
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
		"purity_in": {"pos": Vector3(-0.48, 0.95, 0), "dir": Vector3.LEFT},
		"power": {"pos": Vector3(0.16, 1.62, 0.14), "dir": Vector3.BACK},
		"product": {"pos": Vector3(0.49, 0.65, 0), "dir": Vector3.RIGHT},
		"waste": {"pos": Vector3(-0.49, 0.55, 0), "dir": Vector3.LEFT}},
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

# Facade flow ports: one player-visible pipe connection ("outlet" to
# "inlet") that the plant expands into the availability + metered-draw
# kernel wire pair. The player never touches "draw" directly.
const FLOW_OUTLETS := {
	"tank": {"outlet": {"avail": "level", "draw_in": "draw"}},
	"source": {"outlet": {"avail": "supply", "draw_in": "draw"}},
	"reactor": {"outlet": {"avail": "level", "draw_in": "draw"}},
}
const FLOW_INLETS := {
	"pump": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
	"valve": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
	"drain": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
	"steamgen": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
	"centrifuge": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
	"vialfill": {"inlet": {"avail_in": "inlet", "draw_out": "draw"}},
}


static func flow_outlet_spec(type_id: String, port: String) -> Dictionary:
	return (FLOW_OUTLETS.get(type_id, {}) as Dictionary).get(port, {})


static func flow_inlet_spec(type_id: String, port: String) -> Dictionary:
	return (FLOW_INLETS.get(type_id, {}) as Dictionary).get(port, {})


const KIND_COLORS := {
	SimTypes.PortKind.SIGNAL_DISCRETE: Color(0.11, 0.69, 0.48),
	SimTypes.PortKind.SIGNAL_ANALOG: Color(0.92, 0.60, 0.10),
	SimTypes.PortKind.PROCESS_FLOW: Color(0.16, 0.47, 0.84),
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
				params.get("height_m", 0.0), params.get("diameter_m", 0.0)))
		"pump":
			return sim.add(SimPump.new(name_, params.get("rated_lps", 4.0)))
		"relay":
			return sim.add(SimRelay.new(name_))
		"float_switch":
			return sim.add(SimFloatSwitch.new(name_,
				params.get("low_l", 40.0), params.get("high_l", 80.0)))
		"gauge_level":
			return sim.add(SimGauge.new(name_, "level_kpa",
				params.get("liters_per_meter", 45.45)))
		"gauge_flow":
			return sim.add(SimGauge.new(name_, "flow"))
		"gauge_dp":
			return sim.add(SimGauge.new(name_, "dp_pa"))
		"gauge_press":
			return sim.add(SimGauge.new(name_, "press_kpa"))
		"column":
			return sim.add(SimColumn.new(name_,
				params.get("charge_l", 60.0), params.get("max_duty_kw", 100.0)))
		"air_cascade":
			return sim.add(SimAirCascade.new(name_, AsepticSuite.ROOMS, AsepticSuite.DOORS))
		"valve":
			return sim.add(SimControlValve.new(name_,
				params.get("cv_lps", 6.0), params.get("tau_s", 1.0)))
		"controller":
			return sim.add(SimPID.new(name_,
				params.get("kp", 8.0), params.get("ki", 1.5), params.get("kd", 0.0),
				params.get("sp", 15.0)))
		"plc":
			return sim.add(SimPLC.new(name_,
				params.get("di", 8), params.get("do", 8),
				params.get("ai", 4), params.get("ao", 4)))
		"terminal":
			return sim.add(SimTerminal.new(name_, params.get("kind", "discrete")))
		"mains":
			return sim.add(SimMainsFeed.new(name_, params.get("spec", "480VAC")))
		"psu":
			return sim.add(SimPowerSupply.new(name_))
		"source":
			return sim.add(SimSource.new(name_))
		"drain":
			return sim.add(SimDrain.new(name_, params.get("rate_lps", 1.0)))
		"reactor":
			return sim.add(SimReactor.new(name_,
				params.get("capacity_l", 4000.0), params.get("rate_lps", 6.0)))
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
		"gauge_level", "gauge_flow", "gauge_dp", "gauge_press":
			view = GaugeView.new()
		"column":
			view = ColumnView.new()
		"valve":
			view = ControlValveView.new()
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
		"air_cascade":
			view = AsepticSuite.new()
	if view == null:
		push_error("unknown equipment type '%s'" % type_id)
		return null
	view.set_meta("type_id", type_id)
	view.set_meta("record_name", record.comp_name)
	return view


## Call after the view is in the tree and set up: builds the typed port
## markers connect mode clicks on (collision layer 2). Markers are
## keyed "record:port" and MERGED into the view's existing set, so one
## view (a cabinet) can carry markers for several records (its
## terminals). anchors_override positions ports the type table can't.
static func attach_port_markers(view: Node3D, record: SimComponent, type_id: String,
		anchors_override: Dictionary = {}) -> void:
	var anchors: Dictionary = PORT_ANCHORS.get(type_id, {})
	var markers: Dictionary = view.get_meta("port_markers", {})
	for port_name: String in record.inputs:
		if port_name == "draw":
			continue  # the facade wires draw automatically
		var kind: SimTypes.PortKind = (record.inputs[port_name] as SimInputPort).kind
		if not flow_inlet_spec(type_id, port_name).is_empty():
			kind = SimTypes.PortKind.PROCESS_FLOW  # it's a pipe stub, draw it blue
		var raw: Variant = anchors_override.get(port_name,
			anchors.get(port_name, Vector3(0, 0.5, 0)))
		markers["%s:%s" % [record.comp_name, port_name]] = \
			make_marker(view, record.comp_name, port_name, kind,
				_anchor_pos(raw), true, _anchor_dir(raw))
	for port_name: String in record.outputs:
		if port_name == "draw":
			continue
		var raw: Variant = anchors_override.get(port_name,
			anchors.get(port_name, Vector3(0, 0.8, 0)))
		markers["%s:%s" % [record.comp_name, port_name]] = \
			make_marker(view, record.comp_name, port_name,
				(record.outputs[port_name] as SimOutputPort).kind,
				_anchor_pos(raw), false, _anchor_dir(raw))
	# Facade outlets (tank/source) are not kernel ports; give them a
	# marker of their own unless the view builds custom nozzles.
	for ui_port: String in FLOW_OUTLETS.get(type_id, {}):
		if not anchors.has(ui_port) and not anchors_override.has(ui_port):
			continue
		var raw: Variant = anchors_override.get(ui_port, anchors.get(ui_port))
		markers["%s:%s" % [record.comp_name, ui_port]] = \
			make_marker(view, record.comp_name, ui_port,
				SimTypes.PortKind.PROCESS_FLOW, _anchor_pos(raw), false, _anchor_dir(raw))
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
	var is_pipe := kind == SimTypes.PortKind.PROCESS_FLOW \
		or kind == SimTypes.PortKind.PROCESS_LEVEL \
		or kind == SimTypes.PortKind.PROCESS_PRESSURE
	if is_pipe:
		ViewUtil.box(body, Vector3(0.06, 0.15, 0.15), Vector3(-0.02, 0, 0), steel)
		var neck_r := 0.05 if kind == SimTypes.PortKind.PROCESS_FLOW else 0.032
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
