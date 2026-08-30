class_name Plant
extends Node3D
## Owns the sim graph and the fixed-rate tick; child views only render.
## All equipment — the commissioned starting loop and everything the
## player places — goes through PlantFactory, so save/load can rebuild
## the entire graph from a file.

const SIM_DT := 0.05  # 20 Hz, decoupled from frame rate
const SAVE_VERSION := 3

var save_path: String = "user://save.json"

var sim: Simulation
var historian: SimHistorian
var hmi_view: HmiView

# Convenience refs to the commissioned loop (refreshed after load).
var tank: SimTank
var switch: SimFloatSwitch
var relay: SimRelay
var pump: SimPump

var views: Dictionary = {}         # record name -> Node3D view
var equip_types: Dictionary = {}   # record name -> type_id
var protected: Dictionary = {}     # record name -> true (not deletable)
var _wire_visuals: Array[Dictionary] = []   # {node, a, b}

var _accumulator: float = 0.0


func _ready() -> void:
	_new_graph()
	_self_check()
	_build_initial_plant()
	_build_hmi()
	if DisplayServer.get_name() == "headless":
		_exercise_build_api()


## Headless smoke runs can't press B/C/X, so exercise the build API
## directly: place, connect, mis-wire, remove, save/load round-trip.
func _exercise_build_api() -> void:
	var problems: Array[String] = []
	var gauge := place_new("gauge_level", _world(Vector3(5.0, 0.0, -1.0)), 0.0)
	if gauge == null:
		problems.append("place gauge failed")
	elif connect_equipment("supply_tank", "level", gauge.comp_name, "process",
			[Vector3(4.0, 0.35, -1.5)]) != "":
		problems.append("gauge connect refused")
	if connect_equipment(gauge.comp_name, "signal", "fill_pump", "run") == "":
		problems.append("kind mismatch was NOT refused")
	for _i in 40:
		sim.tick()
	var reading := (gauge as SimGauge).reading
	if reading < 10.0 or reading > 20.0:
		problems.append("gauge reading %.2f kPa outside expected range" % reading)
	var pump2 := place_new("pump", _world(Vector3(6.0, 0.0, -1.0)), 0.0)
	if pump2 == null or not remove_equipment(pump2.comp_name):
		problems.append("place/remove pump failed")
	if remove_equipment("supply_tank"):
		problems.append("protected equipment was removable")
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
	if problems.is_empty():
		print("[flowstate] build-api exercise OK — gauge %.1f kPa, %d components, %d wires"
			% [reading, sim.components.size(), sim.wires.size()])
	else:
		push_warning("[flowstate] build-api exercise FAILED: " + "; ".join(problems))


func _physics_process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= SIM_DT:
		sim.tick()
		_accumulator -= SIM_DT


func _new_graph() -> void:
	sim = Simulation.new(SIM_DT)
	historian = sim.attach_historian(SimHistorian.new())


## ---- equipment lifecycle ------------------------------------------------

func place(type_id: String, name_: String, params: Dictionary,
		world_pos: Vector3, rot_y: float, is_protected: bool) -> SimComponent:
	var record := PlantFactory.make_record(sim, type_id, name_, params)
	if record == null:
		return null
	sim.register_with_historian(record)
	var extra: SimComponent = switch if (type_id == "tank" and is_protected) else null
	var view := PlantFactory.make_view(type_id, record, extra)
	view.position = to_local(world_pos) + Vector3(0, PlantFactory.Y_OFFSETS.get(type_id, 0.0), 0)
	view.rotation.y = rot_y
	add_child(view)
	match type_id:
		"tank":
			(view as TankView).setup(record as SimTank, extra as SimFloatSwitch)
		"pump":
			(view as PumpView).setup(record as SimPump)
		"relay":
			(view as RelayView).setup(record as SimRelay)
		"float_switch":
			(view as FloatSwitchView).setup(record as SimFloatSwitch)
		"gauge_level", "gauge_flow":
			(view as GaugeView).setup(record as SimGauge)
	PlantFactory.attach_port_markers(view, record, type_id)
	views[record.comp_name] = view
	equip_types[record.comp_name] = type_id
	if is_protected:
		protected[record.comp_name] = true
	return record


func place_new(type_id: String, world_pos: Vector3, rot_y: float) -> SimComponent:
	return place(type_id, sim.unique_name(type_id), {}, world_pos, rot_y, false)


func remove_equipment(name_: String) -> bool:
	if protected.has(name_) or not views.has(name_):
		return false
	sim.remove_component(name_)
	var keep: Array[Dictionary] = []
	for visual in _wire_visuals:
		if visual["a"] == name_ or visual["b"] == name_:
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
func connect_equipment(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array = []) -> String:
	var src := sim.get_component(src_name)
	var dst := sim.get_component(dst_name)
	if src == null or dst == null:
		return "component missing"
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
	_wire_visual(src_name, src_port, dst_name, dst_port, waypoints)
	return ""


func _wire_visual(src_name: String, src_port: String,
		dst_name: String, dst_port: String, waypoints: Array) -> void:
	var from := _marker_pos(src_name, src_port)
	var to := _marker_pos(dst_name, dst_port)
	var record := sim.get_component(src_name)
	var port: SimOutputPort = record.outputs[src_port]
	var is_process := port.kind == SimTypes.PortKind.PROCESS_FLOW \
		or port.kind == SimTypes.PortKind.PROCESS_LEVEL
	var color: Color = PlantFactory.KIND_COLORS[port.kind]
	var sparse: Array = [from]
	sparse.append_array(waypoints)
	sparse.append(to)
	var pipe := PipeView.new()
	add_child(pipe)
	pipe.setup(PipeRoute.orthogonalize(sparse), func() -> float: return port.value,
		color, 0.07 if is_process else 0.025)
	_wire_visuals.append({
		"node": pipe, "a": src_name, "a_port": src_port,
		"b": dst_name, "b_port": dst_port, "waypoints": waypoints,
	})


func _marker_pos(record_name: String, port_name: String) -> Vector3:
	var view: Node3D = views.get(record_name)
	if view == null:
		return Vector3.ZERO
	var markers: Dictionary = view.get_meta("port_markers", {})
	var marker: Node3D = markers.get(port_name)
	return to_local(marker.global_position) if marker != null else view.position


## ---- the commissioned starting loop -------------------------------------

func _build_initial_plant() -> void:
	# Switch first: the tank view draws its trip rings from it.
	switch = place("float_switch", "level_switch", {"low_l": 40.0, "high_l": 80.0},
		_world(Vector3(1.55, 1.32, -2.0)), 0.0, true) as SimFloatSwitch
	tank = place("tank", "supply_tank",
		{"capacity_l": 100.0, "level_l": 70.0, "drain_lps": 1.5},
		_world(Vector3(2.5, 0, -2.0)), 0.0, true) as SimTank
	relay = place("relay", "pump_relay", {},
		_world(Vector3(-2.5, 1.5, -4.74)) - Vector3(0, PlantFactory.Y_OFFSETS["relay"], 0),
		0.0, true) as SimRelay
	pump = place("pump", "fill_pump", {"rated_lps": 4.0},
		_world(Vector3(-0.5, 0, -2.6)), 0.0, true) as SimPump
	connect_equipment("supply_tank", "level", "level_switch", "level")
	connect_equipment("level_switch", "contact", "pump_relay", "coil")
	connect_equipment("pump_relay", "contact", "fill_pump", "run")
	connect_equipment("fill_pump", "flow", "supply_tank", "in_flow")


func _world(local: Vector3) -> Vector3:
	return to_global(local)


func _build_hmi() -> void:
	hmi_view = HmiView.new()
	hmi_view.position = Vector3(-4.6, 1.6, -4.75)
	add_child(hmi_view)
	hmi_view.setup(historian, tank, switch, relay, pump)


func _self_check() -> void:
	var check := Simulation.new(SIM_DT)
	var c_tank := check.add(SimTank.new("t", 100.0, 70.0, 1.5)) as SimTank
	var c_switch := check.add(SimFloatSwitch.new("s", 40.0, 80.0)) as SimFloatSwitch
	var c_relay := check.add(SimRelay.new("r")) as SimRelay
	var c_pump := check.add(SimPump.new("p", 4.0)) as SimPump
	check.connect_ports(c_tank, "level", c_switch, "level")
	check.connect_ports(c_switch, "contact", c_relay, "coil")
	check.connect_ports(c_relay, "contact", c_pump, "run")
	check.connect_ports(c_pump, "flow", c_tank, "in_flow")
	check.run_for(600.0)
	var ok := c_tank.level_l >= 38.0 and c_tank.level_l <= 82.0 \
		and c_tank.overflowed_l == 0.0 and c_relay.cycles < 15
	if ok:
		print("[flowstate] kernel self-check OK — 600 s: level %.1f L, %d relay cycles"
			% [c_tank.level_l, c_relay.cycles])
	else:
		push_warning("[flowstate] kernel self-check FAILED — level %.1f L, overflow %.1f L, %d cycles"
			% [c_tank.level_l, c_tank.overflowed_l, c_relay.cycles])


## ---- save / load ---------------------------------------------------------

func save_game() -> bool:
	var comps: Array[Dictionary] = []
	for name_: String in views:
		var record := sim.get_component(name_)
		var view: Node3D = views[name_]
		comps.append({
			"type": equip_types[name_],
			"name": name_,
			"state": record.state_dict(),
			"params": _params_for(record),
			"pos": [view.global_position.x, view.global_position.y
				- PlantFactory.Y_OFFSETS.get(equip_types[name_], 0.0), view.global_position.z],
			"rot_y": view.rotation.y,
			"protected": protected.has(name_),
		})
	var wire_list: Array = []
	for visual in _wire_visuals:
		var path_out: Array = []
		for point: Vector3 in visual["waypoints"]:
			path_out.append([point.x, point.y, point.z])
		wire_list.append({
			"src": visual["a"], "src_port": visual["a_port"],
			"dst": visual["b"], "dst_port": visual["b_port"],
			"waypoints": path_out,
		})
	var payload := {
		"version": SAVE_VERSION, "time": sim.time,
		"components": comps, "wires": wire_list,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	return true


func _params_for(record: SimComponent) -> Dictionary:
	if record is SimTank:
		return {"capacity_l": (record as SimTank).capacity_l}
	if record is SimPump:
		return {"rated_lps": (record as SimPump).rated_lps}
	if record is SimFloatSwitch:
		var fs := record as SimFloatSwitch
		return {"low_l": fs.low_l, "high_l": fs.high_l}
	if record is SimGauge:
		return {"liters_per_meter": (record as SimGauge).liters_per_meter}
	return {}


func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("version", 0)) != SAVE_VERSION:
		return false
	var payload := parsed as Dictionary

	for name_: String in views:
		(views[name_] as Node).queue_free()
	for visual in _wire_visuals:
		(visual["node"] as Node).queue_free()
	views.clear()
	equip_types.clear()
	protected.clear()
	_wire_visuals.clear()
	_new_graph()

	for entry: Dictionary in payload["components"]:
		var pos_arr: Array = entry["pos"]
		var record := place(entry["type"], entry["name"], entry.get("params", {}),
			Vector3(pos_arr[0], pos_arr[1], pos_arr[2]),
			float(entry.get("rot_y", 0.0)), bool(entry.get("protected", false)))
		if record != null:
			record.apply_state(entry.get("state", {}))
	for wire_entry: Dictionary in payload["wires"]:
		var waypoints: Array = []
		for point: Array in wire_entry.get("waypoints", []):
			waypoints.append(Vector3(point[0], point[1], point[2]))
		connect_equipment(wire_entry["src"], wire_entry["src_port"],
			wire_entry["dst"], wire_entry["dst_port"], waypoints)
	sim.time = float(payload.get("time", 0.0))

	tank = sim.get_component("supply_tank") as SimTank
	switch = sim.get_component("level_switch") as SimFloatSwitch
	relay = sim.get_component("pump_relay") as SimRelay
	pump = sim.get_component("fill_pump") as SimPump
	if hmi_view != null and tank != null:
		hmi_view.panel.setup(historian, tank, switch, relay, pump)
	return true
